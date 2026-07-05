# Handoff — session 2026-07-04/05 (public release + v2.0.0 engine/identity split)

**For a fresh agent:** read this + `kb` + `MEMORY.md`, then `gbrain search` what you need.
Design of the split: `docs/plan-2026-07-05-engine-identity-split.md`. Previous handoff
(tool-independence pass, 07-03) is superseded; its open threads that survive are folded in below.

## What this session did (two days, one thread)

1. **Public release prep + go-public.** Security audit found committed kanban cards with
   MirrorBuddy AI-Act compliance detail → history purged (`git filter-repo`) → GitHub kept the
   old history reachable via the merged-PR ref (`refs/pull/1/head`, untouchable server-side) →
   **repo deleted and recreated clean**, then made PUBLIC. MIT license, README with
   prerequisites/install (gstack, gbrain, Ollama). Kanban card content is now **gitignored**
   (`kanban/{todo,doing,done}/` — same split as `private/`); done/ cards restored from the
   pre-purge mirror backup; MirrorBuddy cards revalidated against the real repo (P1 card
   closed via @thor — PR #478 merged, compliance checks 5/5+7/7).
2. **v1.3.0**: fork-identity.sh (rename-based fork) + QUICKSTART — superseded same-day by:
3. **v2.0.0 — engine/identity split** (Roberto explicitly chose the big option over deferral).
   @baccio design → opus implementation in 6 phase-commits → @rex REQUEST-CHANGES (real
   blocker: the learn/ privacy hard-gate didn't follow RDA_HOME for forkers; fixed in
   ee81252, behaviorally verified) → @rex APPROVE → @thor PASS 8/8 → pushed, tagged, released.
   **Core design:** forkers edit ONLY `identity/` (voice, operator, twin-persona,
   identity.conf); engine files never embed identity → `git merge upstream/main` conflict-free
   by construction, proven by `test/test-fork-merge.sh` (wired into validate.sh).
   `RDA_` = fixed engine namespace; `RDA_HOME` (default `~/.roberdan-os`) is the one
   relocatable value. `@roberdan-twin` → **`@twin`** (persona in identity/).
4. **Positioning** (from focus-group + two external reviews, Grok/GPT): "Agentic Digital
   Twin" framing, What-it-is/is-not, `ARCHITECTURE.md` (layer map), "Relationship to
   Convergio" section. GitHub Discussions enabled.
   Release: https://github.com/Roberdan/roberdan-os/releases/tag/v2.0.0

## Afternoon/evening thread (2026-07-05) — multi-CLI orchestration + evolve + Fable

- **Multi-CLI orchestration researched, decided.** CAO (AWS Labs runtime orchestrator) tested
  + rejected (cross-provider handoff to Copilot broken out-of-the-box). **Pivot validated:**
  kanban-as-handoff — `copilot -p` reads a card and executes it one-shot (no runtime orchestration).
  Adversarial review (Fable/@board/@baccio) → external-runners-in-yolo REJECTED; Roberto chose
  **federated kanban + sandboxed runners (restricted form)**. Design in
  `docs/plan-2026-07-05-federated-kanban-multi-cli.md`; @rex APPROVE-WITH-CONCERNS + @luca
  (dormant-mergeable) verdicts appended there. **Next (dedicated session):** @baccio incorporates
  the fixes (leak-check fail-open→preflight #8, lock repo+id, dispatch wired-end-to-end,
  egress-control + hard-wired refusal per @luca), THEN implement phases 1-5 (federation +
  `runner:` label = zero external risk); dispatcher (6-7) stays dormant until OS isolation.
- **evolve watcher rewired** (Saturday 02:00, launchd catch-up if Mac off): now drops a **kanban
  card** per changelog novelty instead of a skeleton draft — any CLI executes it (no `claude -p`).
- **New rule: "Wired End-to-End"** in `rules/best-practices.md` v3.3.0 + `verify-done` — features
  must be reachable from a live path, not just present. (Roberto's rule.)
- **Fable 5 + agent-skills analysis** (both links Roberto gave): Fable doc validates roberdan-os
  on 5 axes; 2 surgical fixes applied — effort doctrine (high/xhigh/low) in the model policy +
  a Fable-scoped section in `thinking-toolkit.md` (NOT in the model:opus agent bodies). addyosmani
  24-skill import rejected (redundant + over-prescription degrades Fable); linked as reference only.

## Federated kanban IMPLEMENTED (2026-07-06, v2.2.0)

Phases 1-6 built + released. @rex APPROVE + @thor PASS, every design fix proven empirically.
- **Read-path** (`kb` cwd-scoped, `kb all`/`g` aggregated, `kb handoff`, explicit registry),
  **`kb init`** (per-repo privacy: gitignore columns, de-track, history-scan, leak-check hook),
  **`runner:`/`human_gates:` + `kb lint`**, **atomic claim** (`repo+id` mkdir-lock) +
  **`factory/lib.sh`** extraction, **dispatcher wired but DORMANT** (`kb dispatch` →
  `factory/dispatch-runner.sh`, preflight #5 hard-wired `readonly` refuse — proven that even
  `OS_FLOOR_PRESENT=1` can't flip it; #8 closes leak-check fail-open).
- **Zero external-runner risk**: the dispatcher refuses every dispatch until a reviewed code
  edit lands the OS floor (phase 7). shellcheck gate extended to the new scripts.
- **⚠️ Security event:** during a credential-helper test the subagent's `git credential fill`
  printed a live `gho_` token into its transcript. Deliverable is CLEAN (0 tokens in tree/history,
  gitleaks clean) — token only in the ephemeral transcript. **Roberto: consider rotating the gh
  token** (revoke "GitHub CLI" OAuth app + re-login).
- **MirrorBuddy P0 card `260703-224310` closed elsewhere** (PR #500 on MirrorBuddy, worktree
  `ai-act-p0`, `approved_by: roberto`) during this window — NOT by this session's dispatcher
  (which refuses). Now in `done/`. Open MirrorBuddy cards: 224312 (P2), 224313 (legal sign-off).

## Open threads

- **PR Convergio #511** — OPEN, blocked by an INDEPENDENT CI failure (RUSTSEC-2026-0190 on
  `anyhow`, team fixing on another branch). Self-merges once the RUSTSEC clears. Roberto's gate:
  https://github.com/Roberdan/convergio/pull/511
- **Federated kanban — remaining human gates (by design):** (1) **phase 7** = OS-isolation floor
  (dedicated uid + per-uid egress-control + empty keychain) — a REVIEWED code edit turns off
  preflight #5; needs its own design doc + @rex/@luca. Until then the dispatcher stays dormant.
  (2) **`kb init` on MirrorBuddy** (+ physically federating cards 224312/224313 into
  `~/GitHub/MirrorBuddy`) — touches a shared FightTheStroke repo.
- **`~/.claude/CLAUDE.md` should be pushed** — the gh token rotation + the effort-doctrine edit
  live there (private, outside the repo).
- Deferred until real demand signal (watch Discussions/forks/traffic): canon levels, metrics
  dashboard, community section, further fork tooling (`twin_handle` generation is scaffolded
  in identity.conf but unconsumed — documented honestly there).
- MirrorBuddy cards: 260703-224310 (P0 code fixes — prosody module + imageBase64 persistence,
  both still open, revalidated 07-05), 260703-224312 (P2 gaps incl. age-gating module that
  appeared since — needs human/legal re-read), 260703-224313 (legal sign-off, Roberto/legale).
- Surviving from 07-03 handoff: eval run against a second agent CLI (harness ready, run it
  when the canon next changes); canon-preference human sample (Roberto's eyes, non-delegable).
- Roberto's machine migrated: bootstrap re-run, `twin.md` symlinked, stale roberdan-twin
  pruned, global `~/.claude/CLAUDE.md` pointer updated, launchd rda-* verified loaded.
  **New sessions invoke `@twin`, not `@roberdan-twin`.**

## Scars this session (don't repeat)

- **GitHub merged-PR refs survive force-push AND branch deletion** — for a real history scrub,
  delete/recreate the repo (or a GitHub support ticket). Structural fix shipped: card content
  is never committed at all now.
- **git filter-repo checks out the rewritten HEAD** → it silently deleted the done/ card
  files from disk too (they were removed from history, so the checkout dropped them);
  restored from the mirror backup. Always `git clone --mirror` before any history rewrite.
- The "rename fork" model (v1.3.0) was wrong within 24h of shipping — the CHANGELOG says so
  honestly. Boundary-by-directory beats rename-by-sed: isolate what forkers edit, don't
  rewrite what they inherit.
