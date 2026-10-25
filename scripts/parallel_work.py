#!/usr/bin/env python3
"""See and claim parallel work before changing files, merging or releasing.

Several sessions and agents work on Airdraft at once, each in its own worktree.
Work collides when one starts on files another has changed but not merged, or
when finished work stays on a branch and a release or deploy ships main without
it. This tool makes that state visible from any checkout:

  status   Every worktree (branch, ahead/behind main, uncommitted files), every
           local branch with commits main does not have, and the active claims.
           `--paths P...` lists the paths you are about to change and fails
           (exit 2) when another worktree, unmerged branch or claim touches
           them. `--release` fails while any branch other than this one holds
           unmerged commits that are not parked.
  claim    Record a task's branch and paths so other sessions see them:
           `claim AD-123 --paths apps/marketing --branch claude/topic`.
           `--parked` marks long-lived work (wip/...) that releases may skip.
  release  Remove a task's claim once its branch is merged (or abandoned).
  cleanup  List what is safe to tidy: worktrees and local branches already
           merged into main with nothing uncommitted, missing worktrees, claims
           whose branch is merged or gone, and (`--remote`) merged branches on
           origin. `--apply` removes them, first copying each removed worktree's
           dist/validation and dist/releases evidence into the main folder's
           dist/ without overwriting. Unmerged work is never removed; it is
           listed to merge or park. Run it at the start and end of every task.

Claims live in the repository's common git directory, shared by every worktree
and never committed. Uses local refs only unless `--fetch` is given.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLAIMS_NAME = "airdraft-claims.json"


def git(*args: str, cwd: Path | None = None, check: bool = False) -> str | None:
    result = subprocess.run(["git", "-C", str(cwd or ROOT), *args], capture_output=True, text=True)
    if result.returncode != 0:
        if check:
            raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
        return None
    # Keep leading spaces: `git status --porcelain` encodes state in column one.
    return result.stdout.rstrip()


def common_dir(root: Path = ROOT) -> Path:
    value = git("rev-parse", "--git-common-dir", cwd=root, check=True)
    path = Path(value)
    return path if path.is_absolute() else (root / path).resolve()


def claims_path(root: Path = ROOT) -> Path:
    return common_dir(root) / CLAIMS_NAME


def load_claims(root: Path = ROOT) -> list[dict]:
    path = claims_path(root)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    return data if isinstance(data, list) else []


def save_claims(claims: list[dict], root: Path = ROOT) -> None:
    path = claims_path(root)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(claims, indent=2, ensure_ascii=False) + "\n")
    os.replace(temporary, path)


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def worktrees(root: Path = ROOT) -> list[dict]:
    output = git("worktree", "list", "--porcelain", cwd=root, check=True) or ""
    entries, current = [], {}
    for line in output.splitlines() + [""]:
        if not line:
            if current:
                entries.append(current)
            current = {}
            continue
        key, _, value = line.partition(" ")
        if key == "worktree":
            current["path"] = value
        elif key == "branch":
            current["branch"] = value.removeprefix("refs/heads/")
        elif key == "HEAD":
            current["head"] = value
        elif key == "detached":
            current["branch"] = None
    return entries


def dirty_files(path: str) -> list[str]:
    """Tracked files with uncommitted changes, plus untracked files outside ignored paths."""
    output = git("status", "--porcelain", "--untracked-files=normal", cwd=Path(path)) or ""
    files = []
    for line in output.splitlines():
        name = line[3:].split(" -> ")[-1].strip().strip('"')
        if name.startswith(("dist/", ".claude/", ".impeccable/")):
            continue
        files.append(name)
    return files


def unmerged_branches(base: str, root: Path = ROOT) -> list[dict]:
    output = git("for-each-ref", "--format=%(refname:short)", "refs/heads/", cwd=root) or ""
    branches = []
    for name in output.splitlines():
        if name == base:
            continue
        ahead = git("rev-list", "--count", f"{base}..{name}", cwd=root)
        if not ahead or int(ahead) == 0:
            continue
        behind = git("rev-list", "--count", f"{name}..{base}", cwd=root) or "0"
        files = (git("diff", "--name-only", f"{base}...{name}", cwd=root) or "").splitlines()
        last = git("log", "-1", "--format=%cs %s", name, cwd=root) or ""
        branches.append({"branch": name, "ahead": int(ahead), "behind": int(behind),
                         "files": files, "last": last})
    return branches


def overlaps(paths: list[str], files: list[str]) -> list[str]:
    """Files under any of `paths` (a path matches itself and everything below it)."""
    def norm(value: str) -> str:
        return value.strip("/")
    wanted = [norm(p) for p in paths if norm(p)]
    hits = []
    for name in files:
        clean = norm(name)
        if any(clean == p or clean.startswith(p + "/") or p.startswith(clean + "/") for p in wanted):
            hits.append(name)
    return hits


def current_branch(root: Path = ROOT) -> str | None:
    return git("symbolic-ref", "--short", "-q", "HEAD", cwd=root)


def status(args, root: Path = ROOT) -> int:
    if args.fetch:
        git("fetch", "-q", "origin", cwd=root)
    base = args.base
    here = current_branch(root)
    here_path = str(Path(git("rev-parse", "--show-toplevel", cwd=root) or root).resolve())
    report = {"base": base, "here": here, "worktrees": [], "unmerged": [], "claims": [], "overlaps": [],
              "releaseBlockers": []}
    claims = load_claims(root)
    claimed = {c.get("branch"): c for c in claims if c.get("branch")}
    live_paths = set()

    for tree in worktrees(root):
        path = str(Path(tree["path"]).resolve())
        live_paths.add(path)
        if not Path(path).exists():
            continue
        branch = tree.get("branch")
        dirty = dirty_files(path)
        entry = {"path": path, "branch": branch, "dirty": dirty, "self": path == here_path}
        if branch:
            entry["ahead"] = int(git("rev-list", "--count", f"{base}..{branch}", cwd=root) or 0)
            entry["behind"] = int(git("rev-list", "--count", f"{branch}..{base}", cwd=root) or 0)
        report["worktrees"].append(entry)
        if args.paths and not entry["self"]:
            for name in overlaps(args.paths, dirty):
                report["overlaps"].append({"source": f"uncommitted in {path} [{branch}]", "file": name})

    for branch in unmerged_branches(base, root):
        claim = claimed.get(branch["branch"])
        branch["parked"] = bool(claim and claim.get("parked"))
        branch["task"] = claim.get("task") if claim else None
        report["unmerged"].append(branch)
        if branch["branch"] == here:
            continue
        if args.paths:
            # A parked branch is set aside on purpose: whoever resumes it rebases,
            # so it informs but never blocks new work.
            target = "parkedOverlaps" if branch["parked"] else "overlaps"
            for name in overlaps(args.paths, branch["files"]):
                report.setdefault(target, []).append({"source": f"unmerged branch {branch['branch']}", "file": name})
        if not branch["parked"]:
            report["releaseBlockers"].append(branch["branch"])

    for claim in claims:
        stale = bool(claim.get("worktree")) and str(Path(claim["worktree"]).resolve()) not in live_paths
        entry = dict(claim, stale=stale)
        report["claims"].append(entry)
        if args.paths and claim.get("branch") != here and not stale:
            for name in overlaps(args.paths, claim.get("paths", [])):
                report["overlaps"].append({"source": f"claim {claim.get('task')} [{claim.get('branch')}]",
                                           "file": name})

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print_report(report, args)
    if report["overlaps"]:
        return 2
    if args.release and report["releaseBlockers"]:
        return 2
    return 0


def print_report(report: dict, args) -> None:
    print(f"Base {report['base']}; this checkout is on {report['here'] or 'a detached HEAD'}.")
    print("\nWorktrees:")
    for tree in report["worktrees"]:
        mark = " (this checkout)" if tree["self"] else ""
        counts = f"ahead {tree.get('ahead', 0)}, behind {tree.get('behind', 0)}" if tree["branch"] else "detached"
        print(f"  {tree['path']} [{tree['branch']}] {counts}, {len(tree['dirty'])} uncommitted{mark}")
        for name in tree["dirty"][:12]:
            print(f"      {name}")
        if len(tree["dirty"]) > 12:
            print(f"      … {len(tree['dirty']) - 12} more")
    print("\nBranches with commits not on base:")
    if not report["unmerged"]:
        print("  none")
    for branch in report["unmerged"]:
        areas = sorted({name.split("/")[0] if "/" not in name else "/".join(name.split("/")[:2])
                        for name in branch["files"]})
        tag = " parked" if branch["parked"] else ""
        task = f" {branch['task']}" if branch["task"] else ""
        print(f"  {branch['branch']}{task}{tag}: {branch['ahead']} ahead, {branch['behind']} behind; "
              f"last {branch['last']}")
        print(f"      touches {', '.join(areas[:8])}{' …' if len(areas) > 8 else ''}")
    print("\nClaims:")
    if not report["claims"]:
        print("  none")
    for claim in report["claims"]:
        flags = " parked" if claim.get("parked") else ""
        flags += " STALE (worktree gone)" if claim["stale"] else ""
        print(f"  {claim.get('task')} [{claim.get('branch')}]{flags}: {', '.join(claim.get('paths', []))}"
              f" (updated {claim.get('updated')}){' — ' + claim['note'] if claim.get('note') else ''}")
    if args.paths:
        print(f"\nOverlap with {', '.join(args.paths)}:")
        if not report["overlaps"]:
            print("  none — safe to start")
        for item in report["overlaps"]:
            print(f"  OVERLAP {item['file']} ← {item['source']}")
        for item in report.get("parkedOverlaps", []):
            print(f"  parked  {item['file']} ← {item['source']} (informational)")
    if args.release:
        print("\nRelease check:")
        if not report["releaseBlockers"]:
            print("  no unmerged, unparked branches")
        for name in report["releaseBlockers"]:
            print(f"  BLOCKER {name} has commits not on {report['base']}: merge it first, "
                  "or park it with `claim TASK --branch NAME --parked`")


def claim(args, root: Path = ROOT) -> int:
    claims = [c for c in load_claims(root) if c.get("task") != args.task]
    existing = next((c for c in load_claims(root) if c.get("task") == args.task), {})
    branch = args.branch or current_branch(root)
    # The claim belongs to the worktree that holds the branch, wherever it is
    # made from; a branch without a worktree has none, so it never goes stale.
    holder = next((t["path"] for t in worktrees(root) if t.get("branch") == branch), "")
    entry = {
        "task": args.task,
        "branch": branch,
        "worktree": str(Path(holder).resolve()) if holder else "",
        "paths": sorted(set(args.paths or existing.get("paths", []))),
        "parked": bool(args.parked),
        "note": args.note or existing.get("note", ""),
        "created": existing.get("created", now()),
        "updated": now(),
    }
    claims.append(entry)
    save_claims(claims, root)
    print(f"Claimed {entry['task']} on {entry['branch']}: {', '.join(entry['paths']) or '(no paths)'}"
          f"{' (parked)' if entry['parked'] else ''}")
    return 0


def release_claim(args, root: Path = ROOT) -> int:
    claims = load_claims(root)
    kept = [c for c in claims if c.get("task") != args.task]
    save_claims(kept, root)
    print(f"Released {args.task}" if len(kept) != len(claims) else f"No claim for {args.task}")
    return 0


def primary_worktree(root: Path = ROOT) -> Path:
    """The main folder: the worktree whose git dir is the common dir."""
    return common_dir(root).parent


def merged(branch: str, base: str, root: Path) -> bool:
    return git("merge-base", "--is-ancestor", branch, base, cwd=root) is not None


def cleanup_plan(args, root: Path = ROOT) -> dict:
    base = args.base
    primary = str(primary_worktree(root).resolve())
    here = str(Path(git("rev-parse", "--show-toplevel", cwd=root) or root).resolve())
    claims = load_claims(root)
    active = {c.get("branch") for c in claims}
    plan = {"worktrees": [], "prune": False, "branches": [], "claims": [], "remote": [], "keep": []}
    held = set()
    for tree in worktrees(root):
        path = str(Path(tree["path"]).resolve())
        branch = tree.get("branch")
        if branch:
            held.add(branch)
        if not Path(path).exists():
            plan["prune"] = True
            continue
        if path in (primary, here):
            continue
        ref = branch or tree.get("head")
        dirty = dirty_files(path)
        if branch in active:
            plan["keep"].append(f"worktree {path} [{branch}]: claimed")
        elif recently_active(path, args.idle_hours):
            # A worktree a session just created has no commits yet and looks
            # merged; leave anything touched recently to its owner.
            plan["keep"].append(f"worktree {path} [{branch}]: active in the last {args.idle_hours:g} h")
        elif dirty:
            plan["keep"].append(f"worktree {path} [{branch}]: {len(dirty)} uncommitted file(s)")
        elif ref and merged(ref, base, root):
            plan["worktrees"].append({"path": path, "branch": branch})
        else:
            plan["keep"].append(f"worktree {path} [{branch}]: commits not on {base} — merge or park")
    removing = {t["branch"] for t in plan["worktrees"] if t["branch"]}
    output = git("for-each-ref", "--format=%(refname:short)", "refs/heads/", cwd=root) or ""
    for name in output.splitlines():
        if name == base or name == current_branch(root) or (name in held and name not in removing):
            continue
        if merged(name, base, root):
            plan["branches"].append(name)
        elif name not in held:
            parked = any(c.get("branch") == name and c.get("parked") for c in claims)
            plan["keep"].append(f"branch {name}: " + ("parked" if parked else f"commits not on {base} — merge or park"))
    gone = set(plan["branches"]) | {t["branch"] for t in plan["worktrees"] if t["branch"]}
    for claim in claims:
        branch = claim.get("branch")
        exists = bool(branch) and git("rev-parse", "-q", "--verify", f"refs/heads/{branch}", cwd=root) is not None
        stale = bool(claim.get("worktree")) and not Path(claim["worktree"]).exists()
        done = (exists and not claim.get("parked") and branch not in held and merged(branch, base, root))
        if branch in gone or (branch and not exists) or stale or done:
            plan["claims"].append(claim.get("task"))
    if args.remote:
        remote = git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin/", cwd=root) or ""
        for name in remote.splitlines():
            short = name.removeprefix("origin/")
            if short in ("HEAD", base, "origin") or short in active:
                continue
            if merged(name, f"origin/{base}", root):
                plan["remote"].append(short)
    return plan


def recently_active(path: str, hours: float) -> bool:
    gitdir = git("rev-parse", "--absolute-git-dir", cwd=Path(path))
    if not gitdir:
        return False
    newest = max((Path(gitdir, name).stat().st_mtime for name in ("index", "HEAD", "logs/HEAD")
                  if Path(gitdir, name).exists()), default=0)
    return (datetime.now().timestamp() - newest) < hours * 3600


def move_evidence(worktree: Path, primary: Path) -> list[str]:
    moved = []
    for sub in ("validation", "releases"):
        source = worktree / "dist" / sub
        if source.is_dir() and any(source.iterdir()):
            target = primary / "dist" / sub / worktree.name
            target.mkdir(parents=True, exist_ok=True)
            subprocess.run(["cp", "-cRn", f"{source}/.", str(target)], capture_output=True)
            moved.append(str(target))
    return moved


def cleanup(args, root: Path = ROOT) -> int:
    if args.fetch or args.remote:
        git("fetch", "-q", "--prune", "origin", cwd=root)
    plan = cleanup_plan(args, root)
    primary = primary_worktree(root)
    verb = "Removing" if args.apply else "Would remove"
    nothing = not (plan["worktrees"] or plan["prune"] or plan["branches"] or plan["claims"] or plan["remote"])
    if nothing:
        print("Workspace tidy: nothing to clean up.")
    for tree in plan["worktrees"]:
        print(f"{verb} worktree {tree['path']} [{tree['branch']}] (merged, clean)")
        if args.apply:
            for target in move_evidence(Path(tree["path"]), primary):
                print(f"  kept its evidence in {target}")
            git("worktree", "remove", "--force", tree["path"], cwd=root, check=True)
    if plan["prune"]:
        print(f"{verb.replace('remove', 'prune')} missing worktree records")
        if args.apply:
            git("worktree", "prune", cwd=root, check=True)
    for name in dict.fromkeys(plan["branches"] + [t["branch"] for t in plan["worktrees"] if t["branch"]]):
        print(f"{verb} branch {name} (merged into {args.base})")
        if args.apply:
            git("branch", "-d", name, cwd=root, check=True)
    for name in plan["remote"]:
        print(f"{verb} origin/{name} (merged into origin/{args.base})")
        if args.apply:
            git("push", "origin", "--delete", name, cwd=root, check=True)
    if plan["claims"]:
        print(f"{verb} claims: {', '.join(plan['claims'])}")
        if args.apply:
            save_claims([c for c in load_claims(root) if c.get("task") not in plan["claims"]], root)
    for line in plan["keep"]:
        print(f"Keep {line}")
    if not args.apply and not nothing:
        print("Run again with --apply to clean up.")
    return 0


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    show = commands.add_parser("status")
    show.add_argument("--paths", nargs="*", default=[], help="Paths you are about to change")
    show.add_argument("--release", action="store_true", help="Fail while unparked branches hold unmerged commits")
    show.add_argument("--base", default="main")
    show.add_argument("--fetch", action="store_true", help="Fetch origin first")
    show.add_argument("--json", action="store_true")
    show.set_defaults(run=status)
    take = commands.add_parser("claim")
    take.add_argument("task", help="Work item ID, e.g. AD-123")
    take.add_argument("--paths", nargs="*")
    take.add_argument("--branch")
    take.add_argument("--parked", action="store_true")
    take.add_argument("--note")
    take.set_defaults(run=claim)
    drop = commands.add_parser("release")
    drop.add_argument("task")
    drop.set_defaults(run=release_claim)
    tidy = commands.add_parser("cleanup")
    tidy.add_argument("--apply", action="store_true", help="Remove what is safe; default lists only")
    tidy.add_argument("--remote", action="store_true", help="Also delete branches on origin merged into main")
    tidy.add_argument("--base", default="main")
    tidy.add_argument("--fetch", action="store_true", help="Fetch and prune origin first")
    tidy.add_argument("--idle-hours", type=float, default=2.0,
                      help="Keep unclaimed worktrees touched within this many hours (default 2)")
    tidy.set_defaults(run=cleanup)
    args = parser.parse_args(argv)
    return args.run(args, root)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as error:
        print(f"parallel_work: {error}", file=sys.stderr)
        sys.exit(1)
