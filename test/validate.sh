#!/usr/bin/env bash
# validate.sh — roberdan-os CI gate. Runs on every PR.
# 1) frontmatter lint (agents vs skills: distinct schemas)  2) link check (exempts [[wikilink]])
# 3) drift check (generation is deterministic)  4) shellcheck  5) leak check  8) sync.sh --install
# skills symlink step (isolated, incl. emit-only must NOT touch it)  10) tool coverage — for
# tools DETECTED as installed on THIS machine, asserts the real wiring artifact still exists
# (skip, never FAIL, for tools not installed — must be a total no-op on a clean CI box)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()      { printf "  ok: %s\n" "$1"; }

# --- 1) Frontmatter lint -----------------------------------------------------
section "frontmatter — agents (name, description, model, effort, tools, constraints, version, maturity)"
for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  miss=""
  for k in name description model effort tools constraints version maturity; do
    grep -qE "^$k:" "$a" || miss="$miss $k"
  done
  # model must be quoted
  if grep -qE '^model:' "$a" && ! grep -qE '^model:[[:space:]]*"' "$a"; then
    miss="$miss model-not-quoted"
  fi
  [ -n "$miss" ] && err "$a missing:$miss" || ok "$(basename "$a")"
done

section "frontmatter — skills (name, description, providers)"
for s in $(find skills -maxdepth 2 -name 'skill.md' | LC_ALL=C sort); do
  miss=""
  for k in name description providers; do
    grep -qE "^$k:" "$s" || miss="$miss $k"
  done
  [ -n "$miss" ] && err "$s missing:$miss" || ok "$s"
done

section "frontmatter — kanban cards, todo/doing only (title, repo, dod, acceptance, status, created)"
# done/ is the append-only audit archive — not linted here (see kanban/README.md): backfilling
# repo: onto historical done cards isn't required, only active todo/doing cards are gated on it.
found=0
for k in kanban/todo kanban/doing; do
  for c in "$k"/*.md; do
    [ -e "$c" ] || continue
    case "$(basename "$c")" in _*) continue ;; esac
    found=1
    miss=""
    for field in title repo dod acceptance status created; do
      grep -qE "^$field:" "$c" || miss="$miss $field"
    done
    [ -n "$miss" ] && err "$c missing:$miss" || ok "$c"
  done
done
[ "$found" -eq 0 ] && printf "  skip: no active todo/doing cards to lint\n"

# federated additive-schema lint (runner: grammar + human_gates:↔human-only, design §2c/§3)
section "frontmatter — federated card schema (runner:, human_gates:↔human-only)"
if bash kanban/lint-cards.sh kanban >/dev/null 2>&1; then ok "runner/human_gates schema clean"; else err "runner/human_gates lint — see bash kanban/lint-cards.sh kanban"; fi

# --- 1e) canon structure — AGENTS.md § Human gates (mechanical invariant, @rex #4) -------
section "canon structure — root AGENTS.md exists and § Human gates lists the 7 numbered gates"
# .github/copilot-instructions.md was shortened to a pointer ("full 7-item list is AGENTS.md
# § Human gates") — that's only safe if the section it points at actually still carries all 7.
# This proves the invariant mechanically instead of trusting the pointer to stay in sync.
# Non-brittle: counts + sequential numbering only, not exact gate wording.
if [ -s AGENTS.md ]; then
  gates_body="$(awk '/^## Human gates/{f=1;next} /^## /{if(f)exit} f' AGENTS.md)"
  gates_count=$(printf '%s\n' "$gates_body" | grep -cE '^[0-9]+\. ')
  gates_seq=$(printf '%s\n' "$gates_body" | grep -oE '^[0-9]+' | paste -sd, -)
  if [ "$gates_count" -eq 7 ] && [ "$gates_seq" = "1,2,3,4,5,6,7" ]; then
    ok "AGENTS.md § Human gates has exactly 7 sequentially-numbered gates"
  else
    err "AGENTS.md § Human gates has $gates_count gate(s) (sequence: ${gates_seq:-none}), expected 7 (1..7) — the copilot-instructions.md pointer promises the full list lives here"
  fi
else
  err "root AGENTS.md missing or empty — every pointer (.github/copilot-instructions.md, CLAUDE.md, ~/.codex/AGENTS.md) depends on it"
fi

# --- 2) Link check (relative markdown; exempts [[wikilink]] and http) --------
section "link check (relative markdown; [[wikilink]] exempted)"
broken=0
for md in $(git ls-files '*.md' | LC_ALL=C sort); do
  dir="$(dirname "$md")"
  # extracts [text](path) targets, excluding http(s) and pure anchors (#...)
  grep -oE '\]\([^)# ][^)]*\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*) continue ;;
    esac
    target="${link%%#*}"                      # strips any anchor
    [ -z "$target" ] && continue
    resolved="$dir/$target"
    if [ ! -e "$resolved" ]; then
      printf "  FAIL: %s → broken link: %s\n" "$md" "$link"
      echo "BROKEN" >> /tmp/rda-linkcheck.$$
    fi
  done
done
if [ -f "/tmp/rda-linkcheck.$$" ]; then broken=$(wc -l < "/tmp/rda-linkcheck.$$"); rm -f "/tmp/rda-linkcheck.$$"; fi
[ "$broken" -gt 0 ] && FAIL=1 || ok "all relative links resolve"

# --- 3) Drift check (generation is deterministic) -----------------------------
# platforms/ is no longer committed (fully generated — see .gitignore). Instead of
# diffing regenerated output against a committed copy, verify bin/sync.sh --emit-only
# is deterministic and succeeds: two independent runs into two temp dirs must be
# byte-identical.
section "drift check — bin/sync.sh --emit-only is deterministic"
d1="$(mktemp -d "${TMPDIR:-/tmp}/rda-sync-check.XXXXXX")"
d2="$(mktemp -d "${TMPDIR:-/tmp}/rda-sync-check.XXXXXX")"
rc1=0; rc2=0
RDA_SYNC_OUT="$d1" bash bin/sync.sh --emit-only >/dev/null 2>&1 || rc1=$?
RDA_SYNC_OUT="$d2" bash bin/sync.sh --emit-only >/dev/null 2>&1 || rc2=$?
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  err "drift: bin/sync.sh --emit-only exited non-zero (run1=$rc1 run2=$rc2)"
elif diff_out="$(diff -r "$d1" "$d2" 2>&1)" && [ -z "$diff_out" ]; then
  ok "generation is deterministic (two independent runs are byte-identical)"
else
  err "drift: bin/sync.sh --emit-only is non-deterministic across runs"
  printf '%s\n' "$diff_out" | sed 's/^/    /'
fi
# H1 guard (rex, HIGH 2026-07-07): the emitted settings snippet must contain NO
# unexpanded $VAR — an undefined var expands empty on merge and kills the hooks silently.
if [ -f "$d1/claude/settings-hooks.json" ]; then
  if grep -qE '\$[A-Za-z_]' "$d1/claude/settings-hooks.json"; then
    err "settings-hooks.json carries an unexpanded \$VAR (hooks would die silently on a fresh merge)"
  else
    ok "settings-hooks.json fully expanded (absolute hook paths, no \$VAR)"
  fi
else
  err "settings-hooks.json missing from emitted output"
fi
rm -rf "$d1" "$d2"

# --- 4) Shellcheck -----------------------------------------------------------
section "shellcheck (hooks + bin + test + eval + factory + dispatcher shims + lint-cards)"
# factory/*.sh, the runner-shims and kanban/lint-cards.sh are security-sensitive (dispatcher
# sandbox path) — kept in the gate, not just hand-checked (rex nit #1). kanban/kb.sh is
# deliberately NOT globbed: it carries pre-existing SC1010/SC2010 warnings in untouched code.
SHELLCHECK_TARGETS=(hooks/*.sh bin/*.sh test/*.sh eval/*.sh factory/*.sh factory/runner-shims/* kanban/lint-cards.sh learn/*.sh ontology/*.sh)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "${SHELLCHECK_TARGETS[@]}"; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck not installed\n"
  for f in "${SHELLCHECK_TARGETS[@]}"; do bash -n "$f" || err "syntax: $f"; done
fi

# --- 5) Leak check (privacy gate) --------------------------------------------
section "leak check (privacy gate)"
if bash test/leak-check.sh >/dev/null 2>&1; then ok "0 confidential terms"; else err "confidential LEAK — see test/leak-check.sh"; fi

# --- 6) Factory + kb gates (real assertions, not a smoke test) ---------------
section "factory + kb gates"
if bash test/test-factory-kb.sh >/dev/null 2>&1; then ok "kb gates + factory guardrails green"; else err "test-factory-kb — see bash test/test-factory-kb.sh"; fi

# --- 6b) kb detail/ops views (history/archive/plans/plan/sched) --------------
section "kb views (history/archive/plans/plan/sched)"
if bash test/test-kb-views.sh >/dev/null 2>&1; then ok "kb views green"; else err "test-kb-views — see bash test/test-kb-views.sh"; fi

# --- 6b2) the done-gate must be mechanical, not honor-system -------------------
# Pins both directions: forged evidence (rubber-stamps, fake SHAs) is refused, and
# real evidence (resolvable SHA, test output, existing path) still passes. The gate
# that only refuses is as useless as the one that only accepts.
section "kb done-gate (mechanical evidence, no rubber-stamps)"
if bash test/test-kb-done-gate.sh >/dev/null 2>&1; then ok "done-gate refuses forged evidence, accepts real"; else err "test-kb-done-gate — see bash test/test-kb-done-gate.sh"; fi

# --- 6c) federated kanban + dormant dispatcher --------------------------------
section "federated kanban (cwd-scoping, kb all/handoff, init, locks, dormant dispatcher)"
# On failure, surface the test's own output (indented) instead of hiding it behind a "see …"
# pointer — a failing gate must show the evidence, especially for CI-only failures.
_fedkb_out="$(bash test/test-federated-kb.sh 2>&1)"
if [ $? -eq 0 ]; then ok "federated kb + dispatcher gates green"; else
  printf '%s\n' "$_fedkb_out" | grep -iE '===|ok:|err|FAIL|got:|outside=|inside=|rc=' | sed 's/^/    /'
  err "test-federated-kb failed (output above)"
fi

# --- 6d) dispatcher WIRED even while dormant (@rex #5) ------------------------
# A module that exists but has no live entry-path is not "wired" — dormancy must
# come from REFUSAL (preflight #5/#8), not from being unreachable. This check FAILS
# if `kb dispatch` no longer routes to an executable dispatch-runner.sh.
section "dispatcher wired (kb dispatch -> factory/dispatch-runner.sh) even while dormant"
if grep -qE '^[[:space:]]*dispatch\)[^#]*factory/dispatch-runner\.sh' kanban/kb.sh && [ -x factory/dispatch-runner.sh ]; then
  ok "kb dispatch routes to an executable dispatch-runner.sh (dormant by refusal, not unreachable)"
else
  err "kb dispatch is NOT wired to factory/dispatch-runner.sh — dormant-by-unreachable is forbidden (@rex #5)"
fi

# --- 7) Leak-check self-test (salted-hash tier b) -----------------------------
section "leak-check self-test — tier (b) salted-hash catches a planted leak"
if bash test/test-leak-check.sh >/dev/null 2>&1; then ok "leak-check tiers verified (see bash test/test-leak-check.sh)"; else err "test-leak-check — see bash test/test-leak-check.sh"; fi

# --- 7b) fork merge-clean proof (the v2.0.0 engine/identity split guarantee) ----------
section "fork merge-clean — identity-only fork merges upstream engine edits, zero conflicts"
if bash test/test-fork-merge.sh >/dev/null 2>&1; then ok "merge-clean proof green (see bash test/test-fork-merge.sh)"; else err "test-fork-merge — see bash test/test-fork-merge.sh"; fi

# --- 8) sync.sh --install: skills symlink step (isolated, no real ~/.claude touched) ---
section "sync.sh --install — skills symlink step (isolated via RDA_CLAUDE_SKILLS_DIR)"
if bash test/test-sync-install.sh >/dev/null 2>&1; then ok "install symlink/skip logic verified (see bash test/test-sync-install.sh)"; else err "test-sync-install — see bash test/test-sync-install.sh"; fi

# --- 8a) Copilot native adapter (agents + extension emission/install/load/guards) ---
section "copilot native adapter — emission, collision-safe install, extension load + guard mapping"
if bash test/test-copilot-adapter.sh >/dev/null 2>&1; then ok "copilot adapter verified (see bash test/test-copilot-adapter.sh)"; else err "test-copilot-adapter — see bash test/test-copilot-adapter.sh"; fi

# --- 8b) hooks/autofmt.sh input contract (stdin JSON; the old env-var API was a silent no-op) ---
section "autofmt hook — stdin JSON input contract"
if bash test/test-autofmt.sh >/dev/null 2>&1; then ok "autofmt receives files via stdin JSON (see bash test/test-autofmt.sh)"; else err "test-autofmt — see bash test/test-autofmt.sh"; fi

# --- 8c) loop receipts emitter (schema, append-only, opt-in placement, no pollution) ---
section "loop receipts — loop/receipt.sh emitter contract"
if bash test/test-receipts.sh >/dev/null 2>&1; then ok "receipt emitter green (see bash test/test-receipts.sh)"; else err "test-receipts — see bash test/test-receipts.sh"; fi

# --- 8d) install-hooks: settings.json merge is additive/idempotent/non-destructive ---
section "install-hooks — settings.json merge contract"
if bash test/test-install-hooks.sh >/dev/null 2>&1; then ok "install-hooks merge green (see bash test/test-install-hooks.sh)"; else err "test-install-hooks — see bash test/test-install-hooks.sh"; fi

# --- 8e) approval inbox: kb pending aggregates + counts, digest writes without failing ---
section "approval inbox — kb pending + digest contract"
if bash test/test-pending.sh >/dev/null 2>&1; then ok "approval inbox green (see bash test/test-pending.sh)"; else err "test-pending — see bash test/test-pending.sh"; fi

# --- 8e) meta-loop wired end-to-end (capture -> distill[real class] -> curate promotes) ---
# The self-improving loop must actually PROMOTE an approved learning, not stall at
# `class: TODO`. Proves capture->distill(real class)->human-approve->curate-promotes,
# plus the two honesty gates (ephemera dropped, unapproved never promoted).
section "meta-loop — capture -> distill -> curate promotion (test/test-metaloop.sh)"
if bash test/test-metaloop.sh >/dev/null 2>&1; then ok "meta-loop promotes end-to-end (see bash test/test-metaloop.sh)"; else err "test-metaloop — see bash test/test-metaloop.sh"; fi

# --- 8b) evolve rejected-proposal buffer --------------------------------------
# Pins that a reworded repeat is recognized, a genuine novelty is NOT suppressed, and the
# buffer actually reaches the agent through the card watch.sh writes (wired, not just present).
section "evolve rejected-proposal buffer (test/test-evolve-declined.sh)"
if bash test/test-evolve-declined.sh >/dev/null 2>&1; then ok "declined buffer matches rewordings, spares novelties, reaches the card"; else err "test-evolve-declined — see bash test/test-evolve-declined.sh"; fi

# --- 9) eval/ harness (stub-mode pipeline test) -------------------------------
# eval/ measures whether the behavioral canon changes agent output (see eval/README.md). The
# actual with/without-canon comparison needs a real `claude` binary and Roberto's own machine —
# what CI can verify is that the harness itself (run-eval.sh -> judge.sh -> report.sh) is
# mechanically correct, resumable, and blind — see eval/test-eval-pipeline.sh.
section "eval/ harness — stub-mode pipeline (run-eval -> judge -> report)"
if bash eval/test-eval-pipeline.sh >/dev/null 2>&1; then ok "eval harness verified (see bash eval/test-eval-pipeline.sh)"; else err "test-eval-pipeline — see bash eval/test-eval-pipeline.sh"; fi

# --- 10) tool coverage (installed tools only) --------------------------------
# Wiring can silently rot: Roberto reinstalls Copilot, deletes a pointer, upgrades
# codex — nothing notices ("looks wired but never ran", see eval/tasks/12). For
# each tool DETECTED as present on this machine, assert its wiring artifact still
# exists. A tool that isn't installed is a clean "skip", never a FAIL — so this
# section is a total no-op on a fresh clone / CI box with no tools installed.
section "tool coverage (installed tools only)"
REMEDIATE="run: bash bin/sync.sh --install"

# claude: only the 3 roberdan-os skills known NOT to collide with another skill
# system (gstack vendors 'review' and 'ship' under the same name — documented,
# intentionally not asserted here).
if [ -d "$HOME/.claude" ]; then
  for s in auto-checkpoint sync verify-done; do
    _lnk="$HOME/.claude/skills/$s/SKILL.md"
    if [ -e "$_lnk" ] && readlink "$_lnk" 2>/dev/null | grep -q "roberdan-os/platforms/"; then
      ok "claude skill '$s' wired (symlink resolves into roberdan-os platforms/)"
    elif [ -e "$_lnk" ]; then
      err "claude skill '$s' exists but is NOT the roberdan-os symlink (foreign same-name skill?) — $REMEDIATE"
    else
      err "claude skill '$s' missing at $_lnk — $REMEDIATE"
    fi
  done
else
  printf "  skip: claude not installed (no ~/.claude)\n"
fi

# copilot: all 8 roberdan-os skills + gbrain wired into its own mcp-config.json.
if [ -d "$HOME/.copilot" ]; then
  for s in auto-checkpoint focus-group premortem problem-validation review ship sync verify-done; do
    _lnk="$HOME/.copilot/skills/$s/SKILL.md"
    if [ -e "$_lnk" ] && readlink "$_lnk" 2>/dev/null | grep -q "roberdan-os/platforms/"; then
      ok "copilot skill '$s' wired (symlink resolves into roberdan-os platforms/)"
    elif [ -e "$_lnk" ]; then
      err "copilot skill '$s' exists but is NOT the roberdan-os symlink (foreign same-name skill?) — $REMEDIATE"
    else
      err "copilot skill '$s' missing at $_lnk — $REMEDIATE"
    fi
  done
  if [ -f "$HOME/.copilot/mcp-config.json" ]; then
    if grep -q "gbrain" "$HOME/.copilot/mcp-config.json" 2>/dev/null; then
      ok "copilot mcp-config.json has gbrain"
    else
      err "copilot mcp-config.json missing gbrain — add it manually (Copilot-owned file, sync.sh never writes it)"
    fi
  else
    printf "  skip: ~/.copilot/mcp-config.json not present yet (Copilot never run)\n"
  fi
  # copilot native agents: each roberdan-os agent symlinked into ~/.copilot/agents.
  # Match the symlink target structurally (…/platforms/copilot/agents/…) rather than by a
  # hardcoded repo-dir name, so a worktree/fork install (dir not literally "roberdan-os") is
  # still recognized as genuinely wired.
  for ag in baccio board coach luca rex socrates thor twin wanda; do
    _agl="$HOME/.copilot/agents/$ag.md"
    if [ -L "$_agl" ] && readlink "$_agl" 2>/dev/null | grep -qE "/platforms/copilot/agents/"; then
      ok "copilot agent '$ag' wired (symlink resolves into a roberdan-os platforms/ checkout)"
    elif [ -e "$_agl" ]; then
      err "copilot agent '$ag' exists but is NOT a roberdan-os symlink (foreign same-name agent?) — $REMEDIATE"
    else
      err "copilot agent '$ag' missing at $_agl — $REMEDIATE"
    fi
  done
  # copilot native extension: symlinked into ~/.copilot/extensions/roberdan-os.
  _extl="$HOME/.copilot/extensions/roberdan-os/extension.mjs"
  if [ -L "$_extl" ] && readlink "$_extl" 2>/dev/null | grep -qE "/platforms/copilot/extension/"; then
    ok "copilot extension wired (symlink resolves into a roberdan-os platforms/ checkout)"
  elif [ -e "$_extl" ]; then
    err "copilot extension exists but is NOT a roberdan-os symlink — $REMEDIATE"
  else
    err "copilot extension missing at $_extl — $REMEDIATE"
  fi
else
  printf "  skip: copilot not installed (no ~/.copilot)\n"
fi

# codex: reads AGENTS.md natively — just the global pointer needs to exist.
if [ -d "$HOME/.codex" ]; then
  if [ -s "$HOME/.codex/AGENTS.md" ]; then
    ok "codex pointer wired (~/.codex/AGENTS.md non-empty)"
  else
    err "codex pointer missing/empty at ~/.codex/AGENTS.md — $REMEDIATE"
  fi
else
  printf "  skip: codex not installed (no ~/.codex)\n"
fi

# opencode: reads AGENTS.md natively — detected by binary OR config dir (same
# detection sync.sh --install uses, so gate and installer never disagree).
if command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ]; then
  if [ -e "$HOME/.config/opencode/AGENTS.md" ]; then
    ok "opencode pointer wired (~/.config/opencode/AGENTS.md exists)"
  else
    err "opencode pointer missing at ~/.config/opencode/AGENTS.md — $REMEDIATE"
  fi
else
  printf "  skip: opencode not installed (command not found)\n"
fi

# ~/GitHub pointer fabric: only meaningful on machines using the canonical
# ~/GitHub layout — i.e. when THIS repo itself lives under $HOME/GitHub. On CI
# runners / other layouts (repo checked out elsewhere) the pointer convention
# doesn't apply, so skip instead of failing (this exact check broke CI on
# 2026-07-03: the runner tripped the $HOME/GitHub condition).
if [ "$(cd "$ROOT/.." 2>/dev/null && pwd)" = "$HOME/GitHub" ]; then
  if [ -f "$HOME/GitHub/AGENTS.md" ] && grep -q "roberdan-os" "$HOME/GitHub/AGENTS.md" 2>/dev/null; then
    ok "\$HOME/GitHub/AGENTS.md wired (mentions roberdan-os)"
  else
    err "\$HOME/GitHub/AGENTS.md missing or doesn't mention roberdan-os — $REMEDIATE"
  fi
else
  printf "  skip: repo not under \$HOME/GitHub (different layout, pointer convention n/a)\n"
fi

# --- 11) plan coverage (every normative plan clause maps to a card) -----------
# The plan→card step is the ONLY link in the chain with no gate — and it is exactly where
# requirements die. Every other gate (kb, @thor, the merge-gate, CI) operates DOWNSTREAM of the
# card, so a requirement that never BECOMES a card is invisible to all of them simultaneously.
# (trading-os, 2026-07-13: the signed plan mandated SEC EDGAR/RSS + company IR + GDELT; the only
# card that could have delivered it said "at least one mandatory free live source", closed honestly
# green, and the news evaporated. An audit found 77 of 149 normative clauses never reached the
# product.) `kb cover` walks FROM the plan: a board cannot show you the ABSENCE of a card.
section "plan coverage (every normative clause of docs/plan.md has a card or a written decision)"
if [ -f "$ROOT/docs/plan.md" ]; then
  if RDA_KANBAN="$ROOT/kanban" bash "$ROOT/kanban/kb.sh" cover "$ROOT/docs/plan.md" > /tmp/kbcover.$$ 2>&1; then
    ok "$(tail -2 /tmp/kbcover.$$ | head -1 | sed 's/^ *//')"
  else
    err "a plan clause has no card and no written decision — run: kb cover docs/plan.md"
    sed 's/^/    /' /tmp/kbcover.$$
  fi
  rm -f /tmp/kbcover.$$
else
  skip "no docs/plan.md"
fi

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "validate: ✅ ALL GREEN"; exit 0; else echo "validate: ❌ FAIL (see above)"; exit 1; fi
