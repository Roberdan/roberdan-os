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

# 3) Destructive reset/clean on history or working tree → confirm.
if printf '%s' "$norm" | grep -qE 'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)'; then
  ask "git reset --hard / clean -f destroys uncommitted changes. Explicit confirmation required before proceeding."
fi

# 4) A `docs(...)` commit must never carry source. `git add -A` does not stage YOUR work —
#    it stages whatever is in the tree, including another process's in-flight edits.
#    Real scar (2026-07-14): @thor was mutation-testing (deliberately reintroducing a clock bug
#    to prove the test caught it) in the same checkout where the orchestrator ran
#    `git add -A && git commit -m "docs(...)"`. The mutation was swept in and PUSHED: a
#    clinical-safety regression shipped inside a documentation commit, every gate green.
#    Staging docs by explicit path costs nothing and makes that impossible.
#    Match on the COMMAND ONLY: strip quoted strings first, so a commit message that *mentions*
#    `git add -A` (e.g. this very rule's changelog) is not itself blocked. That false positive is
#    not hypothetical — it fired on the commit introducing this guard.
cmd_nostr="$(printf '%s' "$cmd" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")"
if printf '%s' "$cmd_nostr" | grep -qE 'git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qiE '\-m[[:space:]]*["'"'"']?(docs|chore\(docs)'; then
  deny "A docs commit must not be staged with 'git add -A': a blanket add stages whatever is in the tree right now — including another agent's in-flight edits (e.g. a mutation test). Stage by explicit path: git add path/to/doc.md"
fi

exit 0
