# learn-protocol — continuous learning (capture → distill → quarantine)

Distill what changed in the world model, after interactions, into classified memory.
**Capture ≠ distill** (decoupled for portability + anti-noise).
See [[ADR-0001]], [[memory-protocol]].

## 1. Capture (per-platform, cheap)

Each platform appends to a durable cursor, **without judgment**:
```
~/.roberdan-os/learnings/inbox/<YYYY-MM-DD>-<session>.md   # 1 record/signal
```
Record a **real learning** by hand or at end-of-task:
```
learn/capture.sh "<a reusable lesson, one sentence>"
learn/capture.sh --class correction "<lesson>"   # assert the class outright (optional)
```
`--class` must be one of the 5 taxonomy classes; it is carried as a `{class:…}` control
token that distill honours. A bare `learn/capture.sh --session "session … cwd=…"` writes
an **ephemeral** marker that distill drops — so per-session boilerplate never becomes a note.
Claude: `Stop` hook, opt-in (`RDA_LEARN=1`). Others: explicit command / end-of-task.
No lock, no writes to the vault here.

## 2. Distill (periodic batch, launchd)

`learn/distill.sh` → reads the accumulated inbox → for each signal:
1. **Drop ephemera** first: session/cwd boilerplate markers (context of a single issue
   ≠ a reusable lesson) are discarded, never quarantined.
2. **Classify** into the taxonomy (5 classes) with a **deterministic, dependency-light**
   classifier (`learn/classify.sh`: an author `{class:…}` token wins, else keyword
   heuristics; no network/LLM, so it runs in CI). It emits a **real class, never `TODO`**;
   an unmatched real learning defaults to `decision` for the human to retag. An optional
   LLM-assisted classifier can be layered on later behind an env flag — the default stays
   deterministic.
3. **Dedup-before-write:** `gbrain search` on the `vault` source → if there's a match,
   propose **merge/supersedes**, not a new file.
4. **Privacy filter** (deny-list as code) → redact or drop.
5. Writes **candidates to quarantine** `~/.roberdan-os/learnings/quarantine/`
   (`approved: false`), never directly to the vault.

## 3. Gate (promotion) — human-gated for EVERY class today

Promotion is done by the single-writer job of [[ontology-protocol]] (`ontology/curate.sh`),
which promotes **only** candidates a human has flipped to `approved: true`. This gate is
Roberto's and is **not** auto-crossed for any class — including `tool-quirk`/`correction`.

- The taxonomy still records intended future policy: `tool-quirk` (≥2×) and `correction`
  (with quote) are the auto-eligibility *candidates*; `capability-gap`, `voice`, ambiguous
  `decision` always need human confirmation.
- **Honest status:** auto-eligibility is **not yet wired** — `curate.sh` requires
  `approved: true` for all classes. The mechanism is complete end-to-end (a classified,
  approved learning is provably promoted, see `test/test-metaloop.sh`); the only step still
  human-in-the-loop is flipping `approved:` — deliberately, per gate #4.

## Anti-degradation

Never auto-write blindly into the canon. A misinterpreted learning that becomes "truth"
self-reinforces: this is why **quarantine + corroboration**, not direct commit.
