#!/usr/bin/env bash
# PostToolUse auto-format. Silent on success. Never blocks.
# Parametric: repo-root detection instead of a hardcoded frontend path.
# Input contract: hooks receive JSON on stdin (.tool_input.file_path) — the old
# CLAUDE_FILE_PATH env var is kept only as a legacy fallback for manual runs.
set -u
FILE=""
if [ ! -t 0 ]; then
  input="$(cat 2>/dev/null || true)"
  FILE="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
fi
[ -z "$FILE" ] && FILE="${CLAUDE_FILE_PATH:-}"
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Repo-root of the file (worktree-aware) to resolve the local JS toolchain.
repo_root="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)"

case "$FILE" in
  *.py)
    command -v ruff  >/dev/null 2>&1 && ruff check --fix --quiet "$FILE" >/dev/null 2>&1 || true
    command -v black >/dev/null 2>&1 && black --quiet "$FILE"           >/dev/null 2>&1 || true
    ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt --edition 2021 "$FILE" >/dev/null 2>&1 || true
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.svelte|*.json|*.md|*.css|*.html)
    # Find the nearest package.json (file dir → repo root) to use the local prettier.
    pkg_dir=""
    d="$(dirname "$FILE")"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
      if [ -f "$d/package.json" ]; then pkg_dir="$d"; break; fi
      [ "$d" = "$repo_root" ] && break
      d="$(dirname "$d")"
    done
    if [ -n "$pkg_dir" ]; then
      (cd "$pkg_dir" && npx --no-install prettier --write "$FILE" >/dev/null 2>&1) || true
    elif command -v prettier >/dev/null 2>&1; then
      prettier --write "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
esac
exit 0
