#!/usr/bin/env bash
# Stop / SubagentStop hook — regenerate per-platform wrappers + privacy leak-check.
# (It does NOT sync the vault or Convergio — that's the /sync skill's job.)
# Mechanizes the end-of-task refresh: regenerates the per-platform wrappers from the canon
# on disk so the local ~/.claude/etc. stay fresh. Never blocks (exit 0). Never pushes.
#
# platforms/ is gitignored and never committed (see .gitignore, bin/sync.sh) — this hook
# only regenerates it locally; it does NOT commit it. If any *other* canon-derived,
# tracked file needs a commit, add it explicitly below.
#
# OPT-IN: active only with RDA_AUTOSYNC=1 — running sync on every Stop would be
# invasive as a default. Without the flag, it exits immediately (no-op).
set -u

[ "${RDA_AUTOSYNC:-0}" = "1" ] || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

# Only acts inside roberdan-os (presence of canonical AGENTS.md + bin/sync.sh).
[ -f "$repo_root/AGENTS.md" ] && [ -f "$repo_root/bin/sync.sh" ] || exit 0

# 1) Regenerate the per-platform wrappers from the canon (idempotent, dry-run-safe,
#    gitignored — this never touches git state).
if [ -x "$repo_root/bin/sync.sh" ]; then
  "$repo_root/bin/sync.sh" --emit-only >/dev/null 2>&1 || true
fi

# 2) Privacy gate — surfaced even though there's nothing left here to commit, in case a
#    future tracked derivative is added to this hook.
if [ -x "$repo_root/test/leak-check.sh" ]; then
  if ! "$repo_root/test/leak-check.sh" >/dev/null 2>&1; then
    printf "\n[post-task-sync] LEAK detected in the canon.\n" >&2
  fi
fi

exit 0
