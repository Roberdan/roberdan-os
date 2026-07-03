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
section "frontmatter — agents (name, description, model, tools, constraints, version, maturity)"
for a in $(find agents -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
  miss=""
  for k in name description model tools constraints version maturity; do
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
rm -rf "$d1" "$d2"

# --- 4) Shellcheck -----------------------------------------------------------
section "shellcheck (hooks + bin + test + eval)"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning hooks/*.sh bin/*.sh test/*.sh eval/*.sh; then ok "shellcheck clean"; else err "shellcheck warning/error"; fi
else
  printf "  skip: shellcheck not installed\n"
  for f in hooks/*.sh bin/*.sh test/*.sh eval/*.sh; do bash -n "$f" || err "syntax: $f"; done
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

# --- 7) Leak-check self-test (salted-hash tier b) -----------------------------
section "leak-check self-test — tier (b) salted-hash catches a planted leak"
if bash test/test-leak-check.sh >/dev/null 2>&1; then ok "leak-check tiers verified (see bash test/test-leak-check.sh)"; else err "test-leak-check — see bash test/test-leak-check.sh"; fi

# --- 8) sync.sh --install: skills symlink step (isolated, no real ~/.claude touched) ---
section "sync.sh --install — skills symlink step (isolated via RDA_CLAUDE_SKILLS_DIR)"
if bash test/test-sync-install.sh >/dev/null 2>&1; then ok "install symlink/skip logic verified (see bash test/test-sync-install.sh)"; else err "test-sync-install — see bash test/test-sync-install.sh"; fi

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

# --- Result --------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "validate: ✅ ALL GREEN"; exit 0; else echo "validate: ❌ FAIL (see above)"; exit 1; fi
