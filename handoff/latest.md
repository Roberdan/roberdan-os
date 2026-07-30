# Handoff — 2026-07-30

> Sostituisce l'handoff MirrorHR del 2026-07-13, conservato in git a **`a33c804`**. Se riprendi
> la card MirrorHR `260713-093430`, il dettaglio (T7 in pausa, base fidata `Development@cc2e04b`,
> ultima PR verificata #567) sta lì: `git show a33c804:handoff/latest.md`.

## In una riga

I due progetti sono **stabili e verificati** (`VirtualBPMFy27 v4.8.0`, `roberdan-os v2.21.0`,
CI verde su entrambi). Il prossimo passo è **una card sola**, su VirtualBPMFy27, e sta scritta
in `VirtualBPMFy27/docs/roadmap.md`.

## Cosa fare all'apertura della prossima sessione

1. Leggere `~/GitHub/VirtualBPMFy27/docs/roadmap.md` — è l'ordine di lavoro, non va ricostruito.
2. La card in corso `260727-185336` **va spezzata prima di continuare**: la sua acceptance è di
   1.300 caratteri con una dozzina di condizioni e due dipendenze, e la parte grossa è già
   consegnata in `v4.8.0` (crew dalla linea di riporto, etichette senza possessivo, denominatore
   sul prestato, loghi cliente). Isolare la condizione che manca davvero, farne una card sola,
   chiudere l'originale con l'evidenza di cosa è stato consegnato.
3. Poi il 1º blocco del roadmap: **i dati reali dentro il codice** (`260729-201500`,
   `260727-134514`, `260728-220212` — sono lo stesso problema visto da tre lati).
4. **Non aprire un secondo fronte**: `kb start` lo rifiuta, ed è voluto.

## Cosa è cambiato oggi nel modo di lavorare — leggere PRIMA di lavorare

Cinque freni, misurati prima di essere scritti. Il mattino del 2026-07-30 il board aveva 33 card
in attesa di Roberto, sette in `doing` di cui **quattro sullo stesso lavoro** aperte da sette
giorni, e **zero card in corso sul progetto principale**, che ne aveva diciannove in coda.

1. **Una card in corso per progetto.** `kb start` rifiuta il secondo fronte sullo stesso `repo:`.
   Esenzione esplicita: `RDA_KB_ALLOW_PARALLEL=1`.
2. **Un finding NON diventa una card.** Va in `docs/findings.md` del suo repo, con scritto quale
   condizione lo renderebbe lavoro. Solo Roberto lo promuove. *Questo ribalta di proposito il
   gate 2 del loop-protocol*: la lezione della cicatrice era "non dentro questa PR", ed era stata
   implementata come "fanne una card" — ed è così che il board è diventato una fabbrica.
3. **Le card in corso da oltre 72 ore vengono chiamate per nome** nel dashboard, col numero di
   commit sul loro ramo. Ha subito pescato una card ferma da 20 giorni.
4. **Una condizione verificabile per card.** `kb add` rifiuta un'acceptance con `;`, ` e `,
   ` and `, `1)`, `2)`. **Ratchet**: le card vecchie non si toccano, perché un gate rosso il
   giorno in cui nasce è un gate che viene aggirato. Esenzione: `RDA_KB_ALLOW_MULTI_CLAUSE=1`.
5. **`kb pending` mostra un progetto alla volta**, quello del cwd; `kb pending --tutti` apre tutto.
   Il conteggio totale **non** è ristretto dalla vista, ed è asserito.

Provati da `test/test-kb-diet.sh` — 13 asserzioni, ognuna nei **due sensi** (il caso rifiutato e
il caso legittimo che deve passare) — agganciato a `test/validate.sh`.

## Gate umani ancora aperti — solo Roberto

1. **Ticket a GitHub Support** per `roberdan-os`: testo pronto in
   `~/Desktop/TICKET-GITHUB-SUPPORT.md`. La storia è stata riscritta e verificata (0 occorrenze
   su `main` pubblico, 0 rami, 0 fork), ma i vecchi commit **restano serviti per codice** finché
   GitHub non fa pulizia. Verifica di completamento:
   `gh api repos/Roberdan/roberdan-os/commits/84b8c74` deve dare 404.
2. **`MirrorBuddy`** (pubblico, org FightTheStroke): 5 indirizzi aziendali distinti nella storia,
   uno dei quali sembra una persona reale che non è Roberto. In `docs/adr/0135-ios-release-pipeline.md`,
   `docs/claude/ios-release.md`, due documenti di compliance e `scripts/env-vault.sh`.
   Consigliato: sostituire il nome nell'albero attuale, **non** riscrivere la storia — sono
   documenti interni, non un dossier clienti.
3. **gbrain**: chiave `ZEROENTROPY_API_KEY` (darla o disattivarla) e ore di GPU per i cicli.

## Job che partono da soli

Spenti il 2026-07-30 perché si svegliavano per non fare niente, o per fare danno:
`rda-evolve` (creava 5 card vuote a ogni giro), `rda-factory` (coda vuota dal 2 luglio),
`rda-learn` (le cartelle su cui doveva lavorare non esistono). Riaccendere:
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<nome>.plist`.

`com.gbrain.autopilot` riconfigurato: sabato e domenica alle 01:00, **solo con il Mac alla
corrente**, massimo 6 ore (`~/.gbrain/autopilot-window.sh`). Prima era `KeepAlive`, cioè sempre —
ed è per questo che era stato lasciato mai avviato.

## Limiti dichiarati, non nascosti

- **`@thor` è sospeso** per decisione di Roberto finché non viene aggiornato. Ogni card chiusa il
  2026-07-30 porta scritto nell'evidenza che la verifica è di Claude e non di thor — perché
  `kb finish` stampa "verified by @thor" comunque (registrato in `docs/findings.md`).
- La batteria dei mutanti del bus è stata eseguita **per intero**: 32 catturati, **1 sopravvissuto**
  (`factory-drop`), registrato in `docs/findings.md` e deliberatamente non inseguito.
- La CI di `VirtualBPMFy27` è raggiungibile solo con `gh auth switch --user roberdan_microsoft`;
  con l'account `Roberdan` quel repo non si risolve nemmeno.
