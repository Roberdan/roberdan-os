# Findings — cose vere che nessuno ha chiesto

Le cose trovate durante un lavoro finiscono qui, **non nel board**. Diventano card solo se
Roberto lo decide. Il motivo è misurato, non teorico: al 30 luglio 2026 c'erano 33 card in
attesa della sua approvazione, quasi tutte nate come findings di revisione, e il board non
sapeva distinguerle dal lavoro che aveva chiesto lui.

Ordinate per rischio.

---

## 1. Il bus può avviare un agente scrivendo nella coda della factory, e nessun test lo prende

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

## 5. `kb finish` dichiara "verified by @thor" anche quando non è vero

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

---

_Aggiornato: 2026-07-30._
