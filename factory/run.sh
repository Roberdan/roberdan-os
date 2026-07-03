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

# Model policy (explicit Roberto directive, 2026-07): the factory must always run on sonnet,
# scaling to opus only when a task needs it — NEVER on the account's interactive default model
# (which can be anything, e.g. the pricier Fable), since `claude -p` without --model silently
# inherits it. Allowlist is deliberately hardcoded (not read from env/frontmatter as-is) so a
# typo or an unexpected value (fable, haiku, empty) can never slip through as a raw string —
# every requested value is clamped through this function before it reaches the claude command
# line. Applies to BOTH the per-task frontmatter `model:` field and the RDA_FACTORY_MODEL env
# override; neither is trusted directly.
resolve_model() {
  local requested="$1"
  case "$requested" in
    sonnet|opus) printf '%s' "$requested" ;;
    *)
      echo "[factory] WARN model '$requested' not allowed (sonnet|opus only) — clamped to sonnet" >&2
      printf 'sonnet'
      ;;
  esac
}

# If a task names its originating kanban card (`card: <id>` in frontmatter), append the
# factory result to that card so kanban/doing/ and factory queue/->done/|failed/ don't
# drift apart — this closes the gap that let two "doing" cards go silently stale.
note_card() {
  local cid="$1" line="$2" cf=""
  for c in todo doing "done"; do [ -e "$KB/$c/$cid.md" ] && cf="$KB/$c/$cid.md"; done
  [ -n "$cf" ] || return 0
  printf -- '\nfactory_result: "%s"\n' "$line" >> "$cf"
}

# Second headless pass, run only when a task exits 0 AND names a `card:` — an exit 0 only
# proves the process didn't crash, not that the card's DoD/acceptance was met (see
# factory-protocol.md). Embodies @thor (see agents/thor.md): fresh context, evidence-only,
# no rubber-stamping. Same invocation conventions as run_task (timeout wrapper, billing-safe
# env, logging). Echoes "PASS<TAB>evidence" or "FAIL<TAB>reason" on stdout — never anything
# else, so callers can split on the first tab.
verify_card() {
  local cid="$1" dir="$2" tmo="$3" vlog="$4" cf="" dod="" acc="" vprompt="" vrc=0 verdict=""
  for c in todo doing "done"; do [ -e "$KB/$c/$cid.md" ] && cf="$KB/$c/$cid.md"; done
  if [ -z "$cf" ]; then
    printf 'FAIL\tcard %s not found in kanban/ for verification\n' "$cid"
    return 0
  fi
  dod="$(field "$cf" dod)"
  acc="$(field "$cf" acceptance)"
  vprompt="You are acting as @thor (see agents/thor.md): the QA / verify-done guardian, brutal
quality validator, zero tolerance for incomplete work, fresh context, evidence-only — no
rubber-stamping. Given these acceptance criteria — Definition of Done: \"$dod\" / Acceptance:
\"$acc\" — and this repo state, verify with concrete evidence (files, commits, test output)
whether they are met. Output exactly \`VERDICT: PASS — <evidence>\` or \`VERDICT: FAIL —
<reason>\` as the last line."

  set +e
  # cd into $dir first: --add-dir only grants filesystem ACCESS, it does not change the
  # process's cwd. Without this, "current directory" in a prompt silently resolves to
  # wherever run.sh itself was launched from (the roberdan-os repo root) instead of the
  # task's declared dir — found live: a probe task wrote its output file into this repo
  # instead of its intended workdir. Subshell so the cd doesn't leak into the rest of run.sh.
  if [ ! -d "$dir" ]; then
    { echo "[factory] FATAL: dir '$dir' does not exist"; } >> "$vlog"
    vrc=2
  elif [ -n "$TIMEOUT_BIN" ]; then
    # Verify pass is QA, not authorship — always sonnet, never scaled to opus and never
    # influenced by RDA_FACTORY_MODEL/per-task model: (those govern the authoring pass only).
    ( cd "$dir" && "$TIMEOUT_BIN" "$tmo" "$CLAUDE" -p "$vprompt" --model sonnet --dangerously-skip-permissions --add-dir "$dir" ) > "$vlog" 2>&1
    vrc=$?
  else
    ( cd "$dir" && "$CLAUDE" -p "$vprompt" --model sonnet --dangerously-skip-permissions --add-dir "$dir" ) > "$vlog" 2>&1
    vrc=$?
  fi
  set -e
  { echo; echo "=== factory: thor-verify exit=$vrc at $(date) ==="; } >> "$vlog"

  verdict="$(grep -oE 'VERDICT: (PASS|FAIL) — .*' "$vlog" 2>/dev/null | tail -1 || true)"
  if [ "$vrc" -ne 0 ] || [ -z "$verdict" ]; then
    printf 'FAIL\tunparseable thor-verify output (exit=%s) — see %s\n' "$vrc" "$vlog"
    return 0
  fi
  case "$verdict" in
    "VERDICT: PASS"*) printf 'PASS\t%s\n' "${verdict#VERDICT: PASS — }" ;;
    "VERDICT: FAIL"*) printf 'FAIL\t%s\n' "${verdict#VERDICT: FAIL — }" ;;
    *) printf 'FAIL\tunparseable verdict line: %s\n' "$verdict" ;;
  esac
}

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
