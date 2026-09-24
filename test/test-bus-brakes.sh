#!/usr/bin/env bash
# test-bus-brakes.sh — hop/TTL cap, hourly budget, taking-collision, pause/resume
# (card 260924-142220, items D and E). Red-then-green: run against a bus.sh with
# none of bus-brakes.sh sourced and every property below fails (no `pausa`/
# `riprendi`/`taking`/`wait` subcommand, no hop or hourly refusal) — this file is
# the green, repeatable form of that walk-through.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export RDA_HOME="$HOME/.roberdan-os"
export RDA_BUS_HOME="$RDA_HOME/bus"
mkdir -p "$HOME" "$TMP/cwd"
REPO=brakes-repo

# RUN FROM A SCRATCH DIRECTORY, NOT FROM THE CHECKOUT — same reason as
# test-bus.sh's canary_run (see test-bus-trust.sh's copy of this note).
runbus() ( cd "$TMP/cwd" && bash "$BUS" "$@" )

# --- hop/TTL: a 4th hop on a reply chain is refused -------------------------
echo m1 | runbus send --repo "$REPO" --card hop --from implementer --to reviewer --kind note >/dev/null
echo m2 | runbus send --repo "$REPO" --card hop --from reviewer --to implementer --kind note --re 1 >/dev/null
echo m3 | runbus send --repo "$REPO" --card hop --from implementer --to reviewer --kind note --re 2 >/dev/null
echo m4 | runbus send --repo "$REPO" --card hop --from reviewer --to implementer --kind note --re 3 >/dev/null
echo m5 | runbus send --repo "$REPO" --card hop --from implementer --to reviewer --kind note --re 4 2>"$TMP/hop.err" \
  && fail "a 4th hop was accepted"
grep -q "hop/TTL brake" "$TMP/hop.err" || fail "hop refusal did not name the brake: $(cat "$TMP/hop.err")"
ok "a reply chain deeper than 3 hops is refused (ping-pong stops at the cap)"

# --- hourly cap: derived from the log, not a second counter -----------------
echo a | RDA_BUS_HOURLY_CAP=2 runbus send --repo "$REPO" --card cap --from implementer --to reviewer --kind note >/dev/null
echo b | RDA_BUS_HOURLY_CAP=2 runbus send --repo "$REPO" --card cap --from implementer --to reviewer --kind note >/dev/null
echo c | RDA_BUS_HOURLY_CAP=2 runbus send --repo "$REPO" --card cap --from implementer --to reviewer --kind note 2>"$TMP/cap.err" \
  && fail "a 3rd send within the hourly cap (2) was accepted"
grep -q "runaway brake" "$TMP/cap.err" || fail "hourly refusal did not name the brake"
ok "the hourly budget is enforced and derived from the log alone"

# --- broadcast never counts as a wake trigger --------------------------------
echo req | runbus send --repo "$REPO" --card wake1 --from implementer --to all --kind request >/dev/null
n="$(runbus unread-direct --repo "$REPO" --card wake1 --as reviewer)"
[ "$n" = "0" ] || fail "a --to all request counted as a DIRECT unread (n=$n) — broadcast must never wake"
ok "bus unread-direct --to all: never wakes"
echo dq | runbus send --repo "$REPO" --card wake1 --from implementer --to reviewer --kind question >/dev/null
n2="$(runbus unread-direct --repo "$REPO" --card wake1 --as reviewer)"
[ "$n2" = "1" ] || fail "a direct question did not count as unread (n=$n2)"
ok "a direct request/question is exactly what bus unread-direct counts"

# --- taking: first taker wins, second is refused (not merely warned) --------
echo req2 | runbus send --repo "$REPO" --card take --from implementer --to all --kind request >/dev/null
runbus taking --repo "$REPO" --card take --as reviewer --re 1 >/dev/null 2>&1 \
  || fail "the first taker was refused"
runbus taking --repo "$REPO" --card take --as qa-gate --re 1 >"$TMP/take2.out" 2>&1 \
  && fail "a second taker on the same record was accepted"
grep -q "already taking" "$TMP/take2.out" || fail "second-taker refusal did not explain why"
records="$(jq -c 'select(.kind=="note" and (.body|startswith("TAKING #1")))' "$RDA_BUS_HOME/$REPO/take.jsonl" | wc -l | tr -d ' ')"
[ "$records" = "1" ] || fail "expected exactly ONE taking record, found $records"
ok "two listeners, one request: exactly one taking record, second taker refused"

# --- pause: deny at bus.sh's own layer too (belt+suspenders with bus-guard.sh) ---
runbus pausa --by implementer --why "brakes test" >/dev/null 2>&1
[ "$(runbus paused)" = "1" ] || fail "bus paused did not report 1 while paused"
echo blocked | runbus send --repo "$REPO" --card take --from implementer --to reviewer --kind note 2>"$TMP/pause.err" \
  && fail "a send succeeded while the bus was paused"
grep -q "PAUSED" "$TMP/pause.err" || fail "the pause refusal did not say why"
runbus riprendi --by implementer >/dev/null 2>&1
[ "$(runbus paused)" = "0" ] || fail "bus paused still reports 1 after riprendi"
echo unblocked | runbus send --repo "$REPO" --card take --from implementer --to reviewer --kind note >/dev/null \
  || fail "a send after riprendi was still refused"
ok "bus pausa denies every send; bus riprendi restores it"

# --- riprendi never deletes a goal-gate.off Roberto set for another reason ---
gg="$RDA_HOME/goal-gate.off"
printf 'roberto-decided-something-else\n' > "$gg"
runbus pausa --by implementer >/dev/null 2>&1
runbus riprendi --by implementer >/dev/null 2>&1
[ -e "$gg" ] && [ "$(cat "$gg")" = "roberto-decided-something-else" ] \
  || fail "riprendi deleted a goal-gate.off it did not create"
ok "riprendi only removes the goal-gate.off flag it created itself"

echo "test-bus-brakes: PASS"
