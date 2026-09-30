#!/usr/bin/env python3
"""Fault checks for the mandatory insertion regression gate."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('insertion_gate', Path(__file__).with_name('verify-insertion-regressions.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class InsertionGateTests(unittest.TestCase):
    def tree(self, result='Passed', target='AirdraftCoreTests'):
        return {'testNodes': [{'children': [
            {'nodeType': 'Test Case', 'nodeIdentifier': name, 'result': result,
             'nodeIdentifierURL': f'test://com.apple.xcode/AirdraftCore/{target}/{name}'}
            for name in gate.REQUIRED_TESTS]}]}

    def test_complete_passing_contract_is_accepted(self):
        self.assertEqual(gate.validate_test_tree(self.tree())['passed'], len(gate.REQUIRED_TESTS))

    def test_missing_suite_or_test_is_rejected(self):
        for tree in [{'testNodes': []}, self.tree()]:
            if tree['testNodes']:
                tree['testNodes'][0]['children'].pop()
            with self.assertRaisesRegex(RuntimeError, 'Missing required'):
                gate.validate_test_tree(tree)

    def test_skipped_failed_unknown_and_absent_statuses_are_rejected(self):
        for status in ['Skipped', 'Failed', 'Expected Failure', 'Unknown', None]:
            with self.subTest(status=status), self.assertRaisesRegex(RuntimeError, 'did not pass'):
                gate.validate_test_tree(self.tree(result=status))

    def test_passing_retry_cannot_hide_a_failed_execution(self):
        tree = self.tree()
        failed = dict(tree['testNodes'][0]['children'][0], result='Failed')
        tree['testNodes'][0]['children'].append(failed)
        with self.assertRaisesRegex(RuntimeError, 'did not pass'):
            gate.validate_test_tree(tree)

    def test_same_test_name_from_another_target_is_not_evidence(self):
        with self.assertRaisesRegex(RuntimeError, 'Missing required'):
            gate.validate_test_tree(self.tree(target='OtherTests'))

    def test_nested_failed_repetition_cannot_hide_under_a_passing_case(self):
        tree = self.tree()
        tree['testNodes'][0]['children'][0]['children'] = [
            {'nodeType': 'Repetition', 'result': 'Failed'},
            {'nodeType': 'Repetition', 'result': 'Passed'}]
        with self.assertRaisesRegex(RuntimeError, 'did not pass'):
            gate.validate_test_tree(tree)


if __name__ == '__main__':
    unittest.main()
