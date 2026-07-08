#!/usr/bin/env bash
# bin/check-embedder.sh — verifies the local-first bge-m3 embedder is actually intact.
#
# As of 2026-07-08 gbrain runs the OFFICIAL upstream (github.com/garrytan/gbrain) — NO fork.
# The old fork (Roberdan/gbrain, commit f7376b11) added bge-m3 to the ollama recipe with 2
# lines; that patch is no longer needed: the config declares `embedding_dimensions: 1024`
# explicitly, and upstream respects the declared dims, so `ollama:bge-m3` embeds fine without
# any code change (proven empirically: search + embed both produce 1024-dim vectors).
#
# So this check no longer looks for a code patch. It verifies the three things that actually
# keep local-first recall working, any of which a bad upgrade/config could break:
#   1. config declares ollama:bge-m3 + embedding_dimensions 1024
#   2. ollama is up and serves bge-m3 at 1024 dims (the OpenAI-compat endpoint)
#   3. the gbrain clone tracks ONLY the official remote (no fork remote crept back)
# It does NOT modify anything — only verifies and reports.
set -uo pipefail

CONFIG="$HOME/.gbrain/config.json"
CLONE="$HOME/gbrain"
fail=0

echo "=== gbrain embedder durability check (official upstream, config-driven bge-m3) ==="

if [ ! -f "$CONFIG" ]; then
  echo "SKIP: $CONFIG not found — gbrain not installed on this machine."
  exit 0
fi

# 1) config: bge-m3 + 1024 dims
if grep -q '"embedding_model"[^,}]*bge-m3' "$CONFIG"; then echo "  ok: config declares ollama:bge-m3"
else echo "  WARN: config does not declare bge-m3 (fine only if you intentionally switched embedders)"; fail=1; fi
if grep -qE '"embedding_dimensions"[[:space:]]*:[[:space:]]*1024' "$CONFIG"; then echo "  ok: config declares embedding_dimensions 1024"
else echo "  FAIL: config lacks 'embedding_dimensions: 1024' — without it the official upstream falls back"
     echo "        to a wrong default and rejects bge-m3 at embed-time (silent recall failure)."; fail=1; fi

# 2) ollama serves bge-m3 at 1024 via the OpenAI-compatible endpoint
dims="$(curl -s http://localhost:11434/v1/embeddings -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","input":"check"}' 2>/dev/null \
  | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data'][0]['embedding']))" 2>/dev/null || echo "")"
if [ "$dims" = "1024" ]; then echo "  ok: ollama serves bge-m3 at 1024 dims"
else echo "  FAIL: ollama did not return a 1024-dim bge-m3 embedding (got '${dims:-none}')."
     echo "        Is ollama running and is bge-m3 pulled? \`ollama pull bge-m3\`"; fail=1; fi

# 3) the clone tracks ONLY the official remote (no fork)
if [ -d "$CLONE/.git" ]; then
  if git -C "$CLONE" remote -v 2>/dev/null | grep -qi 'Roberdan/gbrain'; then
    echo "  FAIL: the gbrain clone still has a FORK remote (Roberdan/gbrain) — should track only"
    echo "        the official garrytan/gbrain. Remove it: git -C $CLONE remote remove fork"; fail=1
  else echo "  ok: gbrain clone tracks only the official upstream (no fork remote)"; fi
  if grep -qi 'bge-m3' "$CLONE/src/core/ai/recipes/ollama.ts" 2>/dev/null; then
    echo "  note: the running code contains a bge-m3 line — you're on a patched/fork checkout, not"
    echo "        the pure official. Not broken, but the goal is official + config-only."
  fi
else
  echo "  WARN: gbrain clone not found at $CLONE — skipping remote check."
fi

if [ "$fail" -eq 0 ]; then echo "check-embedder: OK — local-first bge-m3 intact on official upstream (config-driven)."
else echo "check-embedder: ATTENTION NEEDED — see warnings above."; fi
exit "$fail"
