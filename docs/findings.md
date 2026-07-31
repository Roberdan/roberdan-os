# Findings — cose vere che nessuno ha chiesto

Le cose trovate durante un lavoro finiscono qui, **non nel board**. Diventano card solo se
Roberto lo decide. Il motivo è misurato, non teorico: al 30 luglio 2026 c'erano 33 card in
attesa della sua approvazione, quasi tutte nate come findings di revisione, e il board non
sapeva distinguerle dal lavoro che aveva chiesto lui.

Ordinate per rischio.

**Stato al 31 luglio 2026, sera.** Roberto ha letto la lista e ha deciso: sei rilievi riparati
(1, 8, 11, 14, 15, 16 — ognuno con la sua card chiusa e la sua prova di mutazione), tre chiusi
da una decisione e non da una riparazione (4, 10, 12), uno rinviato di proposito (13), cinque
lasciati aperti con la condizione scritta che li farebbe diventare card (2, 3, 5, 6, 7, 9).
Ogni riga qui sotto dice a che punto e'.

---

## 1. Il bus può avviare un agente scrivendo nella coda della factory, e nessun test lo prende

**RIPARATO il 31 luglio 2026**, card `260731-182457-2`. `assert_factory_queue_untouched` e' accanto agli altri due pavimenti, con `find -L` perche' la fixture rende la coda un symlink. Prova eseguita: il mutante `factory-drop` applicato a `bus.sh` fa uscire `test-bus.sh` con exit 1 e la riga *the bus WROTE the factory queue*. Prima passava.

**Come è emerso** (30 luglio 2026): la batteria di mutazione `test/test-bus-mutants.sh`,
eseguita per intero per la prima volta. 32 mutanti catturati, **1 sopravvissuto**:
`factory-drop` — un bus che spedisce lavoro a un agente scrivendo un file in
`$RDA_HOME/factory/queue`, senza eseguire niente e senza toccare il kanban.

**Perché sfugge.** I tre pavimenti finali di `test/test-bus.sh` (check 50) verificano
"nessuna esecuzione" e "kanban intatto". Non verificano "coda della factory intatta". Il
commento del check 50 racconta che questa famiglia era **già** sfuggita una volta — un
payload aveva piantato un file in quella coda e la suite aveva stampato PASS — e la
riparazione di allora ha aggiunto i due pavimenti sbagliati.

**Perché non è una card oggi.** `bus.sh` non fa questa cosa: il mutante prova che *se
qualcuno la scrivesse* nessun test lo fermerebbe. È un buco di copertura, non un'esposizione
in atto. E il job `com.roberdan.rda-factory` è stato spento il 30 luglio, quindi un file
piantato in quella coda oggi non viene eseguito da nessuno.

**Se peggiora.** Diventa una card il giorno in cui si riaccende `rda-factory`, perché da
quel momento la coda è un percorso di esecuzione vivo.

**La riparazione, per chi la farà**: un `assert_factory_queue_untouched` accanto ai due
pavimenti esistenti di check 50, sullo stesso modello. Circa dieci righe.

---

## 2. `install-git-hooks.sh` lanciato da un worktree incolla nel hook il percorso del worktree

**Come è emerso** (30 luglio 2026): l'installer era stato eseguito da dentro
`worktrees/roberdan-os/260730-092839`. Quando quel worktree è stato rimosso — normale fine di
una card — **ogni commit in roberdan-os si è bloccato**: `pre-commit: BLOCCATO — .../260730-092839/hooks/pre-commit non esiste (repo spostato?)`.

**Perché è la quarta istanza della stessa famiglia in due giorni.** Le altre tre: il controllo
che scattava su ogni clone pulito (PR #31), l'installer che chiedeva `--git-dir` invece di
`--git-path` (PR #33), e il controllo in `validate.sh` con lo stesso difetto. Tutte hanno la
stessa forma: **il hook e il posto da cui lo si installa non sono la stessa cosa**, e il canone
impone di lavorare in un worktree.

**Perché non è grave.** Il hook **si è bloccato ad alta voce**, che è esattamente il
comportamento progettato: un hook che non trova la sua fonte rifiuta il commit invece di
lasciarlo passare senza controlli. Nessun commit è passato senza verifica. La riparazione
immediata è una riga: `bash bin/install-git-hooks.sh` dal checkout principale.

**La riparazione strutturale**: `ROOT` viene dedotto dalla posizione dello script, quindi da un
worktree punta al worktree. Dovrebbe risolvere sempre al checkout principale
(`git rev-parse --path-format=absolute --git-common-dir` poi risalire), così il percorso inciso
nel hook sopravvive alla card che l'ha installato.

---

## 3. Due sessioni si contendono l'account GitHub, e una delle due perde in silenzio

**Come è emerso** (30 luglio 2026): due sessioni attive, una su `roberdan-os` (account
`Roberdan`) e una su `VirtualBPMFy27` (account `roberdan_microsoft`, Enterprise Managed User).
`gh auth switch` scrive in una configurazione **globale**: ogni volta che una delle due
cambiava account, l'altra si ritrovava sotto quello sbagliato. Esiti osservati: due
`pull request create failed: Unauthorized`, un `mergePullRequest` rifiutato, e un `HTTP 401`
mentre le credenziali erano tutte valide.

**Perché conta più di quanto sembri.** Il messaggio d'errore parla di autorizzazione, quindi
la diagnosi naturale è "le credenziali sono scadute" — che è falsa. Si perde tempo a
riautenticare qualcosa che funziona. E un merge rifiutato per questo motivo, in una sessione
che non se ne accorge, diventa "l'ho pushato" senza che sia vero.

**Aggirato**, non riparato: `GH_CONFIG_DIR=/tmp/gh-config-mio` dà a una sessione la sua
configurazione privata, mentre quella globale resta all'altra. Funziona, ma è una variabile
d'ambiente che va ricordata a mano — cioè il tipo di rimedio che dipende dalla disciplina di
chi lo usa, e che questo file esiste per non fingere che basti.

**La riparazione**: `bin/` dovrebbe esporre un piccolo wrapper che sceglie l'account dal
`remote` del repo in cui sei, invece di lasciare che sia uno stato globale conteso. Il repo
sa già a chi appartiene: `git remote get-url origin`.

**Stessa famiglia, stesso giorno, altro file: `VERSION` e `CHANGELOG.md`.** Le due sessioni
hanno bruciato **lo stesso numero di versione (2.25.0)** per due lavori diversi, e il CHANGELOG
si e' ritrovato con due sezioni `## [v2.25.0]`. Chi ha etichettato per primo ha vinto; l'altro
ha rinumerato a 2.26.0. `rules/best-practices.md § Parallel work` lo dice gia' —
*"tieni `VERSION`, `CHANGELOG.md`, `README.md` FUORI dai rami paralleli: si scrivono una volta
sola, in sequenza, al momento del rilascio"* — ma quella riga governa i **rami**, e qui le due
sessioni erano sullo **stesso ramo**. La regola va estesa al caso "due sessioni, un checkout",
oppure `kb`/`bin` deve proporre il prossimo numero libero invece di lasciarlo scegliere a
ognuno.

## 4. Claude Code ha gia' risolto a monte due dei cinque problemi del 30 luglio

**Come e' emerso**: lette **34 versioni per intero** (2.1.206 -> 2.1.220), non un riassunto.
La prima lettura ne aveva viste otto tramite una fetch riassunta e aveva trovato tre voci;
leggendo il changelog vero le voci pertinenti sono molte di piu', e due colpiscono in pieno
i problemi che Roberto aveva elencato quella mattina. Il guardiano `evolve/` non ha contribuito
nulla: era spento, e quando girava produceva "il changelog e' cambiato, vai a leggerlo".

### a) Il problema "non finisce mai" ha ora dei tetti nel runtime

Non erano regole da scrivere: erano manopole gia' esistenti e mai impostate.

| Manopola | Valore di serie | Perche' riguarda Roberto |
|---|---|---|
| `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | **3** (alzato in 2.1.219, era 1) | Un subagente puo' generare subagenti che generano subagenti. E' il moltiplicatore del lavoro non richiesto, ed e' acceso di serie. |
| `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | 200 (2.1.212) | Tetto per sessione contro le catene di delega scappate di mano. |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | 20 (2.1.217) | Tetto su quanti girano insieme. |
| `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` | 200 (2.1.212) | Tetto contro i cicli di ricerca infiniti. |
| `--max-budget-usd` | assente | Dal 2.1.217 **ferma davvero** gli agenti in background: prima li lasciava correre. |

**E Anthropic ha fatto la stessa scelta che abbiamo fatto qui il 30 luglio**: dal 2.1.215
*"Claude non esegue piu' `/verify` e `/code-review` da solo"*, e dal 2.1.218 lo stesso per
`/deep-research`. Cioe': i revisori che partono da soli producono lavoro che nessuno ha
chiesto. E' la stessa diagnosi, presa a monte.

### b) Il problema "gli agenti si pestano i piedi" era in gran parte un difetto del runtime

Cinque riparazioni sui worktree in quattro versioni, e sono **la stessa famiglia** dei cinque
difetti trovati qui in due giorni:

- 2.1.216: subagenti isolati in worktree che redirigevano git sul checkout condiviso via
  `git -C`, `--git-dir`, `GIT_DIR`/`GIT_WORK_TREE` — **letteralmente il nostro difetto**
- 2.1.216: sessioni che finivano nel worktree avanzato di un altro progetto
- 2.1.211: le regole "consenti sempre" ora si salvano nella radice del repo, cosi'
  un'approvazione data in un worktree sopravvive
- 2.1.210: subagenti in worktree che potevano eseguire comandi git sul checkout principale
- 2.1.210: sessioni uccise che lasciavano un `git worktree lock` permanente

**E il finding numero 3 di questo file** — due sessioni che si contendono le credenziali — ha
il suo gemello a monte: 2.1.211, *"sessioni parallele che si scollegavano tutte insieme dopo
il risveglio quando condividono un solo archivio di credenziali"*.

### c) Sandbox: la regola sul raggio d'azione puo' diventare meccanica

- `sandbox.network.strictAllowlist` (2.1.219) nega gli host non in lista **senza chiedere**
- `sandbox.filesystem.disabled` (2.1.216) permette di tenere il controllo sulla rete senza
  l'isolamento del filesystem

`rules/best-practices.md § Security` dice gia' che *"il controllo e' il raggio d'azione, non
la prosa"*. Oggi e' buona volonta'; queste due voci la rendono configurazione. **E' anche
l'unica idea che valeva la pena prendere da langchain-ai/deepagents**: non serve un framework.

### d) Cose che toccano il canone e vanno verificate, non assunte

- **2.1.214: i hook con codice di uscita 2 non bloccavano** quando il JSON su stdout falliva
  la validazione. Diversi hook di roberdan-os contano su quel blocco. Riparato a monte, ma
  vale sapere che per un periodo *non* bloccavano.
- 2.1.212: un `continue:false` di un hook veniva perso se lo strumento falliva a meta'.
- 2.1.206: `/doctor` propone di **sfoltire i `CLAUDE.md` committati** tagliando cio' che si
  puo' dedurre dal codice — un parere esterno sul fatto che il canone sia troppo grande.
- 2.1.210: una scrittura che lascia `MEMORY.md` oltre il limite ora **da' errore** invece di
  troncare in silenzio.
- 2.1.214: i `SessionStart` hook riportano `"fork"` come sorgente — la fotografia della coda
  in `context-inject.sh` non distingue una sessione nuova da un fork.

**Lato Copilot**: "Agent automation controls in GitHub Issues" (23 lug) e "agent session
streaming" (2 lug) spostano il coordinamento fra agenti su GitHub. Da guardare **prima** di
investire altro sul `bus` fatto in casa.

**Perche' non sono card.** Il gruppo (a) e' una manciata di variabili d'ambiente e vale piu'
di tutto il resto messo insieme: attacca meccanicamente il problema numero 1. Il gruppo (b)
suggerisce di appoggiarsi al runtime invece di riparare a mano la stessa famiglia una sesta
volta. Cosa prendere lo decide Roberto.

## 5. Nove skill di roberdan-os sono irraggiungibili dall'agente interno di gbrain

**Come e' emerso** (30 luglio 2026): `gbrain doctor` riporta `[FAIL] resolver_health` con
9 errori, tutti della stessa forma — `UNREACHABLE: verify-done`, `ship`, `review`, `sync`,
`premortem`, `focus-group`, `auto-checkpoint`, `problem-validation`, `engineering-reference`.
Nessuna ha una riga nella tabella di `~/gbrain/skills/RESOLVER.md`, quindi l'agente interno
di gbrain non ha modo di arrivarci.

**E' il difetto che questo repo chiama "esiste ma non e' collegato"**, applicato alle sue
stesse skill: definite, montate, e raggiungibili da nessuno.

**Perche' non e' urgente, ed e' l'unica ragione per cui non e' una card.** Quelle skill
funzionano **benissimo in Claude Code**, che e' dove Roberto le usa: compaiono nell'elenco
degli strumenti e si invocano con `/nome`. L'irraggiungibilita' riguarda solo l'agente che
gira *dentro* gbrain, che lui non usa. L'impatto pratico oggi e' vicino a zero.

**Se peggiora.** Diventa una card il giorno in cui l'agente interno di gbrain viene messo a
lavorare davvero — perche' da quel momento gira senza poter usare nessuna delle regole di
Roberto.

**La riparazione**: 9 righe nella tabella di `~/gbrain/skills/RESOLVER.md`, piu' un
`triggers:` nel frontmatter di ogni skill. Il doctor stampa l'azione esatta per ciascuna.

---

## 6. Il limite dei blocchi di codice e' una costante, non e' derivato dall'embedder

**Come e' emerso** (30 luglio 2026, chiudendo la card `260730-102955`):
`DEFAULT_MAX_CHUNK_TOKENS = 2000` in `~/gbrain/src/core/chunkers/code.ts` e' tarato — lo dice
il commento — sul **piu' piccolo** embedder comune (`nomic-embed-text`, contesto 2048). Con
l'embedder in uso (`bge-m3`, contesto 8192) il margine e' oltre 6000 token invece di 48, e
l'errore non si e' mai verificato: zero occorrenze nei log.

**Perche' resta una riga e non una card.** Oggi il numero prudente non fa danno. Ma e' una
costante che **finge di conoscere l'embedder** senza chiederglielo: se un giorno si cambia
modello, quel 2000 sara' sbagliato in una delle due direzioni — troppo stretto (blocchi
inutilmente piccoli, recupero peggiore) o troppo largo (embedding rifiutati).

**Se peggiora.** Il giorno in cui si cambia embedder. La riparazione giusta **non** e'
cambiare la costante: e' derivarla dal contesto del modello configurato.

## 7. Una pagina sovradimensionata non si indicizza, e il rimedio esiste ma non e' retroattivo

**Come e' emerso** (30 luglio 2026, sera): durante `gbrain sync`, in diretta —
`Error embedding apps-web-src-components-settings-sections-profile-settings-tsx:
[embed(ollama:bge-m3)] the input length exceeds the context length`. Osservato **due volte**.

**Cosa NON era**, e questa e' la parte istruttiva: sembrava la card `260730-102955` (taglio a
2000 token contro 2048), chiusa quel mattino dicendo *"non e' mai successo, non puo' succedere
con bge-m3"*. **Quella chiusura era sbagliata su un punto**: il conteggio a zero era vero, la
conclusione tratta da quel conteggio no. "Non e' mai successo finora" non e' "non puo' succedere".

**Cosa ho trovato scavando.** `bge-m3` dichiara `bert.context_length = 8192`, ma ollama non
aveva **nessun parametro impostato** e lo serviva col proprio valore di serie, **2048** — un
quarto della capacita' del modello. gbrain non passa `num_ctx`. Quindi il margine reale contro
il taglio a 2000 token *stimati* era davvero **48 token**, come diceva la card.
**Riparato**: `bge-m3` ricostruito con `PARAMETER num_ctx 8192`, stesso nome, cosi' gbrain non
vede cambiare il modello e non re-indicizza nulla.

**Perche' resta una riga e non una card.** Dopo la riparazione l'errore su quella pagina
**persiste**: quel blocco supera anche gli 8192, quindi non e' il problema di margine — e' una
**pagina sovradimensionata** sfuggita al taglio, di **un altro progetto** (`apps-web`), 2 blocchi
su un corpus di centinaia di pagine. Il doctor ha gia' un rimedio dichiarato per la famiglia
(`frontmatter.embed_skip`, applicato **d'ufficio ai nuovi ingressi**) — quello che manca e' la
retroattivita' sulle pagine entrate prima.

**Se peggiora.** Quando le pagine non indicizzabili passano da 2 blocchi a una quota che sposta
i risultati di ricerca. Oggi non lo sono. La riparazione: `gbrain quarantine` o `embed_skip` sui
casi esistenti, una volta.

## 8. `kb finish` dichiara "verified by @thor" anche quando non è vero

**RIPARATO il 31 luglio 2026**, card `260731-182457-1`. `kb finish --by <chi>` prende chi verifica come dato: l'output e il campo `verified_by` riportano quello. Dal giorno dopo e' andato oltre: `kb finish` **convoca @thor da solo** (card `260731-185913`), quindi la frase e' vera perche' la verifica avviene, non perche' qualcuno l'ha digitata.

**Come è emerso** (30 luglio 2026): @thor era sospeso per decisione di Roberto, e ogni card
chiusa quel giorno è stata verificata da Claude. `kb finish` ha comunque stampato
*"done/<id> verified by @thor"* su tutte.

**Perché conta.** La frase è generata dal sistema, non da chi verifica, e nessuno la
controlla. È il tipo di affermazione che rende inaffidabile l'intero registro: un domani
qualcuno leggerà "verified by @thor" su una card che @thor non ha mai visto.

**Aggirato oggi** scrivendo a mano dentro l'evidenza di ogni card chi aveva verificato
davvero. Un rimedio che dipende dalla disciplina di chi scrive è esattamente ciò che questa
riga dice di non fare.

**La riparazione**: `kb finish` deve prendere chi verifica come dato (`--by`), non
presupporlo, e stampare quello.

## 9. Una PR si merga anche col check rosso, e niente lo impedisce

**Come è emerso** (29 luglio 2026, dichiarato sul bus dalla sessione che l'ha fatto, card
`260729-150321`): PR #30 è stata mergiata con il check di CI **già rosso**, e `main` è rimasta
rossa da `768a2e3` fino a `4970979`. Nessun passaggio — né umano né meccanico — chiede a una PR
di essere verde prima del merge.

**Perché conta.** È esattamente la forma del falso "done" che il canone vieta a parole: il merge
è l'atto che dichiara "questa cosa è a posto", e oggi può avvenire su prova rossa. Il rilievo è
emerso perché chi l'ha fatto l'ha scritto, non perché qualcosa l'abbia fermato.

**Diventa una card** se accade una seconda volta, oppure appena si merga qualcosa di più di una
sessione singola. La riparazione probabile: branch protection "require status checks" su `main`,
che è però gate umano (tocca la protezione del branch).

## 10. Due test falliscono a caso in CI e passano rilanciandoli

**Come è emerso** (29 luglio 2026, stesso thread bus): `test-fork-merge` è fallito su una PR,
passato in locale e passato **rilanciando lo stesso job senza toccare una riga**; `test-bus` è
stato visto flaky lo stesso giorno.

**Perché conta.** Un gate che a volte mente in una direzione insegna a rilanciare invece che a
leggere — ed è così che un fallimento vero viene scambiato per rumore.

**Diventa una card** quando un flaky fa perdere tempo una seconda volta, o quando fallisce in
una finestra in cui serviva fidarsi del verde. Oggi il costo è un rilancio.

**Seconda occorrenza, 31 luglio 2026 — la condizione dichiarata sopra si è verificata.**
`test-fork-merge` è fallito sulla run `30641426340` (commit `99ee81d`, un commit di sola
documentazione che non tocca nulla di ciò che quel test prova). Misurato nei due sensi:
in locale `bash test/test-fork-merge.sh` → **PASS, exit 0**; rilanciato lo stesso job in CI
**senza cambiare una riga** → **success**. Roberto è stato informato con le due opzioni
(farne una card, o lasciarlo); la promozione resta sua.

**Decisione di Roberto, 31 luglio 2026: si lascia così — nessuna card.** Il costo accettato è
un rilancio quando capita. Chi trova questo test rosso: **prima rilancia**, e solo se fallisce
di nuovo sullo stesso commit cerca la causa. Non riproporre la card senza un fatto nuovo (un
rosso che *non* passa al rilancio, o un rosso in una finestra in cui serviva fidarsi del verde).

## 11. `kb pending` non vede una card ferma in `doing` in attesa di Roberto

**RIPARATO il 31 luglio 2026**, card `260731-182457`. `kb pending` ha una sezione *Card ferme in doing* che stampa anche il perche'. Le card che stanno lavorando non compaiono, ed e' asserito in negativo. Difetto collaterale trovato dal test: `_field` sotto `set -e` troncava l'intero report alla prima card in doing normale.

**Come è emerso** (31 luglio 2026): `handoff/latest.md` nomina una quarta decisione in attesa
(`260729-073336`, VirtualBPMFy27 — *vuoi che Copilot CLI legga i dati di VirtualBPM?*).
`kb pending --tutti` ne elenca 12 e quella non c'è: la card è **in `doing`** con
`blocked_reason: "IN ATTESA DI ROBERTO, non di lavoro"`, e `kb pending` guarda solo `todo`.
Si somma un secondo scarto: quel board vive dentro `VirtualBPMFy27/kanban/`, non in questo.

**Perché conta.** `kb pending` è la lista con cui Roberto decide di cosa occuparsi. Una card
che aspetta lui e non compare lì aspetta per sempre — ed è il caso peggiore, perché
`blocked_reason` dice a chiare lettere che aspetta lui.

**Diventa una card** se una seconda decisione bloccata sfugge allo stesso modo. La riparazione
probabile: `kb pending` legge anche `doing` quando la card porta un `blocked_reason`.

## 12. I gate di rilascio di MirrorHR non sono più tracciati da nessuna card

**Come è emerso** (31 luglio 2026): Roberto ha deciso di rimuovere la card `260713-093430`
(*P1 Safety Recovery*). I due difetti safety-critical di T8 sono chiusi e verificati — questo
non cambia. Ciò che esce dal board sono i gate di T9/T9b, che l'acceptance della card stessa
chiamava **"non-code gates, not waivable"**: fatturazione GitHub Actions, **due notti reali**
di monitoraggio, approvazione umana dei testi EN/IT/AR, evidenza su dispositivo accoppiato.

**Perché conta.** Non sono stati derogati né soddisfatti: sono usciti dal tracciamento. È una
decisione presa da Roberto con la conseguenza scritta davanti (registrata qui il giorno stesso),
non una dimenticanza — ma da oggi nessun sistema li ricorda.

**Diventa una card** nel momento in cui si decide di rilasciare quella versione di MirrorHR.
Fino ad allora la riga è qui.

## 13. `bin/sync.sh` genera ancora i wrapper per Codex e Hermes, che non si usano più

**RINVIATO di proposito, 31 luglio 2026.** Roberto ha deciso: non ora. Si toglie la prossima volta che si mette mano a `bin/sync.sh`, non prima.

**Come è emerso** (31 luglio 2026): togliendo Codex e Hermes dal watcher `evolve/watch.sh`,
per istruzione esplicita di Roberto. Il watcher ora sorveglia tre sorgenti; `bin/sync.sh`
continua invece a emettere `platforms/hermes/` (funzione `emit_hermes`, ~50 righe di README
verificate contro hermes-agent v0.18.0) e il ramo Codex.

**Perché conta poco oggi e potrebbe contare domani.** Non rompe niente: sono file generati in
una cartella gitignorata, installati solo se il tool esiste. Il costo è manutenzione
silenziosa — quelle righe vengono lette, aggiornate e verificate a ogni revisione
dell'adapter, per due strumenti che nessuno lancia.

**Diventa una card** se qualcuno spende di nuovo tempo a verificare quei wrapper, o alla
prossima revisione di `bin/sync.sh`. Non toccato qui perché Roberto ha chiesto di togliere le
due sorgenti **dal watcher**: ridurre l'ambito di un'istruzione è più sicuro che allargarlo.

## 14. La regola anti-force-push del bash-guard blocca anche chi la *nomina* in un messaggio di commit

**RIPARATO il 31 luglio 2026**, card `260731-182445`. Lo strip delle virgolette e' dentro `norm`, quindi vale per tutte le regole che leggono la testa del comando — riparata la classe, non l'istanza. Tradeoff dichiarato e asserito nel test: un flag nascosto fra virgolette non viene piu' intercettato.

**Come è emerso** (31 luglio 2026): scrivendo `test/test-bash-guard.sh`, il primo test che il
guard abbia mai avuto. Un `git commit -m 'never use git push --force here'` viene **negato**:
la regola 1 legge il comando grezzo, mentre la regola 4 (docs + `git add -A`) lo stesso
problema l'aveva già risolto per sé, togliendo prima le stringhe fra virgolette.

**Perché conta.** Un guard che blocca l'innocuo viene disattivato dalla prima persona che
infastidisce, e un guard disattivato vale quanto un guard assente. La regola 1 protegge da uno
scar vero (il force-push del 6 luglio): è la meno rimovibile di tutte.

**Riparazione probabile**: applicare alla regola 1 lo stesso `cmd_nostr` che la regola 4 usa
già — due righe. Non fatta qui perché non è la modifica chiesta. Il test la asserisce **come
si comporta oggi**, etichettata come over-block noto, così il giorno che si ripara la riga
diventa rossa e va aggiornata di proposito.

**Diventa una card** se blocca un commit vero a qualcuno.

## 15. Il changelog di Warp non è più leggibile all'URL che il watcher sorveglia

**RIPARATO il 31 luglio 2026**, card `260731-182445-1`, e l'ambito era piu' largo del previsto: **due sorgenti su tre** erano cieche, non una — anche la pagina docs di Claude Code (0 marcatori di rilascio via curl). `test/test-evolve-sources.sh` ora legge gli URL da `watch.sh` e verifica che il corpo scaricato contenga note di rilascio vere.

**Come è emerso** (31 luglio 2026): scrivendo `proposals/2026-07-31-warp.md`.
`https://docs.warp.dev/getting-started/changelog` — l'URL nella lista sorgenti di
`evolve/watch.sh` — ora reindirizza a `/changelog/`, e quella pagina costruisce le voci nel
browser: un `curl` restituisce menu e script, **zero note di rilascio**.

**Perché conta.** Il watcher continua a funzionare — l'impronta cambia, la card nasce — ma
l'agente che raccoglie quella card non riesce a leggere la fonte che gli viene indicata. È il
caso peggiore di una fonte rotta: silenzioso, perché la parte che regge è il rilevamento.
La versione leggibile esiste: `https://docs.warp.dev/changelog/2026.md` (oppure
`_llms-txt/changelog.txt`).

**Diventa una card** — o meglio, una riga sola in `watch.sh` — se un secondo giro settimanale
produce una card Warp che nessuno riesce a lavorare. Il rischio speculare vale per le altre
due sorgenti: nessuno verifica che l'URL sorvegliato sia ancora quello leggibile.

## 16. In `validate.sh` una suite attesa ma mai lanciata blocca il gate per 15 minuti

**RIPARATO il 31 luglio 2026**, card `260731-182446`. `_suite` rifiuta un nome mai passato a `_spawn` e lo dice in meno di un secondo. `test/test-validate-wiring.sh` estrae le funzioni vere da `validate.sh` invece di riscriverle.

**Come è emerso** (31 luglio 2026): agganciando `test-bash-guard`. `validate.sh` lancia le
suite in parallelo con `_spawn` (riga 74-83) e poi le attende con `_suite`, che aspetta il file
`.rc` prodotto dal lancio. Ho scritto la riga `_suite test-bash-guard` senza aggiungere il nome
alla lista di `_spawn`: il gate si è fermato lì per **15 minuti** prima di dichiarare *"did not
finish within 15 minutes (hung)"*. Due esecuzioni buttate prima di capirlo.

**Perché conta.** I due elenchi devono restare allineati e niente lo controlla: chi aggiunge un
test tocca il posto giusto (`_suite`) e dimentica quello non ovvio (`_spawn`). Il fallimento è
il peggiore per un gate — non è rumoroso, è *lento*: chi lo lancia in CI vede una build che non
finisce e la rilancia.

**Riparazione probabile**: un controllo statico all'avvio di `validate.sh` — ogni nome passato a
`_suite` deve comparire nella lista di `_spawn`, altrimenti esci subito dicendo quale manca.
Poche righe, ma `validate.sh` è già in baseline oltre soglia, quindi è una decisione di spesa,
non un dettaglio.

**Diventa una card** se succede una seconda volta a chiunque.

---

_Aggiornato: 2026-07-31._
