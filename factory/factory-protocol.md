# factory — autonomous agent factory (Convergio's job, without Convergio)

Runs queued tasks through **headless agents**, one after another, unattended and resumable —
the "agent factory" that keeps going while you sleep. Built on the current architecture only:
one headless CLI (`-p` mode) + a durable file queue + `launchd` + the loop-protocol. No daemon,
no Convergio, daemon-optional.

**Engine: GitHub Copilot CLI by default** (`FACTORY_ENGINE=copilot`, since 2026-09-13). Roberto's
rule is that unattended work never spends the Claude subscription, so every launch site in
`factory/` and `eval/` goes through the single `launch_agent()` in `factory/lib.sh`. Copilot also
brings a **native deny list** Claude has no equivalent for: `--deny-tool 'shell(git push)'`
overrides `--allow-all-tools` (verified live), which is the third guard layer below.
`FACTORY_ENGINE=claude` switches back deliberately — it is never the default and never implicit.

> Unrelated to **Warp Factories** (Early Access since Warp 2026.08.18), which is Warp's own
> cloud build infrastructure plus a built-in Factory MCP server. Not adopted: an MCP server that
> arrives enabled with a client update does not pass the review gate in
> `rules/best-practices.md` § Security & Privacy.

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
  (`copilot -p "<task>" --model <claude-sonnet-5|claude-opus-5.5> --allow-all-tools --deny-tool ... --add-dir <dir>`;
  with `FACTORY_ENGINE=claude`: `claude -p "<task>" --model <sonnet|opus> --permission-mode auto --permission-prompts none --add-dir <dir>`),
  capture the log. See "Model policy" below for how `<sonnet|opus>` is chosen.
  **A task only reaches `done/` on exit 0.** On failure it is requeued once (attempt 2/2); if
  it fails again it moves to `failed/` with `escalate: true` — never silently marked done.
  **Resumable:** state lives in the filesystem (queue/ → done/ or failed/), so a killed run just
  re-processes what's left. Loops until the queue is empty or `MAX` is hit.
- If any task fails in a run, a summary is appended to `handoff/latest.md` so the next session
  sees it — a failure that only lives in `logs/` is a failure nobody sees.
- **A mid-stream cutoff is no longer a failure** (claude-code ≥ 2.1.247): in `-p` mode a response
  cut off by a server error, a dropped connection or a stall is continued automatically instead of
  ending with an error. So `failed/` now means the *task* failed — not that the network hiccuped.
  Nothing above changes: `done/` still requires exit 0, and a non-zero exit still goes through the
  same retry-then-`failed/` path. Worth knowing when reading an old log: pre-2.1.247 entries in
  `failed/` include transient cutoffs that today would have recovered on their own.
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

`run.sh` always passes an explicit `--model` to the engine — it never lets the process fall
through to the account's interactive default model. That default is whatever Roberto's account
happens to be set to at the time (it has been the pricier Fable), and a headless `-p` run silently
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
  sonnet` — it is never passed through raw and never causes the task itself to fail. The aliases
  are mapped to the engine's real ids by `engine_model()` (copilot: `sonnet`=claude-sonnet-5,
  `opus`=claude-opus-5.5), so the allowlist keeps working unchanged across engines.
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
itself, not the whole `~/GitHub` tree, since auto mode approves routine writes inside whatever
`--add-dir` points at. What auto mode would ask about is **denied**, not allowed:
`--permission-prompts none` turns every would-be prompt into a refusal, so an unattended run never
hangs and never gets a blanket yes. **Which** commands get denied is the auto-mode classifier's
judgment, not a fixed list: it weighs the task text and context, and it can change between releases.
Measured 2026-09-12: `git commit --amend` on a throwaway local repo was denied in 2 runs (v2.1.269, similar
prompts) and allowed in 5 (launchd and foreground, v2.1.269 and v2.1.270, one identical prompt). The only deterministic blocks are
the hooks. So every factory run also loads **`hooks/factory-guard.sh`** through `--settings` (both
the task run and the @thor verify run): a fixed list that denies, every time, `git push`, history
rewrites (`commit --amend`, `rebase`, `reset --hard`, `filter-branch`, ref/reflog/stash deletion),
`git clean -f`, `branch -D`, `--no-verify`, `rm -rf` in any flag order, `find -delete` and `gh`
write actions (PR create/merge, releases, repo edits, `gh api` writes). It reads the raw command,
quotes included, so `bash -c "git push"` is caught too. `factory/run.sh` refuses to start if the
guard file is missing, because a hook whose script is gone errors out and lets the command through.
Interactive sessions never load it.

**Second layer — `factory/shims/{git,gh,rm}`, first on the agent's `PATH`.** The guard above reads
the command as *text*, so it can only refuse spellings it recognises, and @thor out-spelled it three
times in a row on the same command: `git commit --am"end"`, `/usr/bin/git push`,
`git${IFS}commit${IFS}--amend`, `{git,commit,--amend}`. Each of those is the shell rewriting the
text before anything executes, so chasing them one regex at a time cannot end. The shims sit on the
other side of that line: they are ordinary `git`/`gh`/`rm` executables that inspect `"$@"` **after**
the shell has finished expanding, refuse the same fixed list with exit 97, and `exec` the real
binary for everything else. A new spelling is not a new bypass, and the coverage extends to shapes
no text match can see: a script written to a file and then run, a `python`/`node` subprocess, a
command built from variables. `run.sh` exits 126 if any shim is missing or not executable — one
layer gone is an unguarded run, not a degraded one.

**Neither layer alone is honest, which is why there are two**: the shims are blind to a call that
skips `PATH` (`/usr/bin/git push`), and that is exactly the spelling the text guard catches; the
guard is blind to everything the shell rewrites, and that is exactly what the shims catch. Still
not a sandbox: a copy of the binary under another name, or a language runtime doing the equivalent
work in-process, passes both. Queue only tasks you would approve by hand.

## Guardrails (autonomous ≠ reckless)

- Each task is **scoped** to a dir (`--add-dir`) and has a **timeout**.
- The dispatched agent still reads `AGENTS.md` → **human gates hold** (it won't merge to main, push,
  spend, or delete non-regenerable data autonomously; it leaves those as proposals).
- Everything is **logged** (`logs/`); nothing is silent.
- Prefer tasks that are **additive + verifiable** (write code + tests, draft a doc, research).
  Do NOT queue irreversible/outward-facing tasks for unattended runs.
- Parallel tasks that mutate the same repo should use `git worktree` isolation (planned —
  no `RDA_FACTORY_PARALLEL` flag is implemented yet; today `run.sh` executes tasks serially).

## Config (env)

`RDA_FACTORY` (default `~/.roberdan-os/factory`) · `RDA_FACTORY_WORKDIR` (default `~/GitHub/roberdan-os`) ·
`RDA_FACTORY_MAX` (tasks/run, default 8) · `RDA_FACTORY_TIMEOUT` (default 1800s) ·
`RDA_FACTORY_MODEL` (default model for tasks without a per-task `model:`, clamped to
`sonnet`|`opus` — see "Model policy" above).
