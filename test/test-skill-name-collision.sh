#!/usr/bin/env bash
# test/test-skill-name-collision.sh — l'identita' di una skill e' il `name:` del frontmatter,
# non il nome della directory.
#
# Il difetto che questa suite inchioda: bin/sync.sh controllava la collisione solo sul nome
# della CARTELLA. gstack installa `gstack-review/` che dichiara `name: review`; la cartella
# `review/` risultava libera, la nostra veniva installata accanto, e Claude/Copilot — che
# risolvono la skill dal frontmatter — ne tenevano UNA sola. La nostra spariva in silenzio,
# senza un warning da nessuna parte. Tre skill del canone (review, ship, verify-done) erano
# oscurate cosi', e il `ship` che rispondeva non era quello con i gate umani su main.
#
# Isolata via RDA_CLAUDE_SKILLS_DIR/RDA_COPILOT_SKILLS_DIR: non tocca mai il vero ~/.claude.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Parent .copilot mai creato → il ramo copilot resta fuori da ogni caso qui sotto.
NOCOPILOT_SKILLS_DIR="$TMP/no-copilot/.copilot/skills"

# --- Skill-NAME collision (the real one) ---------------------------------
# Directory name is not identity: Claude and Copilot resolve a skill by the `name:`
# in its frontmatter. gstack installs `gstack-review/` declaring `name: review`, so a
# directory-only check finds the path free, installs our `review/` beside it, and the
# host then silently keeps ONE skill named `review` — ours never loads. These cases
# pin the frontmatter-name detection, the `rdos-` namespaced install, the retire of an
# already-shadowed copy, the heal when the foreign skill goes away, and the invariant
# that a foreign directory is never written to or deleted.
section "skill-name collision — foreign dir declaring our name → namespaced rdos- install"
NC_DIR="$TMP/name-collision"
mkdir -p "$NC_DIR/gstack-review"
printf -- '---\nname: review\ndescription: "gstack review"\n---\nFOREIGN (do not touch)\n' \
  > "$NC_DIR/gstack-review/SKILL.md"

nc_out="$(RDA_CLAUDE_SKILLS_DIR="$NC_DIR" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
    RDA_POINTER_HOME="$TMP/ptr-home-nc" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"

if [ -f "$NC_DIR/rdos-review/SKILL.md" ]; then
  ok "our review installed as rdos-review/ (name 'review' taken by gstack-review/)"
  if [ "$(grep -m1 -E '^name:' "$NC_DIR/rdos-review/SKILL.md")" = "name: rdos-review" ]; then
    ok "namespaced wrapper declares 'name: rdos-review' (no longer collides)"
  else
    err "namespaced wrapper frontmatter name not rewritten: $(grep -m1 -E '^name:' "$NC_DIR/rdos-review/SKILL.md")"
  fi
  grep -q 'skills/review/skill.md' "$NC_DIR/rdos-review/SKILL.md" \
    && ok "namespaced wrapper still points at the canon skills/review/skill.md" \
    || err "namespaced wrapper lost its canon pointer"
else
  err "expected $NC_DIR/rdos-review/SKILL.md after a name collision — got:\n$nc_out"
fi

[ -e "$NC_DIR/review" ] && err "plain review/ installed anyway — it would be shadowed by gstack-review/" \
  || ok "no shadowed plain review/ installed"

if [ "$(sed -n '5p' "$NC_DIR/gstack-review/SKILL.md")" = "FOREIGN (do not touch)" ]; then
  ok "foreign gstack-review/SKILL.md left untouched"
else
  err "foreign gstack-review/SKILL.md was modified — should never happen"
fi

# A non-colliding skill in the same run must still take the plain path.
[ -L "$NC_DIR/ship/SKILL.md" ] && ok "non-colliding skill (ship) still installed as a plain symlink" \
  || err "expected $NC_DIR/ship/SKILL.md to be a plain symlink (no collision on that name)"

section "skill-name collision — namespaced install is idempotent"
nc_out2="$(RDA_CLAUDE_SKILLS_DIR="$NC_DIR" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
    RDA_POINTER_HOME="$TMP/ptr-home-nc" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
nc_installed2="$(printf '%s\n' "$nc_out2" | grep -c '^INSTALL ' || true)"
[ "$nc_installed2" -eq 0 ] && ok "second run installs nothing new (0 INSTALL lines)" \
  || err "second run installed $nc_installed2 skills — expected 0:\n$nc_out2"
printf '%s\n' "$nc_out2" | grep -q "^SKIP review: già installato come rdos-review" \
  && ok "second run reports the namespaced skill as already installed" \
  || err "expected a SKIP line for the namespaced review — got:\n$nc_out2"

section "skill-name collision — an already-installed shadowed copy is retired"
NC2="$TMP/name-collision-retire"
mkdir -p "$NC2"
RDA_CLAUDE_SKILLS_DIR="$NC2" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
  RDA_POINTER_HOME="$TMP/ptr-home-nc2" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install >/dev/null 2>&1
[ -L "$NC2/review/SKILL.md" ] || err "setup: expected a plain review/ symlink before the collision appears"
# gstack shows up afterwards and takes the name
mkdir -p "$NC2/gstack-review"
printf -- '---\nname: review\ndescription: "gstack review"\n---\nFOREIGN\n' > "$NC2/gstack-review/SKILL.md"
RDA_CLAUDE_SKILLS_DIR="$NC2" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
  RDA_POINTER_HOME="$TMP/ptr-home-nc2" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install >/dev/null 2>&1
[ -e "$NC2/review" ] && err "our shadowed review/ survived — it can never load while gstack-review/ owns the name" \
  || ok "our shadowed review/ retired once the name was taken"
[ -f "$NC2/rdos-review/SKILL.md" ] && ok "our review re-installed as rdos-review/" \
  || err "expected $NC2/rdos-review/SKILL.md after the retire"

section "skill-name collision — heals back to the plain name when the foreign skill goes away"
rm -rf "$NC2/gstack-review"
heal_out="$(RDA_CLAUDE_SKILLS_DIR="$NC2" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
    RDA_POINTER_HOME="$TMP/ptr-home-nc2" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
[ -e "$NC2/rdos-review" ] && err "rdos-review/ left behind after the collision disappeared (two copies of one skill)" \
  || ok "rdos-review/ removed once the name was free again"
[ -L "$NC2/review/SKILL.md" ] && ok "review/ restored as a plain symlink" \
  || err "expected $NC2/review/SKILL.md to be restored — got:\n$heal_out"

section "skill-name collision — a FOREIGN rdos-<name>/ is never overwritten"
NC3="$TMP/name-collision-foreign-ns"
mkdir -p "$NC3/gstack-review" "$NC3/rdos-review"
printf -- '---\nname: review\ndescription: "gstack review"\n---\nFOREIGN\n' > "$NC3/gstack-review/SKILL.md"
printf 'SOMEONE ELSE (do not touch)\n' > "$NC3/rdos-review/SKILL.md"
ns_out="$(RDA_CLAUDE_SKILLS_DIR="$NC3" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
    RDA_POINTER_HOME="$TMP/ptr-home-nc3" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
if [ "$(cat "$NC3/rdos-review/SKILL.md")" = "SOMEONE ELSE (do not touch)" ]; then
  ok "foreign rdos-review/SKILL.md left untouched"
else
  err "foreign rdos-review/SKILL.md was overwritten — should never happen"
fi
printf '%s\n' "$ns_out" | grep -q "^SKIP review: .*non è nostro" \
  && ok "SKIP printed for the foreign namespaced dir" \
  || err "expected a SKIP line for the foreign rdos-review/ — got:\n$ns_out"


section "skill-name collision — a SYMLINKED foreign skill dir is seen too (the ~/.copilot case)"
# gstack installs into ~/.claude/skills and symlinks the DIRECTORY into ~/.copilot/skills.
# A plain `find` never descends into a symlinked dir, so the scan came back empty exactly
# where the collision was real and both copies were installed again.
NC4="$TMP/name-collision-symlinked"
REAL4="$TMP/real-gstack-skills"
mkdir -p "$NC4" "$REAL4/gstack-review"
printf -- '---\nname: review\ndescription: "gstack review"\n---\nFOREIGN\n' > "$REAL4/gstack-review/SKILL.md"
ln -s "$REAL4/gstack-review" "$NC4/gstack-review"
sym_out="$(RDA_CLAUDE_SKILLS_DIR="$NC4" RDA_COPILOT_SKILLS_DIR="$NOCOPILOT_SKILLS_DIR" \
    RDA_POINTER_HOME="$TMP/ptr-home-nc4" RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install 2>&1)"
[ -f "$NC4/rdos-review/SKILL.md" ] \
  && ok "collision through a symlinked directory detected → rdos-review/ installed" \
  || err "symlinked gstack-review/ not seen — got:\n$sym_out"
[ -e "$NC4/review" ] && err "plain review/ installed anyway — it would be shadowed by the symlinked gstack-review/" \
  || ok "no shadowed plain review/ installed"

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-skill-name-collision: PASS"; exit 0; else echo "test-skill-name-collision: FAIL"; exit 1; fi
