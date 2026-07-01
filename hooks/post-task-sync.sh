#!/usr/bin/env bash
# Stop / SubagentStop hook — anti-drift for the 3 systems (vault + Convergio + repo).
# Mechanizes the end-of-task sync: regenerates the wrappers from the canon and commits a
# `chore(sync)` IF something changed. Never blocks (exit 0). Never pushes.
#
# OPT-IN: active only with RDA_AUTOSYNC=1 — an auto-commit on every Stop would be
# invasive as a default. Without the flag, it exits immediately (no-op).
set -u

[ "${RDA_AUTOSYNC:-0}" = "1" ] || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

# Only acts inside roberdan-os (presence of canonical AGENTS.md + bin/sync.sh).
[ -f "$repo_root/AGENTS.md" ] && [ -f "$repo_root/bin/sync.sh" ] || exit 0

changed=""

# 1) Regenerate the per-platform wrappers from the canon (idempotent, dry-run-safe).
if [ -x "$repo_root/bin/sync.sh" ]; then
  "$repo_root/bin/sync.sh" --emit-only >/dev/null 2>&1 || true
fi

# 2) Privacy gate before any sync commit.
if [ -x "$repo_root/test/leak-check.sh" ]; then
  if ! "$repo_root/test/leak-check.sh" >/dev/null 2>&1; then
    printf "\n[post-task-sync] LEAK detected — sync aborted, no commit.\n" >&2
    exit 0
  fi
fi

# 3) Commit chore(sync) only if the working tree (excluding private/) has changed derivatives.
if [ -n "$(git status --porcelain -- . ':!:private/**' 2>/dev/null | head -1)" ]; then
  git add -- platforms/ 2>/dev/null || true
  if [ -n "$(git diff --cached --name-only 2>/dev/null | head -1)" ]; then
    git commit -q -m "chore(sync): regenerate per-platform wrappers from the canon" 2>/dev/null || true
    changed="yes"
  fi
fi

[ -n "$changed" ] && printf "\n[post-task-sync] wrappers regenerated and committed (chore sync).\n" >&2
exit 0
