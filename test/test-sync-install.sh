#!/usr/bin/env bash
# test/test-sync-install.sh — proves bin/sync.sh --install's skills symlink step:
# (a) installs a symlink for every generated skill when the target dir is free,
# (b) never overwrites/deletes an already-present ~/.claude/skills/<name>/ (e.g. a
#     same-named skill from another skill system, such as gstack), and
# (c) is idempotent (re-running after a full install is a no-op skip on everything).
# Fully isolated via RDA_CLAUDE_SKILLS_DIR — never touches the real ~/.claude/skills.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILLS_DIR="$TMP/claude-skills"

section "bin/sync.sh --emit-only (default mode): must NOT touch the skills install dir"
RDA_CLAUDE_SKILLS_DIR="$SKILLS_DIR" bash bin/sync.sh --emit-only >/dev/null 2>&1
if [ -e "$SKILLS_DIR" ]; then
  err "--emit-only created/touched $SKILLS_DIR — install must be gated behind --install"
else
  ok "--emit-only left $SKILLS_DIR untouched (does not exist)"
fi

# Fixture: a skill already present at a name that will collide with a generated one
# ("sync" is always generated from skills/sync/skill.md), simulating another skill
# system (e.g. gstack) that got there first.
mkdir -p "$SKILLS_DIR/sync"
printf 'PRE-EXISTING (do not touch)\n' > "$SKILLS_DIR/sync/SKILL.md"

section "bin/sync.sh --install: fresh run installs symlinks, skips the collision"
out="$(RDA_CLAUDE_SKILLS_DIR="$SKILLS_DIR" bash bin/sync.sh --install 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || err "sync.sh --install exited non-zero ($rc)"

if printf '%s\n' "$out" | grep -q "^SKIP sync: già presente"; then
  ok "SKIP printed for the colliding skill (sync)"
else
  err "expected a SKIP line for 'sync' (pre-existing collision) — got:\n$out"
fi

if [ "$(cat "$SKILLS_DIR/sync/SKILL.md")" = "PRE-EXISTING (do not touch)" ]; then
  ok "pre-existing SKILL.md content untouched (no silent overwrite)"
else
  err "pre-existing SKILL.md content was modified — should never happen"
fi
[ -L "$SKILLS_DIR/sync/SKILL.md" ] && err "pre-existing sync/SKILL.md was replaced with a symlink" \
  || ok "pre-existing sync/SKILL.md is still a plain file, not a symlink"

section "bin/sync.sh --install: installs a real symlink for a non-colliding skill"
if [ -L "$SKILLS_DIR/verify-done/SKILL.md" ]; then
  ok "verify-done/SKILL.md is a symlink"
  linked_target="$(readlink "$SKILLS_DIR/verify-done/SKILL.md")"
  case "$linked_target" in
    /*) ok "symlink target is an absolute path ($linked_target)" ;;
    *)  err "symlink target is not absolute: $linked_target" ;;
  esac
  [ -f "$linked_target" ] && ok "symlink resolves to an existing generated wrapper" \
    || err "symlink target does not exist: $linked_target"
else
  err "expected $SKILLS_DIR/verify-done/SKILL.md to be a symlink after install"
fi

section "bin/sync.sh --install: idempotent (second run only SKIPs, installs nothing new)"
out2="$(RDA_CLAUDE_SKILLS_DIR="$SKILLS_DIR" bash bin/sync.sh --install 2>&1)"
installed2="$(printf '%s\n' "$out2" | grep -c '^INSTALL ' || true)"
skipped2="$(printf '%s\n' "$out2" | grep -c '^SKIP ' || true)"
[ "$installed2" -eq 0 ] && ok "second run installs 0 new skills" \
  || err "second run installed $installed2 skills — should be 0 (idempotent skip expected)"
[ "$skipped2" -gt 0 ] && ok "second run skipped $skipped2 already-installed skills" \
  || err "second run skipped 0 — expected all previously-installed skills to be skipped"

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-sync-install: PASS"; exit 0; else echo "test-sync-install: FAIL"; exit 1; fi
