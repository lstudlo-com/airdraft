#!/usr/bin/env python3
"""Offline native input integrity and publication regressions; no Xcode invocation."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock
from urllib.parse import urlsplit
import zipfile

import native_inputs


class NativeInputsTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="airdraft-native-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.vendor = self.root / "Vendor"
        self.archives = self.root / "archives"
        self.archives.mkdir()
        self.inputs = copy.deepcopy(native_inputs.load_inputs())
        for item in self.inputs["libraries"]:
            archive = self.archives / Path(urlsplit(item["url"]).path).name
            with zipfile.ZipFile(archive, "w") as output:
                prefix = f"bundle-macos/{item['id']}.framework/Versions/A/"
                output.writestr(prefix + item["id"], b"harmless static-library fixture")
                if item["id"] == "SherpaOnnxC":
                    output.writestr(prefix + "Headers/sherpa-onnx/c-api/c-api.h", b"/* harmless header */")
            item["sha256"] = native_inputs.digest(archive)
        self.metadata = self.root / "native-inputs.json"
        self.metadata.write_text(json.dumps(self.inputs))
        self.real_run = subprocess.run

    def fake_xcode(self, command, **kwargs):
        if command[0] != "xcodebuild":
            return self.real_run(command, **kwargs)
        output = Path(command[command.index("-output") + 1])
        library = Path(command[command.index("-library") + 1])
        architecture = output / "macos-arm64_x86_64"
        architecture.mkdir(parents=True)
        shutil.copyfile(library, architecture / library.name)
        (output / "Info.plist").write_text("harmless plist fixture")
        if "-headers" in command:
            shutil.copytree(command[command.index("-headers") + 1], architecture / "Headers")
        return subprocess.CompletedProcess(command, 0)

    def prepare(self):
        with mock.patch.object(native_inputs.subprocess, "run", side_effect=self.fake_xcode):
            return native_inputs.prepare_vendor(self.vendor, self.archives, self.metadata)

    def test_verified_archives_produce_a_verifiable_deterministic_manifest(self):
        first = self.prepare()
        second = self.prepare()
        self.assertEqual(first, second)
        self.assertEqual(native_inputs.verify_vendor(self.vendor, self.metadata), first)
        self.assertEqual(first["inputs"], self.inputs)

    def test_corrupt_either_archive_fails_before_extraction_and_preserves_previous_tree(self):
        for index in range(2):
            with self.subTest(index=index):
                self.prepare()
                before = native_inputs.file_digests(self.vendor)
                archive = self.archives / Path(urlsplit(self.inputs["libraries"][index]["url"]).path).name
                good = archive.read_bytes()
                archive.write_bytes(b"corrupt archive fixture")
                try:
                    with mock.patch.object(native_inputs.subprocess, "run") as command:
                        with self.assertRaisesRegex(ValueError, "integrity"):
                            native_inputs.prepare_vendor(self.vendor, self.archives, self.metadata)
                        command.assert_not_called()
                    self.assertEqual(before, native_inputs.file_digests(self.vendor))
                finally:
                    archive.write_bytes(good)

    def test_missing_changed_and_extra_derived_files_fail(self):
        for mutation in ["missing", "changed", "extra"]:
            with self.subTest(mutation=mutation):
                manifest = self.prepare()
                target = self.vendor / next(name for name in manifest["files"] if name.endswith(".a"))
                if mutation == "missing":
                    target.unlink()
                elif mutation == "changed":
                    target.write_bytes(b"different library")
                else:
                    (self.vendor / "unexpected.a").write_bytes(b"extra")
                with self.assertRaises(ValueError):
                    native_inputs.verify_vendor(self.vendor, self.metadata)

    def test_missing_manifest_wrong_input_identity_and_stale_recipe_fail(self):
        for mutation in ["missing", "identity", "recipe"]:
            with self.subTest(mutation=mutation):
                self.prepare()
                path = self.vendor / native_inputs.MANIFEST
                manifest = json.loads(path.read_text())
                if mutation == "missing":
                    path.unlink()
                else:
                    if mutation == "identity":
                        manifest["inputs"]["libraries"][0]["version"] = "different"
                    else:
                        manifest["recipe_sha256"] = "0" * 64
                    path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    native_inputs.verify_vendor(self.vendor, self.metadata)

    def test_repackaging_failure_preserves_the_last_good_tree(self):
        self.prepare()
        before = native_inputs.file_digests(self.vendor)

        def fail_xcode(command, **kwargs):
            if command[0] == "xcodebuild":
                raise subprocess.CalledProcessError(1, command)
            return self.real_run(command, **kwargs)

        with mock.patch.object(native_inputs.subprocess, "run", side_effect=fail_xcode):
            with self.assertRaises(subprocess.CalledProcessError):
                native_inputs.prepare_vendor(self.vendor, self.archives, self.metadata)
        self.assertEqual(before, native_inputs.file_digests(self.vendor))
        native_inputs.verify_vendor(self.vendor, self.metadata)

    def test_replacing_vendor_symlink_never_changes_its_target(self):
        original = self.root / "original"
        original.mkdir()
        (original / "sentinel").write_bytes(b"original vendor remains untouched")
        self.vendor.symlink_to(original, target_is_directory=True)
        self.prepare()
        self.assertFalse(self.vendor.is_symlink())
        self.assertEqual(list(original.iterdir()), [original / "sentinel"])
        self.assertEqual((original / "sentinel").read_bytes(), b"original vendor remains untouched")
        native_inputs.verify_vendor(self.vendor, self.metadata)

    def test_failed_publication_restores_previous_directory_entry(self):
        self.vendor.mkdir()
        (self.vendor / "sentinel").write_bytes(b"previous")
        prepared = self.root / "prepared"
        prepared.mkdir()
        real_replace = os.replace

        def fail_publication(source, destination):
            if Path(source) == prepared:
                raise OSError("fixture publication failure")
            return real_replace(source, destination)

        with mock.patch.object(native_inputs.os, "replace", side_effect=fail_publication):
            with self.assertRaisesRegex(OSError, "publication failure"):
                native_inputs.publish_vendor(prepared, self.vendor)
        self.assertEqual((self.vendor / "sentinel").read_bytes(), b"previous")
        self.assertEqual(list(self.root.glob(".Vendor.previous-*")), [])

    def test_derived_symlinks_are_rejected(self):
        self.prepare()
        (self.vendor / "link").symlink_to(self.metadata)
        with self.assertRaisesRegex(ValueError, "symlink"):
            native_inputs.verify_vendor(self.vendor, self.metadata)


if __name__ == "__main__":
    unittest.main()
