# Assembly, compositing, sound and delivery

## Toolchain on this Mac

Verified present: `ffmpeg` (Homebrew), `ffmpeg-full` (keg-only, carries `libass`, `freetype`,
`drawtext`, `subtitles` — call it by absolute path), Blender 5.2 LTS headless, Node/`npx`,
Python 3, Playwright, Final Cut Pro. Not installed: DaVinci Resolve, After Effects, Motion.

**The trap:** the plain Homebrew `ffmpeg` bottle is built *without* libass and freetype, so
`subtitles`, `ass` and `drawtext` do not exist. Check before relying on them:

```bash
ffmpeg -filters | grep -cE ' (drawtext|subtitles|ass) '   # verified 0 on the plain build
FF=/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg               # verified: has all three
```

Use `$FF` for anything that burns text; plain `ffmpeg` for everything else.

Prefer Remotion for all typography anyway — `drawtext` captions look defaulted, not designed.

## Roles of each tool

- **Real capture (Playwright, screen recording, camera)** — the product. Always.
- **Sora 2** — atmosphere only (see sora-azure.md).
- **Remotion** — typography, lower thirds, device frames, UI-in-space, the end card, animated
  diagrams. Never full-screen headline cards carrying the narrative: that is the slideshow
  trap rewritten in React.
- **Blender (headless)** — 3D product and hardware shots, real camera moves with depth of
  field and true motion blur, and UI-as-object compositing.
- **ffmpeg** — conform, grade, grain, speed ramps, mix, master.

## Capturing UI so it can live in a film

```js
// Playwright: deterministic, high frame rate, reproducible
await page.emulateMedia({ reducedMotion: 'no-preference' });
await context.newPage();           // recordVideo: { size: { width: 1920, height: 1080 } }
```

Capture at **60fps**, drive scripted interactions slowly enough to read, hide the caret,
avoid browser chrome, and never let account identifiers appear on screen.

## The four mismatches that make composites look glued on

1. **Shutter / motion blur.** Screen recordings have none. Conform 60fps capture to the film
   rate with frame blending, which synthesises the missing blur:
   ```bash
   ffmpeg -i ui60.mov -vf "tmix=frames=3:weights='1 1 1',fps=24" -c:v prores_ks ui24.mov
   ```
2. **Grain.** UI is noiseless, everything else is not. Apply one grain pass to the **final
   master** so the grain sits above the seam. Usable band is 4–8; 10+ reads as a filter.
   ```bash
   ffmpeg -i in.mp4 -vf "noise=alls=6:allf=t+u,format=yuv420p" -c:v libx264 -crf 16 -preset slow -tune grain out.mp4
   ```
3. **Colour.** Push the UI through the same LUT as everything else, then reduce contrast
   slightly — a real screen seen through glass is flatter than the source signal.
   ```bash
   ffmpeg -i in.mp4 -vf "lut3d=film.cube" graded.mp4
   ```
4. **Geometry — the big one.** Shoot the UI as an object in a scene, not a flat rectangle.
   In order of quality:
   - **Blender composite (best, scriptable):** the recording becomes a movie texture on a
     device mesh; light the scene, add screen-glow as an area light, a reflection plane, a
     contact shadow, and animate a real camera with DOF and shutter 0.5 (180°).
     `blender -b scene.blend -P shot.py`
   - **ffmpeg `perspective`** corner-pin into a locked-off plate — cheap and convincing when
     the camera does not move (ffmpeg has no tracker).
   - **Remotion 3D transform** — CSS perspective with a generated reflection and shadow;
     deterministic and resolution-independent.

   In every case add a **light wrap / screen spill** onto the surrounding frame and a
   **contact shadow**. Their absence is precisely what reads as "pasted".

Speed ramps hide seams at act transitions; use optical flow only on short ramps, never on a
whole film:

```bash
ffmpeg -i in.mp4 -vf "setpts='if(lt(T,2),PTS, 2/TB + (PTS-2/TB)*2.5)',minterpolate=fps=48:mi_mode=mci:mc_mode=aobmc:vsbmc=1" out.mp4
```

Bloom and halation on speculars, used sparingly:

```bash
ffmpeg -i in.mp4 -filter_complex "[0:v]split=2[a][b];[b]gblur=sigma=18[bl];[a][bl]blend=all_mode=screen:all_opacity=0.28" out.mp4
```

**One frame rate for the whole film**, chosen up front — 24 for a film feel, 30 if the UI
demo dominates. Everything conforms to it.

## Sound — the six layers

Missing layers are why agent films sound like a screen recorder.

1. **Room tone / ambience** — continuous, never gapped, runs *under* the cuts. About −45 to
   −35 dBFS. This is what makes a J-cut work.
2. **Foley / diegetic detail** — the click, the fabric, the cup. Sells reality more than music.
3. **UI ticks** — under 80ms, pitched high, max −24 dBFS, one per real interaction and never
   per animation frame.
4. **Transitions** — risers into act changes; a sub hit (30–60Hz) on the biggest moment and
   on the end card. More than three sub hits and it is a trailer.
5. **Music** — enters late. For 120s: silence or ambient 0–12s, sparse pulse under the
   problem, a new element per proof beat, **emotional lift at 70–75% of runtime**, then decay
   under the end card.
6. **Voice** — always the top of the mix.

### Levels

- Integrated **−14 LUFS**, true peak **≤ −1 dBTP** for web and social delivery.
- Voice peaks around −12 to −10 dBFS; music ducks **6–9 dB** under voice.
- Duck without a DAW:
  ```bash
  ffmpeg -i music.wav -i vo.wav -filter_complex \
    "[0:a][1:a]sidechaincompress=threshold=0.05:ratio=8:attack=200:release=400[ducked]" -map "[ducked]" mixbed.wav
  ```
- Measure, never guess:
  ```bash
  ffmpeg -i master.mp4 -af ebur128=peak=true -f null -
  ffmpeg -i mix.wav -af loudnorm=I=-14:TP=-1:LRA=11:print_format=json -f null -   # pass 1, then re-run with measured values
  ```

### Where music may legitimately come from

- **ElevenLabs** — music, sound effects and voice on one API; commercial rights from the paid
  tiers. Best single-vendor answer for an agent.
- **Stable Audio Open** — trained on licensed data, self-hostable on this Mac, instrumental
  only; Community Licence grants output ownership under $1M revenue.
- **A composed bed** built programmatically — acceptable, and the honest fallback.
- **Avoid** Suno and Udio for anything published: unresolved litigation.
- **Azure has no music or SFX generation.** Azure covers picture (Sora 2) and voice.
- Always record the music's provenance and licence in the production notes.

## Captions

Burned in, always. With `ffmpeg-full` use **ASS**, not SRT — it carries font, size, outline,
margins and per-line styling. Better still, render captions in Remotion. Either way: brand
typeface, at most two lines, ≤42 characters per line, bottom third with a real margin (≥6% of
height), no default drop shadow, and contrast checked against the busiest frame behind them.

## Delivery gate

`scripts/delivery-gate.sh master.mp4` measures and reports pass/fail on: duration against
target, resolution and frame rate, audio presence, integrated loudness and true peak, average
shot length via scene detection, and the presence of a caption/text layer. It also writes a
contact sheet sampled **at cut points and mid-transition** — the sampling that exposes text
ghosting, which beat-centre sampling hides.

Finally, a human watches it. Rendering successfully is not done.

## Scripts in this skill

| Script | Job |
|---|---|
| `scripts/lint-shotlist.mjs <shotlist.json>` | Enforces R1-R11 and the structural checks. Run it **before** generating a single frame — it is far cheaper to fail here. |
| `scripts/sora-azure.sh shot "<prompt>" out.mp4 [size] [seconds]` | Keyless Sora 2 create/poll/download, plus `remix` for coverage. |
| `scripts/delivery-gate.sh master.mp4 [target_s]` | Measures duration, resolution, fps, loudness, true peak, silence, shot density and ASL; writes a contact sheet sampled at cut points. |

Worked example of the gate catching exactly the failure this skill exists to prevent — a
116s dissolve-driven render:

```
  1920x1080  30.00 fps  h264  116.0s
  FAIL  integrated loudness -16.0 LUFS (target -14)
  1 detected shots  ASL 116.00s  1 per 120s
  FAIL  ASL 116.00s outside 1.5-4s (slideshow or trailer)
  warn  near-zero hard cuts: either a single long take, or a dissolve-driven slideshow
  FAIL  1 shots per 120s: slideshow
```

A film assembled from cross-dissolving cards produces almost no hard cuts. The gate sees
that even when a synopsis claims "45 shots". Trust the measurement, not the plan.
