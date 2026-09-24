# claude-ai-skill — the roberto-mode canon, packaged for claude.ai

This directory is a hand-curated export of roberdan-os's **behavioral canon** —
`behavior/roberto-mode.md`, `identity/voice.md`, `behavior/thinking-toolkit.md`,
`rules/constitution.md`, and the human-gates list in `AGENTS.md` — repackaged as a
Custom Skill uploadable to [claude.ai](https://claude.ai).

**What it carries**: how to operate (autonomy + evidence-first + done-criteria), how to
write in Roberto's voice, how to reason through decisions, and the ethical root.

**What it does NOT carry**: the operational infrastructure — no kanban (`kb.sh`), no
gbrain/vault recall, no git/factory automation, no launchd scheduling. None of that
exists on claude.ai's sandboxed VM. Only the judgment/voice layer travels.

**Generated, not hand-maintained** (since 2026-09-24): `python3 bin/gen-portable-skills.py`
builds `roberto-mode/` and `roberto-mode.zip` from the one source,
`.github/skills/roberdan-twin/`, plus the claude.ai-specific overlay
`bin/portable-skills/claude-ai.md`. Edit those, never the output:
`test/test-portable-skills-drift.sh` fails when the two diverge.

## How to upload

Uploading is Roberto's manual step; nothing here reaches claude.ai on its own.

1. Run `python3 bin/gen-portable-skills.py`: it writes `claude-ai-skill/roberto-mode.zip`
   with the folder at the root of the zip (gitignored build product).
2. On claude.ai: **Settings → Customize → Skills → "+" → Create skill → Upload a skill**
3. Upload `roberto-mode.zip`. Requires a Pro/Max/Team/Enterprise plan with code
   execution enabled. Custom Skills on claude.ai are private to your account — not
   synced with the API or with Claude Code.
