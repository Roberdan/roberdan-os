#!/usr/bin/env bash
# PreToolUse Edit|Write guard — blocks writes when the branch is `main`/`master`,
# enforcing branch/worktree discipline. Worktree-aware: resolves the FILE's repo,
# not the CWD's (worktrees have their own HEAD).
# Escape hatch (emergency hotfix only): RDA_ALLOW_MAIN_WRITES=1
set -euo pipefail

[ "${RDA_ALLOW_MAIN_WRITES:-0}" = "1" ] && exit 0

input="$(cat)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"
# Decide on the RESOLVED path: a symlink named *.md pointing at source would otherwise
# satisfy the meta/docs carve-out below. Same class as claude-code v2.1.251 (Read/Write/Edit
# following a symlink swapped after the permission check). New file (Write case): no target
# to resolve yet, so the literal path is kept.
# `-e` alone misses a DANGLING symlink (target doesn't exist yet — a Write through it would
# create the target): `-e` follows the link and is false there, and /bin/realpath fails
# outright on any missing final component, dangling symlink included. So the name is resolved
# by hand first (bounded to 10 hops against a cycle), THEN realpath is tried once the trailing
# component, if any, actually exists.
_hops=0
while [ -L "$fp" ] && [ "$_hops" -lt 10 ]; do
  _target="$(readlink "$fp")"
  case "$_target" in
    /*) fp="$_target" ;;
    *) fp="$(dirname "$fp")/$_target" ;;
  esac
  _hops=$((_hops + 1))
done
if [ -e "$fp" ]; then fp="$(/bin/realpath "$fp" 2>/dev/null || printf '%s' "$fp")"; fi

lookup_dir=""
if [ -n "$fp" ]; then
  if [ -d "$fp" ]; then lookup_dir="$fp"; else lookup_dir="$(dirname "$fp")"; fi
fi
repo_root="$(git -C "${lookup_dir:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# Carve-out: meta/docs editable on main (markdown, .claude/**, config, ADR).
case "$fp" in
  *.md|*/.claude/*|*/docs/*|*/.env.example|*/.gitignore)
    exit 0 ;;
esac

if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  jq -cn --arg reason "MainGuard: writes on $branch are blocked. Create a worktree or a feature branch. Override: RDA_ALLOW_MAIN_WRITES=1 (emergency only)." '{
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason }
  }'
  exit 0
fi
exit 0
