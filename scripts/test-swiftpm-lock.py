#!/usr/bin/env python3
"""Reject missing or drifted package pins at the generation/release boundary."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import swiftpm_lock


class SwiftPMLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.lock = {
            "version": 3, "originHash": "resolver-context",
            "pins": [{"identity": "example", "kind": "remoteSourceControl",
                      "location": "https://example.test/example.git",
                      "state": {"revision": "a" * 40, "version": "1.2.3"}}],
        }
        (self.root / "Package.resolved").write_text(json.dumps(self.lock))
        (self.root / "airdraft.xcodeproj").mkdir()
        (self.root / "airdraft.xcodeproj/project.pbxproj").write_text("fixture")

    def test_fresh_generation_restores_reviewed_resolution(self):
        path = swiftpm_lock.restore(self.root)
        self.assertEqual(path.read_bytes(), (self.root / "Package.resolved").read_bytes())
        self.assertEqual(swiftpm_lock.verify(self.root), path)

    def test_missing_resolution_or_project_fails(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid SwiftPM resolution"):
            swiftpm_lock.verify(self.root)
        (self.root / "Package.resolved").unlink()
        with self.assertRaisesRegex(RuntimeError, "Invalid SwiftPM resolution"):
            swiftpm_lock.restore(self.root)

    def test_drifted_revision_location_or_version_fails(self):
        for field in ("revision", "location", "version"):
            with self.subTest(field=field):
                path = swiftpm_lock.restore(self.root)
                value = json.loads(path.read_text())
                if field == "location":
                    value["pins"][0][field] = "https://example.test/other.git"
                else:
                    value["pins"][0]["state"][field] = "b" * 40 if field == "revision" else "1.2.4"
                path.write_text(json.dumps(value))
                with self.assertRaisesRegex(RuntimeError, "resolution changed"):
                    swiftpm_lock.verify(self.root)

    def test_resolver_context_does_not_change_package_identity(self):
        path = swiftpm_lock.restore(self.root)
        value = json.loads(path.read_text())
        value["originHash"] = "another-project-context"
        path.write_text(json.dumps(value))
        self.assertEqual(swiftpm_lock.verify(self.root), path)

    def test_invalid_and_duplicate_pins_are_rejected(self):
        canonical = self.root / "Package.resolved"
        for value in ({"version": 3, "pins": []}, {"version": 2, "pins": self.lock["pins"]},
                      self.lock | {"pins": self.lock["pins"] * 2}):
            with self.subTest(value=value):
                canonical.write_text(json.dumps(value))
                with self.assertRaises(RuntimeError):
                    swiftpm_lock.restore(self.root)

    def test_project_generator_restores_only_after_success(self):
        script = Path(__file__).with_name("generate-project.py")
        spec = importlib.util.spec_from_file_location("generate_project", script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.__file__ = str(self.root / "scripts/generate-project.py")
        generated = self.root / swiftpm_lock.GENERATED_LOCK
        with patch.object(module.shutil, "which", return_value="/fixture/xcodegen"), \
             patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            self.assertEqual(module.main(), 1)
            self.assertFalse(generated.exists())
        with patch.object(module.shutil, "which", return_value="/fixture/xcodegen"), \
             patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(module.main(), 0)
            swiftpm_lock.verify(self.root)


if __name__ == "__main__":
    unittest.main()
