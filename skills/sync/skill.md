---
name: sync
description: "Keep Obsidian vault (durable memory) and in-repo docs aligned. Anti-drift. Read vault before asking. MANUAL — post-task-sync only regenerates the per-platform wrappers and is opt-in on RDA_AUTOSYNC=1."
providers: [claude, copilot, codex]
---

# sync — align the vault and in-repo docs

Roberto keeps **durable memory and engineering docs** aligned. Drift between them is one of his
top criticisms ("that plan got lost somewhere"). This skill reconciles them.

## Sources of truth
| System | What it is | Source of truth for |
|---|---|---|
| **Obsidian Vault** (`~/Obsidian/Roberdan's Vault`) | durable memory, ~312 notes | decisions, people, history, masterplans |
| **In-repo docs** | `AGENTS.md`, `docs/plans/`, ADR | engineering truth of the code |

## Flow
1. **Read the vault BEFORE asking** — `gbrain search "<context>" --source vault` (semantic).
   The answer is probably already there.
2. **Reconcile** — if they diverge, identify the authoritative source for that type of
   information (table above) and propagate.
3. **Update the masterplan** on the vault without Roberto needing to ask.
4. **Update in-repo docs** (AGENTS.md, repo plan, ADR) if an interface/decision changed.

## When
At the end of **every phase** of a long task (not just at the end), reconcile manually.
[`hooks/post-task-sync.sh`](../../hooks/post-task-sync.sh) only regenerates wrappers
(opt-in `RDA_AUTOSYNC=1`); it does not reconcile the vault or engineering docs.

## Guardrail
- Vault is git-backed with AutoGit: **only one agent at a time** writes to the vault (lock `.git/index.lock`).
- Deleting notes/sources = human gate #4 (non-regenerable data) — never automatic.
