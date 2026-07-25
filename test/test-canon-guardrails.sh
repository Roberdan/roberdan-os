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
require 'Playwright = Microsoft Edge (`msedge`) only' \
  'missing the Edge-only Playwright policy'
require 'no Chrome/Chromium fallback' \
  'missing the Chrome/Chromium fallback prohibition'
require 'If Edge is unavailable, stop and report the blocker' \
  'missing the Edge-unavailable blocker behavior'
require 'override only for Roberto-requested cross-browser tests' \
  'missing the explicit cross-browser override'

exit "$FAIL"
