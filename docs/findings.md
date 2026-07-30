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

## 3. `kb finish` dichiara "verified by @thor" anche quando non è vero

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
