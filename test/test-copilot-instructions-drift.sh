#!/usr/bin/env bash
# test-copilot-instructions-drift.sh — .github/copilot-instructions.md (tracked, auto-loaded
# by GitHub Copilot in this repo) must be exactly what bin/sync.sh's emit_copilot() generates.
#
# Card 260924-085105: the tracked file had drifted (hand-edited paragraphs — digital twin,
# adversarial check — that a later rework of the generator silently dropped) and nothing
# caught it: test-canon-structure.sh only checks five anchor phrases, not the whole file.
# This test diffs the FULL file against a fresh regeneration, so any future hand-edit or any
# generator change that isn't also applied to the tracked copy goes red here.
#
# Regeneration is opt-in (RDA_SYNC_REPO_COPILOT — see bin/sync.sh header): sync.sh runs
# unattended from hooks/post-task-sync.sh and inside parallel test suites sharing this
# checkout, so nothing writes the tracked file unless this exact variable names a target.
# That means this test only ever regenerates into its own temp dir — it never touches the
# real .github/copilot-instructions.md.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rda-copilot-instr-check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

section ".github/copilot-instructions.md matches bin/sync.sh's generated output"
REPO_COPY="$TMP/repo-copilot-instructions.md"
rc=0
RDA_SYNC_OUT="$TMP/platforms" RDA_SYNC_REPO_COPILOT="$REPO_COPY" \
  bash bin/sync.sh --emit-only >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  err "bin/sync.sh --emit-only exited non-zero ($rc)"
elif [ ! -f "$REPO_COPY" ]; then
  err "RDA_SYNC_REPO_COPILOT did not produce a file — the opt-in write path is unwired"
elif [ ! -f "$ROOT/.github/copilot-instructions.md" ]; then
  err ".github/copilot-instructions.md is missing from the repo"
elif diff_out="$(diff "$REPO_COPY" "$ROOT/.github/copilot-instructions.md" 2>&1)" && [ -z "$diff_out" ]; then
  ok "tracked .github/copilot-instructions.md is byte-identical to the generator's output"
else
  err ".github/copilot-instructions.md has drifted from bin/sync.sh's generator — regenerate with:"
  err "  RDA_SYNC_REPO_COPILOT=.github/copilot-instructions.md bash bin/sync.sh --emit-only"
  printf '%s\n' "$diff_out" | sed 's/^/    /'
fi

# The opt-in write path itself, proven independently of the diff above: it must be reachable
# (the env var is actually consumed, not a dead knob) and it must be the SAME content sync.sh
# also emits into platforms/copilot/ — one heredoc, never two hand-copies to drift apart.
section "RDA_SYNC_REPO_COPILOT is wired to the same generated content as platforms/copilot/"
if [ -f "$TMP/platforms/copilot/copilot-instructions.md" ] && [ -f "$REPO_COPY" ]; then
  if diff_out2="$(diff "$TMP/platforms/copilot/copilot-instructions.md" "$REPO_COPY" 2>&1)" && [ -z "$diff_out2" ]; then
    ok "platforms/copilot/copilot-instructions.md and the RDA_SYNC_REPO_COPILOT copy are identical"
  else
    err "the two generated copies diverged — emit_copilot is writing two different bodies"
    printf '%s\n' "$diff_out2" | sed 's/^/    /'
  fi
else
  err "one of the two generated files is missing — cannot compare"
fi

[ "$FAIL" -eq 0 ] && { echo; echo "test-copilot-instructions-drift: PASS"; exit 0; }
echo; echo "test-copilot-instructions-drift: FAIL"; exit 1
