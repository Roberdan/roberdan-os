#!/usr/bin/env bash
# test-pending-digest-avvisa.sh — bin/pending-digest.sh MUST notify through Avvisa (tools/avvisa)
# and NEVER through osascript/AppleScript "display notification". A notification attributed to
# "Editor di script"/Terminal is the exact bug Avvisa exists to fix (tools/README.md § avvisa);
# regressing to osascript here would silently recreate it on every scheduled run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# Minimal fake kanban so `kb pending` returns a deterministic non-zero count without touching
# the real board.
mkdir -p "$TMP/kanban"
cat > "$TMP/kanban/kb.sh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = pending ]; then
  echo "2 card in attesa"
  echo "PENDING: 2"
fi
SH
chmod +x "$TMP/kanban/kb.sh"

# Stub twin-shadow.sh and system-health.sh as inert no-ops: this test is about the notification
# channel, not those subsystems.
cat > "$TMP/twin-shadow.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = agreement ] && echo "Twin — accordo con Roberto: non disponibile"
exit 0
SH
chmod +x "$TMP/twin-shadow.sh"
cat > "$TMP/system-health.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/system-health.sh"

export RDA_HOME="$TMP/home"
export RDA_KB="$TMP/kanban/kb.sh"
export RDA_TWIN_SHADOW="$TMP/twin-shadow.sh"
export RDA_HEALTH_CMD="$TMP/system-health.sh"
export RDA_HEALTH_REPORTS_DIR="$TMP/home/reports"

run_digest() {
  bash "$ROOT/bin/pending-digest.sh" "$@"
}

# --- 1. no osascript INVOCATION anywhere on this source path (comments may still name it to
# explain why it's avoided, but no line may call it or build an AppleScript command string). ---
grep -n 'osascript' "$ROOT/bin/pending-digest.sh" | grep -v '^[0-9]*:# ' && fail "osascript invoked outside a comment in pending-digest.sh"
grep -q 'with title' "$ROOT/bin/pending-digest.sh" && fail "AppleScript 'display notification ... with title' syntax still present"
ok "pending-digest.sh source has no osascript invocation / AppleScript syntax (mention-only comments allowed)"

# Make sure a real osascript on PATH is never reached even if present: put a tripwire binary
# ahead of it that fails loudly if invoked.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/osascript" <<'SH'
#!/usr/bin/env bash
echo "TRIPWIRE: osascript invoked" >> "$OSASCRIPT_CALLS"
exit 0
SH
chmod +x "$TMP/bin/osascript"
export OSASCRIPT_CALLS="$TMP/osascript-calls"
: > "$OSASCRIPT_CALLS"

# --- 2. Avvisa present: called with argv (no shell interpretation of the message) ------------
AVVISA_CALLS="$TMP/avvisa-calls"
export AVVISA_CALLS
# One argv item per line, call terminated by a sentinel — proves each argument arrived as a
# distinct argv entry (not reassembled by a shell from one interpolated string).
cat > "$TMP/bin/avvisa" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a" >> "$AVVISA_CALLS"; done
printf '===CALL_END===\n' >> "$AVVISA_CALLS"
exit 0
SH
chmod +x "$TMP/bin/avvisa"

out="$(PATH="$TMP/bin:$PATH" run_digest --always 2>&1)" || fail "pending-digest.sh exited non-zero with Avvisa present: $out"
[ -s "$AVVISA_CALLS" ] || fail "avvisa was never invoked"
[ -s "$OSASCRIPT_CALLS" ] && fail "osascript tripwire fired while avvisa was available"
call=()
while IFS= read -r line; do
  [ "$line" = "===CALL_END===" ] && break
  call+=("$line")
done < "$AVVISA_CALLS"
# argv must be exactly: --titolo <title> --testo <message> — a literal, argument-safe call,
# never a string handed to a shell/AppleScript interpreter.
[ "${call[0]:-}" = "--titolo" ] || fail "first avvisa arg is not --titolo: ${call[*]}"
[ "${call[2]:-}" = "--testo" ]  || fail "third avvisa arg is not --testo: ${call[*]}"
[[ "${call[3]:-}" == *"kb pending"* ]] || fail "avvisa message missing expected content: ${call[*]}"
grep -q 'display notification' "$AVVISA_CALLS" && fail "AppleScript syntax leaked into avvisa argv"
echo "$out" | grep -q 'notified' || fail "digest did not report a notified pending count"
ok "Avvisa present → called with direct argv (--titolo/--testo), no osascript, no AppleScript syntax"

# --- 3. Avvisa absent: skip with a visible warning, never fall back to osascript -------------
: > "$AVVISA_CALLS"
: > "$OSASCRIPT_CALLS"
out="$(PATH="$TMP/bin-without-avvisa:$PATH" RDA_AVVISA_CMD=avvisa-not-installed run_digest --always 2>&1)" || fail "pending-digest.sh exited non-zero with Avvisa absent: $out"
[ -s "$OSASCRIPT_CALLS" ] && fail "osascript tripwire fired when Avvisa was absent (silent fallback regression)"
echo "$out" | grep -qi 'avvisa non disponibile' || fail "missing repository-standard warning when Avvisa is absent: $out"
ok "Avvisa absent → visible warning, notification skipped, no osascript fallback"

echo "PASS: test-pending-digest-avvisa.sh"
