#!/usr/bin/env bash
# Pre-completion gate hook for Claude Code.
#
# Fires on every Stop event. Surfaces anything that would make a
# "done"/"finished" claim premature:
#
#   - open PRs on the current repo
#   - orphan agent worktrees (ghosts after kill or reaper)
#   - rogue copilot/claude runners spawned by convergio dispatcher
#   - stale `agent_processes.status='running'` rows in convergio DB
#   - uncommitted changes on the main checkout
#
# Output is intentionally short — one line per finding, prefixed
# `⚠️ PRE-COMPLETION:` so Claude (and the operator) see them before
# the turn closes. Stays silent when everything is clean.
#
# Driven by the 2026-05-10 insights report: "Claude occasionally
# claims 'done' before PRs are merged, validation gates pass, or
# deployments are verified." This hook makes that claim impossible
# without first noticing the open work.
#
# Non-blocking: every step has `|| true` so a transient `gh` or
# `sqlite3` error never interrupts the user's flow. Exit 0 always.

set +e

emit() { printf "⚠️  PRE-COMPLETION: %s\n" "$*"; }

# Resolve a git repo root if we are inside one. Skip the entire gate
# when not in a repo (saves overhead in non-coding sessions).
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$repo_root" ] && exit 0

cd "$repo_root" || exit 0

# 1. Uncommitted changes on the operator's main checkout.
#    Worktrees are gitignored so they don't pollute this check; only
#    the canonical checkout's status counts.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  emit "uncommitted changes in $repo_root (run \`git status\`)"
fi

# 2. Open PRs against this repo (any state user owns).
if command -v gh >/dev/null 2>&1; then
  open_prs=$(gh pr list --state open --json number,title,headRefName 2>/dev/null \
    | jq -r '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null \
    | head -5)
  if [ -n "$open_prs" ]; then
    while IFS= read -r line; do
      emit "open PR: $line"
    done <<< "$open_prs"
  fi
fi

# 3. Orphan agent-worktrees (look for `agent-` prefixed dirs).
if [ -d ".claude/worktrees" ]; then
  wt_count=$(find .claude/worktrees -maxdepth 1 -type d -name 'agent-*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$wt_count" -gt 0 ]; then
    emit "$wt_count agent worktree(s) still present under .claude/worktrees/"
  fi
fi

# 4. Convergio runners spawned by the dispatcher (rogue or active).
copilot_count=$(pgrep -f "copilot.*--allow-all" 2>/dev/null | wc -l | tr -d ' ')
if [ "$copilot_count" -gt 0 ]; then
  emit "$copilot_count copilot runner(s) alive — verify they belong to a live convergio task"
fi

# 5. Stale agent_processes rows in convergio state.db (rows marked
#    running with no matching live PID).
db=$HOME/.convergio/v3/state.db
if [ -f "$db" ] && command -v sqlite3 >/dev/null 2>&1; then
  running_pids=$(sqlite3 "$db" \
    "SELECT pid FROM agent_processes WHERE status='running' AND pid IS NOT NULL;" 2>/dev/null)
  if [ -n "$running_pids" ]; then
    stale=0
    while IFS= read -r pid; do
      [ -z "$pid" ] && continue
      kill -0 "$pid" 2>/dev/null || stale=$((stale + 1))
    done <<< "$running_pids"
    if [ "$stale" -gt 0 ]; then
      emit "$stale stale agent_processes row(s) in state.db (pid dead, status='running')"
    fi
  fi
fi

exit 0
