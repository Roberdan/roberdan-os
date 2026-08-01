#!/usr/bin/env bash
# test-plan-coverage.sh — ogni clausola normativa del piano ha una card o una decisione scritta
#
# Estratto da test/validate.sh il 2026-07-31. Da qui si lancia anche da solo:
#   bash test/test-plan-coverage.sh
# che prima non si poteva: bisognava aspettare l'intera suite per leggere queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

# --- 11) plan coverage (every normative plan clause maps to a card) -----------
# The plan→card step is the ONLY link in the chain with no gate — and it is exactly where
# requirements die. Every other gate (kb, @thor, the merge-gate, CI) operates DOWNSTREAM of the
# card, so a requirement that never BECOMES a card is invisible to all of them simultaneously.
# (trading-os, 2026-07-13: the signed plan mandated SEC EDGAR/RSS + company IR + GDELT; the only
# card that could have delivered it said "at least one mandatory free live source", closed honestly
# green, and the news evaporated. An audit found 77 of 149 normative clauses never reached the
# product.) `kb cover` walks FROM the plan: a board cannot show you the ABSENCE of a card.
section "plan coverage (every normative clause of docs/plan.md has a card or a written decision)"
if [ -f "$ROOT/docs/plan.md" ]; then
  if RDA_KANBAN="$ROOT/kanban" bash "$ROOT/kanban/kb.sh" cover "$ROOT/docs/plan.md" > /tmp/kbcover.$$ 2>&1; then
    ok "$(tail -2 /tmp/kbcover.$$ | head -1 | sed 's/^ *//')"
  else
    err "a plan clause has no card and no written decision — run: kb cover docs/plan.md"
    sed 's/^/    /' /tmp/kbcover.$$
  fi
  rm -f /tmp/kbcover.$$
else
  skip "no docs/plan.md"
fi


[ "$FAIL" -eq 0 ] && { echo; echo "test-plan-coverage: PASS"; exit 0; }
echo; echo "test-plan-coverage: FAIL"; exit 1
