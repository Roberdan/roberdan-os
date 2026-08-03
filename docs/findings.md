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
