#!/usr/bin/env python3
"""Tests for parallel_work.py against disposable git repositories with worktrees."""
from contextlib import redirect_stdout
from pathlib import Path
import io
import json
import subprocess
import tempfile
import unittest

import parallel_work


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


class ParallelWorkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        base = Path(self.temporary.name)
        self.main = base / "repo"
        self.main.mkdir()
        run("git", "init", "-q", "-b", "main", cwd=self.main)
        run("git", "config", "user.email", "test@example.com", cwd=self.main)
        run("git", "config", "user.name", "Test", cwd=self.main)
        (self.main / "apps/site").mkdir(parents=True)
        (self.main / "apps/site/page.txt").write_text("one\n")
        (self.main / "Sources").mkdir()
        (self.main / "Sources/App.swift").write_text("// app\n")
        run("git", "add", ".", cwd=self.main)
        run("git", "commit", "-q", "-m", "init", cwd=self.main)
        self.other = base / "other"
        run("git", "worktree", "add", "-q", "-b", "claude/web", str(self.other), cwd=self.main)

    def tearDown(self):
        self.temporary.cleanup()

    def status(self, *argv, root=None):
        output = io.StringIO()
        with redirect_stdout(output):
            code = parallel_work.main(["status", "--json", *argv], root=root or self.main)
        return code, json.loads(output.getvalue())

    def test_clean_repository_has_no_overlap(self):
        code, report = self.status("--paths", "apps/site")
        self.assertEqual(code, 0)
        self.assertEqual(report["overlaps"], [])
        self.assertEqual(len(report["worktrees"]), 2)

    def test_uncommitted_change_in_another_worktree_overlaps(self):
        (self.other / "apps/site/page.txt").write_text("two\n")
        code, report = self.status("--paths", "apps/site")
        self.assertEqual(code, 2)
        self.assertIn("apps/site/page.txt", [o["file"] for o in report["overlaps"]])
        code, _ = self.status("--paths", "Sources")
        self.assertEqual(code, 0, "Unrelated paths must not overlap")

    def test_finished_unmerged_branch_overlaps_and_blocks_release(self):
        (self.other / "apps/site/page.txt").write_text("two\n")
        run("git", "commit", "-q", "-am", "web", cwd=self.other)
        code, report = self.status("--paths", "apps")
        self.assertEqual(code, 2)
        self.assertEqual(report["unmerged"][0]["branch"], "claude/web")
        code, report = self.status("--release")
        self.assertEqual(code, 2)
        self.assertEqual(report["releaseBlockers"], ["claude/web"])

    def test_parked_branch_does_not_block_release(self):
        (self.other / "apps/site/page.txt").write_text("two\n")
        run("git", "commit", "-q", "-am", "web", cwd=self.other)
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-1", "--branch", "claude/web", "--parked"], root=self.other)
        code, report = self.status("--release")
        self.assertEqual(code, 0)
        self.assertTrue(report["unmerged"][0]["parked"])
        code, report = self.status("--paths", "apps/site")
        self.assertEqual(code, 0, "A parked branch informs but never blocks new work")
        self.assertEqual([o["file"] for o in report["parkedOverlaps"]], ["apps/site/page.txt"])

    def test_claims_are_shared_between_worktrees_and_released(self):
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-2", "--paths", "apps/site", "--note", "copy"], root=self.other)
        code, report = self.status("--paths", "apps/site/page.txt")
        self.assertEqual(code, 2, "A claim from another worktree must be visible here")
        self.assertEqual(report["claims"][0]["task"], "AD-2")
        code, _ = self.status("--paths", "apps/site", root=self.other)
        self.assertEqual(code, 0, "Your own claim is not an overlap")
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["release", "AD-2"], root=self.main)
        code, report = self.status("--paths", "apps/site")
        self.assertEqual((code, report["claims"]), (0, []))

    def test_claim_for_a_removed_worktree_is_stale(self):
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-3", "--paths", "apps/site"], root=self.other)
        run("git", "worktree", "remove", "--force", str(self.other), cwd=self.main)
        code, report = self.status("--paths", "apps/site")
        self.assertEqual(code, 0, "A stale claim must not block")
        self.assertTrue(report["claims"][0]["stale"])

    def test_claim_for_another_branch_belongs_to_its_worktree(self):
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-4", "--branch", "claude/web", "--paths", "apps"], root=self.main)
            parallel_work.main(["claim", "AD-5", "--branch", "wip/none", "--parked"], root=self.main)
        claims = {c["task"]: c for c in parallel_work.load_claims(self.main)}
        self.assertEqual(Path(claims["AD-4"]["worktree"]), self.other.resolve())
        self.assertEqual(claims["AD-5"]["worktree"], "")

    def cleanup(self, *argv, root=None):
        output = io.StringIO()
        with redirect_stdout(output):
            parallel_work.main(["cleanup", "--idle-hours", "0", *argv], root=root or self.main)
        return output.getvalue()

    def test_cleanup_removes_merged_clean_worktree_and_keeps_its_evidence(self):
        (self.other / "dist/validation/run").mkdir(parents=True)
        (self.other / "dist/validation/run/result.json").write_text("{}")
        report = self.cleanup()
        self.assertIn("Would remove worktree", report)
        self.assertTrue(self.other.exists(), "Dry run must not remove anything")
        self.cleanup("--apply")
        self.assertFalse(self.other.exists())
        branches = subprocess.run(["git", "branch"], cwd=self.main, capture_output=True, text=True).stdout
        self.assertNotIn("claude/web", branches)
        self.assertTrue((self.main / "dist/validation/other/run/result.json").exists())

    def test_cleanup_deletes_a_branch_merged_locally_but_not_pushed(self):
        remote = Path(self.temporary.name) / "remote.git"
        run("git", "init", "-q", "--bare", str(remote), cwd=self.main)
        run("git", "remote", "add", "origin", str(remote), cwd=self.main)
        run("git", "push", "-q", "-u", "origin", "main", cwd=self.main)
        (self.other / "apps/site/page.txt").write_text("two\n")
        run("git", "commit", "-q", "-am", "web", cwd=self.other)
        run("git", "merge", "-q", "--ff-only", "claude/web", cwd=self.main)
        self.cleanup("--apply")
        branches = subprocess.run(["git", "branch"], cwd=self.main, capture_output=True, text=True).stdout
        self.assertNotIn("claude/web", branches)

    def test_cleanup_keeps_unmerged_dirty_claimed_and_recent_work(self):
        (self.other / "apps/site/page.txt").write_text("two\n")
        self.assertIn("uncommitted", self.cleanup("--apply"))
        run("git", "commit", "-q", "-am", "web", cwd=self.other)
        self.assertIn("commits not on main", self.cleanup("--apply"))
        self.assertTrue(self.other.exists())
        third = Path(self.temporary.name) / "third"
        run("git", "worktree", "add", "-q", "-b", "claude/new", str(third), cwd=self.main)
        output = io.StringIO()
        with redirect_stdout(output):
            parallel_work.main(["cleanup", "--apply"], root=self.main)
        self.assertTrue(third.exists(), "A freshly created worktree belongs to a session that just started")
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-9", "--branch", "claude/new"], root=self.main)
        self.assertIn("claimed", self.cleanup("--apply"))
        self.assertTrue(third.exists())

    def test_cleanup_drops_claims_for_merged_or_missing_branches(self):
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-7", "--branch", "claude/gone"], root=self.main)
            parallel_work.main(["claim", "AD-8", "--branch", "claude/web", "--parked"], root=self.main)
        run("git", "branch", "claude/merged", cwd=self.main)
        with redirect_stdout(io.StringIO()):
            parallel_work.main(["claim", "AD-6", "--branch", "claude/merged"], root=self.main)
        self.cleanup("--apply")
        tasks = {c["task"] for c in parallel_work.load_claims(self.main)}
        self.assertNotIn("AD-7", tasks)
        self.assertNotIn("AD-6", tasks)

    def test_overlap_matches_parents_and_children(self):
        self.assertEqual(parallel_work.overlaps(["apps"], ["apps/site/page.txt"]), ["apps/site/page.txt"])
        self.assertEqual(parallel_work.overlaps(["apps/site/page.txt"], ["apps/site"]), ["apps/site"])
        self.assertEqual(parallel_work.overlaps(["apps/site"], ["apps/sitemap.txt"]), [])


if __name__ == "__main__":
    unittest.main()
