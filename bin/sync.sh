#!/usr/bin/env bash
# sync.sh — genera i wrapper per-platform DAL canone (AGENTS.md, agents/, skills/).
# Niente conoscenza copiata a mano: solo generata, deterministica (drift-checkable).
#
#   bin/sync.sh --emit-only   (DEFAULT sicuro) genera in platforms/{claude,copilot,codex}/
#                             NON tocca ~/.claude live. Usato anche da post-task-sync.sh.
#   bin/sync.sh --install     (GATED) installa i wrapper nei target reali. RIFIUTA di
#                             sovrascrivere un ~/.claude/CLAUDE.md esistente: stampa solo
#                             il blocco-puntatore da aggiungere a mano.
#
# Output deterministico: nessun timestamp, nessun ordine non-stabile.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="emit-only"
case "${1:-}" in
  --emit-only|"") MODE="emit-only" ;;
  --install)      MODE="install" ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  *) echo "sync.sh: flag sconosciuto '$1' (usa --emit-only | --install)" >&2; exit 2 ;;
esac

P="$ROOT/platforms"

# Estrae un campo frontmatter YAML semplice (name:/description:) da un file.
fm() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"; }

# Ordine stabile dei file (sort) per output deterministico.
list() { find "$1" -maxdepth "${3:-1}" -name "$2" 2>/dev/null | LC_ALL=C sort; }

emit_claude() {
  local d="$P/claude"
  mkdir -p "$d/skills" "$d/agents"

  # CLAUDE.md → puntatore thin ad AGENTS.md (NON installato su file esistente).
  cat > "$d/CLAUDE.md" <<EOF
# CLAUDE.md → roberdan-os

Questo è un puntatore thin. La fonte canonica del comportamento è
[\`AGENTS.md\`](../../AGENTS.md) in roberdan-os. Leggi quello.

- Behavior: \`behavior/roberto-mode.md\` (engineering) + \`behavior/roberto-voice.md\` (voce) + \`behavior/thinking-toolkit.md\` (ragionamento)
- Rules: \`rules/constitution.md\` + \`rules/best-practices.md\`
- Agents: \`agents/*.md\` · Loop: \`loop/loop-protocol.md\`
EOF

  # SKILL.md thin per ogni skill canonica → punta a skills/<name>/skill.md.
  local s name desc
  for s in $(list "$ROOT/skills" "skill.md" 3); do
    name="$(fm "$s" name)"; desc="$(fm "$s" description)"
    mkdir -p "$d/skills/$name"
    cat > "$d/skills/$name/SKILL.md" <<EOF
---
name: $name
description: $desc
---

# $name (wrapper)

Logica canonica: leggi \`skills/$name/skill.md\` in roberdan-os. Questo è un wrapper
generato da \`bin/sync.sh\` — non editarlo a mano.
EOF
  done

  # Agent pointer per ogni persona → punta ad agents/<name>.md.
  local a aname adesc
  for a in $(list "$ROOT/agents" "*.md"); do
    aname="$(fm "$a" name)"; adesc="$(fm "$a" description)"
    cat > "$d/agents/$aname.md" <<EOF
---
name: $aname
description: $adesc
---

Persona canonica: \`agents/$aname.md\` in roberdan-os (frontmatter completo: model, tools,
constraints). Wrapper generato — non editare a mano.
EOF
  done

  # Snippet hook per settings.json (da unire a mano, non installato).
  cat > "$d/settings-hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "$RDA_OS/hooks/main-guard.sh" }] },
      { "matcher": "Bash",        "hooks": [{ "type": "command", "command": "$RDA_OS/hooks/bash-guard.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "$RDA_OS/hooks/autofmt.sh" }] }
    ],
    "Stop": [
      { "hooks": [
          { "type": "command", "command": "$RDA_OS/hooks/verify-done.sh" },
          { "type": "command", "command": "$RDA_OS/hooks/post-task-sync.sh" }
      ] }
    ]
  }
}
EOF
}

emit_copilot() {
  local d="$P/copilot"
  mkdir -p "$d/prompts"

  # .github/copilot-instructions.md thin → AGENTS.md.
  cat > "$d/copilot-instructions.md" <<'EOF'
# Copilot instructions → roberdan-os

La fonte canonica del comportamento è `AGENTS.md` in roberdan-os. Copilot legge questo
file thin: per il comportamento completo segui `AGENTS.md` (Behavior, Rules, Agents,
Loop Protocol, Gate umani).

## Behavior
- Engineering: `behavior/roberto-mode.md` — autonomia, evidence-first, done-criteria, quality gate.
- Voice: `behavior/roberto-voice.md` — drafting/triage nella voce di Roberto.
- Thinking: `behavior/thinking-toolkit.md` — first-principles, Feynman, framework selettivi.

## Rules
- `rules/constitution.md` · `rules/best-practices.md`
EOF

  # Skill come .prompt.md thin.
  local s name desc
  for s in $(list "$ROOT/skills" "skill.md" 3); do
    name="$(fm "$s" name)"; desc="$(fm "$s" description)"
    cat > "$d/prompts/$name.prompt.md" <<EOF
# /$name

$desc

Logica canonica: \`skills/$name/skill.md\` in roberdan-os.
EOF
  done
}

emit_codex() {
  local d="$P/codex"
  mkdir -p "$d"
  # Codex legge AGENTS.md nativamente: emetti solo una nota di config.
  cat > "$d/README.md" <<'EOF'
# Codex → roberdan-os

Codex legge `AGENTS.md` nativamente dalla root del repo. Nessun wrapper necessario:
punta Codex alla root di roberdan-os (o symlinka `AGENTS.md` nel repo target).

Config snippet (se serve un instructions-file esplicito):
    codex --instructions "$RDA_OS/AGENTS.md"
EOF
}

emit_hermes() {
  # Deferred — gate "verifica capabilities" prima di proiettare (vedi piano Fase 4).
  mkdir -p "$P/hermes"
  cat > "$P/hermes/README.md" <<'EOF'
# Hermes — deferred

Non costruito ora: formato non verificato, non emerso nello scan di sistema. Gate
"verifica capabilities" prima di proiettare un wrapper. `AGENTS.md` resta compatibile
se in futuro Hermes lo legge nativamente.
EOF
}

emit_chatgpt() {
  # Il bundle incollabile lo genera bin/make-bundle.sh (esclude private/).
  mkdir -p "$P/chatgpt"
  cat > "$P/chatgpt/README.md" <<'EOF'
# ChatGPT / Claude web → bundle

Niente filesystem: usa `bin/make-bundle.sh` per generare un doc incollabile (roberto-mode
+ roberto-voice + best-practices + constitution + agents index) da incollare in Custom
Instructions / Project. Il bundle ESCLUDE sempre `private/`.
EOF
}

emit_claude
emit_copilot
emit_codex
emit_hermes
emit_chatgpt
echo "sync: wrapper emessi in platforms/ (claude, copilot, codex, chatgpt, hermes)."

if [ "$MODE" = "install" ]; then
  echo ""
  echo "=== --install (GATED) ==="
  CL="$HOME/.claude"
  if [ -f "$CL/CLAUDE.md" ]; then
    echo "REFUSE: $CL/CLAUDE.md esiste già (config curata). NON lo sovrascrivo."
    echo "Aggiungi a mano questo blocco-puntatore in cima al tuo CLAUDE.md:"
    echo "---8<---"
    echo "## roberdan-os (canone)"
    echo "Comportamento canonico in ~/GitHub/roberdan-os/AGENTS.md — leggi quello."
    echo "--->8---"
  fi
  echo "Install reale di skills/agents/hooks in ~/.claude: NON eseguito da questo script"
  echo "in modalità non-supervisionata. Esegui i copy manualmente o approva il gate."
fi
