# Findings — cose vere che nessuno ha chiesto

Esiste perché il 30 luglio 2026 c'erano **33 card in attesa dell'approvazione di Roberto**, quasi
tutte nate come rilievi di revisione, e il board non sapeva distinguerle dal lavoro che aveva
chiesto lui. Un rilievo **non diventa una card**: solo Roberto promuove.

**La regola, decisa dal twin il 2 agosto 2026** (la prima versione proposta era "si ripara entro
pochi giorni o si cancella", e il twin l'ha rifiutata: *"mi ridà una coda da smaltire con una
scadenza addosso — è il 30 luglio con un altro nome"*):

> **Tetto duro: 10 rilievi aperti.** Chi scrive l'undicesimo ne cancella uno prima, con una riga
> di motivo. Ogni rilievo nasce con la sua condizione di promozione e la sua data. Passati **14
> giorni** senza che la condizione sia scattata, si cancella. **Promuovere richiede Roberto;
> cancellare non richiede nessuno.** Git conserva tutto.

Il difetto non era che i rilievi vivessero troppo: era che **solo Roberto poteva toglierli**. Il
tetto morde nel momento in cui uno scrive, non in un giro di pulizia che nessuno farà.

Un rilievo che ha bisogno di quaranta righe per spiegarsi non è un rilievo: o è una card, o non
esiste. Il racconto lungo dei 25 rilievi precedenti sta in git, fino a `ac56a98`.

---

## Aperti — 1 su 10

| # | Cosa | Prova |
|---|---|---|
| 26 | `test/validate.sh` non e' ermetico rispetto all'ambiente ereditato: se gira dentro una sessione @thor annidata, `RDA_IN_THOR_VERIFY` (recursion-guard) e `RDA_KANBAN` (registro reale al posto della fixture) lo fanno fallire su codice sano | Il 3 agosto il gate interno di `kb finish` ha dato `test-goal-gate` rosso su `main`, dove lo stesso test e' verde da solo e la suite completa e' ALL GREEN in due run indipendenti. `env -u RDA_IN_THOR_VERIFY -u RDA_KANBAN bash test/validate.sh` -> ALL GREEN. **Un falso rosso e' peggio di nessun test: erode la fiducia in tutti i gate.** `validate.sh` dovrebbe ripulire da se' le variabili che governano il suo stesso comportamento |

Il 2 agosto 2026 la lista e' passata da 19 rilievi aperti a zero: 13 chiusi da una
decisione, 6 riparati con la loro card e la loro prova di mutazione. Il 26 e' nato dopo.
Restano poi i due rinviati qui sotto, che per la regola non contano nel tetto.

**Pagato il 3 agosto, non rinviato:** il gate @thor sulla card `260802-212646` aveva trovato che
l'asse "riga di commento" di `test-kb-repo-path-agree` era un paper-pass (interrogava `"#"`, che
nessuna riga del registro ha mai come basename: verde per costruzione, non per merito). Riparato
dalla card `260803-043240`, PR #39, provato nelle due direzioni. Terzo caso in due giorni della
stessa famiglia — un test che si autoassolve — e ogni volta scoperto solo rifacendo la mutazione.
Una seconda imprecisione della stessa verifica, "tre suite fanno grep sulla frase canonica di
`verify_card`" (ne fa grep solo `test-kb-autothor-board`), era narrazione, non difetto: corretta
qui e basta.

Il posto e' vuoto e va tenuto vuoto: il tetto e' 10, e chi scrive l'undicesimo ne cancella uno.

## Rinviati con motivo scritto — non contano nel tetto

| # | Cosa | Perché non ora |
|---|---|---|
| 13 | `bin/sync.sh` genera ancora i file per Codex e Hermes, che non si usano più | Deciso il 31 lug: si toglie la prossima volta che si mette mano a `sync.sh`. Nessuno ci sta mettendo mano, e quel file genera i wrapper delle piattaforme vere: zero valore, rischio non zero |
| 25b | `hooks/main-guard.sh` non è installato: bloccherebbe le scritture sul ramo principale (tranne `.md`, `docs/`, `.claude/`, `.gitignore`) | **Deciso dal twin: NO.** Il canone permette il commit diretto quando si lavora da soli in sequenza, e con la deroga sui `.md` non avrebbe intercettato nemmeno i commit del 2 agosto. Costo certo, beneficio ipotetico. Resta disponibile per quando siamo in due |

---

## Chiusi il 2 agosto 2026 — il racconto lungo è in git fino a `ac56a98`

**Riparati con card e prova di mutazione:** 1, 8, 11, 14, 15, 16, più — nello stesso giorno — il
gate `tool-coverage` che diceva verde su 7 skill del canone irraggiungibili, il timeout dell'hook
Orca sui tre eventi che bloccano il turno, e la diet di `rules/best-practices.md`.

- **#3 — i due account GitHub che si rubavano il posto.** `bin/gh-shim.sh`, installato come
  `~/.local/bin/gh` (nel PATH viene prima di Homebrew): **si digita `gh` normale** e l'account si
  sceglie dal proprietario del remote, con una cartella di configurazione per account. Niente più
  stato globale, quindi niente da contendere: due sessioni su due repo diversi usano due account
  nello stesso istante. `-R proprietario/nome` vince sul cwd. **Fallisce APERTO** in ogni caso
  ignoto — fuori da un repo, remote non GitHub, proprietario non in mappa, cartella non pronta,
  interruttore, `GH_CONFIG_DIR` o `GH_TOKEN` già scelti dal chiamante: lancia il `gh` vero
  invariato. Verificato dal vivo: in `roberdan-os` risponde `Roberdan` mentre l'account globale
  attivo era `roberdan_microsoft`, e da dentro un repo Microsoft `gh pr list -R Roberdan/roberdan-os`
  trova la PR 35 di un repo privato che prima rispondeva *"Repository not found"*.
  15 asserzioni (10 sul fallire aperto), mutazione 5 su 5 rossa.

- **#20 — il gate rifiutava verifiche RIUSCITE.** Due cause: la lettura pretendeva
  `VERDICT: PASS — ` esatto e il grassetto di @thor non combaciava; e @thor poteva finire il
  turno scrivendo *"aspetto l'esito del test completo"* senza dare il verdetto. Entrambe si
  risolvevano rilanciando identico — la lezione peggiore. Ora la lettura tollera la forma
  (grassetto, trattino semplice, nessun separatore) e resta inflessibile sul contenuto; i due
  fallimenti hanno messaggi diversi; il prompt vieta a @thor di rinviare. **Difetto trovato
  dentro la riparazione:** la prima versione del test riscriveva la logica a mano, e 3 mutanti su
  5 passavano verdi perché il test non toccava il codice vero — risolto estraendo
  `thor_read_verdict()` e facendola chiamare dal test. 16 asserzioni, mutazione 5 su 5 rossa.
- **#23 — il lucchetto orfano che faceva uscire rosso un test innocente.** Ora contiene il PID di
  chi lo tiene: proprietario morto = si riusa, vivo = il rifiuto è vero. La logica sta in
  `test/lib-lock.sh`, un file solo per i due chiamanti. 10 asserzioni, 4 delle quali verificano
  che un lucchetto **vivo** venga rispettato. Mutazione 4 su 4 rossa.

- **#2 — `install-git-hooks.sh` incideva il percorso del worktree.** Ora `ROOT` si chiede a git
  (`--git-common-dir`) invece di dedurlo dalla posizione dello script: dal worktree risolve al
  checkout principale, che e' quello che sopravvive. Il salto resta **condizionato**: se laggiu'
  non c'e' questo repo si resta dov'eravamo. Provato su cloni usa-e-getta, nei due sensi.
  Riparato anche un difetto trovato dal test nella stessa funzione: fuori da un repo lo script
  moriva con l'errore grezzo di git ed exit 128. 5 asserzioni, mutazione 3 su 3 rossa.
- **#9 — una PR si mergeva anche col controllo rosso.** Protezione del ramo accesa il 2 agosto
  nella versione stretta decisa dal twin: i controlli devono passare, **gli admin sono esclusi e
  il push diretto resta libero**, cosi' Roberto lavora come prima. Force-push e cancellazione del
  ramo bloccati.
- **#24 — `install-hooks.sh` diceva "idempotent" e avrebbe raddoppiato 10 controlli.** Ora
  `norm()` riconosce `$HOME`, la tilde e il `bash` iniziale come la stessa cosa, e **non**
  appiattisce redirezioni, argomenti o script diversi. 12 asserzioni, 5 delle quali verificano
  proprio che non appiattisca. Mutazione 5 su 5 rossa.
  - *Due falsi verdi trovati nel test mentre lo scrivevo: l'estrazione della funzione prendeva
    troppo codice, l'import esplodeva, e l'helper leggeva l'errore come "sono diversi" — cinque
    asserzioni passavano verdi per un import rotto. Seconda volta in un giorno che scrivo un test
    che si autoassolve.*

**Chiusi da una decisione, non da una riparazione:**

- **#4** Claude Code aveva già risolto a monte due problemi del 30 luglio. I tetti al runtime che
  il twin voleva accendere **erano già accesi** (profondità di spawn 1, 8 agenti in parallelo, 40
  per sessione, 50 ricerche web). Il resto era notizia, non difetto.
- **#5 #6 #7** riguardano gbrain, non roberdan-os. Sistema diverso, e #5 è probabilmente superato
  dalla riparazione delle skill del 2 agosto.
- **#10** due test instabili in CI: altro repo.
- **#12** i gate di rilascio di MirrorHR. **Decisione del twin: diventano una riga bloccante nella
  procedura di rilascio di MirrorHR, non una card e non una riga qui.** Parole sue: *"al momento
  del rilascio leggo la procedura di rilascio, non i findings di un altro repo. E non una card,
  perché due notti reali di monitoraggio e l'approvazione umana dei testi arabi sono cose che un
  agente in coda non può fare e potrebbe fingere di aver fatto."*
- **#17** due skill di gstack con lo stesso nome: già mitigato negli override, il codice non è
  nostro, un loro aggiornamento lo rifà. Non esiste una riparazione che possa finire.
- **#18** due cartelle senza intestazione che non si caricavano mai. **Riparate cancellandole**
  (`dev-cleanup`, `roberto-mode`): una copia stantia che si chiama `roberto-mode` accanto al
  canone vero è peggio dell'assenza.
- **#19** `engineering-reference` invocata zero volte dal 14 luglio. **La misura non misura quello
  che dice**: il contatore conta le invocazioni esplicite, non i caricamenti automatici. Il test
  giusto è una violazione, non un contatore. Se un giorno un lavoro sbaglia una regola che vive
  solo lì, si riportano in `best-practices.md` **le poche righe che cambiano una decisione**, non
  tutto il file.
- **#21** l'hook di Orca a 10 secondi su `Stop`: il rilievo stesso concludeva "non toccare"
  (2 timeout su 458 esecuzioni). Un rilievo che conclude "non toccare" non è un rilievo aperto.
- **#22** i rifiuti della modalità auto sui comandi composti con `cd`: era un'ipotesi, non un
  difetto misurato.
- **#25** la prima versione diceva "due programmi non installati, vanno installati". Aperti i
  file, è falso in tutti e due i casi: `post-task-sync` è **spento apposta** (parte solo con
  `RDA_AUTOSYNC=1`) e **non tocca il vault**, lo dichiara lui stesso. Il difetto vero era la frase
  che prometteva il contrario nella descrizione della skill `sync` — **corretta il 2 agosto**.

---

## La cosa scomoda, dal twin, 2 agosto 2026

> Su 25 rilievi, **24 riguardano gli attrezzi** — roberdan-os, gbrain, gli hook, le skill, il
> kanban. **Uno solo riguarda un prodotto che serve a qualcuno**: i gate di rilascio di MirrorHR,
> per bambini con ictus. Ed è esattamente quello che ho tolto dal tracciamento. La macchina è
> diventata il cliente di sé stessa. La domanda vera non è cosa faccio dei rilievi aperti: è
> perché nessuno di loro parla dei clienti veri, né di mio figlio.

*(La versione originale del twin faceva quattro nomi propri. Il controllo privacy ha rifiutato il
commit — correttamente: quei nomi vivono solo in `~/.roberdan-os/private/`, mai in git. Il gate ha
funzionato su una frase che stavo scrivendo io.)*

_Aggiornato: 2026-08-03._

---

## Rilievi del 17 agosto 2026 (durante `/gstack-upgrade`)

- **#26 — `gstack-update-check --force` ha taciuto mentre c'era un aggiornamento.** Il controllo
  non ha stampato nulla (stdout+stderr catturati) con il repo `~/.claude/skills/gstack` 2 commit
  indietro e VERSION 1.66.1.0 contro 1.67.1.0 su `origin/main`. Se non avessi confrontato a mano
  con `git rev-list HEAD..origin/main`, la sessione si sarebbe chiusa con "sei già aggiornato" —
  un falso done prodotto dal *silenzio* di uno strumento di terze parti. Causa non distinguibile
  con i dati raccolti: cache `~/.gstack/last-update-check` stantia oppure errore di rete
  inghiottito. *Condizione che lo renderebbe una card:* se si ripete a cache pulita — allora
  Roberto non viene mai avvisato degli aggiornamenti e il canale va sostituito con un confronto
  git diretto.

- **#27 — il watcher `evolve/watch.sh` ha saltato la corsa di sabato 15 agosto, in silenzio.**
  Le card `kanban/todo/260808-*.md` erano ferme all'8 agosto (`stat` sui file); copilot e warp
  *erano* cambiati nel frattempo (verificato: la corsa manuale di oggi ha coalizzato entrambi).
  Il job launchd `com.roberdan.rda-evolve` è caricato e schedulato sabato 02:00, ma la corsa
  mancata non ha lasciato traccia: `StandardOutPath=/tmp/rda-evolve.log` e `/tmp` si svuota al
  riavvio (boot: dom 16 agosto 16:43). *Condizione che lo renderebbe una card:* un secondo sabato
  saltato — allora il log va fuori da `/tmp` e serve un rilevatore di "ultima corsa più vecchia
  di N giorni", perché oggi un watcher morto è indistinguibile da un watcher senza novità.

- **#28 — la fonte `claude-code` del watcher è irraggiungibile e viene saltata senza allarme.**
  `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` risponde **429**
  (rate limit) da questa macchina, ripetutamente; `watch.sh` stampa `claude-code unreachable,
  skip` e prosegue con exit 0. L'API GitHub sullo stesso file risponde 200
  (`api.github.com/repos/anthropics/claude-code/contents/CHANGELOG.md`). È la fonte **più
  importante delle tre** ed è l'unica cieca. *Condizione che lo renderebbe una card:* il 429
  persiste su una corsa schedulata — allora la fonte va spostata sull'endpoint API e il "skip"
  deve diventare visibile a Roberto, non solo una riga di log.

- **#29 — `docs/findings.md` è invisibile a gbrain, e il sync lo dichiara verde lo stesso.**
  Durante `/sync-gbrain` del 17 agosto: `Deleted un-syncable page: docs/findings`, senza dire
  perché. Verificato in tre modi dopo il sync: `gbrain get docs/findings` → `page_not_found`;
  ricerca sul contenuto **nuovo** → niente; ricerca sul contenuto **vecchio** ("la macchina è
  diventata il cliente di sé stessa", nel file dal 2 agosto) → niente. Il file è tracciato
  (`git ls-files docs/` lo elenca) e gli altri documenti sotto `docs/` sono indicizzati
  regolarmente (`docs/privacy-leak-check`, `docs/adr/0001-self-improving`,
  `docs/investigations/2026-07-28-gbrain-bash-code-graph`). Tre run di sync successive, tutte
  `OK code synced (page_count=210)`. **Causa non trovata.** È il registro dei rilievi aperti — il
  posto che il loop-protocol indica come destinazione di tutto ciò che si scopre lavorando — ed è
  l'unico documento del repo che una domanda semantica non può raggiungere. *Condizione che lo
  renderebbe una card:* subito, se si conferma che vale anche da un'altra macchina — un registro
  che nessun agente può trovare non è un registro.
  **Cosa ho escluso** (17 agosto, sul sorgente di gbrain 0.43.0.0): non è il classificatore —
  `unsyncableReason("docs/findings.md")` restituisce `null` sia con strategia `markdown` sia con
  `auto` (provato con `bun -e` su `src/core/sync.ts`); non è la lista dei metafile
  (`SYNC_SKIP_FILES` = schema/index/log/README/RESOLVER — e infatti `README` risulta
  correttamente assente); non è l'assenza dal remoto (`git cat-file -e origin/main:docs/findings.md`
  esiste, esattamente come `docs/privacy-leak-check.md` che invece è indicizzato); non è
  l'embedder (il problema resta con ollama acceso e round-trip verificato). Il meccanismo è il
  ciclo di pulizia del sync, che cancella le pagine il cui file non ritrova nella camminata:
  **perché quel file non venga camminato resta ignoto.**

- **#30 — l'embedder era spento e tutto continuava a dire OK.** `ollama` non era in esecuzione
  (`curl localhost:11434` → connection refused), quindi `gbrain put` falliva con
  `[embed(ollama:bge-m3)] Failed after 3 attempts` e il round-trip scrivi-e-ritrova era rotto.
  Nonostante questo `gstack-gbrain-sync` chiudeva **`3 ok, 0 error, 0 skipped`** e il preview
  citava l'arretrato (`~14,3 M caratteri pending gbrain embed --stale`) come una riga informativa,
  non come un guasto. Risolto avviando il server; round-trip riverificato subito dopo. Resta
  l'arretrato di 14,3 M caratteri mai incorporati: tutto quello scritto mentre l'embedder era giù
  è nel database ma non è cercabile. *Condizione che lo renderebbe una card:* se l'embedder si
  rispegne senza che nulla lo dica — allora serve che il sync fallisca, non che riporti verde.
  **CORREZIONE, 18 agosto: l'arretrato non esiste.** Avevo letto "~14,3 M caratteri pending
  `gbrain embed --stale`" come contenuto perso e stavo per programmare un recupero notturno.
  Misurato invece di creduto: `gbrain embed --stale --dry-run` vede **1** pezzo, non 4.021. I
  4.021 compaiono solo con `--include-null-signature`, e ogni corsa stampa
  `invalidated 3986 chunk(s) embedded under a prior model signature`, li rifà, uno fallisce
  perché troppo lungo per il contesto di bge-m3, e il conteggio torna a 3.987: un ciclo che non
  converge mai. Il contenuto è raggiungibile — cercando `profile settings` nella sorgente
  mirrorbuddy **il primo risultato è proprio la pagina che "fallisce"**. Quindi: nessun
  contenuto perso, nessun recupero da fare, e il job notturno che avevo installato è stato
  disinstallato. *Condizione che lo renderebbe una card:* se una ricerca non trova qualcosa che
  sai di aver scritto — quello sarebbe contenuto davvero mancante, e questa riga andrebbe
  riaperta.

- **Un tool senza destinazione dichiarata scrive nella CWD, e la CWD e' un repo di qualcuno**
  (24 agosto 2026). gbrain e' l'istanza, non la classe. La sorgente `default` non aveva
  `local_path`: non ha rinunciato a scrivere, ha scritto dove si trovava — un repo pubblico —
  e i file erano l'**unica copia** di quei fatti (`gbrain get` → `page_not_found` su tutti e
  tre gli slug), quindi il rischio non era solo la fuga ma anche la perdita se qualcuno li
  avesse cancellati invece che spostati. Risolto per gbrain: casa in
  `~/.roberdan-os/private/brain`, fuori da qualsiasi worktree git, asserito in
  `test/test-private-marker.sh`; `test/private-marker-check.sh` guarda anche gli untracked.
  Quello che **non** e' risolto e' la classe: qualsiasi altro tool con permesso di scrittura,
  lanciato dentro una sessione agente, ha lo stesso comportamento di default, e il gate lo
  prende solo se il file si dichiara privato. Un tool che scrive dati riservati **senza**
  marcatore passerebbe tutti e tre i controlli. **PROMOSSO A CARD** il 24 agosto 2026 su
  decisione di Roberto: `todo/260824-182954` (repo `roberdan-os`). La condizione che avevo
  scritto qui era "un secondo tool diverso da gbrain che deposita file non richiesti in un
  repo"; non si e' avverata, e la promozione e' comunque la sua chiamata, non la mia — le
  condizioni di questo file dicono quando *proporre*, mai quando decidere. Il seguito sta
  sulla card, questa riga resta come origine del perche'.

- **2026-08-28 — `agents/coach.md` ha un frontmatter che non e' YAML valido.** Trovato mentre
  applicavo `cacheTtl` ai quattro agenti opus (card `260828-123448`), verificando che il
  frontmatter reggesse dopo la modifica: `coach` non parsava nemmeno **prima** di toccare
  qualsiasi cosa (`git stash` e riprova → stesso errore). Causa: il valore di `description`
  contiene due punti seguiti da spazio (`"...challenge himself. Maieutic and empathetic: asks
  the right questions..."`) e non e' fra virgolette, quindi YAML lo legge come una mappa
  annidata e si ferma. `wanda` e `board`, controllati insieme, parsano bene. Oggi non rompe
  niente di osservabile: chi legge questi file lo fa con `grep`/`sed`, non con un parser YAML,
  ed e' esattamente per questo che il difetto e' sopravvissuto. **La condizione che lo
  renderebbe una card:** il primo consumatore che parsi davvero il frontmatter — un
  `bin/sync.sh` che generi i wrapper da una struttura invece che per sostituzione di testo, un
  test che validi tutti gli agenti, o un host che rifiuti l'agente all'avvio. Quel giorno
  `coach` sparisce in silenzio, ed e' l'agente con cui Roberto ragiona. Fix, quando servira':
  virgolettare il `description`. Non fatto qui perche' non e' il lavoro della card, e un file
  di comportamento non si tocca di straforo (`AGENTS.md` § Memory: mai auto-commit su
  `agents/`).

- **2026-09-01 — `test/validate.sh` e' tornato al tetto delle 300 righe e va spezzato, non baselinato in eterno.** Trovato agganciando `test/test-session-waste.sh` (card `260901-185951-2`): validate.sh era a **300 esatte** e le 4 righe della nuova sezione l'hanno portato a 304, quindi e' entrato nella baseline delle 300 righe (`test/file-size-baseline.txt`, quindicesima voce). E' lo stesso destino gia' capitato a `test-copilot-adapter.sh` (dodicesima). La baseline e' il meccanismo giusto per una crescita puntuale e visibile, ma validate.sh e' un **indice**: ogni nuova suite aggiunge ~4 righe, e un indice congelato a 304 costringera' ogni prossima aggiunta a crescere la baseline o a spezzare sotto pressione. Il canone lo dice gia' a chiare lettere nel file stesso (*"validate.sh lo spezza, non lo allarga"*), e nel 2026-08-01 era stato spezzato da 623 a 256 proprio per questo. **La condizione che lo renderebbe una card:** la prossima suite che deve entrare (la sedicesima voce di baseline che tocca validate.sh, oppure il primo `err` "validate.sh e' cresciuto da 304"). Il taglio naturale: estrarre l'indice delle sezioni "8*" (receipts/pending/session-waste/meta-loop) in un `test/validate-tools.sh` sourceato, come gia' fatto con `test/validate-privacy.sh`. Non fatto qui perche' e' un refactor del gate condiviso, fuori dallo scope della card.
