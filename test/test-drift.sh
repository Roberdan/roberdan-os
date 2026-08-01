#!/usr/bin/env bash
# test-drift.sh — la generazione di bin/sync.sh e deterministica
#
# Estratto da test/validate.sh il 2026-07-31. Da qui si lancia anche da solo:
#   bash test/test-drift.sh
# che prima non si poteva: bisognava aspettare l'intera suite per leggere queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

# --- 3) Drift check (generation is deterministic) -----------------------------
# platforms/ is no longer committed (fully generated — see .gitignore). Instead of
# diffing regenerated output against a committed copy, verify bin/sync.sh --emit-only
# is deterministic and succeeds: two independent runs into two temp dirs must be
# byte-identical.
section "drift check — bin/sync.sh --emit-only is deterministic"
d1="$(mktemp -d "${TMPDIR:-/tmp}/rda-sync-check.XXXXXX")"
d2="$(mktemp -d "${TMPDIR:-/tmp}/rda-sync-check.XXXXXX")"
rc1=0; rc2=0
RDA_SYNC_OUT="$d1" bash bin/sync.sh --emit-only >/dev/null 2>&1 || rc1=$?
RDA_SYNC_OUT="$d2" bash bin/sync.sh --emit-only >/dev/null 2>&1 || rc2=$?
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  err "drift: bin/sync.sh --emit-only exited non-zero (run1=$rc1 run2=$rc2)"
elif diff_out="$(diff -r "$d1" "$d2" 2>&1)" && [ -z "$diff_out" ]; then
  ok "generation is deterministic (two independent runs are byte-identical)"
else
  err "drift: bin/sync.sh --emit-only is non-deterministic across runs"
  printf '%s\n' "$diff_out" | sed 's/^/    /'
fi
# H1 guard (rex, HIGH 2026-07-07): the emitted settings snippet must contain NO
# unexpanded $VAR — an undefined var expands empty on merge and kills the hooks silently.
if [ -f "$d1/claude/settings-hooks.json" ]; then
  if grep -qE '\$[A-Za-z_]' "$d1/claude/settings-hooks.json"; then
    err "settings-hooks.json carries an unexpanded \$VAR (hooks would die silently on a fresh merge)"
  else
    ok "settings-hooks.json fully expanded (absolute hook paths, no \$VAR)"
  fi
else
  err "settings-hooks.json missing from emitted output"
fi
rm -rf "$d1" "$d2"


[ "$FAIL" -eq 0 ] && { echo; echo "test-drift: PASS"; exit 0; }
echo; echo "test-drift: FAIL"; exit 1
