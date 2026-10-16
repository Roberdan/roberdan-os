#!/usr/bin/env bash
# Sourced by bus.sh: stale-lock reclaim for _with_lock (which stays in bus.sh).
#
# 2026-10-16: a lock directory left at 14:49 with NO owner file (its process was
# killed between `mkdir` and writing `owner`) made every `bus team` die after
# 10s, so the UserPromptSubmit hook timed out on every prompt while waiters from
# other sessions piled up. A lock is now reclaimed when its owner pid is gone, or
# when it has no owner and is older than RDA_BUS_LOCK_STALE_S (default 10s).
# A live owner is never reclaimed.
#
# Why not "write owner in a tmp dir, then mv it into place": `mv` onto an
# existing directory moves INTO it (BSD and GNU alike) and rename(2) replaces an
# EMPTY one, so either would let two processes believe they hold the lock.
# mkdir stays the atomic acquire; the grace period makes the ownerless instant safe.

# Prints why the lock is stale and succeeds, or fails if it may be live.
# `ps -p`, not `kill -0`: kill -0 fails with EPERM on another user's live pid.
# An unreadable owner counts as no owner, so only the age rule can reclaim it.
# Honest limit: a recycled pid reads as alive, which errs on the safe side.
_lock_stale_reason() {
  local lock="$1" grace="${RDA_BUS_LOCK_STALE_S:-10}" pid pid2 mtime mtime2 age
  [[ "$grace" =~ ^[0-9]+$ ]] || grace=10
  # `read`, not an assignment of the whole line: check 45 reads the traced
  # `pid='4242 at ...'` as a command named `at`.
  { read -r _ pid _ < "$lock/owner"; } 2>/dev/null || pid=""
  case "$pid" in
    ''|*[!0-9]*) ;;
    *) ps -p "$pid" >/dev/null 2>&1 && return 1
       # Re-read after ps confirms pid is dead: if pid released the lock before
       # exiting, owner is now gone or holds the next winner's pid.
       { read -r _ pid2 _ < "$lock/owner"; } 2>/dev/null || pid2=""
       [ "$pid2" = "$pid" ] || return 1
       printf 'its owner pid %s is gone' "$pid"; return 0;;
  esac
  mtime="$(date -r "$lock" +%s 2>/dev/null)" || return 1
  age=$(( $(date +%s) - mtime ))
  [ "$age" -ge "$grace" ] || return 1
  { read -r _ pid2 _ < "$lock/owner"; } 2>/dev/null && [ -n "$pid2" ] && return 1
  mtime2="$(date -r "$lock" +%s 2>/dev/null)" || return 1
  [ "$mtime2" = "$mtime" ] || return 1
  printf 'it has no owner and is %ss old' "$age"
}

# Several waiters judge the same stale lock at once (the 2026-10-16 pile-up).
# Without the guard, a waiter acting on an old judgment would rename away the
# LIVE lock another waiter has just taken. Inside it the lock is judged again,
# renamed to a unique tombstone (atomic) and dismantled by name.
_reclaim_stale_lock() {
  local lock="$1" guard="$1.reclaim" why prev tomb rc=1
  if ! mkdir "$guard" 2>/dev/null; then
    # The guard is empty, so a reclaimer killed inside it is healed by rmdir.
    _lock_stale_reason "$guard" >/dev/null && rmdir "$guard" 2>/dev/null
    return 1
  fi
  if why="$(_lock_stale_reason "$lock")"; then
    prev="$(cat "$lock/owner" 2>/dev/null || echo 'no owner file')"
    tomb="$lock.stale.$$.$RANDOM"
    if mv "$lock" "$tomb" 2>/dev/null; then
      printf 'bus: reclaimed the stale lock %s: %s (held since %s, by: %s)\n' \
        "$lock" "$why" "$(_lock_age "$tomb")" "$prev" >&2
      _release_lock "$tomb"
      rc=0
    fi
  fi
  rmdir "$guard" 2>/dev/null || true
  return "$rc"
}
