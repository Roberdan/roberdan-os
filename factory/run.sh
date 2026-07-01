#!/usr/bin/env bash
# factory/run.sh — autonomous agent factory: dispatch queued tasks to headless
# Claude Code agents, sequentially, with logs + resume. See factory/factory-protocol.md.
# Resumable: state = filesystem (queue/ -> done/). Launched by launchd or by hand.
set -euo pipefail

FACTORY="${RDA_FACTORY:-$HOME/.roberdan-os/factory}"
Q="$FACTORY/queue"; DONE="$FACTORY/done"; LOG="$FACTORY/logs"
mkdir -p "$Q" "$DONE" "$LOG"
DEFAULT_DIR="${RDA_FACTORY_WORKDIR:-$HOME/GitHub}"
MAX="${RDA_FACTORY_MAX:-8}"
DEFAULT_TIMEOUT="${RDA_FACTORY_TIMEOUT:-1800}"
PRIMER="${RDA_PRIMER:-$HOME/GitHub/roberdan-os/handoff/context-primer.md}"

# BILLING SAFETY (verified w/ Claude Code docs): in `-p` headless mode, an
# ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN is ALWAYS used → per-token API billing.
# Unset both so auth falls through to the Max subscription OAuth (no API charges).
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN 2>/dev/null || true

# locate claude (avoid the interactive alias; call the binary in headless mode)
CLAUDE="$(command -v claude || echo claude)"

frontmatter() { sed -n '/^---$/,/^---$/p' "$1"; }
field() { frontmatter "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '"' || true; }
prompt_of() { awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$1"; }  # body after 2nd ---

run_task() {
  local f="$1" name ts dir tmo log body
  name="$(basename "$f" .md)"
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="$(field "$f" dir)"; dir="${dir/#\~/$HOME}"; dir="${dir:-$DEFAULT_DIR}"
  tmo="$(field "$f" timeout)"; tmo="${tmo:-$DEFAULT_TIMEOUT}"
  log="$LOG/${ts}-${name}.log"
  body="$(prompt_of "$f")"; [ -n "$body" ] || body="$(cat "$f")"
  # Inject the context-primer so every agent loads the right context before acting.
  local primer=""; [ -f "$PRIMER" ] && primer="$(cat "$PRIMER")"$'\n\n=== YOUR TASK ===\n'
  local full="${primer}${body}"

  echo "[factory] START $name (dir=$dir timeout=${tmo}s) -> $log"
  set +e
  timeout "$tmo" "$CLAUDE" -p "$full" --dangerously-skip-permissions --add-dir "$dir" > "$log" 2>&1
  local rc=$?
  set -e
  { echo; echo "=== factory: exit=$rc at $(date) ==="; } >> "$log"
  mv "$f" "$DONE/${ts}-${name}.md"
  printf -- '\n---\nfactory_exit: %s\nfactory_log: %s\nfactory_completed: %s\n' "$rc" "$log" "$(date)" >> "$DONE/${ts}-${name}.md"
  echo "[factory] DONE  $name (exit $rc)"
}

n=0
shopt -s nullglob
for f in "$Q"/*.md; do
  [ "$n" -ge "$MAX" ] && { echo "[factory] MAX=$MAX reached, stopping"; break; }
  run_task "$f"
  n=$((n+1))
done
[ "$n" -eq 0 ] && echo "[factory] queue empty — nothing to do"
echo "[factory] processed $n task(s) at $(date)"
