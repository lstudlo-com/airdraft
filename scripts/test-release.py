#!/usr/bin/env python3
"""Release gates: push scope, source identity, and hostile/mismatched manifests."""
import importlib.util
from pathlib import Path
import unittest

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

if __name__ == '__main__':
    unittest.main()
