#!/usr/bin/env bash
# Stop hook. Verifica soft — avvisa su stderr, non blocca mai (exit 0 sempre).
# Fa emergere: repo dirty, version drift, commit su main senza bump.
# Parametrico: nessun path hardcoded. Repo-root = CWD; version-file via RDA_VERSION_FILE
# (default: primo tra VERSION, VERSION.md, package.json, Cargo.toml, pyproject.toml).
set -u

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

WARN=""

# 1. Modifiche non committate
if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
  WARN+="• modifiche non committate presenti\n"
fi

# 2. Version drift — confronta il version-file canonico con eventuale manifest.
vfile="${RDA_VERSION_FILE:-}"
if [ -z "$vfile" ]; then
  for c in VERSION VERSION.md package.json Cargo.toml pyproject.toml; do
    [ -f "$c" ] && { vfile="$c"; break; }
  done
fi
if [ -n "$vfile" ] && [ -f "$vfile" ]; then
  V1=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$vfile" 2>/dev/null | head -1)
  for m in package.json Cargo.toml pyproject.toml; do
    [ "$m" = "$vfile" ] && continue
    [ -f "$m" ] || continue
    V2=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$m" 2>/dev/null | head -1)
    if [ -n "$V1" ] && [ -n "$V2" ] && [ "$V1" != "$V2" ]; then
      WARN+="• version drift: $vfile ($V1) != $m ($V2)\n"
    fi
  done
fi

# 3. Ultimo commit su main senza bump version/changelog
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  LAST=$(git log -1 --name-only --pretty=format: 2>/dev/null)
  if ! printf '%s' "$LAST" | grep -qiE '(VERSION|CHANGELOG)'; then
    WARN+="• ultimo commit su $BRANCH senza update VERSION/CHANGELOG\n"
  fi
fi

[ -n "$WARN" ] && printf "\n[verify-done] Rivedi prima di dichiarare done:\n%b\n" "$WARN" >&2
exit 0
