#!/usr/bin/env bash
# test-context-inject-staleness.sh — the SessionStart hook skips the full board on a fresh
# resume/fork (claude-code v2.1.251's prompt_cache_likely_expired field), and MUST fall back to
# the full block whenever that field is missing or unreadable — Copilot's emulated SessionStart
# chain calls this hook with EMPTY stdin (hooks/copilot/extension.template.mjs, onSessionStart:
# runScript(ci, "", ...)), so "no data" must never be read as "fresh".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/context-inject.sh"
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

first_line() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null | head -1; }

check_full() { # check_full <stdin-json-or-empty> <label>
  local l; l="$(first_line "$1")"
  [ "$l" = "## roberdan-os — session context (auto-injected)" ] && ok "$2" \
    || err "$2 (got: '$l')"
}
check_terse() { # check_terse <stdin-json> <label>
  local l; l="$(first_line "$1")"
  [ "$l" = "## roberdan-os — resumed, cache still warm (context unchanged since last turn)" ] && ok "$2" \
    || err "$2 (got: '$l')"
}

echo "=== the new case: fresh resume/fork skips the full block ==="
check_terse '{"source":"resume","prompt_cache_likely_expired":false}' "resume + warm cache -> one line"
check_terse '{"source":"fork","prompt_cache_likely_expired":false}'   "fork + warm cache -> one line"

echo "=== everything else still gets the full block, unconditionally ==="
check_full '' "Copilot's empty stdin -> full block (no data must never read as fresh)"
check_full '{"source":"startup"}' "startup -> full block"
check_full '{"source":"clear"}' "clear -> full block"
check_full '{"source":"compact"}' "compact -> full block"
check_full '{"source":"resume","prompt_cache_likely_expired":true}' "resume + expired cache -> full block"
check_full '{"source":"resume"}' "resume, field absent -> full block (safe fallback)"
check_full 'not json at all' "unparseable stdin -> full block (fail-safe)"

if [ "$fails" -eq 0 ]; then printf '\ntest-context-inject-staleness: ✅ ALL GREEN\n'; else printf '\ntest-context-inject-staleness: ❌ FAIL (see above)\n'; fi
exit "$fails"
