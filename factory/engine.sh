#!/usr/bin/env bash
# factory/engine.sh — WHICH agent runs, HOW it is launched, and what it is refused.
# Split out of factory/lib.sh (2026-09-13) when that file crossed the 300-line ratchet.
# Sourced by factory/lib.sh; never executed on its own.
# --- deterministic guard for headless runs ------------------------------------
# Auto mode's classifier decides case by case (same `git commit --amend`, denied 2 times and
# allowed 5 on 2026-09-12). hooks/factory-guard.sh is the fixed list that always says no to
# push, history rewrite and forced deletion; it is wired ONLY into factory runs, via --settings,
# so interactive sessions are untouched. Resolved from this file, never from env: a variable
# that could point elsewhere would be a switch to turn the guard off.
# --- engine: Copilot by default, Claude only on explicit opt-in ---------------
# Roberto's directive, 2026-09-13: unattended work must never spend the Claude budget. The
# factory therefore runs on GitHub Copilot CLI, and `claude` is reached only when someone
# writes RDA_FACTORY_ENGINE=claude on purpose. Two consequences worth stating:
#   - Copilot has a NATIVE deterministic deny list (`--deny-tool`, which beats
#     `--allow-all-tools`; verified live 2026-09-13: `echo` ran, `git push` was refused).
#     That is the mechanism Claude's auto-mode classifier could not provide;
#   - the PATH shims below are engine-agnostic — both CLIs run shell commands through a
#     shell that inherits PATH — so the second layer holds whichever engine is in use.
FACTORY_ENGINE="${RDA_FACTORY_ENGINE:-copilot}"

FACTORY_GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/factory-guard.sh"
FACTORY_SETTINGS="$(printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \\"%s\\"","timeout":10}]}]}}' "$FACTORY_GUARD")"

# Copilot's equivalent of the guard hook: deny wins over --allow-all-tools, and the match is
# on the command prefix (the same shape ~/.copilot/permissions-config.json stores). Coarse on
# purpose — the exact spellings are the shims' job, and `gh`/`rm` reads must keep working.
FACTORY_DENY_TOOLS=(
  'shell(git push)' 'shell(git commit --amend)' 'shell(git rebase)'
  'shell(git filter-branch)' 'shell(git filter-repo)' 'shell(git replace)'
  'shell(git reset --hard)' 'shell(git clean)' 'shell(git branch -D)'
  'shell(git update-ref)' 'shell(git reflog)' 'shell(git stash drop)'
  'shell(git stash clear)' 'shell(git gc)' 'shell(git worktree prune)'
  'shell(rm -rf)' 'shell(rm -fr)' 'shell(rm -Rf)' 'shell(sudo)'
  'shell(gh pr create)' 'shell(gh pr merge)' 'shell(gh pr close)' 'shell(gh pr edit)'
  'shell(gh release)' 'shell(gh repo delete)' 'shell(gh repo create)' 'shell(gh secret)'
  'shell(gh workflow run)'
)

# The shim directory goes FIRST on the PATH of every headless agent (and only there). It
# holds a `git`, a `gh` and an `rm` that refuse what AGENTS.md reserves to Roberto and exec
# the real binary for everything else — see factory/shims/git for the reasoning. The guard
# above reads the command as text and can be out-spelled; the shims read argv after the shell
# has finished expanding, and are blind to a path-qualified call the guard does catch. Both,
# or neither is honest.
FACTORY_SHIMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shims"
FACTORY_SHIM_BINS="git gh rm"
# Fail closed, same contract as the guard: a shim that has been moved or stripped of its
# executable bit must stop the factory, never silently drop one layer.
factory_shims_ok() {
  local b
  for b in $FACTORY_SHIM_BINS; do
    [ -f "$FACTORY_SHIMS/$b" ] && [ -x "$FACTORY_SHIMS/$b" ] && continue
    echo "[factory] FATAL: shim missing or not executable at $FACTORY_SHIMS/$b" >&2
    return 1
  done
  return 0
}

# --- engine binary + launch ---------------------------------------------------
# launchd starts with a minimal PATH: the interactive shell's alias and its PATH are both
# unavailable, so every binary is resolved explicitly, exactly as $CLAUDE always was.
factory_which() {
  local name="$1"; shift
  local p; p="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$p" ] || [ ! -x "$p" ]; then
    for p in "$@"; do [ -x "$p" ] && break; p=""; done
  fi
  [ -n "$p" ] && [ -x "$p" ] || return 1
  printf '%s' "$p"
}
factory_engine_bin() {
  # An explicit $RDA_ENGINE_BIN (or the historical $CLAUDE) wins over the PATH search: it is
  # how kanban/thor-verify.sh hands down an already-resolved binary, and how a test points the
  # launcher at a stub without putting it on the PATH.
  local pre="${RDA_ENGINE_BIN:-${CLAUDE:-}}"
  if [ -n "$pre" ] && [ -x "$pre" ]; then printf '%s' "$pre"; return 0; fi
  case "$FACTORY_ENGINE" in
    copilot) factory_which copilot "$HOME/.local/bin/copilot" /opt/homebrew/bin/copilot "$HOME/.bun/bin/copilot" /usr/local/bin/copilot "$HOME/.npm-global/bin/copilot" ;;
    claude)  factory_which claude  "$HOME/.local/bin/claude"  /opt/homebrew/bin/claude  "$HOME/.bun/bin/claude"  /usr/local/bin/claude ;;
    *)       echo "[factory] FATAL: unknown RDA_FACTORY_ENGINE '$FACTORY_ENGINE' (copilot|claude)" >&2; return 1 ;;
  esac
}

# The canon speaks in tier aliases (sonnet/opus); each engine spells them its own way. The
# ids come from the reviewed registry (skills/model-selection-policy/models.tsv), never typed
# from memory: `sonnet` is the mid-class row, `opus` the frontier one.
engine_model() {
  local alias="$1"
  case "$FACTORY_ENGINE" in
    copilot) case "$alias" in opus) printf 'claude-opus-5' ;; *) printf 'claude-sonnet-5' ;; esac ;;
    *)       printf '%s' "$alias" ;;
  esac
}

# launch_agent <prompt> <model-alias> <dir> <timeout> <logfile>
# THE single place a headless agent is started — one launch site instead of four, so a guard,
# a shim or an engine flag cannot be wired into some of them and not the others.
# cd into $dir first: --add-dir grants filesystem ACCESS, it does not change the process's
# cwd. Without the cd, "current directory" in a prompt silently resolved to wherever run.sh
# was launched from — found live, a probe task wrote its file into this repo instead of its
# workdir. Subshell, so neither the cd nor the PATH leaks into the rest of the run.
# RDA_HEADLESS=1: a headless run (factory task, @thor verification) owns ONE task. It must not
# re-photograph the authorized queue nor be pushed into it by goal-gate (2026-09-14: a @thor run
# did both, then blocked a real card on the board to escape).
launch_agent() {
  local prompt="$1" alias="$2" dir="$3" tmo="$4" log="$5" rc=0 bin model
  if [ ! -d "$dir" ]; then
    echo "[factory] FATAL: dir '$dir' does not exist" >> "$log"
    return 2
  fi
  bin="$(factory_engine_bin)" || { echo "[factory] FATAL: $FACTORY_ENGINE binary not found" >> "$log"; return 127; }
  model="$(engine_model "$alias")"
  local -a cmd
  if [ "$FACTORY_ENGINE" = "copilot" ]; then
    # --allow-all-tools is REQUIRED for non-interactive mode; --deny-tool overrides it and is
    # the deterministic half of the fixed no. -s keeps the log to the agent's own output.
    cmd=( "$bin" -p "$prompt" --model "$model" --allow-all-tools --add-dir "$dir" --log-level none -s )
    local t; for t in "${FACTORY_DENY_TOOLS[@]}"; do cmd+=( --deny-tool "$t" ); done
  else
    # Auto mode + --permission-prompts none: routine work is still approved, but what the
    # classifier would ask about is DENIED instead of allowed, and a headless run that cannot
    # answer a prompt refuses instead of hanging.
    cmd=( "$bin" -p "$prompt" --model "$model" --permission-mode auto --permission-prompts none --settings "$FACTORY_SETTINGS" --add-dir "$dir" )
  fi
  set +e
  if [ -n "${TIMEOUT_BIN:-}" ]; then
    ( cd "$dir" && RDA_HEADLESS=1 PATH="$FACTORY_SHIMS:$PATH" "$TIMEOUT_BIN" "$tmo" "${cmd[@]}" ) > "$log" 2>&1
    rc=$?
  else
    ( cd "$dir" && RDA_HEADLESS=1 PATH="$FACTORY_SHIMS:$PATH" "${cmd[@]}" ) > "$log" 2>&1
    rc=$?
  fi
  set -e
  return "$rc"
}
