#!/usr/bin/env python3
"""Fault-injection tests for release evidence, independent of live model quality."""
import json
from pathlib import Path
import tempfile
import unittest
from verify_prompt import digest, verify
import hashlib


class PromptGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.sources = self.root / 'Packages/AirdraftCore/Sources/AirdraftCore'
        names = ['LLM/PromptBuilder.swift', 'LLM/RefinementProfile.swift', 'Context/AppFamily.swift', 'Dictionary/DictionaryPostProcessor.swift']
        for name in names:
            path = self.sources / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (self.sources / names[0]).write_text('public static let version = "test"\npublic static let defaultBaseRules = """\n    fixture\n    """')
        self.results = self.root / 'eval/results'
        self.results.mkdir(parents=True)
        self.manifest = {'prompt_version': 'test', 'datasets': {}}
        for dataset in ['correction_cases.json', 'holdout_cases.json']:
            cases = [{'id': 'one', 'expect': ['complete'], 'forbid': ['partial']}]
            (self.root / 'eval' / dataset).write_text(json.dumps(cases))
            report = {'prompt_version': 'test', 'assembly_sources': {name: digest(self.sources/name) for name in names},
                      'default_rules_sha256': hashlib.sha256(b'fixture').hexdigest(),
                      'cases_sha256': digest(self.root/'eval'/dataset), 'cases': dataset,
                      'runs': 3, 'total': 3, 'max': 3,
                      'results': [{'id': 'one', 'passed': 3, 'runs': [{'returncode': 0, 'ok': True, 'text': 'complete'} for _ in range(3)]}]}
            entry = {}
            for kind in ['baseline', 'candidate']:
                name = kind + '-' + dataset
                path = self.results/name
                path.write_text(json.dumps(report))
                entry[kind] = name
                entry[kind+'_sha256'] = digest(path)
            self.manifest['datasets'][dataset] = entry
        self.write_manifest()

    def tearDown(self): self.temp.cleanup()
    def write_manifest(self):
        (self.results/'prompt-validation.json').write_text(json.dumps(self.manifest))

    def mutate_report(self, change):
        entry = self.manifest['datasets']['holdout_cases.json']
        path = self.results/entry['candidate']
        report = json.loads(path.read_text())
        change(report)
        path.write_text(json.dumps(report))
        entry['candidate_sha256'] = digest(path)
        self.write_manifest()

    def test_valid_evidence(self): self.assertEqual(verify(self.root), 'test')

    def test_source_change_invalidates_both_suites(self):
        (self.sources/'Context/AppFamily.swift').write_text('changed')
        with self.assertRaisesRegex(RuntimeError, 'assembly changed'): verify(self.root)

    def test_nonzero_cli_exit_cannot_be_scored_as_success(self):
        self.mutate_report(lambda report: report['results'][0]['runs'][0].update(returncode=1))
        with self.assertRaisesRegex(RuntimeError, 'scores'): verify(self.root)

    def test_holdout_regression_fails_even_with_full_correction_score(self):
        def regress(report):
            report['results'][0]['runs'][0].update(text='partial', ok=False)
            report['results'][0]['passed'] = 2
            report['total'] = 2
        self.mutate_report(regress)
        with self.assertRaisesRegex(RuntimeError, 'regressed'): verify(self.root)

    def test_changed_artifact_hash_is_rejected(self):
        (self.results/'candidate-holdout_cases.json').write_text('{}')
        with self.assertRaisesRegex(RuntimeError, 'Changed candidate'): verify(self.root)


if __name__ == '__main__': unittest.main()
