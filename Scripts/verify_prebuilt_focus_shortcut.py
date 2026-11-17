#!/usr/bin/env python3
"""Audit the pinned MIT-licensed, already-signed HongMix Focus shortcut.

Uses public Apple aea/aa CLIs and OpenSSL, never an iCloud login or a new signer.
Only the exact reviewed action graph is accepted; downloads are hash-pinned.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import urllib.request

COMMIT = '9547e0efb15fdcc241559db73a5f2e490d486f19'
BASE = f'https://raw.githubusercontent.com/HongMix/HongMix/{COMMIT}/'
SHORTCUT_SHA256 = '000e760f62e27eea1599f1117f58e349e97506421b19169016bade8adc7344b0'
SOURCE_SHA256 = 'a6945dd2dfcf6fd90fe1a61117a4e83f39eff82c23232930f3d8bb052be5b209'
LICENSE_SHA256 = 'a8e87a8857de045f49c0560c9c49f11f767946ade7426c18318d5f08ab0105eb'
APPLE_ROOT_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179'
NAME = 'HongMix Focus'
PREFIX = 'is.workflow.actions.'


def download(url, expected_hash):
    with urllib.request.urlopen(url, timeout=20) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError('Pinned public resource hash/size mismatch')
    return data


def signing_chain(data):
    if len(data) < 12 or data[:4] != b'AEA1':
        raise ValueError('Expected signed AEA archive')
    profile, auth_size = struct.unpack('<II', data[4:12])
    if profile != 0 or not 0 < auth_size <= 65536 or len(data) <= 12 + auth_size:
        raise ValueError('Unsupported/truncated signed shortcut envelope')
    auth = plistlib.loads(data[12:12 + auth_size])
    # Contact-only signatures include AppleIDValidationRecord and related keys.
    # The public anyone envelope instead contains the Apple signing chain alone.
    if not isinstance(auth, dict) or set(auth) != {'SigningCertificateChain'}:
        raise ValueError('Contact-restricted or unknown signing audience')
    chain = auth['SigningCertificateChain']
    if not isinstance(chain, list) or len(chain) != 3 or not all(isinstance(x, bytes) for x in chain):
        raise ValueError('Unexpected signing chain')
    if hashlib.sha256(chain[-1]).hexdigest() != APPLE_ROOT_SHA256:
        raise ValueError('Signing root differs from the pinned official Apple Root CA G3')
    return chain


def expected_actions():
    # Exact actions from the reviewed MIT source, with symbolic UUIDs. No source
    # downloaded from the network is executed to construct this expectation.
    def act(suffix, **values):
        return {'WFWorkflowActionIdentifier': PREFIX + suffix, 'WFWorkflowActionParameters': values}
    def attachment(value, name):
        return {'Value': {'Type': 'ActionOutput', 'OutputUUID': value, 'OutputName': name},
                'WFSerializationType': 'WFTextTokenAttachment'}
    input_value = {'Value': {'Type': 'ExtensionInput'}, 'WFSerializationType': 'WFTextTokenAttachment'}
    dnd = {'Identifier': 'com.apple.donotdisturb.mode.default'}
    return [
        act('detect.text', UUID='TEXT', WFInput=input_value),
        act('conditional', GroupingIdentifier='G1', WFControlFlowMode=0, WFCondition=4,
            WFConditionalActionString='on', WFInput={'Type': 'Variable', 'Variable': attachment('TEXT', 'Text')}),
        act('dnd.set', Enabled=1, FocusModes=dnd, AssertionType='Turned Off'),
        act('conditional', GroupingIdentifier='G1', WFControlFlowMode=1),
        act('conditional', GroupingIdentifier='G2', WFControlFlowMode=0, WFCondition=4,
            WFConditionalActionString='off', WFInput={'Type': 'Variable', 'Variable': attachment('TEXT', 'Text')}),
        act('dnd.set', Enabled=0, FocusModes=dnd),
        act('conditional', GroupingIdentifier='G2', WFControlFlowMode=2),
        act('conditional', GroupingIdentifier='G1', WFControlFlowMode=2),
        act('dnd.getfocus', UUID='FOCUS'),
        act('output', WFOutput={'Value': {'string': '\ufffc', 'attachmentsByRange': {
            '{0, 1}': {'Type': 'ActionOutput', 'OutputUUID': 'FOCUS', 'OutputName': 'Focus'}}},
            'WFSerializationType': 'WFTextTokenString'}),
    ]


def normalized_actions(actions):
    if not isinstance(actions, list) or len(actions) > 32:
        raise ValueError('Unexpected action list')
    ids = {}
    for item in actions:
        if not isinstance(item, dict):
            raise ValueError('Malformed action')
        values = item.get('WFWorkflowActionParameters', {})
        for key in ('UUID', 'GroupingIdentifier'):
            value = values.get(key)
            if isinstance(value, str) and value not in ids:
                ids[value] = f'ID-{len(ids)}'
    def normalize(value):
        if isinstance(value, dict):
            return {key: normalize(child) for key, child in value.items()}
        if isinstance(value, list):
            return [normalize(child) for child in value]
        return ids.get(value, value) if isinstance(value, str) else value
    return normalize(actions)


def validate_workflow(workflow):
    if not isinstance(workflow, dict):
        raise ValueError('Expected workflow dictionary')
    if normalized_actions(workflow.get('WFWorkflowActions')) != normalized_actions(expected_actions()):
        raise ValueError('Signed workflow differs from the exact reviewed Focus-only action graph')
    for key in ('WFWorkflowImportQuestions', 'WFWorkflowTypes', 'WFQuickActionSurfaces', 'WFWorkflowTriggers'):
        if workflow.get(key):
            raise ValueError('Unexpected workflow surface/trigger/import question')
    return sorted({item['WFWorkflowActionIdentifier'] for item in workflow['WFWorkflowActions']})


def command(arguments):
    result = subprocess.run(arguments, capture_output=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(Path(arguments[0]).name + ' failed: ' + result.stderr.decode(errors='replace').strip()[:500])
    return result.stdout


def verify_and_extract(data, directory):
    chain = signing_chain(data)
    # Also retrieve the root from Apple's official endpoint, independently of
    # the archive, and require byte equality to the pinned trusted root.
    root = download('https://www.apple.com/certificateauthority/AppleRootCA-G3.cer', APPLE_ROOT_SHA256)
    if chain[-1] != root:
        raise ValueError('Apple root certificate mismatch')
    for index, certificate in enumerate(chain):
        (directory / f'cert-{index}.der').write_bytes(certificate)
        command(['/usr/bin/openssl', 'x509', '-inform', 'DER', '-in', str(directory / f'cert-{index}.der'),
                 '-out', str(directory / f'cert-{index}.pem')])
    command(['/usr/bin/openssl', 'verify', '-CAfile', str(directory / 'cert-2.pem'),
             '-untrusted', str(directory / 'cert-1.pem'), str(directory / 'cert-0.pem')])
    public_pem = command(['/usr/bin/openssl', 'x509', '-inform', 'DER', '-in', str(directory / 'cert-0.der'), '-pubkey', '-noout'])
    (directory / 'public.pem').write_bytes(public_pem)
    public_der = command(['/usr/bin/openssl', 'pkey', '-pubin', '-in', str(directory / 'public.pem'), '-outform', 'DER'])
    if len(public_der) < 68 or public_der[-68:-65] != b'\x03\x42\x00' or public_der[-65] != 4:
        raise ValueError('Expected an uncompressed ECDSA P-256 public key')
    (directory / 'public.hex').write_text('hex:' + public_der[-65:].hex())
    (directory / 'signed.shortcut').write_bytes(data)
    command(['/usr/bin/aea', 'decrypt', '-i', str(directory / 'signed.shortcut'),
             '-o', str(directory / 'payload.aa'), '-sign-pub', str(directory / 'public.hex')])
    extracted = directory / 'decoded'
    extracted.mkdir()
    command(['/usr/bin/aa', 'extract', '-i', str(directory / 'payload.aa'), '-d', str(extracted)])
    files = list(extracted.rglob('*'))
    workflows = [path for path in files if path.is_file() and path.suffix == '.wflow']
    if len(workflows) != 1 or any(path.is_symlink() or not path.resolve().is_relative_to(extracted.resolve()) for path in files):
        raise ValueError('Unexpected archive layout')
    return plistlib.loads(workflows[0].read_bytes())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=Path('Resources/Shortcuts'))
    parser.add_argument('--reports', type=Path, default=Path('dist/reports'))
    args = parser.parse_args(argv)
    if sys.platform != 'darwin':
        parser.error('Apple archive verification requires macOS')
    data = download(BASE + 'Resources/HongMix%20Focus.shortcut', SHORTCUT_SHA256)
    source = download(BASE + 'scripts/make-focus-shortcut.py', SOURCE_SHA256)
    license_data = download(BASE + 'LICENSE', LICENSE_SHA256)
    with tempfile.TemporaryDirectory(prefix='cadenza-audit-focus-') as temp:
        workflow = verify_and_extract(data, Path(temp))
        action_ids = validate_workflow(workflow)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.reports.mkdir(parents=True, exist_ok=True)
    (args.output_dir / (NAME + '.shortcut')).write_bytes(data)
    (args.output_dir / 'HongMix-LICENSE.txt').write_bytes(license_data)
    (args.reports / 'focus-shortcut-source.plist').write_bytes(plistlib.dumps(workflow, sort_keys=False))
    (args.reports / 'focus-upstream-source.py').write_bytes(source)
    report = {'shortcut': NAME, 'upstreamRepository': 'https://github.com/HongMix/HongMix',
              'upstreamCommit': COMMIT, 'license': 'MIT', 'signedSHA256': SHORTCUT_SHA256,
              'upstreamSourceSHA256': SOURCE_SHA256, 'audience': 'anyone',
              'contactIdentityFieldsAbsent': True, 'appleRootPinnedAndMatchedOfficialCertificate': True,
              'certificateChainAndValidityVerified': True, 'archiveSignatureVerifiedWithAppleAEA': True,
              'exactReviewedActionGraph': True, 'actionIdentifiers': action_ids,
              'schoolOrAccountDataInDocument': False, 'runtimeOnIPhoneVerified': False,
              'note': 'Actual import trust, iPhone permissions and Focus execution remain separate device checks.'}
    (args.reports / 'focus-shortcut.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Verified pinned MIT Focus helper, Apple chain/archive signature and exact Focus-only actions; no iCloud login used.')


if __name__ == '__main__':
    main()
