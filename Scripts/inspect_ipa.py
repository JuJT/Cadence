#!/usr/bin/env python3
"""Diagnostic local d’IPA, y compris profils/entitlements intégrés après resignature.

Ce script ne vérifie pas cryptographiquement les signatures. Il ne montre ni Apple ID,
ni UUID d’appareil, ni certificat, ni profil complet. Aucun accès réseau.
"""
import argparse
import json
import plistlib
import struct
import zipfile
from pathlib import Path, PurePosixPath

def signed_entitlements(executable):
    data = executable
    if data[:4] == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', data, 4)[0]
        if count < 1:
            return None
        offset, size = struct.unpack_from('>II', data, 16)
        data = data[offset:offset + size]
    if data[:4] not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        return None
    command_count = struct.unpack_from('<I', data, 16)[0]
    position = 32 if data[:4] == b'\xcf\xfa\xed\xfe' else 28
    for _ in range(command_count):
        command, length = struct.unpack_from('<II', data, position)
        if length < 8 or position + length > len(data):
            return None
        if command == 0x1D:
            start, size = struct.unpack_from('<II', data, position + 8)
            blob = data[start:start + size]
            if len(blob) < 12:
                return None
            magic, _, count = struct.unpack_from('>III', blob)
            if magic != 0xFADE0CC0:
                return None
            for index in range(count):
                kind, location = struct.unpack_from('>II', blob, 12 + index * 8)
                if kind == 5:
                    _, length = struct.unpack_from('>II', blob, location)
                    return plistlib.loads(blob[location + 8:location + length])
            return {}
        position += length
    return {}

def profile_contents(data):
    start = data.find(b'<?xml')
    end = data.find(b'</plist>', start)
    if start < 0 or end < 0:
        return None
    return plistlib.loads(data[start:end + len(b'</plist>')])

def selected_entitlements(values):
    if values is None:
        return None
    return {key: values.get(key) for key in (
        'application-identifier', 'com.apple.security.application-groups', 'get-task-allow') if key in values}

def inspect(ipa):
    with zipfile.ZipFile(ipa) as archive:
        names = set(archive.namelist())
        roots = sorted(name[:-len('/Info.plist')] for name in names if
                       name.startswith('Payload/') and name.endswith('/Info.plist') and
                       (name.count('/') == 2 or '.app/PlugIns/' in name and name.count('/') == 4))
        if not roots:
            raise ValueError('Aucun bundle app dans cet IPA.')
        bundles = []
        for root in roots:
            info = plistlib.loads(archive.read(root + '/Info.plist'))
            executable_path = root + '/' + info['CFBundleExecutable']
            entitlement_values = signed_entitlements(archive.read(executable_path))
            profile_path = root + '/embedded.mobileprovision'
            profile = profile_contents(archive.read(profile_path)) if profile_path in names else None
            signed_groups = (entitlement_values or {}).get('com.apple.security.application-groups', [])
            provisioned_groups = (profile or {}).get('Entitlements', {}).get('com.apple.security.application-groups', [])
            warnings = []
            if not profile:
                warnings.append('Profil absent : normal pour IPA unsigned ; installation non validée.')
            if entitlement_values is None:
                warnings.append('Entitlements exécutables non lisibles par ce diagnostic ; contrôle codesign requis sur macOS.')
            if signed_groups and set(signed_groups) != set(provisioned_groups):
                warnings.append('App Groups de l’exécutable et du profil différents : ne pas attendre de partage widget fiable.')
            bundles.append({'path': root, 'bundleID': info.get('CFBundleIdentifier'),
                            'supportsLiveActivities': info.get('NSSupportsLiveActivities', False),
                            'signedExecutableEntitlements': selected_entitlements(entitlement_values),
                            'profileEntitlements': selected_entitlements((profile or {}).get('Entitlements')),
                            'profileExpiration': str((profile or {}).get('ExpirationDate', 'absent')),
                            'warnings': warnings})
        return {'ipa': Path(ipa).name, 'bundles': bundles,
                'extensionCount': sum('.appex' in bundle['path'] for bundle in bundles),
                'signatureCryptographicallyVerified': False,
                'hardwareValidation': 'NON EFFECTUÉE'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = json.dumps(inspect(args.ipa), ensure_ascii=False, indent=2)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException, struct.error) as error:
        raise SystemExit('Diagnostic impossible : ' + str(error))
    if args.output:
        args.output.write_text(result, encoding='utf-8')
    print(result)
