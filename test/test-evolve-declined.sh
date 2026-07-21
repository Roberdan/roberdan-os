#!/usr/bin/env bash
# test/test-evolve-declined.sh — the rejected-proposal buffer, proved on the REAL case.
#
# The regression this pins (measured 2026-07-21): proposals/2026-07-{11,18,19}-claude-code.md
# each re-raised the same two novelties, each reworded, each concluding "no additional patch
# required now". The buffer must (a) match a reworded repeat, (b) NOT match an unrelated
# novelty, and (c) actually reach the agent — i.e. appear in the card watch.sh writes.
#
# (c) is the load-bearing one: a buffer nothing reads is dead code that looks done.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECLINED="$ROOT/evolve/declined.sh"
fails=0
pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1" >&2; fails=$((fails+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export RDA_EVOLVE_STATE="$tmp/state"

# The real 11 July summary, verbatim in substance.
SEEN='/verify and /code-review are explicit (no auto-run) -> keep explicit verify/review steps'
"$DECLINED" add claude-code "$SEEN" >/dev/null 2>&1

echo "[1/4] fuzzy matching on the observed rewordings"
# The real 19 July rewording — different words, same item.
if "$DECLINED" has claude-code 'Explicit skill invocation requirement for /verify and /code-review' >/dev/null; then
  pass "reworded repeat (19 Jul phrasing) matches the 11 Jul record"
else
  fail "reworded repeat NOT matched — the buffer misses exactly what it exists for"
fi
# The real 18 July rewording.
if "$DECLINED" has claude-code 'Explicit /verify + /code-review invocation policy' >/dev/null; then
  pass "reworded repeat (18 Jul phrasing) matches"
else
  fail "18 Jul phrasing NOT matched"
fi

echo "[2/4] it must not swallow genuine novelties"
if "$DECLINED" has claude-code 'New JSON output format for SessionStart hooks' >/dev/null 2>&1; then
  fail "false positive: an unrelated novelty was treated as already-declined"
else
  pass "unrelated novelty is not suppressed"
fi
# Overlap coefficient's own failure mode: a 1-token summary is a subset of everything.
if "$DECLINED" has claude-code 'verify' >/dev/null 2>&1; then
  fail "false positive: a single-token summary matched (MIN_SHARED guard is not working)"
else
  pass "single-token summary rejected by the MIN_SHARED guard"
fi
if "$DECLINED" has copilot 'Explicit skill invocation requirement for /verify and /code-review' >/dev/null 2>&1; then
  fail "cross-source leak: a claude-code record matched a copilot query"
else
  pass "records are scoped per source"
fi

echo "[3/4] add is idempotent (a repeat does not grow the store)"
"$DECLINED" add claude-code 'Explicit /verify + /code-review invocation policy' >/dev/null 2>&1
lines="$(grep -c . "$RDA_EVOLVE_STATE/declined" 2>/dev/null || echo 0)"
if [ "$lines" -eq 1 ]; then pass "store still holds 1 record after a reworded re-add"
else fail "store grew to $lines records — reworded repeats are being appended"; fi

echo "[4/4] WIRED: the buffer reaches the agent through the card watch.sh writes"
# Drive watch.sh against a local fake "changelog" so the test makes no network call and never
# touches the real board. curl is shadowed by a stub earlier on PATH (same pattern as
# test/test-factory-kb.sh stubbing factory/run.sh).
mkdir -p "$tmp/bin" "$tmp/todo"
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Any fetch returns fixed content; a changed fingerprint vs. an empty seen file => a new card.
echo "fake changelog body $(date +%s%N)"
STUB
chmod +x "$tmp/bin/curl"
PATH="$tmp/bin:$PATH" RDA_KANBAN_TODO="$tmp/todo" bash "$ROOT/evolve/watch.sh" >/dev/null 2>&1 || true

card="$(ls "$tmp/todo"/*claude-code.md 2>/dev/null | head -1 || true)"
if [ -z "$card" ]; then
  fail "watch.sh produced no claude-code card — cannot verify wiring"
else
  if grep -q 'Already assessed and DECLINED' "$card" && grep -qF "$SEEN" "$card"; then
    pass "the declined item appears in the card body (live path, not just on disk)"
  else
    fail "card written but the declined block is MISSING — the buffer is not wired to the agent"
  fi
  if grep -q 'declined.sh add claude-code' "$card"; then
    pass "the card tells the agent how to record a new decline (loop closes)"
  else
    fail "the card never asks the agent to record declines — the buffer can only ever stay empty"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "test-evolve-declined: all green"; exit 0
else echo "test-evolve-declined: $fails failure(s)" >&2; exit 1; fi
