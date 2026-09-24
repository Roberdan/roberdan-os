#!/usr/bin/env bash
# test-portable-skills-drift.sh — the claude.ai and Cowork skills are GENERATED from one source
# (.github/skills/roberdan-twin + a per-surface overlay in bin/portable-skills/), never edited
# by hand. Plan 2026-09-24 item 4.8. Before this, claude-ai-skill/ had silently missed the
# AI-era lens: two hand copies drift and nothing notices. Same shape as
# test-copilot-instructions-drift.sh: regenerate into a temp dir and compare byte for byte.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT/bin/gen-portable-skills.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
OUTS="claude-ai-skill/roberto-mode/SKILL.md claude-ai-skill/roberto-mode/CONSTITUTION.md claude-ai-skill/roberto-mode/THINKING.md claude-ai-skill/roberto-mode/VOICE.md claude-ai-skill/roberto-mode/ENGINEERING.md cowork-skill/roberdan/SKILL.md"

[ -f "$GEN" ] || { err "manca il generatore $GEN"; echo "test-portable-skills-drift: FAIL"; exit 1; }
msg="$(PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --out "$TMP/a" 2>&1)" || err "il generatore fallisce: $msg"
for f in $OUTS; do
  if cmp -s "$ROOT/$f" "$TMP/a/$f"; then ok "$f coincide con la fonte"; else err "$f diverge dalla fonte: rigenera con python3 bin/gen-portable-skills.py"; fi
done
grep -q "claude.ai" <<<"$msg" && grep -qi "a mano\|manual" <<<"$msg" && ok "il generatore dice che il caricamento resta un passo manuale di Roberto" || err "manca l'avviso sul caricamento manuale: $msg"

echo "== la stessa fonte arriva in entrambe le superfici =="
for sk in claude-ai-skill/roberto-mode/SKILL.md cowork-skill/roberdan/SKILL.md; do
  for part in "Sto facendo" "Mi serve da te" "Human gates" "GENERATED"; do
    grep -q "$part" "$ROOT/$sk" && ok "$sk porta '$part'" || err "$sk senza '$part'"
  done
  grep -q "<!-- core" "$ROOT/$sk" && err "$sk contiene direttive non risolte" || ok "$sk: tutte le direttive risolte"
done
grep -q "Cold start" "$ROOT/cowork-skill/roberdan/SKILL.md" && grep -q "WorkIQ" "$ROOT/cowork-skill/roberdan/SKILL.md" \
  && ok "Cowork conserva la sua parte propria (avvio a freddo, dati del tenant)" || err "Cowork ha perso la parte di superficie"
grep -q "AI-era lens" "$ROOT/claude-ai-skill/roberto-mode/THINKING.md" && ok "claude.ai riceve la lente dell'era AI (prima mancava)" || err "THINKING.md di claude.ai indietro"
# The zip is gitignored (a build product): check the generated one, and the local one if present.
z="$(unzip -l "$TMP/a/claude-ai-skill/roberto-mode.zip" 2>/dev/null)"
grep -q " roberto-mode/SKILL.md" <<<"$z" && grep -q " roberto-mode/ENGINEERING.md" <<<"$z" && ok "lo zip ha la cartella alla radice, pronto da caricare" || err "zip senza roberto-mode/SKILL.md: $z"
if [ -f "$ROOT/claude-ai-skill/roberto-mode.zip" ]; then
  cmp -s "$ROOT/claude-ai-skill/roberto-mode.zip" "$TMP/a/claude-ai-skill/roberto-mode.zip" && ok "lo zip locale coincide con la fonte" || err "lo zip locale e' vecchio: rigenera"
fi

echo "== una modifica alla fonte cambia le uscite (il test vede la deriva) =="
cp -R "$ROOT/.github/skills/roberdan-twin" "$TMP/src"
python3 - "$TMP/src/SKILL.md" <<'EOF'
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace("## Never\n", "## Never\n\n- MUTANTE-FONTE\n", 1); open(p, "w").write(s)
EOF
PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --source "$TMP/src" --out "$TMP/b" >/dev/null 2>&1
for sk in claude-ai-skill/roberto-mode/SKILL.md cowork-skill/roberdan/SKILL.md; do
  grep -q "MUTANTE-FONTE" "$TMP/b/$sk" && ! cmp -s "$ROOT/$sk" "$TMP/b/$sk" && ok "fonte cambiata -> $sk cambia" || err "fonte cambiata ma $sk no"
done
PYTHONDONTWRITEBYTECODE=1 python3 "$GEN" --out "$TMP/c" >/dev/null 2>&1
cmp -s "$TMP/a/claude-ai-skill/roberto-mode.zip" "$TMP/c/claude-ai-skill/roberto-mode.zip" && ok "lo zip e' deterministico (due generazioni, stessi byte)" || err "zip non deterministico"

[ "$FAIL" -eq 0 ] && echo "test-portable-skills-drift: PASS" || { echo "test-portable-skills-drift: FAIL"; exit 1; }
