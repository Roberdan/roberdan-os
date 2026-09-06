---
name: long-running-jobs
description: "Discipline for background/async jobs and subagents that can be interrupted or stall — durable state, terminal-condition checks, resume-not-redo, artifact-based progress tracking."
providers: [claude, copilot, codex]
---

# Long-running & background jobs

Brought into the canon repo 2026-08-29 — it lived only as a hand-installed file outside
`~/GitHub` (`~/.claude/skills/`, `~/.agents/skills/`, `~/.junie/skills/`), three unsynchronised
copies that had already drifted from each other on one line. Versioned here from now on;
`bin/sync.sh --install` is the only thing that should write `~/.claude/skills/long-running-jobs/`
and `~/.copilot/skills/long-running-jobs/` going forward.

Agenti e comandi background si interrompono, scadono, stallano. La cura è lo **stato durevole
del job**, mai la chat: il lavoro riprende invece di ripartire.

- **Verifica alla terminal condition, non al singolo run.** Job ripristinabili (embeddings,
  batch sync, indexing, migrazioni): mai "done" dopo un run — controlla lo stato del job
  (`0 unembedded chunks`, `last_commit == HEAD`) e **rilancia fino al traguardo**; preferisci
  un runner self-looping (es. `gbrain-embed-until-done`).
- **Task tagliato/stallato → rilancia, non rifare.** Un job ben fatto legge lo stato persistito
  e continua. Due pass consecutivi senza progresso = incastrato davvero: STOP, di' cos'è
  bloccato (riga oversize, chiave mancante, lock), non loopare.
- **Progresso in artefatti durevoli**, non in conversazione: conteggi DB, checkpoint file,
  log `.jsonl`. `kb pause --context` / [[auto-checkpoint]] conservano lo stato del lavoro;
  gstack `/context-save` e' solo un'aggiunta per la conversazione. Prima di riportare lo
  status, confronta la notifica con gli artefatti reali.
- **Monitora i subagent reali** (il tool di delega dell'host: `task` su Copilot, `Agent` su
  Claude, altri monitor solo se disponibili). Su Copilot attendi la notifica automatica,
  poi leggi il risultato una volta con l'ID noto: niente polling o riscoperta degli ID.
  Background solo quando c'e' lavoro indipendente da svolgere; altrimenti delega sincrona.
  Su host senza notifiche, controlli distanziati secondo durata e progresso attesi.
  Modello/effort/context vengono da [[model-selection-policy]], mai a memoria.
- **Prima di compattare:** salva ID, proprietario, ambito, artefatti, ultima osservazione
  e prossimo controllo dei job nella sezione `pending` della capsula. Dopo la ripresa
  riconcilia gli ID noti con lo stato reale; non avviare copie di agenti ancora attivi.
  Processi shell collegati alla sessione per default; sopravvivenza alla chiusura solo
  quando richiesta esplicitamente e supportata dall'host.
- **Cancellato non significa annullato:** un timeout, una connessione MCP interrotta o un
  agente senza risposta non dimostrano che gli effetti non siano avvenuti. Verifica
  artefatti/stato prima del retry; se l'esito di un'azione non ripetibile resta ignoto,
  fermati su quel passo. Non uccidere un job sano per liberare contesto.
- **Ripresa nativa:** usa il recupero sessione dell'host se disponibile, poi rileggi
  checkpoint e card. Verifica la versione effettiva: non assumere supporto dal nome di
  un modello. I turni lunghi richiedono checkpoint di fase, non solo quello a fine turno.
