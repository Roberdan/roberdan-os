# Loop Protocol — the autonomous loop's standard contract

> Included (by reference) in every loop-aware `AGENTS.md`. Defines how an agent
> operates in **autonomous loop** mode, aligned with Roberto's way of working: total
> autonomy + evidence-first + empirical verification. **Reliable without a daemon**: state is
> durable on file, resume is idempotent, terminal-conditions are verified against ground truth.

---

## The contract

```
state:              <structured state.db> + .agent-state/<task>.jsonl (cursor)
session:            a loop phase is the session unit — /compact continues it, /new starts the next
terminal-condition: <job-specific empirical check — e.g. "cargo test green + CI #N pass">
checkpoint:         1 commit per phase, evidence-first message (SHA/PR/CI in every update)
escalation:         2 failed attempts on the same problem → opus, log the reason
sync-on-iteration:  post-task-sync (vault + cvg + repo) at the end of EVERY phase
resume:             read the state at startup, resume from the last done step, never redo
stuck:              2 passes with no progress → STOP, report what's wedged, don't loop
review-budget:      declared BEFORE round 1 (default 2, hard cap 3) — a review loop whose
                    exit is "the reviewer has nothing left to say" never terminates
```

## Components

### 1. Durable state (daemon-optional)
- **State store:** SQLite at a known path — `~/.convergio/v3/state.db` if present, otherwise
  `~/.roberdan-os/state.db`. RFC3339 timestamps.
- **Per-task cursor:** `.agent-state/<task>.jsonl` (append-only) — one record per step with
  outcome and evidence. `.agent-state/` is gitignored.
- **Tool receipts, not just next-steps:** every durable checkpoint carries *what ran and what
  it returned* (command, exit code, artifact path/SHA) — a transcript is useful context but not
  a recovery log; the receipts are what make resume and thor's provenance check possible.
  **Emitter: [`loop/receipt.sh`](receipt.sh)** — `receipt.sh <task-id> "<cmd>" <exit>
  [artifact] [note]` appends one JSONL record; the Stop-hook auto-checkpoint already emits a
  mechanical per-turn receipt (`session.jsonl`: HEAD + dirty count) with zero agent
  discipline. Placement is opt-in-safe: in-repo `.agent-state/` only where the repo already
  ignores it, else `$RDA_HOME/state/receipts/<repo>/` (proof: `test/test-receipts.sh`).
  Phase-commit messages + kb card audit lines remain receipts too.
- Readable both by hooks and by Convergio if active. **The loop doesn't depend on the daemon:**
  Convergio is an optional observer that *reads* the same state file, never a single point of failure.

### 2. Terminal-condition (empirical verification)
Never "should work." The end condition is a check against **ground truth**:
`cargo test` green, `gh run` SUCCESS, file existing on disk, `0 unembedded chunks`.
Verification is done by `thor` (see `agents/thor.md`) or a job-specific check.
**Probe live state, don't grade the transcript:** the check re-runs the command / queries the
system itself — a verifier that only reads the agent's own narrative can be gamed by it.

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

### 6. Session-as-phase-container (canonical home)
A loop phase is the session **container**, not the task itself — this is the single canonical
statement of the contract (referenced, not duplicated, from `rules/best-practices.md` and any
other canon file). `/compact` and `/new` are literal Copilot CLI slash commands, not conceptual
placeholders:
- **`/compact`** continues the *same* phase — routine continuation, same task, same container.
- **`/new`** (or a fresh project session / headless run) starts the *next* phase — reach for it
  at natural phase boundaries, before heavy skill/attachment work, or before changing
  model/effort (a switch mid-phase invalidates the prompt cache anyway — see Component 1's
  cache-discipline note). Never mid-phase.
- **Cutting the session changes the container, not the task.** Durable state — `kb` cards,
  `handoff/latest.md`, receipts (Component 1) — carries the plan across the cut: a small
  handoff packet (task id, last-done step, next concrete action) is enough for a fresh
  container to resume without re-deriving context. Format: `handoff/handoff-protocol.md`.

### 7. Review budget — bounded verification
**Component 4 covers a loop that keeps FAILING. This covers a loop that keeps SUCCEEDING and
still never ends**, which is the more expensive failure and has no natural brake: every round
finds something real, so every round justifies the next one.

The generating mistake is a review loop whose terminal-condition is *"the reviewer has no
further objection"*. That is not a condition, it is a perimeter. When the property under test
has an **external, mutable attack surface** — the whole machine, the network, another team's
repo — a competent adversarial reviewer can always produce one more true finding, because the
surface grows on its own. Cost then scales with rounds and value does not.

Measured instance, and the reason this component exists: proving "the agent bus never *starts*
an agent" ran **eight** adversarial rounds over one night. Every round returned a real blocker
found by execution, so nothing ever looked like the moment to stop — and the surface kept
widening under the review itself (one dispatch queue → nine → "derive the list from launchd,
because any list you write down is already stale"). The product had been finished for hours.

The rules:
- **Declare the budget before round 1**, in the card: number of rounds (**default 2, hard cap
  3**) and the scope of the property being proven. An undeclared budget is an infinite one.
- **Two rounds on the same CLASS = stop patching instances.** This is the half a counter alone
  misses. Seven rounds on one route check each found another *instance* of one class (two
  hand-written descriptions that drift apart); each round fixed the instance. That loop does
  not end by exhausting instances — it ended by changing the **shape of the guarantee** (one
  reader, and the gate asks it). So at the second round on a class, exactly two moves are
  allowed, both in one step: change the shape so the class cannot occur, or **minute it** as a
  known limit with its cost and stop. A third round of instances is refused.
- **Anything discovered while doing card X goes in a FINDINGS LIST — not in X's PR, and not
  in a new card either.** The other failure is drift, not repetition: a card that said
  *"sort before cutting"* produced a **+6153-line PR about macOS ACL permissions** over 18
  rounds. The work was good. It was not the work that was asked for. The discovery keeps; the
  scope does not.

  **Revised 2026-07-30, and it reverses what this line used to say** ("becomes a NEW CARD").
  The scar's real lesson was *"not in this PR"*; implementing it as *"make a card"* turned
  every reviewer — and reviewers are rewarded for finding one true thing — into a card factory
  pointed at the one gate that only Roberto can open. Measured that morning: **33 cards waiting
  on his approval**, 19 on a single project, most of them findings nobody had asked for, while
  that project had **zero** cards in progress. The gates were not broken; they were faithfully
  verifying an input that had already buried the work.

  A finding is a line in `docs/findings.md` (per repo), ordered by risk, each with **the
  condition that would make it worth a card**. It becomes a card only when Roberto says so.
  This is deliberately a *weaker* default than a card, because the failure mode being fixed is
  a board nobody can read — and a finding nobody triages costs one line, while a card nobody
  triages costs a gate.
- **Bound the property or bound the rounds.** If the property's surface is external and
  mutable, it cannot be closed — write down *which* surface is in scope and treat the rest as
  a declared limit, exactly like a declared survivor in a mutation suite.
- **Record the yield per round** (blockers / round, and their severity). Diminishing returns
  are a stop signal on their own: when a round returns nothing of blocking severity, the loop
  is done regardless of remaining budget.
- **When the budget is spent, STOP and hand the human a DECISION, not another round.** Exactly
  three options, with the evidence: (a) ship as it stands, with the open findings listed;
  (b) one more round, with the single named question it must answer; (c) cut the scope.
  Silence is not option (b).
- **A DEMONSTRATED live exposure overrides the cap** — and nothing else does. Without this
  counterweight the budget becomes a way to ship holes on schedule. *Demonstrated*, not
  feared: say what you ran and what it did. "An attacker could…" is a risk, and a cap that
  yields to *might* is not a cap. The override goes on the record and into the PR.
- **Cost is a terminal-condition, not an afterthought.** Wall-clock and token spend per card
  are tracked like any other metric, and crossing the declared budget escalates to the human
  *automatically* — the same way 2 failed attempts escalate the model. An agent may not spend
  a night on a card without a human saying so at the point the budget ran out.
- **A standing "keep going until it's done" does NOT authorise unbounded rounds.** It
  authorises finishing the **declared scope**. When the scope is what keeps growing, the
  standing instruction has expired and the human has to be asked again.
- **Every PR states its own round count.** `review-budget.sh line <card>` prints the line to
  paste: rounds used, the classes they hit, discoveries filed elsewhere, any override. This
  canon already says *prose did not prevent it, a gate did* — and it applies to this rule too.
  Nobody looped last night for lack of reading ability. A number that has to be **written down**
  does what prose cannot: it makes the eighteenth round embarrassing to type, before anyone
  gets round to forbidding it.

Enforcement is mechanical, not honour-based: **[`loop/review-budget.sh`](review-budget.sh)**
records each round against a card and exits 3 once the budget is spent — or at the second
round on one class, whichever comes first — so the next round has to be an explicit human
decision rather than a default. `discovery` files out-of-scope work away from the PR,
`override` takes a demonstrated exposure and only a demonstrated one, and `line` prints the
count for the PR body.

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
