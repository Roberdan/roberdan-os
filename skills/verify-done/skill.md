---
name: verify-done
description: Evidence-first done-gate. Refuses to mark work complete without concrete artifacts (commit SHA, PR link, file path, test output) verified empirically. The cardinal principle.
providers: [claude, copilot, codex]
---

# verify-done — il done-gate evidence-first

**Done non è "dovrebbe funzionare".** È il principio cardine di Roberto. Usa questa
skill prima di dichiarare completo qualsiasi task.

## Le 3 condizioni obbligatorie
1. **Evidence** — artefatti concreti allegati: commit SHA, PR link, file path, output test.
2. **Verificato empiricamente** — testato davvero, non stimato. Mostra l'output, non la stima.
3. **Sistemi sincronizzati** — vault (Obsidian) + Convergio twin plan + docs in-repo allineati.

## Checklist (NON-NEGOTIABLE)
- [ ] 0 errori di compilazione
- [ ] 0 warnings (trattati come errori)
- [ ] 0 technical debt lasciato aperto
- [ ] Coverage ≥ 80% su business logic, 100% sui critical path
- [ ] Test eseguiti — **output mostrato**, non descritto
- [ ] Docs aggiornate se hai cambiato API/interfacce
- [ ] Commit per ogni fase completata
- [ ] CI verde (o wontfix esplicito documentato)

## Verifica per tipo di claim
| Claim | Evidenza richiesta |
|---|---|
| "Compila" | output di build |
| "I test passano" | output dei test |
| "Funziona" | esecuzione dimostrata |
| "È sicuro" | security scan |
| "È deployato" | deploy confermato |

**Claims without evidence are rejected.** In Convergio: solo `thor` setta `done`
(gli executor propongono `submitted`). Vedi [`agents/thor.md`](../../agents/thor.md).

## Se hai sbagliato
Riconosci, correggi, non giustificare:
`Fatto — era un errore mio. Ho corretto X. Commit abc123.`
