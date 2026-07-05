# Engine / Identity split — architecture design

> **Status:** proposed (design only, not implemented). Author: `@baccio`. Date: 2026-07-05.
> **Decision gate:** human gate #7 (architectural change > 4 files, cross-cutting) — Roberto decides.
> **Target release:** v2.0.0 (breaking). Supersedes the `fork-identity.sh` rename approach (v1.3.0).

## Problem restated

Roberto's identity permeates the repo: `behavior/roberto-voice.md`,
`behavior/roberto-mode.md` (name + embedded profile), `agents/roberdan-twin.md`, the
`RDA_` env prefix, the `~/.roberdan-os` home dir, and "Roberto" throughout the prose.
Today a forker runs `bin/fork-identity.sh` — a mechanical `git mv` + `sed` across ~30
live-canon files. **That is exactly what creates a perpetual merge war:** every renamed
file and every rewritten token diverges from upstream, so `git merge upstream/main`
conflicts forever.

**Goal:** a forker replaces **only identity data**, never renames an engine file, so
`git merge upstream/main` stays clean on engine files permanently.

**Framing (approved):** roberdan-os stays *Roberto's instance*, published under his name.
The repo does **not** need to look anonymous. Filenames or prose that say "roberto" are
fine **as long as forkers never edit those files** — the merge war comes from forkers
editing files that upstream also edits, not from the letters r-o-b-e-r-t-o existing on disk.

---

## Core insight

A merge conflict requires **both** sides to edit the **same path**. So the entire redesign
reduces to one rule:

> **Isolate everything a forker must change into its own set of files (`identity/`), and
> make sure no engine file contains forker-editable identity.** Then a forker edits only
> `identity/*` and engine files merge clean forever.

This means we do **not** need to rename `roberto-mode.md`, purge "Roberto" from prose, or
parametrize 33 env vars. We need to **relocate the forker-editable identity content** out
of engine files and into a single, obvious directory the forker owns.

Two guarantee tiers, stated honestly:

- **Hard guarantee — engine files never conflict.** Forkers never touch them; upstream
  owns them outright.
- **Soft guarantee — `identity/` files rarely conflict.** They are the forker's to own;
  a conflict happens only if upstream *also* edits the same identity file (rare, small,
  localized) — versus today's *guaranteed* 30-file war on every upstream pull.

---

## Decisions (a–h)

### a) Form of identity — `identity/` dir **and** `identity.conf` (both)

They serve different consumers and neither substitutes for the other:

- **`identity.conf`** — machine-readable `KEY=value` (bash-sourceable): `slug`, `full_name`,
  `primary_language`, `twin_handle`, `rda_home`. Consumed by **scripts** (sourced) and by
  `sync.sh` at **generation-time** (to inject name into wrappers). This is the only
  "config" surface — small, greppable, no YAML parser.
- **`identity/*.md`** — human-authored prose that agents read at **runtime**: `voice.md`,
  `operator.md`, `twin-persona.md`, `profile-pointer.md`. You cannot cram a voice canon
  into a `.conf`; prose stays prose.

**Tradeoff:** two surfaces instead of one is marginally more to document, but conflating
them would force either a prose-in-conf hack or a config-in-markdown parser — both worse.
Cost is low: one dir + one 5-line file.

### b) Substitution timing — **hybrid** (runtime for scripts, stable paths for agents, gen-time for wrappers)

Constraint: `hooks/`, `kb.sh`, `factory/` run **standalone**, not via a generated wrapper —
so generation-time substitution alone cannot serve them.

- **Runtime for scripts:** every script derives its home from `RDA_HOME` and, where needed,
  `source`s `identity.conf`. Standalone execution works because the values are read live.
- **Stable neutral paths for agents:** the twin reads `identity/twin-persona.md` +
  `identity/voice.md` at runtime — no substitution, the files *are* the identity.
- **Generation-time for wrappers only:** `sync.sh` reads `identity.conf` to inject
  `full_name`/`twin_handle` into the generated CLAUDE.md/copilot text, and points the
  behavior references at the new stable paths.

**Tradeoff:** no single mechanism, but any single mechanism fails one consumer (pure
gen-time breaks standalone scripts; pure runtime can't template committed wrapper prose).
The hybrid keeps each consumer served by the cheapest mechanism that works. No template
engine, no YAML parser — bash + `source` + stable paths (honours constraint 6).

### c) `roberto-mode.md` and `roberto-voice.md` — split by concern, not by rename

- **`behavior/roberto-mode.md`** is ~80% **engine** (autonomy, done-criteria, quality gate,
  loop discipline, the phrase-response protocol) wrapped around ~20% **identity** ("Who
  Roberto is", "How he communicates", the named-agent ecosystem Ali/Amy/Sofia…, tool stack,
  the Italian phrase table). **Decision:** *keep the filename* (engine brand, huge blast
  radius to rename — AGENTS.md, CLAUDE.md, copilot, the `claude-ai-skill/roberto-mode`
  package, docs, bundle). **Extract** the identity sections into `identity/operator.md` and
  replace them in `roberto-mode.md` with a one-line pointer. After this, a forker never
  edits `roberto-mode.md` → it merges clean forever, even though it keeps a "roberto" name.
- **`behavior/roberto-voice.md`** is ~100% **identity**. **Decision:** *move it* to
  `identity/voice.md`. It belongs with the other forker-owned files so the ownership
  boundary is one directory. One-time upstream rename in v2.0.0; all references
  (twin, AGENTS.md, `sync.sh`, copilot text, `make-bundle.sh`, `thinking-toolkit`
  wikilink) update once, upstream-side.

**Tradeoff:** keeping `roberto-mode.md`'s name is slightly inconsistent (one identity-bearing
name survives) but avoids a large, purely-cosmetic rename the framing doesn't require.
Moving `voice.md` costs one rename + ~6 reference updates but gives forkers a single
"edit everything here" directory — the core UX win of the whole redesign.

### d) `agents/roberdan-twin.md` — neutral engine role + forker persona

The twin is a **generic role** (digital twin: source order, degrade-clean, orchestration
table, guardrails, inherited gates) wearing a **persona** (name, IT/EN/ES, relationship style).

- **Decision:** `git mv agents/roberdan-twin.md → agents/twin.md`, frontmatter `name: twin`
  (neutral, invoked as `@twin` universally). The role prose is upstream-owned.
- The persona moves to **`identity/twin-persona.md`** (forker-owned): "you are <full_name>'s
  twin, bilingual <languages>, relationship-first" + pointers to `identity/voice.md` and the
  local dossier. `agents/twin.md` references it.

**Tradeoff — the one genuine cost:** Roberto loses the `@roberdan-twin` branded handle in
favour of `@twin`. The handle is not load-bearing (personalization lives in the persona
content), and a neutral handle is the only *zero-parametrization* way to keep the agent file
merge-clean. Alternative considered and rejected as over-engineering: generation-time handle
substitution via `identity.conf twin_handle` — but `bootstrap.sh` symlinks `agents/*.md`
raw (not through `sync.sh`), so the raw file's frontmatter would still need a static name;
templating it means routing agent install through generation too. Not worth it for a handle.
(If Roberto insists on `@roberdan-twin`, the fallback is: keep `name:` as an `identity.conf`
value and have `bootstrap.sh` install a generated twin agent instead of a raw symlink —
documented as a future option, not in v2.0.0.)

### e) `RDA_` prefix and `~/.roberdan-os` — prefix stays as fixed engine namespace; home dir gets one env var

- **`RDA_` prefix:** **do not parametrize.** 33 distinct env vars across scripts, tests, and
  three launchd plists (`com.roberdan.rda-*`), plus it is the codebase's single most greppable
  token. Renaming it guarantees merge conflicts on every script upstream later touches, for
  zero functional gain. **Declare it a fixed engine namespace** — `RDA` = "roberdan-os agents",
  documented as the engine's namespace, *not* personal identity. A forker keeps `RDA_`.
- **`~/.roberdan-os` home dir:** the one parametrization worth doing. Scripts today hardcode
  `$HOME/.roberdan-os` in ~15 default expressions (`${RDA_FACTORY:-$HOME/.roberdan-os/...}`).
  **Refactor** so every script derives from a single `RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"`.
  A forker sets `RDA_HOME=~/.jane-os` **once** (in their shell/`identity.conf`) — a *value*,
  not a file edit → merge-clean, and keeps "roberdan" out of their filesystem. **The default
  preserves today's behavior exactly**, so Roberto's machine is untouched.

**Tradeoff:** honestly, `RDA_HOME` is optional polish — a forker could tolerate an opaque
`~/.roberdan-os` engine dir. But the refactor is cheap (one derivation, ~15 default sites) and
removes the last filesystem-visible identity leak without touching the namespace. Parametrizing
the *prefix* is where the cost/benefit inverts, so we stop there.

### f) `bin/fork-identity.sh` — deprecate; replace with `bin/identity-init.sh`

`fork-identity.sh` (shipped v1.3.0) is now **counterproductive**: its `git mv` + `sed` renames
are precisely the mechanism that manufactures the merge war this redesign eliminates.

- **Decision:** **remove** `fork-identity.sh` in v2.0.0; add **`bin/identity-init.sh`** that
  scaffolds `identity.conf` from a template, drops TODO-bannered starter `identity/*.md` (or
  copies the reference instance for the forker to overwrite), and prints the "set `RDA_HOME`,
  rewrite `identity/`, write your denylist" checklist. It **renames no engine file**.
- Honest CHANGELOG note: fork-identity.sh lived exactly one minor version; deprecating it
  immediately is the right call precisely *because* the rename model was wrong, not because it
  was buggy.

### g) "Roberto" in prose — move only embedded *data*, keep the *byline*

Per the framing, most mentions are legitimate — this is Roberto's published instance.

- **Move (identity data):** the profile block inside `roberto-mode.md` (who he is, ecosystem
  agents, tool stack, email, the Italian phrase table) → `identity/operator.md`. Forkers
  override this file.
- **Keep (legitimate instance byline):** AGENTS.md header ("Roberto D'Angelo's agentic
  behavior"), human gates ("Roberto decides"), README/START-HERE framing, the paper,
  `docs/archive/`, CHANGELOG history. These are the published instance's signature; forkers
  don't need them gone and never edit them, so they never conflict.
- **Rewrite (forker-facing docs):** `docs/QUICKSTART-for-forkers.md` and the README fork
  section — describe the new `identity/` workflow instead of the rename dance.

### h) Eval fixtures (`eval/tasks/*.md`) — engine, kept as instance fixtures

The eval **harness** is engine; the fixtures' identity-flavoured content (Roberto/MirrorBuddy)
is **instance test data**. Renaming mid-fixture changes *what is measured*, not just cosmetics
(the old script already correctly excluded them). **Decision:** fixtures stay as Roberto's
instance fixtures; a forker who wants their own rewrites the task prose by hand (documented,
not scripted). They never block merges — upstream owns them, forkers rarely touch them.

---

## Final repo structure

```
roberdan-os/
├── AGENTS.md                      # entry point — UNCHANGED role; refs updated (voice path, twin name)
├── identity/                      # NEW — the ONLY forker-editable surface
│   ├── README.md                  #   "everything you change lives here, nothing else"
│   ├── identity.conf              #   slug, full_name, primary_language, twin_handle, rda_home
│   ├── voice.md                   #   ← moved from behavior/roberto-voice.md (pure identity)
│   ├── operator.md                #   ← extracted profile from behavior/roberto-mode.md
│   ├── twin-persona.md            #   ← persona half of the twin
│   └── profile-pointer.md         #   documents where the local-only dossier lives
├── behavior/
│   ├── roberto-mode.md            #   KEPT name — now pure engine + pointer to identity/operator.md
│   └── thinking-toolkit.md        #   wikilink [[roberto-voice]] → [[voice]] (cosmetic)
├── agents/
│   ├── twin.md                    #   ← renamed from roberdan-twin.md; name: twin; refs identity/
│   ├── baccio.md · rex.md · luca.md · thor.md · socrates.md · board.md · wanda.md   # unchanged
├── rules/ · loop/ · skills/ · learn/ · evolve/ · ontology/ · memory/ · handoff/   # unchanged
├── hooks/                         #   derive RDA_HOME (default preserves ~/.roberdan-os)
├── factory/ · kanban/            #   derive RDA_HOME; plists UNCHANGED (point at run.sh)
├── bin/
│   ├── identity-init.sh           #   NEW — scaffolds identity/, renames NOTHING
│   ├── fork-identity.sh           #   REMOVED (v2.0.0)
│   ├── sync.sh · bootstrap.sh · make-bundle.sh   # refs updated to identity/ paths + RDA_HOME
│   └── …
├── test/
│   ├── validate.sh                #   unchanged gate; + new fork-merge acceptance test wired in
│   ├── test-fork-merge.sh         #   NEW — the merge-clean proof (see acceptance)
│   └── …
├── eval/                          #   fixtures unchanged (instance test data)
├── docs/
│   ├── QUICKSTART-for-forkers.md  #   rewritten for identity/ workflow
│   └── plan-2026-07-05-engine-identity-split.md   # this doc
└── private/ · claude-ai-skill/    # unchanged (dossier local-only; packaged skill as-is)
```

---

## Implementation phases (each leaves `validate.sh` GREEN)

| Phase | What | Files touched (est.) | Green because |
|---|---|---|---|
| **0 — scaffold + RDA_HOME** | Create `identity/` (README, `identity.conf` = today's values, empty prose stubs pointing back to current files). Refactor all scripts to derive `RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"`. No content moved yet. | ~8 (identity/ new; hooks/*.sh, factory/*.sh, learn/*.sh, ontology/curate.sh, kanban/kb.sh, evolve/watch.sh) | Default = today's paths; nothing references the stubs yet; shellcheck clean |
| **1 — move voice** | `git mv behavior/roberto-voice.md → identity/voice.md`. Update refs: `agents/roberdan-twin.md`, AGENTS.md, `sync.sh` (CLAUDE.md + copilot text), `make-bundle.sh`, `thinking-toolkit.md` wikilink, docs. | ~10 | Link-check + drift stay green (all refs repointed atomically) |
| **2 — extract operator profile** | Create `identity/operator.md` with the profile sections cut from `roberto-mode.md`; replace them in `roberto-mode.md` with a pointer. | ~3 (roberto-mode.md, identity/operator.md, AGENTS.md behavior note) | roberto-mode.md still valid markdown; no broken links |
| **3 — split twin** | `git mv agents/roberdan-twin.md → agents/twin.md`; `name: twin`; move persona → `identity/twin-persona.md`; twin.md refs identity/. Update AGENTS.md agent table, `~/.claude/CLAUDE.md` global block wording, `bootstrap.sh` (prune stale `roberdan-twin` symlink). | ~6 | Frontmatter lint passes (twin.md keeps all 7 fields); sync wrapper regenerates from `name:` automatically; drift green |
| **4 — fork tooling + docs** | Remove `fork-identity.sh`; add `bin/identity-init.sh`; rewrite `QUICKSTART-for-forkers.md` + README fork section + START-HERE. | ~5 | shellcheck clean on new script; links resolve |
| **5 — CHANGELOG + acceptance test + migration** | CHANGELOG v2.0.0; add `test/test-fork-merge.sh` and wire into `validate.sh`; finalize `bootstrap.sh` migration cleanup. | ~4 | New test passes; validate.sh green end-to-end |

**Total blast radius:** ~30–35 files across 6 committable phases. Each phase is a single
conventional commit that leaves `bash test/validate.sh` = `✅ ALL GREEN`.

---

## Migration plan — Roberto's machine

Nothing breaks by default because `RDA_HOME` defaults to `~/.roberdan-os` and the `RDA_`
namespace and plist labels are unchanged.

1. `git pull` v2.0.0.
2. Re-run **`bin/bootstrap.sh`** — re-emits wrappers, re-symlinks `agents/*.md` (now installs
   `twin.md`), and **prunes the stale `~/.claude/agents/roberdan-twin.md` symlink** (added to
   bootstrap in Phase 5).
3. **Leave `RDA_HOME` unset** → resolves to `~/.roberdan-os`; existing `factory/`, `private/`,
   queue state untouched.
4. **Verify:**
   - `bash test/validate.sh` → `✅ ALL GREEN`.
   - `@twin` resolves: `readlink ~/.claude/agents/twin.md` → repo `agents/twin.md`; old
     `roberdan-twin.md` symlink gone.
   - launchd unchanged: `com.roberdan.rda-{factory,learn,evolve}` still point at their `.sh`
     (paths unchanged); factory queue still `~/.roberdan-os/factory`.
   - `hooks/context-inject.sh` still injects the board (no path change).
   - leak-check green (voice content is byte-identical, only its path moved; denylist unaffected).
5. No settings.json edit needed (hook paths unchanged). No plist reload needed.

The `claude-ai-skill/roberto-mode/` package stays as-is (a published, named artifact; its
internal VOICE.md copy is out of split scope) — noted in CHANGELOG.

---

## Acceptance tests for `@thor`

1. **Repo green (post-migration):** on Roberto's clone at v2.0.0, `bash test/validate.sh` →
   `✅ ALL GREEN` (all 10 sections: frontmatter, links, drift, shellcheck, leak-check,
   factory+kb, kb-views, leak self-test, sync-install, tool-coverage).

2. **Determinism intact:** `bin/sync.sh --emit-only` into two temp dirs is byte-identical
   (drift section) after the `identity.conf` gen-time injection is added — i.e. injection is
   deterministic (no timestamps, stable read of the conf).

3. **Fork test (identity-only, no engine rename)** — on a scratch clone:
   ```
   bin/identity-init.sh --slug jane --name "Jane Doe"
   # edit identity/voice.md, identity/operator.md, identity/twin-persona.md → fictional Jane
   # set RDA_HOME=~/.jane-os in identity.conf
   git status --porcelain
   ```
   **Assert:**
   - Only `identity/*` and `identity.conf` appear as modified/added.
   - **No engine file renamed:** `agents/twin.md` present (not `agents/jane-twin.md`);
     `behavior/roberto-mode.md` unmodified; no `RDA_`→`JANE_` rewrite anywhere.
   - `bash test/validate.sh` → green (frontmatter lint on `agents/twin.md` still passes;
     leak-check tier-3 no-op or Jane's own denylist).

4. **Merge-clean proof (`test/test-fork-merge.sh`)** — the test that justifies the whole redesign:
   ```
   # scratch clone = "jane fork" with identity/ rewritten (test 3 state, committed)
   # simulate upstream: on a second branch, commit edits to ENGINE files —
   #   append a line to behavior/roberto-mode.md, agents/twin.md, and hooks/bash-guard.sh
   git merge upstream/main
   ```
   **Assert:** merge completes with **ZERO conflicts** — because jane touched only `identity/`
   and upstream touched only engine files. Contrast baseline (documented in the test): the same
   scenario under v1.3.0's `fork-identity.sh` conflicts on every renamed/rewritten file.

5. **Soft-guarantee honesty check:** the test also documents (not asserts) that if upstream
   edits an `identity/*` file the forker also edited, that single file conflicts — a small,
   localized, expected conflict, versus the pervasive war it replaces.

---

## CHANGELOG — v2.0.0 (honest breaking changes)

```markdown
## [v2.0.0] - 2026-07-05

### Changed (BREAKING)
- **Engine / identity split.** All forker-editable identity now lives in one place:
  `identity/` (voice, operator profile, twin persona, `identity.conf`). Engine files no
  longer embed identity, so `git merge upstream/main` stays conflict-free on engine files
  forever. See docs/plan-2026-07-05-engine-identity-split.md.
- **`behavior/roberto-voice.md` → `identity/voice.md`** (moved). Update any local reference.
- **`agents/roberdan-twin.md` → `agents/twin.md`**, invoked as **`@twin`** (was
  `@roberdan-twin`). The persona moved to `identity/twin-persona.md`.
- **`behavior/roberto-mode.md`** keeps its name but is now pure engine discipline; the
  operator profile moved to `identity/operator.md`.
- **`RDA_HOME`** env var introduced (default `~/.roberdan-os`) — set it once to relocate the
  runtime home. The `RDA_` prefix is now documented as a **fixed engine namespace**, not
  identity, and is intentionally not parametrized.

### Removed
- **`bin/fork-identity.sh`** (shipped v1.3.0) — its `git mv`+`sed` rename model is exactly
  what caused perpetual merge conflicts. Replaced by `bin/identity-init.sh`, which scaffolds
  `identity/` and renames no engine file.

### Migration
- Run `bin/bootstrap.sh` (re-symlinks agents incl. `twin.md`, prunes the stale
  `roberdan-twin` symlink). `RDA_HOME` defaults to today's path, so existing factory/dossier
  state is untouched. Full steps: docs/plan-2026-07-05-engine-identity-split.md § Migration.

### Note
- `claude-ai-skill/roberto-mode/` (packaged skill) is unchanged — a published named artifact,
  out of split scope.
```
