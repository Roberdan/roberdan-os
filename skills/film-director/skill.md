---
name: film-director
description: "Required for any moving-image work, including text-only concepts, treatments, scripts and storyboards before any media is produced: product films, demo videos, brand films, launch films, hackathon/competition submissions, trailers, explainers, case-study films, video ads, AI-generated video. Use before planning, making, directing, re-cutting, scoring or reviewing a video, or when a deliverable is an .mp4/.mov. Directs a real film — coverage, shot grammar, cut motivation, sound design, delivery gate — instead of an animated slide deck. Covers Azure Sora 2 generation, screen-recording compositing, Remotion typography, Blender shots, ffmpeg assembly and loudness compliance."
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

A text-only concept, treatment, script or storyboard for a future film is
already video work. Load this guidance even if no media file is requested;
do not expand a short concept request into production or generation.

## Routing

| Read when | File |
|---|---|
| Before the script — deciding what kind of film this is | [two-worlds.md](two-worlds.md) |
| Always — planning shots, structure, the cut | [shot-grammar.md](shot-grammar.md) |
| Filming a product, a website or an app | [capture-product-ui.md](capture-product-ui.md) |
| Generating footage with Sora 2 on Azure | [sora-azure.md](sora-azure.md) |
| Assembling, compositing UI, sound, delivery | [assembly-and-sound.md](assembly-and-sound.md) |

Executable, not prose:
- `scripts/lint-shotlist.mjs` — rejects a shot list that would render as a slideshow.
- `scripts/sora-azure.sh` — verified Azure Sora 2 adapter (create / poll / download / remix).
- `scripts/delivery-gate.sh` — measured pass/fail on the finished master.
- `scripts/preflight.mjs` — local execution, timing, pilot and durable-job consistency guard.

## Operational preflight (before delegation or new paid generation)

One owner, one authoritative absolute manifest path, one output directory, one revision.
Inspect that directory before declaring deliverables absent. Freeze the narration recording
and timing before delegating timed edits; queued changes become one new owner-controlled
revision, not repeated rewrites. The actual rendering worker must run the probe below and
the parent must inspect its receipt before assigning work. An author-only agent cannot
render: a tool listing or an authored command is not execution evidence.

Use a **prototype** first: the simplest real 10–15 second assembly, including video, voice
and captions. At most **two generated clips total** may be acquired without an existing
pilot. Do not build an elaborate renderer or launch a full batch first. **Production**
requires that MP4 to pass ffprobe and a named human's written caption, privacy, legibility
and voice review, bound to the exact media hashes. Audio presence is not proof of narration;
caption aesthetics and privacy cannot be proved by a Boolean. Existing delivery and owner
approval gates still apply to the finished film.

Manifest JSON, version 1 (all file references are `{ "path": "/absolute/canonical/file",
"sha256": "<SHA-256 of bytes>" }`; paths must exist, be readable and owned by the local user):

```json
{
  "version": 1, "owner": "Roberto", "revision": "r1", "worker": "render-worker",
  "phase": "prototype", "outputDir": "/absolute/film/output",
  "narration": {"path": "/absolute/film/voice.wav", "sha256": "..."},
  "timing": {"path": "/absolute/film/timing.json", "sha256": "..."},
  "executionReview": {"path": "/absolute/film/worker-review.json", "sha256": "..."}
}
```

`timing.json` contains `narrationSha256`, `revision`, `durationSeconds` (matching ffprobe,
within 0.1 s), and named `lockedBy`. This is the fixed narration, not a planned duration.
Run `node scripts/preflight.mjs probe /absolute/manifest.json` **in the actual worker**.
It executes a child Node process, writes and reads a challenge in the output directory,
and persists `.film-worker-probe.json` plus its challenge file. The parent reads both,
then writes `worker-review.json` with `probeSha256`, `reviewedBy`, and written `notes`;
hash that review into `executionReview`. Re-probe and re-review after timing, worker or
revision changes. Do not delegate rendering until `check /absolute/manifest.json` passes.

For `phase: "production"`, add `pilot`, `captions`, `pilotReview` file references.
The review JSON contains `pilotSha256`, `narrationSha256`, `captionsSha256`,
`timingSha256`, `revision`, `reviewedBy`, and written `captions`, `privacy`,
`legibility`, `voice` observations. Watch the actual pilot with those captions and voice;
the CLI checks bytes/structure and review linkage, not whether the reviewer was truthful.

At every planning/render/review cycle, run `observe /absolute/manifest.json /absolute/pilot.mp4`
for a new inspectable 10–15 s audio/video artifact, or `observe /absolute/manifest.json -`
if none was produced. Two consecutive no-progress observations block expansion. Repeated
or previously seen hashes are not new progress. Stop auxiliary passes, inspect the blocker,
and produce a small new artifact; never reset the ledger to escape the stop.

The Azure adapter requires explicit `FILM_MANIFEST=/absolute/manifest.json` and a unique
`FILM_REQUEST_KEY=shot-01-r1` for **create/shot/remix only**. These are not spending
approval: obtain human approval separately. `shot` also requires an absolute output path
directly inside `outputDir`. `status/wait/get` on existing IDs remain unguarded/resumable.
The adapter reserves an **uncertain** attempt durably before each paid POST, then records
the returned ID as **accepted**. Identical request bodies or keys cannot be recreated.
One unresolved job blocks all new generation: deliberately conservative concurrency of one,
not an assumed requests-per-minute allowance. On 429, timeout, or lost response, pause new
dispatch, inspect service status/backoff and reconcile; never automatically POST again.

After inspecting actual service evidence, write a reconciliation JSON with `key`, `id`,
`status` (`completed`, `failed`, `cancelled`, or `rejected` only when no job was accepted),
`reviewedBy`, and written `notes` identifying that evidence. Run
`reconcile /absolute/manifest.json request-key /absolute/reconciliation.json`.
Only `rejected` omits `id`. Keys and request hashes remain in the ledger even after failure.
Never invent a rejection to clear an uncertain job. Keep the same manifest path/output
directory and `.film-preflight-state.json` through revisions; do not delete job history.
A leftover `.film-preflight-state.json.lock` means inspect the interrupted writer first.

**Coverage and limits:** a discipline/consistency guard, not a security boundary, remote
agent identity attestation, authorization, or semantic review. It cannot discover absent
remote tools; the worker must execute and the parent inspect. Direct Azure callers and
separate renderers are not intercepted: run this preflight explicitly for their delegation
and batch gates. Progress observations and reconciliation require truthful operator input.
Use this worktree's canonical script directly for local activation; do not hand-edit
installed wrappers or change global settings.

## The non-negotiable order of work

Never open a render tool before step 3 is signed off.

1. **Brief.** Audience, one sentence of intent, runtime, where it will be watched, what the
   viewer must feel and do. Judging criteria if it is a competition entry.
2. **Choose the world** — Apple or TED ([two-worlds.md](two-worlds.md)). The owner decides,
   you recommend. A film that has not chosen will hedge, and a hedged film is a slideshow.
3. **Script.** Narration written for the ear, not the page. Every factual claim carries a
   source; anything not shipped is visibly marked as roadmap. Read it aloud against a stopwatch
   — narration length sets runtime, not the other way round.
4. **Shot list** as JSON (schema in shot-grammar.md), then `node scripts/lint-shotlist.mjs`.
   **A shot list that fails the linter is not a shot list.** Fix the direction, never the linter.
5. **Acquire.** Real footage first (screen recordings, camera, existing assets), generation
   second, motion design third. Generated footage is the atmosphere layer; the product is
   always the real product. For anything on a screen, follow
   [capture-product-ui.md](capture-product-ui.md) and run its three verification checks —
   capture scripts report success while producing unusable files.
6. **Assemble picture** against the narration timing. Cut on motion, not on sentences.
7. **Sound.** Six layers (assembly-and-sound.md). This is where "expensive" is decided.
8. **Adversarial review before the master, not after.** Two independent red teams, different
   models, identical hostile brief, each asked for a ranked kill-list and a one-paragraph
   verdict. Where they converge, act without debating. Where they differ, it is the owner's
   call. This costs an hour and has never once failed to find something disqualifying.
9. **Delivery gate.** `scripts/delivery-gate.sh` must pass, plus a human look at a contact
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

## Lessons paid for the hard way

Each of these cost at least one rejected cut. They are not principles — they are scars.

- **A slideshow is a footage problem before it is a directing problem.** When the source
  captures are small, the only way to fill a frame is to show the whole thing, statically.
  You cannot direct your way out of thumbnails. Fix acquisition first.
- **A tiny shot count is the diagnosis, not a measurement error.** Dissolve-heavy cuts
  under-report scene changes, so the instinct is to distrust the number. Trust it: seven shots
  in two minutes *is* a slide deck, whatever it feels like in the timeline.
- **Never delegate acquisition without verifying the files yourself.** An agent reporting
  "captured 6 scenes at 2560x1440" is not evidence. `ffprobe` is evidence, a contact sheet you
  looked at is evidence.
- **The product must arrive in the first ten seconds** in either world. Every rejected version
  of every film opened with the metaphor.
- **"Make it like Apple" means fewer things on screen, not more expensive things on screen.**
  Deconstruct references into observed rule / inferred purpose / adaptation / uncertainty;
  transfer principles, never identity.
- **One genuine interaction outranks any amount of beautiful marketing site.** If the film
  cannot show the thing working, it is a brand film, and it should be sold as one.
- **Language is a deliverable.** Check it as a fact, with a word count, not as an impression.



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
