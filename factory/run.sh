#!/usr/bin/env bash
# factory/run.sh — autonomous agent factory: dispatch queued tasks to headless
# Claude Code agents, sequentially, with logs + resume. See factory/factory-protocol.md.
# Resumable: state = filesystem (queue/ -> done/). Launched by launchd or by hand.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
FACTORY="${RDA_FACTORY:-$RDA_HOME/factory}"
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

# frontmatter(), field(), resolve_model(), note_card(), verify_card() and the Node 1
# lock primitives are provided by factory/lib.sh — sourced here and by
# dispatch-runner.sh (design §2d, @rex #3). BASH_SOURCE-relative so it resolves
# under launchd's foreign cwd. $CLAUDE/$TIMEOUT_BIN/$KB are already set above; the
# helpers late-bind them at call time regardless.
# shellcheck source=factory/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
prompt_of() { awk 'BEGIN{f=0} /^---$/{f++; next} f>=2{print}' "$1"; }  # body after 2nd ---

run_task() {
  local f="$1" name ts dir tmo log body attempts_file attempts model_req model
  name="$(basename "$f" .md)"
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="$(field "$f" dir)"; dir="${dir/#\~/$HOME}"; dir="${dir:-$DEFAULT_DIR}"
  tmo="$(field "$f" timeout)"; tmo="${tmo:-$DEFAULT_TIMEOUT}"
  log="$LOG/${ts}-${name}.log"
  # Per-task frontmatter `model:` wins; else the global RDA_FACTORY_MODEL override; else
  # sonnet. Either source is clamped through resolve_model()'s allowlist (sonnet|opus only).
  model_req="$(field "$f" model)"; model_req="${model_req:-${RDA_FACTORY_MODEL:-sonnet}}"
  model="$(resolve_model "$model_req")"
  body="$(prompt_of "$f")"; [ -n "$body" ] || body="$(cat "$f")"
  attempts_file="$STATE/${name}.attempts"
  attempts="$(cat "$attempts_file" 2>/dev/null || echo 0)"
  # Inject the context-primer so every agent loads the right context before acting.
  local primer=""; [ -f "$PRIMER" ] && primer="$(cat "$PRIMER")"$'\n\n=== YOUR TASK ===\n'
  local full="${primer}${body}"

  echo "[factory] START $name (dir=$dir timeout=${tmo}s attempt=$((attempts+1)) model=$model) -> $log"
  set +e
  # cd into $dir first — see the comment in verify_card() for why: --add-dir alone leaves
  # the process's actual cwd at wherever run.sh was launched from, not the task's dir.
  local rc
  if [ ! -d "$dir" ]; then
    { echo "[factory] FATAL: dir '$dir' does not exist"; } >> "$log"
    rc=2
  elif [ -n "$TIMEOUT_BIN" ]; then
    ( cd "$dir" && "$TIMEOUT_BIN" "$tmo" "$CLAUDE" -p "$full" --model "$model" --dangerously-skip-permissions --add-dir "$dir" ) > "$log" 2>&1
    rc=$?
  else
    ( cd "$dir" && "$CLAUDE" -p "$full" --model "$model" --dangerously-skip-permissions --add-dir "$dir" ) > "$log" 2>&1
    rc=$?
  fi
  set -e
  { echo; echo "=== factory: exit=$rc at $(date) ==="; } >> "$log"

  local card; card="$(field "$f" card)"
  local verify_status="" verify_detail=""

  # Task exited 0 AND declares a card: run @thor verification before trusting it.
  # A verification FAIL routes through the SAME retry/failed path as a task exit≠0
  # (below) — an exit 0 that didn't meet the DoD is not a success.
  if [ "$rc" -eq 0 ] && [ -n "$card" ]; then
    local vresult; vresult="$(verify_card "$card" "$dir" "$tmo" "$LOG/${ts}-${name}-thor-verify.log")"
    verify_status="${vresult%%$'\t'*}"
    verify_detail="${vresult#*$'\t'}"
    if [ "$verify_status" = "FAIL" ]; then
      echo "[factory] THOR-VERIFY FAILED $name: $verify_detail"
      rc=1
    fi
  fi

  if [ "$rc" -eq 0 ]; then
    rm -f "$attempts_file"
    mv "$f" "$DONE/${ts}-${name}.md"
    printf -- '\n---\nfactory_exit: %s\nfactory_log: %s\nfactory_completed: %s\n' "$rc" "$log" "$(date)" >> "$DONE/${ts}-${name}.md"
    echo "[factory] DONE  $name (exit $rc)"
    if [ -n "$card" ]; then
      note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — succeeded, still needs @thor to reach kanban done/"
      [ "$verify_status" = "PASS" ] && note_card "$card" "headless thor pass PASSED ($verify_detail) — still needs human kb finish"
    fi
    return 0
  fi

  attempts=$((attempts+1))
  if [ "$attempts" -lt "$MAX_ATTEMPTS" ]; then
    echo "$attempts" > "$attempts_file"
    # $f is always already inside $Q (run_task is only ever called on queue/*.md) — a retry
    # requeues by simply leaving it there. `mv` a file onto itself fails under `set -e` (GNU
    # coreutils: "are the same file", exit 1), which used to silently kill the whole factory
    # run on a task's very first failure. Only mv if the paths actually differ.
    [ "$f" -ef "$Q/${name}.md" ] || mv "$f" "$Q/${name}.md"
    echo "[factory] RETRY $name (attempt $attempts/$MAX_ATTEMPTS, exit $rc) -> requeued, see $log"
    if [ "$verify_status" = "FAIL" ]; then
      note_card "$card" "exit=0 log=$log at=$(date +%Y-%m-%d\ %H:%M) — thor-verify FAILED: $verify_detail — retrying (attempt $attempts/$MAX_ATTEMPTS)"
    else
      [ -n "$card" ] && note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — retrying (attempt $attempts/$MAX_ATTEMPTS)"
    fi
  else
    rm -f "$attempts_file"
    mv "$f" "$FAILED/${ts}-${name}.md"
    printf -- '\n---\nfactory_exit: %s\nfactory_log: %s\nfactory_failed_at: %s\nattempts: %s\nescalate: true\n' \
      "$rc" "$log" "$(date)" "$attempts" >> "$FAILED/${ts}-${name}.md"
    echo "[factory] FAILED $name (exit $rc, attempts=$attempts) -> $FAILED/${ts}-${name}.md — escalate"
    if [ "$verify_status" = "FAIL" ]; then
      note_card "$card" "exit=0 log=$log at=$(date +%Y-%m-%d\ %H:%M) — thor-verify FAILED after $attempts attempts: $verify_detail — escalate:true, see $FAILED/${ts}-${name}.md"
    else
      [ -n "$card" ] && note_card "$card" "exit=$rc log=$log at=$(date +%Y-%m-%d\ %H:%M) — FAILED after $attempts attempts, escalate:true, see $FAILED/${ts}-${name}.md"
    fi
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
