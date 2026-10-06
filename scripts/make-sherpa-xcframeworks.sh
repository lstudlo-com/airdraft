#!/bin/bash
# Verify and repackage the pinned native archives as library XCFrameworks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/native_inputs.py" prepare "$@"
