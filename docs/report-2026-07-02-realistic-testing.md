# Report 2026-07-02 — realistic testing round + updated plan

Segue l'analisi Fable post-merge ([`docs/archive/`](archive/) per i giudizi precedenti). Questo
documento chiude il giro: evidenza empirica reale (non teatro, non stub), poi un piano eseguibile.

## 0. Cosa è stato testato per davvero (non teoria)

| Test | Metodo | Esito |
|---|---|---|
| Eval harness reale | `eval/run-eval.sh` (no `--stub`) — 10 fixture × 2 condizioni, claude reale | 20/20 generazioni riuscite |
| Giudizio blind pairwise | `eval/judge.sh` — 10 verdetti, claude reale come giudice | 10/10 verdetti parsati |
| Recall gbrain dal vivo | query reali (Convergio, Microsoft, FightTheStroke) | Funziona correttamente su query genuine |
| Factory + verifica @thor headless | task isolato reale, claude vero (non stub) end-to-end | **Bug trovato e corretto** (vedi §2) |
| gstack smoke test | invocazione `/health` | Interrotto: overhead di onboarding non pertinente per questo repo (vedi §3) |

## 1. Verdetto Fable (sintesi — vedi il testo integrale nella cronologia sessione)

Il sistema **sta ancora auditando se stesso**, ma il backlog interno è **strutturalmente esaurito**:
le 5 card in `todo/` sono tutte gated su una decisione di Roberto. Non è pigrizia del sistema — è
la conseguenza logica di aver chiuso tutto il lavoro interno legittimo. 4 gap genuini identificati,
di cui 3 chiusi in questa sessione (vedi sotto), 1 richiede una decisione.

## 2. Il finding più importante: bug reale trovato SOLO grazie al test realistico

**`factory/run.sh` non faceva mai `cd "$dir"` prima di lanciare claude.** `--add-dir` concede
accesso al filesystem ma non cambia la working directory del processo — che restava sempre dove
`run.sh` era stato lanciato (in produzione: la root del repo roberdan-os). Scoperto lanciando un
task isolato reale che doveva scrivere un file "nella directory corrente": il file è finito nel
repo di roberdan-os invece che nella working dir prevista. Ogni task factory mai eseguito
(incluso il run reale che ha prodotto il commit `4fc5537`) è stato esposto a questo — mascherato
finora solo perché i prompt tendono a specificare path assoluti.

**Fix committato e verificato** (`0b372cb`): `cd "$dir"` in subshell prima di ogni invocazione
claude (sia il pass principale che il verify @thor), con test di regressione che conferma la
cattura del bug (disattivato il fix, il test fallisce con esattamente il sintomo osservato dal
vivo; riattivato, verde).

Questo è esattamente il tipo di scoperta che il test teatrale (stub, auto-audit) non può fare — è
emerso da un task reale con un claude reale che ha fatto qualcosa di inatteso.

## 3. Gap Fable — stato dopo questa sessione

| Gap | Stato |
|---|---|
| `verify_card` mai testato con claude reale | ✅ **Chiuso**: test isolato reale eseguito, verdict PASS accurato, sync sulla card confermato — e ha rivelato il bug del §2 come bonus |
| 4 artefatti fasulli `exit_127` ancora in `factory/done/` | ✅ **Chiuso**: spostati (non cancellati) in `factory/done/_superseded-2026-07-01-exit127-bug/` |
| Skill shadowing/mai installate | ⚠️ **Parzialmente chiuso**: `sync`, `verify-done`, `auto-checkpoint` installati ora (symlink a `platforms/claude/skills/`, nessuna collisione, verificati disponibili). `review`/`ship` **restano in conflitto** con le skill gstack omonime (gstack le ha vendorizzate come symlink sotto lo stesso nome) — **decisione per Roberto**, vedi piano §5. |
| `FtS-ingest` dod in tensione con `vault-fts` | Non nuovo, già in flag nella card — resta bloccata su scelta corpus |

## 4. Eval reale: cosa dice davvero (non nascosto, non gonfiato)

Risultato onesto: **6/10 task preferiscono la condizione SENZA canone**. Non è un fallimento da
minimizzare — è esattamente il tipo di segnale che l'harness esiste per catturare. Due letture
distinte, verificate leggendo gli output reali, non solo i punteggi:

**Artefatto di metodo (2 casi, i peggiori: -7.00 e -3.00).** I due task con `canon:
skills/premortem/skill.md` e `skills/focus-group/skill.md` crollano perché l'harness **incolla
l'intero file skill come contesto passivo** invece di invocarlo come skill reale. Verificato
sull'output: l'agente prova a seguire alla lettera il rituale procedurale della skill (che
richiede di chiarire "come si misura il successo" prima di procedere) e produce una domanda di
chiarimento invece della risposta diretta che il task chiedeva ("talk me through it"). Comportamento
corretto per un'invocazione reale di skill, sbagliato per iniezione-come-contesto. **Non è evidenza
che le skill siano cattive — è un difetto di metodo dell'harness**, da correggere (vedi piano).

**Tensione genuina (4 casi sui file `behavior/*.md`).** Esempio verificato (`03-status-update`):
l'output con canone è più rigoroso (flagga esplicitamente il giorno senza evidenza, aggiunge una
colonna "Evidenza"), ma il giudice lo penalizza per essere più formale/tabellare rispetto alla voce
"calda e breve" di Roberto — probabile causa: il task iniettava solo `roberto-mode.md` (canone
evidence) senza `roberto-voice.md` (canone voce), quindi il fixture testa un canone parziale, non
tutto il sistema comportamentale insieme. Segnalato come possibile difetto di scoping dei fixture,
non necessariamente un difetto del canone.

**Cosa NON prova questo giro** (dichiarato dallo stesso report, `eval/results/report.md`): non
sostituisce gli occhi di Roberto su un campione reale di transcript; N=10 è piccolo; giudice e
soggetto condividono la stessa famiglia di modello.

## 5. Piano aggiornato — solo lavoro reale, eseguibile

Ordinato per chi può eseguirlo. Niente auto-audit manufatto: dove il prossimo passo legittimo è
esterno (dipende da Roberto), lo dico invece di inventare filler interno.

### Eseguibile da agente ora (sonnet, additivo, nessun gate)

1. **Correggere il metodo di iniezione canone dell'eval harness per i file-skill.** Quando
   `canon:` punta a `skills/*/skill.md`, non prependere l'intero file come testo passivo — o (a)
   escludere i task skill-type dalle statistiche aggregate con nota esplicita del perché, o (b)
   iniettare solo la sezione "quando attivare" invece dell'intero rituale procedurale. DoD:
   `eval/run-eval.sh` distingue i due tipi di canone; i due fixture 08/09 non inquinano più il
   punteggio aggregato senza spiegazione. Modello: **sonnet** (scoping chiaro, meccanico).
2. **Verificare/correggere lo scoping dei fixture `behavior/*.md`**: il task 03 (status-update)
   testa solo `roberto-mode.md` ma un vero status update tocca anche la voce — verificare se altri
   fixture hanno lo stesso problema (canon incompleto per il tipo di task) e correggere il campo
   `canon:` dove serve. DoD: ogni fixture dichiara tutti i file canone realisticamente rilevanti
   per il tipo di task, non solo uno. Modello: **sonnet**.
3. **Formalizzare in `bin/sync.sh --install` l'installazione automatica delle skill senza
   collisione** (il pattern usato a mano in questa sessione per sync/verify-done/auto-checkpoint):
   symlink da `~/.claude/skills/<nome>/SKILL.md` a `platforms/claude/skills/<nome>/SKILL.md`,
   SOLO per nomi non già occupati da un'altra skill. Skip esplicito (con messaggio) per i nomi in
   collisione, mai override silenzioso. DoD: `bin/sync.sh --install` esegue questo passo
   automaticamente, wired in test se possibile. Modello: **sonnet**.

### Richiede una decisione di Roberto (gate esplicito)

4. **Collisione `review`/`ship`**: le skill gstack occupano quei nomi (symlink verso
   `~/.claude/skills/gstack/{review,ship}/SKILL.md`). Opzioni: (a) rinominare le skill roberdan-os
   (es. `roberdan-review`, `roberdan-ship`), (b) lasciare che gstack vinca su quei nomi e
   documentare che roberdan-os non ha `/review`/`/ship` propri, (c) qualcos'altro. Nessuna opzione
   è ovviamente giusta — dipende da quale workflow usi più spesso. Non risolvo alla cieca.
5. **FtS-ingest**: scelta corpus A/B/C (pacchetto decisionale già pronto nella card).
6. **G5-always-on**: decisione architetturale (ADR di sicurezza pronto).
7. **X-msft-triage pilota da 1 giorno** (non la settimana intera della card originale, per
   de-rischiare lo scoping): Roberto sceglie un giorno reale, il twin fa solo flag+draft mai send,
   lui annota tempo/qualità. Proposto da Fable come scenario a leva alta e ingresso basso.
8. **X-convergio-decision / X-fts-initiative**: entrambe esplicitamente "not startable blind" —
   richiedono scoping di Roberto prima che un agente possa iniziare.

### Nota sull'eval — il campione umano resta insostituibile

Punto 8 del README dell'harness, confermato da questo giro: **un campione dei 10 transcript reali
letto da Roberto** (non il punteggio del giudice) è l'unico modo di sapere se il canone produce
output che lui preferirebbe davvero. Il giudice è una terza chiamata claude, non un sostituto del
suo giudizio. Non è nel piano come azione-agente perché non è delegabile.

## 6. Esecuzione di questa sessione (evidenza)

- Commit `0b372cb`: fix bug cd/cwd + test di regressione (vedi §2)
- `factory/done/` ripulito dai 4 artefatti fasulli (filesystem locale, non versionato in git)
- 3 skill installate (`sync`, `verify-done`, `auto-checkpoint`), verificate disponibili nella
  lista skill di questa sessione
- `eval/results/` popolato con 20 output reali + 10 verdetti + report aggregato
- `test/validate.sh`: ✅ ALL GREEN dopo ogni commit
