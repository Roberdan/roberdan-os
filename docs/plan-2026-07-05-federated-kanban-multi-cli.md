# Federated kanban + restricted multi-CLI dispatch — design (not yet built)

> **Status:** design (@baccio), awaiting `@rex` review + Roberto go/no-go. No code changed.
> **Binding input:** [`plan-2026-07-05-multi-cli-model-orchestration.md`](plan-2026-07-05-multi-cli-model-orchestration.md)
> — the adversarial review (Fable + @board + @baccio) is **settled and not re-litigated here**.
> This doc turns its verdict into an architecture.
>
> **What the review settled (verbatim constraints):**
> - "runner in `--yolo` auto-executing cards" → **rejected**. Only the **restricted sandbox** form.
> - **Two layers:** AGENTS.md/canon unifies *behavior* above a capability floor; only intercepting
>   *code* guarantees the *gates*. Gates are never prose — they are shell/filesystem/credential
>   enforcement.
> - **Empirical fact that kills inherited gates:** MirrorBuddy has a *standalone* `AGENTS.md` (not a
>   pointer to roberdan-os) and does **not** gitignore `kanban/` (verified 2026-07-05). Gate
>   inheritance via AGENTS.md is **not** guaranteed for target repos. This design assumes none.

---

## 0. The two layers, made explicit

Everything below sits in exactly one of two layers. Confusing them is the failure the review named.

| | **Layer 1 — behavior (canon)** | **Layer 2 — governance (code)** |
|---|---|---|
| Mechanism | `AGENTS.md`, `behavior/`, agent prompts, `runner:` metadata | credential absence, PATH shims, OS isolation, `mkdir` locks, leak-check, PR-only |
| Guarantees | *tendency* to behave, above a capability floor | *invariant* enforced regardless of model quality or prompt injection |
| Fails when | model is weak / injected / goal-pressured (IHEval, Compliance-Gap) | never by prompt — only by a real capability being present that should be absent |
| Travels via | the repo's AGENTS.md — **NOT guaranteed** (MirrorBuddy) | the **dispatcher in roberdan-os** — always present, target repo cannot opt out |

**Consequence for the whole design:** no gate may live in a target repo's config, because a target
repo may not inherit roberdan-os canon. Every hard gate lives in **roberdan-os dispatcher code** and
is applied *to* the target repo from outside. The target repo is treated as untrusted terrain.

**Corollary — Layer-1 filters degrade safe.** Several conveniences below (the `human-only` sentinel,
`runner:` matching, the `human_gates:` lint) are Layer-1: an author can mislabel a card. None of them
is a *guarantee*. The guarantee for any card that slips the filter is always the Layer-2 backstop
(credential vacuum + PR-only + OS floor): a mislabeled card that reaches a runner still *cannot* push,
merge, or escape. Layer-1 filters exist to catch mistakes early and cheaply; a Layer-1 miss degrades
into "the action is attempted and structurally fails", never into "the action succeeds". This is why
the design tolerates fallible labels.

---

## 1. Scope split by risk (from the review, now the module boundary)

Three pieces, three risk classes, three delivery gates:

1. **Kanban federation** — cards per-repo + an aggregating `kb`. *Organizational value, real.* Needs
   a serious per-repo privacy model (gitignore + leak-check), since MirrorBuddy proves it is not
   automatic. **Build.**
2. **`runner:` as declarative metadata** — a card *states* its ideal CLI/model. *Zero risk — a label.*
   Execution still **defaults to Claude-native** (Agent tool + `model:` frontmatter → native gates).
   **Build.**
3. **External-runner dispatcher (restricted form only)** — high risk. **Design in full here, but
   build-gated:** ships only when (a) the OS-isolation floor exists (§Node 3) *and* (b) a concrete
   use-case appears that Claude-native cannot cover. Until then it is a designed-but-dormant module,
   and its acceptance tests run against a **hostile stub**, not a real external CLI.

Federation (1) and runner-eligibility (3) are **orthogonal** and stay that way: `kb init` (privacy
scaffolding) is broad — MirrorBuddy *should* get it, for human/Claude-native work. The
`runner-allowlist` (external CLIs) is a narrow opt-in subset — MirrorBuddy is **excluded by policy**.
The discovery registry ≠ the allowlist.

---

## 2. Design decisions (a–f)

### (a) `kanban/` vs `.kanban/`; how global `kb` discovers boards

**Decision: keep visible `kanban/`** (consistency with roberdan-os today; discoverable; the content
is gitignored anyway, so hiding the *dir* buys nothing). Discovery via an **explicit registry**, not
a blind filesystem scan.

- **Registry:** `~/.roberdan-os/kanban-registry` (local-only, one repo path per line), written by
  `kb init <repo>`. Source of truth for "which repos have a federated, privacy-initialized board."
- **Why registry over `scan ~/GitHub/*/kanban/`:** a scan cannot distinguish an *initialized* board
  (gitignored + leak-check installed) from a raw `kanban/` dir someone created by hand — exactly the
  MirrorBuddy hazard. `kb init` is the act that installs the privacy scaffolding, so making init the
  thing that registers keeps "discovered" ≡ "safe". Tradeoff: one explicit `kb init` per repo (not
  zero-config). Accepted — the alternative silently federates un-gitignored boards.
- **Convenience:** `kb discover` *scans* `~/GitHub/*/kanban/` and **warns** about any board not in the
  registry (i.e. not privacy-initialized) — a linter, never an auto-includer.

### (b) local (current-repo) view vs aggregated global view

**Decision: cwd decides, gbrain-pin style.**

- `kb` inside a git repo → resolves that repo's root (`git rev-parse --show-toplevel`) and shows
  **only that repo's board**. roberdan-os keeps its own `kanban/` and behaves exactly as today.
- `kb all` (alias `kb g`) → **aggregated** view across every registry entry, each card tagged with
  its `repo:`. Reuses the existing `_repo_tag` column already in `kb.sh`.
- `RDA_KANBAN` set (tests, explicit override) → that dir wins, unchanged — preserves current
  `test/*.sh` fixtures and keeps `validate.sh` green.
- Outside any repo with no override → default to the aggregated view (most useful "where am I").

Resolution order (first match wins): `RDA_KANBAN` env → `git rev-parse` of cwd if that repo is in the
registry → aggregated. This is additive: today's tests set `RDA_KANBAN`, so they are unaffected.

**Handoff federates by the same rule (binding decision 1).** Today `handoff/latest.md` is a single
roberdan-os file. Federated: each registered repo gets its own **`handoff/latest.md`** (per-repo live
state, gitignored — see §e), while `handoff/handoff-protocol.md` and `handoff/context-primer.md` stay
**versioned** roberdan-os canon (they are tool, not state). Discovery/aggregation reuses the *same*
registry: `kb handoff` (analogue of `kb all`) concatenates every registered repo's `handoff/latest.md`
newest-first, each section tagged with its repo; inside a repo, `kb handoff` shows only that repo's.
`factory/run.sh`'s `HANDOFF` pointer is unchanged (still roberdan-os's own `handoff/latest.md`) — the
federation is additive, the aggregator reads the registry, it does not move the existing file.

### (c) card schema extension

Additive frontmatter; every field optional so existing cards and `validate.sh`'s
`title/repo/dod/acceptance/status/created` lint are unchanged.

```
---
title: ...
repo: MirrorBuddy
dod: "..."
acceptance: "..."
status: todo
created: 2026-07-05
# --- new, all optional ---
runner: copilot-cli/opus     # DECLARATIVE intent label. Grammar: <cli>/<model> | human-only
                             #   <cli> ∈ claude | copilot-cli | ollama   <model> = free label
                             #   absent  → Claude-native (factory / Agent tool), today's behavior
                             #   human-only → SENTINEL: touches a gated surface, never external-runnable
claimed_by:                  # set ONLY by the atomic claim (§Node 1): "<cli>@<host>/<pid>"
claimed_at:                  # UTC ISO-8601, set atomically with claimed_by
human_gates:                 # optional audit list: merge|push|spend|publish|delete|roberto-name
---
```

**Semantics:**
- `runner:` is **intent, not authority.** It never *causes* an external CLI to run. Default execution
  is Claude-native regardless of the label. Only the external dispatcher (§d) reads it, and only as a
  *filter input* — a card is a candidate for CLI *X* only if `runner:` names *X*.
- `runner: human-only` is a **hard sentinel**: the dispatcher refuses it unconditionally. Cards
  touching any gated surface (merge/push/spend/publish/delete/material in Roberto's or Fight the
  Stroke's name — AGENTS.md#human-gates) MUST be `runner: human-only`. A card that names a gated
  surface in `human_gates:` but is *not* `human-only` is a lint error (new `validate.sh` check).
- **This filter is Layer-1 and fallible by omission.** The lint catches "`human_gates:` set but not
  `human-only`"; it *cannot* catch a card whose author simply omitted `human_gates:` on work that does
  touch a gated surface — such a card is (wrongly) treated as a candidate. That is tolerated **only**
  because Layer-2 is the real gate: even dispatched, it cannot push/merge/escape (§Node 3, §0
  corollary). The label is an early filter, never the guarantee — see residual risk §8.2.
- `claimed_by`/`claimed_at` are written **only** by the atomic claim primitive, never by hand.

### (d) the dispatcher — new bin, not a factory edit

**Decision: new `factory/dispatch-runner.sh`, reusing factory primitives, leaving `run.sh` untouched.**
`factory/run.sh` is the *Claude-native* path and already has working native gates
(`--dangerously-skip-permissions` still reads AGENTS.md, human gates hold, `resolve_model` allowlist,
`verify_card` @thor pass). Do **not** contaminate it with external-CLI sandboxing. The new dispatcher
is a *sibling* that handles only external CLIs in restricted form and **reuses**:

- `verify_card()` / the @thor headless pass (§Node 2) — lifted, not reimplemented.
- the model-policy *pattern* (`resolve_model`'s hardcoded allowlist → a `resolve_runner` allowlist).
- the retry/`failed/`/escalate discipline and card annotation (`note_card`).

**Candidate selection** — a card is dispatchable to external CLI *X* iff **all** hold:
1. its `repo:` is in `~/.roberdan-os/runner-allowlist` (default: file absent/empty ⇒ deny all);
2. `runner:` names *X* and is not `human-only`;
3. `human_gates:` is empty (no gated surface *declared* — Layer-1, see §c caveat);
4. the card is claimable (§Node 1 lock free);
5. the repo passes the full **fail-closed preflight** (§f).

**Pipeline per card** (pseudocode, not implementation):

```
dispatch(card, cli):
  preflight(card, cli)              # §f — ANY failure ⇒ refuse, card untouched, log reason, EXIT
  acquire_repo_lock(repo)           # §Node 1 — one-runner-per-repo, mkdir lock, else skip
  claim(card, cli)                  # §Node 1 — mkdir lock on card id; loser skips; winner stamps
  wt = make_isolated_worktree(repo) # git worktree add on a fresh branch  rda/runner/<card>
  env = sandbox_env(wt)             # §Node 3 — credential-stripped, throwaway HOME, shims, remote-nowhere
  out = run_in(env, wt, cli, card)  # external CLI executes the card IN the worktree only
  leak_check(wt_diff)               # §Node 2/e — MANDATORY before any commit; stderr never logged
  commit_in(wt)                     # commit on the isolated branch (never main, never shared tree)
  # @thor runs in the NORMAL Claude-native env (Max OAuth), NOT inside the stripped sandbox —
  # verify_card uses `claude -p` and needs its subscription auth; the stripped env has none.
  # It reads the worktree read-only and judges evidence. The runner never self-declares.
  verdict = thor_verify(card, wt)   # §Node 2 — Claude/sonnet, evidence-only, OUTSIDE sandbox env
  open_pr(wt, draft = verdict!=PASS)# PR only. MERGE IS NEVER REACHED — human gate.
  release_repo_lock(repo); release_claim(card)
```

Note what the pipeline **cannot** do by construction: it never merges, never pushes to main, never
touches the shared working tree, never runs without a passing preflight. Those are not policy lines in
the code — they are absent capabilities (§Node 3) and structurally impossible call paths.

### (e) per-repo privacy model — `kb init <repo>`

`kb init <repo>` is the single act that makes a repo safe to hold cards. It is **idempotent** and does:

1. `mkdir -p <repo>/kanban/{todo,doing,done}`.
2. Ensure `<repo>/.gitignore` ignores `kanban/todo/`, `kanban/doing/`, `kanban/done/`, and
   `handoff/latest.md` (scoped to the state file — **not** `handoff/`, which in roberdan-os also holds
   the versioned protocol/primer). Append only the lines not already present (never rewrite a target
   repo's gitignore wholesale).
3. **De-track any card/handoff content already committed.** Appending to `.gitignore` does **not**
   stop git tracking a file it already tracks. So `kb init` runs `git -C <repo> ls-files kanban/
   handoff/latest.md` and, for any match, `git rm --cached` it (leaving the working copy). **If any
   such file was already *pushed* to a remote, that is a history-scrub situation → human gate #4**
   (deletion of non-regenerable / already-published data): `kb init` refuses to proceed silently,
   prints the exposed paths, and escalates to Roberto. This is the mechanism that makes "privacy
   active *before* sensitive cards land in git terrain" (mandate) actually true, not aspirational.
   (Checked 2026-07-05: MirrorBuddy has an un-gitignored `kanban/` but **zero** tracked files in it
   yet — so it is still in the safe window; `kb init` must close it before the first card is committed.)
4. Install a per-repo **pre-commit hook** that runs roberdan-os's `leak-check.sh` against the repo's
   staged tree. This is interactive-safety (a human committing by hand); it is *not* the runner's
   gate (a git hook is bypassable with `--no-verify`). The runner's leak gate is enforced by the
   **dispatcher** calling leak-check before it commits (§d) — a path the runner cannot skip.
5. Register the repo path in `~/.roberdan-os/kanban-registry`.

**Denylist: one shared list, not per-repo.** The confidential terms are the *same person's* in every
repo. The dispatcher runs roberdan-os's existing `leak-check.sh` with `RDA_DENYLIST_SRC` pointed at
the **single** `private/.denylist` (tier a) or the committed `denylist.sha256` (tier b), against the
runner-produced files. Per-repo denylists would multiply a confidential surface for no gain.
**Critical:** tier (a) prints the matched confidential text on stderr — the dispatcher MUST discard
leak-check stderr from any runner log, card annotation, or PR body. Leak-check's *exit code* is the
signal; its stderr is local-only, never propagated.

`kb init` does **not** make a repo runner-eligible (that is the separate, narrower `runner-allowlist`).

### (f) fail-closed preflight — refuse rather than degrade

Before the dispatcher launches an external runner it verifies **all** of the following; any single
failure ⇒ it refuses (non-zero exit, card left in `todo/`, reason logged). It never falls back to an
unsafe launch (fail-**closed**, never fail-open):

| # | Check | How verified (bash) | On fail |
|---|---|---|---|
| 1 | repo in allowlist | grep the repo path in `~/.roberdan-os/runner-allowlist` | refuse |
| 2 | board privacy-initialized | repo in registry AND `git check-ignore kanban/todo` passes AND pre-commit hook present AND no tracked card content | refuse |
| 3 | worktree isolation possible | `git -C repo rev-parse` ok, tree clean, `git worktree` supported | refuse |
| 4 | credential stripping available | the sandbox-env builder + shim bindir exist and are executable | refuse |
| 5 | OS-isolation floor present | dedicated-runner-user OR container configured (§Node 3) | refuse |
| 6 | card not gated | `runner: != human-only` AND `human_gates:` empty | refuse |
| 7 | lock acquirable | repo lock + card claim both free (§Node 1) | skip (not fail) |

Check 5 is what keeps the *whole module* dormant until the isolation floor exists: with no dedicated
user/container configured, **every** external dispatch refuses. That is the build-gate expressed as a
runtime invariant, not a promise.

---

## 3. The four technical nodes

### Node 1 — atomic claim (bash 3.2 macOS, no `flock`)

**Decision: `mkdir` locks. Reject atomic-rename.** `mkdir dir` is atomic and fails iff `dir` exists
(POSIX) — a true test-and-set. `mv -n` is **not** a reliable primitive: it does not signal via exit
code whether it moved or skipped, so two racers cannot agree on a winner. So:

- **Card claim:** `mkdir "$LOCKS/card-<id>.lock"` in `~/.roberdan-os/locks/` (outside every repo, like
  factory state). Winner writes `claimed_by`/`claimed_at` into the card, then moves `todo → doing`.
  Loser's `mkdir` fails → it skips the card. The claim happens **before** any card mutation.
- **One-runner-per-repo:** `mkdir "$LOCKS/repo-<name>.lock"` — the vault's documented
  "one-agent-at-a-time" `.git/index.lock` collision, prevented structurally for N runners.
- **Stale recovery:** each lock dir holds a `pid` + `heartbeat` file. A sweep reclaims a lock whose
  PID is dead *and* whose heartbeat is older than a timeout. Honest caveat: stale-lock recovery is the
  one genuinely fiddly part — a crashed runner leaves a lock; reclaiming too eagerly re-introduces the
  race. Conservative default: only reclaim on dead-PID **and** heartbeat older than `2×timeout`.

**Acceptance:** two background claimers on the same card → exactly one `doing`, one skip (testable in
bash, no real CLI).

### Node 2 — done-gate = @thor, never self-declared

**Decision: reuse factory's `verify_card` headless pass verbatim.** The external runner **never**
declares its own card done. After the runner produces its branch, the dispatcher runs the @thor pass:

- **Model:** `claude -p --model sonnet` — Claude-native, gated, billing-safe env (as `run.sh` today).
  A *cheap external* CLI does the authoring; a *gated Claude* verifies it. This is the separation that
  makes external runners tolerable: the verifier is always the trusted layer.
- **Runs OUTSIDE the stripped sandbox.** `verify_card` uses `claude -p`, which needs the Max
  subscription OAuth; factory only unsets `ANTHROPIC_API_KEY`/`AUTH_TOKEN` (billing safety), it keeps
  the OAuth. The credential-vacuum env (§Node 3a) has *no* auth, so running @thor inside it would
  break the verifier itself. @thor therefore runs in the normal Claude-native env, reading the
  worktree read-only. (Only the *runner* runs in the stripped sandbox; the *verifier* does not.)
- **What it verifies:** the card's `dod:`/`acceptance:` against the worktree state, evidence-only,
  emits `VERDICT: PASS — <ev>` / `VERDICT: FAIL — <reason>`.
- **Authority:** a PASS is a *factory-level signal*, **not** a kanban `done`. `kb finish` still needs a
  human `--thor` evidence string, and the *merge* of the runner's PR is still human gate #1. @thor
  FAIL → PR stays draft, card annotated, retry/escalate per factory discipline. @thor cannot undo a
  merge — but by construction there is nothing to undo, because the runner never merges.

### Node 3 — gates enforced by code, not prose (the crux; honest split)

The external CLI (`copilot -p --allow-all-tools`, `ollama`/opencode) does **not** fire Claude's
`PreToolUse` hook — `hooks/bash-guard.sh` is a *Claude Code* hook and is invisible to other CLIs. So
the gate must live where the external process's shell actually passes. Two sub-gates with **different
strengths — state both honestly:**

**3a — push / merge / force-push: SOLVED by capability removal (durable).** No prompt can restore an
absent credential. But a "throwaway HOME" alone is **insufficient on macOS**. The full recipe (all of
it, or the gate leaks):

```
HOME=<throwaway-dir>              # no ~/.gitconfig, no ~/.config/gh
GIT_CONFIG_NOSYSTEM=1             # ignore /etc + Homebrew system gitconfig (osxkeychain lives there,
GIT_CONFIG_GLOBAL=/dev/null       #   NOT under HOME — GIT_CONFIG_GLOBAL alone does NOT disable it)
unset SSH_AUTH_SOCK               # else `git push git@github.com:` works with zero git credentials
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN   # else `gh` authenticates anyway
remote set to a non-pushable URL  # (or removed) inside the worktree
```

With this, even the *real* `/usr/bin/git` cannot push (no auth path exists) — so a PATH shim bypass
via absolute path does not defeat this gate. **This is a true code-enforced invariant.** A shim on
`git`/`gh` is added as first-line defense + audit, but the *guarantee* is the credential vacuum, not
the shim. `reset --hard`/`clean -f` need no separate gate: they only touch uncommitted work **inside
the throwaway worktree**, which is disposable by design.

**3b — filesystem escape (`rm -rf` outside worktree) + dossier read: NOT cleanly solvable in bash.**
A PATH shim on `rm`/`git` is bypassable (`/bin/rm`, `/usr/bin/git`, `python -c os.unlink`). The only
real defenses are OS-level:

- `sandbox-exec` (macOS seatbelt) still exists on Darwin 25 but is **deprecated** for years — list it
  as a *residual-risk mitigation*, not a solid floor.
- **Robust floor: a dedicated macOS user** (separate uid) with **no read permission** on
  `~/.roberdan-os/private/` and write permission **only** on the worktree dir; the dispatcher launches
  the runner as that user. Or a container/VM. This is preflight check #5.

**Honest verdict on Node 3 (this is the "if a node has no clean bash solution, say so" the mandate
asks for):** push/merge is genuinely enforced by credential removal and ships-ready in bash.
`rm -rf`-escape and dossier-read are **not** enforceable by bash alone — they require an OS isolation
floor (dedicated user / container) that is *outside* this repo's language. Therefore module (3) is
**designed in full but build-gated on that floor** (preflight #5 makes every dispatch refuse until it
exists), which is exactly consistent with the review's "park (3) until use-case + reliable Ollama."

### Node 4 — per-CLI budget

**Decision: a fail-closed budget cap, mirroring factory's `MAX`.** `~/.roberdan-os/runner-budget`
(local config): per-CLI daily cap on task-count **and** estimated credits (Copilot ≈ 30 credits/task).
The dispatcher keeps a durable per-day counter (`$STATE/runner-spend-<cli>-<date>`), increments on
each launch, and **refuses to launch when a cap is hit** (fail-closed on budget too). Honest limit:
Copilot's real credit balance is not reliably queryable, so the cap is on task-count + an *estimate*;
where a CLI prints actual usage (Copilot does — "AI credits" in its output), the dispatcher parses and
logs the real figure for reconciliation, but the *gate* is the pre-launch count cap, not a post-hoc
read.

---

## 4. Board mitigations — integral, not appended

The @board non-negotiables are the load-bearing structure of §2–§3, not an afterthought. Cross-map:

| @board mitigation | Where enforced in this design |
|---|---|
| runner env with NO push/merge credentials | §Node 3a — full credential-vacuum recipe (SSH_AUTH_SOCK, GIT_CONFIG_NOSYSTEM, GH_TOKEN…) |
| shell deny-list on destructive git | §Node 3a shim (first-line) + credential vacuum (guarantee) + worktree disposability |
| isolated worktree/branch → PR, merge stays human | §d pipeline: worktree on `rda/runner/<card>`, `open_pr`, merge never reached |
| per-repo allowlist, shared/sensitive repos never | §f #1 `runner-allowlist`, default deny; MirrorBuddy/FightTheStroke excluded by policy |
| one-runner-per-repo lock | §Node 1 repo lock (mkdir) |
| mandatory leak-check before any card commit | §d `leak_check(wt_diff)` before `commit_in`; §e stderr-discarded |
| gated-surface cards → `human-only`, never runnable | §c sentinel + §d selection #2/#3 + §f #6 (Layer-1 filter; §0 corollary is the backstop) |
| fail-closed if structural enforcement missing | §f preflight, esp. #5 (OS floor) — refuses, never degrades |

---

## 5. Final structure

**roberdan-os** (tool + governance only — no card content, ever committed):
```
factory/
  run.sh                 # UNCHANGED — Claude-native headless path (today's gates)
  dispatch-runner.sh     # NEW — external-CLI restricted dispatcher (§d), dormant until §f#5
  runner-sandbox.sh      # NEW — builds the credential-vacuum env + shim bindir (§Node 3a)
  runner-shims/          # NEW — git/gh/rm first-line shims (audit + refuse; not the guarantee)
kanban/
  kb.sh                  # EXTENDED — kb init | kb all/g | kb handoff | cwd-scoped local view (§a,§b)
  todo/ doing/ done/     # gitignored (unchanged)
handoff/
  latest.md              # roberdan-os's own live state (gitignored today? see §5 note)
  handoff-protocol.md    # VERSIONED canon (unchanged)
  context-primer.md      # VERSIONED canon (unchanged)
test/
  leak-check.sh          # REUSED as-is by the dispatcher, single shared denylist (§e)
  test-federated-kb.sh   # NEW — claim race, fail-closed, hostile-stub gate tests (§6)
~/.roberdan-os/          # local-only, never git
  kanban-registry        # NEW — federated repos (written by kb init)
  runner-allowlist       # NEW — external-runner-eligible repos (narrow opt-in, default deny)
  runner-budget          # NEW — per-CLI daily caps (§Node 4)
  locks/                 # NEW — mkdir claim + repo locks (§Node 1)
```

> §5 note: roberdan-os currently **tracks** `handoff/latest.md` (verified 2026-07-05). Federating
> per-repo `handoff/latest.md` as gitignored state raises the question of whether roberdan-os's own
> `latest.md` should also become gitignored. That is a separate, low-risk decision for phase 1 — flag
> it, do not silently change the existing file's tracking in this design.

**A generic federated repo** (e.g. `~/GitHub/orca/`) after `kb init`:
```
orca/
  .gitignore             # + kanban/todo|doing|done/, handoff/latest.md   (appended, not rewritten)
  .git/hooks/pre-commit  # calls roberdan-os leak-check on staged tree (interactive safety)
  kanban/todo|doing|done # local cards, gitignored — never committed
  handoff/latest.md      # per-repo handoff, gitignored
```
No roberdan-os canon is copied in. The repo's AGENTS.md is irrelevant to the gates — they are applied
from the dispatcher. This is the MirrorBuddy lesson operationalized.

---

## 6. @thor acceptance tests (all bash, no real external CLI ⇒ `validate.sh` stays green)

The center is a **hostile stub runner** — a script that *actively attempts* every forbidden action —
because a happy-path test proves nothing about gates.

1. **Gate-crossing impossible even if the model tries (must-have).** This test must **prove the vacuum
   works, not pass vacuously.** Setup: a **local bare repo as the remote** and a **simulated
   credential in the environment** (e.g. a fake `GH_TOKEN` + a writable file-URL remote). Assert two
   things: (i) *outside* the sandbox env, the stub's `git push` to the bare remote **succeeds** — this
   proves the test's push path is real; (ii) *inside* `sandbox_env`, the same push **fails** (vacuum
   stripped the credential/remote), and `gh pr merge`, `git push --force`, `cat
   ~/.roberdan-os/private/*`, `rm -rf <outside-worktree>` all fail or are refused/confined. A test that
   only asserts "push fails" without (i) is green for the wrong reason (CI simply has no credentials) —
   it must show the push *would have* worked and the vacuum *stopped* it. @thor never sees a
   self-declared PASS.
2. **Atomic claim under 2 parallel runners (must-have).** Two background claims on one card → assert
   exactly one `doing`, one clean skip; no double-claim, no corrupt card.
3. **Per-repo leak-check blocks a sensitive card (must-have).** Plant a denylist term in stub output
   → assert leak-check fails the commit and leak-check stderr appears in **no** log/card/PR.
4. **Fail-closed on a repo without enforcement (must-have).** Point the dispatcher at a repo not in
   the allowlist / not `kb init`'d / with no OS floor → assert it **refuses** (non-zero, card
   untouched), never a degraded launch.
5. **`runner: human-only` never dispatched.** Assert a gated card is filtered out of candidates.
6. **Federation lint + init safety.** New `validate.sh` checks: a card with non-empty `human_gates:`
   must be `human-only`; `kb init` is idempotent AND de-tracks already-tracked kanban content (assert
   `git ls-files kanban/` is empty after init on a fixture that had a tracked card); registry/allowlist
   parsing degrades to empty, never crashes.

Each maps to a `test/test-federated-kb.sh` case gated into `validate.sh` — the module can only merge
when all are green.

---

## 7. Committable phases (each leaves `validate.sh` green)

1. **Federation read-path** — `kb` cwd-scoping + `kb all` + `kb handoff` + registry parsing
   (read-only). No new gate. Tests: view/aggregation. *(Layer 1, zero risk.)*
2. **`kb init` + per-repo privacy** — scaffolding, gitignore-append, **de-track already-tracked
   content** (with human-gate escalation if already pushed), pre-commit hook, registry write.
   Tests: idempotency, `git check-ignore`, de-track, leak-check wiring. *(Enables safe cards anywhere.)*
3. **`runner:` metadata + schema lint** — additive frontmatter + `human_gates:`↔`human-only` lint.
   *(Layer 1, a label only — no execution change.)*
4. **Migration** — move existing roberdan-os + MirrorBuddy cards to the federated model, **privacy
   active first** (`kb init` a repo *before* any sensitive card lands in its git terrain; the de-track
   step of phase 2 is the enforcement). MirrorBuddy gets `kb init` (federation) but is **kept out** of
   `runner-allowlist`.
5. **Node 1 locks** — mkdir claim + repo lock + stale sweep. Tests: parallel-claim race.
6. **Dispatcher skeleton + fail-closed preflight** — `dispatch-runner.sh` with §f checks, **but
   preflight #5 always fails** (no OS floor shipped) ⇒ every dispatch refuses. Tests: hostile-stub +
   fail-closed. *(Module present, provably dormant.)*
7. **(gated, later) OS-isolation floor + real CLI enablement** — dedicated runner user / container +
   turning off preflight #5's hard-refuse. **Only** with Roberto's go and a concrete use-case. Its own
   design doc + @rex + @luca security review + @thor.

Phases 1–5 are pure Layer-1/organizational value and ship independent of the risky module. Phase 6
lands the dispatcher *inert*. Phase 7 is the human-gated activation.

---

## 8. Residual risks — honest, even in restricted form

1. **`rm -rf`-escape + dossier-read are not bash-enforceable.** They rest entirely on the OS floor
   (dedicated user / container). Until that exists, the *only* safe posture is preflight #5 refusing
   every dispatch. If someone disables check #5 without building the floor, the gate is gone. Mitigation
   is a *convention* that #5 is never softened without @luca — which is itself Layer-1 (weakest kind).
   **This is the sharpest residual risk.**
2. **`human-only` / `human_gates:` labeling is fallible by omission.** A card touching a gated surface
   whose author forgot the label is treated as a candidate (§c). Backstop is Layer-2 (§0 corollary):
   even dispatched it cannot push/merge/escape — a mislabel *degrades safe*, it does not open the gate.
   But it does mean an inappropriate card could *run* (produce a PR) when it should have been
   human-only; the human merge review is the catch. Not a silent success, but not caught early either.
3. **PATH shims are defense-in-depth, not a guarantee.** An injected model can call absolute-path
   binaries. Only credential-vacuum (3a) and OS isolation (3b) are real; the shims only raise cost and
   log intent.
4. **@thor verifier is itself an LLM.** A sophisticated wrong output could pass a sonnet check. Mitigated
   by: @thor runs on the *gated* Claude layer, PR-only (human still merges), evidence-only prompt — but
   it is not a proof, only a strong filter. The human merge gate is the real backstop.
5. **Budget is an estimate.** Copilot's true balance isn't queryable; a burst within a day could exceed
   the intended spend before the count cap trips. Cap conservatively.
6. **Stale-lock recovery can mis-fire.** Too-eager reclaim re-opens the claim race; too-timid wedges a
   repo after a crash. The `2×timeout`+dead-PID default is a compromise, not a proof of correctness.
7. **Ollama-as-agent is still unproven** (opencode timed out at 120s where raw ollama took 9s, per the
   prior plan). The `ollama/*` runner path is designable but has no reliable execution leg today — a
   real use-case for it does not yet exist.
8. **Registry/allowlist drift.** They are local-only files; if a repo is renamed/moved they go stale.
   `kb discover` warns, but nothing forces reconciliation.

---

## 9. Where bash genuinely cannot deliver (the direct answer to the mandate)

| Node / gate | Clean in bash? | Why |
|---|---|---|
| Atomic claim (Node 1) | **Yes** | `mkdir` is atomic test-and-set on macOS bash 3.2 |
| @thor done-gate (Node 2) | **Yes** | reuses factory's headless pass verbatim (outside the stripped env) |
| push/merge gate (Node 3a) | **Yes** | credential vacuum removes the capability; even real git can't push |
| `rm -rf`-escape / dossier-read (Node 3b) | **No** | needs OS isolation (dedicated user / container); shim is bypassable, sandbox-exec deprecated |
| Budget cap (Node 4) | **Partial** | count cap is clean; true credit balance is not queryable |

The one node with **no clean bash solution is 3b** — and it is precisely why module (3) ships dormant
(preflight #5) rather than pretending bash can sandbox a hostile process.
