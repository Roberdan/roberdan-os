#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

RULES="rules/best-practices.md"
FAIL=0

require() {
  local pattern="$1"
  local message="$2"
  if ! grep -qF "$pattern" "$RULES"; then
    printf 'FAIL: %s\n' "$message" >&2
    FAIL=1
  fi
}

require 'New hand-written source and test files target **≤300 lines**;' \
  'missing the progressive 300-line limit'
require 'Existing oversized files may grow only with explicit,' \
  'missing protection against growing oversized legacy files'
require 'Generated, vendored, lock, snapshot, data, and migration artifacts are exempt.' \
  'missing technical-artifact exemptions'
require 'never force unrelated refactors' \
  'missing the no-unrelated-refactor safeguard'

exit "$FAIL"
