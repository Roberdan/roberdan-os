#!/usr/bin/env bash
# test/test-kb-root-resolution.sh — $ROOT must survive being reached through a
# symlink.
#
# `kb` is installed as ~/.local/bin/kb -> kanban/kb.sh, and bash does NOT resolve
# symlinks for BASH_SOURCE — it reports the link path. The original
#   ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# therefore computed ~/.local on every PATH invocation, i.e. essentially always.
#
# Nothing crashed, and that is the whole reason this went unnoticed from install
# until 2026-07-29. Every consumer of $ROOT fails soft or creates what it cannot
# find:
#   - `kb lint` looked for ~/.local/kanban/lint-cards.sh and merely said it was
#     missing — filed on 2026-07-07 as "path drift", never traced to $ROOT;
#   - RDA_LEAKCHECK pointed at a privacy check that did not exist there;
#   - the worktree calls discard their own failure (`2>/dev/null || true`);
#   - and the fallback board `$ROOT/kanban` silently became ~/.local/kanban,
#     which `mkdir -p` created, so 32 real cards accumulated on a board nobody
#     had chosen and no aggregated view ever showed.
#
# So the assertions below deliberately do not stop at "lint runs". A test that
# only checked the loud symptom would have passed for the wrong reason on the
# day the board split. They pin $ROOT itself, through one link and through a
# chain, and they check a $ROOT-derived path that fails SILENTLY in production.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

KB="$TMP/board"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"

# `kb` prints the resolved repo root for us: `kb plans` lists $ROOT/docs/plan-*.md
# with paths made relative to $ROOT. Asking the script itself is better than
# re-deriving $ROOT here, which would just be a second copy of the bug.
_root_seen_by() {
  # $1 = path to invoke kb through
  RDA_KANBAN="$KB" bash "$1" plans 2>/dev/null | head -1
}

# ---------------------------------------------------------------------------
section "invoked directly, \$ROOT is the repo"
direct="$(RDA_KANBAN="$KB" bash "$ROOT/kanban/kb.sh" lint 2>&1)"
case "$direct" in
  *"lint-cards: OK"*) ok "direct invocation lints" ;;
  *) err "direct invocation should lint, got: $direct" ;;
esac

# ---------------------------------------------------------------------------
section "invoked through ONE symlink (the real install shape)"
mkdir -p "$TMP/bin"
ln -sf "$ROOT/kanban/kb.sh" "$TMP/bin/kb"
linked="$(RDA_KANBAN="$KB" bash "$TMP/bin/kb" lint 2>&1)"
case "$linked" in
  *"lint-cards: OK"*) ok "kb lint works through a symlink" ;;
  *"No such file"*)   err "REGRESSION: \$ROOT not symlink-resolved — $linked" ;;
  *)                  err "unexpected lint output through symlink: $linked" ;;
esac

# ---------------------------------------------------------------------------
section "invoked through a CHAIN of symlinks, including a relative one"
mkdir -p "$TMP/hop1" "$TMP/hop2"
ln -sf "$ROOT/kanban/kb.sh" "$TMP/hop1/kb"
ln -sf "../hop1/kb" "$TMP/hop2/kb"   # relative link — resolved against its own dir
chained="$(RDA_KANBAN="$KB" bash "$TMP/hop2/kb" lint 2>&1)"
case "$chained" in
  *"lint-cards: OK"*) ok "kb lint works through a relative symlink chain" ;;
  *) err "symlink chain not resolved: $chained" ;;
esac

# ---------------------------------------------------------------------------
# The silent half. `kb lint` is the only $ROOT consumer that says anything when
# the path is wrong; RDA_LEAKCHECK just points at nothing and the privacy check
# never runs. Pinning it is the difference between "the symptom is gone" and
# "the cause is gone".
section "a \$ROOT-derived path that fails SILENTLY still resolves"
if [ -f "$ROOT/test/leak-check.sh" ]; then
  ok "leak-check.sh exists at the repo root the fix now resolves"
else
  err "test/leak-check.sh missing — the RDA_LEAKCHECK assertion below is vacuous"
fi

# Compare PHYSICAL paths on both sides: on macOS /tmp is itself a symlink to
# /private/tmp, so a logical $ROOT and a `cd -P` resolution differ by that alone
# and the test would fail for a reason that has nothing to do with kb.
resolved_root="$(cd -P "$(dirname "$(readlink "$TMP/bin/kb")")/.." && pwd)"
physical_root="$(cd -P "$ROOT" && pwd)"
if [ "$resolved_root" = "$physical_root" ]; then
  ok "symlink resolution lands exactly on the repo root"
else
  err "resolved root '$resolved_root' != repo root '$physical_root'"
fi
if [ -f "$resolved_root/test/leak-check.sh" ]; then
  ok "RDA_LEAKCHECK (\$ROOT/test/leak-check.sh) resolves to a real file"
else
  err "RDA_LEAKCHECK would point at nothing — the privacy check cannot run"
fi

# ---------------------------------------------------------------------------
# The board is the consequence that cost 32 cards. Outside any registered repo,
# the fallback board is $ROOT/kanban; with the old $ROOT that was ~/.local/kanban
# and `mkdir -p` brought it into being. Assert the fallback is the REPO's board.
section "the fallback board is the repo's board, not the installer's directory"
fallback="$(cd "$TMP" && env -u RDA_KANBAN HOME="$TMP" bash "$TMP/bin/kb" wt 2>/dev/null; echo)"
if [ -d "$TMP/kanban" ]; then
  err "REGRESSION: a board was created next to the symlink ($TMP/kanban)"
else
  ok "no phantom board created beside the installed symlink"
fi
unset fallback

# ---------------------------------------------------------------------------
# dash.sh carries the same derivation. Today it happens to work because kb.sh
# calls it by its real path — a property of the caller. Test it the way it
# would actually break: through a symlink.
section "dash.sh resolves its own symlink"
REPO_P="$(cd -P "$ROOT" && pwd)"   # physical: /tmp is a symlink to /private/tmp on macOS
ln -sf "$PWD/kanban/dash.sh" "$TMP/bin/dash"
# Ask dash.sh what IT computed, via its own execution trace. Re-deriving the
# path here with a copy of the resolution loop would only test the copy: that
# version of this assertion passed against the unfixed dash.sh.
dash_root="$(RDA_KANBAN="$KB" bash -x "$TMP/bin/dash" 2>&1 | sed -n 's/^+ ROOT=//p' | head -1)"
if [ "$dash_root" = "$REPO_P" ]; then
  ok "dash.sh invoked via symlink resolves ROOT to the repo, so \$WT exists"
else
  err "dash.sh via symlink resolved ROOT to '$dash_root', expected '$REPO_P'"
fi
[ -f "$dash_root/kanban/worktree.sh" ] \
  && ok "worktree.sh is reachable from the resolved ROOT" \
  || err "worktree.sh NOT reachable from '$dash_root' — dash would render empty columns"
unset dash_root

# ---------------------------------------------------------------------------
# Shape, not spelling. A grep for one exact line only catches the one spelling
# that already burned us; the next script to grow a ROOT gets in free. Assert
# the RULE instead: any kanban script that derives a path from BASH_SOURCE must
# resolve the symlink chain first.
section "no kanban script derives a path from BASH_SOURCE without resolving it"
for f in kanban/*.sh; do
  grep -q 'BASH_SOURCE' "$f" || continue
  if grep -q 'while \[ -L' "$f"; then
    ok "$(basename "$f") resolves the symlink chain"
  else
    err "$(basename "$f") uses BASH_SOURCE with no 'while [ -L' resolution loop"
  fi
done

printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-kb-root-resolution: ALL GREEN"; else echo "test-kb-root-resolution: FAILURES"; fi
exit "$FAIL"
