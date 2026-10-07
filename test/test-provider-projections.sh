#!/usr/bin/env bash
# Provider projections must carry the canon's early safety contract verbatim.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
ok() { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"
KERNEL="$TMP/kernel"

awk '/<!-- safety-kernel:begin -->/{f=1;next} /<!-- safety-kernel:end -->/{exit} f' \
  AGENTS.md > "$KERNEL"

[ -s "$KERNEL" ] && ok "canon safety kernel is non-empty" || err "canon safety kernel missing"

first_gate_byte="$(LC_ALL=C grep -abo '^## Safety kernel' AGENTS.md | head -1 | cut -d: -f1)"
[ -n "$first_gate_byte" ] && [ "$first_gate_byte" -lt 4096 ] \
  && ok "root safety kernel begins inside first 4 KiB" \
  || err "root safety kernel is too late (${first_gate_byte:-missing})"

if grep -q 'gstack-gbrain-search-guidance' AGENTS.md; then
  err "vendor-owned gstack marker still writes the canon"
else
  ok "canon has no vendor-owned gstack marker"
fi

RDA_SYNC_OUT="$OUT" bash bin/sync.sh --emit-only >/dev/null 2>&1

for projection in "$OUT/copilot/copilot-instructions.md" "$OUT/codex/AGENTS.md"; do
  if python3 - "$KERNEL" "$projection" <<'PY'
import sys
kernel = open(sys.argv[1], encoding="utf-8").read().strip()
projection = open(sys.argv[2], encoding="utf-8").read()
raise SystemExit(0 if kernel in projection else 1)
PY
  then
    ok "${projection#$OUT/} contains the verbatim safety kernel"
  else
    err "${projection#$OUT/} drifted from the canon safety kernel"
  fi
done

codex_bytes="$(wc -c < "$OUT/codex/AGENTS.md" | tr -d ' ')"
[ "$codex_bytes" -le 28672 ] \
  && ok "Codex projection stays below 28 KiB ($codex_bytes bytes)" \
  || err "Codex projection exceeds 28 KiB ($codex_bytes bytes)"

[ "$FAIL" -eq 0 ] && { echo "test-provider-projections: PASS"; exit 0; }
echo "test-provider-projections: FAIL"
exit 1
