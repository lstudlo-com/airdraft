#!/usr/bin/env python3
"""Release gates: push scope, source identity, and hostile/mismatched manifests."""
import importlib.util
from pathlib import Path
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

    def manifest(self):
        return {'commit': 'a' * 40, 'tag': 'v0.1.1-build.3', 'version': '0.1.1', 'build': 3,
                'signing': dict(release_signing.POLICY),
                'sha256': {'Airdraft-0.1.1-3-arm64.dmg': 'b' * 64, 'appcast.xml': 'c' * 64}}

    def test_manifest_binds_archive_to_commit(self):
        self.assertEqual(release.validate_manifest(self.manifest(), 'a' * 40, 'v0.1.1-build.3'), 'Airdraft-0.1.1-3-arm64.dmg')
        with self.assertRaises(RuntimeError):
            release.validate_manifest(self.manifest(), 'd' * 40, 'v0.1.1-build.3')

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

    def test_ad_hoc_signature_is_rejected_before_packaging(self):
        with patch.object(release_signing, 'command') as command:
            command.return_value.stderr = b'Signature=adhoc\nTeamIdentifier=not set\n'
            with self.assertRaisesRegex(RuntimeError, 'ad-hoc release'):
                release_signing.inspect_app(Path('fixture.app'))

if __name__ == '__main__':
    unittest.main()
