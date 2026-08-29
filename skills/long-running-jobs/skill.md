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
  log `.jsonl`, gstack `/context-save`. Le notifiche dei background task arrivano tardi e in
  disordine — reinterroga la ground truth prima di riportare lo status.
- **Monitora i subagent reali** (Agent tool / `TaskList` / `Monitor`): polla, continua o
  stop+ricrea quelli incastrati passandogli lo stato persistito.
- **Copilot CLI ≥ 1.0.83 (weekly release "August 24", pubDate 2026-08-28) restores sessions that
  did not exit cleanly, including one interrupted mid-turn** — resume the session before
  re-reading the card and rebuilding state from scratch; confirm the version after
  `copilot update`, this predates the installed 1.0.82-1.
