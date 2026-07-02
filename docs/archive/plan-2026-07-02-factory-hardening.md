# Piano 2026-07-02 — hardening factory/kanban (analisi Fable → esecuzione)

Questo documento persiste l'analisi prodotta dal modello **Fable** a inizio sessione e il piano
di 10 azioni che ne è derivato, con lo stato di esecuzione di ciascuna — fino a qui esisteva solo
nella conversazione, non sul filesystem. Vedi anche [`docs/adversarial-judgment-2026-07-01.md`](adversarial-judgment-2026-07-01.md)
(due giudizi adversarial indipendenti successivi, che confermano/estendono questa analisi) e
[`handoff/latest.md`](../../handoff/latest.md) (narrativa di sessione).

## Input: analisi Fable (verbatim, inizio sessione)

> **Il finding che cambia tutto**: la run notturna della factory era già girata ed era fallita
> 4/4 (`exit 127`, claude/timeout non risolti sotto il PATH minimale di launchd), e
> `run_task()` spostava le task fallite in `done/` incondizionatamente — le card kanban
> `T-adversarial-judge`/`T-system-tests` dicevano "doing" mentendo sullo stato reale.
>
> **Coerenza architetturale**: KEEP = kanban gated (`kb.sh`), `test/validate.sh` come vero gate
> CI, privacy split, factory-come-idea (sostituto leggero di Convergio). FIX = due fonti di
> verità non sincronizzate (kanban doing/ vs factory queue/→done/), "resumable" falso sui
> fallimenti, contraddizione CLAUDE.md globale vs handoff sull'embedder, gate umano honor-system,
> card mosse a mano bypassando kb.sh, `--add-dir` default troppo ampio, sovrapposizione
> T-adversarial-judge↔analisi stessa, circolarità T-system-tests (la factory testa la factory).
>
> **Card per card**: FtS-ingest mal scoping (background per un job da 10 min), G5-always-on
> gated correttamente ma senza threat model, T-tests-factory-kb la card più preziosa del board,
> T-adversarial-judge/T-system-tests con stato falso.
>
> **Rischi**: patch gbrain bge-m3 fragile (riapplicazione manuale), factory failure = silenzio,
> success detection debole (exit 0 non prova il DoD), composizione rischi FtS+G5 non tracciata.

## Piano — 10 azioni (A1-A10) e stato di esecuzione

| # | Azione | Modello | Gate | Stato |
|---|---|---|---|---|
| A1 | Riparare semantica fallimento factory (mai più `done/` su task fallita) + risolvere binari `claude`/`timeout` sotto PATH minimale + scope `--add-dir` | sonnet | autonomo | ✅ fatto, verificato end-to-end sotto `env -i` (successo→`done/`, 1° fallimento→retry, 2°→`failed/` con `escalate:true`). Commit `b7f1cd1`. |
| A2 | Test suite reale factory+kb (`test/test-factory-kb.sh`), wired in `validate.sh` | sonnet | supervisionato, poi `kb start/finish` gated | ✅ fatto; trovati e fixati 2 bug pre-esistenti in `kb.sh` (`set -e`/`pipefail` su `ls` di path mancanti). Commit `f7526e9`, poi rafforzato dopo bocciatura di @thor (billing-guard/primer da grep a runtime assertion) in `06efad7`. Card chiusa da @thor: `kb finish T-tests-factory-kb`. |
| A3 | Sanare stato kanban (FtS-ingest root-cause, annotare le 2 card doing false, `kb block`) | sonnet | autonomo | ✅ fatto. Commit `3c6710e`. |
| A4 | Sync factory→kanban (`card:` field, `factory_result:` sulla card) | sonnet | autonomo | ✅ fatto, incorpora anche il finding "exit 0 ≠ DoD soddisfatto" dai giudizi adversarial. Commit `f0cb68c`. |
| A5 | Consolidare `T-adversarial-judge` con l'analisi Fable (non rilanciare alla cieca) | opus | autonomo (advisory) | ✅ fatto — due pass indipendenti (`docs/adversarial-judgment-2026-07-01.md`, commit `22ef50f`, poi corretto per leak privacy). Card chiusa da @thor. |
| A6 | Ri-enqueue selettivo notturno: solo `usage-guide` + `system-tests` | sonnet | autonomo | ✅ fatto diversamente dal previsto: `usage-guide` scritta direttamente (era lavoro meccanico, non serviva la factory), `system-tests` eseguita via factory reale dopo il fix A1 (commit `4fc5537`, report `docs/system-test-report-2026-07-02.md`). Entrambe le card chiuse da @thor. |
| A7 | FtS-ingest in foreground supervisionato (non più background/TCC) | sonnet | **gate umano**: kickoff con Roberto presente | ⚠️ **bloccato correttamente**: la stima "~214 doc" della card non corrisponde a nessuna cartella reale in `~/Documents` (FTS srl: 381 file legali; FightTheStroke Foundation: 308 file marketing) — fermato prima di ingestare dati confidenziali sul path sbagliato. Card marcata `blocked` con `kb block`, in attesa di Roberto. |
| A8 | Threat model @luca su G5-always-on PRIMA della decisione | opus | autonomo (advisory) | ✅ fatto: `docs/adr/adr-always-on-security.md` (commit `10d1363`). Trovato: `workspace:` non è un confine dati enforceable in gbrain; raccomandata source isolata `vault-fts`. |
| A9 | Durabilità patch gbrain bge-m3 + riconciliazione CLAUDE.md globale | sonnet | edit CLAUDE.md globale = **gate umano** | ✅ fatto: `bin/check-embedder.sh` (commit `b1f868f`), verificato live che l'embedder reale è `ollama:bge-m3`; CLAUDE.md globale corretto con approvazione esplicita di Roberto. |
| A10 | Chiusura loop: learn capture, handoff, validate, commit finale | sonnet | autonomo | ✅ fatto: scar catturato in `learn/capture.sh`, `handoff/latest.md` aggiornato, `test/validate.sh` verde end-to-end. |

## Deviazione non pianificata: incidente privacy

Durante l'esecuzione di A5, un subagente ha scritto nomi client reali in un file poi committato
e pushato prima che `leak-check.sh` lo intercettasse (in un run successivo, non al commit). Non
era nel piano Fable — reattivo per necessità. Remediato (storia locale e remota corrette) e
chiuso strutturalmente con `hooks/pre-commit` (commit `47de8ad`): il gate che avrebbe dovuto
prevenirlo esisteva già ma non era enforceable a livello di commit, solo a livello di CI
manuale. Questo non sostituisce l'esecuzione del piano A1-A10 — è successo *dentro* A5, ed è
stato risolto prima di proseguire con A6-A10.

## Esito

10/10 azioni del piano eseguite (una, A7, correttamente bloccata su un gate umano invece che
completata — bloccare su dati non verificabili è l'esito corretto, non un mancato completamento).
Board kanban: 0 card `doing`, 4 card chiuse da @thor con evidenza in questa sessione, 2 card
`todo` in attesa di decisione di Roberto (`FtS-ingest` sullo scope, `G5-always-on` sulla scelta
architetturale — materiale decisionale pronto in entrambi i casi).
