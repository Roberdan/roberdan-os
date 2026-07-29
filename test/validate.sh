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

# --- the suites run CONCURRENTLY, the report stays sequential ----------------
# Every test/test-*.sh below is a separate process with its own fixtures under
# its own temp dir; nothing they do depends on the order they run in. The old
# sequential invocation therefore bought nothing but wall clock: measured on
# this machine, the same 17 suites take 289s one after another and 47s started
# together — the wall clock was the ORDERING, not the tests.
#
# So they are all started here, at once, and each section below then blocks on
# its own result and prints exactly the line it printed before. The report a
# human reads is unchanged and still deterministic; only the waiting is gone.
# A suite that needs its output (not just its exit code) reads _suite_out.
_PARDIR="$(mktemp -d "${TMPDIR:-/tmp}/rda-validate.XXXXXX")"
trap 'rm -rf "$_PARDIR"' EXIT INT TERM

_spawn() {
  # Write the exit code LAST and atomically: _suite treats the .rc file as the
  # signal that the .out file is complete, so a half-written .out must never be
  # reachable through a present .rc.
  ( bash "test/$1.sh" > "$_PARDIR/$1.out" 2>&1
    printf '%s' "$?" > "$_PARDIR/$1.rc.part" && mv "$_PARDIR/$1.rc.part" "$_PARDIR/$1.rc" ) &
}

# Some suites are NOT independent of each other, and pretending otherwise is how
# a parallel gate becomes a flaky gate. test-sync-install and test-copilot-adapter
# both call `bin/sync.sh --install` without RDA_SYNC_OUT, so both regenerate
# platforms/ INSIDE THE CHECKOUT. Their shared state is the working tree, not
# $HOME (both isolate $HOME correctly). Run together they raced and
# test-sync-install went red — observed, not theorised.
#
# So they are pinned into one background job and run sequentially INSIDE it:
# they still overlap every other suite, they just never overlap each other.
# The honest alternative is to teach both to emit into a private directory; that
# is a change to what the tests exercise, and it does not belong in a commit
# about wall clock.
_spawn_serial_group() {
  ( for _g in "$@"; do
      bash "test/$_g.sh" > "$_PARDIR/$_g.out" 2>&1
      printf '%s' "$?" > "$_PARDIR/$_g.rc.part" && mv "$_PARDIR/$_g.rc.part" "$_PARDIR/$_g.rc"
    done ) &
}

_suite() {
  local rc_file="$_PARDIR/$1.rc" waited=0
  while [ ! -f "$rc_file" ]; do
    sleep 0.2
    waited=$((waited+1))
    # 15 minutes. A suite that has not finished by then is hung, and hanging
    # forever inside a CI gate is the one failure mode nobody ever debugs.
    if [ "$waited" -gt 4500 ]; then
      printf '  FAIL: %s did not finish within 15 minutes (hung)\n' "$1"
      return 1
    fi
  done
  return "$(cat "$rc_file")"
}

_suite_out() { cat "$_PARDIR/$1.out" 2>/dev/null; }

for _s in test-canon-guardrails test-factory-kb test-kb-views test-kb-done-gate \
          test-kb-root-resolution test-kb-start-worktree-cause test-nested-board-notice \
          test-federated-kb test-leak-check test-fork-merge test-autofmt \
          test-receipts test-install-hooks test-pending test-metaloop \
          test-evolve-declined test-evolve-watch test-review-budget test-bus test-bus-mcp; do
  _spawn "$_s"
done
unset _s
_spawn_serial_group test-sync-install test-copilot-adapter

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
section "canon structure — root AGENTS.md § Human gates, and every pointer that counts them"
# The gate list grows. A hardcoded expected count here, and a hardcoded "7-item
# list" in the pointer, are two hand-written numbers that must agree with a third
# thing that moves — and hand-written numbers that must agree is the exact class
# this suite exists to refuse. It bit immediately: adding human gate #8 turned
# validate.sh red on a card that had not touched a gate.
# So nothing is hardcoded. The invariant is DERIVED: the gates are numbered
# 1..N with no gaps, and any pointer that states a count states THIS N.
if [ -s AGENTS.md ]; then
  gates_body="$(awk '/^## Human gates/{f=1;next} /^## /{if(f)exit} f' AGENTS.md)"
  gates_count=$(printf '%s\n' "$gates_body" | grep -cE '^[0-9]+\. ')
  gates_seq=$(printf '%s\n' "$gates_body" | grep -oE '^[0-9]+' | paste -sd, -)
  expected_seq=$(awk -v n="$gates_count" 'BEGIN{for(i=1;i<=n;i++){printf "%s%d", (i>1?",":""), i}}')
  if [ "$gates_count" -ge 1 ] && [ "$gates_seq" = "$expected_seq" ]; then
    ok "AGENTS.md § Human gates has $gates_count sequentially-numbered gates (1..$gates_count)"
  else
    err "AGENTS.md § Human gates is not a contiguous list: $gates_count gate(s), sequence ${gates_seq:-none}, expected ${expected_seq:-1..N} — a gap or a duplicate means one gate is unreachable by number"
  fi
  # Every pointer that promises "the full N-item list lives there" must promise
  # the right N, or it is a stale instruction to a reader who cannot see this file.
  for ptr in .github/copilot-instructions.md CLAUDE.md ~/.codex/AGENTS.md; do
    [ -f "$ptr" ] || continue
    claimed="$(grep -oE '[0-9]+-item list is `?AGENTS.md`? § Human gates' "$ptr" 2>/dev/null | grep -oE '^[0-9]+' | head -1)"
    [ -n "$claimed" ] || continue
    if [ "$claimed" = "$gates_count" ]; then
      ok "$ptr promises $claimed gates, and AGENTS.md has $gates_count"
    else
      err "$ptr promises a $claimed-item gate list but AGENTS.md § Human gates now has $gates_count — the pointer is lying to whoever only reads $ptr"
    fi
  done
else
  err "root AGENTS.md missing or empty — every pointer (.github/copilot-instructions.md, CLAUDE.md, ~/.codex/AGENTS.md) depends on it"
fi
section "canon guardrails"; if _suite test-canon-guardrails; then ok "cross-tool guardrails present"; else _suite_out test-canon-guardrails; err "test-canon-guardrails failed"; fi
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
section "shellcheck (hooks + bin + test + eval + factory + dispatcher shims + lint-cards + bus)"
# factory/*.sh, the runner-shims and kanban/lint-cards.sh are security-sensitive (dispatcher
# sandbox path) — kept in the gate, not just hand-checked (rex nit #1). kanban/kb.sh is
# deliberately NOT globbed: it carries pre-existing SC1010/SC2010 warnings in untouched code.
SHELLCHECK_TARGETS=(hooks/*.sh bin/*.sh test/*.sh eval/*.sh factory/*.sh factory/runner-shims/* kanban/lint-cards.sh kanban/dash.sh kanban/worktree.sh learn/*.sh ontology/*.sh bus/*.sh)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "${SHELLCHECK_TARGETS[@]}"; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck not installed\n"
  for f in "${SHELLCHECK_TARGETS[@]}"; do bash -n "$f" || err "syntax: $f"; done
fi

# --- 5) Leak check (privacy gate) --------------------------------------------
section "leak check (privacy gate)"
if bash test/leak-check.sh >/dev/null 2>&1; then ok "0 confidential terms"; else err "confidential LEAK — see test/leak-check.sh"; fi

# The cards carry real names and clients and this remote is public, so
# .gitignore:7-9 excludes kanban/todo|doing|done. That exclusion is NOT stable
# on its own: git collects ignore rules per directory, not per repository, and a
# DEEPER .gitignore overrides a shallower one. The private card repo nested at
# kanban/ ships its own .gitignore, and its first version was an allowlist whose
# `!todo/**` silently re-included all 69 cards here as addable. Asserting the
# outcome instead of the rule: whatever any .gitignore at any depth says, a card
# must still be ignored by THIS repo. `git check-ignore` exits 1 when the path
# is NOT ignored, which is the failure we want to catch.
_ignore_probe="kanban/todo/.rda-ignore-probe.md"
mkdir -p kanban/todo && : > "$_ignore_probe"
if git check-ignore -q "$_ignore_probe"; then
  ok "kanban cards ignored by the public repo (no .gitignore at any depth re-includes them)"
else
  err "kanban cards are NOT ignored — a negation somewhere re-included them; run: git check-ignore -v $_ignore_probe"
fi
rm -f "$_ignore_probe"

# --- 6) Factory + kb gates (real assertions, not a smoke test) ---------------
section "factory + kb gates"
if _suite test-factory-kb; then ok "kb gates + factory guardrails green"; else err "test-factory-kb — see bash test/test-factory-kb.sh"; fi

# --- 6b) kb detail/ops views (history/archive/plans/plan/sched) --------------
section "kb views (history/archive/plans/plan/sched)"
if _suite test-kb-views; then ok "kb views green"; else err "test-kb-views — see bash test/test-kb-views.sh"; fi

# --- 6b3) $ROOT must survive the symlink it is always reached through ---------
# `kb` is installed as ~/.local/bin/kb -> kanban/kb.sh, and BASH_SOURCE reports
# the LINK. The naive derivation therefore resolved ~/.local on every PATH
# invocation: `kb lint` looked for a script that was not there, RDA_LEAKCHECK
# pointed at a privacy check that was not there, and the fallback board became
# ~/.local/kanban — created by mkdir -p, so 32 real cards accumulated on a board
# no view aggregated. One loud symptom, three silent ones.
section "kb \$ROOT resolution (symlinked install)"
if _suite test-kb-root-resolution; then ok "\$ROOT survives symlinks; no phantom board"; else err "test-kb-root-resolution — see bash test/test-kb-root-resolution.sh"; fi
if _suite test-kb-start-worktree-cause; then ok "kb start names the real worktree failure, never a false one"; else err "test-kb-start-worktree-cause — see bash test/test-kb-start-worktree-cause.sh"; fi

# --- 6b4) kb done-gate must be mechanical, not honor-system -------------------
# Pins both directions: forged evidence (rubber-stamps, fake SHAs) is refused, and
# real evidence (resolvable SHA, test output, existing path) still passes. The gate
# that only refuses is as useless as the one that only accepts.
section "kb done-gate (mechanical evidence, no rubber-stamps)"
if _suite test-kb-done-gate; then ok "done-gate refuses forged evidence, accepts real"; else err "test-kb-done-gate — see bash test/test-kb-done-gate.sh"; fi

# --- 6c) federated kanban + dormant dispatcher --------------------------------
section "federated kanban (cwd-scoping, kb all/handoff, init, locks, dormant dispatcher)"
# On failure, surface the test's own output (indented) instead of hiding it behind a "see …"
# pointer — a failing gate must show the evidence, especially for CI-only failures.
_suite test-federated-kb; _fedkb_out="$(_suite_out test-federated-kb)"
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
if _suite test-leak-check; then ok "leak-check tiers verified (see bash test/test-leak-check.sh)"; else err "test-leak-check — see bash test/test-leak-check.sh"; fi

section "pre-commit hook e' installato E aggiornato (il leak check blocca solo se e' acceso)"
# Nothing checked this until 2026-07-29, and on that day the installed hook was still the
# 2 July copy: hooks/pre-commit had been edited, the gate was green, and the new check had
# never run once. The leak check that BLOCKS commits lives in that same hook and was
# written after a real leak was committed and pushed — so "is it actually wired" is not
# hygiene, it is the control itself. A stale copy passes every other test in this file.
#
# The shim is matched on its GENERATED banner, not on the string "hooks/pre-commit": the
# first draft grepped for that path and passed on a stale COPY, because the copy carries
# it in its own header comment. Verified by putting the old copy back and watching this
# turn red — a check nobody has seen fail is a guess.
_gitdir="$(git rev-parse --git-dir 2>/dev/null || true)"
_ih="$_gitdir/hooks/pre-commit"
if [ ! -x "$_ih" ]; then
  err "nessun pre-commit installato — il leak check non blocca niente (bash bin/install-git-hooks.sh)"
elif grep -q '^# GENERATED by bin/install-git-hooks.sh' "$_ih" 2>/dev/null; then
  ok "pre-commit e' uno shim sul file versionato: non puo' andare fuori sincrono"
elif diff -q hooks/pre-commit "$_ih" >/dev/null 2>&1; then
  ok "pre-commit e' una copia, ma identica al sorgente"
else
  err "il pre-commit installato NON e' il sorgente versionato: le modifiche a hooks/pre-commit non hanno effetto (bash bin/install-git-hooks.sh)"
fi
unset _gitdir _ih

section "board annidata — un commit che non include le card lo dice"
if _suite test-nested-board-notice; then ok "kanban/ sporca -> il commit avvisa, e passa comunque"; else err "test-nested-board-notice — see bash test/test-nested-board-notice.sh"; fi

# --- 7b) fork merge-clean proof (the v2.0.0 engine/identity split guarantee) ----------
section "fork merge-clean — identity-only fork merges upstream engine edits, zero conflicts"
if _suite test-fork-merge; then ok "merge-clean proof green (see bash test/test-fork-merge.sh)"; else err "test-fork-merge — see bash test/test-fork-merge.sh"; fi

# --- 8) sync.sh --install: skills symlink step (isolated, no real ~/.claude touched) ---
section "sync.sh --install — skills symlink step (isolated via RDA_CLAUDE_SKILLS_DIR)"
if _suite test-sync-install; then ok "install symlink/skip logic verified (see bash test/test-sync-install.sh)"; else err "test-sync-install — see bash test/test-sync-install.sh"; fi

# --- 8a) Copilot native adapter (agents + extension emission/install/load/guards) ---
section "copilot native adapter — emission, collision-safe install, extension load + guard mapping"
if _suite test-copilot-adapter; then ok "copilot adapter verified (see bash test/test-copilot-adapter.sh)"; else err "test-copilot-adapter — see bash test/test-copilot-adapter.sh"; fi

# --- 8b) hooks/autofmt.sh input contract (stdin JSON; the old env-var API was a silent no-op) ---
section "autofmt hook — stdin JSON input contract"
if _suite test-autofmt; then ok "autofmt receives files via stdin JSON (see bash test/test-autofmt.sh)"; else err "test-autofmt — see bash test/test-autofmt.sh"; fi

# --- 8c) loop receipts emitter (schema, append-only, opt-in placement, no pollution) ---
section "loop receipts — loop/receipt.sh emitter contract"
if _suite test-receipts; then ok "receipt emitter green (see bash test/test-receipts.sh)"; else err "test-receipts — see bash test/test-receipts.sh"; fi

# --- 8d) install-hooks: settings.json merge is additive/idempotent/non-destructive ---
section "install-hooks — settings.json merge contract"
if _suite test-install-hooks; then ok "install-hooks merge green (see bash test/test-install-hooks.sh)"; else err "test-install-hooks — see bash test/test-install-hooks.sh"; fi

# --- 8e) approval inbox: kb pending aggregates + counts, digest writes without failing ---
section "approval inbox — kb pending + digest contract"
if _suite test-pending; then ok "approval inbox green (see bash test/test-pending.sh)"; else err "test-pending — see bash test/test-pending.sh"; fi

# --- 8e) meta-loop wired end-to-end (capture -> distill[real class] -> curate promotes) ---
# The self-improving loop must actually PROMOTE an approved learning, not stall at
# `class: TODO`. Proves capture->distill(real class)->human-approve->curate-promotes,
# plus the two honesty gates (ephemera dropped, unapproved never promoted).
section "meta-loop — capture -> distill -> curate promotion (test/test-metaloop.sh)"
if _suite test-metaloop; then ok "meta-loop promotes end-to-end (see bash test/test-metaloop.sh)"; else err "test-metaloop — see bash test/test-metaloop.sh"; fi

# --- 8b) evolve rejected-proposal buffer --------------------------------------
# Pins that a reworded repeat is recognized, a genuine novelty is NOT suppressed, and the
# buffer actually reaches the agent through the card watch.sh writes (wired, not just present).
section "evolve rejected-proposal buffer (test/test-evolve-declined.sh)"
if _suite test-evolve-declined; then ok "declined buffer matches rewordings, spares novelties, reaches the card"; else err "test-evolve-declined — see bash test/test-evolve-declined.sh"; fi

section "evolve watcher backpressure (test/test-evolve-watch.sh)"
if _suite test-evolve-watch; then ok "a changelog change while a card is still open refreshes it instead of adding a sibling, and the watcher never moves a card between columns"; else _suite_out test-evolve-watch; err "test-evolve-watch — see bash test/test-evolve-watch.sh"; fi

# Messages between agents, never execution. The load-bearing checks are the negative
# ones: the bus must not be able to start an agent (that is factory/dispatch-runner.sh,
# dormant by a reviewed decision), write kanban state, or carry acceptance criteria.
# An unwired test is an unverified claim, so it runs here — see bus/bus-protocol.md.
section "review budget — a review loop that cannot run forever (test/test-review-budget.sh)"
if _suite test-review-budget; then ok "a spent review budget exits 3 and demands a human decision instead of another round"; else err "test-review-budget — see bash test/test-review-budget.sh"; fi

section "agent bus — messages, never execution (test/test-bus.sh)"
if _suite test-bus; then ok "bus delivers durably, attributes, resolves citations to no more than they prove, and executes nothing"; else _suite_out test-bus; err "test-bus — see bash test/test-bus.sh"; fi

section "agent bus — the typed MCP surface (test/test-bus-mcp.sh)"
if _suite test-bus-mcp; then ok "the MCP surface dispatches send/read/log only, refuses unknown tools, and stores shell metacharacters as inert data"; else _suite_out test-bus-mcp; err "test-bus-mcp — see bash test/test-bus-mcp.sh"; fi
# THE MUTATION HARNESS IS NO LONGER A GATE. `bash test/test-bus-mutants.sh` is
# still in the tree and still useful to run by hand when the bus changes shape,
# but it does not decide whether this repo is releasable, for three reasons that
# were measured on 2026-07-28 rather than argued:
#
#   - IT WAS NEVER GREEN. Its floors swept ~/.claude, whose directory mtime moves
#     whenever any live agent session writes. On this machine one always is, so
#     the gate accused the session running it. Not once did a green run exist.
#   - IT COST 60 MINUTES FOR THE WRONG REASON. 96.9 of the suite's 188 seconds
#     were an awk pass handed 9MB of xtrace including a 60,019-character line;
#     27 of the 62 mutants reach that check, so ~45 of the 60 minutes were one
#     badly-fed pipeline, not 62 justified proofs.
#   - IT DECLARES ITS OWN INSUFFICIENCY. `survives brace-blind` is an asserted
#     SURVIVOR: it starts an agent inside a stderr-redirected compound command
#     and this suite stays green. Its comment says there is no in-process fix.
#
# A gate that cannot pass, costs an hour, and states in writing that it cannot
# enforce its own central property is not a gate. Property 1 ("never starts an
# agent") is now enforced by the SHAPE of the bus core rather than detected
# afterwards; property 2 ("never writes kanban state") is still checked, in
# process, by test-bus.sh above.

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
