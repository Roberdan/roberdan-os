---
name: review
description: Pre-landing code review — correctness, security, patterns, reuse/simplification. Severity-classified findings with file:line evidence. Read-only; the owner applies fixes.
providers: [claude, copilot, codex]
---

# review — code review pre-landing

Review del diff prima del merge. Read-only: produci findings con `file:line` ed esempi
concreti; il fix lo applica chi possiede il task. Vedi [`agents/rex.md`](../../agents/rex.md).

## 8 step
`context → architecture → logic → security → performance → style → tests → docs`

## Cosa cercare
- **Correctness** — bug logici, edge case, race condition, error handling.
- **Security** — OWASP Top 10, input validation, secrets, auth, SQL parametrizzato.
- **Patterns** — SOLID; anti-pattern (God Object, Spaghetti, Golden Hammer, Copy-Paste).
- **Reuse / simplification** — DRY, KISS, codice morto, astrazioni sbagliate, complessità inutile.
- **Tests** — coverage adeguato, mock ai boundary giusti (API/network/fs/time, MAI auth/DB/modulo-under-test).
- **Surgical edits** — ogni riga del diff tracciabile alla richiesta; niente "miglioramenti" fuori scope.

## Severità
**CRITICAL** (blocca) · **HIGH** · **MEDIUM** · **SUGGESTION**

## Review comments (quando rispondi ai commenti su una PR)
1. Leggi tutto, capisci la preoccupazione di fondo (un nit sul naming può essere un dubbio sull'astrazione).
2. Decidi: fixa / push-back con ragioni / wontfix motivato / escala. Mai silent-resolve.
3. Implementa il fix con lo stesso rigore del codice fresh (test, tipi, conventional commit).
4. Rispondi sul thread (audit trail), poi risolvi. "fixed" da solo non basta.
5. Se il reviewer ha torto, dillo con rispetto e evidenza. Conviction over agreeableness.
