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
# Both sides of the boundary comparison must be PHYSICAL paths: git answers
# with symlinks resolved (/private/var/... on macOS) while `dirname` preserves
# them (/var/...), so comparing the two raw never matched and every upward walk
# ran past the repo root.
file_dir="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P)" || file_dir="$(dirname "$FILE")"
repo_root="$(git -C "$file_dir" rev-parse --show-toplevel 2>/dev/null || true)"

# Nearest config file walking from the file's directory up to the repo root.
# Bounded at the repo root on purpose: a stray pyproject.toml in a parent
# directory must not opt a repository in behind its back. Outside a repo, only
# the file's own directory is consulted.
find_up() {
  local d="$1"; shift
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    for name in "$@"; do
      [ -f "$d/$name" ] && { printf '%s\n' "$d/$name"; return 0; }
    done
    [ -z "$repo_root" ] && break
    [ "$d" = "$repo_root" ] && break
    d="$(dirname "$d")"
  done
  return 1
}

# Has this repo DECLARED the formatter? $1 = pyproject.toml section pattern,
# remaining args = standalone config filenames that count on their own.
#
# Python formatters used to run everywhere, unlike the prettier branch below
# which only fires where a package.json declares the toolchain. That asymmetry
# rewrote repositories that never asked: black would reformat 63 of 87 files in
# one of them, and `ruff --fix` deletes unused imports - a code change landing
# inside a commit that was about something else. Formatting is now opt-in on
# both sides: declare it, or get your file back byte-identical.
declares() {
  local section="$1"; shift
  local config
  [ "$#" -gt 0 ] && find_up "$file_dir" "$@" >/dev/null && return 0
  config="$(find_up "$file_dir" pyproject.toml)" || return 1
  grep -qE "$section" "$config"
}

case "$FILE" in
  *.py)
    if declares '^\[tool\.ruff' ruff.toml .ruff.toml; then
      command -v ruff >/dev/null 2>&1 && ruff check --fix --quiet "$FILE" >/dev/null 2>&1 || true
    fi
    if declares '^\[tool\.black'; then
      command -v black >/dev/null 2>&1 && black --quiet "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt --edition 2021 "$FILE" >/dev/null 2>&1 || true
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.svelte|*.json|*.md|*.css|*.html)
    # Find the nearest package.json (file dir → repo root) to use the local prettier.
    pkg_dir=""
    d="$file_dir"
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
