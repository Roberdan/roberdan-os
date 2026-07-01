#!/usr/bin/env bash
# factory/run.sh — autonomous agent factory: dispatch queued tasks to headless
# Claude Code agents, sequentially, with logs + resume. See factory/factory-protocol.md.
# Resumable: state = filesystem (queue/ -> done/). Launched by launchd or by hand.
set -euo pipefail

FACTORY="${RDA_FACTORY:-$HOME/.roberdan-os/factory}"
Q="$FACTORY/queue"; DONE="$FACTORY/done"; LOG="$FACTORY/logs"; FAILED="$FACTORY/failed"; STATE="$FACTORY/state"
mkdir -p "$Q" "$DONE" "$LOG" "$FAILED" "$STATE"
# Default scoped to roberdan-os, not all of ~/GitHub: --dangerously-skip-permissions grants
# write access to whatever --add-dir points at, so an unscoped task must not get the whole tree.
DEFAULT_DIR="${RDA_FACTORY_WORKDIR:-$HOME/GitHub/roberdan-os}"
MAX="${RDA_FACTORY_MAX:-8}"
DEFAULT_TIMEOUT="${RDA_FACTORY_TIMEOUT:-1800}"
PRIMER="${RDA_PRIMER:-$HOME/GitHub/roberdan-os/handoff/context-primer.md}"
HANDOFF="${RDA_HANDOFF:-$HOME/GitHub/roberdan-os/handoff/latest.md}"
KB="${RDA_KANBAN:-$HOME/GitHub/roberdan-os/kanban}"
MAX_ATTEMPTS=2

# BILLING SAFETY (verified w/ Claude Code docs): in `-p` headless mode, an
# ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN is ALWAYS used → per-token API billing.
# Unset both so auth falls through to the Max subscription OAuth (no API charges).
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN 2>/dev/null || true

# locate the real claude binary (launchd has a minimal PATH; the interactive alias is unavailable)
CLAUDE="$(command -v claude 2>/dev/null || true)"
if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
  for p in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude "$HOME/.bun/bin/claude" /usr/local/bin/claude; do
    [ -x "$p" ] && { CLAUDE="$p"; break; }
  done
fi
[ -n "$CLAUDE" ] && [ -x "$CLAUDE" ] || { echo "[factory] FATAL: claude binary not found" >&2; exit 127; }

# `timeout` is GNU coreutils, not built into macOS /usr/bin — under launchd's minimal PATH
# it is just as missing as `claude` was. Resolve it the same way, with a portable fallback.
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then
  for p in /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout /usr/local/bin/gtimeout; do
    [ -x "$p" ] && { TIMEOUT_BIN="$p"; break; }
  done
fi
if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then
  echo "[factory] WARN: no timeout binary found (coreutils not installed?) — running without a timeout guard" >&2
  TIMEOUT_BIN=""
fi

frontmatter() { sed -n '/^---$/,/^---$/p' "$1"; }
field() { frontmatter "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '"' || true; }
prompt_of() { awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$1"; }  # body after 2nd ---

# If a task names its originating kanban card (`card: <id>` in frontmatter), append the
# factory result to that card so kanban/doing/ and factory queue/->done/|failed/ don't
# drift apart — this closes the gap that let two "doing" cards go silently stale.
note_card() {
  local cid="$1" line="$2" cf=""
  for c in todo doing done; do [ -e "$KB/$c/$cid.md" ] && cf="$KB/$c/$cid.md"; done
  [ -n "$cf" ] || return 0
  printf -- '\nfactory_result: "%s"\n' "$line" >> "$cf"
}

run_task() {
  local f="$1" name ts dir tmo log body attempts_file attempts
  name="$(basename "$f" .md)"
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="$(field "$f" dir)"; dir="${dir/#\~/$HOME}"; dir="${dir:-$DEFAULT_DIR}"
  tmo="$(field "$f" timeout)"; tmo="${tmo:-$DEFAULT_TIMEOUT}"
  log="$LOG/${ts}-${name}.log"
  body="$(prompt_of "$f")"; [ -n "$body" ] || body="$(cat "$f")"
  attempts_file="$STATE/${name}.attempts"
  attempts="$(cat "$attempts_file" 2>/dev/null || echo 0)"
  # Inject the context-primer so every agent loads the right context before acting.
  local primer=""; [ -f "$PRIMER" ] && primer="$(cat "$PRIMER")"$'\n\n=== YOUR TASK ===\n'
  local full="${primer}${body}"

  echo "[factory] START $name (dir=$dir timeout=${tmo}s attempt=$((attempts+1))) -> $log"
  set +e
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$tmo" "$CLAUDE" -p "$full" --dangerously-skip-permissions --add-dir "$dir" > "$log" 2>&1
  else
    "$CLAUDE" -p "$full" --dangerously-skip-permissions --add-dir "$dir" > "$log" 2>&1
  fi
  local rc=$?
  set -e
  { echo; echo "=== factory: exit=$rc at $(date) ==="; } >> "$log"

  local card; card="$(field "$f" card)"

  if [ "$rc" -eq 0 ]; then
    rm -f "$attempts_file"
    mv "$f" "$DONE/${ts}-${name}.md"
    printf -- '\n---\nfactory_exit: %s\nfactory_log: %s\nfactory_completed: %s\n' "$rc" "$log" "$(date)" >> "$DONE/${ts}-${name}.md"
    echo "[factory] DONE  $name (exit $rc)"
    [ -n "$card" ] && note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — succeeded, still needs @thor to reach kanban done/"
    return 0
  fi

  attempts=$((attempts+1))
  if [ "$attempts" -lt "$MAX_ATTEMPTS" ]; then
    echo "$attempts" > "$attempts_file"
    mv "$f" "$Q/${name}.md"
    echo "[factory] RETRY $name (attempt $attempts/$MAX_ATTEMPTS, exit $rc) -> requeued, see $log"
    [ -n "$card" ] && note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — retrying (attempt $attempts/$MAX_ATTEMPTS)"
  else
    rm -f "$attempts_file"
    mv "$f" "$FAILED/${ts}-${name}.md"
    printf -- '\n---\nfactory_exit: %s\nfactory_log: %s\nfactory_failed_at: %s\nattempts: %s\nescalate: true\n' \
      "$rc" "$log" "$(date)" "$attempts" >> "$FAILED/${ts}-${name}.md"
    echo "[factory] FAILED $name (exit $rc, attempts=$attempts) -> $FAILED/${ts}-${name}.md — escalate"
    [ -n "$card" ] && note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — FAILED after $attempts attempts, escalate:true, see $FAILED/${ts}-${name}.md"
  fi
  FAILURES=$((FAILURES+1))
}

n=0
FAILURES=0
shopt -s nullglob
for f in "$Q"/*.md; do
  [ "$n" -ge "$MAX" ] && { echo "[factory] MAX=$MAX reached, stopping"; break; }
  run_task "$f"
  n=$((n+1))
done
[ "$n" -eq 0 ] && echo "[factory] queue empty — nothing to do"
echo "[factory] processed $n task(s), $FAILURES failure(s) at $(date)"

if [ "$FAILURES" -gt 0 ] && [ -f "$HANDOFF" ]; then
  {
    echo
    echo "## Factory run $(date +%Y-%m-%d\ %H:%M) — $FAILURES failure(s)"
    echo "See \`$LOG\` and \`$FAILED\` for details. A task lands in \`failed/\` only after"
    echo "$MAX_ATTEMPTS failed attempts (escalate: true) — check before assuming a card is done."
  } >> "$HANDOFF"
fi
