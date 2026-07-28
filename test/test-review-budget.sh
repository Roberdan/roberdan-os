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

# --- LOOP A: rounds on the same CLASS -------------------------------------
# The count is only half the brake. Seven rounds on one route check each found
# another INSTANCE of one class; patching instances does not end by exhausting
# them. The second round on a class stops the patching by name.

# 9. Two rounds on the same class stop it, even though the class is spelled
#    differently — a checker fooled by capitalisation notices nothing.
run bash "$BIN" declare 260101-000005 3 "the route gate"
[ "$rc" = 0 ] || fail "declare failed: $out"
run bash "$BIN" record 260101-000005 "DO NOT SHIP" "desc drifted on /api/x" route-desc
[ "$rc" = 0 ] || fail "round 1 on a class should be fine, got $rc: $out"
run bash "$BIN" record 260101-000005 "DO NOT SHIP" "desc drifted on /api/y" "Route-Desc "
[ "$rc" = 3 ] || fail "the SECOND round on one class must stop, got $rc: $out"
grep -q "SECOND ROUND ON THE CLASS 'route-desc'" <<<"$out" || fail "the stop must name the class, normalised: $out"
grep -q "change the shape" <<<"$out" || fail "the way out must be a change of shape, not another patch: $out"
grep -q "MINUTE IT" <<<"$out" || fail "the second way out (write it down and stop) must be offered: $out"

# 10. It fires on the CLASS, not on the budget: this card still had a round left.
grep -q "2/3" <<<"$out" || fail "the class stop must fire while budget remains, showing 2/3: $out"

# 11. Different classes do not trip it — otherwise the rule would just be a
#     lower round cap wearing a costume.
run bash "$BIN" declare 260101-000006 3 "two different classes"
run bash "$BIN" record 260101-000006 "DO NOT SHIP" "a" class-one
[ "$rc" = 0 ] || fail "first class, first round: $out"
run bash "$BIN" record 260101-000006 "DO NOT SHIP" "b" class-two
[ "$rc" = 0 ] || fail "a DIFFERENT class must not trip the same-class stop, got $rc: $out"

# --- LOOP B: scope drift ---------------------------------------------------
# A card that said "sort before cutting" produced a +6153-line PR about macOS
# ACLs over 18 rounds. Good work; not the work asked for.

# 12. A discovery is recorded as NOT part of this PR, and hands back the command
#     that files it as its own card.
run bash "$BIN" discovery 260101-000005 "macOS ACL permissions need sorting"
[ "$rc" = 0 ] || fail "discovery should record cleanly, got $rc: $out"
grep -q "does NOT go in this PR" <<<"$out" || fail "a discovery must be excluded from this PR: $out"
grep -q 'kb add "macOS ACL permissions need sorting"' <<<"$out" || fail "it must hand back the filing command: $out"

# --- The counterweight -----------------------------------------------------
# Without this, the cap is a way to ship holes on schedule.

# 13. A THEORETICAL risk does not override the cap. A cap that yields to "might"
#     is not a cap.
run bash "$BIN" override 260101-000005 "an attacker could escalate this"
[ "$rc" = 2 ] || fail "a theoretical risk must not override the cap, got $rc: $out"
grep -q "that is a risk, not an exposure" <<<"$out" || fail "the refusal must name the difference: $out"

# 14. A DEMONSTRATED exposure does, and it lifts both brakes — the loop is
#     allowed to continue precisely because something real was shown.
run bash "$BIN" override 260101-000005 "ran the mutant: it started 92 live agent sessions in a green run"
[ "$rc" = 0 ] || fail "a demonstrated exposure must override, got $rc: $out"
run bash "$BIN" record 260101-000005 "DO NOT SHIP" "third instance" route-desc
[ "$rc" = 0 ] || fail "after a demonstrated override the class stop must yield, got $rc: $out"

# --- The visible number ----------------------------------------------------
# Prose did not stop this happening to anyone who could read. A count that has
# to be written into the PR makes the eighteenth round embarrassing to type.

# 15. `line` is one line, and it carries every fact someone would rather omit.
run bash "$BIN" line 260101-000005
[ "$rc" = 0 ] || fail "line failed: $out"
[ "$(wc -l <<<"$out" | tr -d ' ')" = "1" ] || fail "the PR line must be ONE line: $out"
grep -q "Review rounds: 3/3" <<<"$out" || fail "the count must be in the line: $out"
grep -q "classes: route-desc" <<<"$out" || fail "the classes must be in the line: $out"
grep -q "discovery(ies) filed as separate cards" <<<"$out" || fail "discoveries must be in the line: $out"
grep -q "CAP OVERRIDDEN" <<<"$out" || fail "an override must be visible in the line, not buried: $out"

echo "PASS: test-review-budget.sh"
