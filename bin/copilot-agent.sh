#!/usr/bin/env bash
# copilot-agent.sh — launch GitHub Copilot CLI on a canon agent with its model, reasoning
# effort and context tier ACTUALLY passed as flags.
#
#   bin/copilot-agent.sh <agent> [copilot args...]
#   bin/copilot-agent.sh baccio -p "review this ADR"
#   RDA_DRY_RUN=1 bin/copilot-agent.sh baccio      # print the argv, launch nothing
#
# WHY IT EXISTS. Copilot's custom-agent frontmatter has fields for `model` but none for
# reasoning effort or context tier — an unknown key is silently ignored, so writing `effort:`
# there would look like configuration and behave like a comment. The two real ways to set
# those knobs are this launcher's flags and the persisted `subagents.agents.<name>` settings
# (`bin/models.sh apply-subagents`). Prose in a skill file is not a third way.
#
# WHAT IT REFUSES TO DO, on purpose:
#   - It adds NO permission flags. No --allow-all-tools, no --yolo, no --allow-all-paths.
#     A launcher that quietly widens permissions is a bigger change than the one it advertises;
#     if you want them, pass them yourself and own the decision.
#   - It does NOT let a caller-supplied --model/--effort/--context sit next to its own. Two
#     copies of the same flag mean the last one wins silently, so the run would use a model
#     this script just told you it was using. It stops with an explicit message instead.
#   - It does NOT fall back to another model when the pinned one is unknown or the knob is
#     unsupported. It fails loudly: a silent substitution is an unreproducible session.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib-models.sh
. "$ROOT/bin/lib-models.sh"

AGENT="${1:-}"
case "$AGENT" in
  ""|-h|--help) sed -n '2,12p' "$0"; exit 0 ;;
esac
shift
case "$AGENT" in *[!a-zA-Z0-9_-]*) echo "copilot-agent: invalid agent name '$AGENT'" >&2; exit 2 ;; esac

AGENT_FILE="$ROOT/agents/$AGENT.md"
[ -f "$AGENT_FILE" ] || { echo "copilot-agent: no canon agent '$AGENT' ($AGENT_FILE)" >&2; exit 2; }
grep -qE '^providers:.*copilot' "$AGENT_FILE" || {
  echo "copilot-agent: agent '$AGENT' does not list provider 'copilot' in its canon frontmatter" >&2; exit 2; }

# A caller flag that would collide with one we are about to set. Checked BEFORE anything runs.
prompt_value=0
for arg in "$@"; do
  if [ "$prompt_value" -eq 1 ]; then prompt_value=0; continue; fi
  case "$arg" in
    -p|--prompt) prompt_value=1 ;;
    --) break ;;
    --agent|--agent=*|--model|--model=*|--effort|--effort=*|--reasoning-effort|--reasoning-effort=*|--context|--context=*)
      echo "copilot-agent: '$arg' collides with the model/effort/context this launcher sets for '$AGENT'." >&2
      echo "  Duplicated flags resolve silently to the last one, so the session would not be running what was claimed." >&2
      echo "  Either change the agent's canon frontmatter, or call 'copilot' directly." >&2
      exit 2 ;;
  esac
done

# Resolve + validate the three knobs from the registry. Any refusal ends here, with its reason
# already on stderr from lib-models.sh. Built with a read loop, not `mapfile`: macOS still
# ships bash 3.2 and a builtin that does not exist there fails in a way nobody reads.
_args_out="$(models_agent_args "$AGENT_FILE")" || exit 2
MODEL_ARGS=()
while IFS= read -r _line; do
  [ -n "$_line" ] && MODEL_ARGS+=("$_line")
done <<EOF
$_args_out
EOF
[ "${#MODEL_ARGS[@]}" -ge 2 ] || { echo "copilot-agent: could not resolve a model for '$AGENT' — see the message above" >&2; exit 2; }

# An argument ARRAY, never a string: a flat string re-splits on whitespace and a prompt with a
# space in it becomes two arguments.
CMD=(copilot --agent "$AGENT" "${MODEL_ARGS[@]}" "$@")

if [ "${RDA_DRY_RUN:-0}" = "1" ]; then
  printf '%s\n' "${CMD[@]}"
  exit 0
fi

command -v copilot >/dev/null 2>&1 || { echo "copilot-agent: 'copilot' not on PATH" >&2; exit 127; }
exec "${CMD[@]}"
