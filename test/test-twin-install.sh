#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/generated"
RDA_SYNC_OUT="$P" RDA_CLAUDE_SKILLS_DIR="$TMP/not-installed" \
  bash "$ROOT/bin/sync.sh" --emit-only >/dev/null
[ ! -e "$TMP/not-installed" ]
fm() { grep -m1 -E "^$2:" "$1" | sed -E "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"; }
list() { find "$1" -maxdepth "${3:-1}" -name "$2" | LC_ALL=C sort; }
# shellcheck source=bin/lib-skills-install.sh
. "$ROOT/bin/lib-skills-install.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
install_at() { install_skills_set test "$1" > "$TMP/last-install.log"; }
new="$ROOT/.github/skills/roberdan-twin"
legacy="$ROOT/.github/skills/roberto-twin"

install_at "$TMP/fresh"
wrapper="$TMP/fresh/roberdan-twin/SKILL.md"
[ -L "$wrapper" ] || fail "fresh install did not create the twin wrapper"
[ "$(fm "$wrapper" name)" = roberdan-twin ] || fail "wrong public name"
for file in SKILL ENGINEERING VOICE THINKING CONSTITUTION; do
  grep -Fq "$new/$file.md" "$wrapper" || fail "missing absolute reference: $file"
  [ -s "$new/$file.md" ] || fail "missing companion: $file"
done
install_at "$TMP/fresh"
if grep -q '^INSTALL ' "$TMP/last-install.log"; then fail "second install was not idempotent"; fi

mkdir "$TMP/dangling"
ln -s "$legacy" "$TMP/dangling/roberto-twin"
install_at "$TMP/dangling"
[ ! -L "$TMP/dangling/roberto-twin" ] || fail "owned dangling directory link retained"
[ -s "$TMP/dangling/roberdan-twin/SKILL.md" ] || fail "replacement not readable"

mkdir -p "$TMP/file-link/roberto-twin"
ln -s "$legacy/SKILL.md" "$TMP/file-link/roberto-twin/SKILL.md"
printf 'preserve this note\n' > "$TMP/file-link/roberto-twin/local-note.txt"
install_at "$TMP/file-link"
[ ! -L "$TMP/file-link/roberto-twin/SKILL.md" ] || fail "owned old file link retained"
grep -q 'preserve this note' "$TMP/file-link/roberto-twin/local-note.txt" || fail "local note lost"

mkdir "$TMP/relative"
relative="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$legacy" "$TMP/relative")"
ln -s "$relative" "$TMP/relative/roberto-twin"
install_at "$TMP/relative"
[ ! -L "$TMP/relative/roberto-twin" ] || fail "relative owned link retained"

mkdir "$TMP/new-alias"
ln -s "$new" "$TMP/new-alias/roberto-twin"
install_at "$TMP/new-alias"
[ ! -L "$TMP/new-alias/roberto-twin" ] || fail "legacy alias of new canon retained"
[ -s "$new/SKILL.md" ] || fail "directory-link migration changed its target"
[ ! -e "$TMP/new-alias/rdos-roberdan-twin" ] || fail "owned alias caused a false name collision"

mkdir -p "$TMP/real/roberto-twin"
printf '%s\n' '---' 'name: roberto-twin' '---' 'local edits' > "$TMP/real/roberto-twin/SKILL.md"
install_at "$TMP/real"
grep -q 'local edits' "$TMP/real/roberto-twin/SKILL.md" || fail "real copy was changed"
grep -q 'preserve real copy' "$TMP/last-install.log" || fail "real-copy conflict was hidden"

mkdir -p "$TMP/foreign/roberdan-twin"
printf '%s\n' '---' 'name: roberdan-twin' '---' 'foreign' > "$TMP/foreign/roberdan-twin/SKILL.md"
ln -s "$legacy" "$TMP/foreign/roberto-twin"
install_at "$TMP/foreign"
[ -L "$TMP/foreign/roberto-twin" ] || fail "legacy link retired without a managed replacement"
grep -q 'foreign' "$TMP/foreign/roberdan-twin/SKILL.md" || fail "foreign replacement overwritten"

mkdir -p "$TMP/collision/foreign"
printf '%s\n' '---' 'name: roberdan-twin' '---' 'foreign' > "$TMP/collision/foreign/SKILL.md"
install_at "$TMP/collision"
[ "$(fm "$TMP/collision/rdos-roberdan-twin/SKILL.md" name)" = rdos-roberdan-twin ] ||
  fail "declared-name collision did not use the existing namespace"
grep -q 'foreign' "$TMP/collision/foreign/SKILL.md" || fail "foreign named skill changed"

mkdir -p "$TMP/unrelated" "$TMP/other"
printf 'other data\n' > "$TMP/other/SKILL.md"
ln -s "$TMP/other" "$TMP/unrelated/roberto-twin"
install_at "$TMP/unrelated"
[ -L "$TMP/unrelated/roberto-twin" ] || fail "unrelated link was removed"
grep -q 'other data' "$TMP/other/SKILL.md" || fail "unrelated target changed"
echo "test-twin-install: PASS (fresh, idempotent, companions, exact-link migration, collisions and preservation)"
