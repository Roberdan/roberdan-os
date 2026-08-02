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

## Aperti — 6 su 10

| # | Cosa si rompe | Riparare costa | Se non facciamo niente | Diventa una card quando | Nato |
|---|---|---|---|---|---|
| 3 | I due account GitHub (`Roberdan` e `roberdan_microsoft`) si rubano il posto: `gh auth switch` scrive uno stato **globale**, quindi una sessione cambia account e l'altra si ritrova sotto quello sbagliato | ~30 righe: un wrapper che sceglie l'account dal `remote` del repo, più il test | Continua. Già visti: 2 PR non create, 1 merge rifiutato, un 401 con credenziali valide, un push che diceva *"Repository not found"* su un repo che esisteva | **Già decisa dal twin il 2 ago: si ripara adesso.** Vincolo: deve funzionare digitando `gh` normale. Se in un'ora non è l'unica strada, ci si ferma e si torna da Roberto | 30 lug |
| 9 | Una PR si merga anche col controllo rosso: nessuna protezione del ramo lo impedisce | 1 comando | Un `main` rotto entra senza che niente si opponga | **Decisa dal twin: accendere, versione stretta** (solo "i controlli devono passare", admin esclusi, push diretto libero). Bloccata dal classificatore di sicurezza il 2 ago — è il gate umano #1, la esegue Roberto a mano | 30 lug |
| 2 | `install-git-hooks.sh` lanciato da un worktree incide nel controllo il percorso del worktree: quando la cartella sparisce, **ogni commit si blocca** | ~5 righe: risolvere sempre al checkout principale | Si ripete a ogni card. Rimedio da 1 riga, ma solo se sai qual è | Alla terza volta, o quando capita a Roberto invece che a un agente | 30 lug |
| 20 | Il controllo di qualità (`kb finish --thor`) ha **rifiutato un PASS vero** per come thor aveva formattato la frase, e al secondo tentativo identico l'ha accettato | ~10 righe sul lettore del verdetto | Insegna la cosa peggiore: che davanti a un rifiuto conviene rilanciare. Un cancello che a volte cede al secondo tentativo non è un cancello | Alla seconda volta, o subito se qualcuno chiude una card con `--by` dopo un rifiuto di lettura invece di rilanciare | 2 ago |
| 23 | Una verifica interrotta lascia un lucchetto in `$TMPDIR` e il controllo successivo esce **rosso su un test innocente** | ~5 righe: scrivere il PID nel lucchetto e considerarlo morto se il processo non c'è | Chi lo incontra impara a cancellare i lucchetti, cioè a disarmare la protezione | Alla seconda volta, o subito se qualcuno cancella un lucchetto senza controllare prima | 2 ago |
| 24 | `bin/install-hooks.sh` dice *"idempotent, a second run is a no-op"* e su questa macchina **raddoppierebbe 10 controlli automatici**: confronta le stringhe esatte, e la configurazione viva usa forme equivalenti ma diverse (`$HOME` contro percorso assoluto, con e senza `bash` iniziale) | ~10 righe: normalizzare prima di confrontare | Chi lancia `--apply` fidandosi di quella riga fa girare ogni controllo due volte | Prima di usare lo script su una macchina che ha già controlli installati | 2 ago |

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

_Aggiornato: 2026-08-02._
