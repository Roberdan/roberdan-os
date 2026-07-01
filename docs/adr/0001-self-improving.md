# ADR-0001 — roberdan-os self-improving: evolve / learn / ontology

**Status:** Accepted (2026-06-30) · **Deciders:** Roberto + advisor (baccio/socrates/rex)

## Context

roberdan-os has the *per-task* loop (`loop/loop-protocol.md`, `skills/auto-checkpoint`) but
no *meta-loop*: it doesn't keep itself up to date on tools, doesn't distill learnings after
interactions, doesn't reorganize memory. Goal: make it **self-improving and the
default standard**, without violating the cardinal principle — *centralized knowledge,
per-platform execution, daemon-optional* — nor the human gates.

**Cross-platform constraint (Roberto's correction):** durable memory lives in the **Obsidian
vault** (markdown readable by every tool, Tolaria ontology, gbrain-indexed),
NOT in `~/.claude/.../memory/` (Claude-only silo → demoted to cache, content migrated).

## Decisions

| Component | Decision | Rationale |
|---|---|---|
| **Scheduling** | **launchd** invokes plain `run.sh` (cron-swappable). Never `ScheduleWakeup`/`CronCreate` for periodic jobs | Must fire even with Claude closed (Copilot/Codex). The gbrain jobs already use launchd |
| **learn/** | **Capture ≠ distill.** Capture = per-platform `.jsonl` cursor → flush to staging inbox `~/.roberdan-os/learnings/inbox/` (no lock). Distill = periodic batch → candidates in **quarantine** | Decouples portability from noise. NO distill on `Stop` (Claude-only + invasive) |
| **ontology/** | **Extend the vault, no new store.** Tolaria = schema authority (`type: agent-learning`); gbrain = semantic dedup. **Single-writer** job promotes candidates → typed notes | socrates: auto-ontology = over-engineering + a 4th store that drifts. Reuse > reinvention |
| **Recall** | gbrain semantic search on the vault (+ greppable markdown). No index loaded every session | Cross-platform, already wired |
| **evolve/** | **Weekly** watcher: Claude/Copilot/Codex changelog → diff vs. capability → **draft only** in `proposals/`, with source citation (URL+version+date) | Cross-platform via launchd |

## Cut (over-engineering — socrates)

Real-time self-updating ontology · auto-generated relations between learnings ·
auto-merge/auto-compression without a gate · bespoke ontology engine on top of Tolaria.
Replaced by: **1 type + 1 human-gated hygiene job** that reuses existing types.

## Invariants (mechanical enforcement, not a promise)

1. **Never auto-apply** changes to `behavior/ rules/ agents/ AGENTS.md` — evolve produces
   **draft only**. Real enforcement in `hooks/post-task-sync.sh` (`git add -- platforms/`,
   opt-in `RDA_AUTOSYNC=1`): auto-commit is scoped only to the deterministic wrappers in
   `platforms/`; `test/validate.sh` does the **drift-check** (wrapper ≡ canon), not the allowlist.
2. **Single-writer on the vault** (Tolaria AutoGit `.git/index.lock`) — concurrent capture
   only writes to the staging inbox; a single serial process does the flush.
3. **Privacy as code:** deny-list pattern (dossier `~/.roberdan-os/private/`, personal/medical
   FtS data) verified **before** every write, not at the model's discretion.
4. **Gated promotion:** candidate → influential note only after corroboration (N sightings
   or human confirmation). The `voice` class is never auto-evolved (gate #6).
5. **No-hallucination:** every evolve proposal cites its source or doesn't exist.

## Risks → mitigation

| Risk | Mitigation |
|---|---|
| Identity/behavior drift | evolve draft-only + path-allowlist in validate.sh |
| Learning poisoning (reinforcing errors) | N-sightings corroboration + periodic `@thor`/human review |
| Memory inflation/noise | dedup-before-write via `gbrain search`; periodic hygiene; minimal hot-index |
| Embedding provider down | **discovered 2026-06-30:** openai=zero-quota, zembed=no-key → semantic recall stalled. See [[local Ollama provider]] as the only sustainable path |

## Consequence

Self-**proposing** system, never self-**applying** on behavior. Gates #6/#7
preserved by construction. Learning taxonomy: `tool-quirk · correction · decision ·
capability-gap · voice`.
