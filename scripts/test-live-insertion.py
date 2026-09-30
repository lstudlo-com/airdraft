#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('live_insertion', Path(__file__).with_name('verify-live-insertion.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LiveInsertionGateTests(unittest.TestCase):
    def reports(self):
        return [dict(action='insert', status='passed', actualTextMatches=True,
                     deliveryCallbacks=1, reportedMethod='paste', notice='', binarySHA256={'core': 'current'},
                     fixtureToken=f'{app}-{method}', targetBundle=app, requestedMethod=method)
                for app in ('com.apple.TextEdit', 'com.google.Chrome') for method in ('auto', 'paste')]

    def testAcceptsActualNativeAndWebDelivery(self):
        self.assertEqual(gate.validate(self.reports(), {'core': 'current'})['cases'], 4)

    def testRejectsMissingCasesAndDuplicateFixtures(self):
        for reports in ([], self.reports()[:-1], self.reports() + [self.reports()[0]]):
            with self.assertRaises(ValueError):
                gate.validate(reports, {'core': 'current'})

    def testRejectsPostedKeysWithoutActualTextAndRecoveryNotices(self):
        for field, value in [('actualTextMatches', False), ('status', 'failed'), ('deliveryCallbacks', 2),
                             ('deliveryCallbacks', True),
                             ('notice', 'Check the destination'), ('reportedMethod', 'clipboardOnly')]:
            reports = self.reports()
            reports[0][field] = value
            with self.assertRaises(ValueError):
                gate.validate(reports, {'core': 'current'})

    def testRejectsEvidenceFromAnOlderBinary(self):
        with self.assertRaises(ValueError):
            gate.validate(self.reports(), {'core': 'new build'})


if __name__ == '__main__':
    unittest.main()
