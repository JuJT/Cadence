import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from collect_test_screenshots import collect


class ScreenshotManifestTests(unittest.TestCase):
    def test_nested_manifest_names_preserve_exact_image_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exported = root / 'raw' / 'iphone'
            exported.mkdir(parents=True)
            (exported / 'opaque-id.png').write_bytes(b'synthetic-test-image')
            (exported / 'manifest.json').write_text(json.dumps([
                {'testIdentifier': 'Navigation', 'attachments': [
                    {'exportedFileName': 'opaque-id.png', 'suggestedHumanReadableName': 'accueil-clair.png'}]}]), encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                result = collect(root / 'raw', root / 'out', root / 'index.json')
            self.assertEqual(len(result['screenshots']), 1)
            self.assertEqual((root / 'out/iphone/accueil-clair.png').read_bytes(), b'synthetic-test-image')
            self.assertEqual(result['screenshots'][0]['label'], 'accueil-clair.png')

    def test_alternate_name_field_and_duplicate_label_do_not_overwrite_different_images(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exported = root / 'raw/ipad'
            exported.mkdir(parents=True)
            for name, value in [('one.png', b'one'), ('two.png', b'two')]:
                (exported / name).write_bytes(value)
            (exported / 'manifest.json').write_text(json.dumps({'attachments': [
                {'exportedFileName': 'one.png', 'name': 'iPad — Accueil'},
                {'exportedFileName': 'two.png', 'filename': 'iPad — Accueil'}]}), encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                result = collect(root / 'raw', root / 'out', root / 'index.json')
            self.assertEqual(len(result['screenshots']), 2)
            paths = [root / 'out' / item['output'] for item in result['screenshots']]
            self.assertEqual({path.read_bytes() for path in paths}, {b'one', b'two'})
            self.assertNotEqual(paths[0], paths[1])

    def test_missing_human_name_and_external_path_never_invent_screen_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            exported = root / 'raw/iphone'
            exported.mkdir(parents=True)
            (exported / 'uuid.png').write_bytes(b'unlabelled')
            (root / 'outside.png').write_bytes(b'outside')
            (exported / 'manifest.json').write_text(json.dumps([
                {'exportedFileName': 'uuid.png'},
                {'exportedFileName': '../../outside.png', 'name': 'accueil-clair'}]), encoding='utf-8')
            with contextlib.redirect_stdout(io.StringIO()):
                result = collect(root / 'raw', root / 'out', root / 'index.json')
            self.assertEqual(result['screenshots'], [])
            self.assertEqual(list((root / 'out').rglob('*.png')), [])
            self.assertEqual(len(result['warnings']), 2)


if __name__ == '__main__':
    unittest.main()
