# Federated kanban + restricted multi-CLI dispatch — design (not yet built)

> **Status:** design (@baccio), **revised 2026-07-05 per @rex + @luca review** (verdicts in the
> tail section, kept as trace). Phases 1–5 ready for implementation; the external dispatcher
> (phases 6–7) is designed-but-dormant and hard-wired to refuse. Awaiting Roberto go/no-go on any
> phase-7 activation. No code changed by this doc.
> **Binding input:** [`plan-2026-07-05-multi-cli-model-orchestration.md`](plan-2026-07-05-multi-cli-model-orchestration.md)
> — the adversarial review (Fable + @board + @baccio) is **settled and not re-litigated here**.
> This doc turns its verdict into an architecture.
>
> **What the review settled (verbatim constraints):**
> - "runner in `--yolo` auto-executing cards" → **rejected**. Only the **restricted sandbox** form.
> - **Two layers:** AGENTS.md/canon unifies *behavior* above a capability floor; only intercepting
>   *code* guarantees the *gates*. Gates are never prose — they are shell/filesystem/credential/
>   network enforcement.
> - **Empirical fact that kills inherited gates:** MirrorBuddy has a *standalone* `AGENTS.md` (not a
>   pointer to roberdan-os) and does **not** gitignore `kanban/` (verified 2026-07-05). Gate
>   inheritance via AGENTS.md is **not** guaranteed for target repos. This design assumes none.
> - **What the @rex + @luca review added (2026-07-05):** the dominant runner risk is **network
>   exfiltration** (`curl`/DNS), not filesystem escape; the credential vacuum must survive a hostile
>   repo-local `.git/config`; the module must be **wired** even while dormant; the dormant refusal
>   must be **hard-wired code**, not a flippable config toggle. All folded into the sections below.

---

## 0. The two layers, made explicit

Everything below sits in exactly one of two layers. Confusing them is the failure the review named.

| | **Layer 1 — behavior (canon)** | **Layer 2 — governance (code)** |
|---|---|---|
| Mechanism | `AGENTS.md`, `behavior/`, agent prompts, `runner:` metadata | credential absence, PATH shims, OS isolation (dedicated uid, per-uid egress-control, disposable TMPDIR), `mkdir` locks, leak-check, PR-only |
| Guarantees | *tendency* to behave, above a capability floor | *invariant* enforced regardless of model quality or prompt injection |
| Fails when | model is weak / injected / goal-pressured (IHEval, Compliance-Gap) | never by prompt — only by a real capability being present that should be absent |
| Travels via | the repo's AGENTS.md — **NOT guaranteed** (MirrorBuddy) | the **dispatcher in roberdan-os** — always present, target repo cannot opt out |

**Consequence for the whole design:** no gate may live in a target repo's config, because a target
repo may not inherit roberdan-os canon. Every hard gate lives in **roberdan-os dispatcher code** and
is applied *to* the target repo from outside. The target repo is treated as untrusted terrain —
**including its `.git/config`**, which the review proved can carry an injected credential helper and
remote (§Node 3a).

**Corollary — Layer-1 filters degrade safe (with one honest boundary).** Several conveniences below
(the `human-only` sentinel, `runner:` matching, the `human_gates:` lint) are Layer-1: an author can
mislabel a card. None of them is a *guarantee*. For a mislabeled card that slips the filter, the
Layer-2 backstop holds it against **push / merge / force-push** (credential vacuum) and — *once the
phase-7 OS floor exists* — against **filesystem escape and dossier read** (dedicated uid) and
**network exfiltration** (per-uid egress-control). The boundary the review sharpened: those last two
are **not** enforceable in bash, so in the dormant module they are guaranteed only by the module
**refusing to dispatch at all** (preflight #5). A Layer-1 miss therefore degrades into "the action is
attempted and structurally fails, *or* the dispatch is refused outright" — never into "the action
succeeds". This is why the design tolerates fallible labels, and why the module stays dormant until
the floor is real.

---

## 1. Scope split by risk (from the review, now the module boundary)

Three pieces, three risk classes, three delivery gates:

1. **Kanban federation** — cards per-repo + an aggregating `kb`. *Organizational value, real.* Needs
   a serious per-repo privacy model (gitignore + leak-check + local-history check), since MirrorBuddy
   proves it is not automatic. **Build.**
2. **`runner:` as declarative metadata** — a card *states* its ideal CLI/model. *Zero risk — a label.*
   Execution still **defaults to Claude-native** (Agent tool + `model:` frontmatter → native gates).
   **Build.**
3. **External-runner dispatcher (restricted form only)** — high risk. **Design in full here, but
   build-gated:** ships only when (a) the OS-isolation floor exists — dedicated uid **and** per-uid
   egress-control (§Node 3) — *and* (b) a concrete use-case appears that Claude-native cannot cover.
   Until then it is a designed-but-dormant *but wired* module, and its acceptance tests run against a
   **hostile stub**, not a real external CLI.

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

**Card ids are per-repo, not global (review fix, @rex #2).** Card ids are `date +%y%m%d-%H%M%S`,
unique only *within* a repo. In the federated model two repos can mint the same id. Every id-keyed
mechanism below — the claim/repo locks (§Node 1) and `verify_card` state (§Node 2) — is therefore
keyed on **`<repo>+<id>`**, never bare `<id>`. Aggregated views likewise render `repo:` alongside the
id so the human is never shown an ambiguous bare id.

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
  corollary). The label is an early filter, never the guarantee — see residual risk §8.
- `claimed_by`/`claimed_at` are written **only** by the atomic claim primitive, never by hand, and the
  claim is keyed on `<repo>+<id>`.

### (d) the dispatcher — new bin, plus a minimal honest extraction from `run.sh`

**Decision: new `factory/dispatch-runner.sh`, reusing factory primitives via an extracted
`factory/lib.sh`.** `factory/run.sh` is the *Claude-native* path and already has working native gates
(`--dangerously-skip-permissions` still reads AGENTS.md, human gates hold, `resolve_model` allowlist,
`verify_card` @thor pass). Do **not** contaminate it with external-CLI sandboxing.

**Honesty fix (@rex #3): `run.sh` is NOT "unchanged".** `verify_card()`, `note_card()` and
`resolve_model()` currently live *inside* `run.sh`. Reusing them from a sibling means **extracting
them into `factory/lib.sh`**, sourced by *both* `run.sh` and `dispatch-runner.sh`. That is a real,
minimal edit to `run.sh` (delete the function bodies, `source factory/lib.sh`), behavior-preserving
and covered by the existing factory tests — but it is a change, and the design states it as one rather
than pretending the file is untouched. The new dispatcher then **reuses** from `lib.sh`:

- `verify_card()` / the @thor headless pass (§Node 2) — lifted, keyed on `<repo>+<id>`.
- the model-policy *pattern* (`resolve_model`'s hardcoded allowlist → a `resolve_runner` allowlist).
- the retry/`failed/`/escalate discipline and card annotation (`note_card`).

**Candidate selection** — a card is dispatchable to external CLI *X* iff **all** hold:
1. its `repo:` is in `~/.roberdan-os/runner-allowlist` (default: file absent/empty ⇒ deny all);
2. `runner:` names *X* and is not `human-only`;
3. `human_gates:` is empty (no gated surface *declared* — Layer-1, see §c caveat);
4. the `<repo>+<id>` is claimable (§Node 1 lock free);
5. the repo passes the full **fail-closed preflight** (§f), which now includes an **active,
   non-empty leak-check tier** (#8) and the **hard-wired OS-floor refusal** (#5).

**Pipeline per card** (pseudocode, not implementation):

```
dispatch(card, cli):
  preflight(card, cli)              # §f — ANY failure ⇒ refuse, card untouched, log reason, EXIT
                                    #   incl. #8 leak-check-active and #5 hard-wired OS-floor refuse
  acquire_repo_lock(repo)           # §Node 1 — one-runner-per-repo, mkdir lock, else skip
  claim(repo, card)                 # §Node 1 — mkdir lock on <repo>+<id>; loser skips; winner stamps
  wt = make_isolated_worktree(repo) # git worktree add on a fresh branch  rda/runner/<card>
  env = sandbox_env(wt)             # §Node 3a — env -i allowlist, credential-vacuum, git creds forced
  out = run_in(env, wt, cli, card)  # external CLI executes the card IN the worktree only
  leak_check(wt_diff)               # §Node 2/e — MANDATORY, tier asserted active by preflight #8;
                                    #   stderr never logged
  commit_in(wt)                     # commit on the isolated branch (never main, never shared tree)
  # @thor runs in the NORMAL Claude-native env (Max OAuth), NOT inside the stripped sandbox —
  # verify_card uses `claude -p` and needs its subscription auth; the stripped env has none.
  # It reads the worktree read-only and judges evidence. The runner never self-declares.
  verdict = thor_verify(repo, card, wt) # §Node 2 — Claude/sonnet, evidence-only, OUTSIDE sandbox env
  open_pr(wt, draft = verdict!=PASS)# PR only. MERGE IS NEVER REACHED — human gate.
  release_repo_lock(repo); release_claim(repo, card)
```

Note what the pipeline **cannot** do by construction: it never merges, never pushes to main, never
touches the shared working tree, never runs without a passing preflight (leak-check tier included).
Those are absent capabilities (§Node 3a) and structurally impossible call paths — not policy lines.
**What it also cannot guarantee in bash alone:** it cannot stop a hostile runner from **exfiltrating
via the network** (`curl`, DNS) or **reading the dossier / escaping the filesystem** — those rest on
the phase-7 OS floor. In the dormant module preflight #5 refuses every dispatch, so no runner ever
executes; the pipeline above is the *shape* of the activated module, not a claim that it is safe
without the floor (§Node 3b/3c, §7, §8).

### (e) per-repo privacy model — `kb init <repo>`

`kb init <repo>` is the single act that makes a repo safe to hold cards. It is **idempotent** and does:

1. `mkdir -p <repo>/kanban/{todo,doing,done}`.
2. Ensure the repo **locally ignores** `kanban/todo/`, `kanban/doing/`, `kanban/done/`, and the
   per-repo pause checkpoint `handoff/resume.md` (the ephemeral file `kb pause` writes — **not**
   `handoff/latest.md`, roberdan-os's *tracked* canon state, nor `handoff/` itself, which also holds
   the versioned protocol/primer). These lines go to **`.git/info/exclude`** — the repo's LOCAL ignore
   — **never the committed `.gitignore`**: federation noise is Roberto-machine-only, so committing
   ignore rules would pollute a shared repo's history for a file no collaborator ever generates. Append
   only lines not already present. *(Changed 2026-07-07 from a committed-`.gitignore` append with the
   wrong filename `handoff/latest.md` — see CHANGELOG v2.6.0.)*
3. **De-track any card/handoff content already committed.** Adding a local exclude entry does **not**
   stop git tracking a file it already tracks. So `kb init` runs `git -C <repo> ls-files kanban/
   handoff/latest.md` and, for any match, `git rm --cached` it (leaving the working copy).
4. **Scan LOCAL git history for already-committed card/handoff content (review fix, @rex #6).**
   `git rm --cached` de-tracks *going forward*, but the blob **remains in local history** — if that
   branch is ever pushed, the card content leaks. So `kb init` also runs
   `git -C <repo> log --all --oneline -- kanban/ handoff/latest.md` and classifies each hit:
   - **already pushed to a remote** → this is a history-scrub situation → **human gate #4** (deletion
     of already-published data): `kb init` refuses to proceed silently, prints the exposed paths +
     commits, and escalates to Roberto.
   - **local-only, non-pushed commits** → `kb init` **does not rewrite history automatically** (that
     is destructive) but **prints the offending commits with a loud warning** that they must not be
     pushed and should be scrubbed (`git filter-repo` / interactive rebase) before any push. Silence
     here would be the exact MirrorBuddy-class blind spot the review named.
   This is the mechanism that makes "privacy active *before* sensitive cards land in git terrain"
   (mandate) actually true, not aspirational. (Checked 2026-07-05: MirrorBuddy has an un-gitignored
   `kanban/` but **zero** tracked files and **zero** history hits — so it is still in the safe window;
   `kb init` must close it before the first card is committed.)
5. Install a per-repo **pre-commit hook** that runs roberdan-os's `leak-check.sh` against the repo's
   staged tree. This is interactive-safety (a human committing by hand); it is *not* the runner's
   gate (a git hook is bypassable with `--no-verify`). The runner's leak gate is enforced by the
   **dispatcher** calling leak-check before it commits (§d) — a path the runner cannot skip — and only
   after preflight #8 has asserted the leak-check tier is actually active (§f).
6. Register the repo path in `~/.roberdan-os/kanban-registry`.

**Denylist: one shared list, not per-repo.** The confidential terms are the *same person's* in every
repo. The dispatcher runs roberdan-os's existing `leak-check.sh` with `RDA_DENYLIST_SRC` pointed at
the **single** `private/.denylist` (tier a) or the committed `denylist.sha256` (tier b), against the
runner-produced files. Per-repo denylists would multiply a confidential surface for no gain.
**Critical:** tier (a) prints the matched confidential text on stderr — the dispatcher MUST discard
leak-check stderr from any runner log, card annotation, or PR body. Leak-check's *exit code* is the
signal; its stderr is local-only, never propagated.

**Leak-check fails OPEN when no tier is active (review fix, @rex #1).** `leak-check.sh` returns
`exit 0` (tier c) when `private/.denylist` is absent/empty **and** no committed `denylist.sha256`
exists — i.e. a "mandatory" gate silently becomes a no-op and the runner's output would be committed
with **zero** protection. None of the original seven preflight checks caught this. The fix is
**preflight #8** (§f): before any dispatch, assert an active, non-empty leak-check tier, else refuse.

`kb init` does **not** make a repo runner-eligible (that is the separate, narrower `runner-allowlist`).

### (f) fail-closed preflight — refuse rather than degrade

Before the dispatcher launches an external runner it verifies **all** of the following; any single
failure ⇒ it refuses (non-zero exit, card left in `todo/`, reason logged). It never falls back to an
unsafe launch (fail-**closed**, never fail-open):

| # | Check | How verified (bash) | On fail |
|---|---|---|---|
| 1 | repo in allowlist | grep the repo path in `~/.roberdan-os/runner-allowlist` | refuse |
| 2 | board privacy-initialized | repo in registry AND `git check-ignore kanban/todo` passes AND pre-commit hook present AND no tracked card content AND no un-pushed local-history card content (§e#4) | refuse |
| 3 | worktree isolation possible | `git -C repo rev-parse` ok, tree clean, `git worktree` supported | refuse |
| 4 | credential stripping available | the sandbox-env builder (`env -i` allowlist form) + shim bindir exist and are executable | refuse |
| 5 | OS-isolation floor present | dedicated-runner-uid **and** per-uid egress-control configured (§Node 3) — **hard-wired refuse, not a config toggle** | refuse |
| 6 | card not gated | `runner: != human-only` AND `human_gates:` empty | refuse |
| 7 | lock acquirable | repo lock + `<repo>+<id>` claim both free (§Node 1) | skip (not fail) |
| 8 | leak-check tier active | an active, **non-empty** leak-check tier resolves (tier a denylist non-empty OR tier b `denylist.sha256` present) — never tier-c fail-open (§e, @rex #1) | refuse |

Check 5 is what keeps the *whole module* dormant until the isolation floor exists: with no dedicated
uid **and** per-uid egress-control configured, **every** external dispatch refuses. It is the
build-gate expressed as a runtime invariant. **It is hard-wired (review fix, @luca #9):** the refusal
is a constant in `dispatch-runner.sh` code, not a value read from any local config file — a target
repo, an env var, or a `~/.roberdan-os/*` file **cannot** flip it to "floor present". Turning #5 off
is a *reviewed code edit* (phase 7), gated on @rex + @luca + Roberto, never a runtime toggle.
Check 8 closes the leak-check fail-open. Checks 5 and 8 together are the two dormancy gates.

---

## 3. The four technical nodes

### Node 1 — atomic claim (bash 3.2 macOS, no `flock`)

**Decision: `mkdir` locks. Reject atomic-rename.** `mkdir dir` is atomic and fails iff `dir` exists
(POSIX) — a true test-and-set. `mv -n` is **not** a reliable primitive: it does not signal via exit
code whether it moved or skipped, so two racers cannot agree on a winner. So:

- **Card claim:** `mkdir "$LOCKS/card-<repo>-<id>.lock"` in `~/.roberdan-os/locks/` (outside every
  repo, like factory state). The lock key is **`<repo>+<id>`, not bare `<id>`** (review fix, @rex #2:
  ids are per-repo unique only, so two federated repos can collide on a bare id). Winner writes
  `claimed_by`/`claimed_at` into the card, then moves `todo → doing`. Loser's `mkdir` fails → it skips
  the card. The claim happens **before** any card mutation.
- **One-runner-per-repo:** `mkdir "$LOCKS/repo-<name>.lock"` — the vault's documented
  "one-agent-at-a-time" `.git/index.lock` collision, prevented structurally for N runners.
- **Stale recovery:** each lock dir holds a `pid` + `heartbeat` file. A sweep reclaims a lock whose
  PID is dead *and* whose heartbeat is older than a timeout. Honest caveat: stale-lock recovery is the
  one genuinely fiddly part — a crashed runner leaves a lock; reclaiming too eagerly re-introduces the
  race. Conservative default: only reclaim on dead-PID **and** heartbeat older than `2×timeout`.

**Acceptance:** two background claimers on the same `<repo>+<id>` → exactly one `doing`, one skip
(testable in bash, no real CLI).

### Node 2 — done-gate = @thor, never self-declared

**Decision: reuse factory's `verify_card` headless pass verbatim — from the extracted `factory/lib.sh`
(§d).** The external runner **never** declares its own card done. After the runner produces its
branch, the dispatcher runs the @thor pass, keyed on `<repo>+<id>`:

- **Model:** `claude -p --model sonnet` — Claude-native, gated, billing-safe env (as `run.sh` today).
  A *cheap external* CLI does the authoring; a *gated Claude* verifies it. This is the separation that
  makes external runners tolerable: the verifier is always the trusted layer.
- **Runs OUTSIDE the stripped sandbox.** `verify_card` uses `claude -p`, which needs the Max
  subscription OAuth; factory only unsets `ANTHROPIC_API_KEY`/`AUTH_TOKEN` (billing safety), it keeps
  the OAuth. The credential-vacuum env (§Node 3a) has *no* auth (it is `env -i` with a tight
  allowlist), so running @thor inside it would break the verifier itself. @thor therefore runs in the
  normal Claude-native env, reading the worktree read-only. (Only the *runner* runs in the stripped
  sandbox; the *verifier* does not.)
- **What it verifies:** the card's `dod:`/`acceptance:` against the worktree state, evidence-only,
  emits `VERDICT: PASS — <ev>` / `VERDICT: FAIL — <reason>`.
- **Authority:** a PASS is a *factory-level signal*, **not** a kanban `done`. `kb finish` still needs a
  human `--thor` evidence string, and the *merge* of the runner's PR is still human gate #1. @thor
  FAIL → PR stays draft, card annotated, retry/escalate per factory discipline. @thor cannot undo a
  merge — but by construction there is nothing to undo, because the runner never merges.

### Node 3 — gates enforced by code, not prose (the crux; honest split, re-scoped by @luca)

The external CLI (`copilot -p --allow-all-tools`, `ollama`/opencode) does **not** fire Claude's
`PreToolUse` hook — `hooks/bash-guard.sh` is a *Claude Code* hook and is invisible to other CLIs. So
the gate must live where the external process's shell actually passes.

**The crux was mis-ranked (review fix, @luca #7).** The original doc treated `rm -rf`-escape and
dossier-read (filesystem) as the sharpest un-bashable risk. The @luca review corrected this: the
**dominant** runner risk is **network exfiltration** — a hostile or injected runner running `curl`,
opening a socket, or leaking secrets through DNS queries. Neither the credential vacuum nor a
dedicated uid closes that; only **per-uid egress-control** does. So Node 3 now has **three** sub-gates
of decreasing bash-tractability: 3a (solved in bash), 3b (needs OS floor), 3c (needs OS floor, and is
the actual crux).

**3a — push / merge / force-push: SOLVED by capability removal (durable), hardened against a hostile
`.git/config`.** No prompt can restore an absent credential. But a "throwaway HOME" alone is
**insufficient on macOS**, and the review found a second hole: the untrusted repo's **own local
`.git/config`** is honored by git regardless of `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL`. A repo that
ships `credential.helper = osxkeychain` + an injected remote, with the keychain unlocked, would push
with *zero* env credentials. The full recipe (all of it, or the gate leaks):

```
env -i \                              # ALLOWLIST, not denylist (review fix, @luca #8): start empty,
  PATH=<shim-bindir>:/usr/bin:/bin \  #   pass ONLY what the runner legitimately needs. GH_TOKEN,
  HOME=<throwaway-dir> \              #   GITHUB_TOKEN, SSH_AUTH_SOCK, GH_ENTERPRISE_TOKEN are simply
  TERM=$TERM LANG=$LANG \             #   never in the allowlist, so no unset can be forgotten.
  TMPDIR=<per-runner-disposable> \    #   (plus the CLI's own required vars, enumerated per CLI)
  <cli> ...

# every git invocation the dispatcher makes is forced credential-less and config-neutral:
git -c credential.helper= \           # DEFEATS a hostile repo-local credential.helper (@luca #8):
    -c protocol.version=2 \           #   an empty helper overrides ANY .git/config helper, so
    GIT_CONFIG_NOSYSTEM=1 ...         #   osxkeychain cannot be reached even if the repo asks for it.
GIT_CONFIG_GLOBAL=/dev/null           # ignore ~/.gitconfig (does NOT cover repo-local; -c does)
```

**On "neutralize all remotes" vs "don't mutate the worktree remote" — the two verdicts reconciled.**
@rex #4 correctly deleted the original step *"set remote to a non-pushable URL inside the worktree"*:
a `git worktree` **shares the parent repo's `.git` and its remotes**, so editing the remote there is
either a no-op or it mutates the *real* repo's remote — a bug, not a gate. @luca #8/#10d asks that
**all** remotes be neutralized (origin, SSH, injected), not just origin. Both are satisfied **without
touching any remote config**: the guarantee is the **absence of an auth path**, applied globally —
`-c credential.helper=` on every git + `env -i` with no `GH_TOKEN`/`GITHUB_TOKEN` + no
`SSH_AUTH_SOCK`. With no credential helper reachable, no token in env, and no ssh-agent socket, a
`git push` to *any* remote — `origin`, an injected `git@…` SSH remote, or a fresh remote the runner
adds itself — has nowhere to authenticate and fails. "All remotes neutralized" is achieved by killing
the *auth*, not by rewriting the *config* of a shared worktree.

With this, even the *real* `/usr/bin/git` cannot push (no auth path exists) — so a PATH shim bypass
via absolute path does not defeat this gate. **This is a true code-enforced invariant.** A shim on
`git`/`gh` is added as first-line defense + audit, but the *guarantee* is the credential vacuum +
forced-empty helper, not the shim. `reset --hard`/`clean -f` need no separate gate: they only touch
uncommitted work **inside the throwaway worktree**, which is disposable by design.

**3b — filesystem escape (`rm -rf` outside worktree) + dossier read: NOT solvable in bash.**
A PATH shim on `rm`/`git` is bypassable (`/bin/rm`, `/usr/bin/git`, `python -c os.unlink`). The only
real defenses are OS-level:

- `sandbox-exec` (macOS seatbelt) still exists on Darwin 25 but is **deprecated** for years — list it
  as a *residual-risk mitigation*, not a solid floor.
- **Robust floor: a dedicated macOS uid** with the phase-7 non-negotiables (§7): `~/.roberdan-os/
  private/` **and every ancestor directory** verified non-readable by the runner uid at runtime
  (`EACCES`, fail-closed) with **no world-readable copy** anywhere; write permission **only** on the
  worktree dir; a per-runner **disposable TMPDIR**. The dispatcher launches the runner as that uid.
  Or a container/VM. This is preflight check #5.

**3c — network exfiltration (`curl` / DNS): NOT solvable in bash, and the dominant risk (@luca #7).**
An injected runner does not need to push or escape the filesystem to do harm — it can `curl` the
dossier (if readable) or any worktree secret to an attacker host, or tunnel data through DNS lookups
that no HTTP proxy sees. Nothing in 3a or 3b closes this. The only real defense is **per-uid
egress-control**:

- macOS `pf` anchored to the runner uid (default-deny egress, allowlist only what the CLI genuinely
  needs — e.g. its own API endpoint), or a **network namespace** / container with no route out except
  an audited proxy.
- This is bash-untractable and is therefore a **phase-7 non-negotiable**, folded into preflight #5:
  the floor is "dedicated uid **and** per-uid egress-control" — both, or #5 refuses.

**Honest verdict on Node 3.** Push/merge (3a) is genuinely enforced by credential removal + forced
`credential.helper=` and ships-ready in bash. `rm -rf`-escape / dossier-read (3b) **and** network
exfiltration (3c) are **not** enforceable by bash alone — they require an OS isolation floor
(dedicated uid + per-uid egress-control) that is *outside* this repo's language, with **3c the
dominant one**. Therefore module (3) is **designed in full but build-gated on that floor** (preflight
#5, hard-wired, makes every dispatch refuse until it exists), consistent with the review's "park (3)
until use-case + reliable Ollama + the floor is proven."

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

## 4. Board mitigations — integral, not appended (re-swept for the review)

The @board non-negotiables are the load-bearing structure of §2–§3, not an afterthought. Cross-map
(updated so no row cites the deleted remote step, and the new gates appear):

| @board / review mitigation | Where enforced in this design |
|---|---|
| runner env with NO push/merge credentials | §Node 3a — `env -i` **allowlist** (no `GH_TOKEN`/`SSH_AUTH_SOCK`) + `GIT_CONFIG_NOSYSTEM`; guarantee is credential *absence*, applied to all remotes without touching the shared worktree config |
| survives a hostile repo-local `.git/config` (@luca #8) | §Node 3a — `-c credential.helper=` forced on every git invocation defeats an injected `osxkeychain` helper |
| network exfiltration blocked (@luca #7, dominant) | §Node 3c — per-uid `pf` egress-control / network-namespace; **phase-7 non-negotiable**, gated by preflight #5 |
| shell deny-list on destructive git | §Node 3a shim (first-line) + credential vacuum (guarantee) + worktree disposability |
| isolated worktree/branch → PR, merge stays human | §d pipeline: worktree on `rda/runner/<card>`, `open_pr`, merge never reached |
| per-repo allowlist, shared/sensitive repos never | §f #1 `runner-allowlist`, default deny; MirrorBuddy/FightTheStroke excluded by policy |
| one-runner-per-repo lock | §Node 1 repo lock (mkdir) |
| mandatory leak-check **actually active** before any commit | §d `leak_check(wt_diff)` before `commit_in`; §f #8 asserts a non-empty tier (no fail-open); §e stderr-discarded |
| dossier unreadable by runner (@luca #10b) | §Node 3b — dedicated uid, `private/`+ancestors `EACCES` at runtime, no world-readable copy; phase-7 non-negotiable |
| gated-surface cards → `human-only`, never runnable | §c sentinel + §d selection #2/#3 + §f #6 (Layer-1 filter; §0 corollary is the backstop) |
| fail-closed if structural enforcement missing | §f preflight, esp. #5 (OS floor, **hard-wired**) + #8 (leak-check active) — refuses, never degrades |

---

## 5. Final structure

**roberdan-os** (tool + governance only — no card content, ever committed):
```
factory/
  lib.sh                 # NEW — extracted verify_card/note_card/resolve_model (§d, @rex #3);
                         #   sourced by BOTH run.sh and dispatch-runner.sh
  run.sh                 # MINIMAL CHANGE — now `source factory/lib.sh` (was inline); gates unchanged
  dispatch-runner.sh     # NEW — external-CLI restricted dispatcher (§d); wired via `kb dispatch`,
                         #   dormant until §f#5 (hard-wired refuse). Entry-path is LIVE even dormant.
  runner-sandbox.sh      # NEW — builds the `env -i` allowlist credential-vacuum env (§Node 3a)
  runner-shims/          # NEW — git/gh/rm first-line shims (audit + refuse; not the guarantee)
kanban/
  kb.sh                  # EXTENDED — kb init | kb all/g | kb handoff | kb dispatch | cwd-scoped view
  todo/ doing/ done/     # gitignored (unchanged)
handoff/
  latest.md              # roberdan-os's own live state (gitignored today? see §5 note)
  handoff-protocol.md    # VERSIONED canon (unchanged)
  context-primer.md      # VERSIONED canon (unchanged)
test/
  leak-check.sh          # REUSED as-is by the dispatcher, single shared denylist (§e)
  test-federated-kb.sh   # NEW — claim race, fail-closed, hostile-stub gate tests, wired-check (§6)
validate.sh              # EXTENDED — human_gates↔human-only lint + wired-check that `kb dispatch`
                         #   routes to dispatch-runner.sh (fails if the module is present-but-unwired)
~/.roberdan-os/          # local-only, never git
  kanban-registry        # NEW — federated repos (written by kb init)
  runner-allowlist       # NEW — external-runner-eligible repos (narrow opt-in, default deny)
  runner-budget          # NEW — per-CLI daily caps (§Node 4)
  locks/                 # NEW — mkdir claim (card-<repo>-<id>) + repo locks (§Node 1)
```

> §5 note: roberdan-os currently **tracks** `handoff/latest.md` (verified 2026-07-05). Federating
> per-repo `handoff/latest.md` as gitignored state raises the question of whether roberdan-os's own
> `latest.md` should also become gitignored. That is a separate, low-risk decision for phase 1 — flag
> it, do not silently change the existing file's tracking in this design.

> **Wired-not-dormant-in-name-only (review fix, @rex #5).** The v3.3.0 "wired end-to-end" rule the
> design itself cites forbids a module that exists but has no live entry-path. So `dispatch-runner.sh`
> is reachable via a real `kb dispatch` sub-command from day one (phase 6), and `validate.sh` gains a
> check that **fails** if `kb dispatch` does not route to the dispatcher. The module is dormant
> *because it refuses* (preflight #5/#8), **not** because it is unreachable — those are different, and
> only the former is honest.

**A generic federated repo** (e.g. `~/GitHub/orca/`) after `kb init`:
```
orca/
  .git/info/exclude      # + kanban/todo|doing|done/, handoff/resume.md   (LOCAL ignore, appended — never the committed .gitignore)
  .git/hooks/pre-commit  # calls roberdan-os leak-check on staged tree (interactive safety)
  kanban/todo|doing|done # local cards, locally-excluded — never committed
  handoff/resume.md      # per-repo pause checkpoint, locally-excluded (ephemeral)
```
No roberdan-os canon is copied in. The repo's AGENTS.md is irrelevant to the gates — they are applied
from the dispatcher. This is the MirrorBuddy lesson operationalized.

---

## 6. @thor acceptance tests (all bash, no real external CLI ⇒ `validate.sh` stays green)

The center is a **hostile stub runner** — a script that *actively attempts* every forbidden action —
because a happy-path test proves nothing about gates.

1. **Gate-crossing impossible even if the model tries (must-have).** This test must **prove the vacuum
   works, not pass vacuously.** Setup: a **local bare repo as the remote**, a **simulated credential
   in the environment** (a fake `GH_TOKEN` + a writable file-URL remote), **and a hostile repo-local
   `.git/config`** planting `credential.helper = osxkeychain` + an injected remote (review fix,
   @luca #8). Assert two things: (i) *outside* the sandbox env, the stub's `git push` to the bare
   remote **succeeds** — this proves the test's push path is real; (ii) *inside* `sandbox_env` (`env -i`
   allowlist + forced `-c credential.helper=`), the same push **fails** (no token in the allowlist, no
   reachable helper — the hostile `.git/config` is neutralized), and `gh pr merge`, `git push --force`
   all fail. A test that only asserts "push fails" without (i) is green for the wrong reason (CI simply
   has no credentials) — it must show the push *would have* worked and the vacuum *stopped* it. @thor
   never sees a self-declared PASS.
2. **Atomic claim under 2 parallel runners (must-have).** Two background claims on one `<repo>+<id>` →
   assert exactly one `doing`, one clean skip; no double-claim, no corrupt card. Add a second case with
   the **same bare id in two different repos** → assert both are claimable independently (proves the
   `<repo>+<id>` keying, @rex #2).
3. **Leak-check blocks a sensitive card AND cannot fail-open (must-have).** (i) Plant a denylist term
   in stub output → assert leak-check fails the commit and leak-check stderr appears in **no**
   log/card/PR. (ii) With an **empty/absent denylist and no `denylist.sha256`**, assert the dispatcher
   **refuses at preflight #8** (never reaches a commit) — the fail-open path is closed (@rex #1).
4. **Fail-closed on a repo without enforcement (must-have).** Point the dispatcher at a repo not in
   the allowlist / not `kb init`'d / with no OS floor → assert it **refuses** (non-zero, card
   untouched), never a degraded launch. Assert preflight #5 refuses **even if** a local config file
   claims the floor is present (hard-wired, @luca #9).
5. **`runner: human-only` never dispatched.** Assert a gated card is filtered out of candidates.
6. **Federation lint + init safety.** New `validate.sh` checks: a card with non-empty `human_gates:`
   must be `human-only`; `kb init` is idempotent, de-tracks already-tracked kanban content (assert
   `git ls-files kanban/` is empty after init on a fixture that had a tracked card), **and flags
   un-pushed local-history card content** (assert `kb init` on a fixture with a committed-then-deleted
   card prints the offending commit and does not silently pass, @rex #6); registry/allowlist parsing
   degrades to empty, never crashes.
7. **Module wired even while dormant (must-have, @rex #5).** Assert `kb dispatch <card>` routes to
   `dispatch-runner.sh` (a live entry-path) and that `validate.sh`'s wired-check **fails** if that
   route is removed — proving dormancy comes from *refusal*, not from an unreachable module.

> **Phase attribution — the egress proof is NOT a phase-6 test.** The phase-6 hostile stub proves
> credential-vacuum + fail-closed + leak-check-active + wired (tests 1–7). It **cannot** prove
> network-egress blocking (3c) or dossier-`EACCES` (3b), because those depend on the OS floor that
> phase 6 does not ship. The proof that the floor actually denies egress and reads is @luca #10(e)'s
> **phase-7 suite**, which runs only after a dedicated uid + per-uid `pf`/namespace exist. Claiming a
> dormant module tests egress would be dishonest — it structurally can't.

Each maps to a `test/test-federated-kb.sh` case gated into `validate.sh` — the module can only merge
when all are green.

---

## 7. Committable phases (each leaves `validate.sh` green)

1. **Federation read-path** — `kb` cwd-scoping + `kb all` + `kb handoff` + registry parsing
   (read-only). No new gate. Tests: view/aggregation. *(Layer 1, zero risk.)*
2. **`kb init` + per-repo privacy** — scaffolding, local-exclude write (`.git/info/exclude`), **de-track already-tracked
   content**, **scan + flag un-pushed local-history card content** (human-gate escalation if already
   pushed, loud warning if local-only, @rex #6), pre-commit hook, registry write.
   Tests: idempotency, `git check-ignore`, de-track, local-history flag, leak-check wiring.
   *(Enables safe cards anywhere.)*
3. **`runner:` metadata + schema lint** — additive frontmatter + `human_gates:`↔`human-only` lint.
   *(Layer 1, a label only — no execution change.)*
4. **Migration** — move existing roberdan-os + MirrorBuddy cards to the federated model, **privacy
   active first** (`kb init` a repo *before* any sensitive card lands in its git terrain; the de-track
   + local-history scan of phase 2 is the enforcement). MirrorBuddy gets `kb init` (federation) but is
   **kept out** of `runner-allowlist`.
5. **Node 1 locks + `factory/lib.sh` extraction** — mkdir claim (`<repo>+<id>`) + repo lock + stale
   sweep; extract `verify_card`/`note_card`/`resolve_model` into `lib.sh`, re-point `run.sh` (@rex #3).
   Tests: parallel-claim race (incl. same-id-different-repo), factory regression still green.
6. **Dispatcher skeleton, WIRED but dormant** — `dispatch-runner.sh` with §f checks, reachable via
   `kb dispatch`, plus the `validate.sh` wired-check (@rex #5). **Preflight #5 (OS floor) and #8
   (leak-check active) both hard-wired to refuse** — #5's refusal is a code constant, not a config
   value a local file can flip (@luca #9). Every dispatch refuses. Tests: hostile-stub (incl. hostile
   `.git/config`), fail-closed, leak-check-active refusal, wired-check. *(Module present + wired +
   provably dormant.)*
7. **(gated, later) OS-isolation floor + real CLI enablement.** Turning off preflight #5's hard-refuse
   is a **reviewed code edit**, not a config toggle — gated on @rex + @luca + Roberto + a concrete
   use-case, with its own design doc. @luca's phase-7 **non-negotiables**, all of which the phase-7
   suite must *prove*:
   - **(a) egress denied per-uid** — default-deny egress via `pf` anchored to the runner uid (or a
     network-namespace), allowlisting only the CLI's own endpoint. Closes the dominant risk (3c).
   - **(b) dossier unreadable at runtime** — `~/.roberdan-os/private/` **and every ancestor** verified
     non-readable by the runner uid (`EACCES`, fail-closed), with **no world-readable copy** anywhere.
   - **(c) worktree is the sole writable path** + a **per-runner disposable TMPDIR**; everything else
     read-only to the runner uid.
   - **(d) git auth removed** — forced `credential.helper=`, an **empty runner keychain**, all remotes
     rendered unauthenticable (via auth absence, not shared-config mutation — §Node 3a).
   - **(e) a phase-7 suite that PROVES the floor** — actively attempts egress, dossier read, and
     out-of-worktree write from the runner uid and asserts each is denied. Green floor-suite is a
     precondition of activation.

Phases 1–5 are pure Layer-1/organizational value and ship independent of the risky module — **zero
external-runner risk**. Phase 6 lands the dispatcher *wired and inert* (it refuses). Phase 7 is the
human-gated activation, and only after its floor-suite proves the four un-bashable gates.

---

## 8. Residual risks — honest, even in restricted form

1. **Network exfiltration is the sharpest risk and is not bash-enforceable (review, @luca #7).** A
   hostile/injected runner can `curl` secrets out or tunnel via DNS; nothing in bash — not the
   credential vacuum, not a dedicated uid — closes it. It rests entirely on the phase-7 per-uid
   egress-control floor (`pf`/namespace). Until that floor exists **and its phase-7 suite proves it**,
   the only safe posture is preflight #5 refusing every dispatch. This is why 3c, not 3b, is now the
   crux.
2. **`rm -rf`-escape + dossier-read are not bash-enforceable.** They rest on the same OS floor
   (dedicated uid, `EACCES` on `private/`+ancestors, no world-readable copy). Same posture: #5 refuses
   until the floor + its suite exist.
3. **Preflight #5 is now hard-wired — a materially stronger posture than the original doc.** The prior
   version guarded "someone softens #5" only with a *convention* (weakest Layer-1). The review upgraded
   this: #5's refusal is a **code constant**, so no local config file, env var, or target repo can flip
   it to "floor present". Softening #5 is a reviewed code edit (phase 7), gated on @rex + @luca +
   Roberto. The residual is now narrowed to "a future code change bypasses the review" — a process
   risk, not a config-flip risk. Genuinely smaller, not eliminated.
4. **`human-only` / `human_gates:` labeling is fallible by omission.** A card touching a gated surface
   whose author forgot the label is treated as a candidate (§c). Backstop is Layer-2 (§0 corollary):
   for push/merge it degrades safe unconditionally; for network/filesystem it degrades safe *only once
   the phase-7 floor exists* (before that, #5 refuses the dispatch entirely). A mislabel could still
   cause an inappropriate card to *run and produce a PR* when it should have been human-only; the human
   merge review is the catch. Not a silent success, but not caught early either.
5. **PATH shims are defense-in-depth, not a guarantee.** An injected model can call absolute-path
   binaries. Only credential-vacuum + forced `credential.helper=` (3a), OS isolation (3b), and per-uid
   egress (3c) are real; the shims only raise cost and log intent.
6. **@thor verifier is itself an LLM.** A sophisticated wrong output could pass a sonnet check.
   Mitigated by: @thor runs on the *gated* Claude layer, PR-only (human still merges), evidence-only
   prompt — but it is not a proof, only a strong filter. The human merge gate is the real backstop.
7. **Budget is an estimate.** Copilot's true balance isn't queryable; a burst within a day could exceed
   the intended spend before the count cap trips. Cap conservatively.
8. **Stale-lock recovery can mis-fire.** Too-eager reclaim re-opens the claim race; too-timid wedges a
   repo after a crash. The `2×timeout`+dead-PID default is a compromise, not a proof of correctness.
9. **Un-pushed local-history card content is flagged, not auto-scrubbed.** `kb init` warns loudly about
   local commits carrying card content but does not rewrite history automatically (that is destructive
   and human-gated). A human who ignores the warning and pushes that branch leaks the content. The
   warning is the mitigation; enforcement of "don't push" stays human (@rex #6).
10. **Ollama-as-agent is still unproven** (opencode timed out at 120s where raw ollama took 9s, per the
    prior plan). The `ollama/*` runner path is designable but has no reliable execution leg today.
11. **Registry/allowlist drift.** They are local-only files; if a repo is renamed/moved they go stale.
    `kb discover` warns, but nothing forces reconciliation.

---

## 9. Where bash genuinely cannot deliver (the direct answer to the mandate)

| Node / gate | Clean in bash? | Why |
|---|---|---|
| Atomic claim (Node 1) | **Yes** | `mkdir` is atomic test-and-set on macOS bash 3.2; keyed `<repo>+<id>` |
| @thor done-gate (Node 2) | **Yes** | reuses factory's headless pass from extracted `lib.sh` (outside the stripped env) |
| push/merge gate (Node 3a) | **Yes** | `env -i` allowlist + forced `-c credential.helper=` removes the capability; even real git can't push, and a hostile `.git/config` is neutralized |
| dossier-read / `rm -rf`-escape (Node 3b) | **No** | needs OS isolation (dedicated uid, `EACCES` on `private/`+ancestors); shim bypassable, sandbox-exec deprecated |
| **network exfiltration (Node 3c)** | **No** | needs per-uid egress-control (`pf` / network-namespace); no bash mechanism blocks `curl`/DNS from an arbitrary process — **the dominant risk (@luca #7)** |
| `run.sh` reuse | **Yes, with a minimal edit** | `verify_card`/`note_card`/`resolve_model` extracted to `factory/lib.sh`; `run.sh` sources it — behavior-preserving but a real change (@rex #3) |
| Budget cap (Node 4) | **Partial** | count cap is clean; true credit balance is not queryable |

The nodes with **no clean bash solution are 3b and 3c** — and **3c (network exfiltration) is the
dominant one**, per @luca. This is precisely why module (3) ships wired-but-dormant (preflight #5,
hard-wired) rather than pretending bash can sandbox a hostile process's *network*, filesystem, or
dossier access.

---

## Review verdicts (2026-07-05) — @rex + @luca

**@rex — APPROVE-WITH-CONCERNS** (design solido, riusa il canone correttamente; concern tutte design-fixabili, nessun blocco che richiede ri-architettura):
1. **Leak-check fail-OPEN (più grave):** `leak-check.sh` con `private/.denylist` assente/vuoto fa `exit 0` (tier c) → il gate "obbligatorio" diventa no-op silente e l'output del runner viene committato senza protezione. Nessuno dei 7 preflight lo copre. **Fix: preflight #8 = asserire un tier leak-check attivo e non-vuoto prima di ogni dispatch, else refuse.**
2. **Card id non globalmente unico nel federato:** `date +%y%m%d-%H%M%S` è per-repo → due repo possono collidere su `locks/card-<id>.lock` e su `verify_card`. **Fix: lock/claim per `repo+id`, non `id` nudo.**
3. **"run.sh UNCHANGED" vs "riusa verify_card": tensione** — quelle funzioni vivono DENTRO run.sh; riusarle richiede estrarre `factory/lib.sh` (tocca run.sh). Dichiararlo.
4. **Node 3a step "remote non-pushable dentro il worktree" è ERRATO** — i worktree condividono `.git`/remote del parent → no-op o muta il remote reale. Rimuoverlo; la garanzia è il credential-vacuum.
5. **Wired end-to-end (viola la regola v3.3.0 citata dal design stesso):** `dispatch-runner.sh` non ha entry-path vivo. **Fix: entry `kb dispatch` + check in validate.sh che fallisce se non wired**, anche se il modulo refusa sempre in fase 6.
- Blind spot privacy: `git rm --cached` de-traccia in avanti ma il blob resta in history locale — leak se quel branch viene mai pushato; kb init deve segnalare anche i commit locali non-pushati con card content.

**@luca — mergeabile in forma DORMIENTE a una condizione** (il modello è solido nella sua onestà; assume l'injection e vincola le conseguenze):
- **Il crux del design è sbagliato:** il rischio dominante non è `rm -rf`/lettura-dossier (filesystem) ma **l'esfiltrazione via rete** (`curl`/DNS) — né credential-vacuum né utente-dedicato la chiudono; serve egress-control per-uid (`pf`) o network-namespace.
- **Buco concreto:** `.git/config` locale del repo untrusted bypassa la vacuum (`GIT_CONFIG_NOSYSTEM`+`GIT_CONFIG_GLOBAL=/dev/null` NON disabilitano il config locale). `credential.helper=osxkeychain` + keychain sbloccato + remote iniettato = push riuscito. **Fix: forzare `-c credential.helper=` su ogni git + neutralizzare TUTTI i remote + `env -i` allowlist invece di unset-denylist.**
- **Non negoziabili per attivare fase 7:** (a) egress denied/allowlist per-uid; (b) `private/`+antenati verificati non-leggibili dalla uid runner a runtime (EACCES, fail-closed) e nessuna copia world-readable; (c) worktree unico path scrivibile + TMPDIR per-runner disposable; (d) git forzato `credential.helper=`, keychain runner vuoto, remote neutralizzati; (e) suite fase-7 che PROVA il floor.
- **Condizione per il merge dormiente:** preflight #5 dev'essere un rifiuto inerte **hard-wired** (attivare = code-edit rivista da @rex+@luca), NON un toggle che un file di config locale possa ribaltare.

**Sintesi:** le fasi 1-5 (federazione kanban + `runner:` label) portano tutto il valore a **rischio-esterno zero**. Il dispatcher esterno (fase 6-7) resta sulla carta/dormiente e richiede: i fix di @rex (preflight #8, lock repo+id, wired-end-to-end, rimuovere step 3a errato, factory/lib.sh) + le non-negoziabili di @luca (egress-control, credential.helper vuoto, EACCES sul dossier, hard-wired refusal). Prossimo: @baccio aggiorna il design incorporandoli, PRIMA di qualunque implementazione.
