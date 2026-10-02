#!/usr/bin/env bash
# Hostile Git environments and argv shapes must fail closed.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok() { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

OS="$TMP/os"
mkdir -p "$OS/kanban"/{todo,doing,done}
cp "$ROOT/kanban/"{kb.sh,kb-resolve.sh,board.sh} "$OS/kanban/"
git init -q "$OS"
git -C "$OS" config user.email test@example.invalid
git -C "$OS" config user.name Test
git -C "$OS" add kanban
git -C "$OS" commit -qm init
KB="$OS/kanban/kb.sh"; REGISTRY="$TMP/registry"; printf '%s\n' "$OS" > "$REGISTRY"

UNKNOWN="$TMP/unknown"
git init -q "$UNKNOWN"
git -C "$UNKNOWN" config user.email test@example.invalid
git -C "$UNKNOWN" config user.name Test
printf 'fixture\n' > "$UNKNOWN/README"
git -C "$UNKNOWN" add README
git -C "$UNKNOWN" commit -qm init

refused_add() {
  local cwd="$1" label="$2"; shift 2
  local before after out rc
  before="$(find "$OS/kanban/todo" -type f | wc -l | tr -d ' ')"
  set +e
  out="$(cd "$cwd" && env "$@" RDA_KANBAN_REGISTRY="$REGISTRY" \
    bash "$KB" add "$label" --repo unknown "One result." "One proof." 2>&1)"
  rc=$?
  set -e
  after="$(find "$OS/kanban/todo" -type f | wc -l | tr -d ' ')"
  [ "$rc" -ne 0 ] && [ "$before" = "$after" ] \
    && printf '%s\n' "$out" | grep -q 'is not registered with kb'
}

printf 'sentinel\n' > "$OS/kanban/.coda-unknown.md"
set +e
mixed="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" queue --stop --restanti 2>&1)"
mixed_rc=$?
set -e
if [ "$mixed_rc" -ne 0 ] && [ -f "$OS/kanban/.coda-unknown.md" ]; then
  ok "mixed queue stop/count flags cannot delete fallback authorization"
else
  err "mixed queue flags bypassed the guard: $mixed"
fi

printf 'sentinel\n' > "$OS/kanban/.coda-victim.md"
set +e
crafted="$(cd "$UNKNOWN" && RDA_KANBAN_REGISTRY="$REGISTRY" \
  bash "$KB" queue --restanti victim "--z --stop " 2>&1)"
crafted_rc=$?
set -e
if [ "$crafted_rc" -ne 0 ] && [ -f "$OS/kanban/.coda-victim.md" ]; then
  ok "only one exact count argument receives the queue read exception"
else
  err "crafted queue arguments bypassed the guard: $crafted"
fi

if refused_add "$UNKNOWN" "Poisoned Git" GIT_DIR="$OS/.git" GIT_WORK_TREE="$OS"; then
  ok "ambient Git repository variables cannot redirect fallback writes"
else
  err "ambient Git repository variables bypassed the guard"
fi
if refused_add "$UNKNOWN" "Ceiling Git" GIT_CEILING_DIRECTORIES="$UNKNOWN"; then
  ok "Git discovery controls cannot hide an unknown repository"
else
  err "Git discovery controls bypassed the guard"
fi
if refused_add "$UNKNOWN/.git" "Dotgit card"; then
  ok "a cwd inside .git still fails closed"
else
  err "a cwd inside .git bypassed the guard"
fi

BARE="$TMP/unknown.git"; git init -q --bare "$BARE"
if refused_add "$BARE" "Bare card"; then
  ok "an unregistered bare repository cannot mutate fallback"
else
  err "a bare repository bypassed the guard"
fi

PRIMARY="$TMP/init-primary"
git init -q "$PRIMARY"
git -C "$PRIMARY" config user.email test@example.invalid
git -C "$PRIMARY" config user.name Test
printf 'fixture\n' > "$PRIMARY/README"
git -C "$PRIMARY" add README
git -C "$PRIMARY" commit -qm init
WORKTREE="$TMP/init-worktree"
git -C "$PRIMARY" worktree add -q -b init-worktree "$WORKTREE"
( cd "$WORKTREE" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" init >/dev/null )
if grep -Fxq "$(cd -P "$PRIMARY" && pwd)" "$REGISTRY" \
   && [ -d "$PRIMARY/kanban/todo" ] && [ ! -d "$WORKTREE/kanban" ]; then
  ok "kb init defaults to the durable primary checkout"
else
  err "kb init defaulted to a disposable worktree"
fi

PRIMARY2="$TMP/init-primary-2"
git init -q "$PRIMARY2"
git -C "$PRIMARY2" config user.email test@example.invalid
git -C "$PRIMARY2" config user.name Test
printf 'fixture\n' > "$PRIMARY2/README"
git -C "$PRIMARY2" add README
git -C "$PRIMARY2" commit -qm init
WORKTREE2="$TMP/init-worktree-2"
git -C "$PRIMARY2" worktree add -q -b init-worktree-2 "$WORKTREE2"
( cd "$TMP" && RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" init "$WORKTREE2" >/dev/null )
if grep -Fxq "$(cd -P "$PRIMARY2" && pwd)" "$REGISTRY" \
   && [ -d "$PRIMARY2/kanban/todo" ] && [ ! -d "$WORKTREE2/kanban" ]; then
  ok "an explicit worktree path normalizes to its primary checkout"
else
  err "explicit kb init kept a disposable worktree path"
fi

TARGET="$TMP/init-target"; OTHER="$TMP/init-other"
for repo in "$TARGET" "$OTHER"; do
  git init -q "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Test
  printf 'fixture\n' > "$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -qm init
done
( cd "$TARGET" && GIT_DIR="$OTHER/.git" GIT_WORK_TREE="$OTHER" \
  RDA_KANBAN_REGISTRY="$REGISTRY" bash "$KB" init >/dev/null )
target_git="$(git -C "$TARGET" rev-parse --absolute-git-dir)"
other_git="$(git -C "$OTHER" rev-parse --absolute-git-dir)"
if grep -Fxq "$(cd -P "$TARGET" && pwd)" "$REGISTRY" \
   && grep -Fxq 'kanban/todo/' "$target_git/info/exclude" \
   && [ -x "$target_git/hooks/pre-commit" ] \
   && ! grep -Fxq 'kanban/todo/' "$other_git/info/exclude" \
   && [ ! -e "$other_git/hooks/pre-commit" ]; then
  ok "kb init protects the same repository it registers under poisoned Git"
else
  err "kb init split registration from privacy protection"
fi

if [ "$FAIL" -eq 0 ]; then
  printf '\ntest-kb-board-hostile: ALL GREEN\n'
else
  printf '\ntest-kb-board-hostile: FAILURES\n'
fi
exit "$FAIL"
