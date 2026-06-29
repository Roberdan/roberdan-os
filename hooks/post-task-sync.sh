#!/usr/bin/env bash
# Stop / SubagentStop hook — anti-drift dei 3 sistemi (vault + Convergio + repo).
# Meccanizza il sync a fine task: rigenera i wrapper dal canone e committa un
# `chore(sync)` SE qualcosa è cambiato. Non blocca mai (exit 0). Non pusha mai.
#
# OPT-IN: attivo solo con RDA_AUTOSYNC=1 — un auto-commit su ogni Stop è invasivo
# come default. Senza il flag, esce subito (no-op).
set -u

[ "${RDA_AUTOSYNC:-0}" = "1" ] || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

# Agisce solo dentro roberdan-os (presenza di AGENTS.md + bin/sync.sh canonici).
[ -f "$repo_root/AGENTS.md" ] && [ -f "$repo_root/bin/sync.sh" ] || exit 0

changed=""

# 1) Rigenera i wrapper per-platform dal canone (idempotente, dry-run-safe).
if [ -x "$repo_root/bin/sync.sh" ]; then
  "$repo_root/bin/sync.sh" --emit-only >/dev/null 2>&1 || true
fi

# 2) Privacy gate prima di qualsiasi commit di sync.
if [ -x "$repo_root/test/leak-check.sh" ]; then
  if ! "$repo_root/test/leak-check.sh" >/dev/null 2>&1; then
    printf "\n[post-task-sync] LEAK rilevato — sync abortito, nessun commit.\n" >&2
    exit 0
  fi
fi

# 3) Commit chore(sync) solo se il working tree (escluso private/) ha derivati cambiati.
if [ -n "$(git status --porcelain -- . ':!:private/**' 2>/dev/null | head -1)" ]; then
  git add -- platforms/ 2>/dev/null || true
  if [ -n "$(git diff --cached --name-only 2>/dev/null | head -1)" ]; then
    git commit -q -m "chore(sync): rigenera wrapper per-platform dal canone" 2>/dev/null || true
    changed="yes"
  fi
fi

[ -n "$changed" ] && printf "\n[post-task-sync] wrapper rigenerati e committati (chore sync).\n" >&2
exit 0
