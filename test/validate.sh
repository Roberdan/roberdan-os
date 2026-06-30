#!/usr/bin/env bash
# validate.sh — gate CI di roberdan-os. Eseguito su ogni PR.
# 1) frontmatter lint (agents vs skills: schemi distinti)  2) link check (esenta [[wikilink]])
# 3) drift check (wrapper rigenerati == committati)  4) shellcheck  5) leak check
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()      { printf "  ok: %s\n" "$1"; }

# --- 1) Frontmatter lint -----------------------------------------------------
section "frontmatter — agents (name, description, model, tools, constraints, version, maturity)"
for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  miss=""
  for k in name description model tools constraints version maturity; do
    grep -qE "^$k:" "$a" || miss="$miss $k"
  done
  # model deve essere quotato
  if grep -qE '^model:' "$a" && ! grep -qE '^model:[[:space:]]*"' "$a"; then
    miss="$miss model-not-quoted"
  fi
  [ -n "$miss" ] && err "$a manca:$miss" || ok "$(basename "$a")"
done

section "frontmatter — skills (name, description, providers)"
for s in $(find skills -maxdepth 2 -name 'skill.md' | LC_ALL=C sort); do
  miss=""
  for k in name description providers; do
    grep -qE "^$k:" "$s" || miss="$miss $k"
  done
  [ -n "$miss" ] && err "$s manca:$miss" || ok "$s"
done

# --- 2) Link check (markdown relativi; esenta [[wikilink]] e http) -----------
section "link check (relative markdown; [[wikilink]] esenti)"
broken=0
for md in $(git ls-files '*.md' | LC_ALL=C sort); do
  dir="$(dirname "$md")"
  # estrae i target di [text](path) escludendo http(s) e ancore pure (#...)
  grep -oE '\]\([^)# ][^)]*\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*) continue ;;
    esac
    target="${link%%#*}"                      # toglie eventuale ancora
    [ -z "$target" ] && continue
    resolved="$dir/$target"
    if [ ! -e "$resolved" ]; then
      printf "  FAIL: %s → link rotto: %s\n" "$md" "$link"
      echo "BROKEN" >> /tmp/rda-linkcheck.$$
    fi
  done
done
if [ -f "/tmp/rda-linkcheck.$$" ]; then broken=$(wc -l < "/tmp/rda-linkcheck.$$"); rm -f "/tmp/rda-linkcheck.$$"; fi
[ "$broken" -gt 0 ] && FAIL=1 || ok "tutti i link relativi risolvono"

# --- 3) Drift check (emit deterministico == committato) ----------------------
section "drift check — wrapper rigenerati == committati"
bash bin/sync.sh --emit-only >/dev/null 2>&1
# git status --porcelain cattura sia i tracked modificati sia i nuovi untracked (bundle.md è gitignored, escluso).
drift_out="$(git status --porcelain -- platforms/ 2>/dev/null)"
if [ -z "$drift_out" ]; then
  ok "nessun drift (platforms/ in sync col canone, inclusi file nuovi)"
else
  err "drift: platforms/ diverge dal canone. Esegui bin/sync.sh --emit-only e committa."
  printf '%s\n' "$drift_out" | sed 's/^/    /'
fi

# --- 4) Shellcheck -----------------------------------------------------------
section "shellcheck (hooks + bin + test)"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning hooks/*.sh bin/*.sh test/*.sh; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck non installato\n"
  for f in hooks/*.sh bin/*.sh test/*.sh; do bash -n "$f" || err "syntax: $f"; done
fi

# --- 5) Leak check (privacy gate) --------------------------------------------
section "leak check (privacy gate)"
if bash test/leak-check.sh >/dev/null 2>&1; then ok "0 termini confidenziali"; else err "LEAK confidenziale — vedi test/leak-check.sh"; fi

# --- Esito -------------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "validate: ✅ TUTTO VERDE"; exit 0; else echo "validate: ❌ FAIL (vedi sopra)"; exit 1; fi
