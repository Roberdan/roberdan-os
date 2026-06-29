---
name: sync
description: Keep the 3 systems aligned — Obsidian vault (durable memory), Convergio twin plans, in-repo docs. Anti-drift. Read vault before asking; mechanized by post-task-sync hook.
providers: [claude, copilot, codex]
---

# sync — allinea i 3 sistemi (vault + Convergio + repo)

Roberto tiene **3 sistemi** che vanno sempre allineati. Il drift tra loro è un suo
top-criticism ("quel piano si è perso in giro"). Questa skill li riconcilia.

## I 3 sistemi
| Sistema | Cos'è | Fonte di verità per |
|---|---|---|
| **Vault Obsidian** (`~/Obsidian/Roberdan's Vault`) | memoria duratura, ~312 note | decisioni, persone, storia, masterplan |
| **Convergio twin plans** (`cvg`, daemon :8420) | witness durevole | stato dei task, audit, gate |
| **Docs in-repo** | `AGENTS.md`, `docs/plans/`, ADR | verità ingegneristica del codice |

## Flusso
1. **Leggi il vault PRIMA di chiedere** — `gbrain search "<contesto>" --source vault` (semantico).
   La risposta è probabilmente già lì.
2. **Riconcilia** — se i 3 divergono, identifica la fonte autorevole per quel tipo di
   informazione (tabella sopra) e propaga.
3. **Aggiorna il masterplan** sul vault senza che Roberto debba chiedere.
4. **Allinea il twin plan** in Convergio (se il daemon è attivo).
5. **Aggiorna le docs in-repo** (AGENTS.md, repo plan, ADR) se è cambiata un'interfaccia/decisione.

## Quando
A fine di **ogni fase** di un task lungo (non solo alla fine). Meccanizzato dall'hook
[`hooks/post-task-sync.sh`](../../hooks/post-task-sync.sh) (opt-in `RDA_AUTOSYNC=1`).

## Guardrail
- Vault git-backed con AutoGit: **un solo agente alla volta** scrive sul vault (lock `.git/index.lock`).
- Cancellazione di note/source = gate umano #4 (dati non-rigenerabili) — mai automatico.
