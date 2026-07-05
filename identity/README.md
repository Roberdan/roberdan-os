# identity/ — the ONLY forker-editable surface

> **Everything you change lives here, nothing else.** Engine files (behavior/, agents/,
> hooks/, bin/, factory/, …) are upstream-owned: never edit them in a fork, and
> `git merge upstream/main` stays conflict-free on them forever. See
> [`docs/plan-2026-07-05-engine-identity-split.md`](../docs/plan-2026-07-05-engine-identity-split.md)
> for the full design.

| File | What it holds | Consumed by |
|---|---|---|
| [`identity.conf`](identity.conf) | machine-readable `KEY=value` (slug, full_name, primary_language, twin_handle, rda_home) | scripts (`source`) and `bin/sync.sh` at generation time |
| [`voice.md`](voice.md) | the voice canon — how the operator writes and decides | the twin agent, at runtime |
| [`operator.md`](operator.md) | who the operator is: profile, named-agent ecosystem, tool stack, phrase table | `behavior/roberto-mode.md` (pointer), agents at runtime |
| [`twin-persona.md`](twin-persona.md) | the persona half of the twin agent (name, languages, relationship style) | `agents/twin.md`, at runtime |
| [`profile-pointer.md`](profile-pointer.md) | where the local-only confidential dossier lives (never in git) | the twin agent, at runtime |

## Ownership contract (the merge-clean guarantee)

- **Hard guarantee — engine files never conflict.** Forkers never touch them; upstream
  owns them outright.
- **Soft guarantee — `identity/` files rarely conflict.** They are the forker's to own;
  a conflict happens only if upstream *also* edits the same identity file (rare, small,
  localized).

Forking? Run `bin/identity-init.sh --slug <you>` and read
[`docs/QUICKSTART-for-forkers.md`](../docs/QUICKSTART-for-forkers.md).

## Note on `RDA_`

The `RDA_` env-var prefix is the engine's **fixed namespace** ("roberdan-os agents"), not
personal identity — it is intentionally not parametrized. The one relocatable value is
**`RDA_HOME`** (default `~/.roberdan-os`): set it once in your shell to move the runtime
home (factory queue, learnings inbox, private dossier) without editing any engine file.
