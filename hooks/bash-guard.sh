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
# Quoted strings are DATA, not command tokens. Rule 4 already stripped them for itself; rules
# 1 and 3 read the raw text and so denied `git commit -m '...never use --force...'` — a guard
# that blocks the innocent gets switched off by the first person it annoys, and a switched-off
# guard is worth exactly as much as no guard. Declared tradeoff: a flag hidden inside quotes
# (`git push "--force"`) is no longer caught. This is a discipline gate against slips, not an
# adversary — and evading it takes more deliberate effort than just not using the flag.
norm="$(printf '%s' "$cmd_head" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g" | tr -s ' \t\n' ' ' | sed 's/^ //;s/ $//')"

# 0) Invisible / bidi / control characters in the command tokens → refuse before classifying.
#    Every rule below decides by READING the command as text. A zero-width joiner or a
#    right-to-left override makes the text a human (and this guard) reads differ from the
#    bytes the shell runs, so a verdict can be correct about the text and wrong about the
#    execution. Fail closed: a guard that cannot trust its own input must not hand one out.
#    (Same class hardened upstream in Claude Code v2.1.216, 2026-07-20.)
#    Scope is deliberate on both axes: the command HEAD only (a heredoc body is data), and
#    OUTSIDE quoted strings — so the accented Italian that fills this repo's commit messages
#    is untouched. NBSP (U+00A0) is deliberately NOT in the set: it is a common paste
#    artifact, it looks like the space it is, and it breaks the command openly instead of
#    disguising it. Matched as raw UTF-8 bytes under LC_ALL=C because BSD grep on macOS has
#    neither -P nor named Unicode classes.
if printf '%s' "$norm" | LC_ALL=C grep -qE $'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]|\xc2[\x80-\x9f\xad]|\xe2\x80[\x8b-\x8f\xaa-\xae]|\xe2\x81[\xa0-\xa4\xa6-\xa9]|\xef\xbb\xbf'; then
  deny "This command carries invisible or direction-overriding characters (zero-width, bidi or control codes) outside any quoted string: what you would read is not what the shell would run. Refused rather than classified — retype it as plain text."
fi

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
