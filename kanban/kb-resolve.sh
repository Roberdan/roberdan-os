#!/usr/bin/env bash
# Board selection for kb.sh. The caller provides ROOT, REGISTRY and _in_registry.
# shellcheck disable=SC2034  # selection state is consumed by the sourcing kb.sh

_kb_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    -u GIT_CEILING_DIRECTORIES -u GIT_DISCOVERY_ACROSS_FILESYSTEM \
    -u GIT_CONFIG_COUNT -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_NOSYSTEM git "$@"
}

_kb_filesystem_git_context() {
  local dir parent
  dir="$(pwd -P)"
  while :; do
    if [ -e "$dir/.git" ]; then
      printf '%s\n' "$dir"; return 0
    fi
    if [ "${dir##*/}" = ".git" ] && [ -f "$dir/HEAD" ]; then
      dirname "$dir"; return 0
    fi
    if [ -f "$dir/HEAD" ] && [ -f "$dir/config" ] \
       && [ -d "$dir/objects" ] && [ -d "$dir/refs" ]; then
      printf '%s\n' "$dir"; return 0
    fi
    parent="$(dirname "$dir")"
    [ "$parent" != "$dir" ] || return 1
    dir="$parent"
  done
}

_kb_home_common="$(_kb_git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ "${_kb_home_common##*/}" = ".git" ]; then
  HOME_REPO_ROOT="$(cd "${_kb_home_common%/.git}" && pwd -P)"
else
  HOME_REPO_ROOT="$ROOT"
fi
unset _kb_home_common

KB_MATCHED=0
KB=""
KB_RESOLUTION=""
KB_UNREGISTERED_ROOT=""
KB_CONTEXT_ROOT=""

_resolve_kb() {
  local root common gitdir bare primary="" physical="" natural="" natural_resolution="" unregistered_root=""
  root="$(_kb_git rev-parse --show-toplevel 2>/dev/null || true)"
  common="$(_kb_git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  gitdir="$(_kb_git rev-parse --absolute-git-dir 2>/dev/null || true)"
  bare="$(_kb_git rev-parse --is-bare-repository 2>/dev/null || true)"
  [ -z "$common" ] || common="$(cd "$common" && pwd -P)"
  [ -z "$gitdir" ] || gitdir="$(cd "$gitdir" && pwd -P)"
  if [ "$bare" = "true" ]; then
    primary="$gitdir"
  elif [ "${common##*/}" = ".git" ]; then
    primary="${common%/.git}"
  fi
  physical="$(_kb_filesystem_git_context 2>/dev/null || true)"
  KB_CONTEXT_ROOT="${primary:-${root:-$physical}}"
  if [ -n "$root" ] && { [ "$root" = "$HOME_REPO_ROOT" ] || _in_registry "$root"; }; then
    natural="$root/kanban"
    natural_resolution="registered-repository"
  elif [ -n "$primary" ] && { [ "$primary" = "$HOME_REPO_ROOT" ] || _in_registry "$primary"; }; then
    natural="$primary/kanban"
    natural_resolution="linked-worktree-primary"
  elif [ -n "$physical" ] && { [ "$physical" = "$HOME_REPO_ROOT" ] || _in_registry "$physical"; }; then
    natural="$physical/kanban"
    natural_resolution="registered-repository"
  elif [ -n "$root" ] || [ -n "$primary" ] || [ -n "$physical" ]; then
    unregistered_root="${primary:-${root:-$physical}}"
    [ -n "$natural" ] || KB_UNREGISTERED_ROOT="$unregistered_root"
  fi
  if [ -n "${RDA_KANBAN:-}" ]; then
    KB_MATCHED=1; KB="$RDA_KANBAN"; KB_RESOLUTION="explicit-override"
    if [ -n "$natural" ] && [ "$KB" != "$natural" ]; then
      echo "kb: WARNING — RDA_KANBAN=$KB overrides this repo's own board ($natural)." >&2
      echo "kb:   Writes will NOT land in the repo's board. Unset RDA_KANBAN to use it." >&2
    fi
  elif [ -n "$natural" ]; then
    KB_MATCHED=1; KB="$natural"; KB_RESOLUTION="$natural_resolution"
  else
    KB="$HOME_REPO_ROOT/kanban"; KB_RESOLUTION="aggregate-fallback"
  fi
}

_guard_board_mutation() {
  [ -n "$KB_UNREGISTERED_ROOT" ] && [ -z "${RDA_KANBAN:-}" ] || return 0
  local command="$1" mutation=0
  shift || true
  case "$command" in
    add|start|block|finish|edit|pause|next|prossima) mutation=1 ;;
    queue|coda)
      [ "$#" -eq 1 ] && { [ "$1" = "--restanti" ] || [ "$1" = "--remaining" ]; } || mutation=1
      ;;
    resume) [ "${1:-}" = "--done" ] && mutation=1 ;;
    wt) [ "${1:-}" = "attach" ] && mutation=1 ;;
    migrate) [ "${1:-}" = "--apply" ] && mutation=1 ;;
  esac
  [ "$mutation" -eq 1 ] || return 0
  echo "REFUSED: '$KB_UNREGISTERED_ROOT' is not registered with kb." >&2
  echo "  No board was changed. Register it with: kb init \"$KB_UNREGISTERED_ROOT\"" >&2
  echo "  Or select a board explicitly for this command with RDA_KANBAN=/path/to/kanban." >&2
  return 1
}

_resolve_kb
