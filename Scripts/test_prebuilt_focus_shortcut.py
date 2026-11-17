import plistlib
import struct
import unittest

from verify_prebuilt_focus_shortcut import expected_actions, normalized_actions, signing_chain, validate_workflow


class PrebuiltFocusShortcutTests(unittest.TestCase):
    def workflow(self):
        return {'WFWorkflowActions': expected_actions(), 'WFWorkflowTypes': [], 'WFWorkflowImportQuestions': []}

    def test_exact_graph_accepts_new_uuid_values_without_changing_references(self):
        workflow = self.workflow()
        actions = workflow['WFWorkflowActions']
        data = plistlib.dumps(actions).replace(b'<string>TEXT</string>', b'<string>REAL-TEXT-UUID</string>')
        workflow['WFWorkflowActions'] = plistlib.loads(data)
        self.assertEqual(len(validate_workflow(workflow)), 5)

    def test_graph_rejects_network_action_wrong_focus_or_broken_reference(self):
        for mutation in ('network', 'focus', 'reference'):
            workflow = self.workflow()
            actions = workflow['WFWorkflowActions']
            if mutation == 'network':
                actions[0]['WFWorkflowActionIdentifier'] = 'is.workflow.actions.downloadurl'
            elif mutation == 'focus':
                actions[2]['WFWorkflowActionParameters']['FocusModes']['Identifier'] = 'another-mode'
            else:
                actions[1]['WFWorkflowActionParameters']['WFInput']['Variable']['Value']['OutputUUID'] = 'MISSING'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_workflow(workflow)

    def test_graph_rejects_automatic_triggers(self):
        workflow = self.workflow()
        workflow['WFWorkflowTriggers'] = [{'kind': 'unexpected'}]
        with self.assertRaises(ValueError):
            validate_workflow(workflow)

    def test_envelope_rejects_malformed_profile_and_contact_signatures(self):
        contacts = plistlib.dumps({'AppleIDValidationRecord': {'example': 'not-used'}})
        cases = [b'not signed', b'AEA1' + struct.pack('<II', 1, 10) + b'x' * 20,
                 b'AEA1' + struct.pack('<II', 0, len(contacts)) + contacts + b'payload']
        for data in cases:
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                signing_chain(data)


if __name__ == '__main__':
    unittest.main()
