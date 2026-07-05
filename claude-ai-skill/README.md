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

Not wired into `bin/sync.sh` — this is a manually maintained export, not an
auto-generated `platforms/` artifact. If the source canon changes meaningfully,
re-derive this by hand (or ask an agent to re-derive it) rather than assuming it's
still in sync.

## How to upload

1. Zip the `roberto-mode/` folder (the folder itself must be at the root of the zip,
   not just its contents): `cd claude-ai-skill && zip -r roberto-mode.zip roberto-mode`
2. On claude.ai: **Settings → Customize → Skills → "+" → Create skill → Upload a skill**
3. Upload `roberto-mode.zip`. Requires a Pro/Max/Team/Enterprise plan with code
   execution enabled. Custom Skills on claude.ai are private to your account — not
   synced with the API or with Claude Code.
