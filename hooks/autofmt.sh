#!/usr/bin/env bash
# PostToolUse auto-format. Silenzioso su successo. Non blocca mai.
# Parametrico: repo-root detection invece di path frontend hardcoded.
set -u
FILE="${CLAUDE_FILE_PATH:-}"
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

# Repo-root del file (worktree-aware) per risolvere il toolchain JS locale.
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
    # Trova il package.json più vicino (file dir → repo root) per usare prettier locale.
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
