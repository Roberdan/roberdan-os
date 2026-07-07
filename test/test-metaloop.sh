#!/usr/bin/env bash
# test-metaloop.sh — proves the self-improving meta-loop is WIRED END-TO-END:
# a real learning flows capture -> distill (REAL class, never TODO) -> human approves
# -> curate PROMOTES it into the vault as a typed note. Also proves the two gates that
# keep the loop honest: ephemeral session boilerplate is DROPPED, and an unapproved
# candidate is NEVER promoted. This test FAILS against the old `class: TODO` stub
# (curate skips TODO -> zero promotions) and PASSES with the deterministic classifier.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fully isolated meta-loop env — never touches the real inbox/quarantine/vault. RDA_HOME
# is a temp dir so both privacy deny-lists (capture + curate) resolve to nothing here.
export RDA_HOME="$TMP/home"
export RDA_INBOX="$TMP/inbox"
export RDA_QUARANTINE="$TMP/quar"
export RDA_SESSION="metaloop-test"
VAULT="$TMP/vault"
export RDA_VAULT="$VAULT"
export RDA_EVOLVE_STATE="$TMP/evolve"
git -C "$TMP" init -q vault
git -C "$VAULT" config user.email "test@example.com"
git -C "$VAULT" config user.name "Meta Loop Test"

CAP="$ROOT/learn/capture.sh"
DIS="$ROOT/learn/distill.sh"
CUR="$ROOT/ontology/curate.sh"

# --- 1) CAPTURE a real learning ------------------------------------------------
bash "$CAP" "agent forgot to re-run validate.sh before commit — should have re-run it"
inbox_file="$RDA_INBOX/$(date +%Y-%m-%d)-metaloop-test.md"
[ -s "$inbox_file" ] || fail "capture wrote no inbox record"

# --- 2) CAPTURE an ephemeral session marker (must be dropped, not promoted) ----
bash "$CAP" --session "session $(date +%Y-%m-%dT%H:%M:%S) cwd=$ROOT"

# --- 3) DISTILL: real class (never TODO) + ephemera dropped ---------------------
bash "$DIS"
cands=("$RDA_QUARANTINE"/*.md)
[ "${#cands[@]}" -eq 1 ] || fail "expected exactly 1 candidate (ephemeral dropped), got ${#cands[@]}"
cand="${cands[0]}"
cls="$(grep -E '^class:' "$cand" | head -1 | sed -E 's/^class:[[:space:]]*//; s/[[:space:]]*#.*//')"
[ "$cls" != "TODO" ] || fail "distill still emits the class: TODO stub — classifier not wired"
[ "$cls" = "correction" ] || fail "expected class 'correction' (forgot/should-have), got '$cls'"
grep -q "agent forgot to re-run validate.sh" "$cand" || fail "candidate body lost the signal"
grep -q '{class:' "$cand" && fail "candidate body leaked a control token"

# --- 4) GATE: an UNAPPROVED candidate is NEVER promoted -------------------------
bash "$CUR"
promoted_now="$(find "$VAULT/agent-learnings" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$promoted_now" = "0" ] || fail "curate promoted an UNAPPROVED candidate (human gate broken)"

# --- 5) HUMAN approves (the gate that stays Roberto's) -> curate PROMOTES -------
# Portable in-place edit (BSD + GNU sed): approved:false -> approved:true.
sed -i.bak -E 's/^approved:[[:space:]]*false/approved: true/' "$cand" && rm -f "$cand.bak"
bash "$CUR"
notes=("$VAULT/agent-learnings"/*.md)
[ "${#notes[@]}" -eq 1 ] || fail "curate did not promote the approved candidate (got ${#notes[@]} notes)"
note="${notes[0]}"
grep -qE '^type:[[:space:]]*agent-learning' "$note" || fail "promoted note missing type: agent-learning"
grep -qE '^class:[[:space:]]*correction' "$note" || fail "promoted note lost its real class"
grep -q "agent forgot to re-run validate.sh" "$note" || fail "promoted note lost the learning body"
git -C "$VAULT" log --oneline | grep -q "promote agent-learning" || fail "promotion was not committed to the vault"
[ -f "$cand.promoted" ] || fail "quarantine source not consumed on a verified commit"

echo "PASS: meta-loop wired end-to-end (capture -> distill[real class] -> approve -> curate promotes; ephemera dropped; unapproved never promoted)"
