# learn-protocol — continuous learning (capture → distill → quarantine)

Distill what changed in the world model, after interactions, into classified memory.
**Capture ≠ distill** (decoupled for portability + anti-noise).
See [[ADR-0001]], [[memory-protocol]].

## 1. Capture (per-platform, cheap)

Each platform appends to a durable cursor, **without judgment**:
```
~/.roberdan-os/learnings/inbox/<YYYY-MM-DD>-<session>.md   # 1 record/signal
```
Claude: `Stop` hook, opt-in (`RDA_LEARN=1`). Others: explicit command / end-of-task.
No lock, no writes to the vault here.

## 2. Distill (periodic batch, launchd)

`learn/distill.sh` → reads the accumulated inbox → for each signal:
1. **Classify** into the taxonomy (5 classes) + discard the ephemeral (context of a
   single issue ≠ a reusable lesson).
2. **Dedup-before-write:** `gbrain search` on the `vault` source → if there's a match,
   propose **merge/supersedes**, not a new file.
3. **Privacy filter** (deny-list as code) → redact or drop.
4. Writes **candidates to quarantine** `~/.roberdan-os/learnings/quarantine/`, never
   directly to the vault.

## 3. Gate (promotion)

- `tool-quirk` (≥2x) and `correction` (with quote) → auto-eligible for promotion.
- `capability-gap`, `voice`, ambiguous `decision` → **human confirmation** before promoting.
- The actual promotion into the vault is done by the single-writer job of
  [[ontology-protocol]].

## Anti-degradation

Never auto-write blindly into the canon. A misinterpreted learning that becomes "truth"
self-reinforces: this is why **quarantine + corroboration**, not direct commit.
