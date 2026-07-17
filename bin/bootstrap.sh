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
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"

DOSSIER=""
[ "${1:-}" = "--dossier" ] && DOSSIER="${2:-}"

echo "== roberdan-os bootstrap =="

# 1) Dependencies
for dep in git jq; do command -v "$dep" >/dev/null 2>&1 || { echo "missing: $dep"; exit 1; }; done
command -v shellcheck >/dev/null 2>&1 || echo "  (shellcheck missing — validate will use bash -n)"
command -v python3 >/dev/null 2>&1 || echo "  (python3 missing — eval pipeline + leak-check tier (b) need it; validate won't be fully green)"

# 2) Generate the wrappers from the canon
bash bin/sync.sh --emit-only

# 3) Agents → ~/.claude/agents (symlink: edit the canon → propagates)
mkdir -p "$HOME/.claude/agents"
for a in agents/*.md; do n="$(basename "$a")"; ln -sf "$ROOT/$a" "$HOME/.claude/agents/$n"; done
echo "  agents symlinked into ~/.claude/agents/ ($(ls agents/*.md | wc -l | tr -d ' '))"
# Migration (v2.0.0 engine/identity split): agents/roberdan-twin.md was renamed to
# agents/twin.md — prune the stale symlink so @roberdan-twin stops resolving.
if [ -L "$HOME/.claude/agents/roberdan-twin.md" ]; then
  rm -f "$HOME/.claude/agents/roberdan-twin.md"
  echo "  pruned stale symlink ~/.claude/agents/roberdan-twin.md (renamed to twin.md in v2.0.0)"
fi

# 3b) kb CLI → ~/.local/bin/kb (symlink; every doc invokes `kb` as a command)
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/kanban/kb.sh" "$HOME/.local/bin/kb"
echo "  kb symlinked into ~/.local/bin/kb (ensure ~/.local/bin is on PATH)"

# 4) Confidential dossier → $RDA_HOME/private (local-only, never in git)
if [ -n "$DOSSIER" ] && [ -f "$DOSSIER" ]; then
  mkdir -p "$RDA_HOME/private"
  cp "$DOSSIER" "$RDA_HOME/private/roberto-profile.md"
  chmod 600 "$RDA_HOME/private/roberto-profile.md"
  echo "  dossier installed (600) in $RDA_HOME/private/"
elif [ -f "$RDA_HOME/private/roberto-profile.md" ]; then
  echo "  dossier already present in $RDA_HOME/private/"
else
  echo "  ⚠ no dossier: the twin will degrade to [placeholder]. Pass --dossier <path> to install it."
fi

# 5) Validation
bash test/validate.sh >/dev/null 2>&1 && echo "  validate: ✅ green" || echo "  validate: ⚠ see 'bash test/validate.sh'"

# 6) Gated steps (NOT executed — add these by hand)
cat <<EOF

== Next steps ==
1) Hooks (one command, idempotent, backs up settings.json first — this is what makes
   Pause & Resume "always-on"): bash bin/install-hooks.sh --apply
   (dry-run without --apply; regenerate the snippet with bash bin/sync.sh --emit-only)
2) Skills: bash bin/sync.sh --install  (symlinks the skill wrappers; validate's
   tool-coverage gate expects them once ~/.claude exists)
3) Add the thin pointer block to ~/.claude/CLAUDE.md (curated personal config — by hand).
   Get the canonical slim block (with markers) from: bash bin/sync.sh --install
   — it prints the exact block to paste. Keep it THIN: never paste a full copy of
   AGENTS.md there (that duplicate costs ~1k tokens every session; the parent
   ~/GitHub/AGENTS.md pointer already carries the canon under ~/GitHub).
4) Copilot per-repo: copy the block from $ROOT/platforms/copilot/copilot-instructions.md
   into the .github/copilot-instructions.md of whichever repos you want.
5) Copilot native adapter (agents + extension + skills): bash bin/sync.sh --install
   symlinks the custom agents into ~/.copilot/agents and the extension into
   ~/.copilot/extensions/roberdan-os/ (collision-safe, gated on ~/.copilot present).
   In Copilot CLI, /agent lists the roberdan-os agents; the extension adds context
   injection, the write/bash guards, an always-on checkpoint, and the roberdanos_*
   tools. Verify with the roberdanos_doctor tool. gbrain MCP stays manual (Copilot
   owns ~/.copilot/mcp-config.json; sync.sh never writes it).
   Note: Copilot's completion/verify-done gate is ADVISORY (warns, cannot block the
   final response) — see CHANGELOG "operational near-parity".

Done. Open a new session to activate CLAUDE.md/hooks/agents.
EOF
