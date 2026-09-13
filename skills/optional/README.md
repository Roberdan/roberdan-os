# Optional skills

This catalog is deliberately separate from always-installed canonical skills.
`bin/sync.sh` discovers lowercase `skill.md`; these self-contained packages use
uppercase `SKILL.md` and are **not** emitted or installed by general sync.
No optional skill is added to `AGENTS.md` or an always-on routing rule.

| Name | Purpose | Status |
|---|---|---|
| [instagram-reel-preview](instagram-reel-preview/SKILL.md) | Local 1080x1920 covers and post-style wrappers | Opt-in |

This skill defaults to the explicitly approved `fightthestroke` publisher and
actual FTS logo; see its [branding provenance](instagram-reel-preview/BRANDING.md).
Other publishers require an explicit override. No logo binary ships in the package.

From the repository root:

```bash
python3 bin/optional-skills.py list
python3 bin/optional-skills.py validate
python3 bin/optional-skills.py build instagram-reel-preview --target /path/to/bundles
python3 bin/optional-skills.py install instagram-reel-preview --target "$HOME/.copilot/skills"
```

`build` creates one portable folder (instructions, renderer and explicit catalog
files only). `install` makes the same self-contained copy and additionally refuses
another declared skill with that name. It does not need the worktree at runtime,
change host settings, install Python dependencies, or touch any other skill.
Use `~/.claude/skills` or another host's supported skills directory as the target
when appropriate. Restart/reload the host's skill discovery after installation.
Existing destinations are refused, including symlinks: review an installed version
before explicitly moving it aside; this tool never overwrites or deletes it.
Failed I/O can leave an incomplete destination; inspect it before retrying.

To add an optional skill, keep all runtime files beside `SKILL.md`, register every
shipped file in `catalog.json`, and validate/build into a disposable directory.
Do not register private fixtures, fonts, media, outputs, or Python caches.

Focused checks (no broad sync or live installation):

```bash
bash test/test-optional-skills.sh
python3 -m unittest discover -s test -p 'test_instagram_reel_preview*.py' -v
```

Use Python 3.10 or newer. Renderer tests need the skill's declared Pillow dependency, ffmpeg on PATH and a
local TrueType/OpenType font (`REEL_PREVIEW_TEST_FONT` overrides discovery). Missing
prerequisites fail with an actionable message, not a success-shaped skip.
