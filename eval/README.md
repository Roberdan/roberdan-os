# eval — does the behavioral canon actually change agent output?

`docs/roberdan-os-paper-en.md` §9.1 has real quantitative ablation for the retrieval/embedding
side of this system (R@k, MRR, mean rank, a model ablation). The behavioral canon —
`behavior/roberto-mode.md`, `identity/voice.md`, `behavior/thinking-toolkit.md`,
`rules/constitution.md`, `rules/best-practices.md`, `agents/*.md` — has never had the equivalent.
It's asserted, never measured. This directory is that measurement.

## Honest limitation, stated up front

This harness measures **stated behavioral compliance and output quality against an explicit
checklist** — does a response cite evidence before claiming done, open warm instead of
corporate-formal, pick one reasoning lens instead of parading five, recognize a human-gate and
stop instead of guessing. It does **not** measure the deeper claim that **Roberto himself** would
prefer the with-canon output. The judge is a third headless `claude` call, not Roberto. Closing
that gap requires his eyes on a sample of real transcripts — this harness produces exactly the
sample worth showing him, it doesn't replace the showing.

## The mechanism limitation — read this before trusting any result

**The one recorded real run did not show the canon winning.** On the 8 core tasks it was 4–4
(and 4–6 across all 10 judged runs once the 2 skill-type tasks are counted, favoring no-canon).
That is a real result and it is reported honestly in `eval/results/report.md`. It does **not**
mean "the canon is worthless" — it means **this harness measures a specific, impoverished version
of the canon**, and a null/negative result here is a fact about *this setup*, not about the system
as it actually runs.

Here is the mechanism gap, stated plainly:

- **Condition B prepends the canon as passive text.** `eval/run-eval.sh` reads the task's declared
  `canon:` file(s) and pastes them verbatim ahead of the prompt, then makes a single headless
  `claude -p` call. That is the *entire* activation.
- **The real system does not work by pasting text.** In a live session the canon reaches the agent
  through **selective activation**: `AGENTS.md`/`CLAUDE.md` point at behavior/rules on demand,
  **hooks fire** (Stop-hook auto-pause, autofmt, post-task-sync — which itself runs leak-check), **subagents get
  invoked** at the right moment (`@thor` as the done-gate, `@rex` for review, `@twin` for voice,
  `@board` for red-teaming), and **skills load as multi-step procedures** when their trigger is
  hit. None of that is a static string prepended to a prompt.
- **So prepend-as-context under-represents the canon for *all* file types, not just skills.** The
  README already conceded the narrow case — a `skills/*/skill.md` is written to be *invoked*, not
  pasted, so `eval/report.sh` excludes those 2 tasks from the aggregate (see the "Skill-type canon
  tasks" methodology note it generates). The broader, more important point: even a `behavior/*.md`
  or `rules/*.md` file, pasted whole into a single one-shot call, loses the *timing* and *agentic
  structure* that makes the canon work — it can dilute a short answer with tens of KB of guidance,
  or trigger an intake/clarify ritual where the task wanted a direct take. A single passive prepend
  cannot reproduce "the right agent fired at the right moment."

**What a realistic eval would need** (and what this harness does **not** do — stated so nobody
mistakes the aspiration for a delivered capability):

- Run each condition through the **actual activation path**: a session with `AGENTS.md`/`CLAUDE.md`
  wired, hooks installed (`bin/install-hooks.sh`), and subagents/skills reachable — so the canon
  is *selected and invoked*, not *pasted*. Condition A would be the same harness with that wiring
  removed.
- Judge **multi-turn transcripts and side effects** (did `@thor` block a false done? did a hook
  catch a leak? did the paused plan actually get driven to its terminal condition?), not a single
  text blob — because most of what the canon does is procedural and only visible over a trajectory.
- Use **repeated trials** and ideally a **cross-family judge** to separate signal from variance and
  from same-family self-preference.

Building that is future work; it is **not** built here. Tasks `13-release-confirm-ci` and
`14-resume-whole-plan` (added below) are execution-flavored precisely to make this visible: run
under the current prepend harness they would likely show the *same* confound as the skill tasks
(a procedural, agentic behavior flattened into one passive answer) — which is evidence **for** this
limitation, not against the canon. The honest conclusion from the recorded run is therefore: *this
measurement apparatus cannot yet see most of what the canon does.* Fixing the tasks (below) makes
them more realistic; it does **not** fix the mechanism, and this PR does not claim to.

## Fixture inventory vs. what's been run

Fixtures on disk and fixtures with a recorded result are different numbers — do not conflate them:

- **17 fixtures exist** on disk (`eval/tasks/01-*.md` … `17-*.md`).
- **10 have ever been run/judged** in a recorded report: `eval/results/report.md` (generated
  2026-07-02, covering tasks `01`–`10`). That file is **gitignored** (`eval/results/` is generated
  output, not tracked) — no run snapshot is committed to the repo; it lives only on the machine
  that generated it.
- **7 fixtures are NOT-YET-RUN**: `11` and `12` were added *after* the 2026-07-02 run and never
  appear in it; `13`–`17` are new in this change. None has a recorded verdict.

So "4–4 / 4–6" refers to the 10-task 2026-07-02 run, not to all 17 fixtures. Re-running
`eval/run-eval.sh && eval/judge.sh && eval/report.sh` on a machine with a real `claude` binary is
what would produce current-canon numbers across all 17 — and even then, subject to the mechanism
limitation above.

## Method

**17 representative task fixtures × 2 conditions × blind pairwise judging.** Fixture count and
*run* count are not the same — see "Fixture inventory vs. what's been run" below before reading any
numbers.

1. **Tasks** (`eval/tasks/*.md`) — small, self-contained fixtures across the 6 surface
   categories the canon most visibly shapes: `code-fix`, `code-review`, `email-draft`,
   `status-update`, `triage`, `done-claim`. Each is written so a canon-naive agent's *default*
   behavior plausibly violates something specific — claiming done without test output, writing a
   corporate-formal email instead of Roberto's warm-brief voice, framework-parading instead of
   diagnosing, rubber-stamping instead of pushing back, doing an irreversible action instead of
   recognizing a human gate. Each fixture carries a **checklist of observable properties**
   (not a model answer) that a canon-compliant response should exhibit, plus a `canon:`
   frontmatter field naming which canon file(s) it targets.

2. **Two conditions** (`eval/run-eval.sh`):
   - **A — no canon.** The task prompt only, exactly as a naive agent with no `AGENTS.md`/
     `CLAUDE.md` pointer would see it.
   - **B — with canon.** The task's declared canon file(s) prepended verbatim, then the task —
     mirroring how `AGENTS.md`/`CLAUDE.md` actually inject `behavior/`/`rules/` content into a
     real session (see `bin/sync.sh`). **Caveat for `skills/*/skill.md` canon:** a skill file is
     written to be **invoked** (an explicit Skill-tool procedure — multi-step ritual, often
     parallel sub-agents), not pasted as passive context; prepend-as-context is a known mismatch
     for that file type, not a faithful mirror of real skill injection. `eval/report.sh` excludes
     those tasks from the aggregate for this reason — see its "Skill-type canon tasks" section.

   Both conditions invoke the same headless `claude -p` call, resolved the same way
   `factory/run.sh` resolves it (PATH, then a fixed fallback list), with the same billing-safety
   env unset. Outputs land in `eval/results/<task-id>/{a,b}.md`. Idempotent: an existing output
   file is skipped unless `--force`.

3. **Blind pairwise judging** (`eval/judge.sh`) — a **third** headless `claude` call sees the
   task, the checklist, and both outputs labeled "Output 1" / "Output 2" in an order **randomized
   per task** (`$RANDOM`, no positional bias across the run). It is never told which output is
   which condition — the a.md/b.md files carry an HTML-comment banner naming the condition for
   human readers, and that banner is stripped before the content reaches the judge
   (`eval_strip_banner` in `eval/lib.sh`; see the note in `eval/judge.sh`). The judge scores each
   checklist property 0-2 per output and gives one holistic "which would Roberto trust more, and
   why" verdict (`output_1` / `output_2` / `tie`). Output: `eval/results/<task-id>/verdict.md`,
   with the real A/B mapping appended as a footer comment (for the aggregator only, never for the
   judge). Idempotent: skips an existing `verdict.md` unless `--force`.

4. **Aggregation** (`eval/report.sh`) — walks every `verdict.md`, maps `output_1`/`output_2` back
   to condition A/B via the footer mapping, and writes `eval/results/report.md`: a
   task × property-scores-A × property-scores-B × holistic-verdict table, a win/loss/tie summary,
   a "which canon file mattered most" breakdown (average score gap B−A per canon file, so you can
   see whether e.g. `identity/voice.md` moves the needle more than `thinking-toolkit.md`), and the
   same "what this does and doesn't prove" section as this README. Tasks whose `canon:` matches
   `skills/*/skill.md` (case-insensitive) are run and judged like any other, but reported in a
   **separate, qualitative-only table** and excluded from the aggregate summary and the
   per-canon-file ranking — see the "Skill-type canon tasks" section `report.sh` generates, and
   the caveat under condition B above.

## Tool independence — `RDA_EVAL_AGENT_CMD`

By default this harness drives headless Claude Code (`claude -p "$prompt"
--dangerously-skip-permissions --add-dir "$ROOT"`, resolved the same way `factory/run.sh` resolves
it) for all three headless calls it makes: condition A generation, condition B generation, and
the blind judge (`eval/judge.sh`). That hardcodes the eval to one tool, which contradicts the
tool-independence goal the rest of this system aims for (`AGENTS.md` is meant to work with any
coding agent, not just Claude Code).

Set `RDA_EVAL_AGENT_CMD` to point every headless call in the harness at a different agent CLI
instead:

```bash
RDA_EVAL_AGENT_CMD="copilot -p"     eval/run-eval.sh
RDA_EVAL_AGENT_CMD="hermes chat -z" eval/run-eval.sh
```

**Convention** (implemented in `eval_invoke_agent`, `eval/lib.sh`):
- `RDA_EVAL_AGENT_CMD` is the **full command** — binary plus any fixed flags, whitespace-split (no
  quoting/escaping support; keep each flag a single token).
- The prompt is delivered over **stdin**, never appended as a trailing CLI argument. Stdin beats
  "prompt as last arg" for two reasons: it works across CLIs with unrelated flag dialects without
  this harness needing to learn each tool's prompt-flag name (as long as the tool reads a prompt
  from stdin when invoked non-interactively, true of `copilot -p` and `hermes chat -z` per their
  own docs), and condition B prompts embed a full canon file (tens of KB) — stdin has no argv
  length ceiling that a single CLI argument can hit.
- The claude-specific flags (`--dangerously-skip-permissions`, `--add-dir`) are **never** passed
  when the override is set — they are meaningless, or actively wrong, for a different tool. The
  override is a fully separate invocation path, not the claude path with flags swapped in.
- Leaving `RDA_EVAL_AGENT_CMD` unset leaves behavior byte-for-byte unchanged: the default resolved
  `claude` binary, `-p "$prompt"` as a CLI arg, same flags as before.

`eval/test-eval-pipeline.sh` proves the override mechanically in stub mode: a fake command reads
the prompt from stdin, confirms no claude-specific flags reached it, and confirms the real
`claude` stub was never invoked while the override was active.

## What's real vs. what's stub

**On a machine without a usable headless `claude` binary** — where `eval_resolve_claude` in
`eval/lib.sh` (same PATH + fallback-path resolution as `factory/run.sh`) comes back empty —
The actual with/without-canon comparison using a real `claude` **has not been run**. What has been
verified in this container:

- **The harness mechanics work.** `eval/test-eval-pipeline.sh` stubs `claude` with a fake script
  (following the exact pattern `test/test-factory-kb.sh` uses to stub `factory/run.sh`: a fake
  executable dropped onto `PATH`, no network, no billing) that returns **differentiated** canned
  output per condition — condition A ("should be fine now") ignores evidence, condition B cites a
  fake commit SHA and test output — and a differentiated judge response that scores B higher. It
  then runs the real `run-eval.sh` → `judge.sh` → `report.sh`, unmodified, against that stub, and
  asserts: both outputs are produced, resumability actually skips completed pairs (and `--force`
  actually regenerates them), the judge never sees the condition banner, and `report.md` comes out
  well-formed with sane counts.
- **It is wired into CI.** `bash test/validate.sh` runs `eval/test-eval-pipeline.sh` as a real
  gate (see § below), not just a claim in this README.

**To get the real numbers, on a machine with Claude Code installed:**

```bash
eval/run-eval.sh          # condition A + B for all 17 tasks -> eval/results/<id>/{a,b}.md
eval/judge.sh              # blind pairwise judging -> eval/results/<id>/verdict.md
eval/report.sh              # aggregate -> eval/results/report.md
```

Each step is resumable — re-running after a partial/killed run only fills in what's missing;
pass `--force` to a step to regenerate everything for that step regardless.

`eval/results/` is gitignored (generated, like `platforms/`) — commit `report.md` by hand if you
want to keep a dated snapshot; otherwise regenerate on demand.

## Directory layout

| Path | What |
|---|---|
| `eval/tasks/*.md` | 17 task fixtures (prompt + checklist + `canon:` pointer) — 10 run, 7 NOT-YET-RUN; see "Fixture inventory vs. what's been run" |
| `eval/lib.sh` | shared bash helpers: frontmatter/section parsing, `claude` resolution, JSON extraction, banner stripping |
| `eval/run-eval.sh` | generates condition A/B outputs |
| `eval/judge.sh` | blind pairwise judging |
| `eval/report.sh` | aggregates verdicts into `eval/results/report.md` |
| `eval/test-eval-pipeline.sh` | stub-mode end-to-end test of the whole pipeline; wired into `test/validate.sh` |
| `eval/results/` | generated, gitignored |

## Caveats (see also `eval/report.sh`'s closing section, generated fresh each run)

- **Small N, and most not yet run.** 17 hand-written fixtures, of which only 10 have a recorded
  result (see "Fixture inventory vs. what's been run"); not a representative sample of everything
  the canon touches.
- **Passive prepend under-represents the canon.** The single biggest caveat — see "The mechanism
  limitation" up top. A null/negative result measures this impoverished activation path, not the
  live system (hooks, subagents, on-demand skills), so it must not be read as "the canon lost."
- **Single judge model, same family as the subject — declared self-preference risk.** Judge and
  subject share whatever blind spots the underlying model has — the same caveat
  `docs/roberdan-os-paper-en.md` makes about focus-group persona sycophancy: a simulated evaluator
  can be systematically wrong in ways it can't see about itself, and same-family judges are known
  to score same-family outputs more favorably than an independent judge would (self-preference
  bias). This risk is not mitigated here — `RDA_EVAL_AGENT_CMD` (see above) can point the
  *subject* calls at a different vendor's CLI, but `eval/judge.sh` still uses whatever
  `RDA_EVAL_AGENT_CMD`/`claude` resolves for the judge call too, so a same-family judge is still
  the default even in a cross-tool run unless the judge itself is deliberately run with a
  different override.
- **Order randomization mitigates position bias, not self-preference bias.** `eval/judge.sh`
  already randomizes which slot ("Output 1" / "Output 2") holds condition A vs B on every task
  (`$RANDOM`, see the "Blind pairwise judging" step above) specifically so the judge can't learn a
  positional pattern across the run — that guards against **position bias**, a different, well
  documented failure mode from self-preference bias above. The two are independent: randomizing
  order does nothing to stop a same-family judge from favoring same-family phrasing/style once it
  reads the content.
- **One run per task per condition.** No repeated trials to measure variance; a single sample
  could land on either side of the model's actual output distribution.
- **Compliance ≠ Roberto's actual preference.** Restated from the top of this file because it's
  the most important caveat: this is a proxy, not the real test.
