#!/usr/bin/env bash
# bootstrap.sh — porta roberdan-os su una macchina nuova. Idempotente, non-distruttivo.
# Tutto il canone è nel repo; questo script genera i wrapper, symlinka gli agenti, e
# (se gli passi il dossier) lo installa local-only. NON sovrascrive CLAUDE.md/settings.json:
# stampa i blocchi da aggiungere a mano (gated).
#
#   bin/bootstrap.sh [--dossier /percorso/profile.md]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOSSIER=""
[ "${1:-}" = "--dossier" ] && DOSSIER="${2:-}"

echo "== roberdan-os bootstrap =="

# 1) Dipendenze
for dep in git jq; do command -v "$dep" >/dev/null 2>&1 || { echo "manca: $dep"; exit 1; }; done
command -v shellcheck >/dev/null 2>&1 || echo "  (shellcheck assente — validate userà bash -n)"

# 2) Genera i wrapper dal canone
bash bin/sync.sh --emit-only

# 3) Agenti → ~/.claude/agents (symlink: edit canone → propaga)
mkdir -p "$HOME/.claude/agents"
for a in agents/*.md; do n="$(basename "$a")"; ln -sf "$ROOT/$a" "$HOME/.claude/agents/$n"; done
echo "  agenti symlinkati in ~/.claude/agents/ ($(ls agents/*.md | wc -l | tr -d ' '))"

# 4) Dossier confidenziale → ~/.roberdan-os/private (local-only, mai in git)
if [ -n "$DOSSIER" ] && [ -f "$DOSSIER" ]; then
  mkdir -p "$HOME/.roberdan-os/private"
  cp "$DOSSIER" "$HOME/.roberdan-os/private/roberto-profile.md"
  chmod 600 "$HOME/.roberdan-os/private/roberto-profile.md"
  echo "  dossier installato (600) in ~/.roberdan-os/private/"
elif [ -f "$HOME/.roberdan-os/private/roberto-profile.md" ]; then
  echo "  dossier già presente in ~/.roberdan-os/private/"
else
  echo "  ⚠ nessun dossier: il twin degraderà con [placeholder]. Passa --dossier <path> per installarlo."
fi

# 5) Validazione
bash test/validate.sh >/dev/null 2>&1 && echo "  validate: ✅ verde" || echo "  validate: ⚠ vedi 'bash test/validate.sh'"

# 6) Step gated (NON eseguiti — da aggiungere a mano)
cat <<EOF

== Step manuali (gated) ==
1) Aggiungi a ~/.claude/CLAUDE.md il blocco-puntatore:
   ## roberdan-os — default = loop+roberto-mode; twin auto su comunicazione/decisioni;
   @board per decisioni high-stakes; @thor done-gate. Canone: $ROOT/AGENTS.md
2) Hook prudente in ~/.claude/settings.json (.hooks.PreToolUse):
   { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash $ROOT/hooks/bash-guard.sh" }] }
3) Copilot per-repo: copia il blocco da $ROOT/platforms/copilot/copilot-instructions.md
   nel .github/copilot-instructions.md dei repo che vuoi.

Fatto. Apri una nuova sessione per attivare CLAUDE.md/hook/agenti.
EOF
