#!/usr/bin/env bash
# bootstrap.sh — brings roberdan-os onto a new machine. Idempotent, non-destructive.
# The whole canon lives in the repo; this script generates the wrappers, symlinks the
# agents, and (if you pass the dossier) installs it local-only. Does NOT overwrite
# CLAUDE.md/settings.json: it prints the blocks to add by hand (gated).
#
#   bin/bootstrap.sh [--dossier /path/to/profile.md]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOSSIER=""
[ "${1:-}" = "--dossier" ] && DOSSIER="${2:-}"

echo "== roberdan-os bootstrap =="

# 1) Dependencies
for dep in git jq; do command -v "$dep" >/dev/null 2>&1 || { echo "missing: $dep"; exit 1; }; done
command -v shellcheck >/dev/null 2>&1 || echo "  (shellcheck missing — validate will use bash -n)"

# 2) Generate the wrappers from the canon
bash bin/sync.sh --emit-only

# 3) Agents → ~/.claude/agents (symlink: edit the canon → propagates)
mkdir -p "$HOME/.claude/agents"
for a in agents/*.md; do n="$(basename "$a")"; ln -sf "$ROOT/$a" "$HOME/.claude/agents/$n"; done
echo "  agents symlinked into ~/.claude/agents/ ($(ls agents/*.md | wc -l | tr -d ' '))"

# 4) Confidential dossier → ~/.roberdan-os/private (local-only, never in git)
if [ -n "$DOSSIER" ] && [ -f "$DOSSIER" ]; then
  mkdir -p "$HOME/.roberdan-os/private"
  cp "$DOSSIER" "$HOME/.roberdan-os/private/roberto-profile.md"
  chmod 600 "$HOME/.roberdan-os/private/roberto-profile.md"
  echo "  dossier installed (600) in ~/.roberdan-os/private/"
elif [ -f "$HOME/.roberdan-os/private/roberto-profile.md" ]; then
  echo "  dossier already present in ~/.roberdan-os/private/"
else
  echo "  ⚠ no dossier: the twin will degrade to [placeholder]. Pass --dossier <path> to install it."
fi

# 5) Validation
bash test/validate.sh >/dev/null 2>&1 && echo "  validate: ✅ green" || echo "  validate: ⚠ see 'bash test/validate.sh'"

# 6) Gated steps (NOT executed — add these by hand)
cat <<EOF

== Manual steps (gated) ==
1) Add the pointer block to ~/.claude/CLAUDE.md:
   ## roberdan-os — default = loop+roberto-mode; twin auto on communication/decisions;
   @board for high-stakes decisions; @thor done-gate. Canon: $ROOT/AGENTS.md
2) Cautious hook in ~/.claude/settings.json (.hooks.PreToolUse):
   { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash $ROOT/hooks/bash-guard.sh" }] }
3) Copilot per-repo: copy the block from $ROOT/platforms/copilot/copilot-instructions.md
   into the .github/copilot-instructions.md of whichever repos you want.

Done. Open a new session to activate CLAUDE.md/hooks/agents.
EOF
