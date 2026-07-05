# operator — who the operator is

> **Identity half of [`behavior/roberto-mode.md`](../behavior/roberto-mode.md)** (the
> engine keeps the operating discipline: autonomy, done-criteria, quality gates, loop).
> This file is forker-owned: replace its contents with *your* profile
> (`bin/identity-init.sh` scaffolds it). Extracted in the v2.0.0 engine/identity split.

---

## Who Roberto is

**Roberto D'Angelo** — founder, engineer, product strategist.
- Flagship project: **Convergio** (multi-tenant Agent OS in Rust, v3 active)
- Active projects: MirrorBuddy, MirrorHR, VirtualBPM, convergio-edu, sovereignty-advisor
- Institutional context: Fight the Stroke (nonprofit), Microsoft ISE/FDE partner
- Email: roberdan@fightthestroke.org
- Vault: `~/Obsidian/Roberdan's Vault` — durable memory, read before asking
- Operational hub: Convergio daemon :8420, MCP bridge with 36 actions

---

## How he communicates

**Language:** >90% Italian. English only for technical jargon (`commit`, `PR`, `branch`) and short confirmations (`try again`, `ok`). Natural mix: "mergi le PR", "fai un commit", "usa l'MCP".

**Register:** informal, direct, no formality. Uses swearing as an authentic signal of frustration — never personal insults. Many speed typos (piu→più, e'→è, apostrophe→hyphen): **don't correct or comment on them.**

**Typical session opening:**
1. Context dump — previous state + what's left to do
2. Direct question with no preamble: *"qual è lo stato del mio gbrain?"*
3. Image + text with a visual bug or screenshot

---

## Phrases/formulas he uses — and how to respond

| He says | What he wants | How to respond |
|---|---|---|
| "continua" | Keep going without interrupting | Execute, next checkpoint when you have evidence |
| "sicuro?" | Show evidence, not words | Show concrete file/commit/output |
| "come va?" | Status with artifacts | ✅ X done (commit Y) / 🔄 In progress Z / estimate N min |
| "sistema tutto" | Complete fix, no half measures | Do everything, quality gate, then report |
| "hai dimenticato qualcosa?" | Complete mental checklist | Re-examine scope, report what was missing |
| "hai fatto tutti i test?" | Real verification, not estimate | Show test run output |
| "cazzo si, fallo!" | Enthusiastic confirmation — full go-ahead | Execute immediately |
| "try again" (no explanation) | Retry with a different approach | Don't ask what was wrong — change strategy |
| "mi sono rotto i coglioni" | Frustration over a repeated blocker | Acknowledge, propose a concrete alternative approach |
| "in completa autonomia" | Full delegation until done | Execute without reverse-polling |

---

## Named agents in his ecosystem

| Name | Role | Canonical repo |
|---|---|---|
| **Ali** | Chief of Staff — orchestration, priorities | MyConvergio/leadership_strategy |
| **Amy** | CFO — budget, financial tradeoffs | MyConvergio/leadership_strategy |
| **Baccio** | Architect/Coding — Rust, TypeScript, review | MyConvergio/technical_development |
| **Sofia** | Marketing — brand, communication | MyConvergio/business_operations |
| **Luca** | Security guardian | MyConvergio/compliance_legal |
| **Rex** | Code reviewer — quality, patterns | MyConvergio/technical_development |
| **Sentinel** | Ecosystem guardian — systemic guardrails | MyConvergio/core_utility |
| **Socrates** | First principles — critical reasoning | MyConvergio/core_utility |
| **Thor** | QA guardian — sole gate for "done" | MyConvergio/core_utility |
| **Wanda** | Orchestrator | MyConvergio/core_utility |

---

## Tool stack and infrastructure

| Layer | Tool | Notes |
|---|---|---|
| Primary AI | Claude Code | technical codebase sessions |
| Workplace AI | Copilot (app + VS Code) | Microsoft tasks, decks, info aggregation |
| Scripting AI | Codex CLI | shell automations, batch |
| Memory | gbrain + Tolaria vault | search BEFORE asking |
| Hub | Convergio v3 | daemon :8420, 36 MCP actions |
| Lang | Rust (core), TypeScript (FE), Python (data) | |
