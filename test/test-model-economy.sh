#!/usr/bin/env bash
# test-model-economy.sh — the Uber cost lever, made binding.
#
# Uber Engineering (2026) cut agentic coding cost 52% per session while usage grew 7x, and named
# their single most impactful lever: "The primary model handles task decomposition and evaluation
# while subagents execute the work" — subagents default to a weaker, cheaper model, with manual
# overrides still allowed. They also default reasoning effort to Medium, because output tokens
# bill at a multiple of input tokens.
#
# In this canon the rule is written once (skills/model-selection-policy/skill.md, AGENTS.md agent
# table, rules/best-practices.md) and every agent frontmatter must agree with it. This test is the
# enforcement: prose nobody measures is an opinion, not a rule.
#
# Two knobs, one escape each — a WRITTEN reason in the frontmatter:
#   - model : an agent on a FRONTIER tier (today `opus`) MUST carry a non-empty `model_rationale:`.
#             An executor flipped to a frontier model without that reason is the exact violation
#             the card's acceptance names — this test goes RED on it.
#   - effort: an agent ABOVE the `medium` default (high/xhigh/max) MUST carry a non-empty
#             `effort_rationale:`.
# Plus: every agent declares `role_class:` as `decider` or `executor` (the distinction the whole
# rule turns on), and an `executor` may only reach a frontier model through the written escape.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

# One frontmatter scalar, unquoted, from the top block of an agent file.
fm() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"; }

# A model token is MID/CHEAP (no reason needed) iff it is the haiku or sonnet tier — by tier name
# or by concrete Copilot id. Anything else (opus, a future top tier, an unknown id) is FRONTIER
# and must justify itself. Erring toward "frontier" is the safe direction: it demands a reason.
is_frontier_model() {
  case "$1" in
    haiku|sonnet|claude-haiku-*|claude-sonnet-*) return 1 ;;
    "") return 1 ;;   # no pin -> inherits session model, not a frontier pin
    *) return 0 ;;
  esac
}

# Effort is ABOVE the medium default iff high/xhigh/max. low/medium/empty are within default.
is_above_medium_effort() {
  case "$1" in
    high|xhigh|max) return 0 ;;
    *) return 1 ;;
  esac
}

printf '\n=== model economy — subagent default: cheap/mid model unless a written reason (Uber lever) ===\n'
for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  name="$(basename "$a")"
  role="$(fm "$a" role_class)"
  model="$(fm "$a" model)"
  effort="$(fm "$a" effort)"
  mrat="$(fm "$a" model_rationale)"
  erat="$(fm "$a" effort_rationale)"

  case "$role" in
    decider|executor) ;;
    "") err "$name: missing role_class (must be decider or executor — the distinction the rule turns on)"; continue ;;
    *)  err "$name: role_class='$role' is not one of {decider, executor}"; continue ;;
  esac

  # THE load-bearing assertion: a frontier model needs a written reason. An executor pinned to a
  # frontier model with no model_rationale is a policy violation — exactly the card's acceptance.
  if is_frontier_model "$model"; then
    if [ -z "$mrat" ]; then
      err "$name: role_class=$role on FRONTIER model '$model' with no model_rationale — a subagent runs on the cheap/mid model unless a written reason justifies frontier"
    else
      ok "$name: frontier model '$model' justified in writing ($role)"
    fi
  else
    ok "$name: mid/cheap model '${model:-inherit}' ($role) — no reason required"
  fi

  # The effort knob, same escape.
  if is_above_medium_effort "$effort"; then
    if [ -z "$erat" ]; then
      err "$name: effort '$effort' is above the medium default with no effort_rationale"
    else
      ok "$name: effort '$effort' above medium, justified in writing"
    fi
  fi
done

printf '\n'
[ "$FAIL" -eq 0 ] && { echo "test-model-economy: PASS"; exit 0; }
echo "test-model-economy: FAIL"; exit 1
