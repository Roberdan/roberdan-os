# Quickstart for forkers

You've cloned `roberdan-os` and want to run it as *your own* system, not Roberto's. Since
v2.0.0 this no longer means renaming anything: **everything you change lives in one
directory, `identity/`** — engine files stay upstream-owned, so `git merge upstream/main`
stays conflict-free on them forever. Five steps, ~15 minutes.

## 1. Clone and wire the remotes

```
git clone https://github.com/Roberdan/roberdan-os.git my-os
cd my-os
git remote rename origin upstream
# create your own GitHub repo first, then:
git remote add origin https://github.com/<you>/my-os.git
```

Keeping `upstream` is the point of the v2.0.0 design: you'll pull engine improvements
from it forever, without merge wars.

## 2. Bootstrap

```
bin/bootstrap.sh
```

Idempotent, non-destructive — generates the per-tool wrappers, symlinks the agents into
`~/.claude/agents/`, runs `test/validate.sh`. Never overwrites `~/.claude/CLAUDE.md` or
`settings.json`; it prints the pointer blocks to add by hand.

## 3. Initialize your identity — the automated part

```
bin/identity-init.sh --slug jane --name "Jane Doe"          # dry run first — prints the plan, writes nothing
bin/identity-init.sh --slug jane --name "Jane Doe" --apply  # then actually do it
```

This rewrites `identity/identity.conf` with your slug/name/home and stamps a
`FORK TODO` banner on each `identity/*.md` prose file (voice, operator profile, twin
persona, profile pointer) — the reference content is kept so you can see the shape,
but it's still Roberto's words until you rewrite it. **It renames no engine file** —
that's not an omission, it's the design: a rename is exactly what would make every
future `git merge upstream/main` conflict. (Its predecessor, `fork-identity.sh`, did
mass renames and was removed in v2.0.0 for precisely that reason.)

Two things are engine namespace, **not** your identity — leave them alone:
- the `RDA_` env-var prefix (fixed engine namespace, "roberdan-os agents");
- filenames like `behavior/roberto-mode.md` (engine brand; you never edit that file,
  so it never conflicts).

The one relocatable value is the runtime home: `export RDA_HOME=~/.jane-os` in your
shell (default `~/.roberdan-os`) — a value, not a file edit.

## 4. Write your own voice and privacy files

- Rewrite `identity/voice.md`, `identity/operator.md`, `identity/twin-persona.md` in
  your own words — the banners mark what's still the upstream operator's.
- Write your own `private/.denylist` and `~/.jane-os/private/<your-profile>.md`
  (confidential dossier, read at runtime by the `twin` agent — see
  `identity/profile-pointer.md`). Roberto's denylist is meaningless to you; yours
  doesn't exist yet. See `README.md § Privacy` and `test/leak-check.sh`.
- Run `bin/update-denylist-hashes.sh` before your first commit so CI can leak-check
  without ever holding your confidential terms in plaintext.

The eval fixtures (`eval/tasks/*.md`) keep Roberto-flavoured task prose — they're
instance test data, and rewriting them changes *what is measured*. Rewrite them by hand
only if you care about running the eval against your own canon.
`claude-ai-skill/roberto-mode/` is a packaged, named artifact — repackage your own if
you want to ship one.

## 5. Verify — including the merge-clean guarantee

```
bash test/validate.sh          # → ✅ ALL GREEN (same gate the real repo runs)
git status --porcelain         # → only identity/* should appear
bash test/test-fork-merge.sh   # → proof: identity-only edits merge clean with upstream engine edits
```

From now on, `git merge upstream/main` is routine: upstream edits engine files you never
touched (hard guarantee: zero conflicts there); a conflict can only happen if upstream
also edits an `identity/*` file you rewrote — rare, small, and localized (soft
guarantee), versus the old guaranteed 30-file war.

That's it — you now have your own behavioral canon that stays mergeable with upstream.
