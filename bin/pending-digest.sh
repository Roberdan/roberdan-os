#!/usr/bin/env bash
# pending-digest.sh — the PROACTIVE half of the approval inbox. Runs on a schedule
# (launchd, see scheduling/) and, when something is waiting on Roberto, pushes a
# macOS notification + writes a durable digest file. This is what turns the system
# from "mute until you look" into "it tells you." Never blocks, never fails a boot.
#
#   bin/pending-digest.sh            # notify only if there's something pending
#   bin/pending-digest.sh --always   # write the digest + notify even if zero (for testing)
#
# Notification is best-effort (osascript on macOS; silently skipped elsewhere). The digest
# file (RDA_HOME/pending-digest.txt) is always refreshed so `kb`/a fresh session can read it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
KB="${RDA_KB:-$ROOT/kanban/kb.sh}"
digest="$RDA_HOME/pending-digest.txt"
mkdir -p "$RDA_HOME" 2>/dev/null || true

always=0
[ "${1:-}" = "--always" ] && always=1

# Full pending report + the machine-readable total (last line "PENDING: N").
report="$(RDA_KANBAN="$ROOT/kanban" bash "$KB" pending 2>/dev/null || true)"
count="$(printf '%s\n' "$report" | sed -n 's/^PENDING:[[:space:]]*//p' | tail -1)"
[ -n "$count" ] || count=0

{
  echo "# roberdan-os — pending digest ($(date '+%Y-%m-%d %H:%M'))"
  echo
  printf '%s\n' "$report"
} > "$digest" 2>/dev/null || true

if [ "$count" -gt 0 ] || [ "$always" -eq 1 ]; then
  # macOS desktop notification (best-effort). Escape double quotes for osascript.
  if command -v osascript >/dev/null 2>&1; then
    msg="$count in attesa della tua approvazione — apri e fai: kb pending"
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"roberdan-os · pending\"" >/dev/null 2>&1 || true
  fi
  echo "pending-digest: $count pending → $digest (notified)" >&2
else
  echo "pending-digest: 0 pending — nothing waiting" >&2
fi
exit 0
