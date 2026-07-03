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

section "global AGENTS.md pointer — fresh install for detected tools, skip for absent/existing"
PTR_HOME="$TMP/ptr-home"
mkdir -p "$PTR_HOME/.codex"                                    # simulate codex installed
mkdir -p "$PTR_HOME/GitHub"
printf 'PRE-EXISTING (do not touch)\n' > "$PTR_HOME/GitHub/AGENTS.md"  # pre-existing → must SKIP

pout="$(RDA_CLAUDE_SKILLS_DIR="$SKILLS_DIR/ptr-skills" RDA_POINTER_HOME="$PTR_HOME" \
        RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
prc=$?
[ "$prc" -eq 0 ] || err "sync.sh --install (pointer section) exited non-zero ($prc)"

if [ -f "$PTR_HOME/.codex/AGENTS.md" ]; then
  ok "codex AGENTS.md installed (~/.codex detected present)"
  grep -q "roberdan-os" "$PTR_HOME/.codex/AGENTS.md" && ok "codex AGENTS.md points at roberdan-os" \
    || err "codex AGENTS.md content missing roberdan-os pointer"
else
  err "expected $PTR_HOME/.codex/AGENTS.md to be installed (codex dir present)"
fi

if [ -e "$PTR_HOME/.config/opencode/AGENTS.md" ]; then
  err "opencode AGENTS.md installed despite RDA_FORCE_OPENCODE=0 (tool 'absent')"
else
  ok "opencode AGENTS.md correctly skipped (tool detected absent)"
fi
printf '%s\n' "$pout" | grep -q "^SKIP opencode:" && ok "SKIP message printed for opencode" \
  || err "expected a SKIP line for opencode — got:\n$pout"

if [ "$(cat "$PTR_HOME/GitHub/AGENTS.md")" = "PRE-EXISTING (do not touch)" ]; then
  ok "pre-existing ~/GitHub/AGENTS.md left untouched (no silent overwrite)"
else
  err "pre-existing ~/GitHub/AGENTS.md content was modified — should never happen"
fi
printf '%s\n' "$pout" | grep -qF 'SKIP $HOME/GitHub/AGENTS.md:' && ok "SKIP message printed for \$HOME/GitHub/AGENTS.md" \
  || err "expected a SKIP line for \$HOME/GitHub/AGENTS.md — got:\n$pout"

section "global AGENTS.md pointer — clean skip when a tool is fully absent (no .codex dir, forced opencode present)"
PTR_HOME2="$TMP/ptr-home-absent"
mkdir -p "$PTR_HOME2"    # no .codex dir at all → codex must be skipped
pout2="$(RDA_CLAUDE_SKILLS_DIR="$SKILLS_DIR/ptr-skills2" RDA_POINTER_HOME="$PTR_HOME2" \
         RDA_FORCE_OPENCODE=1 bash bin/sync.sh --install 2>&1)"
[ -e "$PTR_HOME2/.codex/AGENTS.md" ] && err "codex AGENTS.md installed despite no ~/.codex dir" \
  || ok "codex AGENTS.md correctly skipped (no ~/.codex dir)"
printf '%s\n' "$pout2" | grep -q "^SKIP codex:" && ok "SKIP message printed for codex" \
  || err "expected a SKIP line for codex — got:\n$pout2"
[ -f "$PTR_HOME2/.config/opencode/AGENTS.md" ] && ok "opencode AGENTS.md installed (forced present)" \
  || err "expected $PTR_HOME2/.config/opencode/AGENTS.md to be installed (RDA_FORCE_OPENCODE=1)"
[ -f "$PTR_HOME2/GitHub/AGENTS.md" ] && ok "GitHub/AGENTS.md installed fresh (no pre-existing file)" \
  || err "expected $PTR_HOME2/GitHub/AGENTS.md to be installed"

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-sync-install: PASS"; exit 0; else echo "test-sync-install: FAIL"; exit 1; fi
