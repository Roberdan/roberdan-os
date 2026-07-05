# Quickstart for forkers

You've cloned `roberdan-os` and want to run it as *your own* system, not Roberto's. This is the
fast path: five steps, ~15-20 minutes, most of it automated.

## 1. Clone and rename

```
git clone https://github.com/Roberdan/roberdan-os.git my-os
cd my-os
git remote remove origin
# create your own GitHub repo first, then:
git remote add origin https://github.com/<you>/my-os.git
```

## 2. Bootstrap

```
bin/bootstrap.sh
```

Idempotent, non-destructive — generates the per-tool wrappers, symlinks the agents into
`~/.claude/agents/`, runs `test/validate.sh`. Never overwrites `~/.claude/CLAUDE.md` or
`settings.json`; it prints the pointer blocks to add by hand.

## 3. Rename the identity — the automated part

Roberto's identity runs through more than one file: the `roberdan-twin` agent, the `RDA_` env
var prefix, the `~/.roberdan-os` home directory, `behavior/roberto-voice.md`. Doing this by hand
file-by-file is exactly the kind of job a script should do instead:

```
bin/fork-identity.sh --slug jane --name "Jane Doe"        # dry run first — prints the plan, writes nothing
bin/fork-identity.sh --slug jane --name "Jane Doe" --apply # then actually do it
```

This renames `agents/roberdan-twin.md` → `agents/jane-twin.md`, `behavior/roberto-voice.md` →
`behavior/jane-voice.md`, swaps every `RDA_` env var for `JANE_`, and every `~/.roberdan-os` path
for `~/.jane-os` — across the live canon (`behavior/`, `rules/`, `agents/`, `skills/`, `hooks/`,
`bin/`, `factory/`, `learn/`, `evolve/`, `ontology/`, `kanban/`, `memory/`, `loop/`, `test/`,
functional `eval/*.sh`, plus `AGENTS.md`/`README.md`/`START-HERE.md`/`docs/USAGE.md`/`docs/adr/`).

It deliberately leaves three things untouched — mechanical rename would corrupt them, they need
your judgment instead:
- `docs/archive/`, dated `docs/plan-*.md`/`docs/report-*.md`, `docs/roberdan-os-paper-en.md` —
  Roberto's own dated history. Most forks just delete these rather than rename them.
- `eval/tasks/*.md`, `eval/README.md` — fixture prose, not identity; renaming mid-fixture would
  change what the eval is measuring, not just its cosmetics.
- `claude-ai-skill/roberto-mode/` — a packaged, named skill (directory + `.zip` build artifact).
  Rename and repackage it yourself if you want to ship your own version.

The script refuses `--apply` if your `origin` remote still points at `Roberdan/roberdan-os` (a
rail so it can't be run by accident against the real repo) — pass `--force` only if you're
certain, which you won't be, because you should be running this against *your* fork.

## 4. Write your own voice and privacy files

- Rewrite `behavior/<slug>-voice.md` in your own voice — the script copies Roberto's verbatim
  and adds a banner marking it as a placeholder, but it's still his words until you change them.
- Write your own `private/.denylist` and `~/.<slug>-os/private/profile.md` (confidential dossier,
  read at runtime by the twin agent). Roberto's denylist is meaningless to you; yours doesn't
  exist yet. See `README.md § Privacy` and `test/leak-check.sh` for the mechanism.
- Run `bin/update-denylist-hashes.sh` before your first commit so CI can leak-check without ever
  holding your confidential terms in plaintext.

## 5. Verify

```
bash test/validate.sh
```

Should come back `✅ ALL GREEN` (frontmatter, links, drift, shellcheck, leak-check, kb/factory
gates, eval harness, tool-coverage) — this is the same gate the real repo runs before every
commit. If it isn't green, something in step 3 or 4 needs another pass before you rely on it.

That's it — you now have your own behavioral canon, not a copy of Roberto's.
