#!/usr/bin/env python3
"""Release gates: push scope, source identity, and hostile/mismatched manifests."""
import importlib.util
import io
import json
import runpy
import shutil
import subprocess
import tarfile
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import acknowledgements
import local_signing
import release_signing

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
adhoc_spec = importlib.util.spec_from_file_location('adhoc', Path(__file__).with_name('verify-adhoc-launch.py'))
adhoc = importlib.util.module_from_spec(adhoc_spec)
adhoc_spec.loader.exec_module(adhoc)

class ReleaseTests(unittest.TestCase):
    def test_export_uses_committed_native_verifier_before_linking_vendor(self):
        for code in (0, 9):
            with self.subTest(verifier_exit=code), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                vendor = root / 'Packages/SherpaOnnxKit/Vendor'
                vendor.mkdir(parents=True)
                sentinel = vendor / 'fixture-library'
                sentinel.write_text('preserve original vendor')
                archive = io.BytesIO()
                with tarfile.open(fileobj=archive, mode='w') as bundle:
                    script = f'import sys\nsys.exit({code})\n'.encode()
                    info = tarfile.TarInfo('scripts/native_inputs.py')
                    info.size = len(script)
                    bundle.addfile(info, io.BytesIO(script))
                    directory = tarfile.TarInfo('Packages/SherpaOnnxKit')
                    directory.type = tarfile.DIRTYPE
                    bundle.addfile(directory)
                with patch.object(release, 'ROOT', root), \
                     patch.object(release.subprocess, 'check_output', return_value=archive.getvalue()):
                    if code:
                        with self.assertRaises(subprocess.CalledProcessError):
                            release.export_snapshot('a' * 40)
                        self.assertFalse((root / 'dist/release-source/Packages/SherpaOnnxKit/Vendor').exists())
                    else:
                        source = release.export_snapshot('a' * 40)
                        self.assertEqual((source / 'Packages/SherpaOnnxKit/Vendor').resolve(), vendor.resolve())
                self.assertEqual(sentinel.read_text(), 'preserve original vendor')

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
        # App logic tests are credential-free as a whole target.
        self.assertEqual(selection[-1], '-only-testing:AirdraftAppTests')
        self.assertEqual(selection.count('-only-testing:AirdraftAppTests'), 1)
        self.assertFalse(any('CredentialTests' in name or 'RefinerWireTests' in name for name in selection))
        self.assertFalse(any('SonioxMediaTests' in name or 'CredentialRemovalTests' in name for name in selection))
        self.assertEqual(release.core_test_selection(source, 'full'), [])
        # The CI-only unsigned route is a runner flag, never part of release selection.
        self.assertFalse(any('CODE_SIGN' in name for name in selection))

    def test_credential_free_selection_rejects_forbidden_suites_and_cases(self):
        runner = runpy.run_path(str(Path(__file__).with_name('test-local-e2e.py')))
        select = runner['credential_free_selection']
        for suite in runner['EXCLUDED_SUITES'] | {'AppIdentityTests'}:
            with self.subTest(suite=suite), self.assertRaises(RuntimeError):
                select([suite], [])
        for suite in runner['EXCLUDED_SUITES']:
            with self.subTest(case=suite), self.assertRaises(RuntimeError):
                select([], [suite + '/testFixture'])
        for names in ([], ['SafeTests', 'SafeTests'], ['*'], ['../SafeTests']):
            with self.subTest(names=names), self.assertRaises(RuntimeError):
                select(names, [])

    def test_app_test_gate_requires_executed_passing_app_cases(self):
        runner = runpy.run_path(str(Path(__file__).with_name('test-local-e2e.py')))
        verify = runner['verify_app_tests']

        def tree(*cases, target='AirdraftAppTests'):
            return {'testNodes': [{'nodeType': 'Unit test bundle', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': name, 'result': result,
                 'nodeIdentifierURL': f'test://com.apple.xcode/airdraft/{target}/Suite/{name}'}
                for name, result in cases]}]}

        self.assertEqual(verify(tree(('testA', 'Passed'), ('testB', 'Passed')))['passed'], 2)
        for bad in [{'testNodes': []}, tree(('testA', 'Passed'), target='AirdraftCoreTests')]:
            with self.subTest(tree=bad), self.assertRaisesRegex(RuntimeError, 'No AirdraftAppTests'):
                verify(bad)
        for status in ['Failed', 'Skipped', 'Expected Failure', None]:
            with self.subTest(status=status), self.assertRaisesRegex(RuntimeError, 'did not pass'):
                verify(tree(('testA', 'Passed'), ('testB', status)))

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

    def test_release_builds_pin_the_identity_over_local_signing(self):
        settings = release_signing.build_settings(release_signing.POLICY['certificateSHA1'])
        self.assertIn(f"DEVELOPMENT_TEAM={release_signing.POLICY['teamID']}", settings)
        self.assertIn(f"CODE_SIGN_IDENTITY={release_signing.POLICY['certificateSHA1']}", settings)
        self.assertIn('CODE_SIGN_STYLE=Manual', settings)
        self.assertIn('ENABLE_HARDENED_RUNTIME=YES', settings)
        self.assertNotIn('CODE_SIGN_IDENTITY=-', settings)
        source = Path(release.__file__).read_text()
        self.assertIn('*signing_settings(identity)]', source)
        self.assertNotIn('Local.xcconfig', source)

    def test_committed_signing_config_defaults_to_ad_hoc_and_ignores_local_team(self):
        root = Path(release.__file__).resolve().parents[1]
        config = (root / 'Config/Signing.xcconfig').read_text()
        self.assertIn('CODE_SIGN_IDENTITY = -', config)
        self.assertRegex(config, r'(?m)^DEVELOPMENT_TEAM =\s*$')
        self.assertIn('#include? "Local.xcconfig"', config)
        self.assertIn('/Config/Local.xcconfig', (root / '.gitignore').read_text())
        project = (root / 'project.yml').read_text()
        self.assertNotIn('DEVELOPMENT_TEAM', project)
        # A project-level setting would override the xcconfig and turn Hardened
        # Runtime on for team-less ad-hoc builds, whose frameworks dyld then refuses.
        self.assertNotIn('ENABLE_HARDENED_RUNTIME', project)

    def test_hardened_runtime_follows_the_signing_team(self):
        root = Path(release.__file__).resolve().parents[1]
        config = (root / 'Config/Signing.xcconfig').read_text()
        self.assertIn('AIRDRAFT_HARDENED_RUNTIME_ADHOC = NO', config)
        self.assertIn('ENABLE_HARDENED_RUNTIME = $(AIRDRAFT_HARDENED_RUNTIME_$(DEVELOPMENT_TEAM:default=ADHOC)'
                      ':default=YES)', config)
        self.assertLess(config.index('ENABLE_HARDENED_RUNTIME ='), config.index('#include? "Local.xcconfig"'))
        for local in ((root / 'Config/Local.xcconfig.example').read_text(),
                      local_signing.local_config(release_signing.POLICY['teamID'])):
            self.assertRegex(local, r'(?m)^ENABLE_HARDENED_RUNTIME = YES$')
        self.assertIn('ENABLE_HARDENED_RUNTIME=YES', release_signing.build_settings('0' * 40))
        self.assertTrue((root / 'scripts/verify-adhoc-launch.py').is_file())

    def test_local_signing_uses_pinned_team_only_when_its_certificate_is_installed(self):
        policy = release_signing.POLICY
        for listed, expected in ((policy['certificateSHA1'], 'pinned'), ('0' * 40, 'ad-hoc')):
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / 'scripts').mkdir()
                (root / 'scripts/release-signing.json').write_text(json.dumps(policy))
                result = subprocess.CompletedProcess([], 0, stdout=f'  1) {listed} "Apple Development: x"\n')
                state = local_signing.ensure_local_config(root, run=lambda *a, **k: result,
                                                          log=lambda _: None, environ={})
                self.assertEqual(state, expected)
                local = root / 'Config/Local.xcconfig'
                if expected == 'pinned':
                    self.assertIn(f"DEVELOPMENT_TEAM = {policy['teamID']}", local.read_text())
                    local.write_text('DEVELOPMENT_TEAM = OTHER\n')
                    self.assertEqual(local_signing.ensure_local_config(root, run=lambda *a, **k: result,
                                                                       log=lambda _: None, environ={}), 'existing')
                    self.assertEqual(local.read_text(), 'DEVELOPMENT_TEAM = OTHER\n')
                    local.unlink()
                    self.assertEqual(local_signing.ensure_local_config(
                        root, run=lambda *a, **k: result, log=lambda _: None,
                        environ={'AIRDRAFT_LOCAL_SIGNING': 'ad-hoc'}), 'ad-hoc')
                self.assertFalse(local.exists())

    def fake_xcodegen(self, root, version='2.46.0'):
        """A disposable XcodeGen tree whose binary prints the given version."""
        tree = root / 'xcodegen'
        (tree / 'bin').mkdir(parents=True)
        (tree / 'share/xcodegen/SettingPresets').mkdir(parents=True)
        (tree / 'share/xcodegen/SettingPresets/base.yml').write_text('fixture: true\n')
        binary = tree / 'bin/xcodegen'
        binary.write_text(f'#!/bin/sh\necho "Version: {version}"\n')
        binary.chmod(0o755)
        return binary

    def test_xcodegen_rejects_installed_copies_that_are_not_the_pinned_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pinned = self.fake_xcodegen(root / 'repo/dist/tools')
            other = self.fake_xcodegen(root / 'homebrew')
            (other.parents[1] / 'INSTALL_RECEIPT.json').write_text('{}')
            digest = release.xcodegen_tree_digest(pinned.parents[1])
            with patch.object(release, 'ROOT', root / 'repo'), \
                    patch.object(release, 'XCODEGEN_TREE_SHA256', digest), \
                    patch.object(release.shutil, 'which', return_value=str(other)), \
                    patch.object(release, 'run') as run:
                self.assertEqual(release.xcodegen(), pinned)
                run.assert_not_called()
            with patch.object(release, 'ROOT', root / 'repo'), \
                    patch.object(release, 'XCODEGEN_TREE_SHA256', digest), \
                    patch.object(release.shutil, 'which', return_value=str(pinned)):
                self.assertEqual(release.xcodegen(), pinned)
            # A pinned tree whose binary was swapped, or that reports another version, is refused.
            pinned.write_text('#!/bin/sh\necho "Version: 2.46.0"\n# tampered\n')
            with patch.object(release, 'ROOT', root / 'repo'), \
                    patch.object(release, 'XCODEGEN_TREE_SHA256', digest), \
                    patch.object(release.shutil, 'which', return_value=None):
                with self.assertRaisesRegex(RuntimeError, 'not the pinned XcodeGen'):
                    release.xcodegen()
            wrong = self.fake_xcodegen(root / 'wrong-version', version='2.45.0')
            with patch.object(release, 'XCODEGEN_TREE_SHA256', release.xcodegen_tree_digest(wrong.parents[1])):
                self.assertFalse(release.pinned_xcodegen(wrong))

    def test_xcodegen_download_requires_archive_checksum_and_tree_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def fake_run(*args, **kwargs):
                if args[0] == 'curl':
                    Path(args[args.index('--output') + 1]).write_bytes(b'not the release archive')
                elif args[0] == 'ditto':
                    self.fake_xcodegen(Path(args[-1]), version='9.9.9')

            with patch.object(release, 'ROOT', root), \
                    patch.object(release.shutil, 'which', return_value=None), \
                    patch.object(release, 'run', side_effect=fake_run) as run:
                with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                    release.xcodegen()
                curl = run.call_args_list[0].args
                self.assertIn('=https', curl)
                self.assertEqual(curl[-1], release.XCODEGEN_URL)
            archive = root / f'dist/tools/xcodegen-{release.XCODEGEN_VERSION}.zip'
            with patch.object(release, 'ROOT', root), \
                    patch.object(release, 'XCODEGEN_SHA256', release.sha256(archive)), \
                    patch.object(release.shutil, 'which', return_value=None), \
                    patch.object(release, 'run', side_effect=fake_run):
                with self.assertRaisesRegex(RuntimeError, 'tree digest or version'):
                    release.xcodegen()

    def test_xcodegen_pin_matches_ci(self):
        workflow = (Path(release.__file__).resolve().parents[1] / '.github/workflows/ci.yml').read_text()
        self.assertIn(release.XCODEGEN_URL, workflow)
        self.assertIn('release.pinned_xcodegen', workflow)
        self.assertIn(f'xcodegen-{release.XCODEGEN_VERSION}', workflow)

    def test_adhoc_negative_control_follows_measured_library_validation(self):
        self.assertEqual(adhoc.negative_control_decision('enforced', launched=False), 'refused')
        self.assertEqual(adhoc.negative_control_decision('not-enforced', launched=True), 'not-applicable')
        with self.assertRaisesRegex(RuntimeError, 'unexpectedly launched'):
            adhoc.negative_control_decision('enforced', launched=True)
        with self.assertRaisesRegex(RuntimeError, 'disagrees'):
            adhoc.negative_control_decision('not-enforced', launched=False)

    def test_library_validation_probe_classifies_dyld_outcomes(self):
        refusal = ("dyld[1]: Library not loaded: @rpath/libprobe.dylib ... mapping process and mapped "
                   "file (non-platform) have different Team IDs")
        cases = [((0, ''), (0, ''), 'not-enforced'), ((0, ''), (134, refusal), 'enforced'),
                 ((0, ''), (1, 'segmentation fault'), None), ((1, 'broken'), (0, ''), None)]
        for control, probe, expected in cases:
            def fake_run(command, **kwargs):
                name = Path(command[0]).name
                if name in ('control', 'probe'):
                    code, output = control if name == 'control' else probe
                    return subprocess.CompletedProcess(command, code, stdout='', stderr=output)
                return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
            with self.subTest(control=control, probe=probe), tempfile.TemporaryDirectory() as temporary, \
                    patch.object(adhoc.subprocess, 'run', side_effect=fake_run):
                if expected is None:
                    with self.assertRaises(RuntimeError):
                        adhoc.library_validation_probe(Path(temporary) / 'probe')
                else:
                    self.assertEqual(adhoc.library_validation_probe(Path(temporary) / 'probe')[0], expected)

    @unittest.skipUnless(shutil.which('xcrun') and shutil.which('codesign'), 'needs the Xcode toolchain')
    def test_library_validation_probe_runs_on_this_host(self):
        with tempfile.TemporaryDirectory() as temporary:
            status, outcomes = adhoc.library_validation_probe(Path(temporary) / 'probe')
        self.assertIn(status, ('enforced', 'not-enforced'))
        self.assertEqual(outcomes['control']['exit'], 0)

    def test_optional_insertion_matrix_feeds_the_gate_directory_and_records_a_summary(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            calls = []

            def fake_run(command, **kwargs):
                calls.append([str(part) for part in command])
                evidence = Path(command[command.index('--output') + 1])
                evidence.mkdir(parents=True)
                (evidence / 'matrix.json').write_text(json.dumps({'status': 'unverified', 'accessibilityTrusted': False,
                    'cases': [{'target': 'TextEdit', 'bundleID': 'com.apple.TextEdit', 'method': 'auto',
                               'expectation': 'confirmed', 'status': 'unverified', 'reason': 'no access',
                               'token': 'not recorded'}]}))
                return subprocess.CompletedProcess(command, 2)

            with patch.object(release.subprocess, 'run', side_effect=fake_run):
                summary = release.insertion_matrix(Path('/source'), output, Path('/Debug.app'), 'a' * 40)
            self.assertEqual(calls[0][calls[0].index('--gate-reports') + 1], str(output / 'insertion-e2e'))
            self.assertEqual(summary['status'], 'unverified')
            self.assertEqual(summary['commit'], 'a' * 40)
            self.assertNotIn('token', summary['cases'][0])
            with patch.object(release.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)):
                self.assertEqual(release.insertion_matrix(Path('/source'), output, Path('/Debug.app'), 'a' * 40)['status'],
                                 'failed')

    def test_bundled_acknowledgements_match_resolved_inputs(self):
        self.assertTrue(acknowledgements.check_inputs(Path(release.__file__).resolve().parents[1]))

if __name__ == '__main__':
    unittest.main()
