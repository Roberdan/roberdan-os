#!/usr/bin/env bash
# Stop hook. Soft verification — warns on stderr, never blocks (always exit 0).
# Surfaces: dirty repo, version drift, commit on main without a bump.
# Parametric: no hardcoded paths. Repo-root = CWD; version-file via RDA_VERSION_FILE
# (default: first among VERSION, VERSION.md, package.json, Cargo.toml, pyproject.toml).
set -u

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

WARN=""

# 1. Uncommitted changes
if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
  WARN+="• uncommitted changes present\n"
fi

# 2. Version drift — compares the canonical version-file against any manifest.
vfile="${RDA_VERSION_FILE:-}"
if [ -z "$vfile" ]; then
  for c in VERSION VERSION.md package.json Cargo.toml pyproject.toml; do
    [ -f "$c" ] && { vfile="$c"; break; }
  done
fi
# Top-level manifest version only — the first bare regex hit could match a dependency.
_manifest_version() {
  case "$1" in
    package.json)   grep -m1 '"version"' "$1" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    Cargo.toml)     awk '/^\[package\]/{f=1;next} /^\[/{f=0} f && /^version[[:space:]]*=/{print;exit}' "$1" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    pyproject.toml) awk '/^\[(project|tool.poetry)\]/{f=1;next} /^\[/{f=0} f && /^version[[:space:]]*=/{print;exit}' "$1" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    *)              grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$1" 2>/dev/null | head -1 ;;
  esac
}
if [ -n "$vfile" ] && [ -f "$vfile" ]; then
  V1=$(_manifest_version "$vfile")
  for m in package.json Cargo.toml pyproject.toml; do
    [ "$m" = "$vfile" ] && continue
    [ -f "$m" ] || continue
    V2=$(_manifest_version "$m")
    if [ -n "$V1" ] && [ -n "$V2" ] && [ "$V1" != "$V2" ]; then
      WARN+="• version drift: $vfile ($V1) != $m ($V2)\n"
    fi
  done
fi

# 3. Last commit on main without a version/changelog bump
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  LAST=$(git log -1 --name-only --pretty=format: 2>/dev/null)
  if ! printf '%s' "$LAST" | grep -qiE '(VERSION|CHANGELOG)'; then
    WARN+="• last commit on $BRANCH without a VERSION/CHANGELOG update\n"
  fi
fi

[ -n "$WARN" ] && printf "\n[verify-done] Review before declaring done:\n%b\n" "$WARN" >&2
exit 0
