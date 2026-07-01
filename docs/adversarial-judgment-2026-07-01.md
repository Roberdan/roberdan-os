# Giudizio adversariale di roberdan-os — come Roberto

**Data:** 2026-07-01 · **Giudice:** un agente che incarna Roberto D'Angelo (evidence-first, allergico all'hype, detector del "fatto a cazzo") · **Metodo:** verifica sul filesystem reale, non lettura fiduciosa. · **Input:** analisi Fable (verificata e contestata, non ricopiata).

> Questo verdetto sarebbe dovuto nascere stanotte dalla factory autonoma. La factory è morta 4/4 (exit 127) e ha spostato le task in `done/` mentendo sul proprio stato. Il primo dato su roberdan-os è che **il suo unico giro di lavoro autonomo reale è fallito in silenzio.** Partiamo da lì.

---

## Executive verdict (diretto)

Il sistema è **onesto nell'ossatura e prematuro nell'ambizione.** Le parti file-based e greppabili (kanban gated, validate.sh, privacy split) sono vere e valgono. La parte che vende il sistema — la factory autonoma, il meta-loop auto-migliorante — è **impalcatura non ancora provata sul campo**: la factory ha uno storico di **0 run riusciti su 4**, e il fix di stanotte è committato ma **mai ri-eseguito end-to-end**. Il rischio strutturale è che roberdan-os **riproduca esattamente la patologia che dice di uccidere** (paper §1.1: "superficie di manutenzione contro uso reale — decine mantenute, una manciata usata"), solo un livello più su. Vale la pena tenerlo? **Sì, ma solo se congeli l'ambizione finché la base non ha girato con successo una volta.** Oggi è più impalcatura che casa abitabile — non è teatro, ma non è ancora un sistema di cui fidarsi al buio.

---

## KEEP — cosa tenere così com'è (e perché)

| Cosa | Perché tenerlo | Verifica mia |
|---|---|---|
| **kanban gated (`kb.sh`)** | Semplice, file-based, zero dipendenze, greppabile. I gate `todo→doing` (umano) e `doing→done` (@thor+evidence) rifiutano davvero con `exit 1`, non sono decorativi. | Letto: `kb.sh` righe 82-118. I `REFUSED:` sono reali. |
| **`AGENTS.md` come canone unico + wrapper generati** | Uccide davvero la frammentazione comportamentale. Un file, non 4-6 copie divergenti. Onesto anche sui limiti (vedi il blocco Privacy che ammette che il leak-check degrada a no-op su un clone). | Letto: `AGENTS.md` per intero. L'auto-onestà sul leak-check locale-only è la cosa migliore del documento. |
| **Privacy split (dossier local-only + leak-check)** | Il dossier confidenziale (`~/.roberdan-os/private/roberto-profile.md`) esiste davvero, è fuori git, contiene clienti/deal reali. La voce committata (`roberto-voice.md`) contiene SOLO stile con placeholder `[Partner]`. Lo split regge. | Verificato: dossier presente e pieno; `roberto-voice.md` scrubato. Nessuna leak. |
| **Factory come idea (no daemon, stato = filesystem)** | La decisione di sostituire Convergio con code file-based è quella giusta. L'idea è sana; è l'implementazione a essere acerba. | Concordo con Fable. |
| **`kb block` esiste già** | *Qui correggo Fable.* Fable elenca "manca uno stato blocked" tra i FIX. È **obsoleto**: `kb.sh` righe 94-102 implementano `kb block <id> "<reason>"`. Tienilo. | Verificato: il comando c'è. Fable ha analizzato una versione precedente. |

---

## FIX — cosa è rotto/fragile, in ordine di priorità

**P0 — Il done-gate della factory non verifica nulla (rc==0 ⇒ done).**
`run.sh` riga 75: se `claude` esce con 0, la task va in `done/` e basta. **Exit 0 non prova che il DoD sia soddisfatto** — l'agente può aver prodotto un file vuoto, sbagliato, o nessun file, e la factory dichiarerebbe "done" lo stesso. Questo è il difetto più profondo e **sopravvive al fix di stanotte** (che riguardava solo il caso di fallimento). Concordo con Fable (§3.3) ma alzo la priorità: è P0, non un rischio minore. La factory ha un solo modo di dichiarare done e non guarda l'artefatto.

**P1 — La factory ha 0 run riusciti su 4 ed è "provata" solo in shell interattiva.**
*Qui vado oltre Fable, che prende il fix come "dato acquisito".* Prendo pure io il bug del silent-failure come già fixato (commit `b7f1cd1`: retry/failed invece di done incondizionato) — non lo rilitigo. Ma il punto distinto è un altro: ho verificato che il nuovo `run.sh` risolve `claude` a `/Users/Roberdan/.local/bin/claude` e `timeout` a `/opt/homebrew/bin/timeout` (entrambi nella lista di fallback, entrambi presenti sul disco). Il fix è **logicamente corretto**, ma **non è mai stato ri-eseguito end-to-end** nel vero contesto launchd/non-login. E le card exit-127 di stanotte **stanno ancora in `~/.roberdan-os/factory/done/`** a mentire. "Committato" ≠ "funziona". Questa è **letteralmente la cicatrice che il sistema dice di aver imparato** ("smoke-tested ≠ works in real env") che si ripete. FIX: ri-esegui un giro reale, verifica che una task chiuda con DoD soddisfatto (non solo exit 0), e ripulisci gli artefatti fasulli. Finché non succede, la factory è **non provata sul serio**, non "fixata".

**P1 — Due fonti di verità non riconciliate (kanban `doing/` ↔ factory `queue/→done/`).**
Le card `T-adversarial-judge` e `T-system-tests` sono in `kanban/doing/` e dicono "runs tonight via the factory" — stato falso: nessun lavoro è avvenuto, la versione factory è fallita e giace in `factory/done/`. I due sistemi non si parlano. Concordo con Fable (§1.1).

**P2 — Il gate umano è honor-system, e le card `autonomous:true` lo contraddicono.**
`kb start <id> --by roberto` accetta qualunque stringa: qualsiasi agente che scriva "roberto" passa il gate "umano" (`kb.sh` riga 83-90). Peggio: `T-tests-factory-kb` e `T-usage-guide` hanno `autonomous: true` in frontmatter — cioè sono progettate per bypassare il gate umano che il sistema proclama non-negoziabile. O il gate è reale, o `autonomous:true` è una scappatoia. Scegli. Concordo con Fable (§1.4).

**P2 — Contraddizione documentale sull'embedder.**
`~/.claude/CLAUDE.md` globale dice `must stay openai:text-embedding-3-large`; il paper (§ abstract/1.2) e la card `FtS-ingest` dicono `bge-m3` locale via Ollama. Ho evidenza documentale del conflitto (non serve check live per rilevarlo). È una doc-inconsistency da riconciliare: uno dei due è obsoleto e un agente futuro obbedirà a quello sbagliato. Concordo con Fable (§1.3).

**P2 — La patch gbrain bge-m3 va riapplicata a mano dopo ogni update, senza check automatico.**
Trappola di manutenzione silenziosa: una patch a due righe alla recipe Ollama che nessuno riverifica. Concordo con Fable (§3.1).

**P3 — `docs/USAGE.md` manca.** Verificato: non esiste. Un operatore al giorno 1 non sa cosa è reale e cosa no. La card `T-usage-guide` è pronta e sana — falla (in foreground o con la factory una volta provata).

---

## KILL — cosa è teatro/over-engineering da eliminare oggi

Sono disciplinato qui: KILL = lo cancellerei **oggi**. "Utile ma prematuro" è un FREEZE, non un KILL, e lo dico nel FIX/nota sotto.

- **Le card a stato falso in `doing/` + gli artefatti exit-127 fasulli in `factory/done/`.** Non sono lavoro: sono rumore che mente sullo stato del sistema. Vanno rimossi/riconciliati (nota: non li tocco io — è gate separato). Questo è l'unico vero "teatro" concreto sul disco adesso: file che affermano un lavoro mai avvenuto.

**Non-KILL, ma FREEZE (correzione a un istinto sbagliato):** sarei tentato di uccidere la larghezza del meta-loop — `evolve/` (watcher changelog settimanale), promozione auto dell'ontologia, self-proposing. Ma non è net-negativo né teatro puro: è **prematuro**. Costruire un motore di auto-miglioramento prima che la base abbia girato con successo una volta è mettere il carro davanti ai buoi, non buttare il carro. **Congelalo** finché factory + kb non hanno un giro reale verificato alle spalle. Ucciderlo sarebbe la stessa imprecisione che sto criticando.

**Merito, non KILL:** over-engineering evitato correttamente — niente ontologia auto-aggiornante attiva, Convergio spento, self-proposing-not-self-applying. Concordo con Fable: qui il sistema si è trattenuto bene.

---

## Il singolo rischio più grande, oggi

**Roberto inizia a fidarsi dei run notturni della factory prima che UNO chiuda end-to-end con il DoD verificato — e si sveglia con card "done" fiduciosamente sbagliate.**

Si compone di due cose che ho verificato con i miei occhi: (1) la factory dichiara `done` sul solo `exit 0`, senza mai guardare l'artefatto (P0); (2) il suo unico giro reale è 0/4 e il fix è committato ma non riprovato (P1). Insieme significano che il percorso di esecuzione autonoma del sistema può produrre **fallimenti travestiti da successi** — che è **peggio di nessuna automazione**, perché erode il segnale su cui Roberto fonda la fiducia (artefatti, non parole). Il sistema che predica "claims without evidence are rejected" ha un motore autonomo che accetta claim senza evidence. Chiudi quel loop — verifica il DoD, non l'exit code — prima di dargli in mano una notte.

---

### Dove concordo / dissento da Fable

- **Concordo:** finding sulla factory morta 4/4 e sullo stato falso delle card (§0); due fonti di verità (§1.1); gate honor-system + attrito `autonomous:true` (§1.4); rc==0 non prova il DoD (§3.3, ma io lo alzo a P0); contraddizione embedder (§1.3); patch bge-m3 fragile (§3.1); USAGE.md mancante; over-engineering evitato bene.
- **Dissento / correggo:** (a) Fable elenca "manca lo stato blocked" tra i FIX — **obsoleto**, `kb block` esiste (`kb.sh` 94-102). (b) Fable prende il fix factory come "dato acquisito" e chiude il caso; io verifico che i binari si risolvono davvero *ma* insisto che 0/4 + mai-riprovato = **non provato, non fixato** — "committato ≠ funziona" è esattamente la cicatrice del sistema. (c) Sposto la larghezza del meta-loop da un implicito "forse troppo" a un esplicito **FREEZE, non KILL** — prematuro non è teatro.

*Un secondo giudizio che ripete il primo non vale niente. Il valore qui è aver toccato i file con mano e aver segnato i tre punti dove Fable è invecchiato o si è fermato troppo presto.*
