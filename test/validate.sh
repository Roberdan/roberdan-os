#!/usr/bin/env bash
# validate.sh — roberdan-os CI gate. Runs on every PR.
# 1) frontmatter lint (agents vs skills: distinct schemas)  2) link check (exempts [[wikilink]])
# 3) drift check (generation is deterministic)  4) shellcheck  5) leak check
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
  # model must be quoted
  if grep -qE '^model:' "$a" && ! grep -qE '^model:[[:space:]]*"' "$a"; then
    miss="$miss model-not-quoted"
  fi
  [ -n "$miss" ] && err "$a missing:$miss" || ok "$(basename "$a")"
done

section "frontmatter — skills (name, description, providers)"
for s in $(find skills -maxdepth 2 -name 'skill.md' | LC_ALL=C sort); do
  miss=""
  for k in name description providers; do
    grep -qE "^$k:" "$s" || miss="$miss $k"
  done
  [ -n "$miss" ] && err "$s missing:$miss" || ok "$s"
done

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
rm -rf "$d1" "$d2"

# --- 4) Shellcheck -----------------------------------------------------------
section "shellcheck (hooks + bin + test)"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning hooks/*.sh bin/*.sh test/*.sh; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck not installed\n"
  for f in hooks/*.sh bin/*.sh test/*.sh; do bash -n "$f" || err "syntax: $f"; done
fi

# --- 5) Leak check (privacy gate) --------------------------------------------
section "leak check (privacy gate)"
if bash test/leak-check.sh >/dev/null 2>&1; then ok "0 confidential terms"; else err "confidential LEAK — see test/leak-check.sh"; fi

# --- 6) Factory + kb gates (real assertions, not a smoke test) ---------------
section "factory + kb gates"
if bash test/test-factory-kb.sh >/dev/null 2>&1; then ok "kb gates + factory guardrails green"; else err "test-factory-kb — see bash test/test-factory-kb.sh"; fi

# --- 7) Leak-check self-test (salted-hash tier b) -----------------------------
section "leak-check self-test — tier (b) salted-hash catches a planted leak"
if bash test/test-leak-check.sh >/dev/null 2>&1; then ok "leak-check tiers verified (see bash test/test-leak-check.sh)"; else err "test-leak-check — see bash test/test-leak-check.sh"; fi

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "validate: ✅ ALL GREEN"; exit 0; else echo "validate: ❌ FAIL (see above)"; exit 1; fi
