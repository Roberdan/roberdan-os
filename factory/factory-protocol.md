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
  (`claude -p "<task>" --model <sonnet|opus> --dangerously-skip-permissions --add-dir <dir>`),
  capture the log. See "Model policy" below for how `<sonnet|opus>` is chosen.
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
card: T-example-id             # optional: kanban card id this task fulfills
model: sonnet                  # optional: sonnet (default) | opus — see "Model policy" below
---
<the task / goal, in natural language — the agent reads AGENTS.md and works in roberto-mode>
```

### Model policy — always sonnet, scale to opus on need, never the account default

`run.sh` always passes an explicit `--model` to `claude -p` — it never lets the process fall
through to the account's interactive default model. That default is whatever Roberto's account
happens to be set to at the time (it has been the pricier Fable), and `claude -p` silently
inherits it when `--model` is omitted; an unattended factory must not ride that default.

- **Default: `sonnet`** for every task unless overridden.
- **Per-task override**: set `model: opus` in a task's frontmatter for tasks that genuinely need
  the extra reasoning depth (complex architectural work, hard bugs, high-stakes artefacts — see
  the model-selection decision table in the global instructions). Read via the existing `field()`
  helper, same as `dir:`/`timeout:`/`card:`.
- **Global override**: `RDA_FACTORY_MODEL` env var changes the default for tasks that don't set
  `model:` explicitly.
- **Allowlist is hardcoded to `sonnet` and `opus` only** — never any other value, and in
  particular never `fable`. Both the per-task `model:` field and the `RDA_FACTORY_MODEL` env
  override are clamped through this allowlist before reaching the `claude` command line. An
  unrecognized value (typo, empty string, `fable`, `haiku`, anything else) is clamped to
  `sonnet` and logged as `[factory] WARN model '<x>' not allowed (sonnet|opus only) — clamped to
  sonnet` — it is never passed through raw and never causes the task itself to fail.
- **The headless @thor verification pass always uses `sonnet`**, unconditionally — it is QA
  (compare evidence against `dod:`/`acceptance:`), not authorship, so it never scales to opus and
  is unaffected by `model:` or `RDA_FACTORY_MODEL`.

If `card:` is set, `run.sh` appends a `factory_result:` line to that kanban card (wherever it
currently lives — todo/doing/done) after every attempt: success, retry, or final failure. This is
the only thing that keeps kanban `doing/` and the factory's `queue/ → done/|failed/` from drifting
apart — without it, a card can say "doing" while the factory says "failed" and nothing points from
one to the other. **A factory exit 0 is not a kanban done: it only proves the process didn't crash,**
not that the DoD/acceptance was met — `@thor` still has to validate before `kb finish`.

### Headless @thor verification pass (closing the "exit 0 ≠ DoD" gap)

When a task exits 0 **and** declares `card: <id>`, `run.sh` runs a **second** headless pass before
trusting the result — same invocation conventions as the task itself (timeout wrapper, billing-safe
env, `logs/<ts>-<name>-thor-verify.log`). The prompt embodies `@thor` (see `agents/thor.md`: fresh
context, evidence-only, zero tolerance for incomplete work) and reads the referenced card's `dod:`
and `acceptance:` fields:

> Given these acceptance criteria [`dod:`/`acceptance:` from the card] and this repo state, verify
> with concrete evidence (files, commits, test output) whether they are met. Output exactly
> `VERDICT: PASS — <evidence>` or `VERDICT: FAIL — <reason>` as the last line.

`run.sh` parses the last `VERDICT:` line in the verification log:

- **PASS** → the task proceeds to `done/` as before, and the card gets an extra annotation:
  `headless thor pass PASSED (<evidence excerpt>) — still needs human kb finish`. This is a
  factory-level signal, not a kanban gate: `kb finish` still requires a human-supplied `--thor`
  evidence string (see `kanban/README.md`) — the headless pass narrows what a human has to check,
  it doesn't replace `kb finish`.
- **FAIL or unparseable** (verification process errors, times out, or never prints a `VERDICT:`
  line) → routed through the **exact same** retry/failed path as a task that exits non-zero: retried
  once, then filed under `failed/` with `escalate: true` if it fails again. The card annotation notes
  the verdict text (or the parse failure) so the reason is visible without opening the log.
- **No `card:`** → today's behavior is unchanged: no verification pass runs, exit 0 goes straight to
  `done/`.

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
`RDA_FACTORY_MAX` (tasks/run, default 8) · `RDA_FACTORY_TIMEOUT` (default 1800s) ·
`RDA_FACTORY_MODEL` (default model for tasks without a per-task `model:`, clamped to
`sonnet`|`opus` — see "Model policy" above).
