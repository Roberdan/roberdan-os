---
name: sync
description: Keep the 3 systems aligned — Obsidian vault (durable memory), Convergio twin plans, in-repo docs. Anti-drift. Read vault before asking; mechanized by post-task-sync hook.
providers: [claude, copilot, codex]
---

# sync — align the 3 systems (vault + Convergio + repo)

Roberto keeps **3 systems** that must always stay aligned. Drift between them is one of his
top criticisms ("that plan got lost somewhere"). This skill reconciles them.

## The 3 systems
| System | What it is | Source of truth for |
|---|---|---|
| **Obsidian Vault** (`~/Obsidian/Roberdan's Vault`) | durable memory, ~312 notes | decisions, people, history, masterplans |
| **Convergio twin plans** (`cvg`, daemon :8420) | durable witness | task status, audit, gates |
| **In-repo docs** | `AGENTS.md`, `docs/plans/`, ADR | engineering truth of the code |

## Flow
1. **Read the vault BEFORE asking** — `gbrain search "<context>" --source vault` (semantic).
   The answer is probably already there.
2. **Reconcile** — if the 3 diverge, identify the authoritative source for that type of
   information (table above) and propagate.
3. **Update the masterplan** on the vault without Roberto needing to ask.
4. **Align the twin plan** in Convergio (if the daemon is active).
5. **Update in-repo docs** (AGENTS.md, repo plan, ADR) if an interface/decision changed.

## When
At the end of **every phase** of a long task (not just at the end). Mechanized by the hook
[`hooks/post-task-sync.sh`](../../hooks/post-task-sync.sh) (opt-in `RDA_AUTOSYNC=1`).

## Guardrail
- Vault is git-backed with AutoGit: **only one agent at a time** writes to the vault (lock `.git/index.lock`).
- Deleting notes/sources = human gate #4 (non-regenerable data) — never automatic.
