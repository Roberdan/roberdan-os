#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

RULES="rules/best-practices.md"
REFERENCE="skills/engineering-reference/skill.md"
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

if ! grep -qF 'new hand-written source/test files >300 lines' "$REFERENCE"; then
  printf 'FAIL: engineering reference lacks the progressive new-file gate\n' >&2
  FAIL=1
fi
if ! grep -qF 'unjustified growth in oversized legacy files' "$REFERENCE"; then
  printf 'FAIL: engineering reference lacks the legacy-growth gate\n' >&2
  FAIL=1
fi
if ! grep -qF 'technical artifacts exempt' "$REFERENCE"; then
  printf 'FAIL: engineering reference lacks technical exemptions\n' >&2
  FAIL=1
fi
if grep -qF 'commits with files > 300 lines' "$REFERENCE"; then
  printf 'FAIL: engineering reference still contains the absolute file-size rule\n' >&2
  FAIL=1
fi

# Tests: budget, place, shape (ADR-0006, Roberto 2026-10-11). The new rules must be present,
# and the six old phrases that made every fix a new test file and every push the whole suite
# must not come back anywhere they used to live.
require '## Tests: budget, place, shape' 'missing the Tests budget/place/shape section'
require 'never the whole suite' 'missing the related-tests-only pre-push rule'
require 'Batch related' 'missing the batching rule'
require 'the whole repo is' 'missing the safe default for repos without .test-critical'
require 'Extend before you add' 'missing the extend-before-add rule'
require 'Prune monthly' 'missing the monthly pruning rule'
require 'Never prune `.test-critical`' 'missing the critical-path pruning exemption'
require '`.test-budget`' 'missing the ratchet rule'
require 'case tables and' 'missing the case-table exemption from the 300-line cap'
grep -qF 'Tests: extend, don' AGENTS.md || { printf 'FAIL: AGENTS.md lacks the tests pointer\n' >&2; FAIL=1; }
[ -f docs/testing-template.md ] || { printf 'FAIL: docs/testing-template.md missing\n' >&2; FAIL=1; }

forbid() {
  local file="$1" pattern="$2" message="$3"
  if grep -qF -- "$pattern" "$file"; then
    printf 'FAIL: %s (%s)\n' "$message" "$file" >&2
    FAIL=1
  fi
}
forbid "$RULES" '| Write the test |' '"too simple to test" still answered with a new test'
forbid agents/thor.md '**TDD** — tests present' 'thor gate 8 still asks only for tests present'
forbid skills/verify-done/skill.md 'Coverage ≥ 80%' 'verify-done still has a global coverage target'
forbid behavior/roberto-mode.md 'Coverage ≥ 80%' 'roberto-mode still has a global coverage target'
forbid "$REFERENCE" '80% business logic' 'engineering-reference still has a global coverage target'
forbid "$REFERENCE" 'run the full local pipeline' 'engineering-reference still runs everything before push'
forbid "$REFERENCE" 're-run ALL checks' 'engineering-reference still re-runs everything'
forbid skills/ship/skill.md 're-run all' 'ship still re-runs everything'
forbid skills/review/skill.md '(tests, types, conventional commit)' 'review still fixes every comment with tests'

bash "$ROOT/test/test-pre-completion-gate.sh" || FAIL=1
exit "$FAIL"
