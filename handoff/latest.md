# Handoff — session 2026-06-30 → 07-01 (roberdan-os hardening)

**For a fresh agent:** read this + `kanban/todo.md`+`doing.md` + `MEMORY.md`, then `gbrain search`
what you need. You'll have the full working context without the (huge) original conversation.

## What this session did (the story so far)

Started as "who are you / is the memory usable across tools?" and became a full hardening of
**roberdan-os** into a real, active, English, private, self-improving personal agentic OS. Delivered:
meta-loop (capture/distill/curate/evolve, launchd), memory migrated to the vault (cross-platform),
**local embedding fixed** (gbrain patched for `ollama:bge-m3`@1024 — commit `f7376b11`; recall IT
0→working, measured MRR 1.0 vs 0.41 for a non-multilingual local model), 3 discovery skills
(premortem, focus-group, problem-validation) installed + auto-invoked, a scientific paper (EN, LaTeX
PDF), full IT→EN translation, a **kanban** (`kanban/`), an **agent factory** (`factory/` — autonomous
headless-Claude task loop, Convergio's job without Convergio), and this handoff mechanism.

## Key decisions (with rationale)

- **Memory lives in the vault**, not a Claude silo (cross-platform). `.claude/memory` = deprecated cache.
- **Local-first embedding** (bge-m3 via Ollama) — privacy, cost-zero, multilingual. Patch is a local
  gbrain fork → **re-apply after any gbrain update**.
- **Self-proposing, never self-applying** on behavior. Human gates in `AGENTS.md` hold.
- **No auto-updating ontology** (socrates: over-engineering). 1 type + gated hygiene.
- **Convergio stopped** (idle 2 weeks, reversible: `convergio start` + reload launchd). Its unique
  capability (autonomous cross-session orchestration) is now reproduced lighter by `factory/`.
- **English is canonical** (system + paper). No Italian paper needed.

## Current state (what's built/running)

- Repo: private remote `github.com/Roberdan/roberdan-os`, English, CI green (`test/validate.sh`).
- launchd active: `rda-evolve` (weekly), `rda-learn` (daily), `rda-factory` (nightly 01:00).
- Skills installed in `~/.claude/skills/` (auto-invoked). Capture on (`RDA_LEARN=1`).
- gbrain: local bge-m3, ~51.6k chunks embedded.

## Open threads (the 5 current goals — see kanban/todo.md)

1. **Compound now** — largely realized via memory+kanban+handoff+learn-loop (this doc IS it). Verify learn-loop promotes real learnings over time.
2. **Agent factory** — ✅ built + smoke-tested. Enqueue real overnight tasks with `factory/enqueue.sh`.
3. **Kanban folder** — ✅ done (`kanban/todo|doing|done.md`).
4. **Context handoff** — ✅ this mechanism (`handoff/`).
5. **Always-on + iPhone** — DESIGN pending: needs gbrain+vault hosted on an always-on box + remote
   MCP for the iPhone Claude app. See paper §12 / discuss with Roberto. Not built (infra decision).

## Also in flight
- **FtS document ingest** running in background (`workspace: fightthestroke`, ~214 docs, slow) — check
  `~/.claude/jobs/.../fts-ingest.log` and `vault/reference/fightthestroke/`.

## Honest scars (don't repeat)
Wiped the gbrain brain chasing bge-m3 (recovered). Called a bug "interesting". Mistook "committed"
for "active-by-default". Lesson: verify in the live env; trust durable state, not the chat.
