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
export RDA_KANBAN_REGISTRY="$TMP/registry"
mkdir -p "$RDA_KANBAN"/{todo,doing,done}
: > "$RDA_KANBAN_REGISTRY"

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

section "the accepted card records the evidence"
if grep -q "^verified_evidence:" "$RDA_KANBAN/done/a2.md" 2>/dev/null; then
  ok "verified_evidence is persisted on the card"
else err "verified_evidence missing from the closed card"; fi

printf "\n"
[ "$FAIL" -eq 0 ] && { echo "kb done-gate: ALL PASS"; exit 0; }
echo "kb done-gate: FAILURES"; exit 1
