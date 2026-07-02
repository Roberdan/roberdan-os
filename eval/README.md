# eval — does the behavioral canon actually change agent output?

`docs/roberdan-os-paper-en.md` §9.1 has real quantitative ablation for the retrieval/embedding
side of this system (R@k, MRR, mean rank, a model ablation). The behavioral canon —
`behavior/roberto-mode.md`, `behavior/roberto-voice.md`, `behavior/thinking-toolkit.md`,
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

## Method

**N=10 representative tasks × 2 conditions × blind pairwise judging.**

1. **Tasks** (`eval/tasks/*.md`) — 10 small, self-contained fixtures across the 6 surface
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
   see whether e.g. `roberto-voice.md` moves the needle more than `thinking-toolkit.md`), and the
   same "what this does and doesn't prove" section as this README. Tasks whose `canon:` matches
   `skills/*/skill.md` (case-insensitive) are run and judged like any other, but reported in a
   **separate, qualitative-only table** and excluded from the aggregate summary and the
   per-canon-file ranking — see the "Skill-type canon tasks" section `report.sh` generates, and
   the caveat under condition B above.

## What's real vs. what's stub

**This container has no usable headless `claude` binary** — `eval_resolve_claude` in
`eval/lib.sh` (same PATH + fallback-path resolution as `factory/run.sh`) comes back empty here.
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
eval/run-eval.sh          # condition A + B for all 10 tasks -> eval/results/<id>/{a,b}.md
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
| `eval/tasks/*.md` | 10 task fixtures (prompt + checklist + `canon:` pointer) |
| `eval/lib.sh` | shared bash helpers: frontmatter/section parsing, `claude` resolution, JSON extraction, banner stripping |
| `eval/run-eval.sh` | generates condition A/B outputs |
| `eval/judge.sh` | blind pairwise judging |
| `eval/report.sh` | aggregates verdicts into `eval/results/report.md` |
| `eval/test-eval-pipeline.sh` | stub-mode end-to-end test of the whole pipeline; wired into `test/validate.sh` |
| `eval/results/` | generated, gitignored |

## Caveats (see also `eval/report.sh`'s closing section, generated fresh each run)

- **Small N.** 10 hand-written fixtures, not a representative sample of everything the canon
  touches.
- **Single judge model, same family as the subject.** Judge and subject share whatever blind
  spots the underlying model has — the same caveat `docs/roberdan-os-paper-en.md` makes about
  focus-group persona sycophancy: a simulated evaluator can be systematically wrong in ways it
  can't see about itself.
- **One run per task per condition.** No repeated trials to measure variance; a single sample
  could land on either side of the model's actual output distribution.
- **Compliance ≠ Roberto's actual preference.** Restated from the top of this file because it's
  the most important caveat: this is a proxy, not the real test.
