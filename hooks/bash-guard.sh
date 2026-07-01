#!/usr/bin/env bash
# PreToolUse Bash guard — only the universal git/gh half (security, not token-saving).
# npm/test-runner rules are per-repo and do NOT live here (see repo-local hook).
# Requires `jq`.
set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"

deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }

# Truncate the heredoc body (data, not commands) to avoid false positives on commit messages.
cmd_head="${cmd%%<<*}"
norm="$(printf '%s' "$cmd_head" | tr -s ' \t\n' ' ' | sed 's/^ //;s/ $//')"

# 1) Dangerous pushes: --force / -f / --no-verify → always forbidden (irreversible action).
if printf '%s' "$norm" | grep -qE 'git[[:space:]]+push.*(--no-verify|(^|[[:space:]])-f([[:space:]]|$)|--force)'; then
  deny "--no-verify / --force on git push are forbidden. Fix the cause (failed hook, conflict), don't bypass it. Human gate #2 for force-push on main."
fi

# 2) gh pr merge → requires explicit human approval (human gate #1).
if printf '%s' "$norm" | grep -qE '^gh[[:space:]]+pr[[:space:]]+merge'; then
  ask "Before merging: 'gh pr checks <n>', paste the output, confirm all SUCCESS, and get an explicit 'yes' from the user. See skills/ship."
fi

# 3) Destructive reset/clean on history or working tree → confirm.
if printf '%s' "$norm" | grep -qE 'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)'; then
  ask "git reset --hard / clean -f destroys uncommitted changes. Explicit confirmation required before proceeding."
fi

exit 0
