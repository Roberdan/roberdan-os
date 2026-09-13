# Shot grammar — how to plan a film that is not a slide deck

## The editorial frame

Walter Murch's **Rule of Six** — the priority weights for judging any cut:

| Weight | Criterion |
|---|---|
| 51% | **Emotion** — does the cut preserve what the audience should feel? |
| 23% | **Story** — does it advance the story? |
| 10% | **Rhythm** — is it at the right moment? |
| 7% | **Eye-trace** — does it respect where the eye is looking? |
| 5% | **2D screen plane** — does it respect the 180° axis? |
| 4% | **3D spatial continuity** — is the space consistent? |

Sacrifice from the bottom up, never the top. A cut that exists only because "the next slide
comes now" scores zero on all six. That is the exact failure this skill prevents.

## Numbers for a 120-second film

- **Average shot length (ASL):** commercials cluster at 1.5–2.5s; prestige brand films at
  2.5–4s. Roughly 76% of shots across general media run 1–5s; only ~8% exceed 8s.
- **Shot count:** target **45–55 shots** for 120s. Under 30 shots you are making a slideshow;
  over 80 you are making a trailer.
- **Vary the rhythm** — a constant ASL reads mechanical. Working pattern:
  open 3–4s → develop 1.5–2s → hold the emotional beat 4–6s → end card 2.5–3s.

To ground these on a real reference instead of trusting the numbers, measure it:

```bash
ffmpeg -i reference.mp4 -vf "select='gt(scene,0.3)',metadata=print" -f null - 2>&1 | grep pts_time
```

## Four-act structure for 60–180s

| Act | 120s budget | Job | Typography |
|---|---|---|---|
| **Hook** | 0–12s | One image, one sound. No logo, no explanation. | **Forbidden** |
| **Problem** | 12–35s | The world before the product. Human, not features. | Rare, one line |
| **Proof** | 35–85s | The product doing the thing. UI as an object in space. | Labels ≤5 words, timed to a visual event |
| **Resolve + ask** | 85–120s | Emotional lift, then the ask on a clean card held 2.5–3s | **Here.** Brand typeface, one line, fade only |

Silence is a device: keep the opening ambient/diegetic so the first entry of music lands as
a lift. Competition formats override this — Y Combinator caps application videos at 60s and
wants no music and no effects, with audio clarity as the pass/fail criterion.

## Lens language — write these into prompts and into Blender cameras

| Focal | Reads as |
|---|---|
| 14–24mm | Space, isolation, monumentality; handheld feels urgent |
| 35mm | The observer; documentary, editorial, natural |
| 50mm | Human eye; intimacy without comment |
| 85–135mm | Compression, flattery, separation from background |
| 100mm macro | Product texture — the detail shot |

Depth of field: shallow (T1.4–2.8) on subject and detail; deep (T5.6–8) on establishing so
the world reads. **180° shutter** — shutter = 1/(2×fps), so 1/48s at 24fps. This is the
single parameter that separates "film" from "screen capture"; screen recordings violate it
by construction, which is why they must be conformed (see assembly-and-sound.md).

## Light and grade

- One **key direction per scene**, held across every shot of that scene. This is what makes
  cuts feel like the same room.
- **Practicals in frame** — lamps, screens, signage — give motivated light and depth. Name
  them in every generative prompt.
- One LUT for the whole film. Per-shot corrections exist only to match into that LUT, never
  as per-shot creative grades. Lock the palette to 3–5 named colours and repeat that list
  verbatim in every generation prompt.

## Shot-list schema

The shot list is JSON, and it is the contract the linter checks.

```json
{
  "film": "MirrorBuddy — Microsoft Global Hackathon",
  "fps": 24,
  "targetDuration": 118,
  "palette": ["deep charcoal", "warm paper white", "signal rose", "slate blue"],
  "scenes": [
    {
      "id": "s1",
      "name": "Morning before school",
      "axisSide": "left",
      "keyDirection": "window left, 45 degrees",
      "shots": [
        {
          "id": "s1-01",
          "scale": "WS",
          "azimuth": 0,
          "lens": 24,
          "motion": "slow dolly in",
          "motivation": "reveals the empty desk",
          "source": "sora",
          "duration": 3.2,
          "cutPoint": "mid-action",
          "audioLead": 0.0,
          "foreground": "curtain edge, out of focus",
          "text": null
        }
      ]
    }
  ]
}
```

Field rules: `scale` ∈ `WS|MS|MCU|CU|ECU|INSERT|TEXT`; `azimuth` in degrees around the action
axis; `motion` ∈ `static|pan|tilt|dolly in|dolly out|track|handheld|crane|rack focus`;
`motivation` is prose and may not be `none`; `source` ∈ `live|screen|sora|remotion|blender|stock`;
`cutPoint` ∈ `mid-action|on-hold`; `audioLead` is seconds of audio preceding picture
(negative means audio trails, i.e. an L-cut); `text` is null unless the shot's job is typography.

## The eleven hard rules (enforced by `scripts/lint-shotlist.mjs`)

| # | Rule |
|---|---|
| R1 | Never cut between two static compositions of the same scale |
| R2 | **30° rule** — consecutive shots of the same subject differ by ≥30° azimuth |
| R3 | **Size change** — consecutive shots differ by at least one scale step |
| R4 | **180° rule** — all shots in a scene share one `axisSide` unless a motivated crossing shot is inserted |
| R5 | **Cut on action** — ≥40% of cuts land mid-gesture, not on a hold |
| R6 | **Every move is motivated** — decorative Ken Burns on a still is banned |
| R7 | No two adjacent shots may both be text-only |
| R8 | Coverage minimum per scene: establishing → medium → detail → reaction (4 setups planned) |
| R9 | **J/L-cuts on ≥30% of transitions** — audio in ≠ picture in. This destroys the slideshow read more than any visual trick |
| R10 | **Depth** — every non-text shot names a foreground element |
| R11 | **Crossfade budget 0** — dissolves only across a jump in time or place |

Plus the structural checks: shot count in range for the runtime, ASL in range, rhythm not
constant, typography absent from the hook, and the end card held ≥2.5s.

## Writing narration

- Written for the ear: short clauses, concrete nouns, no subordinate stacking.
- One idea per breath; leave air between beats so the picture can carry meaning.
- Never describe what is on screen — say what the viewer cannot see.
- Read it aloud with a stopwatch before any generation; roughly 150 words is 60 seconds at a
  calm documentary pace, so a 120s film is about 250–280 spoken words **including pauses**.
- Number words, not digits, if the voice engine drops digits. Always re-transcribe the
  rendered voice and diff it against the script.
