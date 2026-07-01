#!/usr/bin/env bash
# learn/capture.sh — appends ONE learning signal to the staging inbox.
# Cheap, no-lock, no-judgment. Callable from any platform (Stop hook,
# end-of-task, or by hand). Judgment (classify/dedup/promote) happens later,
# in distill.sh + curate.sh. See learn/learn-protocol.md.
set -euo pipefail

inbox="${RDA_INBOX:-$HOME/.roberdan-os/learnings/inbox}"
mkdir -p "$inbox"

# Signal from $1 (text) or stdin.
signal="${1:-$(cat)}"
[ -n "${signal// /}" ] || { echo "capture: empty signal, skip" >&2; exit 0; }

# Privacy hard-gate (as CODE, not discretion):
# 1) never capture references to the dossier path
case "$signal" in
  *"/.roberdan-os/private/"*) echo "capture: privacy block (dossier path), skip" >&2; exit 0 ;;
esac
# 2) never capture content matching the real deny-list (confidential names/entities).
#    Runtime deny-list: ~/.roberdan-os/private/.denylist, fallback to the repo.
denylist=""
for d in "$HOME/.roberdan-os/private/.denylist" "$(dirname "$0")/../private/.denylist"; do
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

# 1 record/signal, append-only.
printf -- '- [%s] %s\n' "$ts" "$signal" >> "$file"
echo "capture: +1 signal → $file" >&2
