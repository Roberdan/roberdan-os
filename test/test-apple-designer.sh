#!/usr/bin/env bash
# Verify the mandatory route and real wrapper emission, without changing personal installs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for file in AGENTS.md .github/skills/roberto-twin/ENGINEERING.md; do
  grep -Fq 'Apple application UI: mandatory skill' "$file" ||
    fail "mandatory Apple UI route missing from $file"
  grep -Fq 'apple-designer' "$file" || fail "Apple Designer not named in $file"
done
route_body() {
  awk '/^## Apple application UI: mandatory skill$/{active=1;next}
       active && /^## /{exit} active && NF{print}' "$1"
}
[ "$(route_body AGENTS.md)" = "$(route_body .github/skills/roberto-twin/ENGINEERING.md)" ] ||
  fail "portable and canonical mandatory routing drifted"

skill=skills/apple-designer/skill.md
grep -Eq '^providers:.*claude.*copilot.*codex' "$skill" ||
  fail "Apple Designer must be declared for Claude, Copilot and Codex"
grep -Fq 'Mandatory Apple UI engagement' "$skill" ||
  fail "skill must require engagement before Apple application UI work"
grep -Fq 'visual-language.md' "$skill" || fail "visual-language sidecar is not referenced"
[ -s skills/apple-designer/visual-language.md ] || fail "visual-language sidecar is missing"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude" "$TMP/.copilot"
HOME="$TMP" RDA_CLAUDE_SKILLS_DIR="$TMP/.claude/skills" \
  RDA_COPILOT_SKILLS_DIR="$TMP/.copilot/skills" RDA_POINTER_HOME="$TMP" \
  RDA_FORCE_CODEX=0 RDA_FORCE_OPENCODE=0 bash bin/sync.sh --install >/dev/null
shared="$ROOT/platforms/claude/skills/apple-designer/SKILL.md"
[ -s "$shared" ] || fail "shared portable wrapper was not emitted"
for host in claude copilot; do
  wrapper="$TMP/.$host/skills/apple-designer/SKILL.md"
  [ -L "$wrapper" ] || fail "$host skill was not installed"
  [ "$(readlink "$wrapper")" = "$shared" ] || fail "$host does not reuse the shared wrapper"
  grep -Fq 'name: apple-designer' "$wrapper" || fail "$host skill name is wrong"
  grep -Fq 'skills/apple-designer/skill.md' "$wrapper" ||
    fail "$host wrapper does not point at the canonical skill"
  grep -Fq 'Required for' "$wrapper" || fail "$host trigger does not carry the mandatory route"
done
echo 'test-apple-designer: PASS (mandatory route, providers, sidecar and emitted wrappers)'
