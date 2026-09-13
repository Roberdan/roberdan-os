# Capturing product UI that can carry a film

Written after a hackathon film failed three times. Every failure traced back to the same
place: **the footage was too small, wrongly framed, or of the wrong thing** — and each time
the symptom looked like a directing problem. It was not. A film cut from thumbnails can only
be a slideshow, because a small source leaves no room to push in, crop, or go full-bleed.

**The rule: acquire product footage at twice your delivery resolution, or do not start.**
For a 1920x1080 master that means 2560x1440 minimum, 2560x1600 comfortable.

## The four traps, in the order they bite

### 1. The narrow-column trap

Setting a huge browser viewport (2560x1440) to get a big picture is the obvious move and it
is wrong. Nearly every marketing site constrains its content to a max width, so a 2560 CSS
viewport renders a thin column of content stranded in a sea of empty background. The capture
is technically high-resolution and cinematically worthless.

**Fix:** keep the CSS viewport at a real laptop size — `1280x800` — and get the pixels from
`deviceScaleFactor: 2`. The layout is then the layout a human sees, and the image is 2560x1600.

```js
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  deviceScaleFactor: 2,          // -> 2560x1600 real pixels
  locale: 'en-GB',
});
```

### 2. The half-resolution trap

**Playwright `recordVideo` and CDP `Page.startScreencast` both ignore `deviceScaleFactor`.**
They return viewport-sized frames — 1280x800 — no matter what you set, and `maxWidth` /
`maxHeight` on the screencast will not upscale them. You discover this only if you run
`ffprobe` on a frame, which is why that check is mandatory below.

**Fix:** do not record video at all. `page.screenshot()` *does* honour `deviceScaleFactor`.

### 3. The dropped-frame trap

Real-time recording gives you whatever frame rate the machine managed, with stutters exactly
where the browser was busy — i.e. during the animation you wanted.

**Fix: deterministic stepping.** Drive the scroll yourself in fixed increments and take one
screenshot per increment. Motion smoothness becomes arithmetic instead of luck, and you choose
the frame rate afterwards by how you assemble the sequence.

Ease the movement or it reads as a machine:

```js
const ease = (t) => t * t * (3 - 2 * t);          // smoothstep, no hard start/stop
for (let i = 0; i < frames; i++) {
  const y = y0 + (y1 - y0) * ease(i / (frames - 1));
  await page.evaluate((v) => window.scrollTo(0, v), y);
  await page.screenshot({ path: `${dir}${String(i).padStart(5,'0')}.png`, animations: 'allow' });
}
```

Then `ffmpeg -framerate 48 -i %05d.png` and the shot is exactly `frames / 48` seconds long.

### 4. The wrong-section trap

Scrolling to a heading by text match fails silently and often: headings get split across
elements, lazy sections have not mounted yet, and `scrollIntoView` lands somewhere unhelpful.
The capture completes, reports success, and contains the wrong part of the page. Two of seven
scenes were wrong this way and nobody noticed until a red team asked.

**Fix: measure the page once, then use numbers, not text.**

```js
// mount every lazy section first
await page.evaluate(async () => {
  const h = document.body.scrollHeight;
  for (let y = 0; y < h; y += 500) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 70)); }
});
// then read the real offsets
const map = await page.evaluate(() => [...document.querySelectorAll('h1,h2')]
  .map(e => ({ y: Math.round(e.getBoundingClientRect().top + window.scrollY), t: e.innerText.trim() })));
```

Hard-code the resulting Y values in the shot table. They are stable for the life of the cut,
they are reviewable, and a section that does not exist on the page shows up as a missing row
instead of a silent timeout.

## Hygiene that saves a grade

```js
await page.addStyleTag({ content: `
  *{caret-color:transparent!important}                 /* no blinking cursor */
  ::-webkit-scrollbar{display:none}                    /* no OS furniture */
  [class*="cookie"],[class*="Cookie"],[id*="cookie"]{display:none!important}
`});
```

- Pause ~1.4s after landing before the first frame: let fonts, images and autoplaying video settle.
- Set `locale` explicitly. A film that must be in English will otherwise be captured in whatever
  the machine prefers, and you will not notice until someone else does.
- Discard loading states. A spinner in a hero shot reads as a broken product.

## Mandatory verification — three checks, no exceptions

Capture scripts report success while producing unusable files. Never trust the log.

1. **Resolution, from the file:**
   `ffprobe -v error -show_entries stream=width,height -of default=nw=1 shot/00050.png`
   If it is not at least 2x your delivery height, stop and fix the pipeline.
2. **Content, with your own eyes:** build one contact sheet per scene and look at it.
   ```sh
   ffmpeg -i in.mp4 -vf "select='not(mod(n,40))',scale=480:-1,tile=4x1" -frames:v 1 sheet.jpg
   ```
   You are checking: right section, readable text, right language, no empty margins, no spinner.
3. **Legibility at delivery size.** Text that is comfortable in a 2560px still can be mush at
   1080p. If body copy is unreadable, the shot is a detail shot — crop into it, do not show the page.

## Filming a logged-in product

Public marketing pages prove nothing about the product. A demo film needs the real thing:
the actual interaction, in the actual interface. Use the project's own test account, and treat
the session as production traffic — it costs real usage and leaves real data.

Confirm with the owner before first use, then: log in, dismiss onboarding, and capture the
*interaction* — a question being asked, an answer arriving, a control being changed — never a
static dashboard. One genuine interaction outranks ten pages of well-lit marketing site.
