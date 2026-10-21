#!/usr/bin/env python3
"""Third-party notice generator: reviewed licenses only, and stale output fails."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import acknowledgements as ack

MIT = """MIT License

Copyright (c) 2026 Example

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
"""
APACHE_SHORT = 'Licensed under the Apache License, Version 2.0 (the "License").\n'
BSD3 = """Redistribution and use in source and binary forms, with or without modification,
are permitted. Neither the name of the copyright holder nor the names of its
contributors may be used to endorse or promote products derived from this software.
"""
ZLIB = """This software is provided 'as-is', without any express or implied warranty.
2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.
"""


def git(path, *args):
    subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True)


class Fixture:
    """A minimal repository plus SwiftPM checkout tree."""

    def __init__(self, base):
        self.root = base / "repo"
        self.packages = base / "SourcePackages"
        checkout = self.packages / "checkouts/Example"
        checkout.mkdir(parents=True)
        (checkout / "LICENSE").write_text(MIT)
        git(checkout, "init", "-q")
        git(checkout, "add", ".")
        git(checkout, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "init")
        revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        self.write("Package.resolved", json.dumps({"pins": [{
            "identity": "example", "kind": "remoteSourceControl",
            "location": "https://github.com/example/Example.git",
            "state": {"revision": revision, "version": "1.0.0"}}], "version": 3}))
        (self.packages / "workspace-state.json").write_text(json.dumps({"object": {"artifacts": []}}))
        self.write("Packages/SherpaOnnxKit/native-inputs.json", json.dumps(
            {"schema": 1, "libraries": [{"id": "native", "version": "2.0"}]}))
        self.write("Packages/TranscribeCppKit/Package.swift", "")
        self.write("Packages/AirdraftCore/Package.swift", "")
        self.write("docs/model-brand-assets.md", "| Asset | Source |\n|---|---|\n| Acme | [Acme](https://acme.test) |\n")
        (self.root / "Sources/App/Assets.xcassets/ModelBrandAcme.imageset").mkdir(parents=True)
        self.write("Sources/App/Resources/.keep", "")
        (self.root / "scripts").mkdir()
        shutil.copy2(Path(ack.__file__), self.root / "scripts/acknowledgements.py")
        self.write("ThirdParty/licenses/native/LICENSE", ZLIB)
        self.policy = {
            "schema": 1,
            "swiftpm": {"example": {"name": "Example", "license": "MIT", "files": {"LICENSE": "MIT"}}},
            "binaryTargets": {},
            "native": {"native": {"name": "Native", "version": "2.0", "license": "Zlib",
                                  "source": "https://native.test",
                                  "files": {"ThirdParty/licenses/native/LICENSE": "Zlib"}}},
            "texts": {"ThirdParty/licenses/native/LICENSE": {
                "url": "https://native.test/LICENSE",
                "sha256": hashlib.sha256(ZLIB.encode()).hexdigest()}},
        }
        self.save()

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def save(self):
        self.write("ThirdParty/acknowledgements.json", json.dumps(self.policy))

    def build(self):
        return ack.outputs(self.root, self.packages)


class DetectionTests(unittest.TestCase):
    def test_recognizes_common_license_texts(self):
        self.assertEqual(ack.detect(MIT), {"mit"})
        self.assertEqual(ack.detect(BSD3), {"bsd-3-clause"})
        self.assertEqual(ack.detect(BSD3.replace("Neither the name", "The name").replace("endorse or promote", "x")),
                         {"bsd-2-clause"})
        self.assertEqual(ack.detect(ZLIB), {"zlib"})
        self.assertEqual(ack.detect(APACHE_SHORT + "Runtime Library Exception"), {"apache-2.0", "swift-exception"})
        self.assertEqual(ack.detect("All rights reserved. Proprietary."), set())

    def test_expressions_map_to_kinds_and_reject_unknown_identifiers(self):
        self.assertEqual(ack.expected_kinds("Apache-2.0 WITH Swift-exception"), {"apache-2.0", "swift-exception"})
        self.assertEqual(ack.expected_kinds("Unlicense OR MIT"), {"unlicense", "mit"})
        with self.assertRaises(ack.AcknowledgementError):
            ack.expected_kinds("SSPL-1.0")

    def test_normalization_strips_bom_crlf_and_trailing_space(self):
        self.assertEqual(ack.normalize("﻿\r\nA  \r\nB\r\n\r\n".encode()), "A\nB\n")


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.fixture = Fixture(Path(self.temporary.name))

    def tearDown(self):
        self.temporary.cleanup()

    def assertFails(self, message):
        with self.assertRaisesRegex(ack.AcknowledgementError, message):
            self.fixture.build()

    def test_generates_notices_with_full_and_referenced_texts(self):
        text = self.fixture.build()[ack.OUTPUT.as_posix()]
        self.assertIn("Example 1.0.0", text)
        self.assertIn("Native 2.0", text)
        self.assertIn("Acme: Acme <https://acme.test>", text)
        self.assertIn(ack.FINGERPRINT_LINE + ack.fingerprint(self.fixture.root), text)

    def test_short_apache_notice_requires_a_preceding_full_text(self):
        self.fixture.write("ThirdParty/licenses/native/LICENSE", APACHE_SHORT)
        native = self.fixture.policy["native"]["native"]
        native["license"] = "Apache-2.0"
        native["files"]["ThirdParty/licenses/native/LICENSE"] = "Apache-2.0"
        self.fixture.policy["texts"]["ThirdParty/licenses/native/LICENSE"]["sha256"] = \
            hashlib.sha256(APACHE_SHORT.encode()).hexdigest()
        self.fixture.save()
        self.assertFails("needs a preceding full Apache-2.0 text")

    def test_new_pin_without_review_fails(self):
        del self.fixture.policy["swiftpm"]["example"]
        self.fixture.save()
        self.assertFails("New SwiftPM dependency example")

    def test_unrecognized_license_text_fails(self):
        (self.fixture.packages / "checkouts/Example/LICENSE").write_text("All rights reserved.\n")
        checkout = self.fixture.packages / "checkouts/Example"
        git(checkout, "commit", "-qam", "change", "--author", "t <t@example.com>")
        resolved = json.loads((self.fixture.root / "Package.resolved").read_text())
        resolved["pins"][0]["state"]["revision"] = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        self.fixture.write("Package.resolved", json.dumps(resolved))
        self.assertFails("Unknown license text")

    def test_license_that_differs_from_review_fails(self):
        self.fixture.policy["swiftpm"]["example"]["files"] = {"LICENSE": "BSD-3-Clause"}
        self.fixture.save()
        self.assertFails("policy records 'BSD-3-Clause'")

    def test_unreviewed_nested_license_fails_until_listed_or_excluded(self):
        nested = self.fixture.packages / "checkouts/Example/Vendor/zlib/LICENSE"
        nested.parent.mkdir(parents=True)
        nested.write_text(ZLIB)
        self.assertFails("unreviewed license file Vendor/zlib/LICENSE")
        self.fixture.policy["swiftpm"]["example"]["excluded"] = {"Vendor/": "not linked"}
        self.fixture.save()
        self.fixture.build()

    def test_checkout_must_match_the_pinned_revision(self):
        resolved = json.loads((self.fixture.root / "Package.resolved").read_text())
        resolved["pins"][0]["state"]["revision"] = "0" * 40
        self.fixture.write("Package.resolved", json.dumps(resolved))
        self.assertFails("not at the pinned revision")

    def test_native_version_change_requires_new_texts(self):
        self.fixture.write("Packages/SherpaOnnxKit/native-inputs.json", json.dumps(
            {"schema": 1, "libraries": [{"id": "native", "version": "2.1"}]}))
        self.assertFails("Native input native is now 2.1")

    def test_committed_text_is_bound_to_its_recorded_digest(self):
        self.fixture.write("ThirdParty/licenses/native/LICENSE", APACHE_SHORT + "edited\n")
        self.assertFails("differs from its recorded upstream text")

    def test_brand_assets_must_match_their_source_table(self):
        (self.fixture.root / "Sources/App/Assets.xcassets/ModelBrandOther.imageset").mkdir()
        self.assertFails("undocumented \\['Other'\\]")

    def test_unknown_binary_target_fails(self):
        (self.fixture.packages / "workspace-state.json").write_text(json.dumps({"object": {"artifacts": [
            {"packageRef": {"identity": "example"}, "targetName": "Blob",
             "source": {"type": "remote", "url": "https://example.test/blob.zip"}}]}}))
        self.assertFails("New binary target example/Blob")

    def test_fingerprint_detects_changed_resolution_without_checkouts(self):
        root = self.fixture.root
        for relative, text in self.fixture.build().items():
            (root / relative).write_text(text)
        self.assertTrue(ack.check_inputs(root))
        resolved = json.loads((root / "Package.resolved").read_text())
        resolved["pins"][0]["state"]["version"] = "1.0.1"
        self.fixture.write("Package.resolved", json.dumps(resolved))
        with self.assertRaisesRegex(ack.AcknowledgementError, "stale"):
            ack.check_inputs(root)


class RepositoryTests(unittest.TestCase):
    def test_committed_notices_match_the_committed_inputs(self):
        self.assertTrue(ack.check_inputs(ack.ROOT))

    def test_every_committed_text_has_a_pinned_https_source(self):
        policy = json.loads((ack.ROOT / ack.POLICY).read_text())
        for relative, record in policy["texts"].items():
            self.assertTrue(record["url"].startswith("https://"), relative)
            self.assertNotIn("/main/", record["url"], relative)
            self.assertNotIn("/master/", record["url"], relative)


if __name__ == "__main__":
    unittest.main()
