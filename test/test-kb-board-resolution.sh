#!/usr/bin/env bash
# test/test-kb-board-resolution.sh — linked worktrees use their primary board;
# unknown repositories may read the aggregate but cannot mutate a fallback board.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OS="$TMP/os"
mkdir -p "$OS/kanban"/{todo,doing,done}
cp "$ROOT/kanban/kb.sh" "$OS/kanban/kb.sh"
cp "$ROOT/kanban/board.sh" "$OS/kanban/board.sh"
cp "$ROOT/kanban/kb-resolve.sh" "$OS/kanban/kb-resolve.sh"
OS="$(cd -P "$OS" && pwd)"
git init -q "$OS"
git -C "$OS" config user.email test@example.invalid
git -C "$OS" config user.name Test
git -C "$OS" add kanban/kb.sh kanban/board.sh kanban/kb-resolve.sh
git -C "$OS" commit -qm init
KB="$OS/kanban/kb.sh"
REGISTRY="$TMP/registry"

PRIMARY="$TMP/registered-project"
git init -q "$PRIMARY"
PRIMARY="$(cd -P "$PRIMARY" && pwd)"
git -C "$PRIMARY" config user.email test@example.invalid
git -C "$PRIMARY" config user.name Test
printf 'fixture\n' > "$PRIMARY/README"
git -C "$PRIMARY" add README
git -C "$PRIMARY" commit -qm init
mkdir -p "$PRIMARY/kanban"/{todo,doing,done}
printf '%s\n%s\n' "$OS" "$PRIMARY" > "$REGISTRY"

WORKTREE="$TMP/registered-project-worktree"
git -C "$PRIMARY" worktree add -q -b test-worktree "$WORKTREE"
WORKTREE="$(cd -P "$WORKTREE" && pwd)"

where_out="$(cd "$WORKTREE" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" where)"
if printf '%s\n' "$where_out" | grep -Fxq "board: $PRIMARY/kanban" \
   && printf '%s\n' "$where_out" | grep -Fxq 'resolution: linked-worktree-primary'; then
  ok "a registered linked worktree names its primary board and resolution method"
else
  err "linked worktree resolved the wrong board: $where_out"
fi

( cd "$WORKTREE" && RDA_KANBAN_REGISTRY="$REGISTRY" RDA_KB_ID_BASE=260101-010101 \
    bash "$KB" add "Worktree card" --repo registered-project "One result." "One proof." >/dev/null )
if [ -f "$PRIMARY/kanban/todo/260101-010101.md" ] && [ ! -d "$WORKTREE/kanban" ]; then
  ok "a write from the linked worktree lands only on the primary board"
else
  err "linked-worktree write did not stay on the primary board"
fi

OS_WORKTREE="$TMP/os-worktree"
git -C "$OS" worktree add -q -b os-test-worktree "$OS_WORKTREE"
OS_WORKTREE="$(cd -P "$OS_WORKTREE" && pwd)"
home_where="$(cd "$OS_WORKTREE" && RDA_KANBAN_REGISTRY="$REGISTRY" \
  bash "$OS_WORKTREE/kanban/kb.sh" where)"
if printf '%s\n' "$home_where" | grep -Fxq "board: $OS/kanban" \
   && printf '%s\n' "$home_where" | grep -Fxq 'resolution: linked-worktree-primary'; then
  ok "a branch-local kb script still selects roberdan-os's primary board"
else
  err "branch-local kb script selected its worktree board: $home_where"
fi

UNKNOWN="$TMP/unregistered-project"
git init -q "$UNKNOWN"
UNKNOWN="$(cd -P "$UNKNOWN" && pwd)"
before="$(find "$OS/kanban/todo" -type f | wc -l | tr -d ' ')"
set +e
refusal="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" RDA_KB_ID_BASE=260101-020202 \
  bash "$KB" add "Wrong-board card" --repo unregistered-project "One result." "One proof." 2>&1)"
rc=$?
set -e
after="$(find "$OS/kanban/todo" -type f | wc -l | tr -d ' ')"
if [ "$rc" -ne 0 ] && [ "$before" = "$after" ] \
   && printf '%s\n' "$refusal" | grep -q 'is not registered with kb' \
   && printf '%s\n' "$refusal" | grep -q 'No board was changed'; then
  ok "an unregistered repository cannot mutate the fallback board"
else
  err "unregistered mutation was not refused safely (rc=$rc before=$before after=$after): $refusal"
fi

aggregate="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" view)"
if printf '%s\n' "$aggregate" | grep -q 'Worktree card'; then
  ok "an unregistered repository can still read the aggregate board"
else
  err "aggregate read from an unregistered repository lost registered cards"
fi

EXPLICIT_ROOT="$TMP/explicit-repo"
EXPLICIT="$EXPLICIT_ROOT/kanban"
mkdir -p "$EXPLICIT"/{todo,doing,done}
( cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" RDA_KANBAN="$EXPLICIT" \
    RDA_KB_ID_BASE=260101-030303 bash "$KB" add "Explicit card" --repo personal \
    "One result." "One proof." >/dev/null )
if [ -f "$EXPLICIT/todo/260101-030303.md" ]; then
  ok "an explicit board override remains available inside an unregistered repository"
else
  err "explicit RDA_KANBAN selection was incorrectly refused"
fi

# The primary registered repo itself (no worktree involved) must resolve
# distinctly from the linked-worktree case above — kb-resolve.sh gives it its
# own resolution label, and nothing so far exercises that branch directly.
primary_where="$(cd "$PRIMARY" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" where)"
if printf '%s\n' "$primary_where" | grep -Fxq "board: $PRIMARY/kanban" \
   && printf '%s\n' "$primary_where" | grep -Fxq 'resolution: registered-repository'; then
  ok "the registered primary repo itself resolves as registered-repository, not linked-worktree-primary"
else
  err "primary repo resolution mismatch: $primary_where"
fi

# A cwd outside ANY git repository must still fall back to the aggregate board,
# and — unlike the unregistered-git-repo case above — must NOT report an
# unregistered_repository line: there is no repository to name.
SCRATCH="$TMP/scratch-nongit"; mkdir -p "$SCRATCH"
scratch_where="$(cd "$SCRATCH" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" where)"
if printf '%s\n' "$scratch_where" | grep -Fxq "board: $OS/kanban" \
   && printf '%s\n' "$scratch_where" | grep -Fxq 'resolution: aggregate-fallback' \
   && ! printf '%s\n' "$scratch_where" | grep -q 'unregistered_repository:'; then
  ok "a non-git cwd falls back to the aggregate board with no unregistered-repository line"
else
  err "non-git fallback diagnostic wrong: $scratch_where"
fi

# The unregistered-git-repo case (used above to prove the aggregate read and
# the mutation refusal) must also surface its own root on `kb where`, so an
# operator can tell "no board at all" apart from "a board I haven't told kb about".
unknown_where="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" where)"
if printf '%s\n' "$unknown_where" | grep -Fxq 'resolution: aggregate-fallback' \
   && printf '%s\n' "$unknown_where" | grep -Fxq "unregistered_repository: $UNKNOWN"; then
  ok "an unregistered git repo's own root is named on kb where, unlike the non-git case"
else
  err "unregistered-repo diagnostic missing or wrong: $unknown_where"
fi

# If the unknown checkout is itself a linked worktree, diagnostics and the
# registration suggestion must name its durable primary checkout. Registering
# the disposable worktree would create a board that vanishes with that worktree.
git -C "$UNKNOWN" config user.email test@example.invalid
git -C "$UNKNOWN" config user.name Test
printf 'fixture\n' > "$UNKNOWN/README"
git -C "$UNKNOWN" add README
git -C "$UNKNOWN" commit -qm init
UNKNOWN_WORKTREE="$TMP/unregistered-project-worktree"
git -C "$UNKNOWN" worktree add -q -b unknown-worktree "$UNKNOWN_WORKTREE"
UNKNOWN_WORKTREE="$(cd -P "$UNKNOWN_WORKTREE" && pwd)"
set +e
unknown_worktree_refusal="$(cd "$UNKNOWN_WORKTREE" && RDA_KANBAN_REGISTRY="$REGISTRY" \
  bash "$KB" add "Wrong worktree board" --repo unregistered-project "One result." "One proof." 2>&1)"
unknown_worktree_rc=$?
set -e
if [ "$unknown_worktree_rc" -ne 0 ] \
   && printf '%s\n' "$unknown_worktree_refusal" | grep -Fq "kb init \"$UNKNOWN\"" \
   && ! printf '%s\n' "$unknown_worktree_refusal" | grep -Fq "kb init \"$UNKNOWN_WORKTREE\""; then
  ok "an unknown linked worktree tells the operator to register its durable primary checkout"
else
  err "unknown worktree suggested the wrong registration root: $unknown_worktree_refusal"
fi

# _guard_board_mutation's case statement treats `resume`, `wt` and `migrate`
# as mutating ONLY when a specific qualifying argument is present (--done,
# attach, --apply respectively). `wt attach` is exercised below as the
# qualifying form; `resume` and `migrate` are exercised in BOTH their
# non-qualifying (read) and qualifying (mutating) forms, since those two carry
# their own aux scripts in this minimal fixture (`wt`'s plain form shells out
# to worktree-sweep.sh, which is out of scope for a board-resolution fixture).
reads_ok=1
for args in "resume" "migrate"; do
  # shellcheck disable=SC2086
  out="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" $args 2>&1)"
  if printf '%s\n' "$out" | grep -q 'REFUSED'; then
    reads_ok=0
    err "non-qualifying 'kb $args' was wrongly refused: $out"
  fi
done
[ "$reads_ok" -eq 1 ] && ok "non-qualifying resume/migrate reads are never refused in an unregistered repo"

# The qualifying forms of those same commands (plus `wt attach`) must each be
# refused — proving the guard's per-subcommand argument check (not just the
# unconditional commands like `add`) actually gates the mutating branch.
qualifying_ok=1
run_qualifying() { ( cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" "$@" 2>&1 ); }
for spec in "resume --done" "wt attach card-x /no/such/path" "migrate --apply"; do
  set +e
  # shellcheck disable=SC2086
  out="$(run_qualifying $spec)"; rc=$?
  set -e
  if [ "$rc" -eq 0 ] || ! printf '%s\n' "$out" | grep -q 'is not registered with kb'; then
    qualifying_ok=0
    err "qualifying 'kb $spec' was not refused (rc=$rc): $out"
  fi
done
[ "$qualifying_ok" -eq 1 ] && ok "qualifying resume --done / wt attach / migrate --apply are each refused in an unregistered repo"

# Queue snapshots grant standing work authorization and therefore mutate the board.
# Only the remaining-count probe is read-only (goal-gate depends on it).
set +e
queue_refusal="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" \
  bash "$KB" queue --sessione fixture-session 2>&1)"
queue_rc=$?
set -e
remaining="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" queue --restanti)"
if [ "$queue_rc" -ne 0 ] \
   && printf '%s\n' "$queue_refusal" | grep -q 'is not registered with kb' \
   && [ ! -e "$OS/kanban/.coda-unregistered-project.md" ] \
   && [ "$remaining" = "0" ]; then
  ok "queue snapshots are refused while the remaining-count probe stays read-only"
else
  err "queue guard mismatch (rc=$queue_rc remaining=$remaining): $queue_refusal"
fi

# The automatic Stop-hook should silently skip the intentional unregistered case:
# no fallback checkpoint write and no misleading 'save failed' warning each turn.
HOOK_ERR="$TMP/auto-checkpoint.err"
( cd "$UNKNOWN" && RDA_KB="$KB" RDA_KANBAN_REGISTRY="$REGISTRY" \
    RDA_RECEIPT="$TMP/no-receipt" RDA_WORKTREE_SWEEP="$TMP/no-sweep" \
    bash "$ROOT/hooks/auto-checkpoint.sh" 2>"$HOOK_ERR" )
if [ ! -s "$HOOK_ERR" ] && [ ! -e "$OS/handoff/resume.md" ]; then
  ok "auto-checkpoint silently skips an unregistered repository without touching fallback state"
else
  err "auto-checkpoint emitted noise or changed fallback state: $(cat "$HOOK_ERR")"
fi

# An explicit override is deliberate authority. `kb where` must not label it as
# an unregistered fallback, and the Stop hook must refresh that selected board.
explicit_where="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" \
  RDA_KANBAN="$EXPLICIT" bash "$KB" where)"
( cd "$UNKNOWN" && RDA_KB="$KB" RDA_KANBAN_REGISTRY="$REGISTRY" RDA_KANBAN="$EXPLICIT" \
    RDA_RECEIPT="$TMP/no-receipt" RDA_WORKTREE_SWEEP="$TMP/no-sweep" \
    bash "$ROOT/hooks/auto-checkpoint.sh" )
if printf '%s\n' "$explicit_where" | grep -Fxq 'resolution: explicit-override' \
   && ! printf '%s\n' "$explicit_where" | grep -q 'unregistered_repository:' \
   && [ -f "$EXPLICIT_ROOT/handoff/resume.md" ]; then
  ok "an explicit board override remains eligible for automatic checkpoints"
else
  err "explicit override was misclassified or its checkpoint was skipped: $explicit_where"
fi

if [ "$FAIL" -eq 0 ]; then
  printf '\ntest-kb-board-resolution: ALL GREEN\n'
else
  printf '\ntest-kb-board-resolution: FAILURES\n'
fi
exit "$FAIL"
