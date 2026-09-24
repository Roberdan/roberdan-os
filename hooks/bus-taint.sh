#!/usr/bin/env bash
# PostToolUse — marks THIS session tainted after a tool that could have absorbed
# untrusted external content or confidential material. Card 260924-142220, item B,
# @luca risk #2 (injection laundering: a signature proves the wrapper, not the
# author). Read by bus/bus-trust.sh's _taint_of_session at `bus send` time.
#
# STICKY and NEVER CLEARED here — a session that read the web once stays
# external-tainted for its whole life; confidential is a stronger, separately
# sticky flag (reading private/). Nothing un-taints a session: there is no
# un-read. Best-effort and NEVER blocks: this is PostToolUse, informational only.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9._-')"
[ -n "$sid" ] || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)"
tinput="$(printf '%s' "$input" | jq -c '.tool_input // {}' 2>/dev/null)"
cmd="$(printf '%s' "$tinput" | jq -r '.command // ""' 2>/dev/null)"

# Tool names are matched case-INSENSITIVELY: Claude Code sends "WebFetch"/"Bash",
# Copilot sends "bash"/"shell"/"execute" (extension.template.mjs's SHELL_TOOLS) —
# this hook is provider-neutral, same posture as hookPayload() in that file.
tool_lc="$(printf '%s' "$tool" | tr 'A-Z' 'a-z')"
new=""
case "$tool_lc" in
  webfetch|websearch) new="external" ;;
  mcp__*fetch*|mcp__*search*|mcp__*mail*|mcp__*browse*|mcp__*web*) new="external" ;;
esac
if [ -z "$new" ] && [ -n "$cmd" ]; then
  case "$cmd" in *curl*|*wget*|*'gh api'*|*http://*|*https://*) new="external" ;; esac
fi

# Confidential: any tool that touched ~/.roberdan-os/private/, whichever way it
# named the path (a file_path argument or a Bash command line mentioning it).
case "$tinput" in *"/.roberdan-os/private/"*) new="confidential" ;; esac
case "$cmd" in *".roberdan-os/private/"*) new="confidential" ;; esac

[ -n "$new" ] || exit 0

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
TAINT_HOME="${RDA_BUS_TAINT:-$RDA_HOME/bus-taint}"
mkdir -p "$TAINT_HOME" 2>/dev/null || exit 0
f="$TAINT_HOME/$sid"
cur=""
[ -s "$f" ] && cur="$(tr -d '[:space:]' < "$f" 2>/dev/null)"
_rank() { case "$1" in confidential) echo 2 ;; external) echo 1 ;; *) echo 0 ;; esac; }
if [ "$(_rank "$new")" -gt "$(_rank "$cur")" ]; then
  printf '%s' "$new" > "$f" 2>/dev/null || true
fi
exit 0
