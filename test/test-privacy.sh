#!/usr/bin/env bash
# test-privacy.sh — nessun termine riservato nel canone pubblico
#
# Estratto da test/validate.sh il 2026-07-31. Da qui si lancia anche da solo:
#   bash test/test-privacy.sh
# che prima non si poteva: bisognava aspettare l'intera suite per leggere queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

# --- 5) Leak check (privacy gate) --------------------------------------------
section "leak check (privacy gate)"
if bash test/leak-check.sh >/dev/null 2>&1; then ok "0 confidential terms"; else err "confidential LEAK — see test/leak-check.sh"; fi

# The cards carry real names and clients and this remote is public, so
# .gitignore:7-9 excludes kanban/todo|doing|done. That exclusion is NOT stable
# on its own: git collects ignore rules per directory, not per repository, and a
# DEEPER .gitignore overrides a shallower one. The private card repo nested at
# kanban/ ships its own .gitignore, and its first version was an allowlist whose
# `!todo/**` silently re-included all 69 cards here as addable. Asserting the
# outcome instead of the rule: whatever any .gitignore at any depth says, a card
# must still be ignored by THIS repo. `git check-ignore` exits 1 when the path
# is NOT ignored, which is the failure we want to catch.
_ignore_probe="kanban/todo/.rda-ignore-probe.md"
mkdir -p kanban/todo && : > "$_ignore_probe"
if git check-ignore -q "$_ignore_probe"; then
  ok "kanban cards ignored by the public repo (no .gitignore at any depth re-includes them)"
else
  err "kanban cards are NOT ignored — a negation somewhere re-included them; run: git check-ignore -v $_ignore_probe"
fi
rm -f "$_ignore_probe"


[ "$FAIL" -eq 0 ] && { echo; echo "test-privacy: PASS"; exit 0; }
echo; echo "test-privacy: FAIL"; exit 1
