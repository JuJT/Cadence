#!/usr/bin/env python3
"""Copier les captures XCTest d’après le manifeste exporté, sans déduire un écran d’un UUID."""
import argparse
import hashlib
import json
import re
import shutil
import unicodedata
from pathlib import Path

def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)

def safe_label(value):
    value = unicodedata.normalize('NFKD', Path(value).stem).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-zA-Z0-9_-]+', '-', value).strip('-').lower()[:160]

def collect(source, destination, index_path):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    copied, warnings, seen = [], [], set()
    manifests = sorted(source.rglob('*.json')) if source.exists() else []
    for manifest in manifests:
        try:
            document = json.loads(manifest.read_text(encoding='utf-8'))
        except (ValueError, OSError) as error:
            warnings.append(f'Manifeste illisible {manifest.name}: {error}')
            continue
        for record in dictionaries(document):
            exported = record.get('exportedFileName') or record.get('exportedFilename')
            if not isinstance(exported, str):
                continue
            if Path(exported).suffix.lower() not in ('.png', '.jpg', '.jpeg', '.heic'):
                continue
            candidate = (manifest.parent / exported).resolve()
            try:
                candidate.relative_to(source)
            except ValueError:
                warnings.append('Chemin de pièce jointe hors du dossier exporté ignoré.')
                continue
            if not candidate.is_file():
                matches = [path for path in manifest.parent.rglob(Path(exported).name) if path.is_file()]
                if len(matches) != 1:
                    warnings.append(f'Pièce jointe introuvable ou ambiguë: {exported}')
                    continue
                candidate = matches[0]
            label = next((record[key] for key in ('suggestedHumanReadableName', 'name', 'filename', 'fileName')
                          if isinstance(record.get(key), str) and record[key].strip()), None)
            if label is None:
                warnings.append(f'Aucun nom humain relié à {exported}; pièce jointe brute conservée.')
                continue
            slug = safe_label(label)
            if not slug:
                warnings.append(f'Nom de capture inexploitable pour {exported}.')
                continue
            relative = candidate.relative_to(source)
            group = relative.parts[0] if len(relative.parts) > 1 else 'tests'
            key = (str(candidate), label)
            if key in seen:
                continue
            seen.add(key)
            target_folder = destination / safe_label(group)
            target_folder.mkdir(parents=True, exist_ok=True)
            target = target_folder / (slug + candidate.suffix.lower())
            digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
            if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                target = target_folder / (slug + '-' + digest[:8] + candidate.suffix.lower())
            shutil.copyfile(candidate, target)
            copied.append({'label': label, 'source': str(relative),
                           'manifest': str(manifest.relative_to(source)),
                           'output': str(target.relative_to(destination)), 'sha256': digest})
    if not manifests:
        warnings.append('Aucun manifeste JSON exporté; aucune capture sémantique créée.')
    report = {'screenshots': copied, 'warnings': warnings,
              'provenance': 'pièces jointes XCTest réellement exportées; fichiers copiés sans modification'}
    Path(index_path).parent.mkdir(parents=True, exist_ok=True)
    Path(index_path).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{len(copied)} capture(s) reliée(s) au manifeste XCTest; {len(warnings)} avertissement(s).')
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('index', type=Path)
    arguments = parser.parse_args()
    collect(arguments.source, arguments.destination, arguments.index)
