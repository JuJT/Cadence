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
from fnmatch import fnmatchcase
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
    selected = {key: values.get(key) for key in (
        'com.apple.security.application-groups', 'get-task-allow') if key in values}
    if 'application-identifier' in values:
        selected['application-identifier'] = 'présent (identifiant masqué)'
    if 'keychain-access-groups' in values:
        selected['keychain-access-groups'] = [
            'groupe de résumé Cadence' if item.endswith('.com.cadence.study.widget-summary')
            else 'autre groupe (identifiant masqué)' for item in values['keychain-access-groups']]
    return selected


def keychain_sharing_check(signed_values, profile_values):
    """Compare actual signature/profile groups without printing identities or profiles."""
    groups = [{item for item in (values or {}).get('keychain-access-groups', [])
               if item.endswith('.com.cadence.study.widget-summary')} for values in signed_values]
    common = set.intersection(*groups) if groups else set()
    template = any(item.startswith('UNSIGNED00.') for group in groups for item in group)
    allowed = bool(common) and len(profile_values) == len(groups) and any(
        all(any(fnmatchcase(item, pattern) for pattern in (profile or {}).get('keychain-access-groups', []))
            for profile in profile_values) for item in common)
    return {'extensionAndAppPresent': len(groups) >= 2,
            'commonCadenceGroupInExecutableSignatures': bool(common) and len(groups) >= 2,
            'templateMetadataOnly': template,
            'commonGroupPermittedByEveryProfile': allowed,
            'readyForPhysicalReadTest': len(groups) >= 2 and bool(common) and allowed and not template,
            'note': 'Le test physique doit confirmer la lecture du résumé. Une signature ad-hoc ne permet pas l’installation.'}

def auth_isolation_check(bundle_id, app_values, extension_values, app_profile=None):
    """Describe private auth isolation without revealing group names or identities."""
    app_values = app_values or {}
    app_groups = app_values.get('keychain-access-groups', [])
    private_groups = {item for item in app_groups if isinstance(item, str) and
                      item.endswith('.' + bundle_id) and '*' not in item}
    application_id = app_values.get('application-identifier')
    if isinstance(application_id, str) and application_id.endswith('.' + bundle_id) and '*' not in application_id:
        private_groups.add(application_id)
    extension_readable = all(value is not None for value in extension_values)
    extension_claims = []
    for values in extension_values:
        extension_claims.extend((values or {}).get('keychain-access-groups', []))
        if isinstance((values or {}).get('application-identifier'), str):
            extension_claims.append(values['application-identifier'])
    extension_has_private = any(fnmatchcase(group, claim) for group in private_groups for claim in extension_claims)
    isolated = bool(private_groups) and extension_readable and not extension_has_private
    template = any(group.startswith('UNSIGNED00.') for group in private_groups)
    profile_claims = (app_profile or {}).get('keychain-access-groups', [])
    if isinstance((app_profile or {}).get('application-identifier'), str):
        profile_claims = [*profile_claims, app_profile['application-identifier']]
    permitted = bool(private_groups) and any(fnmatchcase(group, claim) for group in private_groups for claim in profile_claims)
    return {'privateAppGroupPresent': bool(private_groups),
            'privateAppGroupIsDefault': bool(app_groups) and app_groups[0] in private_groups,
            'extensionEntitlementsReadable': extension_readable,
            'extensionHasAppPrivateGroup': extension_has_private,
            'isolatedInExecutableMetadata': isolated,
            'templateMetadataOnly': template,
            'privateGroupPermittedByAppProfile': permitted,
            'readyForPhysicalPrivateStorageTest': isolated and permitted and not template,
            'note': 'Métadonnées seulement ; contrôler la signature après resignature et tester le trousseau privé sur iPhone.'}


def inspect(ipa):
    with zipfile.ZipFile(ipa) as archive:
        names = set(archive.namelist())
        roots = sorted(name[:-len('/Info.plist')] for name in names if
                       name.startswith('Payload/') and name.endswith('/Info.plist') and
                       (name.count('/') == 2 or '.app/PlugIns/' in name and name.count('/') == 4))
        if not roots:
            raise ValueError('Aucun bundle app dans cet IPA.')
        bundles = []
        signature_values = []
        profile_values = []
        app_id = ''
        app_entitlements = None
        app_profile = None
        extension_entitlements = []
        for root in roots:
            info = plistlib.loads(archive.read(root + '/Info.plist'))
            executable_path = root + '/' + info['CFBundleExecutable']
            entitlement_values = signed_entitlements(archive.read(executable_path))
            profile_path = root + '/embedded.mobileprovision'
            profile = profile_contents(archive.read(profile_path)) if profile_path in names else None
            signature_values.append(entitlement_values)
            profile_values.append((profile or {}).get('Entitlements'))
            if '.appex' in root:
                extension_entitlements.append(entitlement_values)
            else:
                app_id = info.get('CFBundleIdentifier', '')
                app_entitlements = entitlement_values
                app_profile = (profile or {}).get('Entitlements')
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
                'keychainSharing': keychain_sharing_check(signature_values, profile_values),
                'authIsolation': auth_isolation_check(app_id, app_entitlements, extension_entitlements, app_profile),
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
