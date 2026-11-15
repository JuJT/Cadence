import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from inspect_ipa import inspect, signed_entitlements, keychain_sharing_check, selected_entitlements
from prepare_signing_intent import prepare
from collect_test_screenshots import collect


def macho(entitlements=None):
    if entitlements is None:
        return struct.pack('<IIIIIIII', 0xFEEDFACF, 0, 0, 2, 0, 0, 0, 0)
    xml = plistlib.dumps(entitlements)
    inner = struct.pack('>II', 0xFADE7171, len(xml) + 8) + xml
    blob = struct.pack('>III', 0xFADE0CC0, 20 + len(inner), 1) + struct.pack('>II', 5, 20) + inner
    header = struct.pack('<IIIIIIII', 0xFEEDFACF, 0, 0, 2, 1, 16, 0, 0)
    return header + struct.pack('<IIII', 0x1D, 16, 48, len(blob)) + blob


class DiagnosticTests(unittest.TestCase):
    def make_ipa(self, path, entitlements=None, profile=None, extension=False):
        with zipfile.ZipFile(path, 'w') as archive:
            roots = ['Payload/Cadence.app']
            if extension:
                roots.append('Payload/Cadence.app/PlugIns/CadenceWidgets.appex')
            for root in roots:
                archive.writestr(root + '/Info.plist', plistlib.dumps({
                    'CFBundleExecutable': 'Cadence',
                    'CFBundleIdentifier': 'com.cadence.study' + ('.widgets' if '.appex' in root else '')
                }, fmt=plistlib.FMT_BINARY))
                archive.writestr(root + '/Cadence', macho(entitlements))
                if profile is not None:
                    archive.writestr(root + '/embedded.mobileprovision', b'CMS-prefix' + plistlib.dumps(profile) + b'CMS-signature')

    def test_unsigned_extension_count_and_no_signing_claim(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic.ipa'
            self.make_ipa(path, extension=True)
            result = inspect(path)
        self.assertEqual(result['extensionCount'], 1)
        self.assertFalse(result['signatureCryptographicallyVerified'])
        self.assertTrue(all('Profil absent' in item['warnings'][0] for item in result['bundles']))

    def test_entitlements_extracted_and_profile_private_values_excluded(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic.ipa'
            self.make_ipa(path, entitlements={'com.apple.security.application-groups': ['group.actual']},
                          profile={'AppleID': 'PRIVATE-DO-NOT-PRINT', 'ProvisionedDevices': ['PRIVATE-DEVICE'],
                                   'Entitlements': {'com.apple.security.application-groups': ['group.expected']}})
            result = inspect(path)
        self.assertNotIn('PRIVATE-', str(result))
        self.assertEqual(result['bundles'][0]['signedExecutableEntitlements']['com.apple.security.application-groups'], ['group.actual'])
        self.assertTrue(any('différents' in warning for warning in result['bundles'][0]['warnings']))

    def test_non_macho_never_claims_empty_valid_signature(self):
        self.assertIsNone(signed_entitlements(b'not-an-executable'))

    def test_keychain_template_is_preserved_but_never_installable(self):
        source = plistlib.dumps({'keychain-access-groups': ['$(AppIdentifierPrefix)com.cadence.study.widget-summary']})
        template = prepare(source)
        check = keychain_sharing_check([template, template], [None, None])
        self.assertTrue(check['commonCadenceGroupInExecutableSignatures'])
        self.assertTrue(check['templateMetadataOnly'])
        self.assertFalse(check['readyForPhysicalReadTest'])

    def test_re_signed_common_group_requires_every_profile_permission(self):
        entitlements = {'keychain-access-groups': ['PRIVATEID1.com.cadence.study.widget-summary']}
        permitted = {'keychain-access-groups': ['PRIVATEID1.*']}
        denied = {'keychain-access-groups': ['OTHERTEAM.*']}
        self.assertTrue(keychain_sharing_check([entitlements, entitlements], [permitted, permitted])['readyForPhysicalReadTest'])
        self.assertFalse(keychain_sharing_check([entitlements, entitlements], [permitted, denied])['readyForPhysicalReadTest'])
        self.assertFalse(keychain_sharing_check([entitlements, {'keychain-access-groups': ['OTHERTEAM.com.cadence.study.widget-summary']}], [permitted, permitted])['readyForPhysicalReadTest'])
        self.assertNotIn('PRIVATEID1', str(selected_entitlements(entitlements)))


if __name__ == '__main__':
    unittest.main()
