---
name: auto-checkpoint
description: Portable "loop kit" — inject durable state, terminal-condition, auto-resume and auto-escalation into any session. Makes the loop reliable without a daemon.
providers: [claude, copilot, codex]
---

# auto-checkpoint — the portable loop kit

A kit injectable into any session to make it loop-reliable **without a daemon**.
Implements the contract in [`loop/loop-protocol.md`](../../loop/loop-protocol.md):
durable state, terminal-condition, auto-resume, auto-escalation.

## What it does
- **Writes/reads durable state** — `state.db` at a known path + `.agent-state/<task>.jsonl` (append-only cursor).
- **Defines the terminal-condition** — an empirical check against ground truth, not an estimate.
- **Enables auto-resume** — on startup, re-reads the state, resumes from the last `done` step.
- **Enables auto-escalation** — 2 failures on the same problem → opus + log the reason.

## State (daemon-optional)
```
state store:  ~/.convergio/v3/state.db  (if present)
              ~/.roberdan-os/state.db    (fallback)
cursor:       .agent-state/<task>.jsonl  (gitignored, 1 record/step + evidence)
timestamp:    RFC3339
```
Convergio, if active, **reads** the same state — optional observer, never a dependency.

## Loop (pseudo)
```
on start:
  state = read(state.db, cursor)         # idempotent resume
  step  = last_done(state) + 1
loop:
  result = execute(step)
  append(cursor, {step, result, evidence})   # checkpoint = 1 commit/phase, evidence-first
  if terminal_condition(): break              # empirical verification (thor / job-specific check)
  if failed_twice(step): escalate(opus); log(reason)
  if no_progress(2 passes): STOP; report_wedged(); break
  step += 1
on each phase end:
  post_task_sync()                             # vault + cvg + repo
```

## Per-platform driver
- **Claude Code:** `/loop` + `ScheduleWakeup` for external waits (CI/deploy/embed) —
  `submit → wakeup +Nmin → check terminal-condition → done | re-arm`.
- **Others:** `launchd`/`cron` re-read the cursor and relaunch until the terminal-condition.

## Reporting
Every checkpoint = an evidence-first update: `[phase N/M ✓] commit <sha> · <check> · next: …`.
Never "still working."
