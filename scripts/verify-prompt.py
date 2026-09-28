#!/usr/bin/env python3
from pathlib import Path
import sys
from verify_prompt import verify

try:
    print(f"Prompt {verify(Path(__file__).resolve().parent.parent)}: correction, holdout and context gates passed with matching source evidence")
except (RuntimeError, OSError, ValueError, KeyError, TypeError) as error:
    print(f"Prompt release blocked: {error}", file=sys.stderr)
    sys.exit(1)
