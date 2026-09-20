#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
python3 "$ROOT/test/test-gbrain-repo-audit.py"
python3 "$ROOT/test/test-gbrain-recover-repos.py"
