#!/usr/bin/env bash
# test-links.sh — i link markdown relativi puntano a qualcosa che esiste
#
# Estratto da test/validate.sh il 2026-07-31. Da qui si lancia anche da solo:
#   bash test/test-links.sh
# che prima non si poteva: bisognava aspettare l'intera suite per leggere queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

# --- 2) Link check (relative markdown; exempts [[wikilink]] and http) --------
section "link check (relative markdown; [[wikilink]] exempted)"
broken=0
for md in $(git ls-files '*.md' | LC_ALL=C sort); do
  dir="$(dirname "$md")"
  # extracts [text](path) targets, excluding http(s) and pure anchors (#...)
  grep -oE '\]\([^)# ][^)]*\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*) continue ;;
    esac
    target="${link%%#*}"                      # strips any anchor
    [ -z "$target" ] && continue
    resolved="$dir/$target"
    if [ ! -e "$resolved" ]; then
      printf "  FAIL: %s → broken link: %s\n" "$md" "$link"
      echo "BROKEN" >> /tmp/rda-linkcheck.$$
    fi
  done
done
if [ -f "/tmp/rda-linkcheck.$$" ]; then broken=$(wc -l < "/tmp/rda-linkcheck.$$"); rm -f "/tmp/rda-linkcheck.$$"; fi
[ "$broken" -gt 0 ] && FAIL=1 || ok "all relative links resolve"

[ "$FAIL" -eq 0 ] && { echo; echo "test-links: PASS"; exit 0; }
echo; echo "test-links: FAIL"; exit 1
