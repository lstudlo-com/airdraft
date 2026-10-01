#!/usr/bin/env python3
"""Fault-injection tests for the vault rules, using a disposable fixture vault."""
from pathlib import Path
import tempfile
import unittest

from vault_check import check, parse_frontmatter

PRODUCT = """---
type: product
kind: feature
status: source-reviewed
verified_on: 2026-10-01
source_commit: 4af8f51fc2bc955ee3db03196923a5c39d79040e
---

# Feature

Current behavior. Related work: [[AD-001 Broken paste]].

## 來源

查核：2026-10-01 對照 `4af8f51`。
"""
ISSUE = """---
id: AD-001
type: issue
status: released
verification: partial
gaps:
  - "Zed"
area: "[[Product/Features/Feature]]"
source: user
opened: 2026-09-30
fixed_in: []
released_in: "[[Records/Releases/2026-10-01 Release 0.4.5 Build 95]]"
---

# AD-001 Broken paste

| 日期 | Commit | 版本 | 做了什麼 | 結果 |
|---|---|---|---|---|
| 2026-10-01 | `23d7a3c` | 0.4.5 | Fix | Works |
"""
RELEASE = """---
type: release
status: published
date: 2026-10-01
verification: partial
version: 0.4.5
build: "95"
source_commit: 1d80bbac9ce60d516bb2f9fb588bbec5c7616088
items: [AD-001]
---

# Release
"""


class VaultCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.vault = Path(self.temp.name)
        self.write("Home.md", "---\ntype: index\nstatus: maintained\n---\n\n![[Work/Work.base#進行中]]\n")
        self.write("Work/Work.base", "views: []\n")
        self.write("Product/Features/Feature.md", PRODUCT)
        self.write("Work/AD-001 Broken paste.md", ISSUE)
        self.write("Records/Releases/2026-10-01 Release 0.4.5 Build 95.md", RELEASE)
        self.write("Templates/Issue.md", "---\nid: AD-\nopened: \"{{date}}\"\n---\n[[Nowhere]]\n")

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, text):
        path = self.vault / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def errors(self):
        return [f for f in check(self.vault) if not f.warning]

    def assertFlags(self, fragment):
        messages = [str(f) for f in self.errors()]
        self.assertTrue(any(fragment in m for m in messages), f"{fragment!r} not in {messages}")

    def test_valid_fixture_passes(self):
        self.assertEqual(self.errors(), [])

    def test_frontmatter_lists_and_quotes(self):
        fm, error = parse_frontmatter(ISSUE)
        self.assertIsNone(error)
        self.assertEqual(fm["gaps"], ["Zed"])
        self.assertEqual(fm["fixed_in"], [])
        self.assertEqual(fm["area"], "[[Product/Features/Feature]]")
        self.assertEqual(parse_frontmatter(RELEASE)[0]["items"], ["AD-001"])

    def test_unknown_type_and_status(self):
        self.write("Product/Features/Feature.md", PRODUCT.replace("type: product", "type: feature"))
        self.assertFlags("type 'feature' is not one of")
        self.write("Product/Features/Feature.md", PRODUCT.replace("status: source-reviewed", "status: published-verified"))
        self.assertFlags("status 'published-verified'")

    def test_type_must_match_folder(self):
        self.write("Records/Releases/2026-09-29 Sandbox Check.md", "---\ntype: verification\nstatus: recorded\ndate: 2026-09-29\n---\n")
        self.assertFlags("does not belong in this folder")

    def test_required_fields_and_enums(self):
        self.write("Records/Releases/2026-10-01 Release 0.4.5 Build 95.md", RELEASE.replace("verification: partial\n", ""))
        self.assertFlags("missing verification")
        self.write("Records/Releases/2026-10-01 Release 0.4.5 Build 95.md", RELEASE.replace("verification: partial", "verification: done"))
        self.assertFlags("verification 'done'")

    def test_record_file_names_and_dates(self):
        self.write("Records/Decisions/Model Corrections.md", "---\ntype: decision\nstatus: adopted\ndate: 2026-09-28\n---\n")
        self.assertFlags("decision notes are named")
        self.write("Records/Releases/2026-10-01 Release 0.4.5 Build 95.md", RELEASE.replace("date: 2026-10-01", "date: 2026-09-30"))
        self.assertFlags("date does not match the file name")

    def test_work_rules(self):
        self.write("Work/AD-002 Duplicate.md", ISSUE.replace("# AD-001", "# AD-002"))
        self.assertFlags("does not match the file name")
        self.write("Work/AD-001 Broken paste.md", ISSUE.replace('released_in: "[[Records/Releases/2026-10-01 Release 0.4.5 Build 95]]"', 'released_in: ""'))
        self.assertFlags("released items need released_in")
        self.write("Work/AD-001 Broken paste.md", ISSUE.replace("verification: partial", "verification: verified"))
        self.assertFlags("verified items cannot list gaps")
        self.write("Work/Broken paste.md", ISSUE)
        self.assertFlags("Work notes are named")

    def test_dated_updates_in_state_notes(self):
        self.write("Product/Features/Feature.md", PRODUCT + "\n## 2026-10-02 修正\n\nAppended.\n")
        self.assertFlags("dated update")
        self.write("Product/Features/Feature.md", PRODUCT + "\n發布更新（2026-10-02）：appended.\n")
        self.assertFlags("dated update")
        self.write("Product/Features/Feature.md", PRODUCT + "\n2026-10-02: appended after the sources.\n")
        self.assertFlags("dated update")

    def test_dated_rows_allowed_in_work_and_records(self):
        self.write("Records/Releases/2026-10-01 Release 0.4.5 Build 95.md", RELEASE + "\n## 2026-10-01 Verification\n")
        self.assertEqual(self.errors(), [])

    def test_unresolved_links(self):
        self.write("Product/Features/Feature.md", PRODUCT + "\n[[Product/Features/Missing]] and [[Missing note|alias]]\n")
        messages = [str(f) for f in self.errors()]
        self.assertEqual(sum("unresolved link" in m for m in messages), 2)

    def test_links_in_code_are_ignored(self):
        self.write("Product/Features/Feature.md", PRODUCT + "\n`[[Not a link]]`\n\n```\n[[Also not]]\n```\n")
        self.assertEqual(self.errors(), [])

    def test_icloud_conflict_copy(self):
        self.write("Product/Features/Feature 2.md", PRODUCT)
        self.assertFlags("iCloud conflict copy")

    def test_large_file_is_warning_only(self):
        (self.vault / "Records/Evidence").mkdir(parents=True)
        with open(self.vault / "Records/Evidence/big.zip", "wb") as f:
            f.truncate(11 * 1024 * 1024)
        self.assertEqual(self.errors(), [])
        self.assertTrue(any(f.warning for f in check(self.vault)))


if __name__ == "__main__":
    unittest.main()
