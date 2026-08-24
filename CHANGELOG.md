# Changelog

All notable changes to roberdan-os. Format: [Keep a Changelog](https://keepachangelog.com);
versioning: semver on the system's behavior/tooling (the paper has its own version).

## [v2.35.0] - 2026-08-24

**La trappola che avrebbe disfatto il v2.34.0, chiusa prima che scattasse.** Il cervello
privato sta fuori da git: e' quella proprieta' — non il nome della cartella, non il
`.gitignore` — a renderlo irraggiungibile da qualunque `git add`. Ma `gbrain sources status`
consiglia `gbrain sync --source default`, e quel comando li' dentro fallisce con *"Not inside
a git repository"*. La correzione ovvia a quell'errore e' `git init`: la mossa sbagliata
fatta per la ragione giusta. Un repo senza remote non si puo' pushare **oggi**; un
`git remote add` un anno dopo non chiede il permesso a nessuno.

- **Il comando giusto e' `gbrain import`**, che non vuole git ed e' **additivo**: misurato,
  354 → 357 pagine, zero cancellate. E' la differenza che rendeva `sync` pericoloso qui —
  `sync` riconcilia una directory con la sorgente, quindi 3 file davanti a 354 pagine sono
  351 candidate alla cancellazione. Le tre note sono ora nel motore **e** sul disco.
- `test/test-private-marker.sh` **fallisce** se `~/.roberdan-os/private/brain` diventa un repo
  git, e il messaggio nomina la causa probabile e il comando giusto. Su una macchina dove la
  cartella non esiste salta, dichiarandolo: un test che fallisce dove la cosa non esiste
  insegna solo a ignorarlo. Asserita anche la **direzione opposta** — che la regola sappia
  riconoscere una cartella dentro un repo — perche' un controllo che non sa fallire non
  protegge niente.
- `docs/privacy-leak-check.md` § *La trappola del futuro* e `memory/memory-protocol.md`
  scrivono `sync` vs `import` dove verranno letti. L'avviso di gbrain non e' sotto il nostro
  controllo; che l'invito non venga accolto, si'.

### Findings

- Annotata in `docs/findings.md` la **classe**, non l'istanza: un tool senza destinazione
  dichiarata non rinuncia a scrivere, scrive dove si trova. Il gate lo prende solo se il file
  si dichiara privato — un tool che scrive dati riservati **senza** marcatore passerebbe tutti
  e tre i controlli. Resta un finding con la sua condizione di promozione, non una card:
  costruire oggi una difesa generale su un solo caso e' progettare al buio.

## [v2.34.0] - 2026-08-24

**Le note private di gbrain hanno una casa, e non e' un repo.** Il gate del v2.33.0 fermava
il sintomo. La causa era un'altra, e si e' vista guardando la configurazione: la sorgente
`default` di gbrain — il cervello personale, slug `people/ projects/ orgs/` — non aveva
**nessun `local_path`**. Un generatore senza destinazione dichiarata non rinuncia a scrivere:
scrive relativo alla CWD, e quel giorno la CWD era questo repo, che e' pubblico.

- **Non erano uno scarto: erano l'unica copia.** `gbrain get` rispondeva `page_not_found` su
  tutti e tre gli slug. Per questo sono state **spostate**, non cancellate, e per questo il
  messaggio del gate ora dice `mv`, mai `rm`.
- **Casa: `~/.roberdan-os/private/brain/`**, e la sorgente `default` ci punta (354 pagine
  intatte, verificato dopo la modifica; backup di `config.json` prima di toccarla). E' la
  cartella gia' dichiarata per il riservato, ed e' **fuori da qualsiasi worktree git** —
  verificato, non assunto. E' quella proprieta' a renderla irraggiungibile da un commit.
- **Scartati, con la ragione scritta:** il vault Obsidian (sincronizza su cloud: esposizione
  diversa, non risolta; ed e' riservato a `type: agent-learning`) e un repo git privato (un
  `git add -A` in un repo resta un `git add -A`).

### Changed — `.gitignore`: tolte le cartelle, messa la ragione

- `people/ projects/ orgs/ claude-code/` **non** sono piu' ignorate. Si ignora cio' che ha
  diritto di stare nell'albero e non va versionato — un artefatto di build, una cache. Quelle
  li' non ci dovevano stare per niente, e ignorarle le rendeva invisibili in `git status`
  senza renderle piu' sicure. **Visibile e bloccata batte nascosta e bloccata**: se `people/`
  ricompare, e' un bug da guardare, e la prima cosa da controllare e' `gbrain sources list`.
- `test/test-private-marker.sh` asserisce la scelta in **tutte e due** le direzioni: che
  quelle cartelle restino fuori dal `.gitignore`, e che `.gitignore` e il messaggio del gate
  dicano **dove** devono stare invece. Un divieto senza destinazione si aggira e basta.

### Changed — il gate guarda anche i file non tracciati

- `test/private-marker-check.sh` in modalita' repo aggiunge `git ls-files --others
  --exclude-standard`: untracked e' lo stato **normale** di una nota generata, e un controllo
  che aspetta `git add` se ne accorge sempre un passo troppo tardi. `--exclude-standard`
  tiene buono il `.gitignore`, cosi' il rinforzo non diventa un falso positivo per chi ha una
  cartella legittimamente ignorata — asserito in entrambi i versi.

### Docs

- `AGENTS.md` § Privacy, `memory/memory-protocol.md` (nuova riga "Private brain" nella
  tabella *Where it lives*) e `docs/privacy-leak-check.md` (sezioni *Dove devono stare
  invece* e *Perche' NON stanno nel .gitignore*, con la tabella delle alternative scartate).

## [v2.33.0] - 2026-08-24

**Un terzo cancello di privacy: il file che si dichiara privato.** `git add -A` in questo repo
— che e' **pubblico** — ha portato dentro un commit due note generate da **gbrain**
(`people/roberto.md`, `claude-code/hooks/bash-guard-sh.md`), ciascuna con righe marcate
`visibility: private`; una terza (`projects/virtualbpmfy27.md`) aspettava non tracciata con
numeri di PR, percentuali di margine e il nome di un cliente. Nessuno aveva deciso di
pubblicare niente: un tool ha scritto nella working tree e `-A` ha preso quello che ha trovato.
**Non e' mai arrivato su GitHub** — verificato contro `origin/main`, che non ha e non ha mai
avuto nessuno di quei file — ma solo perche' il push non era ancora stato dato: per fortuna,
non per un controllo.

- **Perche' gli altri due gate non potevano prenderlo.** `leak-check.sh` e' una denylist: sa i
  termini che qualcuno ha pensato di scrivere, e il testo di un fatto generato domani non e' su
  nessuna lista. `directory-dump-check.sh` cerca la FORMA di una rubrica (indirizzi, ruoli), e
  li' non ce n'erano. Tutti e due hanno risposto correttamente **no**.
- **`test/private-marker-check.sh`** fa la terza domanda: *il file dichiara di essere privato?*
  Sono i file stessi a dirlo, in una colonna che il generatore compila. Gira in
  `hooks/pre-commit` (che **blocca**) e in `test/validate.sh`.
- **Il `.gitignore` non e' la difesa.** Copre `people/ projects/ orgs/ claude-code/`, cioe' le
  cartelle di **oggi**, e serve a togliere il rumore da `git status`. Elencare cartelle e'
  inseguire i nomi: la prossima sync puo' inventarne un'altra. Il gate legge il marcatore
  **dentro** il file, quindi regge lo stesso.
- **Non cancella niente**: i file restano sul disco, escono solo da git (`git rm --cached`).
  Non ristampa il contenuto privato nel proprio errore — un guardiano che incolla il segreto
  lo ha spostato, non fermato. E **non blocca un file marcato `public`**: la dichiarazione si
  rispetta in tutte e due le direzioni, altrimenti diventa un divieto di scrivere la parola.
- **Le deroghe stanno in un file, non nello script.** Al primo commit il gate ha bloccato il
  proprio test, che una nota finta col marcatore la costruisce per mestiere: l'eccezione vive in
  `test/.private-marker-allow`, un percorso **esatto** per riga e nessun glob (`test/*` sarebbe
  una porta aperta). Stessa scelta del `.directory-dump-baseline` — una deroga deve costare una
  riga visibile in un diff. Oggi sono due, e il test fallisce se diventano di piu'.
- Meta' di `test/test-private-marker.sh` verifica che il gate **lasci passare** (repo pulito,
  file `public`, prosa scritta a mano che parla di privacy): un guardiano che non puo' piu'
  aprirsi viene disattivato, e disattivarlo qui spegne anche il leak-check nello stesso hook.
- **`test-nested-board-notice` non si rompera' alla prossima gamba.** Quella suite stubba i
  controlli del hook per parlare d'altro, ed era gia' rimasta rotta una volta per lo stesso
  motivo (gamba anti-dump, 2026-07-30) e una seconda ora. Alla seconda si smette di aggiungere
  righe a mano: le gambe vengono **lette dal hook stesso**, cosi' la terza si stubba da sola.
- `AGENTS.md § Privacy` e `docs/privacy-leak-check.md` ora descrivono i **tre** cancelli e cosa
  ciascuno NON puo' vedere, con la regola operativa: **mai `git add -A` in questo repo**.

## [v2.32.1] - 2026-08-24

**La board di `kb` descrive ogni card con una frase completa, invece di una parete di timestamp.**
Tre colonne affiancate da 34 caratteri entravano solo `id (repo)`: per sapere che cosa fosse
`260802-135739` serviva un `kb show` per card. Ora la board e' impilata per colonna (TO DO, DOING,
DONE piu' recenti) e ogni card ha la sua **frase**, che **va a capo** invece di essere tagliata.

- La frase e' il `title:`; per TO DO e DOING segue un secondo paragrafo `Fatta quando: <dod:>`,
  perche' "cosa fa" e "quando e' finita" sono due affermazioni diverse. Il `dod:` e' tagliato alla
  prima clausola e a 200 caratteri — il testo integrale resta in `kb show`.
- DONE resta compatta (solo la frase): e' storia, non lavoro davanti. Una card legacy senza
  `title:` e' descritta comunque dal suo `dod:`, ovunque si trovi.
- Due forme, una regola: finche' la frase ha ≥40 caratteri, id e `(repo)` restano in colonna e il
  testo va a capo di fianco; sotto quella soglia (terminale stretto, id lunghi) la card diventa un
  blocco — id + `(repo)` su una riga, la frase sotto, rientrata.
- Colonne **misurate**, non fisse, e allineate su tutte e tre le sezioni. L'**id non viene mai
  troncato** (e' la chiave che ridigiti in `show`/`start`/`finish`).
- Wrap e padding **a caratteri, non a byte** (`fold` su macOS conta byte e spezzerebbe a meta' un
  accento); una parola piu' lunga della colonna viene spezzata invece di sfondarla.
- Una colonna vuota stampa `(vuota)`: uno spazio bianco non si distingue da un render morto.
- I tre totali restano su **una riga di riepilogo** in cima — gli stessi che stampa `kb counts`,
  e `test-kb-views` continua a fissarli uguali.
- Il render vive ora in `kanban/board.sh`, sourceato **pigramente** da `kb.sh`: la strada calda
  del hook di sessione (`kb counts` / `kb doing`) non paga la lettura di un file per una tabella
  che non stampa.
- Nuova suite `test/test-kb-board.sh` (agganciata a `validate.sh`): frase che va a capo per intero
  (nessun `…`), righe di continuazione allineate sotto la loro colonna, `dod:` alla prima clausola,
  id intero, fallback sul `dod:` per le card senza titolo, colonne allineate fra sezioni, `(vuota)`,
  e nessuna riga oltre la larghezza a `COLUMNS=62`.

## [v2.32.0] - 2026-08-21

**Il canone ora arriva anche nei due ambienti Cowork e il percorso full-recall e' installabile
senza ricostruirlo da fonti sparse.** E' una minor release perche' aggiunge nuove superfici
operative, non solo documentazione: Microsoft 365 Copilot Cowork e GitHub Copilot Cowork possono
caricare il giudizio di roberdan-os come Agent Skill, mentre il README porta gstack e gbrain da
assenti a operativi con ownership e freshness esplicite.

Questa pubblicazione include anche l'hardening privacy gia' registrato come v2.31.3 ma mai
taggato ne' pubblicato: i tool di memoria host restano negati meccanicamente e il durevole resta
nel vault locale.

### Added

- `.github/skills/roberto-twin/`: il gemello digitale come Agent Skill portabile per GitHub
  Copilot Cowork/coding agent, CLI e VS Code. Il core resta piccolo; engineering, voce, thinking
  e costituzione si caricano on demand.
- `cowork-skill/roberdan-os/`: export dedicato a Microsoft 365 Copilot Cowork. Sostituisce le
  prove git/CI non disponibili su quella superficie con evidenza verificabile su documenti,
  email, meeting, Teams e OneDrive, senza perdere voce, gate umani e ragionamento.

### Changed

- `README.md`: lifecycle zero-to-working di gstack + gbrain — upstream ufficiale, Ollama
  `bge-m3` a 1024 dimensioni, source e pin per worktree, primo indice, autopilot launchd,
  aggiornamenti indipendenti, diagnostica e ownership del blocco generato.
- I comandi gbrain distinguono le superfici reali: `/setup-gbrain` e `/sync-gbrain` su Claude
  Code; `/gstack-setup-gbrain` e `/gstack-sync-gbrain` nell'installazione namespaced di Copilot
  CLI.

### Fixed

- Il frontmatter YAML delle skill esportate viene analizzato davvero nei test: descrizioni con
  `: ` non quotato non possono piu' superare la validazione per poi essere rifiutate da Cowork.

### Security

- Incluso integralmente v2.31.3: l'estensione Copilot nega `store_memory`, `vote_memory`,
  `create_memory` e `update_memory` prima dell'esecuzione, anche se il guard esterno manca.

## [v2.31.3] - 2026-08-21

**La memoria durevole dell'agente finiva su un archivio ospitato da GitHub.** Roberto: *"non mi
piace che le memorie vadano su github, voglio tutte le cose sensibili sempre e solo in locale"*.
`AGENTS.md` gia' lo vietava, ma era una regola che il modello poteva violare — e l'ha fatto, tre
volte, nella sessione del 2026-08-21. Ora e' un meccanismo, non una buona intenzione.

### Added

- `hooks/copilot/extension.template.mjs`: `MEMORY_TOOLS` + un **deny esplicito** in
  `onPreToolUse` per `store_memory`, `vote_memory`, `create_memory`, `update_memory`. E' un
  `deny` e non un `ask` perche' non esiste un caso legittimo: il durevole sta nel vault locale
  (`~/Obsidian/Roberdan's Vault/agent-learnings/`), e un prompt inviterebbe solo all'errore.
  Il diniego e' deciso **inline**, prima di `applyGuard`, quindi vale anche se gli script di
  guard mancano o falliscono.
- `test/test-copilot-adapter.sh`: quattro asserzioni sul diniego (deny, case-insensitive, e il
  messaggio che indica il vault come alternativa).

### Note

- L'interruttore del fornitore (`~/.copilot/settings.json` -> `memory.enabled: false`) e' stato
  impostato in parallelo, ma vive **fuori** da questo repo e puo' essere riacceso da un
  aggiornamento o da un `/memory` distratto: per questo il deny locale esiste comunque.
- Verificato che le **sessioni** non si sincronizzano in blocco: nel cloud store risultano solo
  quelle con un `task_id`, cioe' condivise esplicitamente (`/delegate`, `/remote`, `/share`).

## [v2.31.2] - 2026-08-21

**Il fork gbrain non esiste piu' dal 2026-07-08, ma tre file continuavano a dirlo a chi installa.**
Nessun cambiamento di comportamento: solo la documentazione che tornava a coincidere con la realta'
gia' verificata da `bin/check-embedder.sh:4-8`.

### Fixed

- `README.md` (Prerequisites): la voce gbrain diceva di installare un **fork personale**
  (`Roberdan/gbrain`) pinnato a `ollama:bge-m3`. Falso: dal 2026-07-08 gira l'**upstream ufficiale**
  `garrytan/gbrain` e l'embedder e' scelto da *configurazione* (`embedding_dimensions: 1024` in
  `~/.gbrain/config.json`), non da una patch. Era l'errore piu' costoso dei tre: e' l'istruzione di
  installazione, quindi mandava chiunque a clonare un fork che non deve piu' esistere.
- `README.md` (Honest limitations): "the gbrain fork" -> "gbrain".
- `bin/doctor.sh:116`: l'hint di remediation del check `gbrain` rimandava al fork. Ora indica
  l'upstream ufficiale e chiarisce che l'embedder e' impostato via config.
- `bin/doctor.sh:125,130`: i due messaggi del check `ollama` dicevano "the gbrain **fork's**
  pinned embedder", contraddicendo la riga 116 appena corretta nello stesso file. Ora
  "gbrain's **configured** embedder". Trovate da @thor: il grep di accettazione cercava
  `local fork` e non le beccava, perche' qui la formulazione era `gbrain fork's` — il
  criterio era scritto su tre frasi scelte a mano invece che sul vincolo reale.
- `docs/roberdan-os-paper-en.md` (Limitations): la voce descriveva una fragilita' **non piu'
  esistente** (una patch a due righe da riapplicare dopo ogni upgrade dell'engine). Riscritta invece
  che cancellata: il rischio residuo reale — *config drift* tra `config.json` e l'engine in
  esecuzione — c'e' ancora, ed e' esattamente cio' che `bin/check-embedder.sh` verifica. Cancellarla
  avrebbe lasciato il paper senza alcuna limitazione dichiarata mentre il repo continua a spedire il
  durability check: meno onesto, non piu' onesto. **La card diceva di cancellarla**, quindi la
  deviazione e' stata portata a Roberto invece che decisa dall'agente: @thor ha rifiutato la
  chiusura finche' non si e' pronunciato, e il 2026-08-21 ha approvato la riscrittura.
- `docs/roberdan-os-paper-en.md` (Future work): l'item "cosi' un fork locale e il suo durability
  check non sono piu' necessari" era ormai privo di oggetto. Riformulato sul residuo reale
  (registrare `bge-m3`@1024 nativamente nella recipe ollama upstream).

### Added

- `docs/plan-2026-08-21-gbrain-dependency.md`: indice dell'iniziativa (P1-P8) su come roberdan-os
  dipende da gbrain e gstack. Questa card e' **solo P1**. P2-P8 restano proposte non promosse:
  solo Roberto promuove. Il piano documenta anche il modello a tre livelli
  (canon / automation-core / full-recall) e la catena roberdan-os -> gstack -> gbrain.

## [v2.31.1] - 2026-08-21

**Il watcher evolve aveva tre card ferme: Claude Code, Copilot e Warp sono cambiati, ma il canon non doveva auto-riscriversi.**
Questa release chiude l'analisi in modo tracciabile: ogni proposta cita fonte, versione/data,
file che toccherebbe e separa cio' che e' stato solo documentato da cio' che Roberto deve ancora
approvare.

### Added

- `proposals/2026-08-08-claude-code.md`: valutate le novita' Claude Code da v2.1.223 a v2.1.238,
  inclusi `headersHelper`, self-hosted runner, cross-session messaging, native todo tools e
  hardening sandbox/permission. Nessuna modifica al canon: le regole su plugin helper, bus e
  factory restano decisioni Roberto.
- `proposals/2026-08-08-copilot.md`: valutati Agent Plugins 1.0, nuove superfici Copilot CLI
  (`/tasks`, `/plugin`, `/rewind`, `/memory`, `/remote`, `/fleet`, `/autopilot`), enterprise
  managed settings JetBrains e aggiornamenti modello. Proposta una futura emissione plugin
  Copilot opt-in, non applicata.
- `proposals/2026-08-08-warp.md`: valutati `SKILLS_DIRS`, skill references repository-qualified,
  orchestrazione Warp Agent CLI e fix su toolbelt/background commands. Proposta una futura regola
  Warp per `SKILLS_DIRS`, non applicata.

## [v2.31.0] - 2026-08-20

**Tre skill del canone non si caricavano da nessuna parte, e nessuno lo diceva.**
`bin/sync.sh` rilevava le collisioni sul nome della CARTELLA, ma Claude e Copilot risolvono una
skill dal `name:` del frontmatter. gstack installa `gstack-review/` che dichiara `name: review`:
la cartella `review/` risultava libera, la nostra veniva installata accanto, e l'host ne teneva
UNA sola — la nostra spariva in silenzio. `review`, `ship` e `verify-done` erano oscurate cosi'.
Il costo vero non e' la skill mancante: e' che invocando `/ship` rispondeva quello di gstack, che
si ferma alla PR e fa squash/rebase, mentre il nostro impone merge-commit only, vieta il
force-push e ferma il merge su `main` che tocca protezioni o release-infra. Il cancello piu'
delicato del sistema era sostituito da un altro, senza un warning.

### Fixed

- `bin/sync.sh` (via `bin/lib-skills-install.sh`): la collisione si rileva sul `name:` dichiarato.
  Quando un altro sistema occupa il nome, la nostra skill si installa come `rdos-<name>/` col
  frontmatter riscritto — nessuno dei due sparisce, entrambi restano invocabili. Una copia gia'
  oscurata viene ritirata; se il sistema estraneo sparisce, la run successiva torna al nome piano.
  La scansione usa `find -L`: gstack simlinka le DIRECTORY dentro `~/.copilot/skills`, e un find
  normale non ci entra — cioe' era cieco proprio dove la collisione era reale.

### Changed

- `bin/lib-skills-install.sh` (nuovo): l'installazione delle skill esce da `bin/sync.sh`, che era
  gia' oltre le 300 righe della baseline. Il file scende da 638 a 622 righe: la baseline dice che
  un file oltre soglia si spezza, non si allarga, ed e' la stessa strada gia' fatta da
  `validate.sh` con `test/lib-suites.sh`.
- `test/test-tool-coverage.sh`: il cablaggio di una skill ha due forme valide (symlink al nome
  piano, o wrapper `rdos-<name>` col marker). Rifiuta ancora la skill assente o un'omonima non
  nostra.

### Added

- `test/test-skill-name-collision.sh` (agganciata a `test/validate.sh`): 7 casi — namespace,
  idempotenza, ritiro della copia oscurata, guarigione al nome piano, mai-overwrite di un
  `rdos-<name>/` altrui, e la directory simlinkata che e' il caso reale di `~/.copilot`.
- Documentazione: `docs/USAGE.md` guadagna una sezione "Skill name collisions" (perche' il `name:`
  e' l'identita' vera, cosa fa `rdos-<name>`, e il limite noto: una skill *project-scope* dentro un
  altro repo e' invisibile all'installer e vince legittimamente in casa sua). `README.md` e
  l'invariante 1 di `ARCHITECTURE.md` lo dicono in una riga, dove l'installer e' gia' descritto.

### Nota per chi aggiorna

Le skill del canone oscurate da un altro sistema ora si invocano `/rdos-review` e `/rdos-ship`.
Il nome piano torna da solo se quel sistema viene disinstallato. `verify-done` resta oscurata
*dentro* i repo che ne committano una propria in project scope: e' cross-scope, l'installer non
puo' vederla; altrove funziona.

## [v2.30.0] - 2026-08-20

**Un verificatore spento parlava a nome di @thor, e i segreti si copiavano dentro il repo.**
Quando `claude` esce per credito finito non ha guardato niente — ma `kb` lo riportava come
"@thor ha verificato e dice NO", cioe' scriveva sulla card un giudizio che nessuno aveva
pronunciato. Nella stessa sessione una copia di backup di un file di credenziali e' finita nel
working tree, non coperta da `.gitignore`, a un `git add .` dal commit. Aggiunto il learning che
tiene insieme quattro difetti gia' visti: il check era verde perche' misurava la cosa sbagliata.

### Fixed

- **`SKIP` invece di `FAIL` quando @thor non e' eseguibile.** Misurato su MirrorBuddy, card
  `260820-122649`: log con `You've hit your monthly spend limit`, exit 1, zero righe di verifica,
  e chi chiudeva leggeva `REFUSED: @thor ha verificato e dice NO`. E' la malattia che
  `kanban/thor-verify.sh` esiste per curare, nel verso peggiore — un registro che afferma il
  falso, e che nessuno puo' smentire sei mesi dopo. `thor_unavailable_reason()`
  (`factory/lib.sh`) riconosce credito, quota, token scaduto e sessione assente dal log;
  `verify_card` lo dice con parole sue e `thor-verify.sh` lo traduce in `SKIP`, che `kb` gia'
  gestisce chiedendo chi ha verificato davvero. Provato **end-to-end con un finto `claude`**, non
  con un grep sul sorgente, e con la mutazione: tolta la traduzione, il test torna rosso.
  Distinzione opposta coperta con la stessa cura — una bocciatura vera non deve essere scambiata
  per uno strumento spento, o il cancello si apre da solo.
- **I messaggi di `kb finish` mostrano entrambe le forme.** L'evidenza sta sempre in `--thor`,
  anche quando a verificare non e' stato thor: `--by` sembra l'alternativa, cosi' si prova
  `--by <chi> '<ev>'`, l'evidenza cade posizionale e kb rifiuta uguale (tre tentativi persi il
  2026-08-20 contro un messaggio che non nominava la coppia). A **saldo zero di righe**:
  `kanban/kb.sh` e' oltre soglia e il ratchet non lascia allargarlo.

### Added

- **Regola: il backup di un file con credenziali non si scrive dentro il repo**
  (`rules/best-practices.md` § Security & Privacy). `.gitignore` copriva `.env*` ma non `*.bak`,
  quindi `cp .env.production.local .env.production.local.bak` produceva un file di URL di
  database, chiavi Stripe e Supabase vive che `git status` elencava come untracked. La copia va
  **fuori dal working tree** (`~/.<repo>-env-backups/`, `chmod 600`) e si verifica con
  `git check-ignore`. Allargare `.gitignore` non e' la riparazione: protegge questo repo, su
  questa macchina, per i pattern che qualcuno ha immaginato.
- **`behavior/roberto-mode.md` § "The check has to fail when the thing is broken".** Quattro casi
  con la stessa forma — suite verdi sul corpus invece che sullo store deployato, riga di
  migration invece della funzione, righe fisiche invece di prosa — e i due corollari: un check
  verde sul bersaglio sbagliato e' **peggio** di nessun check perche' chiude l'indagine, e uno
  strumento che non parte non e' un verdetto. Ripreso in `agents/thor.md`, che e' chi deve
  applicarlo.

### Changed

- `kanban/README.md`, `AGENTS.md`, `docs/USAGE.md`: documentati i tre esiti del gate
  `doing → done` (`PASS` / `FAIL` / `SKIP`) e la forma `--by <chi> --thor "<evidenza>"`.

## [v2.29.0] - 2026-08-18

**Tre canali di aggiornamento che tacevano quando fallivano.** Il controllo di gstack non
stampava nulla con due commit di ritardo; il sorvegliante dei changelog dava per "nessuna
novita'" una fonte che rispondeva 429 da nove giorni; il motore di embedding era spento dal
riavvio e il sync chiudeva lo stesso con `3 ok, 0 error`. Nessuno dei tre era rotto in modo
visibile: erano tutti verdi. Chiusa anche una collisione di nomi che spegneva `/ship` e
`/review` a ogni aggiornamento di gstack, e sostituito il modello locale dopo un confronto
misurato invece che dichiarato.

### Fixed

- **`evolve/watch.sh` scambiava "non ho potuto guardare" per "niente di nuovo"** (rilievi 27 e
  28). Tre difetti che si sommavano nello stesso silenzio. La fonte di Claude Code —
  `raw.githubusercontent.com` — rispondeva **429** da questa macchina in modo persistente, non di
  passaggio: lo script stampava `claude-code unreachable, skip` **e usciva 0**. Spostata sul CDN
  jsdelivr, che serve lo stesso file: misurati 513.823 byte e 382 marcatori di versione, identici
  al raw. Alla prima corsa ha trovato subito le novita' accumulate dall'8 agosto.
  - **Un solo tentativo per fonte** diventava un difetto al boot di recupero (il Mac spento
    all'ora prevista): launchd fa partire il job appena si accende, e li' la rete puo' non essere
    ancora su. Ora tre tentativi, 0s + 5s + 15s.
  - **Una fonte muta esce !=0.** launchd conserva `LastExitStatus` per il job anche quando il log
    non esiste piu', quindi `launchctl list` diventa il rilevatore che prima non c'era. Provato
    nei due versi in un worktree usa e getta: con la fonte mutata a un URL invalido `exit=1` e
    `unreachable=claude-code`; sullo script vero `exit=0` e campo vuoto.
  - **Il log stava in `/tmp`**, che macOS svuota a ogni riavvio: la corsa di sabato 15 agosto non
    e' mai partita e non ne restava traccia — le card erano ferme all'8 mentre copilot e warp
    *erano* cambiati. Log e traccia durevole ora in `~/.roberdan-os/`.

- **`bin/toolchain-doctor`** (dal 16 agosto). `doctor.sh` risponde "e' installato". Nessuno dei
  quattro guasti di quel giorno era di installazione: erano tutti installati, giravano, e non
  facevano niente. Esempio: gstack collega `bin/` ma non `lib/`, quindi 13 binari morivano
  all'import e le scritture di learnings, decisioni e telemetria sparivano senza errore.

- **`copilot-local` sceglieva un modello mai scaricato** (dal 16 agosto). Il default era cablato
  su `qwen3-coder:30b`, assente su questa macchina: la via di fuga offline era morta e non lo
  sapeva nessuno finche' non la si usava. Ora il modello si risolve a runtime prendendo il primo
  della lista `PREFERRED` davvero presente in Ollama. I modelli di solo-embedding non sono mai
  auto-selezionabili: non sanno chattare.

- **Il cancello di `@thor` rifiutava per indirizzo, non per merito.** `kb finish` chiamava
  `thor-verify.sh` senza `RDA_KANBAN`, e quello script calcolava il proprio board da dove sta il
  file — cioe' sempre `roberdan-os/kanban`. Per ogni card di un repo federato la risposta era
  "card not found" → SKIP → REFUSED. **Dal 31 luglio la verifica automatica che Roberto aveva
  chiesto non e' mai scattata fuori da questo repo.**
  - E il commit che lo riparava ha portato `kanban/kb.sh` da `100755` a `100644`. `~/.local/bin/kb`
    e' un symlink a quel file: dal merge in poi **ogni** comando `kb`, su qualunque repo, moriva
    con `Permission denied`. Lo strumento che gestisce le card e' stato reso inavviabile dal
    commit che riparava le card.
  - `thor-verify` ora risolve la directory dal campo `repo:` della card, non da dove e' partito:
    un verdetto sincero emesso su codice estraneo resta un verdetto sbagliato. Se il repo non e'
    risolvibile esce SKIP e `kb finish` **rifiuta** di chiudere.

- **Un'asserzione che restava verde per costruzione.** Il test di accordo su `_repo_path`
  interrogava la funzione con la stringa `"#"`. Nessuna riga del registro ha `#` come basename,
  quindi quell'asse rispondeva `""` sempre: restava verde anche togliendo il salto-commenti a una
  delle tre copie, cioe' **proprio nel caso per cui esiste**. Ora interroga il basename reale.

### Changed

- **Modello locale predefinito: `qwen3.6:35b-mlx` → `qwen3.8:27b-mlx`.** Confronto misurato sui
  quattro usi reali che ha qui, stesse domande, stesso momento. Il 3.8 vince tre prove su quattro:
  estrazione di fatti (tutte le date compilate; il 3.6 ne lasciava tre vuote e fondeva due fatti in
  una riga malformata), spiegazione in italiano (diagnosi corretta contro un consiglio sbagliato),
  chiamata di strumenti (8s contro 19s, streaming verificato con `curl -N` e `stream:true` —
  requisito duro di `copilot-local`). Il 3.6 vinceva solo l'aderenza al formato su una domanda di
  lettura bash. 18GB invece di 21GB, stesso contesto 256k. Il vecchio bruciava il **95%** dei token
  in ragionamento interno (1065 parole per risponderne 58); il nuovo il 75%. Il 3.6 e' stato
  disinstallato su decisione di Roberto.
  - Scoperto strada facendo: **due dei quattro tier di gbrain puntavano a `qwen3.6:35b` senza
    `-mlx`**, un modello mai installato su questa macchina. Non ha mai dato errore.

- **`AGENTS.md` accoglie i due blocchi di gstack** (decisione di Roberto, 18 agosto): `Skill
  routing` e `GBrain Search Guidance`. Il collegamento `CLAUDE.md → AGENTS.md` resta un symlink —
  il metodo di scrittura di gstack (file temporaneo + rinomina) lo avrebbe sostituito con un file
  normale, sdoppiando canone Claude e canone universale. La guida dichiara anche il limite
  **misurato** di questo repo: i chunk bash restano con `symbol_name: null`, quindi `code-def` e
  `code-callers` rispondono `count: 0` per ogni funzione di shell, per quanti cicli si lancino.

- **Collisione di nomi con gstack, chiusa alla radice.** gstack e roberdan-os definiscono entrambi
  `ship` e `review`. L'installer di gstack sovrascrive senza avvisare, `bin/sync.sh --install`
  invece salta se la cartella esiste: gstack vinceva sempre, in silenzio, a ogni aggiornamento, e
  `test/test-tool-coverage.sh` diventava rosso. Risolto con l'interruttore nativo di gstack
  (`skill_prefix: true`): le sue 52 skill diventano `/gstack-*`, i nomi corti restano a
  roberdan-os. Sopravvive agli aggiornamenti — il suo `setup` rilegge la preferenza salvata e
  salta il prompt. Non erano in gara: `/gstack-ship` porta dal codice al PR e si ferma li',
  `/ship` copre il tratto dopo (CI, merge-commit only, gate umani).

- **Ollama parte all'accensione del Mac.** Non era negli elementi di login e non aveva un job suo:
  al riavvio del 16 agosto e' rimasto spento, e i due lavori notturni di gbrain (03:00 e 04:00)
  hanno girato a vuoto senza dirlo. E' la causa prima del rilievo 30.

### Findings

Cinque rilievi nuovi in [`docs/findings.md`](docs/findings.md) (26-30), ciascuno con la condizione
che lo renderebbe una card. Uno merita di essere letto anche da chi non tocchera' mai questo repo:

- **Il rilievo 30 e' stato aperto e poi corretto lo stesso giorno.** Avevo letto
  `~14,3 M caratteri pending gbrain embed --stale` come contenuto perso e stavo per programmare un
  recupero notturno di sei ore. Misurato invece di creduto: `--stale` da solo vede **1** pezzo. I
  4.021 compaiono solo con `--include-null-signature`, e ogni corsa stampa
  `invalidated 3986 chunk(s) embedded under a prior model signature`, li rifa', uno fallisce perche'
  troppo lungo per il contesto di bge-m3, e il conteggio torna a 3.987: un ciclo che non converge
  mai. Il contenuto e' raggiungibile — cercando `profile settings` **il primo risultato e' proprio
  la pagina che "fallisce"**. Il job notturno era gia' installato ed e' stato disinstallato.
  - Lo stesso job, provato in ambiente pulito (`env -i … bash -lc`, come parte davvero da launchd),
    usciva **127**: `gbrain` non si trovava, perche' `bash -lc` carica `~/.bash_profile` e
    `~/.bun/bin` sta nel PATH di zsh. Sarebbe partito alle 02:00, finito in mezzo secondo, e avrebbe
    scritto un rapporto che *sembrava* un rapporto — lo stesso difetto che questa versione chiude in
    tre posti diversi.

- **Il rilievo 29 resta aperto e senza spiegazione.** `docs/findings.md` — il registro dei rilievi
  stesso — non e' raggiungibile da una ricerca semantica. Escluse quattro cause con prova
  (classificatore, lista dei metafile, assenza dal remoto, embedder). Il meccanismo e' il ciclo di
  pulizia del sync; **perche' quel file non venga camminato non lo sappiamo.**

## [v2.28.1] - 2026-08-02

**La lista dei rilievi aperti e' a zero.** Da 19 la mattina: 13 chiusi da una decisione, 6
riparati con la loro card e la loro prova di mutazione. E' la prima volta che succede.

### Fixed

- **`install-git-hooks.sh` incideva nel controllo il percorso della cartella da cui lo si
  lanciava** (rilievo 2, dal 30 luglio). Il canone impone **un worktree per card**, quindi
  lanciarlo da li' e' il caso normale — e quel percorso e' garantito sparire. E' successo:
  rimosso `worktrees/roberdan-os/260730-092839`, **ogni commit in roberdan-os si e' bloccato**.
  Ora `ROOT` si chiede a git (`--git-common-dir`) invece di dedurlo dalla posizione dello script.
  Il salto resta **condizionato**: se nel checkout principale non c'e' questo repo si resta
  dov'eravamo, invece di incidere un percorso peggiore di quello che si sta riparando.
  - Riparato anche, perche' sta nella stessa funzione e l'ha trovato il test scritto per altro:
    fuori da un repo git lo script moriva con l'errore grezzo di git ed exit 128.

- **`install-hooks.sh` dichiarava di essere idempotente e avrebbe raddoppiato dieci controlli**
  (rilievo 24). Il dedup confrontava la stringa grezza, e la configurazione viva usa forme
  equivalenti ma diverse da quelle che il generatore produce oggi (`bash $HOME/…` contro il
  percorso assoluto, con e senza `bash` iniziale). Il dry-run annunciava *"would add 11"* quando
  dieci erano gia' installati: `--apply` avrebbe fatto girare **due checkpoint, due gate di
  pre-completamento, due formattatori** a ogni evento. E chi lo lancia lo fa fidandosi di quella
  riga.
  - `norm()` normalizza **solo** cio' che e' davvero la stessa cosa. `X` e `X 2>/dev/null || true`
    restano due comandi diversi: hanno comportamenti diversi davanti a un errore. Cinque
    asserzioni su dodici verificano proprio che **non** appiattisca — un dedup troppo generoso
    saprebbe di idempotenza e sarebbe invece un controllo che sparisce senza dirlo.

### Changed

- **Protezione del ramo accesa su `main`** (rilievo 9), nella versione stretta decisa dal twin:
  i controlli devono passare prima di un merge, **gli admin sono esclusi e il push diretto resta
  libero** — Roberto lavora come prima. Force-push e cancellazione del ramo bloccati. E' il gate
  umano #1 e l'ha esercitato lui.

### La cosa che mi porto dietro

**Due volte in un giorno ho scritto un test che si autoassolve.** In `test-thor-verdict.sh` la
logica era riscritta a mano invece di chiamare quella vera, e 3 mutanti su 5 applicati al codice
passavano verdi. In `test-install-hooks-dedup.sh` l'estrazione della funzione prendeva troppo
codice, l'import esplodeva, e l'helper leggeva l'errore come *"sono diversi"*: cinque asserzioni
verdi per un import rotto. Tutte e due le volte l'ho scoperto **solo** rifacendo la prova di
mutazione — nessuna delle due sarebbe emersa da una suite verde. E' § No False Done punto 3, e la
lezione non e' "stare piu' attenti": e' che **un test che non chiama il codice vero non e' un
test**, e l'unico modo di accorgersene e' rimettere il difetto e guardare.

## [v2.28.0] - 2026-08-02

Il filo: **una sessione che si ferma da sola, e i cancelli che rifiutavano il lavoro fatto.**
Misurato su una sessione vera (VirtualBPM, 31 lug → 2 ago): **46,5 ore di sessione, 4,4 ore di
lavoro**. Il 90% era silenzio, e non per un gate — prima di ogni pausa l'agente aveva scritto da
solo cosa avrebbe fatto dopo, e la pausa finiva perché Roberto scriveva "vai".

### Added

- **`hooks/goal-gate.sh` — il primo hook di questo repo che BLOCCA.** Un turno non può chiudersi
  finché `kb queue --restanti` è maggiore di zero: l'agente viene rimandato dentro con `kb next`.
  È il meccanismo che il comando integrato `/goal` installa a mano per una sessione sola, tranne
  che qui è **il default** e la condizione non è una frase in prosa ma la lista che Roberto ha
  già autorizzato il 2026-07-30.
  - *Le tre pause più lunghe della sessione misurata, con l'ultima frase dell'agente prima del
    silenzio: «Non mi serve niente da te … e vado sulla #2» → 3 h. «La #2 parte subito dopo» →
    7 h 20. «Non aspetto niente da te» → 14 h 36. Un turno finisce quando l'agente SCRIVE: "poi
    faccio la #2" non è un piano che il sistema tiene, è l'ultima frase prima del silenzio. Gli
    altri due hook su `Stop` guardano il repo (file non committati, PR aperte, worktree orfani) e
    dichiarano **entrambi di non bloccare mai**. Nessuno guardava la lavagna.*
  - **I freni sono metà del lavoro**, perché un cancello che non si riapre più è peggio di uno
    che non si chiude mai: coda finita · coda che non si accorcia da 2 giri · tetto di 12
    ripartenze · nessuna coda autorizzata (il gate `todo→doing` di Roberto resta in piedi) ·
    `RDA_NO_GOAL_GATE=1` o `~/.roberdan-os/goal-gate.off`. **8 asserzioni su 14 verificano che
    LASCI PASSARE.** Mutazione 4 su 4 rossa.
  - Aggiunto `kb queue --restanti` (solo il numero) perché l'hook non riscriva la risoluzione di
    repo/KB/coda: due copie divergono, e quella dentro un cancello di uscita diverge in silenzio.

- **`bin/gh-shim.sh` — l'account GitHub si sceglie dal repo.** Installato come `~/.local/bin/gh`,
  che nel PATH precede Homebrew: **si digita `gh` normale**, niente da ricordarsi. Una cartella
  di configurazione per account, scelta dal proprietario del `remote`; `-R proprietario/nome`
  vince sul cwd. Niente più stato globale da contendere: due sessioni su due repo diversi usano
  due account nello stesso istante.
  - *Rilievo 3, aperto dal 30 luglio. `gh auth switch` scrive l'account attivo in una
    configurazione globale: due PR non create, un merge rifiutato, un 401 con credenziali valide,
    e un push che diceva "Repository not found" su un repo che esisteva — GitHub risponde 404 e
    non 403 a chi non è autorizzato, quindi l'errore diceva il contrario della verità. Il più
    caro dei quattro è il merge rifiutato: la sessione lo ha raccontato come fatto.*
  - Verificato prima di scrivere codice che `gh` 2.97 non abbia una strada nativa: non ce l'ha.
  - **Fallisce APERTO**: fuori da un repo, remote non GitHub, proprietario non in mappa (nessuna
    wildcard), cartella non pronta, interruttore, `GH_CONFIG_DIR`/`GH_TOKEN` già scelti → lancia
    il `gh` vero invariato. **10 asserzioni su 15 verificano proprio questo.** Mutazione 5 su 5.

### Fixed

- **Il gate di `@thor` rifiutava verifiche RIUSCITE, e rilanciare identico bastava** (rilievo 20,
  due volte in un giorno, due cause diverse). La lettura pretendeva `VERDICT: PASS — ` esatto e
  il grassetto di @thor non combaciava; e @thor poteva finire il turno scrivendo *"aspetto
  l'esito del test completo, non blocco su questo"* senza dare il verdetto. Ora: lettura
  tollerante sulla **forma** e inflessibile sul **contenuto** (serve la parola `VERDICT`, vince
  l'ultima occorrenza); i due fallimenti hanno messaggi distinti; e il prompt vieta a @thor di
  rinviare — che è la riparazione alla radice.
  - *Un cancello che cede al secondo tentativo insegna che davanti a un rifiuto conviene
    ritentare. È la lezione peggiore che un gate possa dare.*
  - **Difetto commesso dentro la riparazione, e vale più della riparazione:** la prima versione
    del test riscriveva la logica di lettura a mano, e **3 mutanti su 5 applicati al codice vero
    passavano verdi** perché il test non lo stava toccando. § No False Done punto 3, dentro il
    file scritto per impedirlo. Risolto estraendo `thor_read_verdict()` in `factory/lib.sh` e
    facendola chiamare dal test: 5 su 5 rosse.

- **Un lucchetto non rilasciato faceva uscire rosso un test innocente** (rilievo 23, due volte).
  `mkdir` come lucchetto è giusto — atomico, e su bash 3.2 di macOS `flock` non c'è — ma veniva
  rilasciato solo da un `trap EXIT`, che non gira se il processo viene ucciso. Ora contiene il
  PID: proprietario morto = orfano e si riusa, vivo = il rifiuto è vero. Logica in
  `test/lib-lock.sh`, un file solo per i due chiamanti.
  - *Il rosso non era sul difetto, era su un innocente: chi lo incontra impara a cancellare i
    lucchetti a mano, cioè a disarmare la protezione. L'ho fatto io, due volte, in un giorno.*
  - Un lucchetto **senza** PID non è orfano subito: aspetta e rilegge, perché fra il `mkdir` e la
    scrittura del PID c'è una finestra in cui un lucchetto legittimo sembra abbandonato.

### Changed

- **`docs/findings.md` da 583 righe a ~100, da 19 rilievi aperti a 3.** Ora è una tabella che sta
  in una schermata: cosa si rompe · quanto costa · cosa succede se non facciamo niente · la
  condizione che lo fa diventare card · la data.
  - **La regola nuova l'ha decisa il twin**, e ha rifiutato quella che avevo proposto io
    ("si ripara entro pochi giorni o si cancella"): *"mi ridà una coda da smaltire con una
    scadenza addosso — è il 30 luglio con un altro nome"*. La sua: **tetto duro di 10 rilievi
    aperti**, chi scrive l'undicesimo ne cancella uno prima; 14 giorni senza che la condizione
    scatti e si cancella; **promuovere richiede Roberto, cancellare non richiede nessuno**. Il
    difetto non era che i rilievi vivessero troppo: era che solo Roberto poteva toglierli.
  - Il twin ha corretto tre delle collocazioni proposte e ne ha decisi quattro nel merito.
    Chiusi 13 rilievi, tutti con il motivo scritto.
  - Il controllo privacy ha **bloccato il primo commit**: la citazione del twin faceva quattro
    nomi di clienti, che vivono solo in `~/.roberdan-os/private/`. Il gate ha funzionato su una
    frase scritta da un agente, che è il motivo per cui esiste.

- Corretta la descrizione della skill `sync`: prometteva *"mechanized by post-task-sync hook"*, e
  `post-task-sync` dichiara di **non** toccare il vault ed è spento salvo `RDA_AUTOSYNC=1`.
- `README.md`: la tabella dei componenti nomina `goal-gate` e `gh-shim`, e dice quali hook **non**
  sono installati invece di lasciarlo intendere.

## [v2.27.0] - 2026-08-02

Il filo di questa versione e' uno solo: **i gate che dicevano verde senza guardare.** Cinque dei
nove `fix` qui sotto sono controlli che passavano mentre la cosa che dovevano proteggere era
rotta — e ognuno e' stato chiuso con una prova di mutazione, cioe' rimettendo il difetto e
guardando il test diventare rosso. Il resto e' il costo di quella scoperta: `validate.sh`
riscritto per poter lanciare un controllo alla volta, e sette rilievi nuovi scritti dove si
guarda invece che aperti come card.

### Added

- **`@thor` verifica da solo su `kb finish`.** Richiesta esplicita di Roberto il 31 luglio: prima
  l'evidenza scritta in `--thor` era una stringa che nessuno controllava, e chi chiudeva la card
  era anche chi decideva cosa dimostrare. Ora `kb finish` **convoca** thor, che legge la card e i
  suoi criteri e verifica per conto proprio.
  - **Uno SKIP non diventa mai un PASS**, ed e' la meta' importante: un verdetto che non c'e'
    lascia la card in `doing`. Stessa logica per un FAIL. `--by <chi>` resta la via manuale e non
    convoca nessuno, cosi' resta distinguibile chi ha verificato davvero.
  - Misurato oggi su quattro card di fila: in una thor ha rifatto la prova di mutazione **su una
    skill diversa** da quella citata nell'evidenza, invece di rileggere il commit.
  - Limite dichiarato, invariato: `--by` e `--thor` sul percorso manuale restano gate di
    disciplina, non confini di sicurezza.

- **Il watcher `evolve` smette di sorvegliare due fonti che non esistevano piu'** (codex e
  hermes-agent). Una fonte morta non fa rumore: produce un'impronta stabile per sempre, cioe'
  *"nessuna novita'"*, che e' esattamente cio' che si vede anche quando va tutto bene.

- **La mappa dei modelli Copilot era ferma a due generazioni fa**, e `bash-guard.sh` non aveva un
  test proprio. Ora ha `test/test-bash-guard.sh`, lanciabile da solo.

### Fixed

- **Il gate `tool-coverage` diceva PASS mentre 7 delle 9 skill del canon erano irraggiungibili in
  Claude Code.** L'elenco da verificare era scritto a mano e fermo a 3 nomi, con la motivazione
  (vera) che `ship` e `review` collidevano con le omonime di gstack.
  - Misurato da `/doctor` il 2 agosto: **2** skill puntavano alle versioni di gstack, **3** erano
    copie statiche congelate di un `sync.sh` vecchio, **7** erano spente in `skillOverrides`.
    Nessuna di queste condizioni poteva far fallire il gate, perche' il gate non le guardava.
  - Ora l'elenco e' **derivato** da `skills/*/skill.md`, uguale per claude e copilot: una skill
    nuova entra nel gate da sola. Le asserzioni di cablaggio passano da 11 a 18.
  - **Una derivazione vuota e' un FAIL esplicito**, non un PASS silenzioso — altrimenti il difetto
    tornerebbe travestito da bug dello script.
  - Prova di mutazione, tre casi, tutti rossi e tutti ripristinati: symlink rimosso, symlink
    sostituito da una skill estranea, cartella `skills/` vuota.

  *E' il punto 3 di `rules/best-practices.md` § No False Done, e questa volta con la variante
  peggiore: la restrizione era **documentata nel commento**, quindi sembrava una scelta e non una
  dimenticanza. Un limite dichiarato non smette di essere un buco.*

- **Un timeout di `thor-verify` arrivava come un NO.** Un verdetto che non e' stato dato non e' un
  verdetto negativo: ora si distingue.

- **In `validate.sh` una suite attesa ma mai lanciata bloccava il gate per 15 minuti.** I due
  elenchi (`_spawn` e `_suite`) dovevano restare allineati a mano e niente lo controllava. Il
  fallimento non era rumoroso, era *lento* — la firma che in CI si scambia per una build appesa.
  Ora `_suite` rifiuta un nome mai lanciato e lo dice in meno di un secondo.

- **`bash-guard`: le stringhe fra virgolette sono dati, non comandi.** Un comando che *nomina* una
  operazione pericolosa dentro una stringa veniva bloccato come se la eseguisse.

- **Due fonti su tre del watcher `evolve` erano cieche**: l'URL sorvegliato veniva rilevato ma
  restituiva menu e script invece delle note di rilascio. Il rilevamento reggeva, la lettura no.

- **Una card ferma su una decisione di Roberto non compariva in `kb pending`** — cioe' proprio
  nella lista che esiste per dirgli cosa aspetta lui.

- **`kb finish` presupponeva chi avesse verificato invece di registrarlo.** Ora e' un dato sulla
  card.

- **`test-bus` non guardava la coda della factory**, che e' la terza superficie che il bus puo'
  toccare. Il mutante `factory-drop` passava verde; ora esce con exit 1.

### Changed

- **`validate.sh` da 623 a 256 righe, e ogni controllo si lancia da solo.** Prima leggere l'esito
  di un singolo controllo costava tre minuti e mezzo di suite intera. Otto controlli sono usciti
  in file propri; `test/test-validate-wiring.sh` estrae le funzioni vere dal gate invece di
  riscriverle, cosi' non possono divergere.

- **`rules/best-practices.md` da 225 a 212 righe.** Il file dichiara un budget di 200 e tre delle
  sue sezioni erano puntatori alla skill `engineering-reference` scritti come cronaca: quando il
  contenuto e' stato spostato, con che data, quanto costava prima. Via anche le tre righe
  generiche di § Security & Privacy (valida gli input, escape XSS, HTTPS/OAuth), che il modello
  segue gia'. **Nessuna cicatrice tolta**, verificate una per una. Il file e' caricato in ogni
  progetto via il symlink `~/.claude/rules/best-practices.md`, quindi ogni riga qui si paga
  ovunque.

- **Lo snapshot della coda non puo' piu' finire nel repo pubblico** (`.gitignore`).

### Docs

- **`docs/findings.md`: dai 16 rilievi ai 23.** I primi 16 hanno ora lo stato scritto accanto dopo
  le decisioni di Roberto del 31 luglio — sei riparati con la loro card e la loro prova di
  mutazione, tre chiusi da una decisione e non da una riparazione, uno rinviato di proposito,
  cinque lasciati aperti con la condizione che li farebbe diventare card.
- **Sette rilievi nuovi (17-23)** dal giro `/doctor` del 2 agosto: due coppie di skill che
  dichiarano lo stesso `name` (chi vince dipende dall'ordine di lettura della cartella), due
  cartelle senza frontmatter che non si caricano mai, `engineering-reference` cablata e invocata
  zero volte da quando esiste, il controllo di `kb finish --thor` che ha rifiutato un PASS vero e
  al secondo tentativo identico l'ha accettato, l'hook Orca ancora a 10s su `Stop`, i 43 rifiuti
  della modalita' auto concentrati sui comandi Bash composti, e un lock di `test-bus` non
  rilasciato che ha fatto uscire rosso un test innocente.
- I tre giri `evolve` del 31 luglio e 1 agosto, con una riga corretta dopo che `@thor` l'ha
  presa: diceva il falso sul buffer delle proposte rifiutate.

### Non nel repo, ma parte dello stesso lavoro

La riparazione che ha reso utile il gate nuovo vive fuori da git, in `~/.claude/`: le 9 skill del
canon ripuntate ai wrapper generati (erano 2 su 9 corrette), 7 riaccese, 11 skill gstack ferme da
uno-tre mesi spente, e il timeout dell'hook Orca sceso da 10s a 3s sui tre eventi che bloccano il
turno a ogni giro. Il gate di questa versione e' cio' che impedisce a quella riparazione di
marcire in silenzio la prossima volta che gstack si aggiorna.

## [v2.26.0] - 2026-07-30

### Added

- **Il precheck: le tre domande da fare a una card PRIMA di eseguirla.** `kb start` ora chiede,
  e stampa cio' che trova **anche sulla card**: *e' ancora valida?* (piu' di 7 giorni), *la sta
  gia' facendo un'altra card?* (2+ parole significative in comune con una card aperta), *e' gia'
  stata fatta?* (idem con le 30 chiuse piu' recenti).
  - **Non blocca**, di proposito: un gate che blocca su un sospetto statistico viene aggirato al
    terzo falso allarme. Si spegne con `RDA_NO_PRECHECK=1`.
  - **La proprieta' che lo rende utile e' il SILENZIO**: su una card nuova e senza parentele non
    stampa niente. Un avviso che compare sempre e' rumore che si impara a saltare, e il giorno
    che dice il vero nessuno lo legge. Meta' delle asserzioni di `test/test-kb-precheck.sh`
    verificano proprio che taccia, e che non blocchi.
  - Vive in `kanban/precheck.sh` (97 righe) invece che dentro `kb.sh`, che e' gia' a 1680.

  *Scar misurato, non ipotizzato: il 2026-07-30 **cinque** card si sono rivelate sbagliate nel
  momento in cui qualcuno le ha prese in mano. Le azioni MCAPS erano aperte da **venti giorni**
  su lavoro gia' fatto il giorno 11 e reso irrilevante da una decisione del giorno 13 — 56
  risorse Azure distrutte, fra cui esattamente Redis, Event Hubs e le sottoreti che la card
  doveva mettere in sicurezza. Le altre quattro: una card la cui acceptance chiedeva cio' che le
  sue sorelle dovevano fare, due card sullo stesso problema, quattro card sullo stesso lavoro.
  I freni scritti quel mattino fermano la NASCITA delle card e ne limitano il numero in corso;
  nessuno guardava una card nel momento in cui la prendi in mano — che e' l'unico momento in cui
  quelle domande hanno senso. Una card e' la fotografia di un problema NEL GIORNO in cui e' stata
  scritta: piu' invecchia, meno assomiglia al presente, e la pila non aveva memoria di questo.*

## [v2.25.0] - 2026-07-30

### Fixed

- **Il SessionStart hook renderizzava tutto il board per stampare tre numeri.**
  `hooks/context-inject.sh` chiedeva `kb list` (tutte e tre le colonne, poi `sed` per tenere
  solo DOING) e `kb view` (disegna il box intero, poi `grep` per tre interi). Tutte e due
  attraversavano le 96 card in `done/` chiamando grep+sed+basename **una volta per card**, per
  produrre due titoli e una riga di conteggi. È un costo pagato prima che Roberto possa
  scrivere, in ogni sessione, in ogni repo.
  - Ora chiede la colonna, non il board: `kb doing` + **`kb counts`** (comando nuovo — conta i
    file e si ferma: niente `stat`, niente sort, niente box, niente legenda).
  - **Misurato**, A/B alternato sullo stesso carico macchina, 3 giri sul board vero:
    vecchio **2.534 / 2.917 / 2.579 s** → nuovo **0.074 / 0.075 / 0.074 s**. ~34×, ~2,5 s in
    meno a ogni avvio di sessione. Output identico a meno del separatore dei conteggi.
  - **`kb counts` rispecchia la selezione dei board di `_board`** (aggregata fuori da un board
    riconosciuto, questa altrimenti): numeri diversi dal box che una persona legge due righe
    sopra sarebbero peggio di numeri lenti. `test/test-kb-views.sh` li inchioda **uguali** —
    l'asserzione è l'uguaglianza con l'header di `kb view`, non una tripla scritta a mano, che
    passerebbe verde proprio il giorno in cui `_board` cambia cosa conta.
  - **Provato per mutazione, in un worktree usa-e-getta** (mai nel checkout dove si committa —
    § Parallel work): hook riportato a `kb list`/`kb view` → rosso; `_counts` che smette di
    contare l'archivio → rosso; `_counts` che conta i file `_archive-*.md` come card → rosso.
    Ripristino → verde. Tre su tre.
  - Il ratchet delle 300 righe ha fatto il suo lavoro e ha bloccato la crescita: la baseline è
    alzata **con la motivazione scritta dentro**, come il file stesso prescrive.

- **Il bundle per ChatGPT/web perdeva in silenzio ogni migrazione verso `engineering-reference`.**
  `bin/make-bundle.sh` includeva `rules/` ma non `skills/`. Claude carica una skill quando
  serve; ChatGPT non ha quel meccanismo — quel bundle **è** tutto il suo canone. Così il batch
  del 2026-07-14 (code style, testing, CI locale, merge discipline, review comments, repo
  setup, git hooks) e quello del 2026-07-30 (carded end-to-end, documentation, documentation
  budget) erano usciti da `rules/` e non erano arrivati da nessuna parte su quella superficie.
  Un puntatore a una skill non è un puntatore **lì**.
  - `skills/engineering-reference/skill.md` entra in `SECTIONS`. Costa una incollata, non un
    token per turno: la ragione per cui è uscito da `rules/` non vale per questo artefatto.
  - Verificato sul prodotto, non sullo script: bundle rigenerato, leak-check passato, entrambe
    le migrazioni presenti (1.052 righe).

### Changed

- **`rules/best-practices.md` -27 righe**: `Carded End-to-End`, `Documentation` e
  `Documentation Budget` passano alla skill `engineering-reference`, con due puntatori al loro
  posto. Stessa mossa già fatta il 2026-07-14 e per la stessa ragione — il controllo di
  Carded End-to-End è il gate `kb cover` dentro `test/validate.sh`, non il paragrafo. Il file
  sempre caricato scende da 17.628 a 15.300 caratteri (~-582 token stimati per sessione).

### Note

- **Un avviso della diagnosi precedente era sbagliato e va ritirato**: `hooks/bus-doorbell.sh`
  era stato segnalato lento (media 2.029 ms, picco 40.280 ms nei transcript). Misurato: **293 ms
  a freddo, 112 ms a caldo**. Quei numeri venivano da un test di carico lasciato girare da
  un'altra sessione (25 processi `while True: pass`, load average 45 su 18 core), non dall'hook.
  Nessuna modifica al doorbell: non aveva niente che non andasse. Lezione generale: un numero di
  performance misurato su una macchina satura misura la macchina, non il codice.

## [v2.24.0] - 2026-07-30

### Added

- **La regola "Playwright parla con Edge" smette di essere solo una frase.**
  `test/test-canon-guardrails.sh` proteggeva già il TESTO nel canone;
  `test/test-edge-only.sh` protegge il **comportamento**: nessun file di codice può avviare
  Chrome o Chromium (`chromium.launch`, `channel: chrome`, `--browser chromium`,
  `browser_type=chromium`). I file di documentazione sono esclusi, perché nominano Chrome per
  vietarlo e un gate rosso sul canone che lo istituisce sarebbe assurdo.
  - **L'eccezione è prevista e va scritta**: il marcatore `cross-browser: richiesto da Roberto`,
    sulla riga stessa o su quella prima, la dichiara. Vive nel diff che una persona legge, non
    nella memoria di chi l'ha introdotta.
  - **Limite dichiarato in cima al file, perché rende onesto il suo verde**: in roberdan-os
    oggi **non c'è una riga di codice Playwright**. Un PASS significa "nessuno ha violato la
    regola", non "abbiamo visto Edge funzionare". Il gate esiste perché il primo codice browser
    che entrerà qui non nasca puntato su Chrome.
  - Provato per mutazione in **tre** direzioni: codice che lancia Chromium → rosso col file e la
    riga; stessa riga con l'eccezione dichiarata → verde; clausola "se Edge manca, fermati"
    cancellata dal canone → rosso. Ripristino → verde.

## [v2.23.0] - 2026-07-30

### Added

- **La regola delle 300 righe smette di essere un consiglio.** `rules/best-practices.md` la
  dichiarava da tempo; nessuno la misurava, e **undici file l'avevano superata** — uno a 1606
  righe. `test/test-file-size-ratchet.sh` la fa valere come **ratchet**: i file già oltre soglia
  sono congelati in `test/file-size-baseline.txt` e passano, mentre un file **nuovo** oltre 300
  righe e un file baselinato che **cresce** fanno fallire il gate. Provato per mutazione nei due
  sensi: file finto da 350 righe → rosso; file della baseline allargato di 50 → rosso; ripristino
  → verde. Non chiede di spezzare i file esistenti, come la card dice esplicitamente.
  - La baseline dichiara il proprio numero di voci, così non la si può allargare di nascosto.
  - **Il gate ha subito preso il suo autore**: la correzione qui sotto faceva crescere
    `kanban/kb.sh` da 1606 a 1623 righe e il ratchet è diventato rosso. La baseline è stata
    alzata di proposito, in questo diff — che è l'uscita di sicurezza dichiarata nel file, non
    un aggiramento.

### Fixed

- **`kb pending` e `kb queue` erano ciechi dentro un worktree**, cioè esattamente dove il canone
  impone di lavorare. Deducevano il nome del progetto da
  `basename $(git rev-parse --show-toplevel)`, che in un worktree è
  `worktrees/<repo>/<card-id>`: il "repo" risultava chiamarsi come la **card**, il filtro non
  trovava niente e `kb queue` avrebbe fotografato una lista vuota. Ora c'è `_repo_qui`, che usa
  `--git-common-dir`. **Quinta istanza in due giorni della stessa famiglia** (il hook installato
  col percorso del worktree, `--git-dir` invece di `--git-path` in due file, il pre-commit inciso
  su un worktree rimosso): la forma è sempre *si chiede a git dove guarda, non si deduce dal cwd*.

## [v2.22.0] - 2026-07-30

### Changed

- **Il gate umano `todo → doing` non è più per singola card: è per LISTA.** Decisione di
  Roberto, presa dopo che gli avevo proposto una versione più stretta e lui ha chiesto questa:
  *"completa tutte le card che ci sono quando comincia una sessione e poi fermati, così io
  vedo solo se hai aggiunto altro."* Il gate esisteva perché un agente non si scegliesse il
  lavoro da solo, e il costo era che ogni card si fermava su di lui — il problema numero 3 della
  sua lista del mattino: *"si blocca in continuazione in attesa di me"*. Misurato lo stesso
  giorno: una sessione ha chiuso una card, rilasciato `4.8.1`, e si è fermata. Non era rotta:
  obbediva.
  - `kb queue` fotografa all'inizio sessione le card `todo` **del repo in cui sei** (una board
    ne tiene di più d'uno, e una coda che li mescolasse farebbe partire lavoro altrove).
  - `kb next` prende la successiva **senza chiedere**, una per volta — la regola "una card in
    corso per progetto" vale ancora dentro la coda.
  - L'approvazione scritta sulla card **nomina la sua origine** (`roberto (coda autorizzata,
    scatto del …)`), così una card partita da sola è distinguibile da un `--by roberto` digitato.
  - **La proprietà che rende questo uno spostamento del gate e non una rimozione**: una card
    creata **dopo** lo scatto non è nella lista e **non parte**. A lista esaurita `kb next` le
    elenca per nome. Se quel report tace, il gate è sparito — è l'unica cosa che Roberto ha
    chiesto di vedere, ed è asserita nei due sensi in `test/test-kb-queue.sh`.
  - Si revoca con `kb queue --stop`: si torna all'approvazione per singola card.
  - Lo scatto è agganciato a `hooks/context-inject.sh`, perché "quando comincia una sessione"
    è un momento che solo quel hook conosce.

## [v2.21.0] - 2026-07-30

### Added

- **Tre freni al board che cresce come le ninfee**, misurati prima di essere scritti. Il
  30 luglio 2026 il board aveva **33 card in attesa** dell'approvazione di Roberto, **sette
  in `doing`** di cui **quattro sullo stesso lavoro** aperte da sette giorni, e **zero card
  in corso sul progetto principale**, che ne aveva diciannove in coda. Nessun gate era rotto:
  mancavano. `review-budget.sh` limita i *giri* dentro una card e il meta-card budget limita
  le card di auto-miglioramento; niente limitava **quante** card esistono, **quanto vecchie**
  sono, e **quante** ne girano insieme sullo stesso progetto.
  - **Una card in corso per progetto** (`kb start` rifiuta il secondo fronte sullo stesso
    `repo:`). Il limite è per repo e non globale: due progetti in parallelo sono legittimi,
    il secondo fronte sullo stesso progetto è il modo in cui nascono i duplicati.
    Esenzione esplicita: `RDA_KB_ALLOW_PARALLEL=1`.
  - **Una condizione verificabile per card** (`kb add` rifiuta un'`acceptance` che contenga
    `;`, ` e `, ` and `, `1)`, `2)`). Una card in `doing` aveva 491 caratteri e nove
    condizioni in fila: card così non si chiudono mai, e la sessione dopo qualcuno ne apre
    un'altra sullo stesso argomento. **È un ratchet**: le card preesistenti non vengono
    toccate, perché un gate rosso il giorno in cui nasce è un gate che viene aggirato.
    Esenzione esplicita: `RDA_KB_ALLOW_MULTI_CLAUSE=1`.
  - **Le card in corso da più di 72 ore vengono chiamate per nome** nel dashboard, con il
    numero di commit sul loro ramo: `ferma da 20g e ZERO commit: bloccata o morta?`. Il
    board sa mostrare le card che esistono; non sapeva mostrare che una era morta, e una
    card morta aveva lo stesso aspetto di una viva.
- **`kb pending` mostra un progetto alla volta**, quello del cwd, e conta gli altri
  (`kb pending --tutti` apre l'elenco). Impilava otto board in un muro di 33 righe. L'effetto
  osservato non era che Roberto approvasse le cose sbagliate: era che non ne approvava
  nessuna. Il conteggio totale (`--count`, quello dell'hook di inizio sessione e del digest)
  **non** è ristretto dalla vista, ed è asserito: una vista che restringe anche il numero
  è una vista che mente.
- **`test/test-kb-diet.sh`**, agganciato a `validate.sh`, 13 asserzioni **in due direzioni**
  ciascuna: il caso rifiutato *e* il caso legittimo che deve passare. La prima stesura del
  test usava `kb ... | grep -q` sotto `set -o pipefail` e riportava "ACCETTATA" su tre gate
  che funzionavano — l'errore fortunato, perché quello opposto stampa PASS su un gate spento.

### Fixed

- **`bin/install-git-hooks.sh` non installava niente dentro un worktree**: chiedeva a git
  `--git-dir`, che in un worktree è `.git/worktrees/<nome>/` e non contiene hook. Il canone
  impone **un worktree per card**, quindi il controllo anti-fughe non era installato in
  nessun posto dove il lavoro avviene davvero. Ora usa `--git-path hooks`, come già fa
  `validate.sh`. Terza istanza della stessa famiglia in due giorni.
- **Il campanello del bus suonava due volte per lo stesso stato su Linux.** `stat -f`
  significa "formato" per BSD e "stato del **filesystem**" per GNU coreutils, dove **esce 0**:
  il fallback `stat -f … || stat -c …` non scattava mai, e la firma smetteva di seguire
  l'mtime dei singoli file. Passava su macOS, rosso su ubuntu-latest. Onestà sul metodo: la
  controprova tentata in locale con un finto `stat` GNU **non** ha riprodotto il difetto,
  quindi non provava nulla; la prova è il run su Linux vero.
- **`test/test-bus-mutants.sh` aveva un mutante silenziosamente in pensione.** La sua ancora
  era un rientro più `echo "bus: WARNING`, e ha smesso di essere unica quando `count` ha
  aggiunto il proprio avviso a un rientro più profondo: il testo a 8 spazi combaciava anche
  con gli ultimi 8 di quella riga, il conteggio passava a 2 e l'intera batteria si fermava
  con "anchor drift". Ora l'ancora nomina il ramo che muta. Eseguita per intero: **32
  mutanti catturati, 1 sopravvissuto** (`factory-drop`), registrato in `docs/findings.md`.

### Changed

- **`docs/findings.md`**: le cose vere trovate durante un lavoro vanno in una lista che
  Roberto smista, **non** in una card. Questo ribalta di proposito una regola nata da una
  cicatrice — la lezione vera era *"non dentro questa PR"*, ed era stata implementata come
  *"fanne una card"*. È così che nascono le ninfee.

## [v2.20.0] - 2026-07-30

### Added
- **The bus doorbell: `bus count` + `hooks/bus-doorbell.sh`.** Pull-only delivery had a
  cost nobody had paid yet — a message waits until somebody asks, and nobody asks, because
  nobody knows it is there. The fix is a **count, never the mail**: `bus count --repo R`
  prints one `card<TAB>role<TAB>n` line per role with unread mail and **nothing at all** when
  there is none, and a `PostToolUse` hook injects it as `hookSpecificOutput.additionalContext`
  inside a session that is **already running**. Nothing is woken, so property 1 is untouched;
  a number carries no claim, so the anti-laundering property the board protected is untouched
  too. Bodies still only arrive through `bus read`, stamped `UNVERIFIED`.
  Four properties are pinned, not promised (checks 49b–49d in `test/test-bus.sh` and the new
  `test/test-bus-doorbell.sh`, wired into `validate.sh`): it renders no body, it advances no
  cursor, it is silent at zero, and it is wired on `PostToolUse` **and nowhere else** — the
  test parses the generated settings snippet and fails on `Stop`, because a Stop hook that
  surfaces pending mail is one edit away from "if a message is pending, continue the session",
  the mutation `bus-protocol.md` names as the most dangerous.
  **The detail this would have shipped broken on:** for `PostToolUse`, Claude Code writes hook
  stdout to the debug log and the model never sees it (only `UserPromptSubmit`,
  `UserPromptExpansion` and `SessionStart` get stdout as context). A doorbell written with
  `echo` is a doorbell nobody hears and looks identical to a working one — so the JSON dialect
  is asserted.
  **Five mutants were run by hand**; four died immediately (cursor advanced, `.body` counted
  instead of matched, a preview added with an off-allowlist command, a preview on every view),
  and **one survived**: a body appended to the *repo-wide* summary line — the exact form the
  hook calls — passed the whole suite green, because the marker the test grepped for sat in an
  already-read record. The assertion now uses a marker unread *at the moment of the count*.
  Declared limits, both real: the count is role-agnostic (the hook is not told which role the
  session plays, so it also rings for mail *you* sent — the line names the recipient), and it
  is taken without the append lock (so it can be short by one mid-append; the cursor never
  moves, and `read` stays exact).
- **Three more bus roles: `architect`, `qa-gate`, `security`.** "Only two agents" was never a
  property of the design — it was the number of manifests that happened to exist. `_assert_role`
  knows no cardinality: a role is addressable if `bus/roles/<role>.json` exists and claims no
  human-gated action. `qa-gate` states in its own manifest that it is **not** the done-gate:
  moving a card stays `kb finish` by @thor. The genuinely unsolved case — two sessions playing
  the *same* role, which share one cursor and split the mail — is written up in
  `bus-protocol.md` § Two sessions, one job, with the two constraints any future design must
  respect (an instance id may key a cursor but never be an addressee; it must be
  machine-assigned, never self-chosen).
- **`bus/` — agent-to-agent messages, per repo and per card.** Generalises the improvised
  `/tmp` file channel two sessions used across seven review rounds of VirtualBPM PR #46.
  Append-only JSONL thread per (repo, card), per-role cursors, provenance stamped
  `UNVERIFIED` on every delivery, roles addressable only through a manifest that claims no
  human-gated action. Not wired into `AGENTS.md`, `hooks/` or `kb`: that is human gate #7.
- **`test/test-bus.sh`, wired into `validate.sh`.** The two load-bearing properties — never
  STARTS an agent session, never writes kanban state — are enforced **behaviourally**. (Not
  "never executes anything": that is the proxy round 6 rejected, and it is neither necessary
  nor sufficient — the bus legitimately runs `jq`, and two rounds of mutants started agents
  while executing nothing at all.) The enforcement is in two
  halves with different blind spots: a table of *argument paths* (not subcommand names) runs
  against a `PATH` of stub binaries with a canary, and an allowlist of external commands is
  derived from an xtrace of what actually ran, **each traced word normalised** (`VAR=` prefix
  stripped, basename taken) before matching. The normalisation is the boundary, not the
  stubs: a command invoked by **absolute path never consults `PATH`**, so the stub half
  cannot see it at all — a @rex mutant spawned 54 agents that way and passed every check.
  Coverage is a safety property rather than a metric here: the multi-agent checks run with
  the *real* `PATH`, so a branch missing from the table does not merely go unnoticed, it
  starts live sessions during the test run. `bus/*.sh` added to `SHELLCHECK_TARGETS`.
- **`test/test-bus-mutants.sh`, wired into `validate.sh`.** One deliberate violation per
  load-bearing check, each naming the property it breaks and the check that must catch it,
  plus DECLARED SURVIVORS that assert a known hole is still open and turn red the day it
  closes. No count is written here: the harness asserts its own mutant count and derives its
  own coverage, and a number restated in prose is the exact defect this repo spent eight
  review rounds on. Written
  because two reviews found their blockers by *executing* mutants while every reading of the
  same code passed it — a check that has never been seen to fail is not evidence. It found
  two bugs in its own assertions and one in `who`. A third, adversarial pass then found three
  more real holes: a payload in `close`/`open` (subcommands added after the path table and
  never added to it), kanban state written by **shell redirection** — which violated the
  property while satisfying its proxy, since no command is executed at all — and a `--peek`
  that consumed broadcasts, the one failure mode where a message is accepted, never
  delivered, and nothing prints an error. The gate now hashes the kanban tree around the run
  instead of only watching for `kb`. A fourth pass (@thor, refusing to mark the card done)
  found the same coverage hole in its third disguise: payloads in the **degraded** branches —
  the damaged-log warning in `who` and the lock-timeout refusal — passed the whole green suite
  while the canary recorded live `claude -p` calls. Those branches run in an ordinary test
  run, so the gate now sets up a damaged log, an empty log and a held lock and drives them on
  purpose. An error path is still a path. It also made the close/open checks run in their own
  repo: `who` deduplicates per role, so "a closed thread disappears from `who`" was true or
  false depending on which timestamp sorted last, and caught its mutant by hand while missing
  it in the harness.
  A fifth pass (@rex, third round) then found the same hole in its fifth disguise and with six
  live instances on the shipping commit: the **refusal** branches, which the table could not
  reach by construction — it only ever supplies valid roles, valid slugs, a passing leak-check
  and an empty registry. Extending the table a sixth time would have been another enumeration,
  so the polarity is **inverted**: the recording stubs are now first on `PATH` for the entire
  `test-bus.sh` run and the canary must be empty at the end. "Gated" stops meaning "somebody
  remembered to list this branch" and starts meaning "anything the suite exercises anywhere is
  measured". All six died to that one assertion.
  A sixth pass (@rex, fourth round) found the hole in the **seam between the two halves**:
  the canary is blind to an absolute path by construction, and the *allowlist* — the half
  that does see absolute paths — was still scoped to the table, so `"/tmp/x/claude"` inside
  a refusal branch passed the entire green suite and started a live agent. Two halves of one
  boundary have to be floors together, so every bus invocation in the suite now runs under
  `busrun` (`bash -x`, marked `PS4`) and the allowlist reads the trace of the whole run; a
  static check refuses any direct `bash "$BUS"` call site that would opt out of it. The same
  round did the same to property 2: the kanban fingerprint was hoisted run-wide, with the
  suite's own fixture writes bracketed *assert-then-write-then-rebaseline* — re-baselining
  without asserting first silently **adopts** the damage, which is how a mutant that wrote a
  card from a refused send survived a round.
- **Round 5 (@rex).** The fingerprint hashed one board while the resolver reached every
  registered one, so a `read` could stamp an approval line onto another repo's card and
  cite it (mutant 29 — the fingerprint now spans the whole reachable set). The last
  unaudited hop, log -> snapshot, is now counted under the same lock as the copy: a
  `tail -n 500` lost 100 of 600 records with exit 0 and every downstream count honestly
  agreeing (mutant 30, check 49 sends 600 and demands 600). `set -E` + an `ERR` trap, so
  a `set -e` abort can no longer exit 1 printing nothing at all. `python3` is no longer
  stubbed by the canary: `leak-check.sh` falls back to it wherever `private/.denylist` is
  absent, which is every machine but this one, so "ALL GREEN" was machine-local. And the
  limit of in-process tracing is now DECLARED rather than implied — `PS4=`/`set +x`/
  `exec 2>`/`BASH_XTRACEFD` blind check 45 from inside; check 48 is a three-line denylist
  for them, named as one, with `ps4-blind`/`setx-blind` kept as standing mutants.
- **Round 6 (@rex).** Six survivors, and the pattern behind all six rounds finally named:
  every blocker has been the property measured through the ONE cause somebody enumerated.
  kanban: `kb` -> a file. Delivery: rendered -> counted. Agents: EXECUTED -> **dispatched
  by writing a file something else executes**. `com.roberdan.rda-factory` is loaded in
  launchd and runs every `.md` in `$RDA_HOME/factory/queue` through a headless `claude -p`,
  so one `printf` starts a live session with no command, no PATH, no binary name and no
  kanban write: 14 files were planted in the real `~/.roberdan-os` during a green run
  (check 47b, mutant 33). The bus's DEFAULT board — `$ROOT/kanban`, computed from its own
  location — was hidden by the suite's own `RDA_KANBAN` override and got `approved_by:
  roberto` on 14 real cards, suite green (mutant 34). The 3MB body test asserted exit codes
  only, so `[0:4096]` truncated a 300KB verdict permanently while `send` printed "appended"
  (mutants 35, 36). The delivery audit counted instead of comparing, so losing record 300
  and repeating 299 was invisible (mutant 37). Permanence was asserted on ten records, so
  capping the log during a read destroyed 100 of 600 (mutant 38). And the tracing denylist
  is now described honestly: the hole is ANY stderr redirection of a compound command, not
  four tokens — `brace-blind` is kept as a declared survivor that fails the day it is
  caught.
- **Round 7 (@rex).** The factory queue was one of NINE surfaces that start an agent
  without executing one: `~/.claude/scripts` (a loaded launchd job runs it), `~/.claude/skills`
  (every future session reads it), the `~/.claude` and `~/.orca` hook/agent/command trees,
  **this repo's own `hooks/`** (run on every tool call, and the bus computes `$ROOT` itself),
  `~/Library/LaunchAgents`, `.git/hooks`, and `handoff/` (concatenated into the prompt of
  every `--dangerously-skip-permissions` agent — dispatch by prompt injection). Enumerating
  is now backed by inversion: a marker file before the first bus invocation, and nothing
  under any of those roots may be newer than it (0.5s over ~20k files; mutants 39-41).
  Three more ways to fool an assertion rather than pass it: a payload gated on a large
  thread fired UNDERNEATH every "whole run" floor, so the floors are repeated after the
  last bus invocation (check 50, mutant 43); check 34 compared the stored body against the
  file it handed the bus, and a mutant rewrote both, so the digest is now taken before the
  send and held in the test process (mutant 42); and the canary lived under a directory the
  bus is given, so a mutant ran `kb` and then erased the record of it — it now lives where
  the bus is never told and is tamper-evident rather than merely non-empty (mutant 45).
  Permanence is audited by content, not line count (mutant 44), and the dispatch hash
  follows symlinks like the kanban one already did.
- **Round 8 (@rex).** Five more, and the first one needed no new surface at all: check 45
  allowlists the command NAME (`awk '{print $1}'` of the trace) and three allowlisted names
  are interpreters, so `git -c alias.z='!/abs/claude -p wake' z` started **92 real agent
  sessions during a green run** - blind to the canary, the allowlist, the dispatch hash and
  the tracing denylist simultaneously. Check 45b now polices the arguments: no agent CLI as
  any word of any traced line, and the interpreter escape hatches (`git -c`, `alias.*`,
  `core.{pager,sshCommand,hooksPath,editor}`, `awk system(`, `sort --compress-program`)
  refused outright. Then the same lesson three times over: the sweep MARKER was placed in
  the directory the canary had just been moved out of, and was forgeable without knowing its
  name, so the reference is now a timestamp held in a variable of the test process; the
  nine-surface list was still a hand list, so the roots are now DERIVED - every plist in
  `~/Library/LaunchAgents` is parsed for the scripts launchd will run, the whole checkout is
  swept (five loaded jobs execute scripts inside it, and `>> "$ROOT/factory/run.sh"` is
  arbitrary code at 01:00), and `~/.claude` is swept wholesale minus a declared
  session-mutable denylist. `plugins` had been excluded on an assumption; measured, it
  changes zero times in 125s and carries hooks and skills. Mutants 46-52 plus a
  symlinked-queue fixture that finally pins `find -L`, a repo-shaped mutant sandbox so
  `$ROOT` has production shape, and a lock so two harnesses cannot corrupt each other's
  evidence now that the sweep watches the real `$HOME`. Also corrected here: the doc claimed
  `-newer` cannot see deletion. It can - unlinking bumps the parent directory's mtime. A
  declared limit that is not real costs as much as an undeclared one that is.
- **`read` audits its own delivery, and non-UTF-8 bodies are refused rather than repaired.**
  Nothing measured delivery *completeness*: every assertion used batches of one to three, so a
  20-record cap passed the whole suite while five messages became unreachable forever — `send`
  returned 0, `read` returned 0, the trailer reported the right count, and the cursor had moved
  past all of them on an append-only log. `read` now compares what it handed the renderer with
  what the renderer produced and refuses to advance on a mismatch. Separately, `jq --rawfile`
  substituted U+FFFD for undecodable bytes, so a latin-1 diff was silently rewritten while
  `send` reported success; "survives verbatim" had only ever been asserted with ASCII.
  The audit's first form was **downstream-only** — it counted the same file that fed the
  renderer, so anything the *filter* dropped was missing from both sides and both numbers
  agreed while both were wrong. It now counts the snapshot independently. The other silent
  loss is the cursor, where both counts agree by construction: `read` takes a validated
  test-only pause so the "message arrived mid-read" check stops being a race it wins twice
  out of three and becomes an invariant (the stored cursor is the snapshot's line count),
  caught 10 times out of 10.
- **Broadcast addressing (`--to all`) so the bus works with three or more agents.** Reaches
  every role except the sender; nothing is consumed, so a broadcast is delivered in full to
  each role rather than taken by whoever reads first — a bus, not a work queue. `all` is a
  reserved addressee: nothing may send *from* it or read *as* it, and an `all.json` manifest
  is refused rather than disambiguated. Cursors now index raw records instead of the filtered
  stream, so widening the delivery rule re-delivers (visible) rather than drops (silent).
- **`bus close` / `bus open` — a finished thread stops delivering and keeps every word.**
  Asked whether the bus should delete handled messages to save tokens; measured instead: the
  cursor already means a read costs only what is new (2037 bytes, then 95 on the next read),
  so deletion saves nothing at read time and costs the reasoning the kanban does not keep.
  `close` gives the actual thing wanted — no delivery, gone from `who`, new mail refused —
  as a **record appended to the log**, not a rename or a side file, so the state is in the
  same auditable history as everything else.
- Regression tests for everything the @rex review found by execution: path traversal through
  `--repo`/`--card`, missing flag values, a laundered approval read off a **denied** card,
  moving git refs cited as evidence, concurrent-append corruption, partial reads of a damaged
  log, delivery lost to a message arriving mid-read, fail-open leak-check, and `who` missing a
  role that had only read.

## [v2.19.4] - 2026-07-25

### Added
- **All agents now resist creating new source and test monoliths.** New hand-written files target
  at most 300 lines and split by responsibility first. Existing oversized files are not forced
  through unrelated refactors, but may grow only with an explicit task-relevant reason.
  Generated, vendored, lock, snapshot, data and migration artifacts stay exempt.

### Changed
- **Playwright automation now uses Microsoft Edge (`msedge`) only.** Agents no longer silently
  fall back to Chrome or Chromium; an unavailable Edge installation is a visible blocker.
  Cross-browser execution remains possible only when Roberto explicitly requests it.
- **The on-demand engineering reference now matches the progressive policy.** Its recommended
  `FileSizeGuard` distinguishes new files, justified legacy growth and technical exemptions
  instead of contradicting the canon with an absolute all-files block.

## [v2.19.3] - 2026-07-24

### Fixed
- **`bin/sync.sh --install` printed a pointer block that no longer matched reality.** The
  installed `~/.claude/CLAUDE.md` block was trimmed from 10 lines to 3 during the v2.19.2
  `/doctor` pass (that file is resident context in *every* project, and under `~/GitHub` the
  committed `~/GitHub/CLAUDE.md` already carries the detail) — but the generator still emitted
  the long version as "the canonical slim block". No functional risk: `--install` **refuses** to
  overwrite an existing `~/.claude/CLAUDE.md`, so nothing was ever restored behind anyone's back.
  It was a copy-paste trap for the next fresh install. Generator and installed block are now
  byte-identical (verified with `diff`), and the printed note says *why* it stays this short.

## [v2.19.2] - 2026-07-24

### Changed
- **The Meta-Card Budget norm moved out of the always-loaded rules file.**
  `rules/best-practices.md` is symlinked into `~/.claude/rules/`, so every word of it is
  resident context in **every** project and every tool — but the Meta-Card Budget governs only
  the roberdan-os kanban. The full rule now lives in `kanban/README.md § Meta-card budget`
  (which until now only pointed back at `best-practices.md`, so the norm had two homes and one
  of them was empty), with a one-line pointer from `AGENTS.md` § Loop Protocol so it stays
  reachable from the always-loaded canon — same wired-end-to-end bar as everything else.
  Cost: ~364 est. tokens of resident context saved per session, in every project.
  **Honest tradeoff:** `kanban/README.md` is not in `bin/make-bundle.sh`'s `SECTIONS`, so the
  norm no longer reaches the ChatGPT/web bundle — where `kb` is never run anyway. Nothing else
  in the canon points at the old location (grepped).

### Notes
- **Where this came from — a `/doctor` pass on the Claude Code setup, not a planned change.**
  Findings worth recording, all measured rather than estimated from memory:
  - Install is healthy (native 2.1.218, latest on channel; no npm leftovers; every settings file
    parses; all 9 agents have valid, non-colliding frontmatter).
  - **49 of 74 user skills have never been invoked once in 565 startups** (~1.8k est. tokens of
    listing in every session). Roberto chose to disable only 3 of them — `ship-pr` (a duplicate
    of the repo's own `ship`), `dev-cleanup` and `roberto-mode` (both had **no frontmatter
    description at all**, so the skill router could never match them: present but unreachable).
    The ~46 gstack/Orca skills stay enabled by his call. Disabling is via `skillOverrides` in
    `~/.claude/settings.json` — the skill files are untouched on disk.
  - **`test/leak-check.sh` takes 3m33s**, and it runs as a blocking `pre-commit` hook — a commit
    in this repo cannot complete inside a 2-minute timeout. Recorded here because it is not
    documented anywhere and it looks like a hung commit the first time you meet it.
  - Two findings left as warnings, no change made: the shell alias `claude` carries
    `--dangerously-skip-permissions`, which makes the configured `auto` permission mode moot; and
    one `PreToolUse` hook on Bash hit its 10s timeout during the scanned window.

## [v2.19.1] - 2026-07-24

### Fixed
- **CI: `actions/checkout@v4` → `@v5`.** GitHub now force-runs v4 on Node 24 and annotates every
  run with a Node-20 deprecation warning. Green either way; the pin is corrected so the annotation
  stops and the action is not left on a version GitHub is retiring.
- **Paper § Reproducibility said "private remote".** Factually wrong since v1.2.0 (4 July): the
  remote has been public under MIT for three weeks. Corrected, and the licence posture now stated
  where a reader actually looks for it — public under MIT, with `NOTICE` recording what MIT does
  not convey (name, persona, voice) and `SECURITY.md` the reporting channel. The v1.0.0 privacy
  incident narrative still says "private remote" and is left alone: on 1 July the remote *was*
  private, and that is accurate history. Paper bumped to v1.3 with an updated date, since its
  content changed.

### Notes
- **Release tags are now complete; GitHub Release *pages* deliberately are not.** Every version in
  this file has a git tag as of v2.19.0 (six were backfilled). Only 13 of 32 tags have ever had a
  Release page — that was never the convention here, and backfilling 19 of them would notify
  watchers about three-week-old commits for no benefit. Tags carry the numbering; Release pages
  stay occasional.

## [v2.19.0] - 2026-07-24

### Added
- **`NOTICE` — the identity is not part of the MIT grant.** The repo has been public since
  v1.2.0 under MIT, with `identity/voice.md`, `identity/operator.md` and
  `identity/twin-persona.md` committed. Nothing stated that MIT — a *copyright* licence —
  never conveyed the right to use a living person's name, persona or voice, nor to present a
  fork or its output as Roberto or as his digital twin. `README.md` only *advised* replacing
  the identity layer, and `bin/identity-init.sh` deliberately leaves the reference prose in
  place, so a fork that stops halfway is still running Roberto's persona. `NOTICE` states the
  reservation explicitly (declaratory, not an added restriction — the MIT grant on the code is
  untouched), points forkers at `identity-init.sh`, and carries the AI-disclosure expectation
  from `agents/twin.md`. Linked from `README.md` § License.
- **`SECURITY.md` — private reporting channel with a real scope boundary.** Declares what is a
  vulnerability here (privacy-boundary bypasses, code-execution paths in `hooks/ bin/ test/
  factory/ kb.sh`, agent-supply-chain prompt injection, meta-loop guardrail bypass, secret
  handling) and what is not (bad agent advice, third-party tools, the documented salted-denylist
  tradeoff). GitHub private vulnerability reporting **enabled on the repository** so the
  advisory link the file gives actually works — verified `{"enabled":true}` via the API, not
  assumed. Also states plainly that installing this system executes its code on your machine.

## [v2.18.0] - 2026-07-22

### Added
- **Plain language toward Roberto is now a NON-NEGOTIABLE rule, enforced at the system-prompt
  level.** The § Communicating contract existed since v2.x but was advisory prose buried in a
  222-line JIT-loaded file, and Roberto reported — plainly — that he still struggled to follow
  what agents told him and asked of him. The rule is now a row in `behavior/roberto-mode.md`
  § NON-NEGOTIABLE (answer first in plain words → what's needed from him and why → technical
  detail below), backed in Claude Code by a new output style (`~/.claude/output-styles/
  roberto-plain.md`, activated via `outputStyle`), which edits the system prompt every turn
  instead of hoping a prose rule survives context-rot. Honest limit: the output style is
  Claude-Code-only; Copilot/Codex/web carry the rule through the canon alone.
- **`kb cover` — the plan→card gate the canon promised.** Fails red on any normative clause in a
  plan with no card and no written decision, wired into `test/validate.sh`. Companion to the new
  `rules/best-practices.md` § Carded End-to-End (a requirement that never becomes a card is
  invisible to `kb`, `@thor`, the merge-gate and CI simultaneously) and § the three structural
  holes that let a false done through.
- **Train/val split gate in `eval/`** so a canon change can't be judged by the fixtures it was
  written against.
- **Rejected-proposal buffer in `evolve/`** — the changelog watcher stops re-proposing what was
  already declined.
- **`bin/copilot-local`** — opt-in Copilot CLI against a local Ollama model (BYOK).

### Fixed
- **`kb` done-gate is mechanical, not rhetorical**: `--thor` evidence must actually resolve
  (commit/file/test output), not merely be non-empty.
- `kb add` refuses unknown flags instead of silently swallowing them into the card title.
- `kb pending` hardened; card-ID collisions handled.
- `kb` warns when `RDA_KANBAN` silently points at a board other than the repo's own.
- `leak-check`: plain-word terms are anchored and binaries skipped — fewer false positives
  without loosening the gate.
- Copilot's kanban tool now reads the same board source as the `kb` CLI.

### Changed
- The `CLAUDE.md` pointer block is now the canonical slim source, killing drift between the
  global pointer and the repo canon.

_Release hygiene note: `v2.16.0` and `v2.17.0` were written to the changelog but never tagged.
This release tags `v2.18.0` at HEAD; the two intermediate versions remain changelog-only._

## [v2.17.0] - 2026-07-11

### Added
- **Session-lifecycle contract (session-cost efficiency pilot, 2-week measurement window).**
  Following measured Copilot session-cost signal (247.4:1 input:output token ratio, top-session
  concentration, 18/47 sessions growing ≥1.5x across quartiles; Baccio/Board convergence:
  phase-as-session is the key lever), `loop/loop-protocol.md` § "Session-as-phase-container" is
  now the **single canonical home** for the lifecycle contract: `/compact` continues the same
  phase; `/new` at natural phase boundaries, before a heavy skill/attachment-bearing step, or
  before changing model/effort; cutting a session changes the *container*, not the task (a small
  durable handoff packet — see `handoff/handoff-protocol.md` — carries the task across the cut).
  `rules/best-practices.md` now carries a one-line pointer instead of restating the contract,
  removing the duplication an independent @rex review flagged.
- **Owned always-loaded context footprint reduced.** The prior commit (6763bb3) touching this
  contract landed net *larger* than its parent (296+28=324 lines across the two files
  `bin/make-bundle.sh` and Copilot actually load unconditionally: `rules/best-practices.md` +
  `.github/copilot-instructions.md`) despite the stated goal being context slimming. This release
  corrects that: the same two files now total 319 lines — tied with the pre-session-lifecycle
  parent (96c1cf5) and down 5 lines from 6763bb3, while the full contract detail still lives in
  full in `loop/loop-protocol.md` (JIT-loaded only, not part of the always-on budget).
  `rules/best-practices.md` remains above its own internal ≤200-line aspirational target
  (291 lines) — that overage predates this change and 6763bb3; a full prune is out of scope here.
- **`test/validate.sh`: mechanical invariant for the shortened `.github/copilot-instructions.md`
  pointer.** That pointer now reads "full 7-item list is AGENTS.md § Human gates" instead of
  restating all seven gates inline (safer — the old inline copy had silently drifted and omitted
  gate #7). A new deterministic assertion proves root `AGENTS.md` exists and its `## Human gates`
  section still lists exactly seven sequentially-numbered gates, so the pointer can never again
  silently point at a stale or incomplete list.

### Fixed
- **`hooks/copilot/extension.template.mjs`: corrected an inaccurate SDK comment.** The prior
  comment claimed Copilot hooks "expose only workingDirectory, toolName, toolArgs and error" —
  contradicted by `@github/copilot-sdk@1.0.6`'s own types (`onSessionStart` carries
  `sessionId`/`timestamp`/`source`/`initialPrompt`; `onSessionEnd` carries
  `reason`/`finalMessage`/`error`; `onPostToolUse` carries a `toolResult` with
  `textResultForLlm`/`resultType`/optional `sessionLog`/`toolTelemetry`). The comment now states
  only the defensible fact: none of that is a *validated* token/usage field — tool-result bytes
  and `toolTelemetry` are proxies at best, not a verified correlation to context size — so this
  release still ships **no** telemetry, threshold, or warning built on top of them (deferred, as
  originally scoped; not a walk-back).
- **`test/test-pending.sh`: deterministic SIGPIPE false failure.** Under `set -o pipefail`,
  `printf ... | grep -q ...` can legitimately exit 141 (grep exits at first match, killing
  `printf` mid-write via SIGPIPE) — not a flake, a guaranteed race between two specific
  constructs. Rewritten as here-strings (`grep -q ... <<<"..."`), which never pipe. Verified
  deterministic pass across repeated runs.
- **`test/test-federated-kb.sh`: credential-vacuum probe read contaminated ambient env.** The
  CI/sandbox environment can inject its own `GIT_CONFIG_PARAMETERS`/`GIT_CONFIG_*` (e.g. a
  `gh`-auth git-credential trampoline); the test's "outside" canary leg didn't strip these before
  asserting no vacuum, so it could pass or fail on unrelated ambient config rather than the
  `factory/runner-sandbox.sh` isolation actually under test. Both probe legs now strip ambient
  `GIT_CONFIG_*` first. `factory/runner-sandbox.sh`'s real isolation logic was unchanged and
  independently confirmed sound — this was a test-harness hygiene bug, not a security defect.
  Both of the above were previously, incorrectly, called "flaky"/reported as the sole failure in
  kanban evidence; they are deterministic and both are now fixed. Corrected record: full
  `bash test/validate.sh` is genuinely green, confirmed across repeated consecutive runs.

### Note (accurate version citation)
- The parent commit's message referenced "Copilot CLI v2.16" — that conflated roberdan-os's own
  version (2.16.0) with the installed GitHub Copilot CLI binary (1.0.70 at the time). Corrected
  here rather than by amending the already-pushed/reviewed commit: roberdan-os and the Copilot CLI
  binary version independently; the AGENTS.md-native-loading behavior itself was accurately
  documented and is unaffected.

### Reviewed
- **@rex:** original APPROVE-WITH-FINDINGS (context-budget self-violation + duplicate policy
  HIGH; inaccurate SDK comment MEDIUM; version citation LOW; missing mechanical invariant for the
  shortened human-gates pointer LOW/high-value; validation-truth and kanban-evidence findings).
  All findings addressed in this release; see items above.

### Pilot caveat
- This is a **2-week measurement pilot** for the session-lifecycle contract. No token or dollar
  savings are claimed yet — that requires the pilot's own before/after session data.

## [v2.16.0] - 2026-07-10

### Added
- **Native GitHub Copilot adapter — operational near-parity in stock Copilot CLI, no separate
  SDK host.** roberdan-os now drives Copilot through its own first-class extension surface
  instead of relying on skills + a global instructions pointer alone. Generated deterministically
  from the canon by `bin/sync.sh`, installed collision-safely (never overwrites, always symlinks
  so it tracks the canon):
  - **Copilot custom agents** — one wrapper per `agents/*.md` that lists provider `copilot`,
    in Copilot's authoritative frontmatter (description required; canonical tools mapped to
    Copilot aliases `read/edit/execute/search/web`; coarse model tier mapped to a concrete id,
    which degrades gracefully to the session model if unavailable). Symlinked into
    `~/.copilot/agents/<name>.md`, skipping any pre-existing same-named file.
  - **User-scoped extension** `~/.copilot/extensions/roberdan-os/extension.mjs` — the native
    binding of the provider-neutral `hooks/`, sourced from `hooks/copilot/extension.template.mjs`
    (repo root baked at emit time; a runtime `RDA_OS` env still overrides for forks):
    - `onSessionStart` → `hooks/context-inject.sh` (fresh durable context injection).
    - `onPreToolUse` → `hooks/main-guard.sh` + `hooks/bash-guard.sh`, mapped to Copilot
      `allow/ask/deny`. A guard can only tighten, never loosen (safe actions defer to Copilot's
      own permission flow). **A guard failure maps to `ask`, never a silent success-shaped allow.**
    - `onPostToolUse` → `hooks/autofmt.sh` (best-effort format after edits, never blocks).
    - `onPostToolUseFailure` → ephemeral observability log (no hidden model steering).
    - `session.idle` / `onSessionEnd` → the Claude "Stop" chain (pre-completion-gate → verify-done
      → post-task-sync → always-on auto-checkpoint), throttled + serialized to avoid duplicate/
      reentrant runs.
    - Safe, globally-unique namespaced tools: `roberdanos_kanban` (board reads + gated
      add/start/finish/block — the todo→doing Roberto gate and doing→done @thor evidence gate are
      enforced by `kb.sh` itself, never bypassed), `roberdanos_pause`, `roberdanos_resume`,
      `roberdanos_verify_done`, `roberdanos_doctor` (wiring diagnostic; reports gbrain MCP presence
      without ever reading/echoing the secret-bearing `mcp-config.json`). No arbitrary shell proxy.
  - `bin/sync.sh --install` extends to `~/.copilot/agents` (`RDA_COPILOT_AGENTS_DIR`) and
    `~/.copilot/extensions` (`RDA_COPILOT_EXT_DIR`), same no-silent-overwrite posture as the skills
    install; a total no-op when `~/.copilot` is absent. `mcp-config.json` remains read-only (WARN if
    gbrain missing) — Copilot owns that file and it holds secrets.
  - `test/test-copilot-adapter.sh` (wired into `validate.sh` + the tool-coverage gate): deterministic
    emission, frontmatter/tool/model mappings, collision-safe install, no-write-when-absent,
    real ESM load against a stubbed SDK, PreToolUse guard mapping (deny/ask/allow + fail-safe),
    idle dedup/throttle wiring, and the privacy check on `mcp-config.json`.

### Known limitation (operational near-parity, stated honestly)
- **No bit-for-bit Claude `Stop` parity.** Copilot exposes `session.idle`/`onSessionEnd` only
  *after* a turn's final assistant message is produced, and there is no proven Copilot hook that
  can block or rewrite that message. So `verify-done` / `pre-completion-gate` run as **advisory
  warnings + side effects** in Copilot — they cannot hold back a premature "done" claim the way the
  Claude Stop hook's blocking output can. The always-on pause/resume checkpoint, the PreToolUse
  guards (which *can* deny/ask before execution), context injection, custom agents, and the native
  tools are full-fidelity; the completion gate is advisory only.

### Reviewed
- **@luca (security):** no high-confidence vulnerabilities — command-injection (argv-only spawn,
  no shell string, no exec proxy), secret exposure (`mcp-config.json` probed only for the `gbrain`
  token, never read out), install safety (collision-safe, no-op when `~/.copilot` absent), human-gate
  preservation, and path/symlink handling all refuted.
- **@rex (ecosystem/code):** two findings, both resolved before commit — (Medium) `onPreToolUse`
  did not forward the session `workingDirectory`, so `main-guard.sh` could fail *open* on a relative
  path when the extension cwd ≠ the session repo → fixed by threading `cwd` into `applyGuard`, with a
  relative-path-on-`main` regression test; (Low) the `validate.sh` tool-coverage asserts hardcoded the
  substring `roberdan-os/platforms/`, false-failing worktree/fork installs → fixed to a structural
  `…/platforms/copilot/{agents,extension}/…` match.
- **@thor (done-gate, fresh context):** round 1 REJECTED on empty/broad catches + a silently-dropped
  autofmt failure in the extension (criterion 3 "no hidden failures"). Resolved: every catch now binds
  the error and routes it to a single stderr `diag()` sink (stdout stays JSON-RPC-only), autofmt
  non-zero exits are reported (not swallowed), and `test-copilot-adapter.sh` gained a guard against any
  bare empty catch / silent no-op handler regressing.

## [v2.15.1] - 2026-07-09

### Fixed
- **`pre-completion-gate.sh` promoted from private `~/.claude` to canon** (`/doctor` run
  found it: the Stop-event done-gate hook — checks open PRs, orphan worktrees, rogue
  convergio runners, uncommitted changes before a completion claim — existed only in
  Roberto's local `~/.claude/hooks/`, hardcoded to that path, invisible to a fresh
  `roberdan-os` clone despite firing on every turn. Now lives in `hooks/`, wired into
  `bin/sync.sh`'s generated Stop-hook chain (first hook, matching its live position).
  `~/.claude/hooks/pre-completion-gate.sh` and `~/.claude/rules/best-practices.md` (a
  second drifted private copy found the same way, stale since May) are now symlinks
  into this repo — no more silent divergence between what Roberto's machine runs and
  what the canon documents.
- **`test-factory-kb.sh` flaky under system load — root cause fixed.** `validate.sh` failed
  once, then passed clean standalone and on a full re-run: the test fixtures dispatch a
  trivial mock `claude` binary (`exit 0`/`exit 5`) through the real `factory/run.sh`, which
  wraps it in a hard wall-clock `timeout`/`gtimeout` — fixtures set `timeout: 5`, tight enough
  that ordinary scheduler contention (many concurrent processes, as in this very session) can
  occasionally exceed it even though the mock exits instantly. Bumped all 14 fixture
  `timeout:` values from 5s to 30s (pure test-data slack, doesn't change what's asserted);
  confirmed with 3 consecutive full `validate.sh` green runs, including one running
  concurrently with other load.

## [v2.15.0] - 2026-07-09

### Added
- **Plain-language gate — agents must communicate FOR Roberto, not for a log** (Roberto's
  observation: explanations, updates, and the decisions he's asked to make are often too dense or
  jargon-heavy to follow, with implications left unstated). A first-class behavioral rule, on par
  with "No False Done", in `AGENTS.md § Behavior` + `behavior/roberto-mode.md § Communicating`,
  so it travels to every tool (Claude, Copilot, Codex):
  - **no unexplained jargon** — when Roberto will read it, say what a SHA / flag / term *means*;
  - **every decision carries its implications in his terms** — what A vs B leads to, cost, risk,
    and a recommendation; a question he can't answer for lack of context is the agent's failure to
    explain, not his to understand;
  - **end-of-task = one plain sentence** (what happened + what's needed from him and why), technical
    detail below, never as the headline;
  - **answer first, depth after** (progressive disclosure);
  - **"I don't understand" is feedback about the writing** — re-say it simpler, not louder.
  Framed as an accessibility and respect commitment.

## [v2.14.2] - 2026-07-09

### Changed
- **A couple of the coaching methodologies now live in the default way of thinking** (Roberto's
  question "does it make sense to add some of these to how roberdan-os itself thinks?"). Two were
  worth it and are **integrated into the existing mother-rule steps**, not added as new rituals:
  - step 2 (first principles) gains **distrust of absolutes** — "always / never / impossible / we
    have to" is a System-1 shortcut, not a fact; test it;
  - step 4 (prove yourself wrong) gains a **Kahneman bias-check** — a fast, confident answer is
    exactly when to slow down and name the likely bias.
  Deliberately *not* added to the default: GROW, reframing, one-question-at-a-time — those are
  interpersonal *coaching* moves; making them default would turn every reasoning into a ceremony,
  which is the "pretend to think" the mother-rule exists to prevent. Discipline is adding *little*.

## [v2.14.1] - 2026-07-09

### Changed
- **`@coach` now composes with the whole roberdan-os arsenal instead of being an island** (v1.1,
  Roberto's point: "doesn't it make sense to put in the coach things we already have, used this
  way?"). New "Compose — don't reinvent" section makes the coach a conductor that reaches, *in
  coaching form (as questions)*, for what already exists:
  - **Roberto's own decision-lens first** (`identity/voice.md`) — reflect *his* criteria back
    (relationship-first, bias-to-action, purpose/impact, protect family, right-altitude) instead
    of importing external ones. The best coaching question is often his own value made explicit.
  - the **`thinking-toolkit` repertoire turned into questions** (one/two-way door, base rates,
    regret-minimization, Cynefin, theory-of-constraints, Chesterton's fence);
  - the **discovery/validation skills** when they fit (`premortem`, `problem-validation`,
    `focus-group`); and the other **agents** called in (`@board`, `@socrates`) — not replaced.

## [v2.14.0] - 2026-07-09

### Added
- **`@coach` — a maieutic thinking coach** (Roberto's /goal). Helps him reason, decide, and
  challenge himself *by drawing the answer out* — a light GROW loop (Goal → Reality → Options →
  Will), one good question at a time. Deliberately distinct from the reasoning agents it sits
  beside: `@socrates` deconstructs (cold), `@board` red-teams (adversarial), `@coach` is the
  warm inside voice that **guides, never decides** (the call stays Roberto's, gate #5) and never
  red-teams. Registered in AGENTS.md + the global `~/.claude/CLAUDE.md` block, symlinked into
  `~/.claude/agents` (invokable now). @thor-gated PASS.
- **`thinking-toolkit` enriched with Kahneman + coaching tools.** The bias section is now framed
  around **Kahneman's System 1 / System 2** (*Thinking, Fast and Slow* — Nobel, empirical) with
  the catalogue extended (availability/recency, loss aversion/framing, overconfidence/planning
  fallacy). New **Coaching & reframing** section: GROW, well-formed outcome, meta-model (language
  discipline against "everyone/never/I have to/impossible"), reframing. Feynman first-principles
  kept as before.
  - **Honesty (evidence-first):** the reframing/meta-model techniques have NLP roots but are kept
    for what they *demonstrably do* (grounded in CBT / goal-setting), **not** given NLP's
    scientific authority, whose theoretical claims don't hold. Neither cargo-culted in nor
    scrubbed out — the honest middle.
- **`kb repo <name>` — a per-repo dashboard** on top of the kanban: git state (branch, dirty,
  last commit, ahead/behind vs origin), open non-bot PRs, and that repo's cards grouped
  doing/todo/done. Handles local-only repos (no origin) without aborting. Test-covered.

### Changed
- **Canon: `kb start` at the BEGINNING of the work, not retrospectively** (AGENTS.md +
  kanban/README). A card should *live* in `doing` for the duration of the task so `doing` shows
  what's actually in progress — instead of the observed pattern where agents batch add+start+finish
  at the end and `doing` is always empty.

### Known follow-up (non-blocking, from @thor)
- `claude-ai-skill/roberto-mode/THINKING.md` (a hand-curated, intentionally non-sync'd web export)
  is now stale vs the Kahneman/coaching toolkit — re-derive by hand on a future pass.

## [v2.13.0] - 2026-07-09

### Added
- **`kb` board now shows what each card is, not just its ID.** The 3-column box stays compact
  (ID + repo, for the at-a-glance layout), and a **legend below it** lists every *active* card
  (todo + doing) as `<id> (<repo>) — <title>`. The legend lives outside the box on purpose:
  titles are long and may be non-ASCII (accents), which would desync the box's fixed-width
  column separators if placed inside a cell. Done cards are omitted (many, and finished). So
  the aggregated board is now readable — you can tell `260708-120132` is "Decidere: OS-isolation
  floor (ADR-0002)" without opening the card.

## [v2.12.1] - 2026-07-08

### Fixed
- **`kb init` pre-commit hook hung and scanned the wrong repo.** The generated hook called
  `leak-check.sh` with no args, and leak-check's *default* target is roberdan-os's own tree
  (`git ls-files` in its own ROOT) — so on every commit of *another* federated repo it
  re-scanned all ~200 roberdan-os files (slow, hung past 2 min on repos with large blobs) AND
  never actually checked the committing repo's files. Two-part fix:
  - `test/leak-check.sh` gains an **`--only <files…>`** flag: scan exactly the given files, not
    the default tree. Backward-compatible — validate.sh and `make-bundle.sh` (no flag) are
    unchanged.
  - the `kb init` hook template now passes the repo's **staged files** (`git diff --cached`,
    absolute paths) to `leak-check.sh --only`, so it checks the right files, fast (0.2s vs a
    2-minute hang), and skips cleanly when nothing is staged.
  - Regenerated the already-installed hook in every kb-init'd repo (Fabrica, the-standing-egg,
    MirrorBuddy, trading-os). Verified: a commit's pre-commit now runs in ~0.24s.

### Note (machine ops)
- **AGENTS.md/CLAUDE.md pointers added to the personal federated repos** (Fabrica,
  ConvergioEdu2030, the-standing-egg, trading-os): thin pointers to the canon that tell any agent
  working there to operate in roberto-mode and **track the plan on the `kb` board**. The shared
  team repos (convergio, MirrorBuddy) were left untouched — they have their own project canon and
  imposing a personal workflow on a team repo isn't appropriate.

## [v2.12.0] - 2026-07-08

### Changed
- **gbrain: dropped the local fork — now runs the official upstream.** The "fork"
  (`Roberdan/gbrain`, commit `f7376b11`) was just a 2-line patch adding `bge-m3` to the ollama
  recipe. It's no longer needed: `~/.gbrain/config.json` declares `embedding_dimensions: 1024`
  explicitly and the official `garrytan/gbrain` respects it, so `ollama:bge-m3` embeds fine with
  **zero code changes**. Verified end-to-end on the real DB (11.769 pages, untouched): search
  returns identical-score results and embed writes 1024-dim chunks. The `~/gbrain` clone now
  tracks only the official remote (fork remote removed), pinned to the `official` branch @
  v0.42.53. **Honest caveat:** upgrading to the latest official (v0.42.57) is blocked by a failing
  DB migration (v0.32.2) on this DB — a separate, unresolved gbrain issue, not forced.
- **`bin/check-embedder.sh` rewritten** for the fork-free world: instead of looking for a code
  patch (there is none), it now verifies the three things that actually keep local-first recall
  working — config declares `bge-m3` + `1024` dims, ollama serves `bge-m3` at 1024 via its
  OpenAI-compatible endpoint, and the clone has no fork remote. Shellcheck-clean, green.

### Note (machine ops, not repo code)
- **`trading-os` integrated into both memory systems**: registered + indexed in gbrain (93 pages,
  auto-scoped via `.gbrain-source` pin) and federated into the kanban (`kb init` — board
  scaffolded, card columns excluded via `.git/info/exclude`, leak-check pre-commit hook). It was
  absent simply because both systems are explicit opt-in and it had never been registered.

## [v2.11.0] - 2026-07-08

### Added
- **Approval inbox — the system now tells Roberto when he's needed (push, not just pull).**
  Answers the standing question "how do I know when something waits on me?". Three parts:
  - **`kb pending [--count]`** — one place aggregating, across every registered repo: gated todo
    cards + unapproved learning candidates + open PRs awaiting review/merge (**bot PRs excluded** —
    Dependabot/renovate/actions are noise, not decisions; an agent-authored PR like copilot-swe-agent
    is *kept*, it needs a merge decision). `--count` is a fast LOCAL total (todo+learning, no `gh`).
  - **`bin/pending-digest.sh`** + launchd `com.roberdan.rda-pending-digest` (twice daily, 09:00 +
    18:00) — pushes a macOS notification + refreshes `~/.roberdan-os/pending-digest.txt` with the
    full picture (PRs included) when something waits. Runs from no cwd, iterates the registry.
  - **SessionStart badge** — `📥 N in attesa` at the top of every fresh session (fast local count).
  - `test/test-pending.sh` (validate §8e): count correctness, approved-learning excluded, digest
    writes+exits-0, PR bot-filter predicate. @thor-gated (twice — see below).
- **First real meta-loop promotion.** With the v2.10.0 loop live, the 2 genuine learnings that
  surfaced (the leak-check "a safety check you must remember to run is not a control" scar + the
  "recurring gap is DISTRIBUTION not architecture" lesson) were human-approved and promoted to the
  vault — the loop's first end-to-end cycle in production. The 619-item boilerplate backlog was
  archived (not promoted).

### Fixed
- **@thor caught two real defects the green tests didn't** (the qualitative done-gate earning its
  keep): (1) an eval-limitation framing that was quantitatively fine but interpretively one-sided
  (immunized the canon from its null result) → made symmetric; (2) the approval inbox's PR leg was
  dead on the *push* path (digest runs from no repo, so a cwd-scoped `gh` check always failed) and
  the docs over-claimed PR coverage → PRs now aggregate registry-wide, bot-filtered, and the docs
  match what the code delivers.

### Known follow-ups (honest, non-blocking — from @thor's PASS)
- `test/test-pending.sh` §5 pins a *copy* of the bot-filter jq predicate rather than asserting
  against `kanban/kb.sh` directly; extract it to a shared var so a future filter edit can't drift.
- `kb pending` PR discovery iterates repos that have a `kanban/` dir, not raw registry membership;
  a registered repo without a board would have its PRs silently skipped (no miss today).

## [v2.10.0] - 2026-07-07

Two parallel worktree+PR streams (the new norm — see below), each @rex-reviewed and @thor
qualitative-gated, merged into main. Addresses two of the honest gaps the v2.7.1 README disclosed.

### Added
- **The self-improving meta-loop now actually promotes** (PR #2, closes the biggest prose-vs-reality
  gap). Before: `learn→ontology` captured only boilerplate, `distill` wrote `class: TODO` always,
  `curate` skipped TODO → **zero promotions ever**. Now: `learn/classify.sh` is a real deterministic
  classifier over ADR-0001's 5-class taxonomy (no network/LLM, CI-safe); `distill` emits a real
  class; `curate` promotes human-approved candidates. Promotion stays **human-gated** (`approved:
  true` is Roberto's). `test/test-metaloop.sh` proves capture→distill→approve→promote end-to-end.
  - **Approval gate hardened** (rex HIGH): the gate now reads the YAML frontmatter block only
    (`_frontmatter()`), so a captured signal whose body begins `approved: true …` can no longer
    self-promote past the human gate. Regression-tested.
  - **Backlog unstuck** (rex MED): `learn/backfill-classify.sh` re-classified the real 619-item
    `class: TODO` backlog — 617 legacy `- session … cwd=` boilerplate pings archived, 2 real
    learnings surfaced for approval, **0 promotions, vault untouched** (backup taken first).
  - **Ephemera filter fixed**: it missed the bulleted legacy form (`- session … cwd=`), so pings
    slipped into quarantine misclassified — now dropped, with a unit case that also proves it
    doesn't over-match a real sentence mentioning "session"/"cwd".
- **Realistic eval fixtures + honest mechanism limit** (PR #1). 5 new task fixtures
  (`eval/tasks/13-17`) grounded in real public repo work (release-confirm-CI, resume-whole-plan,
  surgical-edit, review-comment, warm-intro), privacy-safe. `eval/README.md` now states plainly
  that the harness injects the canon as *passive prepended text* — which under-represents the live
  system (selective activation, hooks, subagents) — and **holds both hypotheses open**: the null
  result may be an impoverished measurement OR the canon genuinely adding less value than hoped.
  Honest state: "we don't know yet." No numbers fudged (the 4–6 result stands). Fixture inventory
  reconciled: 17 exist, 10 ever run, 7 not-yet-run.
- **Parallel-work norm** (`rules/best-practices.md` v3.6.0): parallelizing inside one repo = one
  `git worktree` + branch + PR per stream, disjoint file ownership, shared merge-prone files bumped
  once sequentially, each stream ends in a PR (CI → @rex → @thor → merge). Never two writers on one
  checkout. Born from today's concurrent-session scar.
- **Intake gate + qualitative done-gate** (v2.9.0, folded in): clarify ambiguous goals before
  executing; @thor validates goal fulfilment in substance, not just green tests. Both proved their
  worth this release — @thor rejected an eval framing that was quantitatively fine but
  interpretively one-sided, catching a dishonesty the mechanical checks couldn't.

### Changed
- README "Real vs. aspirational" map updated: the `learn→ontology` meta-loop moves from
  *scaffolding* to *works (human-gated)*; only `evolve` (never fired) and deliberate auto-promotion
  remain in the scaffolding column.

## [v2.9.0] - 2026-07-07

### Added
- **Intake gate — clarify ambiguous goals before executing (default behavior, every tool).**
  Roberto's directive: when a goal/prompt/command is ambiguous or under-specified in a way that
  would change the result, ask targeted clarifying questions **before** starting, so the output
  is precise. Canonized in `behavior/roberto-mode.md` (new § Intake + workflow step 0 + the
  NON-NEGOTIABLE row reworded from "Ask when unclear" to "Clarify at intake"), surfaced in
  `AGENTS.md § Behavior`, and in the `roberdan-os` block of the global `~/.claude/CLAUDE.md`
  (so it's live in every session without opening roberto-mode). Balanced against total autonomy:
  it's an **entry** gate, not a permission gate — resolve what evidence or an obvious default can
  answer (state the assumption), batch the rest into 2-4 sharp questions, and once the goal is
  clear execute autonomously without asking again. Propagates to Copilot/Codex via `AGENTS.md`.
- **@thor validates goal fulfilment qualitatively, not just quantitatively** (thor v1.3 + the
  `verify-done` skill). The done-gate's cardinal question, run *before* the mechanical gates: did
  the work fulfil the goal/order **in substance and with quality** — not just "N tasks done,
  tests green"? Map each goal-clause ↔ what was delivered; a silent gap, a thinner-than-asked
  result, or "the letter not the spirit" is a FALSE done even with every box ticked. The
  judgment stays evidence-bound (goal-clause ↔ artifact mapping, never a vibe-pass, never
  satisfied by volume of output). Closes the loop with the intake gate: intake defines the goal
  precisely, thor validates the outcome against that precise intent.

## [v2.8.0] - 2026-07-07

### Added
- **`bin/install-hooks.sh` — the repo now self-installs its Claude Code hooks.** Closes the last
  "manual step" gap in reusability: `clone → bootstrap → install-hooks --apply → sync --install`
  is a complete, zero-hand-edit setup on a fresh machine. The script merges the *generated*
  five-event hook snippet (`platforms/claude/settings-hooks.json`) into the real
  `~/.claude/settings.json` **additively** (only adds roberdan-os entries not already present,
  dedup by command — never touches the user's other hooks), **idempotently** (second run is a
  no-op), with a timestamped **backup** first and a post-write JSON-validity check. Dry-run by
  default; `--apply` writes. `RDA_CLAUDE_SETTINGS` overrides the target for testing.
  `test/test-install-hooks.sh` proves all five properties; wired into validate.sh §8d.
- **bootstrap + README + QUICKSTART** now present the three-command install (bootstrap →
  install-hooks → sync --install) instead of hand-editing JSON. The only remaining manual step
  is the one-line pointer block in the operator's *personal* `~/.claude/CLAUDE.md` (curated
  config the engine deliberately never overwrites).

### Note on the reusability boundary
Three layers, made explicit: **(1) public engine** (agents, skills, hooks, kb, canon, install
scripts) — fully in-repo, installed by the three commands; **(2) forker identity** (`identity/`)
— the one directory a fork edits; **(3) operator's personal machine config** (the global
`~/.claude/CLAUDE.md` with absolute paths / gbrain fork / launchd job names, the `gbrain-ops`
runbook, the confidential dossier) — deliberately *not* in the public repo, by the
privacy/identity split. Replicating layer 3 across the operator's *own* machines is a separate
private overlay, not a defect in the public repo.

## [v2.7.1] - 2026-07-07

### Fixed
- **H1 (rex, HIGH): generated `settings-hooks.json` carried literal `$RDA_OS`** — a variable
  defined nowhere. A verbatim merge on a fresh install/fork expanded it empty
  (`/hooks/main-guard.sh`) and the security guards died silently. `bin/sync.sh` now expands
  the repo root at generation time (as `bootstrap.sh` already did); same expansion for the
  codex README snippet. New `validate.sh` guard: the emitted snippet must contain no
  unexpanded `$VAR` (`ok: settings-hooks.json fully expanded`).

### Added
- **Audit addendum §5** in `docs/report-2026-07-07-best-practices-2026.md` — third-session
  independent verification of the v2.7.0 release claims: actor map corrected (THREE concurrent
  sessions, not two), 6/6 release claims re-verified empirically, AGENTS.md session-tax measure
  updated to the post-compression truth (161 lines / ~1.259 words ≈ ~1.7k tokens; the §4 table
  reported the pre-compression 183 / ~2.9k).
- **Tool-receipts emitter wired for real** (closes the rex HIGH "declared but unwired" gap,
  Roberto's go): `loop/receipt.sh` appends JSONL receipts `{ts, task, cmd, exit, artifact,
  note}` to the loop cursor; the Stop-hook auto-checkpoint emits a mechanical per-turn receipt
  (`session.jsonl`) automatically. Placement is opt-in-safe (in-repo `.agent-state/` only where
  already ignored; else `$RDA_HOME/state/receipts/<repo>/`). `test/test-receipts.sh` (5 cases)
  wired into validate.sh §8c; loop-protocol + thor gate #10 updated to the real contract.
- **Docs freshness pass** (audit H1-H4/M1-M10/L1-L4, all findings verified): bootstrap now
  installs the `kb` symlink and points its manual steps at the generated five-event hook
  snippet; QUICKSTART adds the `bin/sync.sh --install` step (its ALL-GREEN promise was false
  for forkers); README status/tables/prerequisites refreshed (python3 required); `docs/plan.md`
  banner'd as historical; kanban/USAGE document `kb pause/resume` + federation; scheduling
  cadence corrected (evolve = Sat 02:00); factory-protocol dead flag `RDA_FACTORY_PARALLEL`
  marked planned-not-implemented; ARCHITECTURE notes the native CLAUDE.md symlink path.
- **validate.sh**: agent frontmatter lint now requires `effort:` (so the new field can't
  silently drift off an agent) + §8c receipts gate.

## [v2.7.0] - 2026-07-07

### Added
- **Context & Token Economy** section in `rules/best-practices.md` (v3.5.0): always-loaded
  instruction files ≤200 lines with the "would removing this cause mistakes?" per-line test,
  just-in-time retrieval over pre-loading, subagent exploration isolation, prompt-cache
  discipline (stable prefix, model+effort picked once), durable state on disk over
  in-conversation state, runaway loop = cost incident. (Anthropic context-engineering +
  Claude Code best practices, 2026.)
- **Agent supply-chain rules** in `rules/best-practices.md` § Security: third-party skills/MCP
  servers reviewed before install and re-reviewed on update; no unreviewed MCP server in a
  session that can read `private/`; blast-radius over prompt-level pleading. (Snyk ToxicSkills
  2026-02; OWASP Agentic Top 10 2025-12.)
- **Provenance gate in @thor** (v1.1, gate #10): verify *how* an artifact came to exist (git
  history, re-run/traceable test output, loop-cursor receipts), not just that it exists — anti
  reward-hacking. (EvilGenie benchmark + Anthropic evals guidance, 2026.)
- **Tool receipts in the loop cursor** (`loop/loop-protocol.md`): each step records what ran and
  what it returned (command, exit code, artifact SHA) — a transcript is context, not a recovery
  log; verification probes live state, never grades the transcript. (Managed Agents, 2026-04.)
- **Delegation-not-impersonation guardrail in @twin** (v2.1): machine-readable trails sign as
  the operator's assistant; EU AI Act Art. 50 disclosure norm (operative 2026-08-02) if a fully
  automated external interaction is ever enabled — draft-not-send unchanged.
- **Root `CLAUDE.md → AGENTS.md` symlink**: Claude Code loads the canon natively in-repo
  (official recommendation for AGENTS.md-native repos); forkers get oriented without the
  SessionStart hook installed.
- **`effort: xhigh` frontmatter** on board/socrates (subagent frontmatter supports effort in
  2026) — the effort doctrine's hardest capability-sensitive calls, now wired.

### Fixed
- **`hooks/autofmt.sh` was a silent no-op**: it read `CLAUDE_FILE_PATH`, an env var the modern
  hook API never sets (hooks receive JSON on stdin). Now parses `.tool_input.file_path` from
  stdin, legacy env var kept as manual-run fallback.
- **`settings-hooks.json` snippet drifted from the canon**: it lacked the SessionStart
  context-inject and the Stop auto-checkpoint that AGENTS.md § Pause & Resume declares
  always-on. Now emitted complete, plus a PreCompact checkpoint so durable state is saved
  *before* the context window is compressed (SessionStart with no matcher re-injects after
  compact too).

### Changed
- Best-practices research pass 2026-07-07 documented in
  `docs/report-2026-07-07-best-practices-2026.md` (research synthesis, gap analysis, applied
  vs proposed — incl. the ~6.4k-token global `~/.claude/CLAUDE.md` slimming proposal left to
  Roberto), with the full-repo audit (efficiency, effectiveness, autonomy, reliability,
  cost/token). **Two sessions ran the same goal concurrently** and converged: session B's
  disjoint-file pass (`docs/report-2026-07-07-best-practices-2026-session-b.md`) landed the
  complements below; @rex audited both (APPROVE-WITH-CONCERNS → concerns fixed in this release).
- **Session B (same pass, disjoint files):** AGENTS.md § Pause & Resume + § Privacy compressed
  ~30% at equal contract; **zero-progress screen** as gate #0 in @thor (v1.2) and
  `verify-done.sh` (cheapest predicate first: durable state must have changed at all);
  explicit hook timeouts + `disable-model-invocation` passthrough in generated skill wrappers
  (ship gated); Convergio demoted to optional observer everywhere in roberto-mode (no
  done-gate deadlock on a daemon that isn't running); context-inject cry-wolf fix (loud
  PAUSED banner only on explicit `kb pause`); `curate.sh` atomic per-candidate vault commits;
  `verify-done.sh` parses the real top-level manifest version; `effort:` frontmatter across
  all agents (baccio/luca/rex/thor/twin high, wanda medium, board/socrates xhigh).
- **@rex concerns closed:** duplicate `effort:` keys deduped (concurrent-edit artifact);
  loop-protocol receipts + thor provenance gate now state the honest wiring
  (`.agent-state/*.jsonl` is a declared format with **no in-repo emitter yet** — phase-commit
  evidence + kb audit lines are today's receipts); the ≤200-line rule carries its own scope
  note (this file is bundled verbatim for ChatGPT/web → prune-before-add duty);
  `test/test-autofmt.sh` added and wired into validate.sh (the silent-no-op class of bug now
  has a regression gate).

## [v2.6.0] - 2026-07-07

### Changed
- **Resume the WHOLE plan, not just the paused task.** The pause checkpoint is single-task by
  design, and on a session restart the agent tunneled on it — it drove only the checkpointed
  next-step and looked at the rest of the backlog only when prompted. Fixed on two levers: (1)
  `kb resume` now prints the checkpoint **plus the live backlog** (todo + doing) with a reminder
  that the checkpoint is the re-entry *point*, the board + `handoff/latest.md` are the *scope*; (2)
  AGENTS.md § Pause & Resume reworded — "continua/riprendi" means re-hydrate and drive the whole
  plan forward, every open thread and pending decision, with human gates still applying on resume
  (`todo->doing` stays Roberto's; never auto-cross a gate).

### Fixed
- **`kb init` no longer pollutes a shared repo's history, and ignores the right file.** Two coupled
  bugs (Roberto's decision, option B): (1) it appended federation ignores to the committed
  `.gitignore`, so federating a repo wrote Roberto-machine-only noise into shared history — now they
  go to the **local `.git/info/exclude`** (self-sufficient on any machine, unlike a global
  `core.excludesfile`, without touching shared git state; shared across worktrees via the common git
  dir). (2) It ignored `handoff/latest.md` (roberdan-os's *tracked* canon file) instead of
  `handoff/resume.md` (the ephemeral per-repo pause checkpoint `kb pause` actually writes) — so the
  rule matched a file that never exists in siblings. This was the exact stale-rule mess found in
  Fabrica/MirrorBuddy/convergio, whose committed `.gitignore` lines came from the old `kb init`.
  Test strengthened: asserts `resume.md` is excluded and the committed `.gitignore` is never touched.
  Federation design + migration docs aligned to the new mechanism (the gate to federate a *shared*
  team repo stands — it's now an organizational, not a git-history, decision).

## [v2.5.0] - 2026-07-06

### Added
- **"No False Done" — the cardinal reliability rule** (`rules/best-practices.md` v3.4.0, top of
  file; reinforced in the `verify-done` skill). Never claim done/verified/working/green/released
  until the evidence for THAT claim is observed end-to-end: a claim needs evidence for itself
  ("released" ⇒ CI green on the release commit confirmed, not "I pushed"), whole-system not just
  the touched part, "should/probably" ≠ "is", prefer a mechanical gate that carries the evidence,
  and on a wrong claim say so first with the fact. Documents the real 2026-07-06 miss (v2.4.0
  announced released while its CI was red). The lever is verification + gates, not temperature.

## [v2.4.2] - 2026-07-06

### Fixed
- **Skill/agent wrappers broke skill loading in Copilot CLI.** `bin/sync.sh` wrote the frontmatter
  `description:` as an *unquoted* YAML scalar. Descriptions contain `: ` (colon+space) and
  apostrophes, so any such description failed to parse (`mapping values are not allowed`) — silently
  dropping the affected skills at load time (`focus-group`, `premortem`, `problem-validation` were
  the casualties). The generator now emits every description as a double-quoted, escaped scalar
  (new `yaml_dq` helper, applied to both skill and agent wrappers). Added a regression guard in
  `test/test-sync-install.sh` that emits into a clean temp dir and asserts every generated wrapper
  description is a quoted YAML scalar.

## [v2.4.1] - 2026-07-06

### Fixed
- Completed v2.4.0: `kb pause --auto` (the lean variant the Stop hook and the test depend on) was
  added to `kanban/kb.sh` but left unstaged in the phase-2 commit, so on `main` the auto-checkpoint
  hook and its CI test were broken (green locally, red in CI). Now committed.

## [v2.4.0] - 2026-07-06

### Added
- **Pause / Resume — never lose work on a break or reboot.** A canonical, cross-tool contract
  (any `AGENTS.md` reader inherits it) plus tooling:
  - **`kb pause ["next step"]`** writes a lean, per-repo, gitignored checkpoint
    (`<repo>/handoff/resume.md`, cwd-scoped like `kb`/`kb handoff`): the next-step note + mechanical
    state (HEAD, dirty count, doing card). **`kb resume`** reads it (`--all` aggregates across repos,
    `--done` clears it). Per-repo by design — same shape as the federated kanban.
  - **Always-on lean auto-save:** a `Stop` hook (`hooks/auto-checkpoint.sh`) runs `kb pause --auto`
    after every turn — refreshes mechanical state, **preserves the human note**, overwrites one file
    (fixed sections, never a growing log). Even an unannounced crash loses at most the current turn.
  - The `SessionStart` context hook surfaces a pending checkpoint at the top, so a fresh session
    (post-reboot) immediately notices "continua" work.
  - Canon: `AGENTS.md § Pause & Resume` (trigger phrases, safe-point rule). Design:
    `docs/plan-2026-07-06-pause-resume-checkpoint.md`.

## [v2.3.0] - 2026-07-06

### Added
- **The aggregated `kb` view is a real three-column kanban.** `kb all` / `kb g` (and `kb` run
  outside any repo) now render the TO DO / DOING / DONE board shape aggregated across every
  registered board — each card still tagged with its `repo:` — instead of a flat list. `_board`
  gained `--all`: it collects all columns from home + the registry, sorts DONE newest-first
  cross-repo, and sums archived-goal counts. The flat-list `_all` was removed (dead code once
  both dispatch sites route to `_board --all`). `kb list`/`ls` stays the plain vertical list.

### Fixed
- **Font-independent board alignment.** The board's `│` separators didn't line up with the rows:
  the header used emoji (📋 🔵 ✅), which render 2 cells wide but `printf %-*s` counts as 1, and a
  missing `repo:` rendered as an em-dash (`—`, 3 bytes / 1 cell) — both desync the columns and both
  are font/terminal-dependent. The board is now ASCII-only (1 byte = 1 char = 1 cell), so alignment
  holds on any font, terminal, or bash version (verified: every `│` column at an identical position).

## [v2.2.1] - 2026-07-06

### Fixed
- **CI-only failure of `test-federated-kb` (green on macOS, red on Linux CI).** `_mtime`
  (`kanban/kb.sh`) and `_lock_epoch` (`factory/lib.sh`) tried BSD `stat -f %m` before GNU
  `stat -c %Y`. That order is fine on macOS but broken on Linux, where `stat -f` means
  `--file-system` and prints multi-line garbage for `%m`+file instead of failing cleanly — so
  `_mtime` returned junk, the `mtime|root` row corrupted, and `kb handoff`'s aggregated view
  rendered empty, failing the gate only in CI. Inverted to GNU-first (macOS's `stat -c` fails
  cleanly, so the BSD fallback still runs). `test/validate.sh` now also surfaces the
  `test-federated-kb` output on failure instead of hiding it behind a "see …" pointer — a
  failing gate must show its evidence, which is what pinned this down.

## [v2.2.0] - 2026-07-06

Non-breaking: the kanban goes federated and a multi-CLI dispatcher lands **wired but provably
dormant** (external-runner risk stays zero — it is hard-wired to refuse until a reviewed
OS-isolation floor exists). Reviewed by @rex (APPROVE) + @thor (PASS), every design fix proven
empirically.

### Added
- **Federated kanban + dormant multi-CLI dispatcher** (phases 1–6 of
  `docs/plan-2026-07-05-federated-kanban-multi-cli.md`). All additive; external-runner risk stays
  **zero** (the dispatcher is wired but hard-wired to refuse).
  - **Read-path** (`kanban/kb.sh`): cwd board resolution, `kb all`/`kb g` aggregated view across a
    local-only registry (`~/.roberdan-os/kanban-registry`), `kb handoff` (per-repo or aggregated).
  - **`kb init`**: idempotent per-repo privacy scaffolding — gitignore card columns, de-track
    already-committed card content, scan local history (pushed → refuse/human-gate #4, local-only →
    warn), install a leak-check pre-commit hook, register the board.
  - **`runner:`/`human_gates:` fields + `kb lint`** (`kanban/lint-cards.sh`): declarative CLI/model
    intent label (no execution change) + a lint enforcing `human_gates: ⇒ runner: human-only`.
  - **Atomic claim + repo locks** (`factory/lib.sh`): `mkdir`-based, keyed `<repo>+<id>`, with a
    stale sweep. `verify_card`/`note_card`/`resolve_model` extracted from `run.sh` into `lib.sh`
    (behavior-preserving), sourced by both `run.sh` and the dispatcher.
  - **Restricted dispatcher, dormant** (`factory/dispatch-runner.sh`, `factory/runner-sandbox.sh`,
    `factory/runner-shims/`): reachable via `kb dispatch`, with a fail-closed preflight. Preflight
    #5 (OS-isolation floor) and #8 (leak-check tier active) are **hard-wired to refuse** — #5 is a
    code constant no config can flip — so **every** external dispatch refuses until a reviewed code
    edit (phase 7) lands the OS floor.
- **Migration record** (`docs/federated-kanban-migration-2026-07-05.md`): roberdan-os migrated in
  place; MirrorBuddy cards kept in place with `kb init` on MirrorBuddy left as an un-crossed human
  gate.

## [v2.1.0] - 2026-07-05

Non-breaking follow-up to v2.0.0: a new quality rule, a rewired weekly watcher, and
Fable-5 reasoning guidance — all additive.

### Added
- **"Wired End-to-End" rule** (`rules/best-practices.md` v3.3.0 + `verify-done` skill): a feature
  that exists but is never reached from a live path is not done — it's dead code that looks done.
  Trace entry→caller→feature; prefer a mechanical proof (coverage gate) over human vigilance.
  Grounded in real failure modes from this repo's work.
- **Fable-5-scoped reasoning guidance** (`behavior/thinking-toolkit.md § Running on Fable 5`):
  effort doctrine (`high` default / `xhigh` for the hardest `board`/`socrates` calls / `low`
  routine), act-sooner-survey-less, clean final output, and a `reasoning_extraction` landmine
  note. Deliberately scoped — NOT written into the `model:opus` agent bodies where it would
  misfire. Effort knob also documented in the global model policy. From Anthropic's
  Prompting-Claude-Fable-5 doc, which validates the repo on 5 axes; addyosmani/agent-skills
  linked as a reference (not imported — redundant + over-prescription degrades Fable).
- Research + design docs for the multi-CLI thread (`docs/plan-2026-07-05-*`): CAO tested and
  rejected, kanban-as-handoff validated, the federated-kanban + sandboxed-dispatcher design
  (reviewed by @rex + @luca; dispatcher stays dormant until OS isolation).

### Changed
- **evolve watcher** (`evolve/watch.sh`): moved to **Saturday 02:00** (launchd catch-up runs a
  missed job at next boot/wake if the Mac was off) and now **drops a kanban card** per changelog
  novelty instead of a skeleton draft — any CLI (Claude, Copilot) executes it on its next run.
  No headless `claude -p`; the card is the cross-tool handoff. `RDA_KANBAN_TODO` override added
  for testability. Tested end-to-end (5 sources → 5 lint-clean cards).

## [v2.0.0] - 2026-07-05

### Changed (BREAKING)
- **Engine / identity split.** All forker-editable identity now lives in one place:
  `identity/` (voice, operator profile, twin persona, `identity.conf`). Engine files no
  longer embed identity, so `git merge upstream/main` stays conflict-free on engine files
  forever. See docs/plan-2026-07-05-engine-identity-split.md.
- **`behavior/roberto-voice.md` → `identity/voice.md`** (moved; content unchanged except
  one internal self-reference, `roberdan-twin` → `twin`). Update any local reference.
- **`agents/roberdan-twin.md` → `agents/twin.md`**, invoked as **`@twin`** (was
  `@roberdan-twin`). The role prose is now operator-neutral engine; the persona moved to
  `identity/twin-persona.md`.
- **`behavior/roberto-mode.md`** keeps its name but is now pure engine discipline; the
  operator profile (who he is, how he communicates, the Italian phrase table, named-agent
  ecosystem, tool stack) moved to `identity/operator.md`.
- **`RDA_HOME`** env var introduced (default `~/.roberdan-os`) — set it once to relocate the
  runtime home. The `RDA_` prefix is now documented as a **fixed engine namespace**, not
  identity, and is intentionally not parametrized.
- `bin/sync.sh` reads `identity/identity.conf` at generation time (deterministic) to inject
  the operator's name into the generated wrappers; behavior references in the wrappers point
  at the new `identity/` paths. Eval `canon:` wiring repointed to `identity/voice.md`
  (fixture prose itself unchanged — it stays instance test data).

### Removed
- **`bin/fork-identity.sh`** (shipped v1.3.0) — its `git mv`+`sed` rename model is exactly
  what caused perpetual merge conflicts; deprecated after one minor version because the
  model was wrong, not because it was buggy. Replaced by `bin/identity-init.sh`, which
  scaffolds `identity/` and renames no engine file.

### Added
- `identity/` — the ONLY forker-editable surface (`README.md` ownership contract,
  `identity.conf`, `voice.md`, `operator.md`, `twin-persona.md`, `profile-pointer.md`).
- `bin/identity-init.sh` — dry-run-by-default fork scaffolder (`--slug`/`--name`/`--apply`,
  same origin-refusal rail as its predecessor).
- `test/test-fork-merge.sh` — the merge-clean proof, wired into `test/validate.sh`:
  an identity-only fork merges simulated upstream engine edits with **zero conflicts**;
  the soft guarantee (an `identity/` file both sides edit can still conflict, small and
  localized) is documented in the test, not asserted.
- `docs/QUICKSTART-for-forkers.md` rewritten for the `identity/` workflow.

### Migration
- Run `bin/bootstrap.sh` (re-symlinks agents incl. `twin.md`, prunes the stale
  `roberdan-twin` symlink). `RDA_HOME` defaults to today's path, so existing factory/dossier
  state is untouched. Full steps: docs/plan-2026-07-05-engine-identity-split.md § Migration.

### Note
- `claude-ai-skill/roberto-mode/` (packaged skill) is unchanged — a published named artifact,
  out of split scope.

## [v1.3.0] - 2026-07-05

Feedback from an external review of the public repo (via Grok) converged with the earlier
focus-group finding: forking this for yourself was underspecified as "adapt one file."

### Added
- `bin/fork-identity.sh` — dry-run-by-default script that renames the `roberdan-twin` agent,
  `RDA_` env prefix, `~/.roberdan-os` home dir and `behavior/roberto-voice.md` across the live
  canon for a fork, in one pass. Refuses `--apply` against the real `Roberdan/roberdan-os` origin
  without `--force`. Deliberately leaves `docs/archive/`, dated plan/report docs, `eval/tasks/`
  fixtures and `claude-ai-skill/roberto-mode/` untouched (mechanical rename would corrupt them) —
  prints them as a manual-review checklist instead. Tested end-to-end on a scratch clone
  (renamed + `test/validate.sh` still ALL GREEN afterward).
- `docs/QUICKSTART-for-forkers.md` — the 5-step fast path (clone → bootstrap → fork-identity.sh →
  write your own voice/privacy files → validate).

## [v1.2.0] - 2026-07-04

Prepared the repo for public release.

### Changed
- **Kanban card content is gitignored** (`kanban/todo/`, `kanban/doing/`, `kanban/done/`) — same
  split as `private/`. The `kb` tool and protocol stay versioned; the live task/business content
  in individual cards never enters git. `kanban/README.md`/`AGENTS.md`/`README.md` updated to
  document the split.
- **History purged** of all previously-committed kanban card content (`git filter-repo`), including
  three cards with unredacted product-compliance detail that should never have been committed —
  found and removed before the repo went public. A stale, already-merged remote branch carrying
  the same pre-purge history was deleted rather than rewritten.
- Added `LICENSE` (MIT) and a public-facing README (prerequisites, install, gstack/gbrain setup).

### Fixed
- Same class of privacy incident as the one noted in v1.0.0 — cards from a different session
  slipped past denylist-based leak-check (which only catches known terms, not business-sensitive
  prose it was never told about) and reached `main`. Structural fix this time: the content class
  is gitignored, not just its exact known strings.

## [v1.1.0] - 2026-07-03

Kanban cards now say what they're about, not just what they're called.

### Added
- **`repo:` mandatory field on every kanban card** — names the `~/GitHub` repo/scope the card
  is about (or `personal` for non-code work). `kb add` requires `--repo`; `kb start` refuses a
  card whose `repo:` is missing or still `FILL:`, same discipline as `dod:`/`acceptance:`.
- Board/`kb list`/`kb history` render `(repo)` next to every card so scope is visible at a
  glance — the board never truncates the id itself (the key you pass to `show`/`start`/`finish`),
  it only appends the repo tag when it fits the column width; legacy cards with no `repo:`
  degrade to `(—)` instead of crashing.
- `test/validate.sh` gained a frontmatter lint for `kanban/todo`+`kanban/doing` cards (mirrors
  the existing agents/skills sections), scoped to active cards only.

### Fixed
- `_board` crashed (`set -e` + `pipefail`) on a kanban with zero archive files — the bare
  `_archive-*.md` glob passed straight to `grep` failed to open the literal non-matching
  pattern and killed the whole script. Never seen on the real board (always has ≥1 archive);
  found while testing the `repo:` display against a clean fixture.

## [v1.0.0] - 2026-07-03

First tagged release: the system graduates from "under construction" to versioned operation.
Everything below was verified end-to-end (test/validate.sh, 10 gate sections) and, where noted,
reviewed by @rex and validated by @thor with evidence.

### Added
- **Cross-tool canon distribution** (tool-independence pass): global `AGENTS.md` pointer fabric
  (`~/GitHub`, `~/.codex`, `~/.config/opencode`) installed by `bin/sync.sh --install`; roberdan-os
  skills distributed to Claude *and* Copilot CLI (`~/.copilot/skills`, SKILL.md portable standard);
  hermes + Warp documented (both read AGENTS.md natively); ownership-aware tool-coverage gate in
  `test/validate.sh`.
- **Gated kanban** (`kb`): DoD+acceptance per card, human gate todo→doing, @thor+evidence gate
  doing→done, `kb block`, audit trail on every start attempt; detail-on-demand views
  (`history`, `archive`, `plans`/`plan`, `sched` — launchd schedules + factory state in one place).
- **Agent factory**: unattended headless task queue with retry → `failed/` escalation (a failing
  task can never be filed as done), headless @thor verify pass against the card's DoD, result
  sync back onto the kanban card, and a hard model policy (sonnet default, `model: opus` opt-in,
  allowlist-clamped — never the account default).
- **Eval harness** (`eval/`): A/B canon-vs-no-canon with blind judging, 12 fixtures (2 derived
  from this system's own real failures), agent-agnostic via `RDA_EVAL_AGENT_CMD`.
- **Meta-loop**: learn (capture→distill→quarantine, daily), evolve (weekly changelog watcher over
  claude/copilot/codex/hermes-agent/warp, draft-only proposals), all launchd-scheduled.
- **Privacy enforcement**: 3-tier leak-check (local denylist / salted hashes in CI / no-op) wired
  as a blocking git pre-commit hook; `private/` never in git.
- **Local-first memory**: Obsidian vault + gbrain (Postgres, `ollama:bge-m3` on-device embedding),
  MCP for Claude and Copilot, `bin/check-embedder.sh` durability guard.
- Operator guide (`docs/USAGE.md`), scientific paper v1.2 (`docs/roberdan-os-paper-en.md`).

### Fixed
- Factory silent-failure bug (exit-127 tasks filed as done) + wrong-cwd dispatch bug
  (`--add-dir` grants access, doesn't chdir) — both found by live, non-stub testing.
- kb `set -e`/pipefail silent-death bugs; double-zero DONE count; BSD-only `sed -i ''`.
- A real privacy incident (confidential names committed and briefly pushed) — remediated and
  closed structurally with the pre-commit gate.
- CI-vs-local drift in the tool-coverage gate (`~/GitHub` check now layout-gated).

### Changed
- English is canonical; generated `platforms/` wrappers are no longer committed (deterministic
  emission checked in CI instead); dated session artifacts roll up into `docs/archive/` and
  `kanban/done/_archive-*.md` (documentation budget).
