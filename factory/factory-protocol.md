# factory — autonomous agent factory (Convergio's job, without Convergio)

Runs queued tasks through **headless Claude Code agents**, one after another, unattended and
resumable — the "agent factory" that keeps going while you sleep. Built on the current architecture
only: `claude -p` (headless) + a durable file queue + `launchd` + the loop-protocol. No daemon, no
Convergio, daemon-optional.

## How it works

```
~/.roberdan-os/factory/
  queue/   *.md   ← drop a task here (one file = one autonomous task)
  done/    *.md   ← succeeded tasks (exit 0), moved here with result + log pointer
  failed/  *.md   ← exhausted tasks (exit≠0 after MAX_ATTEMPTS), escalate: true
  state/   *.attempts ← per-task retry counter (deleted on success or final failure)
  logs/    *.log  ← full agent transcript per task
```

- `factory/enqueue.sh "<task text or file>" [name]` — add a task to the queue.
- `factory/run.sh` — process the queue: for each task, dispatch a headless agent
  (`claude -p "<task>" --dangerously-skip-permissions --add-dir <dir>`), capture the log.
  **A task only reaches `done/` on exit 0.** On failure it is requeued once (attempt 2/2); if
  it fails again it moves to `failed/` with `escalate: true` — never silently marked done.
  **Resumable:** state lives in the filesystem (queue/ → done/ or failed/), so a killed run just
  re-processes what's left. Loops until the queue is empty or `MAX` is hit.
- If any task fails in a run, a summary is appended to `handoff/latest.md` so the next session
  sees it — a failure that only lives in `logs/` is a failure nobody sees.
- launchd `com.roberdan.rda-factory` runs `run.sh` nightly (or on demand). **Check `failed/` in the
  morning** — do not assume the queue being empty means everything succeeded.

## Task file format

```
---
dir: ~/GitHub/roberdan-os      # working dir the agent gets (--add-dir); default ~/GitHub/roberdan-os
timeout: 1800                  # seconds (optional)
---
<the task / goal, in natural language — the agent reads AGENTS.md and works in roberto-mode>
```

Always set `dir:` explicitly for tasks outside roberdan-os — the default is scoped to roberdan-os
itself, not the whole `~/GitHub` tree, since `--dangerously-skip-permissions` grants write access
to whatever `--add-dir` points at.

## Guardrails (autonomous ≠ reckless)

- Each task is **scoped** to a dir (`--add-dir`) and has a **timeout**.
- The dispatched agent still reads `AGENTS.md` → **human gates hold** (it won't merge to main, push,
  spend, or delete non-regenerable data autonomously; it leaves those as proposals).
- Everything is **logged** (`logs/`); nothing is silent.
- Prefer tasks that are **additive + verifiable** (write code + tests, draft a doc, research).
  Do NOT queue irreversible/outward-facing tasks for unattended runs.
- Parallel tasks that mutate the same repo should use `git worktree` isolation (flag `RDA_FACTORY_PARALLEL`).

## Config (env)

`RDA_FACTORY` (default `~/.roberdan-os/factory`) · `RDA_FACTORY_WORKDIR` (default `~/GitHub`) ·
`RDA_FACTORY_MAX` (tasks/run, default 8) · `RDA_FACTORY_TIMEOUT` (default 1800s).
