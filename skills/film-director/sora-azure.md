# Sora 2 on Azure — generation as a cinematography instrument

Verified against Microsoft Learn (`foundry/openai/concepts/video-generation`, updated
2026-03-18) and OpenAI's Sora 2 prompting guide (updated March 2026), and exercised
end-to-end on Roberto's `virtual-bpm-prod` subscription.

## Access

Keyless Entra authentication. Account keys are disabled by corporate policy in this tenant —
do not attempt to fetch keys and never add policy skip tags.

```bash
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)
```

Tokens expire in about an hour; refresh per batch. `scripts/sora-azure.sh` wraps create,
poll, download and remix. Provisioned deployment at time of writing: `sora-2` on
`imgtests-openai-8015083b` (eastus2), quota **9 requests per minute** — serialise, never blast.

## The two API surfaces

**v1 `videos` (preferred, OpenAI-compatible).**
`POST /openai/v1/videos?api-version=preview` with `{model, prompt, size, seconds,
input_reference?, remix_video_id?}`; then `GET /openai/v1/videos/{id}` to poll and
`GET /openai/v1/videos/{id}/content` to download.
Azure documents `size` ∈ `1280x720 | 720x1280` and `seconds` ∈ `4 | 8 | 12` (default 4).
OpenAI documents more for `sora-2-pro` (1080p, up to 20s, extension 6× to 120s, a
`characters[]` API). **Treat the Azure table as binding and probe the live deployment**
before designing a shot around 1080p or 20s.

**Legacy `video/generations/jobs` (multipart).** Documents `width`/`height` up to
`1920x1080`, `n_variants` 1–4, and `inpaint_items` — an image or video anchored at a chosen
`frame_index` with `crop_bounds`. This is the only documented Azure path to frame-index
conditioning, and `n_variants` is free coverage: **generate four variants and select like
takes** rather than chasing a perfect prompt.

Render time is 1–5 minutes per clip.

## Content restrictions that will bite a product film

- **No real people, including public figures. Input images containing faces are rejected.**
  Founders, customers and children must be shot, composited, or left out.
- No copyrighted characters, branded hardware lookalikes, or music.
- Output must be safe for under-18 audiences.

Consequence: Sora is the **atmosphere layer** — light, texture, environment, hands, paper,
desks, weather, interiors. It never depicts the product, its users, or its results.

## Prompt structure that actually works

```text
[Prose scene description: subject, wardrobe, set, weather, texture]

Cinematography:
Camera shot: [framing + angle, e.g. "medium close-up, slow push-in with parallax"]
Lens: [e.g. "35 mm virtual lens, shallow depth of field"]
Lighting: [key direction + practical + rim]
Palette anchors: [the film's 3-5 named colours, verbatim, every time]
Mood: [tone]

Actions:
- [beat 1, countable: "takes four steps to the window"]
- [beat 2: "pauses"]
- [beat 3: "pulls the curtain in the final second"]

Background Sound:
[diegetic only, name 2-3 sources; "no added score"]
```

Findings from the official guide, which are load-bearing:

- **Shorter clips follow instructions more reliably.** Stitching two 4-second clips beats
  generating one 8-second clip. **Default shot length is 4 seconds** — which lines up with a
  2–3s ASL: generate 4s, cut 2.5s, keep handles.
- **One camera move and one subject action per clip.** State beats as counts, not adverbs.
- Short prompts give creative variance; long prompts give control with lower reliability.
  The same prompt twice does not give the same result — **batch and select is the workflow**.
- Rewrite weak prompts into physical specifics: "a beautiful street at night" becomes "wet
  asphalt, zebra crosswalk, neon signs reflecting in puddles"; "cinematic look" becomes
  "anamorphic 2.0x lens, shallow depth of field, volumetric light".
- The guide's ultra-detailed template is a camera-department brief — *Format & Look*
  (`180° shutter`, `fine grain`, `subtle halation`, `no gate weave`), *Lenses & Filtration*
  (`32/50mm spherical primes; Black Pro-Mist 1/4`), *Grade/Palette* (highlights, mids, blacks
  separately), *Lighting & Atmosphere* (named sources and negative fill), *Location & Framing*
  (foreground/midground/background named — this is rule R10), *Sound* (diegetic, with a level),
  and a shot list with timecodes **inside** the four seconds (`0.00–2.40`, `2.40–4.00`).
  Lift that template; it is the highest-value artifact in the whole guide.

## Continuity toolkit, ranked by what works

1. **`input_reference` first frame.** Strongest control. Generate the keyframe with an image
   model at exactly the output resolution, then animate it. Locks composition, set and
   palette. It is also the official mitigation for garbled text: **put type in the reference
   image, or better, never ask Sora for type at all.**
2. **Characters API** (where available) — a 2–4s reference clip, max two characters, referred
   to by name. Blocked for humans; works for objects. Make the *object* the character.
3. **Extend** — uses the full prior clip as context. Right tool for a continuous long take,
   wrong tool for coverage.
4. **Remix/edit** — nudge one variable at a time ("same shot, 85mm"). This is how you get
   coverage of one scene from several angles: lock a hero shot, then remix to 30°/60°
   variants instead of re-prompting from zero.
5. **`inpaint_items` + `frame_index`** — pseudo last-frame conditioning. Test before relying.
6. **`n_variants: 4`** — cheap takes for the selects bin.

## Failure modes and mitigations

| Failure | Mitigation |
|---|---|
| Garbled text, fake glyphs | Never generate type. Reference image or Remotion overlay. |
| Identity/wardrobe morphing across shots | Repeat descriptors verbatim, no pronouns, identical palette line; use characters/remix |
| Temporal flicker, warping | Shorter clip, one move, simpler action, cleaner background — then re-layer |
| Physics breaks, floating, bad contact | Sora has no simulator. Keep contact events out of frame, or do them in Blender |
| Lip-sync drift | Avoid on-camera dialogue entirely |
| Lighting mismatch between clips of one scene | Identical `Lighting:` and `Palette anchors:` blocks across the scene |

## Audio from Sora

Sora 2 returns synchronised audio. **Usually discard it** and rebuild the six-layer mix — but
keep it as a free foley reference for what the shot should sound like.

## Cost

Billed per second of generated video (about ten US cents per second at time of writing). A
two-minute film using generation for the atmosphere layer typically consumes 60–120 seconds
of generated material per pass. Budget for three passes and selection waste.
