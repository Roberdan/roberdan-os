#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s "$ROOT/test" -p 'test_optional_skills.py' -v
