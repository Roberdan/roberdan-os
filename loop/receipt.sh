#!/usr/bin/env bash
# loop/receipt.sh — append ONE tool receipt to the loop cursor (.agent-state/<task>.jsonl).
# The emitter the loop-protocol's "tool receipts" contract declares: each record names what
# ran and what it returned, so resume and @thor's provenance gate (#10) have something
# mechanical to probe — a transcript is context, not a recovery log.
#
#   loop/receipt.sh <task-id> <command-ran> <exit-code> [artifact] [note]
#
# Writes to <repo-root>/.agent-state/<task-id>.jsonl when the repo ignores .agent-state
# (roberdan-os does via .gitignore; kb-init'd repos via .git/info/exclude). Otherwise falls
# back to $RDA_HOME/state/receipts/<repo-name>/<task-id>.jsonl so no repo ever gets polluted
# with an untracked dir it didn't opt into. Override the target dir with RDA_RECEIPTS_DIR.
# Append-only, one JSON object per line, jq-escaped. Never fails the caller (exit 0 always).
set -u

task="${1:-}"; cmd="${2:-}"; code="${3:-}"; artifact="${4:-}"; note="${5:-}"
[ -z "$task" ] || [ -z "$cmd" ] || [ -z "$code" ] && {
  echo "usage: receipt.sh <task-id> <command-ran> <exit-code> [artifact] [note]" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
dir="${RDA_RECEIPTS_DIR:-}"
if [ -z "$dir" ]; then
  # probe a path INSIDE the dir: a trailing-slash pattern (".agent-state/") only matches
  # directories, and git can't classify a non-existent bare path as one.
  if [ -n "$repo_root" ] && git -C "$repo_root" check-ignore -q ".agent-state/probe" 2>/dev/null; then
    dir="$repo_root/.agent-state"
  else
    dir="${RDA_HOME:-$HOME/.roberdan-os}/state/receipts/$(basename "${repo_root:-no-repo}")"
  fi
fi
mkdir -p "$dir" 2>/dev/null || exit 0

jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg task "$task" --arg cmd "$cmd" --arg code "$code" \
  --arg artifact "$artifact" --arg note "$note" \
  '{ts:$ts, task:$task, cmd:$cmd, exit:($code|tonumber? // $code), artifact:$artifact, note:$note}' \
  >> "$dir/$task.jsonl" 2>/dev/null || true
exit 0
