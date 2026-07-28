#!/usr/bin/env bash
# test-evolve-watch.sh — the evolve watcher must not grow the board without bound.
#
# WHY THIS EXISTS. On 2026-07-28 the board held five untouched `evolve:` cards from
# 07-25 while proposals/ stopped at 07-19, and the next Saturday run would have added
# five more. The watcher is a generator with no guaranteed consumer, and nothing in it
# noticed that its previous output was still sitting there. Five a week compounds into
# an unusable board within a month, and an unusable board is how a real card gets lost.
#
# The property under test is therefore NOT "it creates cards" (it always did) but
# "a second changelog change while the first card is still open produces NO second
# card". That is the whole point, and it is what a naive re-read of the script would
# get wrong: the old code created one card per detected delta, unconditionally.
#
# It also pins the half that must NOT happen: the watcher must never move a card out
# of todo/. Card transitions are human gates (kb start needs Roberto, kb finish needs
# @thor). A watcher that expired its own cards on a timer would cross that gate on a
# schedule, unattended, which is worse than a long board.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$ROOT/evolve/watch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- isolation ---------------------------------------------------------------
# Never touch the real board or the real evolve state. RDA_KANBAN_TODO/DOING and
# RDA_EVOLVE_STATE are the documented seams; if a future change stops honouring
# them this suite dirties a real board, so check the isolation held at the end.
export RDA_EVOLVE_STATE="$TMP/state"
export RDA_KANBAN_TODO="$TMP/todo"
export RDA_KANBAN_DOING="$TMP/doing"
mkdir -p "$RDA_KANBAN_TODO" "$RDA_KANBAN_DOING"

# --- curl stub ---------------------------------------------------------------
# A PATH stub, not a network call: the suite must be hermetic and must not depend
# on five third-party changelogs being reachable and unchanged. The stub echoes
# whatever is in $TMP/payload, so "the changelog changed" is a file write.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
cat "${RDA_TEST_PAYLOAD:?}"
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export RDA_TEST_PAYLOAD="$TMP/payload"

_cards() { find "$RDA_KANBAN_TODO" "$RDA_KANBAN_DOING" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

# --- 1. first run: a delta with an empty board creates cards ------------------
echo "v1 changelog" > "$RDA_TEST_PAYLOAD"
bash "$WATCH" >"$TMP/run1.log" 2>&1 || fail "first run exited non-zero: $(cat "$TMP/run1.log")"
n1="$(_cards)"
[ "$n1" -gt 0 ] || fail "the watcher created no card at all on a fresh delta - the stub or the seams are wrong, not the feature"

# --- 2. no delta: a re-run with identical content adds nothing ----------------
# Pre-existing behaviour, pinned so the coalescing work cannot quietly break it.
bash "$WATCH" >"$TMP/run2.log" 2>&1 || fail "second run exited non-zero"
[ "$(_cards)" = "$n1" ] || fail "an unchanged changelog produced new cards ($n1 -> $(_cards))"

# --- 3. THE PROPERTY: a new delta while the cards are still open adds none ----
# This is the assertion the old watcher failed. It created one card per delta with
# no regard for what was already on the board.
echo "v2 changelog" > "$RDA_TEST_PAYLOAD"
bash "$WATCH" >"$TMP/run3.log" 2>&1 || fail "third run exited non-zero"
n3="$(_cards)"
[ "$n3" = "$n1" ] \
  || fail "a second changelog change added cards while the first were still open ($n1 -> $n3) - the board grows without bound, which is the whole defect"
grep -q 'COALESCED' "$TMP/run3.log" \
  || fail "the run folded the delta in silently: an operator reading the log cannot tell a coalesce from a no-op"

# --- 4. the coalesce must be VISIBLE on the card, not just in the log ---------
# A refresh nobody can see on the card is indistinguishable from a dropped signal:
# the agent that eventually picks the card up must know it covers more than one change.
card="$(find "$RDA_KANBAN_TODO" -name '*.md' | head -1)"
grep -q '^- changelog changed on ' "$card" \
  || fail "the card carries no record that its source changed again - the second signal was swallowed"
grep -q 'covers 2 changes' "$card" \
  || fail "the card does not say how many changes it now covers"

# --- 5. a card in DOING suppresses creation just as much as one in todo -------
# An agent holding the card will read the refreshed body. Creating a sibling while
# one is being worked is the same defect wearing a different column.
mv "$RDA_KANBAN_TODO"/*.md "$RDA_KANBAN_DOING"/ 2>/dev/null || true
n4="$(_cards)"
echo "v3 changelog" > "$RDA_TEST_PAYLOAD"
bash "$WATCH" >"$TMP/run4.log" 2>&1 || fail "fourth run exited non-zero"
[ "$(_cards)" = "$n4" ] \
  || fail "a card in doing/ did not suppress creation ($n4 -> $(_cards)) - the watcher would duplicate work an agent already holds"

# --- 6. the watcher must NEVER move a card out of todo/ ----------------------
# Card transitions are human gates. Expiry-on-a-timer would cross them unattended.
before="$(find "$RDA_KANBAN_DOING" -name '*.md' | sort | shasum | awk '{print $1}')"
echo "v4 changelog" > "$RDA_TEST_PAYLOAD"
bash "$WATCH" >"$TMP/run5.log" 2>&1 || fail "fifth run exited non-zero"
after="$(find "$RDA_KANBAN_DOING" -name '*.md' | sort | shasum | awk '{print $1}')"
[ "$before" = "$after" ] || fail "the watcher moved or removed a card - transitions are a human gate, never a timer"

# --- 7. isolation actually held ----------------------------------------------
# If the seams were ignored the assertions above could all pass against the REAL
# board while this suite reported green on an empty temp dir.
[ -d "$RDA_EVOLVE_STATE" ] || fail "RDA_EVOLVE_STATE was ignored: the run used real state"
[ -s "$RDA_EVOLVE_STATE/seen" ] || fail "no fingerprints recorded: the watcher would re-fire the same delta forever"

echo "PASS: test-evolve-watch.sh"
