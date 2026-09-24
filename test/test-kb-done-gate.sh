#!/usr/bin/env bash
# test/test-kb-done-gate.sh — the done-gate must be MECHANICAL, not honor-system.
#
# Before 2026-07-13, `kb finish <id> --thor "<ev>"` accepted any non-empty string:
# `--thor ok` closed a card and stamped `verified_by: thor`. best-practices.md
# § No False Done says the opposite ("prefer a mechanical gate over your own
# assurance; move the evidence OUT of your words"), so the canon was preaching a
# mechanical gate while shipping an honor-system one.
#
# The trading-os audit (2026-07-13) showed where that shape leads: its merge gate
# accepted `evidence.ci == "pass"` as a self-declared string, ~40 PRs merged with
# no CI at all, and 33 cards closed green while the product produced zero value.
#
# These assertions pin the fix in BOTH directions — a gate that only ever refuses
# is as useless as one that only ever accepts:
#   - forged/empty evidence is REFUSED (rubber-stamps, unverifiable prose, fake SHAs)
#   - real evidence is ACCEPTED (a resolvable SHA, real test output, an existing path)
#
# Uses temp fixtures via RDA_KANBAN — never the real board.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RDA_KANBAN="$TMP/board"
# Le chiusure di questa suite NON devono convocare @thor davvero: la verifica headless
# lancia un processo `claude` per card, costa minuti e denaro, e qui le card sono finte.
# Il percorso automatico ha il suo test dedicato (test-kb-autothor.sh).
export RDA_KB_AUTOTHOR=0
export RDA_KANBAN_REGISTRY="$TMP/registry"
mkdir -p "$RDA_KANBAN"/{todo,doing,done}
: > "$RDA_KANBAN_REGISTRY"
# Sandboxed bus store for the "kb finish closes the bus thread" section below —
# never the real ~/.roberdan-os/bus, even though these cards carry a repo: field.
export RDA_BUS_HOME="$TMP/bus"

KB="bash $ROOT/kanban/kb.sh"
card() { printf 'id: %s\nstatus: doing\ntitle: "gate fixture"\n' "$1" > "$RDA_KANBAN/doing/$1.md"; }

# A card must still be in doing/ (refused) or moved to done/ (accepted).
refused() { [ -e "$RDA_KANBAN/doing/$1.md" ] && [ ! -e "$RDA_KANBAN/done/$1.md" ]; }
accepted() { [ -e "$RDA_KANBAN/done/$1.md" ] && [ ! -e "$RDA_KANBAN/doing/$1.md" ]; }

section "forged or empty evidence is REFUSED"

card r1
if $KB finish r1 --thor "ok" >/dev/null 2>&1 || ! refused r1; then
  err "a rubber-stamp ('ok') closed the card"
else ok "rubber-stamp 'ok' refused"; fi

card r2
if $KB finish r2 --thor "tutto a posto" >/dev/null 2>&1 || ! refused r2; then
  err "an italian rubber-stamp ('tutto a posto') closed the card"
else ok "rubber-stamp 'tutto a posto' refused"; fi

card r3
if $KB finish r3 --thor "ho verificato tutto, funziona bene" >/dev/null 2>&1 || ! refused r3; then
  err "unverifiable prose closed the card"
else ok "prose that names nothing verifiable refused"; fi

card r4
if $KB finish r4 --thor "verified at commit deadbeef1234567" >/dev/null 2>&1 || ! refused r4; then
  err "a FORGED commit sha closed the card"
else ok "a commit sha that resolves nowhere is refused (forged evidence)"; fi

card r5
if $KB finish r5 --thor "" >/dev/null 2>&1 || ! refused r5; then
  err "empty evidence closed the card"
else ok "empty evidence refused"; fi

section "real evidence is ACCEPTED (no false refusals)"

REALSHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "")"
if [ -n "$REALSHA" ]; then
  card a1
  if $KB finish a1 --thor "fix landed in $REALSHA, suite green" >/dev/null 2>&1 && accepted a1; then
    ok "a resolvable commit sha is accepted"
  else err "a REAL commit sha was refused — the gate blocks honest work"; fi
fi

card a2
if $KB finish a2 --thor "make check: 148 passed, coverage 100%" >/dev/null 2>&1 && accepted a2; then
  ok "real test output is accepted"
else err "real test output was refused — the gate blocks honest work"; fi

card a3
if $KB finish a3 --thor "runbook written in kanban/README.md and validated" >/dev/null 2>&1 && accepted a3; then
  ok "an existing file path is accepted"
else err "an existing file path was refused — the gate blocks honest work"; fi

# The board can be a git repo of its own, and since 2026-07-28 this one is: the
# cards live in a private repo nested at kanban/, because the repo that holds
# them is public and they carry real names and clients. That repo is NOT in the
# registry on purpose (the registry lists boards), so before the fix a REAL
# commit of a REAL card was refused as forged evidence — the gate calling an
# honest citation a lie. Hermetic here: the temp board becomes a git repo, and
# the sha exists NOWHERE else, so this passes only if kb consults the board.
card a4
BOARDSHA=""
if git -C "$RDA_KANBAN" init -q 2>/dev/null; then
  printf 'seed\n' > "$RDA_KANBAN/.board-seed"
  git -C "$RDA_KANBAN" add -A >/dev/null 2>&1
  git -C "$RDA_KANBAN" -c user.name=t -c user.email=t@t commit -qm "board history" >/dev/null 2>&1
  BOARDSHA="$(git -C "$RDA_KANBAN" rev-parse --short HEAD 2>/dev/null || echo "")"
fi
if [ -z "$BOARDSHA" ]; then
  err "could not build the board-repo fixture — case not exercised, not passed"
elif git -C "$ROOT" cat-file -e "${BOARDSHA}^{commit}" 2>/dev/null; then
  err "fixture sha $BOARDSHA also resolves in the main repo — the case proves nothing"
elif $KB finish a4 --thor "cards committed in the board repo at $BOARDSHA" >/dev/null 2>&1 && accepted a4; then
  ok "a sha that resolves ONLY in the board's own repo is accepted"
else
  err "a REAL commit in the board's own repo was refused as forged — the gate blocks honest work"
fi

section "the accepted card records the evidence"
if grep -q "^verified_evidence:" "$RDA_KANBAN/done/a2.md" 2>/dev/null; then
  ok "verified_evidence is persisted on the card"
else err "verified_evidence missing from the closed card"; fi

# --- chi verifica e' un DATO, non un presupposto (findings #8) ---------------------
# Prima kb stampava e scriveva "verified by @thor" su ogni chiusura, anche quando @thor era
# sospeso e aveva verificato qualcun altro. La frase la generava il sistema, nessuno la
# controllava, e restava per sempre nell'archivio.
card V-BY
out_by="$($KB finish V-BY --thor "test/test-kb-done-gate.sh eseguito: 14 passed, exit 0" --by claude 2>&1 | grep -v '^kb: ' | tail -1)"
case "$out_by" in
  *"verified by @claude"*) ok "chiudendo con --by claude, l'output dice claude" ;;
  *) err "l'output non nomina chi ha verificato davvero: $out_by" ;;
esac
case "$out_by" in
  *thor*) err "l'output nomina ancora thor quando a verificare e' stato claude" ;;
  *) ok "e non nomina thor" ;;
esac
if grep -q '^verified_by: claude' "$RDA_KANBAN/done/V-BY.md"; then
  ok "la card archiviata registra verified_by: claude"
else err "la card archiviata non registra chi ha verificato: $(grep '^verified_by' "$RDA_KANBAN/done/V-BY.md")"; fi
if grep -q '^verified_by: thor' "$RDA_KANBAN/done/V-BY.md"; then
  err "la card archiviata afferma ancora thor"
else ok "e non afferma thor"; fi

# --- kb finish closes the card's bus thread (card 260924-120127, defect 2) -------
# Threads of already-closed cards stayed open forever: nothing closed them when the
# work finished. `bus/bus.sh close` already existed; this proves kb.sh's finish path
# actually calls it — end to end, not just that the function is defined somewhere.
section "kb finish closes the card's bus thread"
BUS="bash $ROOT/bus/bus.sh"
cardrepo() { printf 'id: %s\nrepo: %s\nstatus: doing\ntitle: "gate fixture"\n' "$1" "$2" > "$RDA_KANBAN/doing/$1.md"; }
thread_state() { # repo card -> "closed" | "open" | "missing"
  $BUS log --repo "$1" --card "$2" >/dev/null 2>&1 || { echo missing; return; }
  $BUS log --repo "$1" --card "$2" 2>/dev/null | grep -q "thread closed" && echo closed || echo open
}

cardrepo b1 bus-gate-repo
echo "note for the b1 thread" | $BUS send --repo bus-gate-repo --card b1 --from implementer --to sol-gate --kind note >/dev/null 2>&1
if [ "$(thread_state bus-gate-repo b1)" = "open" ]; then ok "b1 fixture thread starts open"
else err "the b1 thread fixture did not land — case not exercised"; fi
if $KB finish b1 --thor "bus-close fixture verified against kanban/README.md" >/dev/null 2>&1 && accepted b1; then
  if [ "$(thread_state bus-gate-repo b1)" = "closed" ]; then
    ok "kb finish closed the card's bus thread"
  else err "kb finish accepted the card but the bus thread is still open"; fi
else err "kb finish refused a card with real evidence — cannot test the bus-close wiring"; fi

# The whole word survives the close — closing is a record, never a deletion.
if $BUS log --repo bus-gate-repo --card b1 2>/dev/null | grep -q "note for the b1 thread"; then
  ok "closing kept every word of the thread (bus log still reads it)"
else err "the thread's own content was lost when it was closed"; fi

# A REFUSED finish must never close anything: the gate is what decides "done", not
# a side effect of calling kb.sh at all.
cardrepo b2 bus-gate-repo-refused
echo "note for the untouched b2 thread" | $BUS send --repo bus-gate-repo-refused --card b2 --from implementer --to sol-gate >/dev/null 2>&1
if $KB finish b2 --thor "ok" >/dev/null 2>&1 || ! refused b2; then
  err "the refused-evidence fixture for b2 did not stay refused — case not exercised"
elif [ "$(thread_state bus-gate-repo-refused b2)" = "open" ]; then
  ok "a refused finish leaves the bus thread open"
else err "a REFUSED finish still closed the bus thread"; fi

# GUARDED: a repo with no thread at all, and a card with no repo: field, must
# never fail the finish — the bus is a courtesy here, not a dependency.
card b3
if $KB finish b3 --thor "no repo field, verified against kanban/README.md" >/dev/null 2>&1 && accepted b3; then
  ok "a card with no repo: field still finishes (bus close silently skipped)"
else err "a card with no repo: field failed to finish — kb finish must never depend on the bus"; fi

cardrepo b4 bus-gate-repo-no-thread
if $KB finish b4 --thor "repo set, never used the bus, per kanban/README.md" >/dev/null 2>&1 && accepted b4; then
  ok "a repo with no bus thread still finishes"
else err "a card whose repo never used the bus failed to finish"; fi

printf "\n"
[ "$FAIL" -eq 0 ] && { echo "kb done-gate: ALL PASS"; exit 0; }
echo "kb done-gate: FAILURES"; exit 1
