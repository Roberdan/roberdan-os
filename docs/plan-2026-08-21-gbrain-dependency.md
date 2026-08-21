# Piano 2026-08-21 — gbrain/gstack come dipendenze esplicite + decision intelligence sul board

> **Indice di iniziativa, non una card.** Ogni P-item qui sotto è un candidato a card
> atomica con **una** condizione di accettazione osservabile. Non esiste una card ombrello
> che li chiude tutti: la prima stesura ne aveva una, ed è stata ritirata — vedi
> § Storia della revisione.

## Stato: rivisto dopo adversarial review (GPT-5.6 Sol, 2026-08-21)

La prima stesura conteneva errori di fatto e un difetto di processo. Correzioni applicate
in questo documento; i numeri qui sotto sono quelli verificati.

## Perché

### 1. gbrain è documentato, quasi mai invocato

L'igiene documentale è corretta: `ontology/ontology-protocol.md` dice *"No bespoke ontology
engine"*, *"Extends the vault's ontology, not a new store"*; `memory/memory-protocol.md`
mette gbrain come layer di recall e il vault come source-of-truth. **Nessuna duplicazione
da correggere.**

Ma l'integrazione non c'è: **zero** occorrenze di `gbrain` in `loop/`, `factory/`,
`agents/`, `evolve/`. Circa **212** occorrenze in `docs/` e **55** in `bin/` (in gran parte
health-check in `doctor.sh`/`bootstrap.sh`). *Corretto rispetto alla prima stesura, che
diceva 172/45 e "zero invocazioni operative":* esiste almeno una chiamata reale fuori dagli
health check, `learn/distill.sh:22`. La conclusione onesta è **"documentato e invocato
sporadicamente, non integrato nei loop principali, nel factory, negli agent, nel kanban"**,
non "mai usato".

- `hooks/context-inject.sh:37` cita gbrain in **una riga di testo echoed**; non lo interroga
  mai. P7 è quindi una dipendenza runtime **nuova**, non l'attivazione di codice dormiente.
- `kanban/kb.sh` (1753 righe, dispatch a `~1382-1750`) non espone `search`/`find`/`similar`/`why`.

### 2. gstack possiede 53 righe del canon, ed è marcato "optional"

`AGENTS.md:328-381` è un blocco **generato**, delimitato da
`<!-- gstack-gbrain-search-guidance:start/end -->`, di proprietà della skill gstack
`sync-gbrain`. Le skill che installano e mantengono gbrain — `setup-gbrain`, `sync-gbrain`,
`USING_GBRAIN_WITH_GSTACK.md` — vivono in `~/.claude/skills/gstack/`, **non** in roberdan-os.

Conseguenze:
- Il file che si autodefinisce *"the single canonical source"* ha due generatori: `bin/sync.sh`
  (dichiarato) e gstack (non dichiarato). Se gstack cambia formato, il canon deriva senza gate.
- Il lifecycle che P1/P2 vogliono documentare **non è codice di questo repo**.
- La catena reale è a tre livelli: roberdan-os → gstack (installer/sync) → gbrain (recall).
  Rendere gbrain un requisito senza fare altrettanto per il suo installer produce un
  requisito senza modo supportato di soddisfarlo.
- **Contraddizione operativa attiva:** il blocco gstack dice *"Run `/sync-gbrain` after
  meaningful code changes"*; `~/.claude/CLAUDE.md` dice *"launchd jobs già wired — non
  duplicare sync manuali"*.

### 3. Il corpus decisionale è fuori dall'indice

`kanban/done` contiene **149 file .md, di cui 2 archivi → 147 card reali**. `approved_by`
compare in 136, `verified_by`/`verified_evidence` in 135, `title`/`dod`/`acceptance` in 147.
Il corpus copre **2026-07-03 → 2026-08-18, circa sei settimane** — *non "tre anni", come
affermava erroneamente la prima stesura.*

**Correzione strutturale importante:** questi campi **non sono YAML frontmatter**. In
`kanban/done/T-tool-independence.md` il frontmatter finisce a riga 8; `kb_start_audit`,
`approved_by`, `verified_by` stanno alle righe 13-16, **dopo** il delimitatore, perché
`kb start` (`kb.sh:1533-1534,1577-1578`) e `kb finish` (`kb.sh:1725-1727`) li **appendono in
coda al file**. Nessun parser può assumerli come metadati strutturati. Questo vincola P4.

Le card non sono nell'indice: `gbrain search "kb_start_audit approved_by verified_by thor"
--source gstack-code-roberdan-os-67e84638` non restituisce card. *Causa corretta:* non è
"gbrain indicizza solo il tracked" — gbrain cammina **tracked + untracked non-ignorati**
(`~/gbrain/src/commands/import.ts:653-739`). Il fattore decisivo è la **semantica di
gitignore**: `.gitignore:4-24` esclude le directory delle card, `.gitignore:52` esclude
`.gbrain-source`.

**E soprattutto:** `kanban/` è un **repo git annidato e privato**, remote
`Roberdan/roberdan-os-cards`. È quello — non le directory ignorate del parent pubblico — la
radice naturale per P3.

### 4. La documentazione sul fork è obsoleta

`bin/check-embedder.sh:4-8`: *"As of 2026-07-08 gbrain runs the OFFICIAL upstream
(github.com/garrytan/gbrain) — NO fork."* La patch del vecchio fork (`Roberdan/gbrain`,
commit `f7376b11`) non serve: il config dichiara `embedding_dimensions: 1024` e l'upstream le
rispetta. Riferimenti obsoleti residui: `README.md:202-204`, `README.md:218`,
`bin/doctor.sh:115-130`, `docs/roberdan-os-paper-en.md:552-556` — quest'ultimo elenca ancora
fra le **Limitations** una fragilità che non esiste più. Da **rimuovere**, non riscrivere.

Non limitarsi a questi quattro punti: P1 cerca ed elimina *ogni* occorrenza residua di
`Roberdan/gbrain`, "patched fork" e formulazioni equivalenti.

## Livelli di dipendenza: tre, non due

La prima stesura proponeva `gbrain` come `check_cmd required` in `doctor.sh`. **Rifiutato in
review, e la review ha ragione.** `doctor.sh:101` definisce `required` come i tool senza cui
*"the engine does not work"*, e la loro assenza fa fallire il doctor (`doctor.sh:199-219`).
Non è il caso di gbrain sotto questo piano: `kb` mantiene i fallback grep, il canon resta
usabile, hook, factory e bus continuano a funzionare, e P5-P7 prevedono esplicitamente
degradazione anziché fallimento totale. Evidenza da macchina pulita: `bin/bootstrap.sh:18-24`
richiede solo git e jq; `.github/workflows/validate.yml:7-15` non installa gbrain;
`test/validate.sh:21-32,286-295` non invoca `doctor.sh`; nessun consumer attuale usa il suo
exit code. Metterlo fra i `required` non romperebbe la CI, ma farebbe fallire il doctor su un
clone legittimo in cui il motore funziona: un contratto diagnostico **fuorviante**.

| Livello | Cos'è | gbrain |
|---|---|---|
| **Canon** | markdown letto anche da claude.ai / ChatGPT web | nessuna dipendenza binaria — non installabile per definizione |
| **Automation core** | loop, factory, bus, `kb` con fallback grep | opzionale, degradato |
| **Full-recall automation** | recall semantico, `kb similar`, context-inject arricchito | **richiesto, e verificato operativamente** |

Implementazione: **non** spostare gbrain nel bucket `required` esistente. Introdurre
`doctor --profile full-automation` (oppure un terzo stato `required-for-recall`) in cui gbrain
è obbligatorio. Il profilo di default resta onesto.

## Cosa si prende da Semantica (e cosa no)

`semantica` v0.6.6 — install verificato impossibile su questa macchina (`files.pythonhosted.org`
e `registry.npmjs.org` bloccati con TLS reset da GlobalProtect/Defender; `pypi.org` raggiungibile).
Analisi condotta su README/sorgenti upstream. **Non si installa nulla**: si prende il modello.

Si scartano: RDF/OWL/SHACL, triple store polyglot, Rete/Datalog, export W3C PROV-O, connettori
Databricks/Snowflake (`README.md:25,68,82-88,186-195`, `ARCHITECTURE.md:53-55` upstream).

Si prende, con due correzioni rispetto alla prima stesura:
- `trace_decision_chain` (`context_graph.py:4150`) = risalita **a monte** → `kb why`.
- `analyze_decision_impact` (`context_graph.py:4120`) = discesa **a valle** — direzione
  **diversa**. Non va rivendicata sotto `kb why` se non è implementata.
- `find_similar_decisions` (`context_graph.py:4094`) → `kb similar`, che **non è nuovo**:
  `kanban/precheck.sh:68-94` fa già overlap lessicale contro le card aperte e le 30 più
  recenti chiuse, emettendo `SOVRAPPOSIZIONE` e `FORSE GIA' FATTA`. P6 **estende** quella
  pipeline, non ne apre una seconda.
- Le righe di audit appese alle card sono evidenza utile, ma **non** sono provenance
  entity/activity in senso PROV-O. Non chiamarla provenance formale.

## P-item

Ognuno è un candidato a card atomica. **Nessuna card ombrello.**

### P1 — Rimuovere la documentazione obsoleta sul fork
Eliminare ogni riferimento residuo al fork verso l'upstream ufficiale; rimuovere la voce
*Limitations* del paper. Fonte autorevole: `bin/check-embedder.sh:4-8`.
*Rischio: nullo. Valore: corregge un'affermazione falsa in un documento pubblicato.*

### P2 — Lifecycle documentato di gbrain **e gstack**
README: install upstream ufficiale, Ollama + `embedding_dimensions: 1024`, `self-upgrade`,
registrazione source, pin `.gbrain-source`, freshness launchd — **e** il ruolo di gstack come
proprietario di `setup-gbrain`/`sync-gbrain` e del blocco `AGENTS.md:328-381`. Risolvere la
contraddizione "sync manuale vs launchd".

### P3 — `doctor --profile full-automation`
Nuovo profilo in cui gbrain è richiesto. Il default resta invariato. Il check non è
`command -v`: smoke test limitato — versione, risoluzione del pin, stato della source, **una**
query scoped economica, comportamento a timeout. `check-embedder.sh` resta separato.
Prerequisito: **aggiornare gbrain** `0.43.0.0` → `0.46.24.0`.

### P4 — Indicizzare il board privato *(la voce a più alto rischio, non a più basso)*
La prima stesura la definiva "minimo rischio": **sbagliato**, cambia il perimetro privacy.
`--no-federated` governa il mixing di default, **non** prova che il brain sia locale, che la
source non sia selezionabile esplicitamente, che client MCP/OAuth non abbiano grant, né che
gli snippet non finiscano a un modello esterno (`~/gbrain/src/core/source-resolver.ts:407-452`,
`~/gbrain/src/mcp/server.ts:40-76`, `~/gbrain/docs/architecture/brains-and-sources.md:34-52`).
Il repo documenta già la distinzione in `docs/adr/adr-always-on-security.md:34-55,103-123`.

Requisiti: radice = il **repo annidato privato** `kanban/`; registrazione **isolated**; mai
`--include-gitignored` sulla source pubblica esistente; asserzione che l'endpoint DB è locale;
audit di ogni grant MCP/OAuth; test negativi (una canary unica del board non deve uscire da
una search federata non qualificata, né da `__all__` remoto, né da un client senza grant, e
**deve** uscire da una query esplicita alla source del board); invarianti sullo stato git di
parent e nested; modello di freshness (il nested è oggi dirty, e le card si spostano fra
directory senza cambiare HEAD); procedura di **cancellazione/rollback** della source e dei dati
privati indicizzati. Upgrade e verifica dell'isolamento **prima** di ingerire materiale
confidenziale.

### P5 — Link causali: scegliere UNA fonte di verità
`caused_by` / `influenced_by` / `precedent_for`. Il piano deve decidere **esplicitamente**:
- **kb-native** — `kb` valida e attraversa; gbrain li indicizza solo come testo. Allora non
  rivendicare che siano archi del grafo gbrain.
- **gbrain-native** — serve un page type per le card e un mapping frontmatter→link in uno
  schema pack esplicito (lo schema attivo dichiara i tipi di link a
  `~/gbrain/src/core/schema-pack/base/gbrain-base-v2.yaml:322-346` e **non** contiene questi).

Da specificare comunque: direzione dell'arco e inversi, ID mancanti, card archiviate, cicli,
ID duplicati fra board, qualificazione per repo/source, profondità massima, momento della
validazione. E il fatto che i campi finirebbero **dopo** il frontmatter (vedi § Perché 3).
**Non mantenere silenziosamente due grafi.**

### P6 — `kb why <id>`
Risalita a monte + `approved_by` + `verified_evidence`. **Solo** upstream: l'impact analysis
è un'altra direzione e un'altra card, se mai.

### P7 — `kb similar` come interfaccia di `precheck.sh`
Stessa pipeline: candidati deterministici keyword-first (il gap di recall semantico è
documentato in `memory-protocol.md` / `reference-gbrain-semantic-recall-gap`), rerank gbrain
opzionale, fallback deterministico. Specificare `kb similar <card-id>` vs `<query>`, source,
limite, ranking, dedup.

### P8 — Context-inject con contratto, non con buone intenzioni
**Nessuna query semantica live non limitata nell'hook.** Cache locale precalcolata (refresh su
`kb start` o job in background), letta con timeout wall-clock e cap in byte; scope al
repo/card corrente; iniettare **ID e sintesi minime**, mai `verified_evidence` grezzo o corpi
di card — *iniettare snippet privati in una sessione Claude/Copilot li manda a un modello
esterno anche se l'indice è locale*. Test: gbrain assente, DB non disponibile, comando
appeso, output malformato, output sovradimensionato, più card in doing, repo non correlato,
accesso negato alla source privata. L'hook ha già una storia di latenza rimossa
deliberatamente: serve un budget p95, non una promessa.

## Storia della revisione

**2026-08-21, prima stesura:** una card ombrello (`260821-121235`) con `dod` P1-P7 e una sola
condizione sintattica di accettazione (*"@thor PASS su ogni P-item"*).

**Ritirata.** `kb add` aveva già rifiutato la versione esplicita a più condizioni
(`kb.sh:1450-1478`: *"una card = una condizione verificabile"*); riformularla come un'unica
frase che semanticamente ne richiede sette **aggira il guard meccanicamente conservando ogni
ragione per cui esiste**. `T-tool-independence` non è un precedente valido: è del 2026-07-03 e
**precede** il ratchet a una condizione. Verifica meccanica:
`kb cover docs/plan-2026-08-21-gbrain-dependency.md` riportava
`0 clause(s) · 0 carded · 0 uncovered` — il piano non offriva alcun confine di review
(estrattore a `kb.sh:1298-1320`). Contesto: la lezione del PR da +6153 righe, `AGENTS.md:112-137`.

Le card atomiche non vengono create d'ufficio: `AGENTS.md` è esplicito sul fatto che un
finding è *"una riga con la condizione che lo renderebbe degno di una card; solo Roberto la
promuove"*. Questo documento **è** quell'indice.
