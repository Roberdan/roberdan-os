# System test report — roberdan-os — 2026-07-02

Full-system test with real use cases, run interactively in `~/GitHub/roberdan-os` (roberto-mode:
evidence-first, no push). Six scenarios, each exercised end-to-end against the real repo (temp
dirs used only where a scenario would otherwise mutate the live kanban/factory state). Commands
and raw output below are the evidence, not paraphrase.

**Overall: 6/6 PASS on their stated criteria.** The factory silent-failure regression (the reason
this task exists) holds. One real, previously-undetected gap was found alongside a passing
criterion (scenario 2: manual-skill install/collision issue) and one minor one-commit staleness
(scenario 6) — both flagged for Roberto, neither blocks the PASS verdict.

---

## 1. Recall (gbrain search/query against the vault) — PASS

Canon (`AGENTS.md` §Memory): *"Recall: `gbrain search` keyword first (semantic search drops
scattered topics)."* Verified both modes.

Keyword search, vault-scoped, for terms describing this repo's own plan:

```
$ gbrain search "roberdan-os factory kanban gates" --source vault --limit 8
[0.8473] agent-learnings/roberdan-os-paper
[0.8248] agent-learnings/roberdan-os-adr-0001-self-improving
[0.8120] agent-learnings/roberdan-os-plan
[0.7913] programs/convergio/plans/convergio-local-public-readiness
[0.7802] type/agent-learning
...
```

Correctly surfaces the three roberdan-os-specific vault notes at the top (score ≥ 0.81), with
generic noise below them — exactly the "keyword first" behavior the canon prescribes.

Semantic mode (`gbrain query`) was also probed:

```
$ gbrain query "how does the factory guard against silent failures" --source vault --limit 5
[0.8740] decisions/d034-fleet-retrieval-cross-repo-graph -- Test Strategy...
[0.8728] programs/mirror-buddy/mirror-buddy-path-to-v-1-real-product -- gating per modalità costose (voice)...
[0.8481] reference/career-stage-profiles/reliability-engineering-hardware-engineering -- ...
[0.8240] reference/career-stage-profiles/radio-frequency-engineering-hardware-engineering -- ...
[0.8171] programs/convergio/v3/prd-fleet-retrieval-cross-repo-graph -- FR-6.4 `cvg fleet validate`...
```

Zero roberdan-os-specific hits — all five results are unrelated Convergio/career-profile notes,
scored deceptively high (0.82–0.87). This is the exact failure mode the canon warns about
("semantic search drops scattered topics"), confirming the documented guidance is correct advice,
not boilerplate: an agent relying on `gbrain query` alone here would get confidently-wrong noise
instead of the real answer the keyword search found above.

**Caveat, not a failure:** this session's own incident (the exit-127 factory bug, the privacy
leak) is not yet recallable from the vault — it lives in `handoff/latest.md` and this session's
transcript, not (yet) promoted through `learn/` → `curate` → vault. That is by design (promotion
is human-gated, see scenario 3), not a recall defect.

---

## 2. Skills — auto-invoke wiring — PASS on the documented criterion, + a real finding on the rest

Canon (`AGENTS.md` §Skills) lists 8 canonical skills and states 3 of them
(`premortem`, `focus-group`, `problem-validation`) auto-trigger on documented phrases. `bin/sync.sh
--emit-only` (run by `bootstrap.sh` and by `test/validate.sh`'s drift check) correctly generates
**all 8** wrappers into staging:

```
$ ls platforms/claude/skills/
auto-checkpoint  focus-group  premortem  problem-validation  review  ship  sync  verify-done
```

But staging (`platforms/claude/skills/`) is **not** the live, auto-invoke-relevant location —
`~/.claude/skills/` is. `bootstrap.sh` symlinks `agents/*.md` into `~/.claude/agents/` (step 3) but
has **no equivalent step for skills** — installing them live is left to `bin/sync.sh --install`,
run manually, at some point in the past. Checking what's actually live today:

```
$ ls ~/.claude/skills/ | grep -E "premortem|focus-group|problem-validation|review|ship|sync|verify-done|auto-checkpoint"
focus-group        (drwxr-xr-x, Jul 1 12:12)
premortem          (drwxr-xr-x, Jul 1 12:12)
problem-validation (drwxr-xr-x, Jul 1 12:12)
review             (drwx------, Jun 28 10:05)   <- present, but NOT roberdan-os's
ship               (drwx------, Jun 28 10:05)   <- present, but NOT roberdan-os's
# sync, verify-done, auto-checkpoint: absent entirely
```

Content check on the live `review`/`ship` confirms they are **gstack's own skills of the same
name**, not roberdan-os's wrapper — a name collision silently shadows roberdan-os's version:

```
$ head -6 ~/.claude/skills/review/SKILL.md
name: review
description: Pre-landing PR review. (gstack)
```

versus the genuine roberdan-os wrapper pattern (verified present and correct for the 3 that *are*
live):

```
$ head -8 ~/.claude/skills/premortem/SKILL.md
name: premortem
description: ...MANDATORY TRIGGERS: 'premortem this/questo'...
# premortem (wrapper)
Logica canonica: leggi `skills/premortem/skill.md` in roberdan-os. Questo è un wrapper
generato da `bin/sync.sh` — non editarlo a mano.
```
(Same verified for `focus-group` and `problem-validation` — both carry the "wrapper generato da
`bin/sync.sh`" marker and the documented TRIGGER text, matching this session's own injected skill
list verbatim.)

**On the task's literal criterion** — "confirm auto-invoke wiring *where documented*" — this is a
clean PASS: `AGENTS.md` §Skills documents auto-trigger for exactly three skills
(`premortem`/`focus-group`/`problem-validation`), and all three are verified live with the correct
wrapper content and TRIGGER text. The other 5 skills are manually-invoked by design (no
auto-trigger claim in the canon), and `bin/sync.sh` defaults to `--emit-only` / staging —
`--install` to `~/.claude/skills/` is explicitly gated, and `bootstrap.sh` deliberately installs
agents live (step 3) but has no equivalent step for skills. So "not live" may be **intended**
(canon-as-source-of-truth, live install optional), not automatically a defect.

**Real finding, separate from the criterion:** of the 5 manual skills, 2 (`review`, `ship`) *are*
live in `~/.claude/skills/` but are silently **shadowed by gstack's own skills of the same name**
(confirmed by content, not just presence — see below), and 3 (`sync`, `verify-done`,
`auto-checkpoint`) were never installed at all. If Roberto ever expects roberdan-os's `/review` or
`/ship` semantics, he gets gstack's instead, with no error or warning. Whether this is a bug (name
collision to fix) or acceptable (those 2 were always meant to be manual/rare) is Roberto's call —
flagging it, not fixing it.

**Verdict, by skill:**

| Skill | Canon says auto-trigger | Live in `~/.claude/skills/` | Status |
|---|---|---|---|
| `premortem` | yes | yes, genuine wrapper | ✅ live and correct |
| `focus-group` | yes | yes, genuine wrapper | ✅ live and correct |
| `problem-validation` | yes | yes, genuine wrapper | ✅ live and correct |
| `review` | (manual) | yes, but it's **gstack's**, shadowed | ⚠ shadowed |
| `ship` | (manual) | yes, but it's **gstack's**, shadowed | ⚠ shadowed |
| `sync` | (manual) | **absent** | ❌ never installed |
| `verify-done` | (manual) | **absent** | ❌ never installed |
| `auto-checkpoint` | (manual) | **absent** | ❌ never installed |

`test/validate.sh` lints the canon's own `skill.md` frontmatter and checks canon-vs-staging drift
(`platforms/`), but has **no check on staging-vs-live** (`~/.claude/skills/`) — so this gap is
invisible to the existing test suite. The 3 auto-trigger skills the canon actually depends on for
unattended behavior are fine; the 5 manually-invoked ones have real gaps that would surprise
Roberto if he typed `/verify-done` or `/sync` expecting roberdan-os's version.

---

## 3. Meta-loop — `learn/capture.sh` + `learn/distill.sh` — PASS

Ran against a synthetic signal with isolated `RDA_INBOX`/`RDA_QUARANTINE` (never touches the real
inbox):

```
$ RDA_SESSION="systest-2026-07-02" RDA_INBOX="$TMP_INBOX" bash learn/capture.sh \
  "system-test synthetic signal: agent forgot to re-run validate.sh before commit"
capture: +1 signal → .../inbox/2026-07-02-systest-2026-07-02.md
exit=0

$ cat inbox/2026-07-02-systest-2026-07-02.md
- [2026-07-02T04:36:26+0200] system-test synthetic signal: agent forgot to re-run validate.sh before commit

$ RDA_INBOX="$TMP_INBOX" RDA_QUARANTINE="$TMP_QUAR" bash learn/distill.sh
distill: 1 candidates → .../quarantine (quarantine, gated)
exit=0

$ cat quarantine/20260702-043627-1.md
---
class: TODO
approved: false   # human/curate gate — see learn-protocol
source_inbox: 2026-07-02-systest-2026-07-02.md
---
## Signal
system-test synthetic signal: agent forgot to re-run validate.sh before commit
## Possible duplicates in the vault (keyword dedup-check)
...
```

Both scripts ran clean (`exit=0`), the inbox record is append-only and correctly timestamped/
session-tagged, and `distill.sh` correctly staged the signal as an **unapproved** candidate
(`approved: false`) in quarantine rather than writing to the vault — matching the documented
"self-proposing, never self-applying" contract (`AGENTS.md` §Memory, `docs/adr/0001-self-improving.md`).

Privacy hard-gate probed with a signal containing the dossier path — correctly blocked at
`capture.sh`, before it ever reaches the inbox:

```
$ RDA_INBOX="$TMP_INBOX" bash learn/capture.sh \
  "leak test: ~/.roberdan-os/private/roberto-profile.md contains X"
capture: privacy block (dossier path), skip
exit=0
```

---

## 4. KB gates — end-user walkthrough (todo→doing, doing→done) — PASS

Full narrative walkthrough against an isolated `RDA_KANBAN` temp board (not the real one),
simulating what an agent and Roberto/`@thor` actually see:

```
### 1) Roberto adds a real card via kb add
$ kb add "walkthrough probe card" "real DoD: report exists" "real acceptance: PASS/FAIL with evidence"
added todo/260702-043638

### 2) an agent tries to self-start the card without human approval
$ kb start 260702-043638
REFUSED: todo->doing is a human gate. Approve with: kb start 260702-043638 --by roberto
rc=1

### 3) Roberto approves
$ kb start 260702-043638 --by roberto
doing/260702-043638 started (approved by roberto)
rc=0

### 4) agent tries to self-close without @thor evidence
$ kb finish 260702-043638
REFUSED: doing->done needs @thor validation with EVIDENCE (not a rubber-stamp).
rc=1

### 5) @thor validates with evidence
$ kb finish 260702-043638 --thor "system-test-2026-07-02: verified via walkthrough"
done/260702-043638 verified by @thor (system-test-2026-07-02: verified via walkthrough)
rc=0
```

Final card state confirms both gate approvals are durably recorded, not just accepted-and-forgotten:

```
status: done
approved_by: roberto
approved_at: 2026-07-02
verified_by: thor
verified_evidence: system-test-2026-07-02: verified via walkthrough
verified_at: 2026-07-02
```

Both gates (human approval for `todo→doing`, `@thor`+evidence for `doing→done`) refuse exactly as
documented, and the card only moves forward once the correct actor supplies the correct evidence.

---

## 5. Factory guard — the regression this task exists to catch — PASS

This is the fix from commit `b7f1cd1` (`claude`/`timeout` binaries unresolved under launchd's
minimal PATH → tasks failing with exit 127 were silently filed as `done/`), verified present in
history:

```
$ git cat-file -t b7f1cd1
commit
$ git log --oneline | grep b7f1cd1
b7f1cd1 fix(factory): don't mark failed tasks done; resolve timeout binary; scope default dir
```

Re-ran the regression suite directly:

```
$ bash test/test-factory-kb.sh
...
=== factory: billing guard (no API-key billing on the Max plan) ===
  ok: factory/run.sh unsets ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN
=== factory: context-primer injection ===
  ok: factory/run.sh references handoff/context-primer.md
=== factory: a failing task never lands in done/ (regression test for the 2026-07-01 bug) ===
  ok: a failing task was never filed under done/
  ok: a task that exhausts retries lands in failed/ with escalate: true
=== factory: a succeeding task lands in done/ ===
  ok: a succeeding task lands in done/
=== factory: card: field syncs the result back onto the kanban card ===
  ok: factory result synced onto the referenced kanban card
=== factory: claude binary resolved even without the interactive alias in PATH ===
  ok: claude binary resolved via the $HOME/.local/bin fallback (no PATH, no alias)
...
test-factory-kb: ✅ TUTTO VERDE
EXIT=0
```

Confirmed wired into the standard gate (not just a standalone script someone has to remember to
run):

```
$ grep -n "test-factory-kb" test/validate.sh
86:if bash test/test-factory-kb.sh >/dev/null 2>&1; then ok "kb gates + factory guardrails verdi"; ...
```

Full `test/validate.sh` run, end to end, all green including this suite:

```
$ bash test/validate.sh
...
=== factory + kb gates ===
  ok: kb gates + factory guardrails verdi
validate: ✅ TUTTO VERDE
```

The specific failure mode (exit-127 task silently landing in `done/`) is exercised under an
`env -i` launchd-like minimal PATH inside the suite (`FAC/bin/claude` a stub that exits 5, no
`timeout`/`claude` in PATH) and correctly lands in `failed/` with `escalate: true` after exhausting
retries, never in `done/`. **The fix holds.**

---

## 6. Handoff currency — PASS (minor staleness noted)

`handoff/latest.md` and `handoff/context-primer.md` both exist and are readable; every file/path
the primer names (`AGENTS.md`, `handoff/latest.md`, `kanban/`) exists on disk:

```
OK  AGENTS.md
OK  handoff/latest.md
OK  kanban
```

`handoff/latest.md` was last updated in commit `8c986fa` ("docs(handoff): refresh with this
session's story..."). One commit landed after it, `fe6e32f` ("chore(kanban): close
T-adversarial-judge (verified by @thor)"):

```
$ git log --oneline -8
fe6e32f chore(kanban): close T-adversarial-judge (verified by @thor)
8c986fa docs(handoff): refresh with this session's story, decisions, open gates
...
```

Comparing the handoff's "Open threads" section against current kanban state: thread #2 still says
*"`kb finish --thor` for the same two cards, plus re-annotated `T-adversarial-judge` /
`T-system-tests`"* — implying `T-adversarial-judge` still needs a `@thor` pass. It does not:

```
$ ls kanban/done | grep -i adversarial
T-adversarial-judge.md
$ ls kanban/doing kanban/todo
kanban/doing: T-system-tests.md
kanban/todo:  FtS-ingest.md  G5-always-on.md  T-tests-factory-kb.md  T-usage-guide.md
```

**Minor, one-commit-old drift**: the handoff narrative text is stale on this single point (the
card was closed after the handoff doc was last written). Everything else in "Open threads" (item
1, the pending `kb start --by roberto` approvals; item 6, push confirmation) still matches current
kanban/git state exactly. Pointers/paths are all correct; only this one narrative line needs a
one-line touch-up next time `handoff/latest.md` is edited.

---

## Summary table

| # | Scenario | Verdict | Notable finding |
|---|---|---|---|
| 1 | Recall (gbrain) | ✅ PASS | Keyword-first guidance in canon empirically correct; semantic mode does drop this repo's own topics as documented |
| 2 | Skills auto-invoke | ✅ PASS (documented criterion) + finding | All 3 documented auto-trigger skills correctly live; separately found `review`/`ship` shadowed by gstack skills of the same name and `sync`/`verify-done`/`auto-checkpoint` never installed live — intended or defect is Roberto's call, no test currently catches it |
| 3 | Meta-loop (capture/distill) | ✅ PASS | Runs clean, privacy hard-gate blocks dossier-path signals, correctly quarantines as unapproved |
| 4 | KB gates walkthrough | ✅ PASS | Both human gates refuse/accept exactly as documented, evidence durably recorded |
| 5 | Factory guard regression | ✅ PASS | `test/test-factory-kb.sh` green, wired into `test/validate.sh`, exit-127-into-done/ bug does not regress |
| 6 | Handoff currency | ✅ PASS (minor) | Files/pointers all correct; one narrative line one commit stale |

**Recommendation (not executed — human decision):** file a small follow-up card to either (a) add
a `sync.sh`/`bootstrap.sh` step that installs skills live with collision detection against
existing `~/.claude/skills/` entries, or (b) rename roberdan-os's `review`/`ship` skills to avoid
colliding with gstack's, and extend `test/validate.sh` with a staging-vs-live skill check.
