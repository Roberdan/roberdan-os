#!/usr/bin/env bash
# bin/check-embedder.sh — verifies the local-first bge-m3 embedder is actually intact.
#
# Why this exists: gbrain's config (`~/.gbrain/config.json`) declares
# `embedding_model: ollama:bge-m3`, but the CODE that recognizes "bge-m3" as a valid
# Ollama model lives in a local fork (github.com/Roberdan/gbrain, commit f7376b11) — NOT
# upstream (github.com/garrytan/gbrain). The running binary is a bun-global install of the
# npm package `gbrain` (`~/.bun/bin/gbrain` -> .../node_modules/gbrain/src/cli.ts), which
# is a SEPARATE artifact from the fork's git history. An upgrade that pulls from the
# published package instead of the fork silently drops the patch: the config would still
# say bge-m3, but the code would no longer recognize it — a silent embedding failure,
# which is the worst kind of failure for a memory system (recall degrades with no error).
#
# This script does NOT modify anything — it only verifies and reports.
set -euo pipefail

CONFIG="$HOME/.gbrain/config.json"
INSTALLED="$HOME/.bun/install/global/node_modules/gbrain/src/core/ai/recipes/ollama.ts"
FORK_COMMIT="f7376b11"
FORK_REMOTE="https://github.com/Roberdan/gbrain.git"

fail=0

echo "=== gbrain embedder durability check ==="

if [ ! -f "$CONFIG" ]; then
  echo "SKIP: $CONFIG not found — gbrain not installed on this machine."
  exit 0
fi

configured="$(grep -o '"embedding_model"[^,}]*' "$CONFIG" | head -1)"
echo "config declares: $configured"
case "$configured" in
  *bge-m3*) echo "  ok: config expects bge-m3" ;;
  *) echo "  WARN: config does not mention bge-m3 — expected if you intentionally switched embedders."; fail=1 ;;
esac

if [ -f "$INSTALLED" ]; then
  if grep -qi "bge-m3\|bge_m3" "$INSTALLED"; then
    echo "  ok: installed gbrain package recognizes bge-m3 ($INSTALLED)"
  else
    echo "  FAIL: installed gbrain package does NOT recognize bge-m3 — the patch was lost,"
    echo "        likely by an upgrade that pulled from the published package instead of"
    echo "        the fork. Config says bge-m3 but the code will silently fail to embed."
    echo "        Recovery: reinstall from the fork ($FORK_REMOTE, commit $FORK_COMMIT+)"
    echo "        or re-apply that commit's diff to the installed package."
    fail=1
  fi
else
  echo "  WARN: could not find $INSTALLED — installed package layout may have changed."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "check-embedder: OK — bge-m3 patch intact."
else
  echo "check-embedder: ATTENTION NEEDED — see warnings above."
fi
exit "$fail"
