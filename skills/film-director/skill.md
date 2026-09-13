---
name: film-director
description: "Required for any moving-image work: product films, demo videos, brand films, launch films, hackathon/competition submissions, trailers, explainers, case-study films, video ads, AI-generated video. Use when the request involves making, directing, re-cutting, scoring or reviewing a video, or when a deliverable is an .mp4/.mov. Directs a real film — coverage, shot grammar, cut motivation, sound design, delivery gate — instead of an animated slide deck. Covers Azure Sora 2 generation, screen-recording compositing, Remotion typography, Blender shots, ffmpeg assembly and loudness compliance."
providers: [claude, copilot, codex]
---

# Film director

## Why this skill exists

Agent-made videos fail in one specific, recognisable way: they are **assembled**
(full-screen headline cards, screenshots on flat backgrounds, crossfades between text,
Ken Burns pushes on stills) instead of **covered** (a scene shot from several angles and
cut on motion). The result reads as an animated slide deck. Roberto has rejected exactly
that output; this skill exists so it does not happen again.

A slide deck is one composition per idea, cut on a text beat, with no spatial relationship
between adjacent frames. A film is several compositions per idea, cut on motion, with
continuity of space and a sound bed that runs underneath the cuts.

**Engage this skill before writing a single prompt, script line or ffmpeg command** for any
moving-image deliverable. It supplies craft and an executable gate — not permission to
spend, publish, or declare done. The owner approves subjective direction. Nothing is
uploaded, published or submitted without an explicit human instruction.

## Routing

| Read when | File |
|---|---|
| Always — planning shots, structure, the cut | [shot-grammar.md](shot-grammar.md) |
| Generating footage with Sora 2 on Azure | [sora-azure.md](sora-azure.md) |
| Assembling, compositing UI, sound, delivery | [assembly-and-sound.md](assembly-and-sound.md) |

Executable, not prose:
- `scripts/lint-shotlist.mjs` — rejects a shot list that would render as a slideshow.
- `scripts/sora-azure.sh` — verified Azure Sora 2 adapter (create / poll / download / remix).
- `scripts/delivery-gate.sh` — measured pass/fail on the finished master.

## The non-negotiable order of work

Never open a render tool before step 3 is signed off.

1. **Brief.** Audience, one sentence of intent, runtime, where it will be watched, what the
   viewer must feel and do. Judging criteria if it is a competition entry.
2. **Script.** Narration written for the ear, not the page. Every factual claim carries a
   source; anything not shipped is visibly marked as roadmap. Read it aloud against a stopwatch
   — narration length sets runtime, not the other way round.
3. **Shot list** as JSON (schema in shot-grammar.md), then `node scripts/lint-shotlist.mjs`.
   **A shot list that fails the linter is not a shot list.** Fix the direction, never the linter.
4. **Acquire.** Real footage first (screen recordings, camera, existing assets), generation
   second, motion design third. Generated footage is the atmosphere layer; the product is
   always the real product.
5. **Assemble picture** against the narration timing. Cut on motion, not on sentences.
6. **Sound.** Six layers (assembly-and-sound.md). This is where "expensive" is decided.
7. **Delivery gate.** `scripts/delivery-gate.sh` must pass, plus a human look at a contact
   sheet sampled **at cut points and mid-transition**, not only at beat centres.

## Ten rules that survive every project

1. **Coverage, not cards.** Every idea gets establishing → medium → detail → reaction, even
   if only two survive the cut.
2. **Every cut is motivated** — by movement, by a new piece of information, or by sound.
   "The next slide" is not a motivation.
3. **Never dissolve text through text.** Crossfade budget is zero except across a jump in
   time or place.
4. **Typography is a shot with a job**, never a beat separator, and never on top of UI.
5. **No decorative camera moves.** A push-in on a still because the frame is boring is the
   signature of the failure mode.
6. **Depth in every frame** — foreground, midground, background. A subject on a flat colour
   field is a slide.
7. **Sound runs under the picture**, continuously. J- and L-cuts on at least a third of edits.
8. **One frame rate, one grade, one typeface, one key-light direction per scene.**
9. **The real product, captured live.** Never fake UI with a generative model, ever.
10. **Measure, don't claim.** Duration, loudness, average shot length, caption legibility and
    factual sourcing are all verified with commands before anyone says "done".

## Honesty rules specific to film

Film technique is persuasion, which makes it easy to lie by implication. In any film that
represents real work:

- Never imply a capability the product does not have. Roadmap is labelled on screen or in
  narration, not buried in production notes.
- No invented metrics, users, revenue, partnerships, awards or clinical claims.
- Generated footage may carry mood; it must never depict the product, its users or its
  results. Keep a `third-party-assets` section in the production notes for anything you did
  not create, with its licence.
- Sora 2 rejects images containing faces and blocks real people — do not attempt lookalikes
  of identifiable individuals, and do not present generated humans as customers.
- Captions are an accessibility requirement, not a style choice.

## What "done" means here

A film is done when the delivery gate passes, the contact sheet shows no collisions or
ghosting, every claim in the narration traces to a source, and the owner has watched it.
Rendering successfully is not done. Thor remains the final quality gate.

## Attribution

Structural debt to two prior-art skills, reused within their licences:
[wuwangzhang1216/DirectorSKILL](https://github.com/wuwangzhang1216/DirectorSKILL) (MIT) for
the symptom→diagnosis framing of the slideshow failure, and
[smixs/visual-skills](https://github.com/smixs/visual-skills) (CC-BY-4.0) for per-model
prompt-adapter structure. Editorial doctrine follows Walter Murch, *In the Blink of an Eye*.
Neither prior skill renders a film; the generation, assembly, sound and gate here are ours.
