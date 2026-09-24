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

# --- weekly system health, folded into the same digest ----------------------
# bin/system-health.sh is a CONSUMER here, never edited to know about the digest — this is the
# one place that decides WHEN it runs. Only when the latest report is stale (>7 days, or absent)
# — twice-daily launchd runs must not pay its cost (gbrain probe, telemetry.sh) every time.
# Bounded and best-effort: a slow/failing health run degrades the digest's health section, never
# the digest itself (see bin/system-health.sh for each section's own degrade-to-"non disponibile").
HEALTH_CMD="${RDA_HEALTH_CMD:-$ROOT/bin/system-health.sh}"
health_reports_dir="${RDA_HEALTH_REPORTS_DIR:-$RDA_HOME/reports}"
health_total_timeout="${RDA_HEALTH_TOTAL_TIMEOUT:-1200}"
health_section=""
latest_health="$(ls -1 "$health_reports_dir"/system-health-*.md 2>/dev/null | sort | tail -1)"
stale=1
[ -n "$latest_health" ] && [ -n "$(find "$latest_health" -mtime -7 2>/dev/null)" ] && stale=0
if [ "$stale" -eq 1 ]; then
  if command -v timeout >/dev/null 2>&1; then
    timeout "$health_total_timeout" env RDA_HOME="$RDA_HOME" bash "$HEALTH_CMD" >/dev/null 2>&1 || true
  else
    RDA_HOME="$RDA_HOME" bash "$HEALTH_CMD" >/dev/null 2>&1 || true
  fi
  latest_health="$(ls -1 "$health_reports_dir"/system-health-*.md 2>/dev/null | sort | tail -1)"
fi
if [ -n "$latest_health" ] && [ -r "$latest_health" ]; then
  # The digest must carry the REPORT, not just a path to it — a pointer nobody follows is the
  # same as no digest. The summary block is the handful of lines system-health.sh already
  # wrote between its H1 and its first "## " section; the proposal lines are the exact `kb add`
  # commands, scoped to "## Proposte" (the rest of the report never starts a line with "- ").
  summary="$(awk 'NR>1 && /^## /{exit} NR>1' "$latest_health")"
  proposals="$(sed -n '/^## Proposte/,$p' "$latest_health" | grep '^- ')"
  # `grep -c`/`grep` ALREADY print their match text (or nothing) and exit 1 on zero matches —
  # `|| echo 0` INSIDE a substitution would print a SECOND value on its own line. `|| true`
  # here is outside the substitution: it only swallows that exit status, never adds output
  # (scar: this exact bug shipped once for the count, caught only because the test grepped for
  # a bare "0" anywhere on the page, which a doubled "0\n0" still contains).
  n_prop="$(printf '%s\n' "$proposals" | grep -c '^- ')" || true
  [ -n "$proposals" ] || proposals="Nessuna proposta: nessuna soglia documentata e' stata superata."
  health_section="## Salute del sistema
referto: $latest_health
$summary
$n_prop proposte in attesa di approvazione:
$proposals"
else
  health_section="## Salute del sistema
non disponibile: nessun referto ancora prodotto (bin/system-health.sh non e' andato a buon fine)"
fi

{
  echo "# roberdan-os — pending digest ($(date '+%Y-%m-%d %H:%M'))"
  echo
  printf '%s\n' "$report"
  echo
  printf '%s\n' "$health_section"
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
