#!/usr/bin/env bash
# Preserve repo checks without consulting the retired platform's processes or database.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${RDA_TEST_COMPLETION_GATE:-$ROOT/hooks/pre-completion-gate.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" RETIRED_CALLS="$TMP/retired-calls" PR_FIXTURE='[]'
mkdir -p "$HOME/.convergio/v3" "$TMP/repo" "$TMP/outside"
touch "$HOME/.convergio/v3/state.db"
git -C "$TMP/repo" init -q

gh() { printf '%s\n' "$PR_FIXTURE"; }
pgrep() { printf 'pgrep\n' >> "$RETIRED_CALLS"; printf '999999\n'; }
sqlite3() { printf 'sqlite3\n' >> "$RETIRED_CALLS"; printf '999999\n'; }
export -f gh pgrep sqlite3

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_gate() { (cd "$1" && bash "$GATE"); }

[ -z "$(run_gate "$TMP/outside")" ] || fail "non-repo session must be silent"
[ -z "$(run_gate "$TMP/repo")" ] || fail "clean repo must be silent"
[ ! -e "$RETIRED_CALLS" ] || fail "retired runtime must not be probed"

touch "$TMP/repo/uncommitted"
mkdir -p "$TMP/repo/.claude/worktrees/agent-probe"
export PR_FIXTURE='[{"number":7,"title":"Pending work","headRefName":"feature/probe"}]'
out="$(run_gate "$TMP/repo")"
for expected in 'uncommitted changes' 'open PR: #7 Pending work [feature/probe]' \
  '1 agent worktree(s) still present'; do
  printf '%s\n' "$out" | grep -qF "$expected" || fail "missing: $expected"
done
[ ! -e "$RETIRED_CALLS" ] || fail "retired runtime must not be probed"

gh() { return 1; }
export -f gh
out="$(run_gate "$TMP/repo")"
printf '%s\n' "$out" | grep -qF 'uncommitted changes' || fail "gh failure hid local changes"
printf '%s\n' "$out" | grep -qF 'agent worktree(s)' || fail "gh failure hid worktrees"

echo "test-pre-completion-gate: PASS"
