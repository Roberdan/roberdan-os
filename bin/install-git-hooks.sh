#!/usr/bin/env bash
# bin/install-git-hooks.sh — installs the repo's native git hooks (.git/hooks is not
# versioned by git, so this is the one-time step that wires hooks/pre-commit in).
# Idempotent: safe to re-run. Run this once per clone/worktree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITDIR="$(git -C "$ROOT" rev-parse --git-dir)"

install_hook() {
  local name="$1" src="$ROOT/hooks/$1" dst="$GITDIR/hooks/$1"
  [ -f "$src" ] || { echo "install-git-hooks: skip $name (no hooks/$name in repo)"; return 0; }
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "install-git-hooks: installed $name -> $dst"
}

install_hook pre-commit
