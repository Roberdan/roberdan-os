# Loop Protocol — the autonomous loop's standard contract

> Included (by reference) in every loop-aware `AGENTS.md`. Defines how an agent
> operates in **autonomous loop** mode, aligned with Roberto's way of working: total
> autonomy + evidence-first + empirical verification. **Reliable without a daemon**: state is
> durable on file, resume is idempotent, terminal-conditions are verified against ground truth.

---

## The contract

```
state:              <structured state.db> + .agent-state/<task>.jsonl (cursor)
terminal-condition: <job-specific empirical check — e.g. "cargo test green + CI #N pass">
checkpoint:         1 commit per phase, evidence-first message (SHA/PR/CI in every update)
escalation:         2 failed attempts on the same problem → opus, log the reason
sync-on-iteration:  post-task-sync (vault + cvg + repo) at the end of EVERY phase
resume:             read the state at startup, resume from the last done step, never redo
stuck:              2 passes with no progress → STOP, report what's wedged, don't loop
```

## Components

### 1. Durable state (daemon-optional)
- **State store:** SQLite at a known path — `~/.convergio/v3/state.db` if present, otherwise
  `~/.roberdan-os/state.db`. RFC3339 timestamps.
- **Per-task cursor:** `.agent-state/<task>.jsonl` (append-only) — one record per step with
  outcome and evidence. `.agent-state/` is gitignored.
- Readable both by hooks and by Convergio if active. **The loop doesn't depend on the daemon:**
  Convergio is an optional observer that *reads* the same state file, never a single point of failure.

### 2. Terminal-condition (empirical verification)
Never "should work." The end condition is a check against **ground truth**:
`cargo test` green, `gh run` SUCCESS, file existing on disk, `0 unembedded chunks`.
Verification is done by `thor` (see `agents/thor.md`) or a job-specific check.

### 3. Idempotent resume
At startup: read `state.db` + the jsonl cursor, identify the last `done` step, **resume from there**.
A well-built task reads the persisted state and continues — a killed/stalled task gets
**relaunched, not redone from scratch**.

### 4. Escalation
2 failed attempts on the same problem → escalate the model (Opus for critical analysis) and
**log the reason** in the cursor. If 2 consecutive passes make no progress, it's genuinely
stuck: STOP, report what's wedged (oversized row, missing key, lock), don't loop.

### 5. Proactive reporting (anti-polling)
Every checkpoint is an **evidence-first** update:
`[phase 3/7 ✓] commit a1b2c3d · CI #4821 green · next: apply migration`
Never "still working." Roberto trusts artifacts, not words.

---

## Per-platform driver

| Platform | Driver |
|---|---|
| **Claude Code** | `/loop` + `ScheduleWakeup` for external waits (CI/deploy/embed): `submit → wakeup +Nmin → check terminal-condition → done \| re-arm`. |
| **Others (Copilot/Codex)** | `launchd`/`cron` read the same checkpoint file and relaunch until the terminal-condition. |

The injectable kit that implements this contract in any session is
[`skills/auto-checkpoint`](../skills/auto-checkpoint/skill.md).

---

## Human gates

The loop **never automates** the [human gates](../AGENTS.md#gate-umani). In particular:
merges to `main` impacting protections/security/release, force-push, external spend/emails,
irreversible deletions, strategic decisions. These always go through Roberto with a
direct message — never relayed by a coordinator.
