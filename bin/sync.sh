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
#                               if <target>/<name>/ does NOT exist yet, creates it and
#                               symlinks SKILL.md to the repo's generated wrapper (stays in sync
#                               automatically as the canon changes — no static copy to drift).
#                               If <target>/<name>/ already exists (e.g. same-named skill
#                               from another skill system such as gstack), SKIPs it explicitly —
#                               never a silent overwrite. Installed into ~/.claude/skills/ always,
#                               and into ~/.copilot/skills/ too when ~/.copilot is detected present.
#                             - copilot mcp-config.json: read-only check, WARN if gbrain missing
#                               (never modified — that file is owned by Copilot).
#                             - agents/hooks: still NOT installed by this script (manual/approve).
#
# platforms/ is NOT committed to git (it's fully generated — see .gitignore). Run
# --emit-only locally whenever you need the wrappers on disk; test/validate.sh's drift
# check verifies generation is deterministic instead of diffing against committed output.
#
# Output dir override (for the determinism check in test/validate.sh): RDA_SYNC_OUT.
# Skills install dir override (for the isolated install test): RDA_CLAUDE_SKILLS_DIR
# (default $HOME/.claude/skills).
# Copilot skills install (--install only, GATED on ~/.copilot existing — i.e. Copilot
# CLI/coding-agent detected as installed): same collision-safe symlink pattern as the
# Claude skills install, into ~/.copilot/skills/. SKILL.md is a portable format (Codex,
# Gemini CLI, Cursor support it; opencode reads .claude/skills directly), so this reuses
# the ALREADY-GENERATED platforms/claude/skills/<name>/SKILL.md wrappers as the source —
# no separate copilot skill wrapper is generated. Override RDA_COPILOT_SKILLS_DIR (default
# $HOME/.copilot/skills) for isolated testing; presence is gated on the PARENT dir of that
# path existing (so tests can simulate "Copilot absent" by simply not creating it).
# Read-only check (never writes): if ~/.copilot/mcp-config.json exists but does not
# contain "gbrain", prints a WARN — that file is owned by Copilot, never modified here.
# Override RDA_COPILOT_MCP_CONFIG for isolated testing.
# Global AGENTS.md pointer install (--install only): writes ~/.codex/AGENTS.md,
# ~/.config/opencode/AGENTS.md and ~/GitHub/AGENTS.md for tools DETECTED as
# installed, never overwriting an existing file. RDA_POINTER_HOME overrides
# $HOME (default $HOME) for isolated testing; RDA_FORCE_CODEX / RDA_FORCE_OPENCODE
# (0|1) force tool-presence detection for tests.
# NB: installed skill symlinks point INTO platforms/ (gitignored) — after a
# `git clean -fdx` they dangle until the next `--emit-only`/`--install` run
# re-materializes the targets; validate.sh's tool-coverage section flags that.
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
  # Verified 2026-07-03 against hermes-agent v0.18.0 (~/.hermes): reads AGENTS.md
  # natively as "workspace instructions" — no dedicated wrapper needed, only docs.
  mkdir -p "$P/hermes"
  cat > "$P/hermes/README.md" <<'EOF'
# Hermes (Nous Research hermes-agent) → roberdan-os

Verified against hermes-agent v0.18.0 (`~/.hermes/`, wrapper `~/.local/bin/hermes`):
Hermes reads `AGENTS.md` **natively** as workspace instructions (confirmed by
`hermes chat --help`: `--ignore-rules` "Skip auto-injection of AGENTS.md, SOUL.md,
.cursorrules, memory, and preloaded skills"). The canon is already compatible —
**no wrapper needed**, only a working directory / workdir that contains (or
inherits) an `AGENTS.md`.

This file documents the recommended setup as **exact commands** — it does not run
them. `~/.hermes/config.yaml` is never touched by `bin/sync.sh`; apply by hand if
you want it.

## 1. Point a workspace at the canon

`~/GitHub/AGENTS.md` is already installed (by `bin/sync.sh --install`) as a thin
pointer to this repo's `AGENTS.md`. Two ways to use it with Hermes:

- Interactive chat: run `hermes` (or `hermes chat`) with `~/GitHub` (or any repo
  under it that has its own `AGENTS.md`) as the current directory — AGENTS.md
  auto-injects unless `--ignore-rules`/`--safe-mode` is passed.
- Cron jobs: `hermes cron create <schedule> "<prompt>" --workdir ~/GitHub` — the
  `--workdir` flag is documented (`hermes cron create --help`) to "Inject AGENTS.md
  / CLAUDE.md / .cursorrules from that directory and use it as the cwd for
  terminal/file/code_exec tools."

## 2. Add gbrain as an MCP server

Verified exact syntax via `hermes mcp add --help` (positional `name`, then
`--command` + `--args`, **not** a `--` passthrough):

```
hermes mcp add gbrain --command ~/.gbrain/gbrain-mcp-serve.sh
```

Confirm afterwards with `hermes mcp list`.

## 3. Skills (SKILL.md)

Hermes' `hermes skills` subsystem is registry/hub-driven (`browse`, `search`,
`tap add <github-repo>`, `install <identifier-or-URL>`), not a local-directory
loader: `hermes skills install --help` shows it accepts a skill identifier
(`org/skills/name`) or a direct HTTPS URL to a `SKILL.md`, and
`hermes skills tap add` can register a GitHub repo as a skill source. No flag for
"install every SKILL.md under a local dir" was found in v0.18.0. To bring in a
roberdan-os skill:

```
hermes skills tap add roberdan/roberdan-os        # if/when this repo is public on GitHub
hermes skills install <skill-identifier-from-tap>
```

Until then, Hermes sessions running inside a repo with `AGENTS.md` still see the
`skills/*/skill.md` index referenced from there — just not pre-registered as
Hermes hub skills.
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
  # generated wrapper platforms/claude/skills/<name>/SKILL.md, if <target>/<name>/
  # does not exist yet, create it and symlink SKILL.md to the repo's generated wrapper — so
  # it stays in sync automatically whenever the canon changes (no static copy to drift).
  # If <target>/<name>/ already exists (e.g. a same-named skill from another skill
  # system such as gstack), SKIP it explicitly rather than silently overriding it.
  # Generalized over a list of (label, target dir) pairs — the same
  # source wrapper set (SKILL.md is a portable format) is symlinked into
  # every detected tool's skills dir, instead of duplicating the loop per tool.
  install_skills_set() {
    local label="$1" target_dir="$2"
    echo ""
    echo "--- skills install ($label, symlink, into $target_dir) ---"
    mkdir -p "$target_dir"
    local w sname target
    for w in $(list "$P/claude/skills" "SKILL.md" 2); do
      sname="$(basename "$(dirname "$w")")"
      target="$target_dir/$sname"
      if [ -e "$target" ]; then
        echo "SKIP $sname: già presente in $target/ (verifica manualmente se è una collisione con un altro sistema di skill, es. gstack)"
        continue
      fi
      mkdir -p "$target"
      ln -s "$w" "$target/SKILL.md"
      echo "INSTALL $sname: symlink $target/SKILL.md -> $w"
    done
  }

  SKILLS_DIR="${RDA_CLAUDE_SKILLS_DIR:-$CL/skills}"
  install_skills_set "claude" "$SKILLS_DIR"

  # Copilot: same pattern, GATED on ~/.copilot existing (Copilot detected as
  # installed). RDA_COPILOT_SKILLS_DIR overrides the target dir for isolated
  # testing; presence is gated on that path's PARENT dir existing, so a test
  # can simulate "Copilot absent" by simply never creating it.
  COPILOT_SKILLS_DIR="${RDA_COPILOT_SKILLS_DIR:-$HOME/.copilot/skills}"
  COPILOT_ROOT="$(dirname "$COPILOT_SKILLS_DIR")"
  echo ""
  if [ -d "$COPILOT_ROOT" ]; then
    install_skills_set "copilot" "$COPILOT_SKILLS_DIR"
  else
    echo "--- skills install (copilot) ---"
    echo "SKIP copilot: $COPILOT_ROOT non trovato (Copilot non installato)"
  fi

  # Read-only check: Copilot's own mcp-config.json is never modified by this
  # script (it's Copilot's file), but we WARN if gbrain isn't wired into it yet.
  COPILOT_MCP_CONFIG="${RDA_COPILOT_MCP_CONFIG:-$COPILOT_ROOT/mcp-config.json}"
  if [ -f "$COPILOT_MCP_CONFIG" ]; then
    if grep -q "gbrain" "$COPILOT_MCP_CONFIG" 2>/dev/null; then
      echo "OK copilot mcp-config.json: gbrain già presente ($COPILOT_MCP_CONFIG)"
    else
      echo "WARN copilot mcp-config.json: gbrain NON trovato in $COPILOT_MCP_CONFIG — aggiungilo manualmente (file di proprietà di Copilot, mai modificato da questo script)"
    fi
  fi

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

  # opencode: ~/.config/opencode/AGENTS.md — detected by binary OR config dir
  # (rex LOW-3: a GUI/launchd-installed opencode may not be on this shell's
  # PATH; the config dir is the same detection style codex uses).
  opencode_present=0
  if [ "${RDA_FORCE_OPENCODE:-}" = "1" ]; then opencode_present=1
  elif [ "${RDA_FORCE_OPENCODE:-}" = "0" ]; then opencode_present=0
  elif command -v opencode >/dev/null 2>&1 || [ -d "$PTR_HOME/.config/opencode" ]; then opencode_present=1
  fi
  if [ "$opencode_present" -eq 1 ]; then
    install_agents_pointer "$PTR_HOME/.config/opencode/AGENTS.md" "opencode"
  else
    echo "SKIP opencode: né comando 'opencode' né $PTR_HOME/.config/opencode trovati (tool non installato)"
  fi

  # ~/GitHub/AGENTS.md: only if ~/GitHub already exists (rex LOW-2: --install
  # must not create directory trees outside the repo on machines with a
  # different layout) — plus the usual existing-file guard.
  if [ -d "$PTR_HOME/GitHub" ]; then
    install_agents_pointer "$PTR_HOME/GitHub/AGENTS.md" "\$HOME/GitHub/AGENTS.md"
  else
    echo "SKIP \$HOME/GitHub/AGENTS.md: $PTR_HOME/GitHub non esiste (layout diverso, nessuna dir creata)"
  fi

  echo ""
  echo "Real install of agents/hooks into ~/.claude: NOT performed by this script"
  echo "in unsupervised mode. Run the copies manually or approve the gate."
fi
