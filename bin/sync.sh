#!/usr/bin/env bash
# sync.sh — generates the per-platform wrappers FROM the canon (AGENTS.md, agents/, skills/).
# No hand-copied knowledge: only generated, deterministic (drift-checkable) output.
#
#   bin/sync.sh --emit-only   (safe DEFAULT) generates into platforms/{claude,copilot,codex}/
#                             does NOT touch the live ~/.claude. Also used by post-task-sync.sh.
#   bin/sync.sh --install     (GATED) installs into the real targets, defensively:
#                             - CLAUDE.md: REFUSES to overwrite an existing ~/.claude/CLAUDE.md;
#                               only prints the pointer block to add by hand.
#                             - skills: for each generated platforms/claude/skills/<name>/SKILL.md,
#                               if ~/.claude/skills/<name>/ does NOT exist yet, creates it and
#                               symlinks SKILL.md to the repo's generated wrapper (stays in sync
#                               automatically as the canon changes — no static copy to drift).
#                               If ~/.claude/skills/<name>/ already exists (e.g. same-named skill
#                               from another skill system such as gstack), SKIPs it explicitly —
#                               never a silent overwrite.
#                             - agents/hooks: still NOT installed by this script (manual/approve).
#
# platforms/ is NOT committed to git (it's fully generated — see .gitignore). Run
# --emit-only locally whenever you need the wrappers on disk; test/validate.sh's drift
# check verifies generation is deterministic instead of diffing against committed output.
#
# Output dir override (for the determinism check in test/validate.sh): RDA_SYNC_OUT.
# Skills install dir override (for the isolated install test): RDA_CLAUDE_SKILLS_DIR
# (default $HOME/.claude/skills).
# Global AGENTS.md pointer install (--install only): writes ~/.codex/AGENTS.md,
# ~/.config/opencode/AGENTS.md and ~/GitHub/AGENTS.md for tools DETECTED as
# installed, never overwriting an existing file. RDA_POINTER_HOME overrides
# $HOME (default $HOME) for isolated testing; RDA_FORCE_CODEX / RDA_FORCE_OPENCODE
# (0|1) force tool-presence detection for tests.
#
# Deterministic output: no timestamps, no unstable ordering.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="emit-only"
case "${1:-}" in
  --emit-only|"") MODE="emit-only" ;;
  --install)      MODE="install" ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  *) echo "sync.sh: unknown flag '$1' (use --emit-only | --install)" >&2; exit 2 ;;
esac

P="${RDA_SYNC_OUT:-$ROOT/platforms}"

# Extracts a simple YAML frontmatter field (name:/description:) from a file.
fm() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"; }

# Stable file ordering (sort) for deterministic output.
list() { find "$1" -maxdepth "${3:-1}" -name "$2" 2>/dev/null | LC_ALL=C sort; }

emit_global_agents_pointer() {
  # Content of the thin AGENTS.md pointer installed OUTSIDE this repo (parent
  # ~/GitHub, plus any AGENTS.md-native tool's global instructions dir: codex,
  # opencode). Single source so every installed copy is byte-identical —
  # never hand-copy this text elsewhere.
  cat <<'EOF'
# AGENTS.md → roberdan-os

Thin pointer. Canonical behavior lives in `AGENTS.md` inside `roberdan-os`
(`~/GitHub/roberdan-os/AGENTS.md`) — read that, do not duplicate it here.

Working in any repo under `~/GitHub`, by default:
- **Loop engineering** (autonomy, evidence-first, commit per phase, verified done) — code and business alike.
- **Digital twin** kicks in automatically when the output is communication/decision "as Roberto" (draft-not-send for anything external).
- Agents at the right moment: `@thor` (done-gate), `@rex` (review), `@luca` (security), `@baccio` (architecture), `@socrates` (first-principles), `@wanda` (loop).
- Human gates are never automated (see `roberdan-os/AGENTS.md#gate-umani`).
EOF
}

emit_claude() {
  local d="$P/claude"
  mkdir -p "$d/skills" "$d/agents"

  # CLAUDE.md → thin pointer to AGENTS.md (NOT installed over an existing file).
  cat > "$d/CLAUDE.md" <<EOF
# CLAUDE.md → roberdan-os

This is a thin pointer. The canonical source of behavior is
[\`AGENTS.md\`](../../AGENTS.md) in roberdan-os. Read that.

- Behavior: \`behavior/roberto-mode.md\` (engineering) + \`behavior/roberto-voice.md\` (voice) + \`behavior/thinking-toolkit.md\` (reasoning)
- Rules: \`rules/constitution.md\` + \`rules/best-practices.md\`
- Agents: \`agents/*.md\` · Loop: \`loop/loop-protocol.md\`
EOF

  # Thin SKILL.md per canonical skill → points to skills/<name>/skill.md.
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

Canonical logic: read \`skills/$name/skill.md\` in roberdan-os. This is a wrapper
generated by \`bin/sync.sh\` — do not hand-edit it.
EOF
  done

  # Agent pointer per persona → points to agents/<name>.md.
  local a aname adesc
  for a in $(list "$ROOT/agents" "*.md"); do
    aname="$(fm "$a" name)"; adesc="$(fm "$a" description)"
    cat > "$d/agents/$aname.md" <<EOF
---
name: $aname
description: $adesc
---

Canonical persona: \`agents/$aname.md\` in roberdan-os (full frontmatter: model, tools,
constraints). Generated wrapper — do not hand-edit.
EOF
  done

  # Hook snippet for settings.json (merge by hand, not installed).
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

The canonical source of behavior is `AGENTS.md` in roberdan-os. Copilot reads this
thin file: for the full behavior follow `AGENTS.md` (Behavior, Rules, Agents,
Loop Protocol, Human gates).

## Behavior
- Engineering: `behavior/roberto-mode.md` — autonomy, evidence-first, done-criteria, quality gate.
- Voice: `behavior/roberto-voice.md` — drafting/triage in Roberto's voice.
- Thinking: `behavior/thinking-toolkit.md` — first-principles, Feynman, selective frameworks.

## Rules
- `rules/constitution.md` · `rules/best-practices.md`
EOF

  # Skills as thin .prompt.md files.
  local s name desc
  for s in $(list "$ROOT/skills" "skill.md" 3); do
    name="$(fm "$s" name)"; desc="$(fm "$s" description)"
    cat > "$d/prompts/$name.prompt.md" <<EOF
# /$name

$desc

Canonical logic: \`skills/$name/skill.md\` in roberdan-os.
EOF
  done
}

emit_codex() {
  local d="$P/codex"
  mkdir -p "$d"
  # Codex reads AGENTS.md natively: emit just a config note.
  cat > "$d/README.md" <<'EOF'
# Codex → roberdan-os

Codex reads `AGENTS.md` natively from the repo root. No wrapper needed: point Codex
at the roberdan-os root (or symlink `AGENTS.md` into the target repo).

Config snippet (if an explicit instructions file is needed):
    codex --instructions "$RDA_OS/AGENTS.md"
EOF
}

emit_hermes() {
  # Deferred — "verify capabilities" gate before projecting a wrapper (see the Phase 4 plan).
  mkdir -p "$P/hermes"
  cat > "$P/hermes/README.md" <<'EOF'
# Hermes — deferred

Not built yet: format unverified, did not surface in the system scan. Gate on
"verify capabilities" before projecting a wrapper. `AGENTS.md` stays compatible
if Hermes reads it natively in the future.
EOF
}

emit_chatgpt() {
  # The pasteable bundle is generated by bin/make-bundle.sh (excludes private/).
  mkdir -p "$P/chatgpt"
  cat > "$P/chatgpt/README.md" <<'EOF'
# ChatGPT / Claude web → bundle

No filesystem: use `bin/make-bundle.sh` to generate a pasteable doc (roberto-mode
+ roberto-voice + best-practices + constitution + agents index) to paste into Custom
Instructions / Project. The bundle always EXCLUDES `private/`.
EOF
}

emit_claude
emit_copilot
emit_codex
emit_hermes
emit_chatgpt
echo "sync: wrappers emitted into $P (claude, copilot, codex, chatgpt, hermes)."

if [ "$MODE" = "install" ]; then
  echo ""
  echo "=== --install (GATED) ==="
  CL="$HOME/.claude"
  if [ -f "$CL/CLAUDE.md" ]; then
    echo "REFUSE: $CL/CLAUDE.md already exists (curated config). NOT overwriting it."
    echo "Add this pointer block by hand at the top of your CLAUDE.md:"
    echo "---8<---"
    echo "## roberdan-os (canon)"
    echo "Canonical behavior in ~/GitHub/roberdan-os/AGENTS.md — read that."
    echo "--->8---"
  fi

  # Skills → symlink install (defensive: never overwrite, never delete). For each
  # generated wrapper platforms/claude/skills/<name>/SKILL.md, if ~/.claude/skills/<name>/
  # does not exist yet, create it and symlink SKILL.md to the repo's generated wrapper — so
  # it stays in sync automatically whenever the canon changes (no static copy to drift).
  # If ~/.claude/skills/<name>/ already exists (e.g. a same-named skill from another skill
  # system such as gstack), SKIP it explicitly rather than silently overriding it.
  SKILLS_DIR="${RDA_CLAUDE_SKILLS_DIR:-$CL/skills}"
  echo ""
  echo "--- skills install (symlink, into $SKILLS_DIR) ---"
  mkdir -p "$SKILLS_DIR"
  for w in $(list "$P/claude/skills" "SKILL.md" 2); do
    sname="$(basename "$(dirname "$w")")"
    target="$SKILLS_DIR/$sname"
    if [ -e "$target" ]; then
      echo "SKIP $sname: già presente in $target/ (verifica manualmente se è una collisione con un altro sistema di skill, es. gstack)"
      continue
    fi
    mkdir -p "$target"
    ln -s "$w" "$target/SKILL.md"
    echo "INSTALL $sname: symlink $target/SKILL.md -> $w"
  done

  # Global AGENTS.md pointer install — ONLY for tools detected as installed,
  # ONLY if the target doesn't already exist (never overwrite curated config).
  # RDA_POINTER_HOME overrides $HOME for isolated testing (default $HOME).
  # RDA_FORCE_CODEX / RDA_FORCE_OPENCODE (0|1) force detection for tests
  # without depending on the real machine's installed tools.
  PTR_HOME="${RDA_POINTER_HOME:-$HOME}"
  echo ""
  echo "--- global AGENTS.md pointer install (detected tools only, into $PTR_HOME) ---"

  install_agents_pointer() {
    local target="$1" label="$2"
    if [ -e "$target" ]; then
      echo "SKIP $label: già presente in $target (mai overwrite)"
      return
    fi
    mkdir -p "$(dirname "$target")"
    emit_global_agents_pointer > "$target"
    echo "INSTALL $label: pointer scritto in $target"
  }

  # codex: ~/.codex/AGENTS.md, only if ~/.codex exists (codex installed).
  codex_present=0
  if [ "${RDA_FORCE_CODEX:-}" = "1" ]; then codex_present=1
  elif [ "${RDA_FORCE_CODEX:-}" = "0" ]; then codex_present=0
  elif [ -d "$PTR_HOME/.codex" ]; then codex_present=1
  fi
  if [ "$codex_present" -eq 1 ]; then
    install_agents_pointer "$PTR_HOME/.codex/AGENTS.md" "codex"
  else
    echo "SKIP codex: $PTR_HOME/.codex non trovato (tool non installato)"
  fi

  # opencode: ~/.config/opencode/AGENTS.md, only if `opencode` resolves.
  opencode_present=0
  if [ "${RDA_FORCE_OPENCODE:-}" = "1" ]; then opencode_present=1
  elif [ "${RDA_FORCE_OPENCODE:-}" = "0" ]; then opencode_present=0
  elif command -v opencode >/dev/null 2>&1; then opencode_present=1
  fi
  if [ "$opencode_present" -eq 1 ]; then
    install_agents_pointer "$PTR_HOME/.config/opencode/AGENTS.md" "opencode"
  else
    echo "SKIP opencode: comando 'opencode' non risolto (tool non installato)"
  fi

  # ~/GitHub/AGENTS.md: always eligible (this machine's ~/GitHub layout), no
  # tool-presence gate — only the existing-file guard applies.
  install_agents_pointer "$PTR_HOME/GitHub/AGENTS.md" "\$HOME/GitHub/AGENTS.md"

  echo ""
  echo "Real install of agents/hooks into ~/.claude: NOT performed by this script"
  echo "in unsupervised mode. Run the copies manually or approve the gate."
fi
