---
name: auto-checkpoint
description: Portable "loop kit" — inject durable state, terminal-condition, auto-resume and auto-escalation into any session. Makes the loop reliable without a daemon.
providers: [claude, copilot, codex]
---

# auto-checkpoint — il kit loop portatile

Kit iniettabile in qualsiasi sessione per renderla loop-affidabile **senza daemon**.
Implementa il contratto di [`loop/loop-protocol.md`](../../loop/loop-protocol.md):
stato durevole, terminal-condition, auto-resume, auto-escalation.

## Cosa fa
- **Scrive/legge stato durevole** — `state.db` a path noto + `.agent-state/<task>.jsonl` (cursor append-only).
- **Definisce la terminal-condition** — un check empirico su ground truth, non una stima.
- **Abilita auto-resume** — all'avvio rilegge lo stato, riparte dall'ultimo step `done`.
- **Abilita auto-escalation** — 2 fail sullo stesso problema → opus + log del motivo.

## Stato (daemon-optional)
```
state store:  ~/.convergio/v3/state.db  (se presente)
              ~/.roberdan-os/state.db    (fallback)
cursor:       .agent-state/<task>.jsonl  (gitignored, 1 record/step + evidenza)
timestamp:    RFC3339
```
Convergio, se attivo, **legge** lo stesso state — osservatore opzionale, mai dipendenza.

## Loop (pseudo)
```
on start:
  state = read(state.db, cursor)         # resume idempotente
  step  = last_done(state) + 1
loop:
  result = execute(step)
  append(cursor, {step, result, evidence})   # checkpoint = 1 commit/fase, evidence-first
  if terminal_condition(): break              # verifica empirica (thor / check job-specific)
  if failed_twice(step): escalate(opus); log(reason)
  if no_progress(2 passes): STOP; report_wedged(); break
  step += 1
on each phase end:
  post_task_sync()                             # vault + cvg + repo
```

## Driver per-platform
- **Claude Code:** `/loop` + `ScheduleWakeup` per attese esterne (CI/deploy/embed) —
  `submit → wakeup +Nmin → check terminal-condition → done | re-arm`.
- **Altri:** `launchd`/`cron` rileggono il cursor e rilanciano fino alla terminal-condition.

## Segnalazione
Ogni checkpoint = update evidence-first: `[fase N/M ✓] commit <sha> · <check> · next: …`.
Mai "sto lavorando".
