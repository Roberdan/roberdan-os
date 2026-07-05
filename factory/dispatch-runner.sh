#!/usr/bin/env bash
# factory/dispatch-runner.sh — restricted external-CLI dispatcher (design §2d).
# WIRED (reachable via `kb dispatch`) but DORMANT: preflight #5 (OS-isolation floor)
# and #8 (leak-check tier active) are HARD-WIRED to refuse, so EVERY dispatch refuses
# and no external runner can ever execute without a reviewed CODE edit (phase 7).
#
# This is the Claude-native factory's untrusted-terrain sibling. It NEVER merges,
# NEVER pushes to main, NEVER touches a shared working tree, NEVER runs without a
# passing fail-closed preflight — those are structurally-impossible call paths here,
# not policy lines (design §d). What bash CANNOT enforce (network exfiltration §3c,
# filesystem escape / dossier read §3b) is exactly why #5 refuses until the OS floor
# exists. See docs/plan-2026-07-05-federated-kanban-multi-cli.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
# shellcheck source=factory/lib.sh
source "$DIR/lib.sh"           # field/frontmatter + Node 1 locks
# shellcheck source=factory/runner-sandbox.sh
source "$DIR/runner-sandbox.sh"  # credential-vacuum env (unused while dormant, but wired)

# ===========================================================================
# HARD-WIRED OS-ISOLATION FLOOR (design §f#5, @luca #9). This is a CODE CONSTANT.
# It is NOT read from any config file, env var, target repo, or ~/.roberdan-os/*.
# A target repo, a hostile .git/config, or an env var CANNOT flip it to "present".
# Turning it on is a REVIEWED code edit (phase 7), gated on @rex + @luca + Roberto,
# only after the OS floor (dedicated uid + per-uid egress-control) and its phase-7
# proof-suite exist. Do not make this configurable.
# ===========================================================================
readonly OS_FLOOR_PRESENT=0

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
RUNNER_ALLOWLIST="${RDA_RUNNER_ALLOWLIST:-$RDA_HOME/runner-allowlist}"
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"
DENYLIST="${RDA_DENYLIST_SRC:-$ROOT/private/.denylist}"
HASHFILE="${RDA_DENYLIST_HASHFILE:-$ROOT/test/denylist.sha256}"
SHIM_BINDIR="$DIR/runner-shims"
KB_HOME="${RDA_KANBAN:-$ROOT/kanban}"

# --- preflight checks (§f). Each is a function so a test can exercise it. ------

# #1 — repo in the narrow runner-allowlist. Default deny (file absent/empty).
_repo_in_allowlist() {
  local repo="$1"
  [ -n "$repo" ] || return 1
  [ -f "$RUNNER_ALLOWLIST" ] || return 1
  grep -qxF "$repo" "$RUNNER_ALLOWLIST" 2>/dev/null
}

# #2 — board is privacy-initialized: registered, card cols gitignored, leak-check
# hook present, and no card content currently tracked.
_board_privacy_ok() {
  local root="$1" hook
  [ -n "$root" ] || return 1
  [ -f "$REGISTRY" ] && grep -qxF "$root" "$REGISTRY" 2>/dev/null || return 1
  git -C "$root" check-ignore kanban/todo/probe.md >/dev/null 2>&1 || return 1
  hook="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)/hooks/pre-commit"
  { [ -f "$hook" ] && grep -q 'leak-check' "$hook" 2>/dev/null; } || return 1
  [ -z "$(git -C "$root" ls-files kanban/todo/ kanban/doing/ kanban/done/ 2>/dev/null)" ] || return 1
  return 0
}

# #3 — worktree isolation possible.
_worktree_ok() {
  local root="$1"
  [ -n "$root" ] || return 1
  git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || return 1
  git -C "$root" worktree list >/dev/null 2>&1 || return 1
  return 0
}

# #4 — credential-vacuum builder + shim bindir exist and are executable.
_cred_stripping_ok() {
  [ -f "$DIR/runner-sandbox.sh" ] || return 1
  [ -d "$SHIM_BINDIR" ] || return 1
  { [ -x "$SHIM_BINDIR/git" ] && [ -x "$SHIM_BINDIR/gh" ]; } || return 1
  return 0
}

# #5 — OS-isolation floor. HARD-WIRED: reads ONLY the code constant. No input path.
_os_floor_ok() { [ "$OS_FLOOR_PRESENT" -eq 1 ]; }

# #6 — card is not gated (runner: != human-only AND human_gates: empty).
_card_not_gated() {
  local card="$1" runner gates
  [ -n "$card" ] && [ -f "$card" ] || return 1
  runner="$(field "$card" runner)"
  gates="$(field "$card" human_gates)"
  [ "$runner" = "human-only" ] && return 1
  [ -n "$gates" ] && return 1
  return 0
}

# #8 — an ACTIVE, non-empty leak-check tier resolves (never tier-c fail-open, @rex #1).
_leakcheck_tier_active() {
  if [ -f "$DENYLIST" ] && grep -qvE '^[[:space:]]*(#|$)' "$DENYLIST" 2>/dev/null; then return 0; fi
  [ -f "$HASHFILE" ] && return 0
  return 1
}

# run_preflight <card> <cli> — evaluates ALL checks, records every failing reason in
# PREFLIGHT_REASONS. Returns 0 only if ALL hard checks pass — which NEVER happens
# while dormant (#5). #7 (lock acquirable) is a skip-not-fail and is handled in the
# activation path, never reached here.
PREFLIGHT_REASONS=()
run_preflight() {
  local card="$1" repo="" root=""
  if [ -n "$card" ] && [ -f "$card" ]; then
    repo="$(field "$card" repo)"
    # pwd -P (physical) so root matches the CANONICAL path git/kb-init store in the
    # registry — otherwise a /var -> /private/var symlink makes #2 mismatch (registry).
    root="$(cd "$(dirname "$card")/../.." 2>/dev/null && pwd -P || true)"
  fi
  PREFLIGHT_REASONS=()
  { [ -n "$card" ] && [ -f "$card" ]; } || PREFLIGHT_REASONS+=("#0 card not found: '$card'")
  _repo_in_allowlist "$repo"  || PREFLIGHT_REASONS+=("#1 repo '${repo:-?}' not in runner-allowlist (default deny)")
  _board_privacy_ok "$root"   || PREFLIGHT_REASONS+=("#2 board not privacy-initialized")
  _worktree_ok "$root"        || PREFLIGHT_REASONS+=("#3 worktree isolation not possible")
  _cred_stripping_ok          || PREFLIGHT_REASONS+=("#4 credential-vacuum/shim bindir missing or not executable")
  _os_floor_ok                || PREFLIGHT_REASONS+=("#5 OS-isolation floor ABSENT (HARD-WIRED refuse — code constant; no config/env/repo can flip it)")
  _card_not_gated "$card"     || PREFLIGHT_REASONS+=("#6 card is gated (runner: human-only or human_gates: set)")
  _leakcheck_tier_active      || PREFLIGHT_REASONS+=("#8 no ACTIVE leak-check tier (tier-c fail-open closed)")
  [ "${#PREFLIGHT_REASONS[@]}" -eq 0 ]
}

main() {
  local arg="${1:-}" cli="${2:-copilot-cli}" card="" c
  if [ -z "$arg" ]; then echo "usage: dispatch-runner.sh <card-id|card-path> [cli]" >&2; exit 2; fi
  if [ -f "$arg" ]; then card="$arg"
  else
    for c in todo doing "done"; do [ -f "$KB_HOME/$c/$arg.md" ] && card="$KB_HOME/$c/$arg.md"; done
  fi
  echo "[dispatch] external-runner dispatch requested: card='$arg' cli='$cli'" >&2

  if run_preflight "$card" "$cli"; then
    # UNREACHABLE while dormant (#5 always fails). Belt-and-braces refuse so it is
    # IMPOSSIBLE to launch a runner without a reviewed code edit (phase 7).
    echo "[dispatch] FATAL: preflight passed without an OS floor — refusing anyway (dormant)." >&2
    exit 1
  fi

  {
    echo "[dispatch] REFUSED — external dispatch is DORMANT and fail-closed. Card left untouched. Reasons:"
    for c in "${PREFLIGHT_REASONS[@]}"; do echo "  REFUSE $c"; done
  } >&2
  exit 1
}

# Run main only when EXECUTED, not when sourced by a test.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi
