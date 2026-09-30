#!/usr/bin/env python3
"""Release gates: push scope, source identity, and hostile/mismatched manifests."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import release_signing

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseTests(unittest.TestCase):
    def test_only_main_pushes_prepare_releases(self):
        sha = 'a' * 40
        self.assertIsNone(release.pushed_commit(f'refs/heads/feature {sha} refs/heads/feature {release.ZERO}\n'))
        self.assertIsNone(release.pushed_commit(f'refs/tags/v1 {sha} refs/tags/v1 {release.ZERO}\n'))
        self.assertEqual(release.pushed_commit(f'refs/heads/main {sha} refs/heads/main {release.ZERO}\n'), (sha, release.ZERO))

    def test_deletion_is_rejected(self):
        with self.assertRaises(RuntimeError):
            release.pushed_commit(f'(delete) {release.ZERO} refs/heads/main {"a" * 40}')

    def test_version_has_unique_monotonic_build_tag(self):
        self.assertEqual(release.version_for('CFBundleShortVersionString: "0.1.1"', 3), ('0.1.1', 'v0.1.1-build.3'))
        self.assertNotEqual(release.version_for('CFBundleShortVersionString: "0.1.1"', 4)[1], 'v0.1.1-build.3')

    def test_credential_free_scope_uses_the_local_allowlist(self):
        source = Path(__file__).resolve().parents[1]
        selection = release.core_test_selection(source, 'credential-free')
        self.assertIn('-only-testing:AirdraftCoreTests/OnboardingProgressTests', selection)
        self.assertIn('-only-testing:AirdraftCoreTests/CLIProcessTests', selection)
        self.assertIn('-only-testing:AirdraftCoreTests/TextDeliveryRegressionTests', selection)
        self.assertNotIn('-only-testing:AirdraftCoreTests/AppIdentityTests', selection)
        self.assertFalse(any('CredentialTests' in name or 'RefinerWireTests' in name for name in selection))
        self.assertEqual(release.core_test_selection(source, 'full'), [])

    def test_unknown_scope_never_expands_to_full_tests(self):
        with self.assertRaisesRegex(RuntimeError, 'Unknown release test scope'):
            release.core_test_selection(Path('.'), 'typo')

    def test_local_test_environment_excludes_unrelated_settings(self):
        with patch.dict(release.os.environ, {'HOME': '/fixture', 'PATH': '/bin',
                                            'UNRELATED_SETTING': 'excluded'}, clear=True):
            self.assertEqual(release.local_test_environment(), {'HOME': '/fixture', 'PATH': '/bin'})

    def test_manifest_records_scope_and_exact_exclusions(self):
        for scope in release.TEST_SCOPES:
            manifest = self.manifest() | {'verification': release.verification_for(scope)}
            release.validate_manifest(manifest, 'a' * 40, manifest['tag'])
        for verification in [None, {}, {'testScope': 'typo'},
                             {'testScope': 'credential-free', 'excluded': []}]:
            manifest = self.manifest() | {'verification': verification}
            with self.assertRaises(RuntimeError):
                release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def manifest(self):
        return {'commit': 'a' * 40, 'tag': 'v0.1.1-build.3', 'version': '0.1.1', 'build': 3,
                'signing': dict(release_signing.POLICY),
                'sha256': {'Airdraft-0.1.1-3-arm64.dmg': 'b' * 64, 'appcast.xml': 'c' * 64}}

    def test_manifest_binds_archive_to_commit(self):
        self.assertEqual(release.validate_manifest(self.manifest(), 'a' * 40, 'v0.1.1-build.3'), 'Airdraft-0.1.1-3-arm64.dmg')
        with self.assertRaises(RuntimeError):
            release.validate_manifest(self.manifest(), 'd' * 40, 'v0.1.1-build.3')

    def test_new_releases_require_native_and_web_insertion_evidence(self):
        manifest = self.manifest() | {'version': '0.4.2', 'tag': 'v0.4.2-build.3',
            'sha256': {'Airdraft-0.4.2-3-arm64.dmg': 'b' * 64, 'appcast.xml': 'c' * 64}}
        evidence = {'status': 'passed', 'commit': 'a' * 40, 'cases': 4,
            'binarySHA256': {name: 'd' * 64 for name in ('Airdraft Debug', 'Airdraft Debug.debug.dylib', 'AirdraftCore')},
            'verifiedTargets': [[app, method] for app in ('com.apple.TextEdit', 'com.google.Chrome')
                                for method in ('auto', 'paste')]}
        for invalid in ({}, evidence | {'commit': 'e' * 40}, evidence | {'status': 'failed'},
                        evidence | {'verifiedTargets': []}, evidence | {'binarySHA256': {}},
                        evidence | {'cases': True}):
            with self.assertRaisesRegex(RuntimeError, 'insertion evidence'):
                release.validate_manifest(manifest | {'liveInsertion': invalid}, 'a' * 40, manifest['tag'])
        release.validate_manifest(manifest | {'liveInsertion': evidence}, 'a' * 40, manifest['tag'])

    def test_manifest_version_and_build_must_match_tag(self):
        for version, build in [('0.9.9', 3), ('0.1.1', 4)]:
            with self.subTest(version=version, build=build):
                manifest = self.manifest()
                manifest.update(version=version, build=build)
                manifest['sha256'] = {f'Airdraft-{version}-{build}-arm64.dmg': 'b' * 64,
                                      'appcast.xml': 'c' * 64}
                with self.assertRaisesRegex(RuntimeError, 'version/build'):
                    release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def test_unverified_live_insertion_is_honest_and_commit_bound(self):
        manifest = self.manifest() | {'version': '0.4.2', 'tag': 'v0.4.2-build.3',
            'sha256': {'Airdraft-0.4.2-3-arm64.dmg': 'b' * 64, 'appcast.xml': 'c' * 64}}
        evidence = {'status': 'unverified', 'commit': 'a' * 40,
                    'reason': 'Debug Accessibility is unavailable.',
                    'releasePolicy': 'report-unverified-after-release'}
        release.validate_manifest(manifest | {'liveInsertion': evidence}, 'a' * 40, manifest['tag'])
        for invalid in (evidence | {'reason': ''}, evidence | {'reason': ' '},
                        evidence | {'commit': 'e' * 40}, evidence | {'releasePolicy': None},
                        evidence | {'cases': 4}, evidence | {'verifiedTargets': [['com.apple.TextEdit', 'auto']]}):
            with self.subTest(evidence=invalid), self.assertRaises(RuntimeError):
                release.validate_manifest(manifest | {'liveInsertion': invalid}, 'a' * 40, manifest['tag'])

    def test_live_insertion_policy_retains_failure_and_does_not_invent_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = output / 'insertion-e2e.json'
            failure = {'status': 'failed', 'reason': 'Missing live editor receipts'}
            report.write_text(json.dumps(failure))
            with patch.object(release, 'logged', side_effect=RuntimeError('Fixture incomplete')):
                with self.assertRaisesRegex(RuntimeError, 'Fixture incomplete'):
                    release.live_insertion_evidence(output, output, output / 'Debug.app', 'a' * 40)
                evidence = release.live_insertion_evidence(
                    output, output, output / 'Debug.app', 'a' * 40, 'Debug Accessibility unavailable')
            self.assertEqual(evidence['status'], 'unverified')
            self.assertNotIn('cases', evidence)
            self.assertEqual(json.loads(report.read_text()), failure)
            passed = {'status': 'passed', 'cases': 4}
            report.write_text(json.dumps(passed))
            with patch.object(release, 'logged'):
                self.assertEqual(release.live_insertion_evidence(
                    output, output, output / 'Debug.app', 'a' * 40, 'Unused reason'),
                    passed | {'commit': 'a' * 40})

    def test_manifest_rejects_boolean_build_numbers(self):
        manifest = self.manifest()
        manifest.update(build=True, tag='v0.1.1-build.True')
        manifest['sha256'] = {'Airdraft-0.1.1-True-arm64.dmg': 'b' * 64, 'appcast.xml': 'c' * 64}
        with self.assertRaisesRegex(RuntimeError, 'build'):
            release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def test_manifest_rejects_other_tags_paths_and_missing_assets(self):
        with self.assertRaises(RuntimeError):
            release.validate_manifest(self.manifest(), 'a' * 40, 'v0.1.1-build.4')
        for name in ['../../secret', 'other.dmg']:
            manifest = self.manifest()
            manifest['sha256'][name] = 'b' * 64
            with self.assertRaises(RuntimeError):
                release.validate_manifest(manifest, 'a' * 40, manifest['tag'])
        manifest = self.manifest()
        del manifest['sha256']['appcast.xml']
        with self.assertRaises(RuntimeError):
            release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def test_manifest_rejects_invalid_hashes(self):
        manifest = self.manifest()
        manifest['sha256']['appcast.xml'] = 'invalid'
        with self.assertRaises(RuntimeError):
            release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def test_manifest_rejects_unsigned_or_changed_identity(self):
        for field, value in [('bundleID', 'com.lstudlo.app.airdraft.debug'),
                             ('teamID', 'OTHERTEAM'), ('certificateSHA1', '0' * 40),
                             ('designatedRequirement', 'identifier "com.lstudlo.app.airdraft"'),
                             ('designatedRequirement', 'cdhash H"' + 'a' * 40 + '"')]:
            with self.subTest(field=field, value=value):
                manifest = self.manifest()
                manifest['signing'][field] = value
                with self.assertRaises(RuntimeError):
                    release.validate_manifest(manifest, 'a' * 40, manifest['tag'])
        manifest = self.manifest()
        del manifest['signing']
        with self.assertRaises(RuntimeError):
            release.validate_manifest(manifest, 'a' * 40, manifest['tag'])

    def test_missing_certificate_does_not_fall_back(self):
        with patch.object(release_signing, 'command') as command:
            command.return_value.stdout = b'0 valid identities found'
            with self.assertRaisesRegex(RuntimeError, 'never fall back'):
                release_signing.preflight()

    def test_previous_release_identity_cannot_silently_change(self):
        release.validate_continuity(self.manifest())
        for field in ('bundleID', 'teamID', 'designatedRequirement'):
            manifest = self.manifest()
            manifest['signing'][field] = 'changed'
            with self.assertRaises(RuntimeError):
                release.validate_continuity(manifest)

    def test_only_known_legacy_release_can_migrate_without_signing_metadata(self):
        legacy = {'tag': 'v0.1.4-build.6', 'commit': '7dbd3aaac6a669715c64c150238f71d397e0ad26'}
        release.validate_continuity(legacy)
        for replacement in ({'tag': 'v0.1.5-build.7'}, {'commit': 'a' * 40}):
            with self.assertRaises(RuntimeError):
                release.validate_continuity(legacy | replacement)

    def test_hardened_runtime_is_required_even_with_certificate_signature(self):
        for flags in ["", "CodeDirectory flags=0x0(none)", "CodeDirectory flags=0x2(adhoc)"]:
            with self.assertRaisesRegex(RuntimeError, "Hardened Runtime"):
                release_signing.validate_runtime(flags)
        release_signing.validate_runtime("CodeDirectory flags=0x10000(runtime)")

    def test_ad_hoc_signature_is_rejected_before_packaging(self):
        with patch.object(release_signing, 'command') as command:
            command.return_value.stderr = b'Signature=adhoc\nTeamIdentifier=not set\n'
            with self.assertRaisesRegex(RuntimeError, 'ad-hoc release'):
                release_signing.inspect_app(Path('fixture.app'))

if __name__ == '__main__':
    unittest.main()
