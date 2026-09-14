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
check_full '{"source":"startup","prompt_cache_likely_expired":false}' "startup + warm-cache field present -> still full block (only resume/fork may go terse)"
check_full '{"source":"compact"}' "compact -> full block"
check_full '{"source":"resume","prompt_cache_likely_expired":true}' "resume + expired cache -> full block"
check_full '{"source":"resume"}' "resume, field absent -> full block (safe fallback)"
check_full 'not json at all' "unparseable stdin -> full block (fail-safe)"

echo "=== the authorized queue is re-photographed for a NEW session only (2026-09-14) ==="
# The defect: the first photo lived forever (roberdan-os: 2026-07-30, all closed), so goal-gate
# never held anyone. Runs the real hook against a throwaway HOME + board, never the real one.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.local/bin" "$T/board/todo" "$T/board/doing" "$T/board/done"
ln -s "$ROOT/kanban/kb.sh" "$T/home/.local/bin/kb"
git -C "$T" init -q ciq 2>/dev/null
card() { printf -- '---\ntitle: card %s\nrepo: ciq\ndod: "d"\nacceptance: "a"\nstatus: todo\ncreated: 2026-09-14\n---\n' "$1" > "$T/board/todo/$1.md"; }
inject() { (cd "$T/ciq" && unset RDA_HEADLESS RDA_IN_THOR_VERIFY && printf '%s' "$1" | HOME="$T/home" RDA_KANBAN="$T/board" RDA_KANBAN_REGISTRY="$T/reg" bash "$HOOK" >/dev/null 2>&1); }
inq() { grep -qx "$1" "$T/board/.coda-ciq.md" 2>/dev/null; }
card Q1
inject '{"session_id":"s1","source":"startup"}'
inq Q1 && ok "Claude startup with a session id -> photo taken" || err "Claude startup took no photo"
card Q2
inject '{"session_id":"s1","source":"compact"}'
inq Q2 && err "compact re-photographed: a card born mid-session would start" || ok "compact keeps the session's photo"
inject '{"session_id":"s2","source":"resume"}'
inq Q2 && err "resume re-photographed" || ok "resume keeps the photo"
inject ''
inq Q2 && err "empty stdin (no session id) re-photographed" || ok "empty stdin keeps the photo (no id, no renewal)"
inject '{"session_id":"s3","source":"startup"}'
inq Q2 && ok "a NEW Claude session re-photographs: the card born before it enters" || err "new Claude session kept the stale photo (the 2026-07-30 defect)"
card Q3
inject '{"session_id":"cp-9","source":"new"}'
inq Q3 && ok "Copilot-shaped start (sessionId + source new) re-photographs too" || err "Copilot new session kept the stale photo"
card Q4
inject '{"session_id":"cp-9","source":"resume"}'
inq Q4 && err "Copilot resume re-photographed" || ok "Copilot resume keeps the photo"
card Q5
(cd "$T/ciq" && printf '%s' '{"session_id":"hl-1","source":"startup"}' | HOME="$T/home" RDA_KANBAN="$T/board" RDA_KANBAN_REGISTRY="$T/reg" RDA_HEADLESS=1 bash "$HOOK" >/dev/null 2>&1)
inq Q5 && err "a headless run (factory/@thor) re-photographed the queue" || ok "a headless run (RDA_HEADLESS=1) never touches the queue photo"
# (that the real Copilot extension SENDS this shape is asserted in test-copilot-adapter.sh § G2)

if [ "$fails" -eq 0 ]; then printf '\ntest-context-inject-staleness: ✅ ALL GREEN\n'; else printf '\ntest-context-inject-staleness: ❌ FAIL (see above)\n'; fi
exit "$fails"
