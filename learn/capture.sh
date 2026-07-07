#!/usr/bin/env bash
# learn/capture.sh — appends ONE learning signal to the staging inbox.
# Cheap, no-lock, no-judgment. Callable from any platform (Stop hook,
# end-of-task, or by hand). Judgment (classify/dedup/promote) happens later,
# in distill.sh + curate.sh. See learn/learn-protocol.md.
#
# Usage:
#   capture.sh "<a real learning, one sentence>"      # distillable → classified later
#   capture.sh --class correction "<learning>"        # assert the taxonomy class outright
#   capture.sh --session "session <ts> cwd=<pwd>"      # ephemeral marker → distill drops it
#   echo "<learning>" | capture.sh                     # stdin also works
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
inbox="${RDA_INBOX:-$RDA_HOME/learnings/inbox}"
mkdir -p "$inbox"

# Shared taxonomy (validate --class against ADR-0001's 5 classes).
# shellcheck source=learn/classify.sh
. "$(dirname "$0")/classify.sh"

# Optional leading flags, then the signal. A control token is prepended to the stored
# record so distill can act on the author's intent without a second heuristic guess:
#   --class <c> → "{class:<c>} <text>"   (author-asserted class wins in distill)
#   --session   → "{kind:session} <text>" (distill treats it as ephemeral, never a note)
token=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session)   token="{kind:session} "; shift ;;
    --class)     rda_class_valid "${2:-}" || { echo "capture: --class must be one of: $RDA_LEARN_CLASSES" >&2; exit 2; }
                 token="{class:$2} "; shift 2 ;;
    --class=*)   c="${1#--class=}"; rda_class_valid "$c" || { echo "capture: --class must be one of: $RDA_LEARN_CLASSES" >&2; exit 2; }
                 token="{class:$c} "; shift ;;
    --)          shift; break ;;
    -*)          echo "capture: unknown flag $1" >&2; exit 2 ;;
    *)           break ;;
  esac
done

# Signal from the remaining $1 (text) or stdin.
signal="${1:-$(cat)}"
[ -n "${signal// /}" ] || { echo "capture: empty signal, skip" >&2; exit 0; }

# Privacy hard-gate (as CODE, not discretion):
# 1) never capture references to the dossier path. Match on the RDA_HOME basename
#    (".roberdan-os" by default, ".jane-os" for a forker who exported RDA_HOME) so both
#    tilde-written and absolute mentions are caught, and the gate follows the fork.
case "$signal" in
  *"/${RDA_HOME##*/}/private/"*) echo "capture: privacy block (dossier path), skip" >&2; exit 0 ;;
esac
# 2) never capture content matching the real deny-list (confidential names/entities).
#    Runtime deny-list: $RDA_HOME/private/.denylist, fallback to the repo.
denylist=""
for d in "$RDA_HOME/private/.denylist" "$(dirname "$0")/../private/.denylist"; do
  [ -f "$d" ] && { denylist="$d"; break; }
done
# NB: filter blank/comment lines from the deny-list (an empty pattern in grep -f matches everything).
if [ -n "$denylist" ] && printf '%s' "$signal" | grep -iEf <(grep -vE '^[[:space:]]*($|#)' "$denylist") >/dev/null 2>&1; then
  echo "capture: privacy block (deny-list match), skip" >&2; exit 0
fi

day="$(date +%Y-%m-%d)"
sess="${RDA_SESSION:-${CLAUDE_SESSION_ID:-local}}"
ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
file="$inbox/${day}-${sess}.md"

# 1 record/signal, append-only. Control token (if any) precedes the human text; the
# privacy gate above deliberately ran on the raw text, not the token.
printf -- '- [%s] %s%s\n' "$ts" "$token" "$signal" >> "$file"
echo "capture: +1 signal → $file" >&2
