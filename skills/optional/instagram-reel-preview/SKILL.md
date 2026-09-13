---
name: instagram-reel-preview
description: Create local Instagram Reel preview covers or Instagram-inspired post frames from real video frames or an approved cover. Use for cover images, thumbnails, side-by-side previews, or requests to surround a cover with a typical post window. Optional image-only workflow; no upload or publishing.
---

# Instagram Reel preview

Create one **1080x1920 RGB JPEG** per preview, using the local `render.py` beside
this file. This is an image workflow, not a video edit or an official Instagram
embed. Do not change source videos, approved covers, or another task's scripts.
No account, online service, API key, transcription model download or upload is
needed by the renderer.

**Default publisher: `fightthestroke`, always with the actual approved FTS logo.**
Only an explicit request for another publisher permits an override. Subject names
are subjects, never account owners. Read [BRANDING.md](BRANDING.md) for the approved
source URL, pinned hash and safe local cache/download. Supply `--publisher-logo`;
missing or mismatched FTS artwork fails rather than drawing initials or a substitute.
Keep the logo whole and proportional: no redraw, recoloring, stretching or clipping.

## Evidence before copy

1. Establish the actual local source, intended audience, display name, output
   directory and locale. Do not infer claims, identity or project branding from
   filenames. Publisher defaults to FTS; project labels remain optional and supplied.
2. Extract a local contact sheet at useful timestamps and **inspect it visually**.
   Choose an expressive real frame: eyes open, face in focus, sane headroom,
   no accidental gesture or obscured features. Inspect the selected frame at full
   size. If the default crop cuts the face, adjust `focus_x`/`focus_y` or use
   `photo_fit: contain` (full frame above the text).
3. **Read the actual transcript before writing copy.** Use an existing transcript
   or an already-installed local transcription engine/model. Inspect the engine's
   help and run it locally; verify names and uncertain phrases against the audio.
   No engine available: request a supplied transcript or approved copy rather than
   guessing. Never upload private media without explicit destination-specific
   authorization. Never automatically download a speech model.
4. Write 1-3 short editorial headline lines plus a supporting detail grounded in
   that transcript. Make a genuine curiosity hook, not a literal quotation or
   invented outcome. No fake followers, engagement, endorsements, verification
   badge, pity, medical sensationalism, or disability-as-inspiration framing.
   Preserve the person's agency. Keep timecoded support for each factual claim
   in the task's local evidence, **outside git**.
5. Choose/infer the language from the current task, not a prior session. English
   is the renderer's default only. Translate **all** authored text consistently:
   headline, support, CTA, Reels label and any descriptive project label. Preserve
   supplied proper names. For non-English video covers, pass `cta` and
   `reels_label` explicitly; the renderer does not translate or fact-check copy.
   For an existing cover, check its language first; the wrapper cannot translate
   the text baked into it.

Local contact-sheet example (choose a new destination; `-n` refuses overwrite):

```bash
ffmpeg -hide_banner -loglevel error -nostdin -n -protocol_whitelist file,pipe \
  -i "/path/to/source.mp4" \
  -vf "fps=1/5,scale=216:-1,tile=5x4" -frames:v 1 \
  "/path/to/output/contact-sheet.png"
```

This shows the first 20 sampled frames, not necessarily the entire video.
For longer footage, inspect further intervals with `-ss` before `-i`; record the
absolute chosen timestamp. The renderer is not a substitute for this inspection.

## Render locally

Resolve `SKILL_DIR` to the directory containing **this** `SKILL.md` (not the
working directory). Use Python 3.10+; check it with `python3 -c "import PIL"`,
and `ffmpeg -version`. Only if Pillow is missing, install the adjacent
`requirements.txt` into an explicitly chosen environment. No blind installs.
Supply a readable TTF/OTF font with the selected language's glyphs; optionally
supply a separate body font. No proprietary fonts or media ship with the skill.

```bash
python3 "$SKILL_DIR/render.py" \
  --video "/path/to/source.mp4" --timestamp 12.5 \
  --title-line "A SMALL CHANGE." --title-line "WHAT HAPPENS NEXT?" \
  --subtitle "A transcript-supported detail." --display-name "Supplied name" \
  --publisher-logo "/path/to/local/cache/approved-fts-logo.png" \
  --font "/path/to/headline.ttf" --sans-font "/path/to/body.ttf" \
  --output-dir "/path/to/user/output" --output-name preview-new.jpg
```

The example copy is illustrative, not a factual claim to reuse. For repeatable
work, copy `example.json` to a **local, non-versioned** location, replace its
placeholders and run `python3 "$SKILL_DIR/render.py" --config /path/to/job.json`.
CLI options override config values; repeated `--title-line` replaces the full
list. Paths in JSON are relative to the JSON file, CLI paths to the current
directory. `--revise` is CLI-only and requires the user's explicit revision
request. Do not use it just to clear a filename collision.

### Two styles

| Style | Result |
|---|---|
| `reel-cover` (default) | Real frame, dark legibility gradient, short headline/support, name badge, Reels icon, CTA; thick orange/pink/purple gradient border and white outer space |
| `instagram-post` | The entire cover proportionally reduced between the approved-logo/publisher header with ellipsis and heart/comment/share/bookmark outlines below; no crop, overlap, invented handle, verification badge or engagement counts |

Cover margins are **48 px left/right, 85 px top, 86 px bottom** at 1080x1920.
The bordered card is 984x1749, so two full-size covers placed side by side have
96 px of white separation. Keep this spacing in a contact sheet; do not crop it
away to make a collage. JPEG edge compression can slightly tint the pixels
immediately beside the border.

For `instagram-post`, use the video options above with
`--style instagram-post`, or wrap an approved cover directly:

```bash
python3 "$SKILL_DIR/render.py" --style instagram-post \
  --cover-input "/path/to/approved-cover.jpg" --display-name "Supplied name" \
  --publisher-logo "/path/to/local/cache/approved-fts-logo.png" \
  --font "/path/to/body.ttf" --output-dir "/path/to/user/output" \
  --output-name preview-post.jpg
```

Optional `--project-label "Supplied label"` adds supplied text next to the subject,
not a replacement account. The header publisher remains `fightthestroke`.
Only an explicitly requested different `--publisher` permits other branding or an
optional `--avatar`; a neutral silhouette is never allowed in the default FTS preset.
Do not supply headline/subtitle/timestamp with an existing cover. Every pixel of
the input cover is represented through scaling into a 984x1480 maximum area,
not cropped. Smaller text will therefore become smaller; inspect at phone size.
This decorative framing is **Instagram-inspired**, not a captured post or
official embed. Do not describe the controls as functional.

### Configuration

`--help` lists all flags; JSON uses underscore names. Required video keys:
`video`, `timestamp` (seconds), `title_lines`, `subtitle`, `display_name`, `font`,
`output_dir`, `output_name`, plus `publisher_logo` for the FTS default. Wrapper input replaces video/copy keys with
`cover_input`. Common optional keys: `style`, `sans_font` (same font when absent),
`locale` (`en`), `cta` (`WATCH THE VIDEO`), `reels_label` (`REELS`),
`project_label`, `publisher` (defaults to `fightthestroke`; explicit override only),
`publisher_logo` (approved local original), `avatar` (non-FTS post only), `photo_fit` (`cover` or `contain`),
`focus_x`, `focus_y` (0..1 crop centering; defaults 0.5).

Text shrinks only within readable limits, then fails with **Text overflow**.
Shorten the copy or choose a fitting font; do not remove bounds checks, truncate
silently, or claim multilingual glyph coverage without inspecting the output.

## Delivery and safety

Keep outputs in the explicit user-selected folder (normally beside their media,
never in this skill's source). Filenames are safe `.jpg` basenames. Each output
has a `.jpg.json` provenance sidecar containing input/logo SHA-256 hashes, publisher,
subject, approved FTS source URL when applicable, timestamp,
drawn text/bounds and scaling geometry. Inputs are read-only and rehashed before
publication. Hashes prove identity, not editorial accuracy.

Existing files are refused by default. Explicit `--revise` accepts only an
unchanged generated JPEG with its matching generator/hash sidecar. Originals,
symlinks and hard links to inputs are refused. Never remove a user's original.
Keep the sidecar for revision; it contains local paths/copy and is private task
data. A process interruption can leave a lock or mismatched JPEG/sidecar pair:
report it and use a new output name, do not bypass the provenance check. Pair
publication is not a filesystem transaction.

Open both full-size and phone-size outputs. Inspect faces, all glyphs/copy,
whitespace, gradient border, safe text bounds and the wrapper's uncropped photo
and CTA. Verify the JPEG is 1080x1920 RGB and the original hashes are unchanged.
Report exact output paths and whether visual inspection happened. Do not claim
publishing, Instagram UI accuracy, or human approval from a local render.
