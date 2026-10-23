#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('live_insertion', Path(__file__).with_name('verify-live-insertion.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
matrix_spec = importlib.util.spec_from_file_location('insertion_matrix',
                                                     Path(__file__).with_name('verify-insertion-matrix.py'))
matrix = importlib.util.module_from_spec(matrix_spec)
matrix_spec.loader.exec_module(matrix)


def fake_app(path, identifier, executable='Fixture'):
    (path / 'Contents/MacOS').mkdir(parents=True)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(
        {'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable}))
    return path


def fake_debug_app(root):
    app = fake_app(root / 'Airdraft Debug.app', 'com.lstudlo.app.airdraft.debug', 'Airdraft Debug')
    (app / 'Contents/MacOS/Airdraft Debug').write_bytes(b'executable')
    (app / 'Contents/MacOS/Airdraft Debug.debug.dylib').write_bytes(b'ui')
    core = app / 'Contents/Frameworks/AirdraftCore.framework'
    core.mkdir(parents=True)
    (core / 'AirdraftCore').write_bytes(b'core')
    return app


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


class InsertionMatrixTests(unittest.TestCase):
    prefixes = ['dev.warp.Warp', 'dev.zed.Zed', 'com.mitchellh.ghostty']

    def installed(self, root):
        apps = root / 'Applications'
        for name, identifier in [('TextEdit', 'com.apple.TextEdit'), ('Google Chrome', 'com.google.Chrome'),
                                 ('Terminal', 'com.apple.Terminal'), ('Ghostty', 'com.mitchellh.ghostty'),
                                 ('Zed', 'dev.zed.Zed'), ('Unrelated', 'com.example.Other')]:
            fake_app(apps / f'{name}.app', identifier)
        return apps

    def report(self, case, hashes, **changes):
        report = dict(action='insert', status='passed', targetBundle=case['bundleID'],
                      requestedMethod=case['method'], reportedMethod='paste', notice='',
                      delivery='delivered' if case['expectation'] == 'confirmed' else 'sentUnverified',
                      fieldMode=case['fieldMode'], actualTextMatches=case['expectation'] == 'confirmed',
                      deliveryCallbacks=1, fixtureToken=case['token'], binarySHA256=hashes)
        return report | changes

    def testDetectsOnlyInstalledTargetsByBundleID(self):
        with tempfile.TemporaryDirectory() as temporary:
            apps = self.installed(Path(temporary))
            found = matrix.detect_targets([apps])
            self.assertEqual([target.name for target, _, _ in found], ['TextEdit', 'Chrome', 'Zed', 'Ghostty', 'Terminal'])
            self.assertEqual([t.name for t, _, _ in matrix.detect_targets([apps], {'terminal'})], ['Terminal'])

    def testSelfDrawingListComesFromTheBuildOrItsSingleSource(self):
        source = matrix.self_drawing_prefixes()
        self.assertIn('dev.warp.Warp', source)
        self.assertIn('com.mitchellh.ghostty', source)
        self.assertNotIn('com.apple.Terminal', source)
        self.assertEqual(matrix.self_drawing_prefixes({'selfDrawingEditorBundlePrefixes': ['x.y']}), ['x.y'])

    def testReadsFrontmostBundleFromBothLsappinfoFormats(self):
        self.assertEqual(matrix.parse_lsappinfo_bundle('"CFBundleIdentifier"="com.apple.TextEdit"'), 'com.apple.TextEdit')
        modern = '[ NULL ]  ASN:0x0-0x6c06c: (in front) \n    bundleID="com.google.Chrome"\n    bundle path=[ NULL ] \n'
        self.assertEqual(matrix.parse_lsappinfo_bundle(modern), 'com.google.Chrome')
        self.assertIsNone(matrix.parse_lsappinfo_bundle('[ NULL ]'))

    def testPlansFreshCasesWithGateReportsOnlyForTextEditAndChrome(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cases = matrix.plan_cases(matrix.detect_targets([self.installed(root)]), self.prefixes,
                                      matrix.METHODS, root / 'out', root / 'gate')
            self.assertEqual(len(cases), 10)
            self.assertEqual(len({case['token'] for case in cases}), 10)
            by_name = {(case['target'], case['method']): case for case in cases}
            gate_case = Path(by_name['TextEdit', 'auto']['data'])
            self.assertEqual(gate_case.parent, root / 'gate')
            self.assertTrue(gate_case.name.startswith('textedit-auto-'))
            self.assertEqual(Path(by_name['Terminal', 'paste']['data']), root / 'out/cases/terminal-paste/e2e')
            self.assertEqual((by_name['TextEdit', 'paste']['fieldMode'], by_name['Terminal', 'auto']['fieldMode'],
                              by_name['Ghostty', 'auto']['fieldMode'], by_name['Zed', 'auto']['fieldMode']),
                             ('exact', 'suffix', 'none', 'none'))
            self.assertEqual(by_name['Ghostty', 'auto']['expectation'], 'sent-unverified')
            self.assertEqual(by_name['Terminal', 'auto']['expectation'], 'confirmed')

    def testEvaluatesActualTextSentUnverifiedAndReceiverEvidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cases = {(c['target'], c['method']): c for c in matrix.plan_cases(
                matrix.detect_targets([self.installed(root)]), self.prefixes, matrix.METHODS, root / 'out')}
            hashes = {'core': 'current'}
            textedit, zed, ghostty, terminal = (cases[name, 'auto'] for name in ('TextEdit', 'Zed', 'Ghostty', 'Terminal'))
            self.assertEqual(matrix.evaluate(textedit, self.report(textedit, hashes), hashes)[0], 'passed')
            self.assertEqual(matrix.evaluate(zed, self.report(zed, hashes), hashes)[0], 'passed')
            one = {'pastes': [matrix.inserted_text(ghostty['token'])]}
            self.assertEqual(matrix.evaluate(ghostty, self.report(ghostty, hashes), hashes, one)[0], 'passed')
            self.assertEqual(matrix.evaluate(ghostty, self.report(ghostty, hashes), hashes)[0], 'failed')
            twice = {'pastes': one['pastes'] * 2}
            self.assertEqual(matrix.evaluate(ghostty, self.report(ghostty, hashes), hashes, twice)[0], 'failed')
            evidence = {'pastes': [matrix.inserted_text(terminal['token'])]}
            self.assertEqual(matrix.evaluate(terminal, self.report(terminal, hashes), hashes, evidence)[0], 'passed')
            for changes in [dict(notice='Paste could not be confirmed'), dict(deliveryCallbacks=2),
                            dict(deliveryCallbacks=True), dict(actualTextMatches=False), dict(status='failed'),
                            dict(delivery='notDelivered', reportedMethod='clipboardOnly'),
                            dict(fixtureToken='reused'), dict(binarySHA256={'core': 'old'}), dict(fieldMode='suffix')]:
                with self.subTest(changes=changes):
                    self.assertEqual(matrix.evaluate(textedit, self.report(textedit, hashes, **changes), hashes)[0],
                                     'failed')
            # A self-drawing editor that reports confirmed delivery contradicts its documented outcome.
            self.assertEqual(matrix.evaluate(zed, self.report(zed, hashes, delivery='delivered'), hashes)[0], 'failed')
            # Ghostty 1.3 publishes a caret and may confirm; its receiver still proves one paste.
            self.assertEqual(matrix.evaluate(ghostty, self.report(ghostty, hashes, delivery='delivered'), hashes, one)[0],
                             'passed')
            self.assertEqual(matrix.evaluate(ghostty, self.report(ghostty, hashes, delivery='delivered'), hashes, twice)[0],
                             'failed')
            self.assertEqual(matrix.evaluate(textedit, None, hashes)[0], 'failed')
            refused = {'action': 'insert', 'status': 'failed', 'error': 'The requested fixture app is not frontmost.'}
            self.assertEqual(matrix.evaluate(textedit, refused, hashes)[0], 'unverified')

    def testConfirmedGateCaseSatisfiesTheReleaseGate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cases = matrix.plan_cases(matrix.detect_targets([self.installed(root)], {'textedit', 'chrome'}),
                                      self.prefixes, matrix.METHODS, root / 'out', root / 'gate')
            reports = [self.report(case, {'core': 'current'}) for case in cases]
            self.assertEqual(gate.validate(reports, {'core': 'current'})['cases'], 4)

    def testSummaryExitCodes(self):
        self.assertEqual(matrix.summarize([]), ('unverified', 2))
        self.assertEqual(matrix.summarize([{'status': 'passed'}]), ('passed', 0))
        self.assertEqual(matrix.summarize([{'status': 'passed'}, {'status': 'unverified'}]), ('unverified', 2))
        self.assertEqual(matrix.summarize([{'status': 'failed'}, {'status': 'unverified'}]), ('failed', 1))

    def run_matrix(self, root, *extra, probe=None):
        app = fake_debug_app(root)
        calls = []

        def fake_action(app_path, data, arguments, launcher, timeout):
            calls.append(arguments)
            return probe(gate.app_hashes(app)) if probe else None

        with patch.object(matrix, 'run_action', side_effect=fake_action), \
                patch.object(matrix, 'prepare_field', side_effect=AssertionError('prepared a field')), \
                patch.object(matrix.subprocess, 'run', side_effect=AssertionError('launched a process')), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = matrix.main(['--app', str(app), '--output', str(root / 'out'),
                                '--applications-dir', str(self.installed(root)), *extra])
        return code, json.loads((root / 'out/matrix.json').read_text()), calls

    def testNoLaunchRecordsEveryCaseUnverifiedWithoutStartingAnything(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, summary, calls = self.run_matrix(Path(temporary), '--no-launch', 'no app launches allowed')
            self.assertEqual((code, summary['status'], calls), (2, 'unverified', []))
            self.assertEqual(len(summary['cases']), 10)
            self.assertTrue(all(case['status'] == 'unverified' and 'no app launches allowed' in case['reason']
                                for case in summary['cases']))

    def testUntrustedDebugAppMakesEveryCaseUnverifiedWithInstructions(self):
        with tempfile.TemporaryDirectory() as temporary:
            probe = lambda hashes: {'action': 'accessibility', 'status': 'passed', 'trusted': False,
                                    'bundleIdentifier': 'com.lstudlo.app.airdraft.debug', 'binarySHA256': hashes,
                                    'selfDrawingEditorBundlePrefixes': self.prefixes}
            code, summary, calls = self.run_matrix(Path(temporary), probe=probe)
            self.assertEqual(calls, [['--e2e-action', 'accessibility']])
            self.assertEqual((code, summary['status'], summary['accessibilityTrusted']), (2, 'unverified', False))
            self.assertIn('Privacy & Security > Accessibility', summary['instructions'])
            self.assertTrue(all(case['status'] == 'unverified' for case in summary['cases']))
            stale = lambda hashes: {'status': 'passed', 'trusted': True, 'binarySHA256': {'other': 'build'}}
            code, summary, _ = self.run_matrix(Path(temporary) / 'stale', probe=stale)
            self.assertEqual((code, summary['accessibilityTrusted']), (2, None))

    def testTerminalReceiverParsesBracketedPastesAndFocus(self):
        data = (b'\x1b[I' + b'x' + matrix.PASTE_START + 'é text'.encode() + matrix.PASTE_END + b'\x1b[O'
                + matrix.PASTE_START + b'partial')
        pastes, focus, stray, consumed = matrix.parse_terminal_input(data)
        self.assertEqual((pastes, focus, stray), (['é text'], ['in', 'out'], 1))
        self.assertLess(consumed, len(data))


if __name__ == '__main__':
    unittest.main()
