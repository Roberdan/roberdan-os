# Handoff — 2026-07-30 (sera)

> Sostituisce l'handoff MirrorHR del 2026-07-13, conservato in git a **`a33c804`**. Se riprendi
> la card MirrorHR `260713-093430`, il dettaglio (T7 in pausa, base fidata `Development@cc2e04b`,
> ultima PR verificata #567) sta lì: `git show a33c804:handoff/latest.md`.

## Le quattro decisioni del 31 luglio — Roberto ha risposto

1. **gbrain, reindicizzare**: **SÌ → FATTO**, card `260730-102956` **chiusa** il 31/7.
   **13 sorgenti su 13**, dalle 10:00 alle 17:02 locali, **zero fallimenti**. Il `doctor` non
   ha **nessun `[FAIL]`**: `cycle_freshness` è sceso a `[WARN]` e `sync_freshness`, che era
   rosso, è `[OK]`. Prova indipendente dal log: `last_full_cycle_at` scritto nel DB per tutte
   e 13 (`psql -d gbrain_local -tAc "select id, config->>'last_full_cycle_at' from sources"`).
   Evidenza: `~/.roberdan-os/evidence/260730-102956-cicli.txt`.
   Tre cose da sapere: le sorgenti erano **13, non 12** come diceva il titolo; il `[WARN]`
   `cycle_freshness` **si riaccende da solo** dopo poche ore (la soglia è bassa — per tenerlo
   spento serve `gbrain autopilot`, oggi limitato al weekend); il runner riutilizzabile è
   `~/.roberdan-os/jobs/gbrain-cycles/run.sh` e **salta ciò che è già fatto**.
2. **MirrorHR accelerometro/EDA** (`260709-114214`): **NO** → archiviata in `done/` come annullata.
3. **MirrorHR P1 Safety Recovery** (`260713-093430`): **rimuovere** → archiviata. I due difetti
   safety-critical restano chiusi e verificati; i gate di rilascio T9/T9b **non sono più tracciati
   da nessuna card** — scritto sulla card e in `docs/findings.md` #12.
4. **VirtualBPMFy27** (`260729-073336`): **un'altra sessione ci sta già lavorando**. Commit
   `a0f012c` del 31/7 09:47 sul branch `card/260729-073336`: adattatore MCP, schema, 395 righe
   di test, ADR 0015 — 1028 righe. Roberto: *"lascia fare a quella sessione"*. **Non entrare in
   quel repo.**

## Aggiornamento 31 luglio (mattina) — quattro cose fatte, nessuna nuova decisione

- **`kanban/.coda-*` ora è ignorato** nel repo pubblico: lo scatto della coda elencava id di card
  del board privato ed era untracked ma committabile. `git check-ignore -v` lo conferma.
- **Il board era rimasto solo su disco**: 21 file (sei card chiuse il 30/7, `precheck.sh`) non
  erano nel repo card privato. Committati e pushati (`6f62275` → `roberdan-os-cards`). Il
  `git add -A` che l'ha fatto ha anche tracciato due volte `precheck.sh` — corretto subito,
  ora escluso in `kanban/.gitignore`.
- **I due thread bus aperti sono chiusi** (`260728-164449`, `260729-150321`, come `@architect`;
  il log resta leggibile). Contenevano tre rilievi che vivevano solo lì: uno era già riparato in
  `kanban/kb.sh:159-176`, gli altri due sono ora **findings #9 e #10**.
- **Finding #11**: la quarta decisione (`260729-073336`, VirtualBPM) non compare in `kb pending`
  perché è in `doing`. La tabella qui sotto resta valida; la lista di `kb pending` no.
- CI di `roberdan-os` verde **oggi** (run `30611347980`, commit `b660f9f`). Quella di
  VirtualBPMFy27 è verde di ieri sera, non riverificata.

## In una riga

Tutto stabile e verificato — **`roberdan-os v2.26.0`**, **`VirtualBPMFy27 v4.10.2`**, CI verde
su entrambi, board a **zero card eseguibili**. Le tre rimaste aspettano una decisione di
Roberto, non del lavoro.

## Cosa fare all'apertura della prossima sessione

**Probabilmente niente.** Non c'è una coda da smaltire: `kb next` risponde `LISTA FINITA` su
entrambi i progetti, e nessuna sessione ha aggiunto card. Se Roberto non chiede altro, la cosa
utile è **chiedergli una delle tre decisioni qui sotto**, non cercare lavoro.

## Le tre decisioni che aspettano lui — e nient'altro

| Card | La domanda |
|---|---|
| `260730-102956` (gbrain) | reindicizzare 12 sorgenti costa **ore di GPU** sul Mac. Vale? |
| `260709-114214` (MirrorHR) | segnali accelerometro/EDA da Apple Watch: decisione di **prodotto e hardware**, marcata gate umano |
| `260713-093430` (MirrorHR) | i due difetti safety-critical sono **chiusi** (verificato: 25 chiavi arabe presenti, via VoiceOver sul Watch presente). Restano gate non-codice: fatturazione GitHub, **due notti reali** di monitoraggio, approvazione umana EN/IT/AR |

Più una su VirtualBPM (`260729-073336`): *vuoi che Copilot CLI legga i dati di VirtualBPM
attraverso gli undici strumenti tipati?*

## Le regole nuove di oggi — leggere PRIMA di lavorare

Il mattino del 2026-07-30 il board aveva **33 card in attesa di Roberto**, sette in `doing` di
cui **quattro sullo stesso lavoro**, e **zero card in corso sul progetto principale**. Sei freni,
tutti con un test che li verifica **nei due sensi**:

1. **Una card in corso per progetto** — `kb start` rifiuta il secondo fronte (`RDA_KB_ALLOW_PARALLEL=1` per l'eccezione)
2. **Un finding NON diventa una card** — va in `docs/findings.md`, solo Roberto lo promuove. *Ribalta di proposito il gate 2 del loop-protocol.*
3. **Card ferme da oltre 72 ore chiamate per nome** nel dashboard, col numero di commit
4. **Una condizione verificabile per card** — `kb add` rifiuta `;`, ` e `, `1)`, `2)`. Ratchet: le vecchie non si toccano
5. **`kb pending` mostra un progetto alla volta** (`--tutti` apre tutto). Il conteggio non è ristretto dalla vista
6. **Il precheck** (`kanban/precheck.sh`) — `kb start` chiede: *serve ancora? la fa già un'altra? è già stata fatta?* Non blocca, e **su una card pulita tace**

E il gate `todo → doing` è **sulla LISTA, non sulla card**: `kb queue` fotografa all'inizio
sessione, `kb next` percorre senza chiedere. **Ciò che nasce dopo lo scatto non parte** — è
l'unica proprietà che lo rende un gate spostato e non rimosso.

## Gate umani ancora aperti

1. **Ticket a GitHub Support** per `roberdan-os`: testo pronto in `~/Desktop/TICKET-GITHUB-SUPPORT.md`.
   La storia è stata riscritta e verificata, ma i vecchi commit **restano serviti per codice**
   finché GitHub non fa pulizia. Verifica: `gh api repos/Roberdan/roberdan-os/commits/84b8c74` → 404.
2. **`MirrorBuddy`** (pubblico): 5 indirizzi aziendali nella storia, uno di una persona che non
   è Roberto. Consigliato: sostituire il nome nell'albero attuale, **non** riscrivere la storia.
3. **gbrain**: chiave `ZEROENTROPY_API_KEY` (81 fallimenti del reranker in 7 giorni).

## Limiti dichiarati, non nascosti

- **`@thor` è sospeso** per decisione di Roberto. Ogni card chiusa oggi dice nell'evidenza che
  la verifica è di Claude, non di thor — perché `kb finish` stampa "verified by @thor" comunque
  (registrato in `docs/findings.md` come difetto).
- **Due volte oggi ho dichiarato qualcosa che non reggeva**, e in entrambi i casi mi ha
  contraddetto qualcosa di meccanico, non io: (a) una card chiusa citando un test che provava
  un'altra cosa — trovato dall'altra sessione, corretto per mutazione; (b) *"l'errore non può
  succedere"* su un guasto comparso un'ora dopo — corretto sulla card e nei findings. **Entrambe
  sono scritte, non nascoste.** È il motivo per cui i gate valgono più delle rassicurazioni.
- Evidenza delle chiusure su file in `~/.roberdan-os/evidence/`.
- La CI di `VirtualBPMFy27` si legge solo con l'account `roberdan_microsoft`; quella di
  `roberdan-os` con `Roberdan`. **Non usare `gh auth switch`**: le due sessioni se lo strappano.
  Usa `GH_CONFIG_DIR=~/.roberdan-os/gh-roberdan` (registrato nei findings).

## Job che partono da soli

Spenti oggi perché si svegliavano per non fare niente, o per fare danno: `rda-evolve` (creava
5 card vuote a ogni giro), `rda-factory` (coda vuota dal 2 luglio), `rda-learn` (le cartelle non
esistono). Riaccendere: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<nome>.plist`.

`com.gbrain.autopilot` riconfigurato: **sabato e domenica alle 01:00, solo con il Mac alla
corrente, massimo 6 ore**. Prima era `KeepAlive`, cioè sempre — ed è per questo che era stato
lasciato mai avviato.

Nel runtime di Claude Code sono stati messi i tetti che non erano mai stati impostati:
**profondità di delega a 1** (era 3: un agente poteva creare agenti che creavano agenti), 40
agenti per sessione, 8 in parallelo, 50 ricerche web. Valgono dalla sessione successiva a quella
in cui sono stati scritti.
