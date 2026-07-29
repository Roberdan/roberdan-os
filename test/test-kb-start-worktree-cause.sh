#!/usr/bin/env bash
# test/test-kb-start-worktree-cause.sh — when `kb start` gets no worktree, it must say
# what actually failed, not pick one cause and assert it.
#
# The bug this pins: `kb start` called worktree.sh with `2>/dev/null || true` and then,
# on empty output, wrote a single fixed line — "repo X non e un git repo". worktree.sh
# distinguishes at least three failures on stderr (repo is not a git repo / git refused
# to attach the branch / git refused to create it from the base), and all three were
# thrown away before the message was composed. A repo that IS a git repo was therefore
# told it was not.
#
# That is worse than a bare error. An error makes you look; a FALSE error makes you look
# in the wrong place, and this one sent a real session hunting a git problem that did not
# exist. Reproduced on 2026-07-29 before the fix: with the worktree path occupied by a
# file, worktree.sh said "git refused to create card/TEST-3 from master" and kb reported
# "repo 'fakerepo' non e un git repo".
#
# The assertions below are negative as well as positive on purpose. Checking only that
# the true cause appears would still pass if kb printed BOTH the truth and the invented
# line, so each case also asserts the wrong diagnosis is absent.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

KB="$TMP/board"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done" "$TMP/wt"

# A real git repo, reachable only through the registry, so nothing under ~/GitHub is
# touched and the test cannot accidentally attach a worktree to a live checkout.
git init -q "$TMP/realrepo"
git -C "$TMP/realrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m seed
printf '%s\n' "$TMP/realrepo" > "$TMP/registry"

_card() { # _card <id> <repo-name>
  printf 'title: %s\nrepo: %s\ndod: "x"\nacceptance: "y"\nstatus: todo\ncreated: 2026-07-29\n' \
    "$1" "$2" > "$KB/todo/$1.md"
}

_start() { # _start <id> [<kb.sh path>] — prints the combined output of `kb start`
  RDA_KANBAN="$KB" RDA_KANBAN_REGISTRY="$TMP/registry" RDA_WORKTREES="$TMP/wt" \
    bash "${2:-$ROOT/kanban/kb.sh}" start "$1" --by roberto 2>&1
}

section "git refused the branch: the repo IS a git repo, so kb must not say otherwise"
_card C1 realrepo
mkdir -p "$TMP/wt/realrepo"
: > "$TMP/wt/realrepo/C1"          # path occupied by a FILE — `git worktree add` refuses
out="$(_start C1)"
case "$out" in
  *"git refused"*) ok "names git's refusal: $(printf '%s' "$out" | tail -1)" ;;
  *) err "does not name git's refusal: $out" ;;
esac
case "$out" in
  *"non e un git repo"*) err "still asserts the false cause: $out" ;;
  *) ok "does not claim the repo is not a git repo" ;;
esac
# The card on disk carries the same reason: the terminal line scrolls away, the card
# is what a later session reads.
grep -q 'git refused' "$KB/doing/C1.md" \
  && ok "the card records the real cause" \
  || err "the card records: $(grep worktree_none "$KB/doing/C1.md" 2>/dev/null)"

section "genuinely not a git repo: the honest message must survive the fix"
_card C2 nonesistente
out="$(_start C2)"
case "$out" in
  *"not a git repo"*) ok "still says it is not a git repo" ;;
  *) err "lost the true negative: $out" ;;
esac

section "worktree.sh missing: name that, do not blame the repo"
cp -R "$ROOT" "$TMP/ros" 2>/dev/null
rm -f "$TMP/ros/kanban/worktree.sh"
_card C3 realrepo
out="$(_start C3 "$TMP/ros/kanban/kb.sh")"
case "$out" in
  *"worktree.sh non trovato"*) ok "names the missing script" ;;
  *) err "does not name the missing script: $out" ;;
esac
case "$out" in
  *"non e un git repo"*) err "blames the repo for a missing script: $out" ;;
  *) ok "does not blame the repo" ;;
esac

section "the happy path still creates the worktree"
_card C4 realrepo
out="$(_start C4)"
if [ -d "$TMP/wt/realrepo/C4" ] && printf '%s' "$out" | grep -q 'worktree:'; then
  ok "worktree created and reported"
else
  err "no worktree on the success path: $out"
fi
grep -q '^worktree_none:' "$KB/doing/C4.md" \
  && err "success path wrote a worktree_none line" \
  || ok "success path writes no failure line"

printf "\n"
[ "$FAIL" = 0 ] && echo "test-kb-start-worktree-cause: PASS" || echo "test-kb-start-worktree-cause: FAIL"
exit "$FAIL"
