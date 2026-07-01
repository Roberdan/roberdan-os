# Session Goal Ledger — durable, trackable, auditable

Registro durevole dei goal (sopravvive a chiusura Mac / reset sessione; git-tracked = resumabile
ovunque). **Regola:** ogni goal ha `status` + `evidence`. A inizio sessione, leggi questo file
prima di agire. A fine fase, aggiorna la riga. `@thor` (done-gate) è l'unico che mette `verified`.

Status: `todo` · `wip` · `done` (fatto) · `verified` (verificato empiricamente) · `dropped`

## Sessione 2026-06-30 → 07-01 (roberdan-os hardening)

| # | Goal | Status | Evidence |
|---|---|---|---|
| 1 | Chi sei / sei roberdan-os | verified | risposta data |
| 2 | Aggiornare memoria durevole senza bruciare token | verified | ciclo dimostrato |
| 3 | Ciclo salva→recupera dimostrato | verified | demo eseguita |
| 4 | roberdan-os: loop, auto-update, apprendi ogni interazione, DI DEFAULT | verified | meta-loop attivo (launchd) + skill installati in ~/.claude/skills + RDA_LEARN=1 |
| 5 | Memoria cross-platform nel vault (non silo Claude) | verified | 19+3 note migrate, indicizzate bge-m3 |
| 6 | Ontologia auto-aggiornante? | verified | decisa NO (socrates); 1 type + igiene gated |
| 7 | Finisci tutto + cancella backup + attiva + verifica cron | verified | launchd caricati, backup rm, cron ok (bge-m3 default) |
| 8 | 3 skill (premortem/focus-group/problem-validation) auto-usati | verified | committati + INSTALLATI ~/.claude/skills (system-reminder li elenca) |
| 9 | Review completa + paper scientifico | verified | 2 audit → 4 difetti corretti; paper IT+EN |
| 10 | Re-init bge-m3 locale + PDF LaTeX | verified | patch gbrain f7376b11; ollama ps GPU; PDF IT+EN |
| 11 | Avvisami re-embed completo + test recall IT | verified | 6 NULL; IT MRR 0.82 (deployed) |
| 12 | Paper: exec summary + gbrain/gstack + skill + §9 quantitativa + casi-studio | done | commit paper-en; eval bge-m3 vs nomic (IT MRR 1.0 vs 0.41) |
| 13 | **Tradurre TUTTO il sistema in inglese** (readme/doc/agenti/skill) | **todo** | delega a Sonnet — NON ancora fatto |
| 14 | **Checklist durevole/auditabile dei goal** | **wip** | QUESTO file |
| 15 | **Decidere: Convergio separato serve ancora?** | **todo** | analisi + verifica stato convergio |
| 16 | **Continuità cloud (chiudere il Mac senza perdere nulla)** | **todo** | vincolo: engine locali (gbrain/ollama) offline a Mac spento; vedi nota |

## Note aperte
- **#13 traduzione:** repo per lo più in italiano (behavior 3, agents 8, skills 8, protocolli). Delega a Sonnet in parallelo. Escludere: `private/`, i 2 paper (hanno già versione EN), `platforms/` (rigenerati).
- **#16 cloud:** lo STATO (questo ledger + git committato/pushato) è resumabile ovunque. Ma gbrain/ollama/vault sono LOCALI: un agente cloud può continuare pianificazione/scrittura, non interrogare la memoria locale finché il Mac è spento.
