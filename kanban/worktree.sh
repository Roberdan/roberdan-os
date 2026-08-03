#!/usr/bin/env bash
# kanban/worktree.sh — one git worktree per card, and nothing left behind when the card closes.
#
# WHY a worktree per card and not a branch in the shared checkout: rules/best-practices.md
# § Parallel work records the scar — two sessions committing to the same working checkout
# re-edited each other's files and swept a live mutation into a `docs(...)` commit. A card is
# exactly the unit that can run in parallel with another card, so the card is the right unit
# of isolation. It also makes token spend ATTRIBUTABLE: a session's transcript records its cwd,
# so "what did this card cost" stops being a guess over a time window (see kanban/dash.sh).
#
# Used by `kb start` (create), `kb finish` (verify clean + remove) and `kb dash` (report).
# Every subcommand degrades instead of crashing: a card whose repo is not a git repo, or a repo
# that no longer exists, yields "no worktree" — never a failed `kb start`.
set -uo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"
# Where per-card worktrees live. One directory per repo, one worktree per card id, so
# `ls ~/GitHub/worktrees/<repo>` answers "what is in flight here" without git.
WT_HOME="${RDA_WORKTREES:-$HOME/GitHub/worktrees}"

# repo NAME -> repo PATH: a registry entry with that basename, else ~/GitHub/<name>.
# (Same resolution as kb.sh's _repo_path — kept here so this script stands alone.)
_repo_path() {
  local name="$1" r
  [ -n "$name" ] || return 1   # vedi kb.sh: senza questa riga un nome vuoto -> $HOME/GitHub/
  if [ -f "$REGISTRY" ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      case "$r" in \#*) continue ;; esac   # una riga di commento non e' un repo
      [ "$(basename "$r")" = "$name" ] && { printf '%s' "$r"; return 0; }
    done < "$REGISTRY"
  fi
  [ -d "$HOME/GitHub/$name" ] && printf '%s' "$HOME/GitHub/$name"
}

_wt_path() { printf '%s/%s/%s' "$WT_HOME" "$1" "$2"; }

# The branch a card's worktree forks FROM. Prefer the repo's default branch over whatever
# happens to be checked out: a card started while the main checkout sits on some feature
# branch must not silently inherit that branch's work as its own baseline.
_base_ref() {
  local repo="$1" head
  head="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$head" ] && { printf '%s' "${head#refs/remotes/}"; return 0; }
  local b
  for b in main master; do
    git -C "$repo" show-ref --verify --quiet "refs/heads/$b" && { printf '%s' "$b"; return 0; }
  done
  git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# wt create <repo-name> <card-id> — idempotent. Prints the worktree path on stdout (and
# nothing else, so callers can capture it); diagnostics go to stderr. Exit 1 = no worktree
# (not a git repo / repo not found / git refused) — the caller carries on without one.
_create() {
  local name="${1:?repo name}" id="${2:?card id}" repo wt branch base
  repo="$(_repo_path "$name")"
  [ -n "$repo" ] && git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "worktree: '$name' is not a git repo — card runs without a worktree" >&2; return 1; }
  wt="$(_wt_path "$name" "$id")"
  branch="card/$id"
  if [ -d "$wt" ]; then printf '%s' "$wt"; return 0; fi
  mkdir -p "$(dirname "$wt")"
  base="$(_base_ref "$repo")"
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add "$wt" "$branch" >&2 2>/dev/null || \
      { echo "worktree: git refused to attach $branch — card runs without a worktree" >&2; return 1; }
  else
    git -C "$repo" worktree add "$wt" -b "$branch" "$base" >/dev/null 2>&1 || \
      { echo "worktree: git refused to create $branch from $base — card runs without a worktree" >&2; return 1; }
  fi
  printf '%s' "$wt"
}

# wt status <path> [<repo-name>] — one line describing how far the worktree is from clean.
# Prints "clean" (nothing uncommitted, nothing unmerged) or a human list of what is dirty.
# A missing directory prints "gone" — a card whose worktree was removed by hand is not an error.
_status() {
  local wt="${1:?worktree path}" name="${2:-}" dirty ahead base repo branch
  [ -d "$wt" ] || { echo "gone"; return 0; }
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git worktree"; return 0; }
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | grep -c . || true)"
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  # Unmerged = commits on this branch that the base branch does not contain. That is work
  # which disappears from view the moment the worktree is removed, so it counts as "not clean".
  ahead=0
  repo="$([ -n "$name" ] && _repo_path "$name" || true)"
  if [ -n "$repo" ]; then
    base="$(_base_ref "$repo")"
    ahead="$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)"
  fi
  local out=""
  [ "${dirty:-0}" -gt 0 ] && out="$dirty file non committati"
  [ "${ahead:-0}" -gt 0 ] && out="${out:+$out, }$ahead commit non ancora in ${base:-base}"
  if [ -z "$out" ]; then echo "clean"; else printf '%s (branch %s)\n' "$out" "$branch"; fi
}

# wt remove <path> [<repo-name>] — remove ONLY when clean; refuse loudly otherwise.
# "Clean" is the same definition _status uses, so what `kb dash` shows is what this enforces.
_remove() {
  local wt="${1:?worktree path}" name="${2:-}" st repo branch
  [ -d "$wt" ] || { echo "worktree already gone: $wt"; return 0; }
  st="$(_status "$wt" "$name")"
  if [ "$st" != "clean" ]; then
    echo "REFUSED: il worktree della card non e pulito — $st" >&2
    echo "  $wt" >&2
    echo "  Committa e mergia (o scarta) prima di chiudere la card, oppure chiudi con" >&2
    echo "  --keep-worktree \"<perche>\" per lasciarlo in piedi con la ragione scritta sulla card." >&2
    return 1
  fi
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  repo="$([ -n "$name" ] && _repo_path "$name" || true)"
  git -C "${repo:-$wt}" worktree remove "$wt" 2>/dev/null || rm -rf "$wt"
  # The branch is deleted only when git agrees it is fully merged (-d, never -D): an unmerged
  # branch is the last copy of that work, and this command must never be how it is lost.
  if [ -n "$repo" ] && [ -n "$branch" ] && [ "$branch" != "?" ]; then
    git -C "$repo" branch -d "$branch" >/dev/null 2>&1 || true
  fi
  echo "worktree rimosso: $wt"
}

case "${1:-}" in
  path)   shift; _wt_path "${1:?repo name}" "${2:?card id}" ;;
  create) shift; _create "$@" ;;
  status) shift; _status "$@" ;;
  remove) shift; _remove "$@" ;;
  home)   printf '%s' "$WT_HOME" ;;
  *) echo "usage: worktree.sh {path|create|status|remove} <args> | home" >&2; exit 2 ;;
esac
