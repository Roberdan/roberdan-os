#!/usr/bin/env bash
# PreToolUse Bash guard for UNATTENDED factory runs only (factory/run.sh + verify_card in
# factory/lib.sh load it with --settings). Interactive sessions never see it.
#
# Why a second guard: auto mode's classifier decides case by case. Measured 2026-09-12, the
# same `git commit --amend` prompt was denied twice and allowed five times (launchd and
# foreground, v2.1.269 and v2.1.270). A run nobody watches needs a list that says no every
# time for what AGENTS.md reserves to Roberto: pushing, rewriting history, forced deletion.
#
# Deliberately stricter than hooks/bash-guard.sh, which serves a person at the keyboard:
#   - it matches the RAW command, quoted strings and heredoc bodies included. `bash -c "git push"`
#     is caught; `git commit -m "never git push"` is a false positive, and in a factory run
#     the price is one refused command, not an annoyed human switching the guard off;
#   - everything here is deny, never ask: a headless run has nobody to ask.
# Not a sandbox: a script written to a file and then run, or a python/node subprocess, does
# not pass through this text. It removes the direct path, not every path.
# Requires `jq`; without it the guard fails CLOSED.
set -euo pipefail

input="$(cat)"
deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
command -v jq >/dev/null 2>&1 || deny "factory-guard: jq missing, refusing every Bash command in an unattended run."
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
# Quote and backslash CHARACTERS are deleted (not the quoted text): `git "commit" --am"end"` and
# `git\ push` run exactly like the plain spelling, so they must read like it too.
norm="$(printf '%s' "$cmd" | tr -d "\"'\\\\" | tr -s ' \t\n\r' ' ')"

why="Unattended factory run: pushing, rewriting git history and forced deletion are Roberto's gates. Leave it as a proposal in your report instead."
# `git`, optionally followed by global options (-C dir, -c k=v, --git-dir=...), then the subcommand.
G='(^|[^[:alnum:]_./-])git(([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)|([[:space:]]+--?[[:alnum:]-]+(=[^[:space:]]+)?))*[[:space:]]+'
hit() { printf '%s' "$norm" | grep -qE -- "$1"; }

hit "${G}push([[:space:]]|$)"                                   && deny "git push refused. $why"
hit "${G}commit([[:space:]].*)?[[:space:]]--am(e|en|end)?([[:space:]=]|$)"               && deny "git commit --amend refused. $why"
hit "${G}(rebase|filter-branch|filter-repo|replace)([[:space:]]|$)" && deny "git history rewrite refused. $why"
hit "${G}reset([[:space:]].*)?[[:space:]]--(hard|keep|merge)"    && deny "git reset --hard refused. $why"
hit "${G}clean([[:space:]].*)?[[:space:]]-[[:alpha:]]*f"         && deny "git clean -f refused. $why"
hit "${G}branch([[:space:]].*)?[[:space:]](-D|--delete[[:space:]].*--force|--force[[:space:]].*--delete)" && deny "forced branch deletion refused. $why"
hit "${G}(update-ref([[:space:]].*)?[[:space:]]-d|reflog[[:space:]]+(expire|delete)|stash[[:space:]]+(drop|clear)|gc([[:space:]].*)?[[:space:]]--prune)" && deny "deleting git refs or objects refused. $why"
hit '--no-verify'                                                && deny "--no-verify refused. $why"
hit '(^|[^[:alnum:]_-])rm[[:space:]]+(.*[[:space:]])?(-[[:alpha:]]*[rR][[:alpha:]]*f|-[[:alpha:]]*f[[:alpha:]]*[rR])' && deny "rm -rf refused. $why"
hit '(^|[^[:alnum:]_-])rm[[:space:]]+(.*[[:space:]])?(-[rR]|--recursive)[[:space:]](.*[[:space:]])?(-f|--force)([[:space:]]|$)' && deny "rm -r -f refused. $why"
hit '(^|[^[:alnum:]_-])rm[[:space:]]+(.*[[:space:]])?(-f|--force)[[:space:]](.*[[:space:]])?(-[rR]|--recursive)([[:space:]]|$)' && deny "rm -f -r refused. $why"
hit '(^|[^[:alnum:]_-])find[[:space:]].*[[:space:]]-delete([[:space:]]|$)' && deny "find -delete refused. $why"
hit '(^|[^[:alnum:]_-])gh[[:space:]]+(pr[[:space:]]+(create|merge|close|edit|comment|review|ready)|issue[[:space:]]+(create|close|edit|comment|delete|transfer)|release|repo[[:space:]]+(create|delete|edit|rename|archive|fork)|secret|variable|workflow[[:space:]]+run)([[:space:]]|$)' && deny "gh write action refused. $why"
hit '(^|[^[:alnum:]_-])gh[[:space:]]+api[[:space:]].*(-X|--method)[[:space:]]*(POST|PUT|PATCH|DELETE)' && deny "gh api write refused. $why"

exit 0
