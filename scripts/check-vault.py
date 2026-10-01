#!/usr/bin/env python3
"""Check the Airdraft Obsidian vault against its maintenance rules.

Read-only. Exits 1 when any rule fails; warnings do not change the exit code.
Run after writing to the vault and before release:

    python3 scripts/check-vault.py [--vault PATH]
"""
import argparse
from pathlib import Path
import sys

from vault_check import DEFAULT_VAULT, check


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    args = parser.parse_args()
    if not args.vault.is_dir():
        print(f"error: vault not found: {args.vault}", file=sys.stderr)
        return 1
    findings = check(args.vault)
    for finding in findings:
        print(finding)
    errors = sum(not f.warning for f in findings)
    print(f"{errors} error(s), {len(findings) - errors} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
