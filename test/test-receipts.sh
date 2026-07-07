#!/usr/bin/env bash
# test-receipts.sh — the loop cursor emitter (loop/receipt.sh) actually writes receipts,
# in the right place, without ever polluting a repo that didn't opt in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RCPT="$ROOT/loop/receipt.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Explicit dir override: writes valid JSONL with the full schema.
RDA_RECEIPTS_DIR="$TMP/r1" bash "$RCPT" T-42 "cargo test" 0 "abc1234" "8 passed"
line="$(cat "$TMP/r1/T-42.jsonl")"
echo "$line" | jq -e '.task=="T-42" and .cmd=="cargo test" and .exit==0 and .artifact=="abc1234"' >/dev/null \
  || fail "receipt JSONL schema wrong: $line"

# 2. Append-only: a second receipt adds a line, never truncates.
RDA_RECEIPTS_DIR="$TMP/r1" bash "$RCPT" T-42 "gh run watch" 1
[ "$(wc -l < "$TMP/r1/T-42.jsonl" | tr -d ' ')" = "2" ] || fail "not append-only"

# 3. Repo that IGNORES .agent-state → receipts land in-repo.
git -C "$TMP" init -q optin && printf '.agent-state/\n' > "$TMP/optin/.gitignore"
(cd "$TMP/optin" && bash "$RCPT" T-1 "step" 0)
[ -f "$TMP/optin/.agent-state/T-1.jsonl" ] || fail "opt-in repo did not get in-repo receipts"

# 4. Repo that does NOT ignore .agent-state → NO pollution; falls back to RDA_HOME.
git -C "$TMP" init -q vanilla
(cd "$TMP/vanilla" && RDA_HOME="$TMP/home" bash "$RCPT" T-2 "step" 0)
[ ! -e "$TMP/vanilla/.agent-state" ] || fail "polluted a repo that didn't opt in"
[ -f "$TMP/home/state/receipts/vanilla/T-2.jsonl" ] || fail "RDA_HOME fallback missing"

# 5. Degenerate input → exit 0, never fails the caller (hook safety).
bash "$RCPT" || fail "no-args must exit 0"

echo "PASS: receipt emitter (schema, append-only, opt-in placement, no pollution, hook-safe)"
