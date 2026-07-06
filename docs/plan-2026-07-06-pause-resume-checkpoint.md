# Pause / Resume + lean auto-checkpoint — design (not yet built)

> **Status:** design agreed with Roberto 2026-07-06, implementation pending. Durable so a reboot
> mid-thread loses nothing: a fresh session reads this + `handoff/latest.md` and can build it.

## The ask

A canonical, cross-tool (Claude, Copilot, …) way to never lose work when Roberto has to leave or
reboot:
- On **"devo andare" / "metti in pausa" / "fermati" / "pausa" / "stop"** → the agent brings work
  to a safe point and writes a durable checkpoint, then confirms it's safe to leave.
- On **"continua" / "continua da dove eri arrivato" / "riprendi"** → the agent reads the
  checkpoint and continues from the exact next step.
- Plus a **lean auto-save**: the checkpoint stays current after every turn by default, so even an
  unannounced crash/reboot loses nothing. **Lean = one overwritten file, fixed sections — never a
  growing log.**

## What already exists (do NOT reinvent)

- **git commit per phase** (roberto-mode): every committed phase is already a durable checkpoint —
  the reason no work was lost this session despite dead subagents.
- **`handoff/latest.md`**: injected at every session start by the `SessionStart` context hook —
  already the "resume from where you were" for cross-session state.
- **`skills/auto-checkpoint`**: a loop kit with durable-state + auto-resume — but scoped to the
  loop, not an always-on session auto-save.
- **`hooks/post-task-sync.sh`**: runs after each task, but regenerates wrappers — doesn't checkpoint.

The gap is exactly the lean always-on session checkpoint + the explicit pause/resume verbs.

## Decision: per-repo, like the KB (Roberto's call)

The checkpoint is **per-repo, cwd-resolved, gitignored** — the same shape as the now-federated
kanban and handoff, not a global exception.

- **File:** `<repo>/handoff/resume.md` (next to `handoff/latest.md`, but **gitignored** — it is
  ephemeral local runtime state, not committed canon). `kb init` adds it to a repo's gitignore;
  roberdan-os gitignores it directly.
- **Resolution:** `kb pause`/`kb resume` resolve the current repo from cwd, exactly like `kb` and
  `kb handoff`. Outside a repo, or with `--all`, they aggregate across registered boards.

## Commands (in `kanban/kb.sh`)

- **`kb pause [note]`** — write/overwrite `<repo>/handoff/resume.md` with fixed sections:
  timestamp, the note (*what I was doing + the precise next step* — the part only the agent can
  articulate), `HEAD` sha+subject, `git status` dirty count, the current `doing/` card (if any).
  Lean: overwrite, never append.
- **`kb resume`** — cwd repo's checkpoint; `kb resume --all` (or outside a repo) aggregates every
  registered repo's checkpoint; `kb resume --done` clears it after resuming.
- **`kb pause --auto`** — the lean variant the Stop hook calls: refresh only the mechanical fields
  (HEAD, git, doing, timestamp), **preserve the human note** from the last explicit `kb pause`.

## Auto-save (the "always current" part)

A **`Stop` hook** (`hooks/auto-checkpoint.sh`, wired in settings.json) runs after every agent turn
and calls `kb pause --auto` in the session cwd. Overwrite-only → stays lean. So the mechanical
"where I am" is never more than one turn stale; the richer "what/next" note is refreshed by the
agent at meaningful moments (end of a phase, before a long op) or on an explicit pause — not every
micro-step (that's what keeps it from exploding).

## Canon (cross-tool)

New **`AGENTS.md § Pause & Resume`** section defines the trigger phrases and the contract, so every
tool that reads AGENTS.md (Copilot, Codex, …) inherits it. The `SessionStart` context-inject hook
surfaces `<repo>/handoff/resume.md` if present, so a fresh session auto-notices a pending resume.

## Phases (each leaves validate green)

1. `kb pause`/`kb resume` (+ `--all`/`--done`/`--auto`) in kb.sh + usage + gitignore + `kb init`
   adds resume.md to per-repo gitignore. Test: write/read/clear, cwd vs aggregate, lean-overwrite.
2. `hooks/auto-checkpoint.sh` (Stop hook) + wire into settings.json (gated: it edits the user's
   global settings — confirm) + context-inject surfaces a pending resume.
3. `AGENTS.md § Pause & Resume` canon + a note in the global `~/.claude/CLAUDE.md` block.

## Honest limits

- The Stop hook captures mechanical state; the "next step" note is only as good as the agent's
  last explicit update — a crash between a note update and real progress can leave the note one
  step optimistic. git HEAD + the doing card are the ground truth backstop.
- `--auto` must be fast and never fail the turn (a hook that errors is worse than no hook): guard
  everything, always exit 0.
