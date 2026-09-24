# shellcheck shell=bash
# hooks/lib-context-cache.sh — cache + background-refresh helpers for hooks/context-inject.sh.
# Split out 2026-09-24 (card 260924-085104) to keep context-inject.sh under the 300-line ratchet
# (test/test-file-size-ratchet.sh); sourced, not a standalone script — no shebang, not executable
# on its own (matches test/lib-copilot-continuity.sh). Behavior is unchanged from before the
# split, only the file it lives in.
#
# Measured 2026-09-24 (card 260924-085104, this repo's real board): `kb pending --count` ~0.6s
# (it aggregates EVERY registered board, not just this one), `kb doing` ~0.86s (0.05s user — it's
# waiting, not computing), `bus hello --arrival` ~2-2.5s — a SessionStart hook that used to take
# 4-5s wall, almost all of it waiting on these three subprocess chains, none of which this file
# is allowed to speed up from the inside (kb.sh and bus/bus.sh belong to other cards). The lever
# left here is: never make THIS run wait for them.
#
# Pattern (same idiom kanban/worktree-sweep.sh already uses for `wt count --cached`): read the
# last computed value NOW (a plain file read, no subprocess), and if it looks stale, kick a
# refresh in the BACKGROUND for the *next* run — this run never blocks on it. A cold cache (never
# run before) shows nothing for that one section rather than block; every run after the first is
# warm. Cache lives outside the repo ($RDA_HOME, same convention as kb.sh/bus.sh), so it is never
# committed and never shared between machines.
_ci_home="${RDA_HOME:-$HOME/.roberdan-os}"
_ci_cache="$_ci_home/context-inject-cache"
mkdir -p "$_ci_cache" 2>/dev/null || true

# _ci_bg <cache-file> -- <command...> — run <command...> in the background, atomically replacing
# <cache-file> with its stdout on success (never on failure/empty, so a transient error keeps the
# last good value rather than blanking it). stdin/stdout/stderr all redirected away from the
# hook's own — a background child that inherited any of them would make whatever reads this
# hook's output wait for it anyway, defeating the point. No `disown`: this hook has no job
# control (non-interactive), so `disown` just errors; the parenthesized subshell already detaches
# it, same as the existing autosweep line in context-inject.sh.
_ci_bg() {
  local f="$1"; shift; [ "${1:-}" = "--" ] && shift
  ( if "$@" > "$f.new.$$" 2>/dev/null; then mv -f "$f.new.$$" "$f"; else rm -f "$f.new.$$"; fi ) </dev/null >/dev/null 2>&1 &
}

# _ci_stale <cache-file> <ttl-minutes> <anchor-path...> — true (0) when <cache-file> should be
# refreshed: missing, older than <ttl-minutes>, or an anchor path changed since the cache was
# written. `-maxdepth 1`, deliberately: a card lives directly inside todo/doing/done, so adding
# or removing one touches that directory's OWN mtime — checking depth 1 catches that in a
# handful of stat()s. Measured on the real board (469 files under kanban/, mostly done/'s
# archive): unbounded `find kanban -newer <cache>` cost ~0.6s by itself whenever nothing
# recent enough matched and it had to walk the whole tree — more than this entire hook's
# 1s budget, for a check that exists to keep it fast. `-maxdepth 1` doesn't see a card's
# title being edited in place without also being added/removed; the short TTL is the
# backstop for that, same trade-off the task that introduced this accepted elsewhere.
_ci_stale() {
  local f="$1" ttl="$2"; shift 2
  [ -s "$f" ] || return 0
  [ -n "$(find "$f" -mmin "+$ttl" 2>/dev/null)" ] && return 0
  # One `find` for every anchor together, not one per anchor — each spawned process is real
  # money on a loaded machine (measured ~30-70ms apiece here), and `find` already accepts
  # multiple starting paths in a single call.
  local -a existing=()
  local p
  for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
  [ "${#existing[@]}" -eq 0 ] && return 1
  [ -n "$(find "${existing[@]}" -maxdepth 1 -newer "$f" -print -quit 2>/dev/null)" ] && return 0
  return 1
}
