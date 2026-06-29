#!/usr/bin/env bash
# PreToolUse Edit|Write guard — blocca le scritture quando il branch è `main`/`master`,
# forzando la disciplina branch/worktree. Worktree-aware: risolve il repo del FILE,
# non della CWD (i worktree hanno HEAD propri).
# Escape hatch (solo hotfix d'emergenza): RDA_ALLOW_MAIN_WRITES=1
set -euo pipefail

[ "${RDA_ALLOW_MAIN_WRITES:-0}" = "1" ] && exit 0

input="$(cat)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"

lookup_dir=""
if [ -n "$fp" ]; then
  if [ -d "$fp" ]; then lookup_dir="$fp"; else lookup_dir="$(dirname "$fp")"; fi
fi
repo_root="$(git -C "${lookup_dir:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# Carve-out: meta/docs editabili su main (markdown, .claude/**, config, ADR).
case "$fp" in
  *.md|*/.claude/*|*/docs/*|*/.env.example|*/.gitignore)
    exit 0 ;;
esac

if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  jq -cn --arg reason "MainGuard: scritture su $branch bloccate. Crea un worktree o un feature branch. Override: RDA_ALLOW_MAIN_WRITES=1 (solo emergenza)." '{
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason }
  }'
  exit 0
fi
exit 0
