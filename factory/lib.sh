#!/usr/bin/env bash
# factory/lib.sh — shared factory primitives, sourced by BOTH factory/run.sh and
# factory/dispatch-runner.sh (design §2d, @rex #3). Extracting verify_card /
# note_card / resolve_model out of run.sh is behavior-preserving (covered by the
# existing factory tests) but a REAL edit to run.sh — the design states it as one.
#
# This file is SOURCED, never executed: it sets no shell options (the sourcing
# script owns `set -euo pipefail`). The Claude-native helpers below reference
# globals the sourcing script defines before it CALLS them:
#   CLAUDE, TIMEOUT_BIN  (verify_card)   and   KB  (verify_card / note_card).
# The Node 1 lock primitives are fully self-contained.

# --- kanban frontmatter helpers (used by verify_card/note_card + run.sh) ------
frontmatter() { sed -n '/^---$/,/^---$/p' "$1"; }
# shellcheck disable=SC2015
field() { frontmatter "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '"' || true; }

# --- model policy -------------------------------------------------------------
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

# --- card result annotation ---------------------------------------------------
# If a task names its originating kanban card (`card: <id>` in frontmatter), append the
# factory result to that card so kanban/doing/ and factory queue/->done/|failed/ don't
# drift apart — this closes the gap that let two "doing" cards go silently stale.
note_card() {
  local cid="$1" line="$2" cf=""
  for c in todo doing "done"; do [ -e "$KB/$c/$cid.md" ] && cf="$KB/$c/$cid.md"; done
  [ -n "$cf" ] || return 0
  printf -- '\nfactory_result: "%s"\n' "$line" >> "$cf"
}

# --- @thor headless verify pass ----------------------------------------------
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

# --- Node 1: atomic claim + repo locks (mkdir; bash 3.2 macOS, no flock) -------
# `mkdir dir` is atomic and fails iff `dir` already exists (POSIX) — a true
# test-and-set. `mv -n` is NOT a reliable primitive (it does not signal via exit
# code whether it moved or skipped), so it is rejected. Locks live OUTSIDE every
# repo, like factory state. Keys are <repo>+<id>, NEVER bare <id> — ids are
# per-repo unique only, so two federated repos can collide on a bare id (@rex #2).
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
LOCKS="${RDA_LOCKS:-$RDA_HOME/locks}"
RDA_LOCK_TIMEOUT="${RDA_LOCK_TIMEOUT:-1800}"   # seconds; the stale sweep uses 2x

# sanitize a repo/id token so it is safe as a single path component
_lock_slug() { printf '%s' "$1" | tr '/ :@.' '_____'; }
_lock_epoch() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

_lock_stamp() {  # write pid + heartbeat into an acquired lock dir
  local d="$1"
  printf '%s\n' "$$" > "$d/pid"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$d/heartbeat"
}

# claim_card <repo> <id> — atomic claim on <repo>+<id>. 0=won (stamped), 1=lost.
claim_card() {
  local repo="$1" id="$2" d
  mkdir -p "$LOCKS" 2>/dev/null || true
  d="$LOCKS/card-$(_lock_slug "$repo")-$(_lock_slug "$id").lock"
  if mkdir "$d" 2>/dev/null; then _lock_stamp "$d"; return 0; fi
  return 1
}
release_claim() {
  local repo="$1" id="$2"
  rm -rf "$LOCKS/card-$(_lock_slug "$repo")-$(_lock_slug "$id").lock" 2>/dev/null || true
}

# acquire_repo_lock <repo> — one-runner-per-repo (the vault's documented
# .git/index.lock collision, prevented structurally for N runners). 0=won, 1=busy.
acquire_repo_lock() {
  local repo="$1" d
  mkdir -p "$LOCKS" 2>/dev/null || true
  d="$LOCKS/repo-$(_lock_slug "$repo").lock"
  if mkdir "$d" 2>/dev/null; then _lock_stamp "$d"; return 0; fi
  return 1
}
release_repo_lock() {
  local repo="$1"
  rm -rf "$LOCKS/repo-$(_lock_slug "$repo").lock" 2>/dev/null || true
}

# sweep_stale_locks — reclaim a lock ONLY when its pid is dead AND its heartbeat
# file is older than 2x the timeout. Conservative on purpose: too-eager reclaim
# re-introduces the claim race, too-timid wedges a repo after a crash (§Node 1).
sweep_stale_locks() {
  local d pid now age hbepoch twotimeout
  [ -d "$LOCKS" ] || return 0
  now="$(date +%s)"; twotimeout=$(( RDA_LOCK_TIMEOUT * 2 ))
  for d in "$LOCKS"/*.lock; do
    [ -d "$d" ] || continue
    pid="$(cat "$d/pid" 2>/dev/null || echo '')"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then continue; fi  # still alive
    [ -f "$d/heartbeat" ] || continue
    hbepoch="$(_lock_epoch "$d/heartbeat")"
    age=$(( now - hbepoch ))
    if [ "$age" -gt "$twotimeout" ]; then rm -rf "$d" 2>/dev/null || true; fi
  done
}
