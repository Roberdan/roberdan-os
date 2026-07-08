# kanban — durable, auditable, token-bounded, GATED goal tracking

Card-files (one file per card) in three columns, driven by the fast **`kb`** CLI:
- `todo/` — queued · `doing/` — in progress · `done/` — completed/verified (append-only, read on demand)

**Card content is local-only, never in git.** `todo/`, `doing/` and `done/` are gitignored — they
hold Roberto's live operational/business state (task detail, client/product specifics), the same
split as `private/`. Only the tool (`kb.sh`, this `README.md`) is versioned. On a fresh clone the
three directories start empty; `kb.sh` creates them on demand.

## Fast commands (`kb`)
```
kb                                    # view the board (fast)
kb show <id>                         # show a card
kb add "<title>" --repo <r> [dod] [acc]   # new card in todo/ (repo required)
kb edit <id>                         # fill Definition of Done + Acceptance + repo
kb start <id> --by roberto           # GATE: todo->doing (needs Roberto's approval)
kb finish <id> --thor "<ev>"         # GATE: doing->done (@thor validates with evidence)
kb pause "<next step>"               # lean per-repo checkpoint handoff/resume.md (overwritten;
                                     #   a Stop hook runs `kb pause --auto` after every turn)
kb resume [--done]                   # show checkpoint + live backlog | clear when resumed
kb pending [--count]                 # approval inbox: todo + unapproved learning + non-bot PRs
                                     #   across all registered repos. --count = fast LOCAL total
                                     #   (todo+learning only, no gh) for the SessionStart badge
```

## The two gates (no rubber-stamping)
- **`todo → doing`** is a **human gate** — only Roberto approves what becomes active.
- **`doing → done`** needs **`@thor`** (the done-gate agent) to validate against the card's
  **acceptance criteria**, with **evidence** (commit/test/output). No rubber-stamps.

## Every card has (mandatory)
`title:` — states the **objective** (what outcome this card produces, not just a label) ·
`repo:` — which repo/scope this card is about · `dod:` — a clear **Definition of Done** ·
`acceptance:` — **acceptance criteria** (how @thor verifies). A card cannot `start` until
`repo:`, `dod:` and `acceptance:` are all filled.

## `repo:` — which repo this card is about

Every card must name its scope so a glance at the board (or `kb list`) tells you *what* it's
for, not just its id. Value is one of:
- The **directory name under `~/GitHub`** the card is about, e.g. `repo: roberdan-os`,
  `repo: convergio`, `repo: MirrorBuddy` — this is what most cards should use.
- `repo: personal` — reserved for work that isn't a code repo at all (e.g. inbox/Teams triage,
  a non-code Fight the Stroke initiative).

`kb add "<title>" --repo <r> [dod] [acc]` refuses without `--repo`; `kb start` refuses a card
whose `repo:` is empty or still says `FILL: …` — same discipline as `dod:`/`acceptance:`. The
value isn't validated against the filesystem (the repo may not be cloned on this machine, or may
not exist yet), only checked for "present and not a placeholder."

Where it shows up: `kb list`/`kb todo`/`kb doing`/`kb done` print `[id] (repo) title`; `kb history`
prints `[id] (repo) title (verified <date>)`; the board (`kb`/`kb view`) appends `(repo)` next to
the id whenever it fits the column width, otherwise it degrades to the bare id (never truncates
the id itself — that's the key you pass to `show`/`start`/`finish`). Legacy cards with no `repo:`
render as `(—)` instead of crashing.

## Federation — one board per repo, one aggregating `kb`

Cards live **per-repo** (each repo's own gitignored `kanban/`), and a global `kb` aggregates
them. See `docs/plan-2026-07-05-federated-kanban-multi-cli.md` for the full design.

```
kb                 # inside a repo: that repo's board. Outside any repo: aggregated.
kb all | kb g      # aggregated view across every registered board (cards tagged repo:)
kb handoff         # per-repo handoff/latest.md (in a repo) or aggregated (outside)
kb init [repo]     # make a repo safe to hold cards — idempotent (see below)
kb lint            # schema lint for the optional federated fields
```

**Discovery is an explicit registry, never a scan.** `kb init <repo>` is the single act that
makes a repo safe to hold cards and registers it in `~/.roberdan-os/kanban-registry` (local-only).
It: scaffolds `kanban/{todo,doing,done}`; excludes the card columns + `handoff/resume.md` via the
**local `.git/info/exclude`** (v2.6.0 — never the shared `.gitignore`); de-tracks any card content
already committed (`git rm --cached`, scoped to the columns — never your tracked `kb.sh`/README);
scans **local history** for card blobs (pushed → **refuses**, human gate #4; local-only → loud
warning); installs a leak-check pre-commit hook. A raw `kanban/` dir made by hand is **not**
discovered — only `kb init`'d boards are, so "discovered" ≡ "privacy-initialized". `kb init` does
**not** make a repo runner-eligible (that is the separate, narrower `runner-allowlist`).

> roberdan-os's own `handoff/latest.md` is currently **tracked** canon-ish state; `kb init` **flags**
> it and does **not** silently change that tracking (design §5 note). An untracked `latest.md` in a
> generic repo gets gitignored normally.

## Optional card fields (additive — every one is optional; existing cards are unaffected)

```
runner: copilot-cli/opus   # DECLARATIVE intent label. Grammar: <cli>/<model> | human-only
                           #   <cli> ∈ claude | copilot-cli | ollama
                           #   absent → Claude-native (factory / Agent tool) — today's behavior
                           #   human-only → SENTINEL: touches a gated surface, never external-runnable
human_gates: merge, push   # optional audit list: merge|push|spend|publish|delete|roberto-name
claimed_by:                # set ONLY by the atomic claim (never by hand): "<cli>@<host>/<pid>"
claimed_at:                # UTC ISO-8601, set atomically with claimed_by
```

`runner:` is **intent, not authority** — it never *causes* an external CLI to run (default stays
Claude-native). `kb lint` enforces two rules: `runner:` grammar, and **`human_gates:` non-empty ⇒
`runner:` must be `human-only`** (a gated-surface card must never be runner-eligible). This is a
Layer-1 label — fallible by omission; the real gate is the dispatcher's Layer-2 code (see the design).

## Honest limit: `--by` is a DISCIPLINE gate, not a security boundary

`kb start <id> --by roberto` does **not** verify the caller actually is Roberto — any process
that can run `kb.sh` can pass `--by roberto`. There is deliberately **no blocking check** here:
one would break the documented "do all the todos" autonomous flow, where an agent is expected
to work through queued cards without stopping for interactive confirmation on every single one.

What `kb start` does instead: it appends an audit line to the card on **every call**, including
refused ones — `kb_start_audit: "at=<UTC timestamp> by=<value given> interactive=<yes/no>"` (see
`kanban/kb.sh`). This doesn't stop a bypass, but it makes one **visible** in the card's own
history — a card that was "approved by roberto" from a non-interactive process, or with an
`--by` value that doesn't match who's actually driving the session, is a signal to look closer,
not proof of anything on its own. Treat `--by`/`approved_by` as an honor-system claim the same
way you'd treat a commit's author field — attributable, reviewable, not cryptographically bound.

Only `todo`+`doing` are loaded at session start (auto-injected by `hooks/context-inject.sh`); `done`
is the audit archive → the board never bloats the context.

## Meta-card budget

Self-improvement cards (about roberdan-os itself) can crowd out external-facing ones if left
unbounded — see the **Meta-Card Budget** rule in [`rules/best-practices.md`](../rules/best-practices.md)
for the discipline norm (not a `kb.sh`-enforced gate). `repo:` makes "how many active cards are
`roberdan-os` vs. something external" a one-glance `kb list` read instead of a re-read of every
card's body — still a discipline norm, not a mechanized gate.
