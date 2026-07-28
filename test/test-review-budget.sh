#!/usr/bin/env bash
# test-review-budget.sh — the brake has to be seen working, or it is decoration.
#
# The rule it enforces was written after eight adversarial review rounds in one
# night, every one of which returned a true finding. A rule that expensive is
# worth a test that actually runs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/loop/review-budget.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RDA_REVIEW_BUDGET_DIR="$TMP/state"

fail() { echo "FAIL: $*" >&2; exit 1; }
run()  { set +e; out="$("$@" 2>&1)"; rc=$?; set -e; }

# 1. An undeclared budget is an infinite one — so `check` must SAY the default is
#    being assumed rather than silently applying it.
run bash "$BIN" check 260101-000001
[ "$rc" = 0 ] || fail "check on an unknown card should not be an error, got $rc"
grep -q "NO DECLARED BUDGET" <<<"$out" || fail "check must say the budget is undeclared: $out"
grep -q "0/2 rounds used" <<<"$out" || fail "default budget should be 2: $out"

# 2. Declaring records the property, not just the number. "Two rounds" of what is
#    the half that decides whether the loop can ever end.
run bash "$BIN" declare 260101-000002 2 "the bus never starts an agent session"
[ "$rc" = 0 ] || fail "declare failed: $out"
grep -q "never starts an agent" <<<"$out" || fail "declare must echo the property: $out"

# 3. Re-declaring mid-loop is refused. Moving the goalposts is exactly how a
#    bounded review becomes an unbounded one.
run bash "$BIN" declare 260101-000002 3 "something else"
[ "$rc" = 2 ] || fail "re-declaring should be refused with exit 2, got $rc: $out"

# 4. A budget above the hard cap is refused, and the message names the real
#    problem: an unbounded PROPERTY, not an insufficient review.
run bash "$BIN" declare 260101-000003 9 "everything is safe"
[ "$rc" = 2 ] || fail "over-cap budget should be refused, got $rc"
grep -q "it is the PROPERTY that is unbounded" <<<"$out" || fail "refusal must name the cause: $out"

# 5. THE ONE THAT MATTERS. Rounds inside the budget pass; the round that spends
#    it exits 3 and demands a human decision. Exit 3 is not a failure of the
#    work — it is the loop refusing to start another round by default.
run bash "$BIN" record 260101-000002 "DO NOT SHIP" "found a real blocker"
[ "$rc" = 0 ] || fail "round 1 of 2 should be fine, got $rc: $out"
grep -q "1/2 rounds used" <<<"$out" || fail "round 1 not counted: $out"

run bash "$BIN" record 260101-000002 "DO NOT SHIP" "found another real blocker"
[ "$rc" = 3 ] || fail "the round that spends the budget must exit 3, got $rc: $out"
grep -q "BUDGET SPENT" <<<"$out" || fail "no stop directive: $out"
grep -q "(a) ship as it stands" <<<"$out" || fail "the three options must be spelled out: $out"
grep -q "Silence is not (b)" <<<"$out" || fail "the default-to-another-round trap must be named: $out"

# 6. And it STAYS spent. A later `check` cannot quietly re-open the loop, which
#    is the whole point: the next round has to be an explicit decision.
run bash "$BIN" check 260101-000002
[ "$rc" = 3 ] || fail "check after the budget is spent must keep exiting 3, got $rc"
grep -q "round 1: DO NOT SHIP" <<<"$out" || fail "the per-round history must be readable: $out"

# 7. The state is durable and per-card: one card's spent budget does not touch
#    another's. A brake shared across cards would be worse than none.
run bash "$BIN" declare 260101-000004 1 "a different property"
[ "$rc" = 0 ] || fail "a second card should be independent: $out"
run bash "$BIN" check 260101-000004
[ "$rc" = 0 ] || fail "the second card must not inherit the first's spent budget, got $rc: $out"

# 8. Path traversal in a card id is refused rather than writing anywhere it likes.
run bash "$BIN" check "../../etc/passwd"
[ "$rc" = 2 ] || fail "a traversing card id must be refused, got $rc: $out"

echo "PASS: test-review-budget.sh"
