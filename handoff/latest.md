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

## Open threads

- **PR Convergio #511** (docs/vision.md cross-ref, "one citizen's house" bullet) — OPEN,
  **merge is Roberto's gate**: https://github.com/Roberdan/convergio/pull/511
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
