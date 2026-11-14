#!/usr/bin/env python3
"""Inspecter un .app compilé, sans collecter de données ou d’identifiants Apple."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

app, output = Path(sys.argv[1]), Path(sys.argv[2])
if not app.is_dir() or app.suffix != '.app':
    raise SystemExit('Le premier paramètre doit être un véritable dossier .app compilé.')

def describe(bundle):
    with (bundle / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    executable = bundle / info['CFBundleExecutable']
    if not executable.is_file():
        raise SystemExit('Exécutable manquant dans ' + str(bundle))
    result = subprocess.run(['xcrun', 'vtool', '-show-build', str(executable)], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr)
    if 'platform IOS' not in result.stdout or 'IOSSIMULATOR' in result.stdout:
        raise SystemExit('Ce bundle ne cible pas un appareil iOS physique : ' + str(bundle))
    return {'path': str(bundle.relative_to(app.parent)), 'bundleID': info['CFBundleIdentifier'],
            'executable': info['CFBundleExecutable'], 'minimumOS': info.get('MinimumOSVersion'),
            'platformInspection': result.stdout, 'provisionProfilePresent': (bundle / 'embedded.mobileprovision').exists()}

report = {'kind': 'inventaire-du-bundle-compilé-non-signé', 'app': describe(app),
          'extensions': [describe(item) for item in sorted((app / 'PlugIns').glob('*.appex'))],
          'tree': ['Cadence.app/'] + ['  ' + str(path.relative_to(app)) + ('/' if path.is_dir() else '')
                                    for path in sorted(app.rglob('*'))
                                    if len(path.relative_to(app).parts) <= 3],
          'hardwareValidation': 'NON EFFECTUÉE'}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
output.with_suffix('.txt').write_text('\n'.join(report['tree']), encoding='utf-8')
print(f"Bundle physique inspecté : {len(report['extensions'])} extension(s). Aucune signature validée.")
