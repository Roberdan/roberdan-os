#!/usr/bin/env bash
# test-bus-doorbell.sh — the hook may RING, it may never DELIVER, and it may
# never wake anything.
#
# The doorbell is the only piece of this system that pushes anything into a
# model's context on its own, so it gets its own gate. Three properties, and the
# third is the one nobody would notice was broken:
#
#   1. It never renders a body and never advances a cursor - the mail it
#      announces must still be there, unread, stamped UNVERIFIED, when `read`
#      finally runs.
#   2. It is SILENT at zero. It fires on every tool call, so a single line
#      printed with no mail waiting is a line paid on every tool call forever.
#   3. It speaks the ONE dialect the model can hear. For PostToolUse, Claude Code
#      writes stdout to the debug log and the model never sees it; only
#      `hookSpecificOutput.additionalContext` on valid JSON is injected next to
#      the tool result. A doorbell wired with `echo` is a doorbell nobody hears,
#      and it is indistinguishable from a working one by eye - which is exactly
#      why it is asserted here instead of trusted.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/bus-doorbell.sh"
BUS="$ROOT/bus/bus.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export RDA_BUS_HOME="$TMP/bus"
export TMPDIR="$TMP/stamps"          # the doorbell's ring-once stamp lives here
mkdir -p "$RDA_BUS_HOME" "$TMPDIR"

# A repo the hook will derive from cwd: it is the directory NAME, so the fixture
# has to be a directory, not a string.
REPO=doorbell-repo
WORK="$TMP/$REPO"; mkdir -p "$WORK"

BODY="DOORBELL-TEST-BODY-MUST-NOT-LEAK-a7c2"
echo "$BODY" | bash "$BUS" send --repo "$REPO" --card d1 \
  --from sol-gate --to implementer --kind verdict >/dev/null \
  || fail "could not seed the thread"

payload() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse"}' "$1" "$WORK"; }

# --- 1. it rings, in the dialect the model can hear -------------------------
out="$(payload s1 | bash "$HOOK" 2>/dev/null)" || fail "the hook exited non-zero with mail waiting"
[ -n "$out" ] || fail "the hook stayed silent while a message was unread"
jq -e . <<<"$out" >/dev/null 2>&1 || fail "the hook did not emit valid JSON — stdout alone is invisible to the model on PostToolUse"
[ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" = "PostToolUse" ] \
  || fail "the JSON does not name the PostToolUse event, so nothing is injected"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
[ -n "$ctx" ] && [ "$ctx" != "null" ] \
  || fail "additionalContext is empty — this is the ONLY field the model actually sees"
grep -q "d1" <<<"$ctx" || fail "the ring does not say which card has mail"
grep -q "bus read" <<<"$ctx" || fail "the ring does not say how to actually read the mail"

# --- 2. it rings, it does not deliver ---------------------------------------
grep -q "$BODY" <<<"$out" \
  && fail "THE HOOK LEAKED A BODY into the model's context, unstamped and unattributed"
[ ! -e "$RDA_BUS_HOME/$REPO/.cursor/d1/implementer" ] \
  || fail "the hook advanced a cursor: it consumed the mail it announced"
delivered="$(bash "$BUS" read --repo "$REPO" --card d1 --as implementer)"
grep -q "$BODY" <<<"$delivered" || fail "the announced message was gone by the time read ran"
grep -q "UNVERIFIED" <<<"$delivered" || fail "the message lost its provenance stamp"

# --- 3. silent at zero ------------------------------------------------------
quiet="$(payload s-zero | bash "$HOOK" 2>/dev/null)"
[ -z "$quiet" ] || fail "the hook printed something with no unread mail: $quiet"
# ...and silent for a directory the bus has never heard of. This is the case that
# runs on essentially every tool call of every session on this machine.
NOWHERE="$TMP/not-a-bus-repo"; mkdir -p "$NOWHERE"
none="$(printf '{"session_id":"s3","cwd":"%s"}' "$NOWHERE" | bash "$HOOK" 2>/dev/null)"
[ -z "$none" ] || fail "the hook printed something for a repo with no traffic at all: $none"

# --- 4. ring ONCE per change, not on every tool call ------------------------
# The naive version compares the log against the cursor, which stays true until
# somebody reads: that rings on every single tool call until then, which is how a
# useful signal becomes noise everybody filters out.
echo "another one" | bash "$BUS" send --repo "$REPO" --card d1 \
  --from sol-gate --to implementer >/dev/null
first="$(payload s4 | bash "$HOOK" 2>/dev/null)"
[ -n "$first" ] || fail "the hook did not ring for a NEW message"
second="$(payload s4 | bash "$HOOK" 2>/dev/null)"
if [ -n "$second" ]; then
  # TEMPORARY (2026-07-30): this assertion passes on macOS and failed on
  # ubuntu-latest, and three hypotheses about why were wrong. Rather than guess a
  # fourth, print the state the hook decides on. Remove once the cause is fixed.
  echo "--- diagnostica: perche' ha suonato due volte ---" >&2
  echo "stamp dir: $TMPDIR/rda-bus-doorbell" >&2
  ls -la "$TMPDIR/rda-bus-doorbell" 2>&1 >&2 || true
  for s in "$TMPDIR/rda-bus-doorbell"/*; do
    [ -e "$s" ] || continue
    echo "stamp $s:" >&2; cat -A "$s" >&2 2>/dev/null || true
  done
  echo "file che entrano nella firma:" >&2
  ls -la "$RDA_BUS_HOME/$REPO"/*.jsonl "$RDA_BUS_HOME/$REPO"/.cursor/*/* 2>&1 >&2 || true
  echo "stat -c disponibile? $(stat -c '%Y' . 2>/dev/null || echo no)" >&2
  echo "stat -f su un file: $(stat -f '%m %z %N' "$RDA_BUS_HOME/$REPO/d1.jsonl" 2>&1 | head -1)" >&2
  echo "esito stat -f: $?" >&2
  fail "the hook rang twice for the same unchanged state — it is a level, not an edge"
fi
# A different session has its own stamp: it has not been told yet.
other="$(payload s5 | bash "$HOOK" 2>/dev/null)"
[ -n "$other" ] || fail "a second session inherited the first session's silence"

# --- 5. it starts nothing ---------------------------------------------------
# Same lever as test-bus.sh: stub agent CLIs first on PATH, each dropping a
# canary when invoked. The hook runs on every tool call, so a payload here would
# fire more often than anywhere else in the system.
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
CANARY="$TMP/canary-outside-the-blast-radius"; : > "$CANARY"
for c in claude copilot codex osascript launchctl nohup kb kb.sh; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$CANARY" > "$STUBS/$c"
  chmod +x "$STUBS/$c"
done
echo "third" | bash "$BUS" send --repo "$REPO" --card d1 --from sol-gate --to implementer >/dev/null
PATH="$STUBS:$PATH" payload s6 | PATH="$STUBS:$PATH" bash "$HOOK" >/dev/null 2>&1 || true
[ ! -s "$CANARY" ] \
  || fail "the doorbell EXECUTED an agent CLI or kb: $(tr '\n' ' ' < "$CANARY")"

# --- 6. it is not wired anywhere that can continue a turn -------------------
# A Stop hook that surfaces pending mail is one edit away from "if a message is
# pending, continue the session" — the mutation bus-protocol.md names as the most
# likely and most dangerous. The generated settings snippet is where that would
# happen, so it is read here rather than trusted.
SNIP="$(sed -n '/settings-hooks\.json" <</,/^EOF$/p' "$ROOT/bin/sync.sh")"
grep -q "bus-doorbell" <<<"$SNIP" || fail "the doorbell is not wired into the generated hook snippet — an unwired hook is dead code that looks done"
python3 - "$ROOT/bin/sync.sh" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
snip = re.search(r"settings-hooks\.json\" <<'EOF'\n(.*?)\nEOF\n", src, re.S)
if not snip:
    print("FAIL: could not find the generated hook snippet in bin/sync.sh", file=sys.stderr); sys.exit(1)
import json
cfg = json.loads(snip.group(1).replace("$RDA_OS", "/RDA_OS"))
hooks = cfg["hooks"]
where = [ev for ev, groups in hooks.items()
         for g in groups for h in g.get("hooks", [])
         if "bus-doorbell" in h.get("command", "")]
if where != ["PostToolUse"]:
    print(f"FAIL: the doorbell is wired on {where}; it must be on PostToolUse and nowhere else "
          "(a Stop hook that surfaces mail can continue a turn)", file=sys.stderr); sys.exit(1)
PY

echo "PASS: test-bus-doorbell.sh"
