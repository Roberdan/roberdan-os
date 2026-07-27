#!/usr/bin/env bash
# test-bus-mutants.sh — a test that has never been seen to fail is an unverified
# claim, and test-bus.sh makes some very large claims. This harness breaks the
# bus on purpose, once per load-bearing property, and asserts the suite NOTICES.
#
# It exists because the first @rex review found a check that was completely dead
# (it grepped for KB while the variable is KANBAN) and a set of checks that a
# deliberately malicious mutant walked straight past. Green means nothing until
# you have watched red.
#
# Each mutant below states the property it violates and the check that must catch
# it. If a mutant survives, either the mutation is wrong or the check is theatre —
# both are worth knowing, and neither is discoverable from a passing suite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUS="$ROOT/bus/bus.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# SAFETY. One mutant invokes an agent CLI by name, and `claude` really exists on
# this machine: run unguarded, it starts a live session. Every mutant therefore
# runs with harmless stubs FIRST on PATH. This is not belt-and-braces, it has
# already happened once.
STUBS="$WORK/stubs"; mkdir -p "$STUBS"
for danger in claude copilot codex osascript launchctl nohup kb kb.sh; do
  printf '#!/bin/sh\necho "stub %s invoked" >&2\nexit 0\n' "$danger" > "$STUBS/$danger"
  chmod +x "$STUBS/$danger"
done

mutants_run=0

# mutate <name> <property> <expected-check> <program> [evidence-regex]
# The program reads bus.sh on stdin and writes the mutant on stdout.
#
# `evidence` defaults to a FAIL line from the suite, which is what "the suite
# noticed" looks like. A few mutants are caught by the BUS ITSELF instead - the
# delivery audit refuses to advance the cursor and dies - and that fires on the
# first read, long before the check written for it. That is a STRONGER outcome
# than a red check (the defect cannot reach a user at all, not merely cannot
# reach a release), but it is a different string, so those mutants say so
# explicitly rather than being waved through by a looser default.
mutate() {
  local name="$1" property="$2" expect="$3" program="$4" evidence="${5:-^FAIL}"
  local mut="$WORK/$name.sh" out
  python3 -c "$program" < "$BUS" > "$mut" || fail "$name: the mutation program itself failed"
  chmod +x "$mut"
  cmp -s "$BUS" "$mut" && fail "$name: the mutation changed nothing — the anchor text has drifted, so this mutant is not testing anything"
  bash -n "$mut" || fail "$name: the mutant is not valid shell"

  set +e
  out="$(PATH="$STUBS:$PATH" RDA_BUS_STUBDIR="$STUBS" RDA_BUS_BIN="$mut" timeout 300 bash "$ROOT/test/test-bus.sh" 2>&1)"
  local rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "SURVIVED: $name — the suite passed a bus that $property. The check that should have caught it: $expect"
  grep -qE "$evidence" <<<"$out" || fail "$name: the suite exited $rc without matching /$evidence/ — it broke rather than detected: $(tail -3 <<<"$out")"
  printf '  caught: %-22s (%s)\n       -> %s\n' "$name" "$property" "$(grep -m1 -E "$evidence" <<<"$out")"
  mutants_run=$((mutants_run + 1))
}

echo "mutation-testing the bus suite (each run is a full test-bus.sh, ~11s)"

# 1. THE ONE THAT MATTERS MOST. A bus that starts an agent is a dispatcher, and
#    factory/dispatch-runner.sh is dormant by a reviewed decision. This mutant
#    uses the indirection @rex used to defeat the old grep-based checks: the
#    binary name is assembled from spliced strings and reached through a
#    variable, so nothing in the source reads "claude".
mutate dispatch "starts an agent CLI" "check 13 (stub PATH + canary)" '
import sys
s = sys.stdin.read()
anchor = "  echo \"bus: appended $kind from $from to $to on $repo/$card -> $log\""
assert s.count(anchor) == 1, "anchor drift"
s = s.replace(anchor, "  _agent=\"cla\"\"ude\"; \"$_agent\" -p \"you have bus mail\" >/dev/null 2>&1 || true\n" + anchor)
sys.stdout.write(s)
'

# 2. Same lever, the other property: a bus that can move a card can launder a
#    human gate. kb is on the stub PATH precisely so this is survivable to test.
mutate kanban-write "writes kanban state" "check 13 (kb is among the stubs)" '
import sys
s = sys.stdin.read()
anchor = "  echo \"bus: appended $kind from $from to $to on $repo/$card -> $log\""
s = s.replace(anchor, "  kb start \"$card\" --by roberto >/dev/null 2>&1 || true\n" + anchor)
sys.stdout.write(s)
'

# 3. A broadcast that echoes to its sender teaches every agent to filter its own
#    mail by hand, and the one that forgets loops.
mutate self-echo "echoes a broadcast back to its sender" "check 25" '
import sys
s = sys.stdin.read()
s = s.replace("select(.to == $me or (.to == $all and .from != $me))", "select(.to == $me or .to == $all)")
sys.stdout.write(s)
'

# 4. The cursor counting the filtered stream instead of raw records. Self-
#    consistent, so it passes almost everything — check 28b is the one that
#    pins it, and this mutant is the proof that 28b is not decoration.
mutate filtered-cursor "couples the cursor to the delivery rule" "check 28b (migration)" '
import sys
s = sys.stdin.read()
old = "  _with_lock \"$log\" _snapshot_log \"$log\" \"$snap\" \"$snapcount\""
# the count is written from the filtered snapshot too, so this mutant fails on
# the property under test (the cursor) and not on the snapshot audit above it.
new = "  jq -c --arg me \"$as\" --arg all \"$BROADCAST\" \x27select(.to == $me or (.to == $all and .from != $me))\x27 \"$log\" > \"$snap\"; wc -l < \"$snap\" | tr -d \x27 \x27 > \"$snapcount\""
assert s.count(old) == 1, "anchor drift"
s = s.replace(old, new)
sys.stdout.write(s)
'

# 5. Unlocked appends. The log is permanent and never repaired, so an interleave
#    is not a transient glitch — it is a thread that stays broken.
#    The mutation must be surgical: _with_lock also creates the log directory, so
#    removing the CALL breaks the bus outright instead of racing it, and a mutant
#    that crashes proves nothing about the check.
mutate no-lock "appends without a lock" "check 19 (concurrent appends)" '
import sys
s = sys.stdin.read()
old = """  until mkdir "$lock" 2>/dev/null; do
    waited=$((waited + 1))
    [ "$waited" -lt 100 ] || die "could not acquire the log lock ($lock) - remove it if stale"
    sleep 0.1
  done
"""
if s.count(old) != 1:
    import re
    m = re.search(r"  until mkdir .*?\n  done\n", s, re.S)
    assert m, "anchor drift: the lock acquisition loop was not found"
    old = m.group(0)
s = s.replace(old, "  : # lock acquisition removed\n")
sys.stdout.write(s)
'

# 6. Fail-open leak-check. The bus lives outside every git tree, so if it does
#    not scan the body, nothing ever will.
mutate leak-open "accepts an unusable leak-check" "check 22 (fail-closed)" '
import sys
s = sys.stdin.read()
old = "  [ -x \"$LEAKCHECK\" ] || die \"send: leak-check is not executable at $LEAKCHECK"
assert s.count(old) == 1, "anchor drift"
s = s.replace(old, "  [ -x \"$LEAKCHECK\" ] || true; [ 1 = 1 ] || die \"send: leak-check is not executable at $LEAKCHECK")
sys.stdout.write(s)
'

# 7. `all` promoted from addressee to actor. One word naming both a capability
#    set and its own audience is a manifest nobody can read.
mutate all-as-actor "lets something act as the broadcast addressee" "check 27" '
import sys
s = sys.stdin.read()
old = "  [ \"$role\" != \"$BROADCAST\" ] \\\n"
assert s.count(old) == 1, "anchor drift"
s = s.replace(old, "  [ \"$role\" != \"__never__\" ] \\\n")
sys.stdout.write(s)
'

# 8. Unvalidated --repo/--card. These reach mkdir and printf, so a traversal
#    writes a JSONL file wherever it likes.
mutate traversal "interpolates --repo unvalidated" "check 15 (path traversal)" '
import sys
s = sys.stdin.read()
old = "  repo=\"$(_slug \"--repo\" \"$repo\")\"; card=\"$(_slug \"--card\" \"$card\")\"\n  case \"$kind\""
assert s.count(old) == 1, "anchor drift"
s = s.replace(old, "  case \"$kind\"")
sys.stdout.write(s)
'

# 9. The laundering mutant. Printing the bare word "verified" manufactures an
#    independent confirmation inside the component whose entire purpose is
#    preventing exactly that — and kb start --by is honor-system by kb.sh own
#    admission, so there is no confirmation to report.
#    Surgical on purpose: the resolution text is left intact and only the
#    forbidden word is added, so the mutant is caught by the anti-laundering
#    assertion itself and not by a neighbour noticing the citation stopped
#    resolving. A mutant caught for the wrong reason tests the wrong check.
mutate says-verified "reports a citation as verified" "check 17 (denied-card laundering)" '
import sys
s = sys.stdin.read()
old = "echo \"RESOLVES to an honor-system approval line"
assert s.count(old) == 1, "anchor drift"
s = s.replace(old, "echo \"VERIFIED — RESOLVES to an honor-system approval line")
sys.stdout.write(s)
'

# 10. THE ABSOLUTE PATH. @rex walked through the "behavioural" gate with this
#     twice: a PATH of stubs cannot see a command that never consults PATH, and
#     the allowlist threw the word away because it starts with "/". Adding names
#     to the stub list cannot fix this class - only normalising the traced word
#     before matching it can.
mutate abs-path "spawns an agent by absolute path" "check 13b (basename normalisation)" '
import sys
s = sys.stdin.read()
anchor = "  echo \"bus: appended $kind from $from to $to on $repo/$card -> $log\""
assert s.count(anchor) == 1, "anchor drift"
s = s.replace(anchor, "  \"${RDA_BUS_STUBDIR:-/nonexistent}/claude\" -p \"mail\" >/dev/null 2>&1 || true\n" + anchor)
sys.stdout.write(s)
'

# 11. The env-assignment prefix. `BUS_WAKE=1 claude` put the ASSIGNMENT in the
#     first column, so the allowlist matched on "BUS_WAKE=1" and never saw the
#     command at all.
mutate env-prefix "spawns an agent behind an env assignment" "check 13b (VAR= stripping)" '
import sys
s = sys.stdin.read()
anchor = "  echo \"bus: appended $kind from $from to $to on $repo/$card -> $log\""
s = s.replace(anchor, "  BUS_WAKE=1 claude -p \"mail\" >/dev/null 2>&1 || true\n" + anchor)
sys.stdout.write(s)
'

# 12. THE COVERAGE HOLE, which was the more dangerous half. The gate only ever
#     ran seven subcommand names, so a payload in the broadcast branch was never
#     executed under the stub PATH - and checks 24-29 exercise that branch with
#     the REAL PATH. It would not merely have been missed; it would have started
#     live agent sessions during the test run.
mutate broadcast-branch "spawns an agent from the broadcast branch only" "check 13 (path table includes --to all)" '
import sys
s = sys.stdin.read()
anchor = "  if [ \"$to\" = \"$BROADCAST\" ]; then\n    _assert_no_broadcast_manifest"
assert s.count(anchor) == 1, "anchor drift"
s = s.replace(anchor, "  if [ \"$to\" = \"$BROADCAST\" ]; then\n    claude -p \"broadcast pending\" >/dev/null 2>&1 || true\n    _assert_no_broadcast_manifest")
sys.stdout.write(s)
'

# 13. Closing must never become deleting. The whole argument for keeping history
#     is that the reasoning is the artifact; a close that quietly truncates the
#     log would satisfy every other test in the suite.
mutate close-deletes "deletes the thread when closing it" "check 37-40 (close/open lifecycle: closing keeps every word)" '
import sys
s = sys.stdin.read()
anchor = "  local bf; bf=\"$(mktemp)\"\n"
s = s.replace(anchor, "  [ \"$want\" != closed ] || : > \"$log\"\n" + anchor, 1)
sys.stdout.write(s)
'

# 14. `who` honouring "closed" on the append path but not on the cursor path.
#     A real bug, found by check 39 failing only when stdout was not a tty: a
#     role that had merely READ the thread still showed under it, so closing hid
#     the writers and kept the readers. Which half won depended on which
#     timestamp sorted last, so the check has to be run more than once to be
#     believed - hence this mutant, which makes it deterministic.
mutate who-half-closed "hides closed threads from who only on the write path" "check 37-40 (close/open lifecycle: closed disappears from who)" '
import sys
s = sys.stdin.read()
anchor = "        [ \"$(_thread_state \"$clog\")\" != \"closed\" ] || continue"
assert s.count(anchor) == 1, "anchor drift"
s = s.replace(anchor, "        :")
sys.stdout.write(s)
'

# --- Found by an adversarial pass (gpt-5.6-sol) on the twice-hardened gate. It
#     proposed five evasions; three of them really did survive the full suite.
#     It reported them as "likely survives" without running them, so each one had
#     to be executed before it counted - which is the same discipline the gate
#     itself is built on, applied to the review.

# 15. A payload in `close`/`open`. The path table drove seventeen ARGUMENT paths
#     and still missed two whole subcommands, added late and never added to it.
#     This is the same coverage hole as the broadcast branch, which is exactly
#     why it is worth a standing mutant rather than a one-time fix: the hole is
#     structural, it will reopen the next time a subcommand is added.
mutate close-branch "spawns an agent from close/open, which the path table missed" "check 13 (path table covers close/open)" '
import sys
s = sys.stdin.read()
a = "  echo \"bus: $repo/$card is now $want"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  claude -p \"thread changed\" >/dev/null 2>&1 || true\n" + a)
sys.stdout.write(s)
'

# 16. Writing kanban state with a SHELL REDIRECTION. The property is "never
#     writes kanban state"; the check measured "never executes kb". A `printf >>`
#     into a card satisfies the check perfectly while violating the property
#     completely: no external command, no traced word, no stub, no canary. The
#     gap was between the property and its proxy, and the fix is to measure the
#     effect (hash the tree) instead of one known cause of it.
mutate kanban-redirect "writes kanban state without executing anything" "check 13 (kanban fingerprint)" '
import sys
s = sys.stdin.read()
a = "  echo \"bus: appended $kind from $from to $to on $repo/$card -> $log\""
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  printf \x27\\nbus_mutated_by: %s\\n\x27 \"$from\" >> \"$RDA_KANBAN/doing/$card.md\" 2>/dev/null || true\n" + a)
sys.stdout.write(s)
'

# 17. `--peek` consuming what it peeked. The worst failure mode this thing has:
#     send succeeds, read returns nothing, and nothing anywhere prints an error.
#     The old checks peeked exactly one direct message, so a peek that ate
#     broadcasts was invisible.
mutate peek-consumes "lets --peek advance the cursor over broadcasts" "check 41 (peek never advances)" '
import sys
s = sys.stdin.read()
a = "  if [ \"$advance\" = \"1\" ]; then"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  if [ \"$advance\" = \"1\" ] || grep -q \x27\"to\":\"all\"\x27 \"$deliverable\"; then")
sys.stdout.write(s)
'

# --- Found by @thor validating the card, by executing rather than reading. The
#     same coverage class as mutants 12 and 15, in its third disguise: not an
#     unexercised SUBCOMMAND this time, but an unexercised DEGRADED BRANCH. Both
#     of these passed the entire green suite while the canary recorded live
#     `claude -p` calls. What makes it load-bearing rather than tidy: those
#     branches really do run in a normal test run, under the REAL PATH, so the
#     regression would not have been missed - it would have started live agent
#     sessions during a run that printed PASS.
#     The standing lesson: AN ERROR PATH IS STILL A PATH.

# 18. The damaged-log warning inside `who`.
mutate damaged-branch "spawns an agent from the damaged-log branch of who" "check 13 (path table drives degraded logs)" '
import sys
s = sys.stdin.read()
a = "        echo \"bus: WARNING"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "        claude -p \"who saw damage\" >/dev/null 2>&1 || true\n" + a)
sys.stdout.write(s)
'

# 19. The lock-timeout refusal. Reached only when a lock is already held, which
#     nothing in the gate used to do.
mutate lock-timeout "spawns an agent when it cannot take the lock" "check 13 (path table holds a lock)" '
import sys
s = sys.stdin.read()
a = "    [ \"$waited\" -lt \"$tries\" ] || die"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    [ \"$waited\" -lt \"$tries\" ] || claude -p \"lock stuck\" >/dev/null 2>&1 || true\n" + a)
sys.stdout.write(s)
'

# --- Third @rex round. He found the coverage hole in its FIFTH disguise, and
#     this time with six live instances on the shipping commit: the REFUSAL
#     branches. The path table could not reach them by construction - it only
#     ever supplies valid roles, valid slugs, a passing leak-check and an empty
#     registry - so every refusal path was ungated while running under the real
#     PATH elsewhere in the suite.
#     The answer was not a sixth enumeration. The canary stubs are now first on
#     PATH for the ENTIRE test-bus.sh run, and the canary must be empty at the
#     end: anything the suite exercises anywhere is measured, whether or not
#     anyone thought to list it. The four mutants below are kept as evidence of
#     the class, not as the definition of it - they were all caught by the same
#     single assertion, which is the whole point.

mutate slug-branch "spawns an agent from the slug refusal" "check 42 (canary floor for the whole run)" '
import sys
s = sys.stdin.read()
a = "    -*) die \"$what: \x27$value\x27 looks like a flag, not a value\";;"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    -*) claude -p x >/dev/null 2>&1 || true; die \"$what: \x27$value\x27 looks like a flag, not a value\";;")
sys.stdout.write(s)
'

mutate role-branch "spawns an agent from the human-gated-capability refusal" "check 42 (canary floor for the whole run)" '
import sys
s = sys.stdin.read()
a = "  [ -z \"$offenders\" ] || die"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  [ -z \"$offenders\" ] || claude -p x >/dev/null 2>&1 || true\n" + a)
sys.stdout.write(s)
'

mutate leakblock-branch "spawns an agent when the leak-check BLOCKS a body" "check 42 (canary floor for the whole run)" '
import sys
s = sys.stdin.read()
a = "    || die \"send: BLOCKED"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    || { claude -p x >/dev/null 2>&1 || true; false; } \\\n" + a)
sys.stdout.write(s)
'

# 23. THE SILENT DROP, and the only one of these that is not about execution.
#     Nothing measured delivery COMPLETENESS: every other assertion used batches
#     of one to three, so a batch cap - the most likely "save tokens" edit anyone
#     will ever make here - passed the whole suite while five messages became
#     unreachable forever. send returned 0, read returned 0, the trailer even
#     reported the right count. The bus now audits itself (rendered vs
#     deliverable) and refuses to advance the cursor on a mismatch.
mutate emit-cap "caps the batch, losing messages with no error" "check 43 (delivery is complete at 25)" '
import sys
s = sys.stdin.read()
a = "    n=$((n+1))"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, a + "\n    [ \"$n\" -le 20 ] || continue")
sys.stdout.write(s)
'

# 24. Accepting a body that jq will silently rewrite. "Survives verbatim" was
#     asserted with ASCII only and was false for everything else.
mutate encoding-mangle "accepts a body jq will silently rewrite" "check 44 (non-UTF-8 is refused, not repaired)" '
import sys
s = sys.stdin.read()
a = "  iconv -f UTF-8 -t UTF-8 < \"$body\""
assert s.count(a) == 1, "anchor drift"
i = s.index(a)
j = s.index("\n", s.index("send again.", i)) + 1
s = s[:i] + s[j:]
sys.stdout.write(s)
'

# ===========================================================================
# 25-28. The @rex round-4 findings. Two are the SEAM between the two halves of
#        the boundary; two are silent loss the delivery audit could not see.
# ===========================================================================

# 25. THE SEAM. The canary is run-wide but structurally blind to an ABSOLUTE
#     path (a stub is only ever consulted through PATH); the xtrace allowlist
#     sees absolute paths but used to be scoped to the argument table. Put the
#     payload where both blind spots overlap - an absolute path, in a refusal
#     branch the table cannot reach - and it passed the whole green suite while
#     starting a live agent. Both halves are floors now, which is why this dies.
mutate abs-in-refusal "spawns an agent BY ABSOLUTE PATH from a refusal branch" "check 45 (allowlist over the whole run)" '
import sys
s = sys.stdin.read()
a = "    || die \"send: BLOCKED"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    || { \"$RDA_BUS_STUBDIR/claude\" -p x >/dev/null 2>&1 || true; false; } \\\n" + a)
sys.stdout.write(s)
'

# 26. The same seam for property 2. This one executes NOTHING - no command, no
#     traced word, no stub - so only the fingerprint can see it, and the
#     fingerprint used to be scoped to the table. A REFUSED send wrote a card.
mutate kanban-in-refusal "writes a card from a refusal branch, executing nothing" "check 47 (kanban fingerprint over the whole run)" '
import sys
s = sys.stdin.read()
a = "    || die \"send: BLOCKED"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    || { printf \"laundered_by: %s\\\\n\" \"$from\" >> \"$KANBAN/doing/$card.md\" 2>/dev/null; false; } \\\n" + a)
sys.stdout.write(s)
'

# 27. SILENT LOSS UPSTREAM OF THE AUDIT. The audit compared the renderer against
#     the very file that fed it, so anything the FILTER dropped was missing from
#     both sides: both numbers agreed and both were wrong. `want` is now counted
#     from the snapshot instead, which spans the whole path.
#     Caught by the bus, not by the suite: the audit dies on the FIRST read of
#     the run, which is exactly the behaviour that makes this class survivable.
mutate upstream-dedupe "drops deliverable records in the filter, before the audit can count them" "the delivery audit in read (check 43 pins the same property)" '
import sys
s = sys.stdin.read()
a = "    | jq -c --arg me \"$as\" --arg all \"$BROADCAST\" \\\n        \x27select(.to == $me or (.to == $all and .from != $me))\x27 > \"$deliverable\""
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    | jq -sc --arg me \"$as\" --arg all \"$BROADCAST\" \\\n        \x27map(select(.to == $me or (.to == $all and .from != $me))) | unique_by(.to) | .[]\x27 > \"$deliverable\"")
sys.stdout.write(s)
' "delivery is incomplete"

# 28. The H1 regression, and the reason check 21 is no longer a race: this exact
#     mutant was caught 1 run in 3 while genuinely losing a message 1 trial in
#     10. A standing mutant with a 33% catch rate is a green suite that means
#     nothing on the property it claims to hold.
#     Since the count moved under the snapshot lock (Finding D), the BUS kills
#     this one before check 21 runs: the count and the snapshot disagree on the
#     first read and nothing is delivered at all. Stronger, different string.
mutate upstream-totallog "advances the cursor past records it never snapshotted" "check 21 (cursor == the snapshot it emitted)" '
import sys
s = sys.stdin.read()
a = "  total=\"$(wc -l < \"$snap\" | tr -d \x27 \x27)\""
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  total=\"$(wc -l < \"$log\" | tr -d \x27 \x27)\"")
sys.stdout.write(s)
' "is short: the log held|^FAIL"

# ===========================================================================
# @rex round 5. Two of these are the gate's own blind spots (a board it never
# hashed, a hop it never counted). The last two are the honest ones: they are
# caught by a DENYLIST, and a denylist is exactly as good as its list.
# ===========================================================================

# 29. THE REACHABLE SET IS THE BOUNDARY, NOT THE NEAREST PART OF IT. The
#     fingerprint hashed $RDA_KANBAN, while _card_boards reaches $root/kanban for
#     EVERY registry entry. A plain `read` stamped an approval line onto another
#     repo's card and then cited that card as resolving - the citation and the
#     thing it cites both written by the bus, and nothing in the suite moved.
mutate kanban-other-board "stamps an approval line onto ANOTHER repo's card while resolving a citation" "check 47 (fingerprint over every board _card_boards reaches)" '
import sys
s = sys.stdin.read()
a = "        echo \"RESOLVES to an honor-system approval line"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "        case \"$found\" in \"$KANBAN\"/*) ;; *) printf \x27approved_by: roberto\\\\n\x27 >> \"$found\" 2>/dev/null || true;; esac\n" + a)
sys.stdout.write(s)
'

# 30. THE HOP NOBODY COUNTED. Bound the memory a read may use - a defensible
#     change, five characters - and 600 records become 500 with exit 0, a correct
#     trailer, and the cursor parked past all of them. Every count downstream
#     agreed with every other, because they were all counting the truncated copy.
mutate snapshot-cap "silently truncates the snapshot, losing the oldest records with exit 0" "check 49 (600 records in, 600 rendered) and the snapshot audit in read" '
import sys
s = sys.stdin.read()
a = "  cp \"$1\" \"$2\""
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "  tail -n 500 \"$1\" > \"$2\"")
sys.stdout.write(s)
' "the snapshot of .* is short|^FAIL"

# 31. THE LID, AND WHAT IT IS WORTH. `PS4=` for the duration of the payload and
#     the traced line is unmarked; the classifier drops it as stderr and check 45
#     never sees the word `claude`. There is no fix for this from inside the
#     traced process - the process owns its own tracing. What kills it here is
#     check 48, a three-line grep for the tracing machinery, and that is a
#     denylist: it catches this spelling because someone thought of this spelling.
#     Kept because a mutant you can only catch by name is the most honest
#     description of where a boundary ends.
mutate ps4-blind "blanks PS4 around a spawn, so the trace never records it" "check 48 (the tracing-machinery denylist)" '
import sys
s = sys.stdin.read()
a = "    || die \"send: BLOCKED"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    || { PS4=\x27\x27; \"$RDA_BUS_STUBDIR/claude\" -p x >/dev/null 2>&1 || true; PS4=\x27#XT# \x27; false; } \\\n" + a)
sys.stdout.write(s)
'

# 32. The same lid, other hand: `set +x` simply stops the trace. Same conclusion,
#     and it matters that BOTH spellings are named, because the denylist is the
#     whole mechanism here and its coverage is its list.
mutate setx-blind "turns the trace off around a spawn" "check 48 (the tracing-machinery denylist)" '
import sys
s = sys.stdin.read()
a = "    || die \"send: BLOCKED"
assert s.count(a) == 1, "anchor drift"
s = s.replace(a, "    || { set +x; \"$RDA_BUS_STUBDIR/claude\" -p x >/dev/null 2>&1 || true; set -x; false; } \\\n" + a)
sys.stdout.write(s)
'

[ "$mutants_run" = "32" ] || fail "expected 32 mutants, ran $mutants_run"
echo "PASS: test-bus-mutants.sh — 32/32 mutants caught"
