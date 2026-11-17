import plistlib
import unittest

from prepare_focus_shortcut import build_workflow, GET_FOCUS_ACTION, PREFIX


def run_document(document, command, current_focus=None):
    """Evaluate the serialized branching, not a second shortcut generator.

    Only the small allowlisted action vocabulary is accepted. This catches wrong
    branch boundaries and accidental side effects in probe/unknown-input paths.
    Apple still owns actual action execution and signature validation.
    """
    actions = document['WFWorkflowActions']
    variables, effects, stack = {}, [], []
    executing = True
    for action in actions:
        name = action['WFWorkflowActionIdentifier']
        parameters = action['WFWorkflowActionParameters']
        if name == PREFIX + 'conditional':
            mode = parameters['WFControlFlowMode']
            if mode == 0:
                reference = parameters['WFInput']['Variable']['Value']['OutputUUID']
                value = variables.get(reference)
                condition = parameters['WFCondition']
                if condition == 4:
                    accepted = value == parameters['WFConditionalActionString']
                elif condition == 100:
                    accepted = value is not None and value != ''
                else:
                    raise AssertionError('Unsupported condition')
                stack.append((parameters['GroupingIdentifier'], executing, accepted))
                executing = executing and accepted
            elif mode == 1:
                group, outer, accepted = stack[-1]
                assert group == parameters['GroupingIdentifier']
                executing = outer and not accepted
            elif mode == 2:
                group, executing, _ = stack.pop()
                assert group == parameters['GroupingIdentifier']
            else:
                raise AssertionError('Unsupported control flow')
        elif not executing:
            continue
        elif name == PREFIX + 'comment':
            pass
        elif name == PREFIX + 'text.trimwhitespace':
            variables[parameters['UUID']] = command.strip()
        elif name == GET_FOCUS_ACTION:
            variables[parameters['UUID']] = current_focus
        elif name == PREFIX + 'dnd.set':
            effects.append(parameters['Enabled'])
            # Omitting FocusModes deliberately uses the action's DND default.
            assert 'FocusModes' not in parameters
        elif name == PREFIX + 'output':
            return parameters['WFOutput']['Value']['string'], effects
        else:
            raise AssertionError('Unexpected action: ' + name)
    raise AssertionError('Document did not return a value')


class FocusShortcutTests(unittest.TestCase):
    def setUp(self):
        # Round-trip the exported plist bytes before evaluating the actions.
        self.document = plistlib.loads(plistlib.dumps(build_workflow()))

    def test_probe_and_unknown_inputs_have_no_focus_effect(self):
        for value in ('probe', '', 'invalid', 'ON', 'off:work'):
            with self.subTest(value=value):
                self.assertEqual(run_document(self.document, value), ('cadenza-focus-v1', []))

    def test_on_activates_dnd_only_when_no_focus_exists(self):
        self.assertEqual(run_document(self.document, ' on '), ('enabled', [True]))
        for value in ('Work', 'Personal', 'Do Not Disturb'):
            with self.subTest(value=value):
                self.assertEqual(run_document(self.document, 'on', value), ('kept', []))

    def test_off_only_requests_dnd_deactivation(self):
        self.assertEqual(run_document(self.document, 'off', 'Work'), ('disabled', [False]))
        self.assertEqual(run_document(self.document, 'off'), ('disabled', [False]))

    def test_all_control_flow_groups_and_output_references_are_balanced(self):
        groups, declared, referenced = [], set(), set()
        for item in self.document['WFWorkflowActions']:
            parameters = item['WFWorkflowActionParameters']
            if 'UUID' in parameters:
                self.assertNotIn(parameters['UUID'], declared)
                declared.add(parameters['UUID'])
            if item['WFWorkflowActionIdentifier'] == PREFIX + 'conditional':
                mode, group = parameters['WFControlFlowMode'], parameters['GroupingIdentifier']
                if mode == 0:
                    groups.append(group)
                    referenced.add(parameters['WFInput']['Variable']['Value']['OutputUUID'])
                else:
                    self.assertEqual(group, groups[-1])
                    if mode == 2:
                        groups.pop()
        self.assertEqual(groups, [])
        self.assertTrue(referenced <= declared)

    def test_document_has_no_sensitive_or_network_actions(self):
        names = {item['WFWorkflowActionIdentifier'] for item in self.document['WFWorkflowActions']}
        self.assertEqual(names, {PREFIX + suffix for suffix in (
            'comment', 'text.trimwhitespace', 'conditional', 'dnd.getfocus', 'dnd.set', 'output')})
        self.assertEqual(self.document['WFWorkflowImportQuestions'], [])
        self.assertNotIn('WFWorkflowUserInfo', self.document)


if __name__ == '__main__':
    unittest.main()
