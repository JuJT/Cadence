#!/usr/bin/env python3
"""Build and sign the reviewable Focus helper with Apple's public shortcuts CLI.

The file format is the exported Shortcuts document format. No private framework
is loaded or called. Only Apple's public shortcuts command signs the document.
Exported action identifiers are explicit and versioned; signing fails closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

NAME = 'Cadenza Concentration'
PREFIX = 'is.workflow.actions.'
GET_FOCUS_ACTION = PREFIX + 'dnd.getfocus'
NAMESPACE = uuid.UUID('d6d1a98c-7159-4aca-8393-91733ac2fb34')


def identifier(label):
    return str(uuid.uuid5(NAMESPACE, label)).upper()


def action(name, **parameters):
    return {'WFWorkflowActionIdentifier': name,
            'WFWorkflowActionParameters': parameters}


def text(value):
    return {'WFSerializationType': 'WFTextTokenString',
            'Value': {'string': value, 'attachmentsByRange': {}}}


def output(value):
    return action(PREFIX + 'output', WFOutput=text(value))


def reference(output_id, name):
    return {'Type': 'Variable', 'Variable': {
        'WFSerializationType': 'WFTextTokenAttachment',
        'Value': {'Type': 'ActionOutput', 'OutputUUID': output_id, 'OutputName': name}}}


def branch(label, input_value, condition, body, comparison=None):
    group = identifier(label)
    parameters = {'GroupingIdentifier': group, 'WFControlFlowMode': 0,
                  'WFInput': input_value, 'WFCondition': condition}
    if comparison is not None:
        parameters['WFConditionalActionString'] = comparison
    return [action(PREFIX + 'conditional', **parameters), *body,
            action(PREFIX + 'conditional', GroupingIdentifier=group, WFControlFlowMode=1),
            action(PREFIX + 'conditional', GroupingIdentifier=group, WFControlFlowMode=2)]


def build_workflow():
    input_id, focus_id = identifier('input'), identifier('current-focus')
    shortcut_input = {'WFSerializationType': 'WFTextTokenString',
                      'Value': {'string': '\ufffc',
                                'attachmentsByRange': {'{0, 1}': {'Type': 'ExtensionInput'}}}}
    input_ref = reference(input_id, 'Updated Text')
    focus_ref = reference(focus_id, 'Current Focus')
    # A no-side-effect probe precedes every Focus action. Unknown input, including
    # a manual run with no input, returns a marker and does not change Focus.
    actions = [action(PREFIX + 'comment', WFCommentActionText=(
        'Cadenza — Concentration pendant une séance.\n'
        'probe : vérifier sans changer de réglage.\n'
        'on : conserver tout mode déjà actif, sinon activer Ne pas déranger.\n'
        'off : désactiver spécifiquement Ne pas déranger.\n'
        'Aucun réseau, fichier, contact, calendrier ou identifiant de compte lu.')),
        action(PREFIX + 'text.trimwhitespace', UUID=input_id, WFInput=shortcut_input)]
    actions += branch('probe-branch', input_ref, 4, [output('cadenza-focus-v1')], 'probe')
    actions += branch('enable-branch', input_ref, 4, [
        action(GET_FOCUS_ACTION, UUID=focus_id),
        *branch('existing-focus', focus_ref, 100, [output('kept')]),
        action(PREFIX + 'dnd.set', Enabled=True, AssertionType='Turned Off'),
        output('enabled')], 'on')
    actions += branch('disable-branch', input_ref, 4, [
        action(PREFIX + 'dnd.set', Enabled=False), output('disabled')], 'off')
    actions += [output('cadenza-focus-v1')]
    return {'WFWorkflowName': NAME, 'WFWorkflowClientVersion': '2607.0.4',
            'WFWorkflowMinimumClientVersion': 900,
            'WFWorkflowMinimumClientVersionString': '900',
            'WFWorkflowIcon': {'WFWorkflowIconStartColor': 1440408063,
                               'WFWorkflowIconGlyphNumber': 59511},
            'WFWorkflowImportQuestions': [], 'WFWorkflowTypes': [],
            'WFQuickActionSurfaces': [], 'WFWorkflowHasShortcutInputVariables': True,
            'WFWorkflowInputContentItemClasses': ['WFStringContentItem', 'WFGenericFileContentItem'],
            'WFWorkflowOutputContentItemClasses': ['WFStringContentItem'],
            'WFWorkflowActions': actions}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=Path('Resources/Shortcuts'))
    parser.add_argument('--reports', type=Path, default=Path('dist/reports'))
    args = parser.parse_args(argv)
    if sys.platform != 'darwin':
        parser.error('Signing requires macOS and the Apple shortcuts command')
    workflow = build_workflow()
    unsigned = plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY, sort_keys=False)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.reports.mkdir(parents=True, exist_ok=True)
    destination = args.output_dir / (NAME + '.shortcut')
    with tempfile.TemporaryDirectory(prefix='cadenza-focus-') as temporary:
        source = Path(temporary) / (NAME + '.shortcut')
        source.write_bytes(unsigned)
        signed = Path(temporary) / 'signed.shortcut'
        process = subprocess.run(['/usr/bin/shortcuts', 'sign', '--mode', 'anyone',
                                  '--input', str(source), '--output', str(signed)],
                                 capture_output=True, text=True, timeout=55)
        if process.returncode != 0 or not signed.is_file():
            raise RuntimeError('Apple shortcuts sign failed: ' + (process.stderr.strip() or process.stdout.strip())[:500])
        data = signed.read_bytes()
        if not data.startswith(b'AEA1') or len(data) <= 128:
            raise RuntimeError('Apple shortcuts sign did not produce the expected signed archive')
        destination.write_bytes(data)
    (args.reports / 'focus-shortcut-source.plist').write_bytes(plistlib.dumps(workflow, sort_keys=False))
    report = {'shortcut': NAME, 'getFocusAction': GET_FOCUS_ACTION,
              'signedByAppleShortcutsCLI': True, 'signingMode': 'anyone',
              'sourceSHA256': hashlib.sha256(unsigned).hexdigest(),
              'signedSHA256': hashlib.sha256(data).hexdigest(), 'signedBytes': len(data),
              'runtimeOnIPhoneVerified': False,
              'note': 'Signature/container validation does not validate iPhone permissions or action execution.'}
    (args.reports / 'focus-shortcut.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Prepared signed shortcut for import; iPhone runtime remains unverified.')


if __name__ == '__main__':
    main()
