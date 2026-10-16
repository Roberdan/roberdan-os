#!/usr/bin/env bash
# PreToolUse Bash guard — only the universal git/gh half (security, not token-saving).
# npm/test-runner rules are per-repo and do NOT live here (see repo-local hook).
# Requires `jq`.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "bash-guard: jq is required" >&2; exit 2; }

deny() { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0; }

# Single jq pass: reads stdin directly, strips heredoc bodies (preserving commands after the
# closing delimiter and leaving <<< here-strings intact), strips quoted strings (data, not
# command tokens), and normalizes whitespace. Uses \u0027 (valid JSON/jq escape), never \x27.
{
  IFS= read -r -d '' cmd || cmd=""
  IFS= read -r -d '' cmd_nostr || cmd_nostr=""
  IFS= read -r -d '' norm || norm=""
} < <(jq -j '
  (.tool_input.command // "" | if type == "string" then . else "" end) as $raw
  | ($raw | gsub("\u0000"; "")) as $clean
  | ($clean
     | split("\n")
     | reduce .[] as $line (
         {end: null, out: []};
         if .end != null then
           if ($line | sub("^\t*"; "")) == .end then .end = null else . end
         elif ($line | test("(^|[^<])<<(?![<])[ \t]*-?[ \t]*[\u0027\"]?[A-Za-z_][A-Za-z0-9_]*[\u0027\"]?")) then
           .out += [($line | sub("<<(?![<]).*$"; ""))]
           | .end = ($line | capture("(^|[^<])<<(?![<])[ \t]*-?[ \t]*[\u0027\"]?(?<w>[A-Za-z_][A-Za-z0-9_]*)[\u0027\"]?").w)
         else
           .out += [$line]
         end
       ).out
     | join("\n")) as $no_heredoc
  | ($clean | gsub("\u0027[^\u0027]*\u0027|\"[^\"]*\""; "")) as $nostr
  | ($no_heredoc
     | gsub("\u0027[^\u0027]*\u0027|\"[^\"]*\""; "")
     | gsub("[ \t\n]+"; " ")
     | sub("^ "; "")
     | sub(" $"; "")) as $norm
  | $clean, "\u0000", $nostr, "\u0000", $norm, "\u0000"
')

# 0) Invisible / bidi / control characters in the command tokens → refuse before classifying.
#    Fast-path: pure printable ASCII cannot contain control, zero-width, soft-hyphen or bidi
#    UTF-8 sequences, so grep runs only when non-printable or non-ASCII bytes are present.
if LC_ALL=C eval '[[ "$norm" =~ [^[:print:]\ ] ]]' \
   && printf '%s' "$norm" | LC_ALL=C grep -qE $'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]|\xc2[\x80-\x9f\xad]|\xe2\x80[\x8b-\x8f\xaa-\xae]|\xe2\x81[\xa0-\xa4\xa6-\xa9]|\xef\xbb\xbf'; then
  deny "This command carries invisible or direction-overriding characters (zero-width, bidi or control codes) outside any quoted string: what you would read is not what the shell would run. Refused rather than classified — retype it as plain text."
fi

# 1) Dangerous pushes: --force / -f / -fu / +refspec / --no-verify (including git -C <dir> push).
_push_re='(^|[;|&[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:];|&]+)*[[:space:]]+push([[:space:]].*)?[[:space:]](--no-verify|--force(-with-lease)?|-[A-Za-z]*f[A-Za-z]*([[:space:];|&]|$)|\+[A-Za-z0-9_./-]+([[:space:];|&:]|$))'
if [[ "$norm" =~ $_push_re ]]; then
  deny "--no-verify / --force on git push are forbidden. Fix the cause (failed hook, conflict), don't bypass it. Human gate #2 for force-push on main."
fi

# 3) Destructive reset/clean on history or working tree → confirm.
_reset_re='(^|[;|&[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:];|&]+)*[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f)'
if [[ "$norm" =~ $_reset_re ]]; then
  ask "git reset --hard / clean -f destroys uncommitted changes. Explicit confirmation required before proceeding."
fi

# 4) A `docs(...)` commit must never carry source. `git add -A` does not stage YOUR work —
#    it stages whatever is in the tree, including another process's in-flight edits.
_add_re='git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:];|&]|$)'
if [[ "$cmd_nostr" =~ $_add_re ]] \
   && printf '%s' "$cmd" | grep -qiE '\-m[[:space:]]*["'"'"']?(docs|chore\(docs)'; then
  deny "A docs commit must not be staged with 'git add -A': a blanket add stages whatever is in the tree right now — including another agent's in-flight edits (e.g. a mutation test). Stage by explicit path: git add path/to/doc.md"
fi

# 5) Whole-disk searches. Checked only when find/bfs/fd appears in the quote-stripped command.
_find_re='(^|[[:space:];|&(])(find|bfs|fd)[[:space:]]'
if [[ "$cmd_nostr" =~ $_find_re ]] \
   && printf '%s' "$cmd_nostr" | tr ';&|' '\n\n\n' \
      | grep -qE '^[[:space:](]*(sudo[[:space:]]+)?(find|bfs|fd)([[:space:]].*)?[[:space:]](/|/System/Volumes/Data/?)([[:space:]]|$)'; then
  deny "Searching the whole disk (find/bfs/fd on /) is forbidden: it runs for hours and slows every agent. Search a specific folder (e.g. ~/GitHub/<repo>, ~/Library/LaunchAgents), or use mdfind -name / gbrain."
fi

exit 0
