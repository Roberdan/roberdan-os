#!/usr/bin/env bash
# test/test-factory-kb.sh — real assertions for the kanban gates + factory guardrails.
# factory and kb.sh are the most autonomous components of roberdan-os and were previously
# only smoke-tested; the 2026-07-01 silent factory failure (exit 127 tasks filed as done/)
# proved that was not enough. Uses temp dirs (RDA_KANBAN, RDA_FACTORY) — never touches the
# real board or queue.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
section "kb gate: todo->doing needs human approval"
KB="$TMP/kanban"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
cat > "$KB/todo/probe.md" <<'EOF'
---
title: probe card
dod: "real dod"
acceptance: "real acceptance"
status: todo
created: 2026-07-01
---
body
EOF

if RDA_KANBAN="$KB" bash kanban/kb.sh start probe >/dev/null 2>&1; then
  err "kb start without --by was ACCEPTED (should be refused: human gate)"
else
  ok "kb start without --by refused"
fi
[ -e "$KB/todo/probe.md" ] && [ ! -e "$KB/doing/probe.md" ] \
  && ok "card stayed in todo/ after refused start" \
  || err "card moved despite refused start"

section "kb gate: start refuses cards with unfilled DoD/acceptance"
cat > "$KB/todo/unfilled.md" <<'EOF'
---
title: unfilled card
dod: "FILL: definition of done"
acceptance: "real acceptance"
status: todo
created: 2026-07-01
---
body
EOF
if RDA_KANBAN="$KB" bash kanban/kb.sh start unfilled --by roberto >/dev/null 2>&1; then
  err "kb start accepted a card with FILL: placeholder in dod"
else
  ok "kb start refuses unfilled DoD"
fi

section "kb gate: doing->done needs @thor + evidence"
RDA_KANBAN="$KB" bash kanban/kb.sh start probe --by roberto >/dev/null 2>&1
[ -e "$KB/doing/probe.md" ] || err "setup: probe card did not reach doing/ via a valid start"
if RDA_KANBAN="$KB" bash kanban/kb.sh finish probe >/dev/null 2>&1; then
  err "kb finish without --thor was ACCEPTED (should be refused)"
else
  ok "kb finish without --thor refused"
fi
[ -e "$KB/doing/probe.md" ] && [ ! -e "$KB/done/probe.md" ] \
  && ok "card stayed in doing/ after refused finish" \
  || err "card moved despite refused finish"

if RDA_KANBAN="$KB" bash kanban/kb.sh finish probe --thor "test evidence" >/dev/null 2>&1 \
  && [ -e "$KB/done/probe.md" ]; then
  ok "kb finish with --thor evidence moves card to done/"
else
  err "kb finish with valid evidence did not complete"
fi

section "kb show/edit: nonexistent id reports an error instead of dying silently"
# Regression test: under `set -euo pipefail`, `ls nonexistent 2>/dev/null | head -1`
# still propagates ls's exit code through the pipe, killing the script before it can
# print "no card <id>" — found empirically while writing this suite.
out="$(RDA_KANBAN="$KB" bash kanban/kb.sh show does-not-exist-xyz 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no card'; then
  ok "kb show <missing-id> prints an error and exits non-zero"
else
  err "kb show <missing-id> did not report the expected error (got rc=$rc, out=$out)"
fi

section "kb block: marks a card blocked and returns it to todo/"
cat > "$KB/doing/inflight.md" <<'EOF'
---
title: inflight card
dod: "real dod"
acceptance: "real acceptance"
status: doing
approved_by: roberto
created: 2026-07-01
---
body
EOF
if RDA_KANBAN="$KB" bash kanban/kb.sh block inflight "stuck on external dependency" >/dev/null 2>&1 \
  && [ -e "$KB/todo/inflight.md" ] && grep -q '^status: blocked' "$KB/todo/inflight.md" \
  && grep -q 'blocked_reason:' "$KB/todo/inflight.md"; then
  ok "kb block moves the card to todo/ with status+reason recorded"
else
  err "kb block did not produce the expected state"
fi

# ---------------------------------------------------------------------------
# The two checks below started as `grep` on factory/run.sh source text — that only proves the
# line exists, not that it works (e.g. a bug that wraps `unset ...` in a subshell would still
# match the grep while silently breaking the guard for the actual child process). Verified this
# empirically while writing these tests: a broken subshell version still passed the grep-only
# check. Replaced with runtime assertions using a fake `claude` that reports what it actually saw.
section "factory: billing guard is real (child process never sees the API-key env vars)"
FAC5="$TMP/factory-billing"; mkdir -p "$FAC5/queue" "$FAC5/bin"
cat > "$FAC5/bin/claude" <<'EOF'
#!/usr/bin/env bash
env > "${CAPTURE_ENV:?}"
exit 0
EOF
chmod +x "$FAC5/bin/claude"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe\n' "$TMP" > "$FAC5/queue/billing.md"
CAPENV="$TMP/billing-env.txt"
env -i PATH="$FAC5/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC5" RDA_HANDOFF=/dev/null \
  ANTHROPIC_API_KEY="probe-should-be-stripped" ANTHROPIC_AUTH_TOKEN="probe-should-be-stripped" \
  CAPTURE_ENV="$CAPENV" \
  bash factory/run.sh >/dev/null 2>&1
if [ -f "$CAPENV" ] && ! grep -qE '^ANTHROPIC_(API_KEY|AUTH_TOKEN)=' "$CAPENV"; then
  ok "billing guard verified at runtime: the child process env has no ANTHROPIC_API_KEY/AUTH_TOKEN"
else
  err "the child process COULD SEE ANTHROPIC_API_KEY/AUTH_TOKEN — billing guard is broken"
fi

section "factory: context-primer content actually reaches the prompt sent to claude"
FAC6="$TMP/factory-primer"; mkdir -p "$FAC6/queue" "$FAC6/bin"
cat > "$FAC6/bin/claude" <<'EOF'
#!/usr/bin/env bash
# invoked as: claude -p "<prompt>" --dangerously-skip-permissions --add-dir <dir>
printf '%s' "$2" > "${CAPTURE_PROMPT:?}"
exit 0
EOF
chmod +x "$FAC6/bin/claude"
PRIMER_FILE="$TMP/fake-primer.md"
echo "SENTINEL-PRIMER-MARKER-98214" > "$PRIMER_FILE"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe task body\n' "$TMP" > "$FAC6/queue/primer.md"
CAPPROMPT="$TMP/received-prompt.txt"
env -i PATH="$FAC6/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC6" RDA_HANDOFF=/dev/null RDA_PRIMER="$PRIMER_FILE" \
  CAPTURE_PROMPT="$CAPPROMPT" \
  bash factory/run.sh >/dev/null 2>&1
if [ -f "$CAPPROMPT" ] && grep -q "SENTINEL-PRIMER-MARKER-98214" "$CAPPROMPT" \
  && grep -q "probe task body" "$CAPPROMPT"; then
  ok "primer content + task body both verified present in the actual prompt sent to claude -p"
else
  err "primer sentinel and/or task body missing from the prompt actually passed to claude -p"
fi

# ---------------------------------------------------------------------------
section "factory: a failing task never lands in done/ (regression test for the 2026-07-01 bug)"
FAC="$TMP/factory"
mkdir -p "$FAC/queue" "$FAC/bin"
cat > "$FAC/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 5
EOF
chmod +x "$FAC/bin/claude"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe task\n' "$TMP" > "$FAC/queue/failer.md"

# minimal, launchd-like PATH: no alias, no interactive shell config
env -i PATH="$FAC/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
env -i PATH="$FAC/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1

if [ -z "$(ls -A "$FAC/done" 2>/dev/null)" ]; then
  ok "a failing task was never filed under done/"
else
  err "a failing task ended up in done/ — the 2026-07-01 bug regressed"
fi
if ls "$FAC/failed"/*.md >/dev/null 2>&1 && grep -q 'escalate: true' "$FAC/failed"/*.md; then
  ok "a task that exhausts retries lands in failed/ with escalate: true"
else
  err "no task reached failed/ with escalate: true after exhausting retries"
fi

section "factory: a succeeding task lands in done/"
FAC2="$TMP/factory-ok"
mkdir -p "$FAC2/queue" "$FAC2/bin"
cat > "$FAC2/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAC2/bin/claude"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe task\n' "$TMP" > "$FAC2/queue/succeeder.md"
env -i PATH="$FAC2/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC2" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if ls "$FAC2/done"/*.md >/dev/null 2>&1; then
  ok "a succeeding task lands in done/"
else
  err "a succeeding task did not reach done/"
fi

section "factory: card: field syncs the result back onto the kanban card"
FAC4="$TMP/factory-sync"; KB4="$TMP/kanban-sync"
mkdir -p "$FAC4/queue" "$FAC4/bin" "$KB4/doing"
cat > "$FAC4/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAC4/bin/claude"
cat > "$KB4/doing/probe-sync.md" <<'EOF'
---
title: probe sync card
dod: "real dod"
acceptance: "real acceptance"
status: doing
approved_by: roberto
created: 2026-07-01
---
body
EOF
printf -- '---\ndir: %s\ntimeout: 5\ncard: probe-sync\n---\nprobe task\n' "$TMP" > "$FAC4/queue/synced.md"
env -i PATH="$FAC4/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC4" RDA_KANBAN="$KB4" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if grep -q 'factory_result:' "$KB4/doing/probe-sync.md" 2>/dev/null; then
  ok "factory result synced onto the referenced kanban card"
else
  err "card: field did not sync a factory_result: line onto the kanban card"
fi

# ---------------------------------------------------------------------------
# Phase 6: a factory exit 0 only proves the process didn't crash, not that the card's
# DoD/acceptance was met — factory/run.sh now runs a second headless pass embodying @thor
# whenever a task exits 0 AND declares `card:`. These three cases exercise: PASS verdict,
# FAIL verdict (routed through the existing retry/failed path), and no `card:` at all (no
# verification triggered). The stub `claude` distinguishes the thor-verify call from the
# main task call by inspecting the prompt text ($2) for the thor-verify marker.
section "factory: card + thor-verify PASS -> done/ with a PASSED annotation on the card"
FAC7="$TMP/factory-verify-pass"; KB7="$TMP/kanban-verify-pass"
mkdir -p "$FAC7/queue" "$FAC7/bin" "$KB7/doing"
cat > "$FAC7/bin/claude" <<'EOF'
#!/usr/bin/env bash
# invoked as: claude -p "<prompt>" --dangerously-skip-permissions --add-dir <dir>
case "$2" in
  *"You are acting as @thor"*) echo "VERDICT: PASS — files exist, tests pass" ;;
esac
exit 0
EOF
chmod +x "$FAC7/bin/claude"
cat > "$KB7/doing/verify-pass.md" <<'EOF'
---
title: verify pass card
dod: "real dod"
acceptance: "real acceptance"
status: doing
approved_by: roberto
created: 2026-07-01
---
body
EOF
printf -- '---\ndir: %s\ntimeout: 5\ncard: verify-pass\n---\nprobe task\n' "$TMP" > "$FAC7/queue/verifypass.md"
env -i PATH="$FAC7/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC7" RDA_KANBAN="$KB7" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if ls "$FAC7/done"/*.md >/dev/null 2>&1 \
  && grep -q 'headless thor pass PASSED' "$KB7/doing/verify-pass.md" 2>/dev/null \
  && ls "$FAC7/logs"/*-thor-verify.log >/dev/null 2>&1; then
  ok "task with card + thor-verify PASS lands in done/ and the card is annotated PASSED"
else
  err "task with card + thor-verify PASS did not land in done/ with a PASSED annotation"
fi

section "factory: card + thor-verify FAIL -> routed through the existing failure path"
FAC8="$TMP/factory-verify-fail"; KB8="$TMP/kanban-verify-fail"
mkdir -p "$FAC8/queue" "$FAC8/bin" "$KB8/doing"
cat > "$FAC8/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  *"You are acting as @thor"*) echo "VERDICT: FAIL — acceptance criteria not met, no test output found" ;;
esac
exit 0
EOF
chmod +x "$FAC8/bin/claude"
cat > "$KB8/doing/verify-fail.md" <<'EOF'
---
title: verify fail card
dod: "real dod"
acceptance: "real acceptance"
status: doing
approved_by: roberto
created: 2026-07-01
---
body
EOF
printf -- '---\ndir: %s\ntimeout: 5\ncard: verify-fail\n---\nprobe task\n' "$TMP" > "$FAC8/queue/verifyfail.md"
# Two runs, same as the "failing task" regression test above: attempt 1 retries,
# attempt 2 exhausts MAX_ATTEMPTS=2 into failed/.
env -i PATH="$FAC8/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC8" RDA_KANBAN="$KB8" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
env -i PATH="$FAC8/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC8" RDA_KANBAN="$KB8" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if [ -z "$(ls -A "$FAC8/done" 2>/dev/null)" ] \
  && ls "$FAC8/failed"/*.md >/dev/null 2>&1 && grep -q 'escalate: true' "$FAC8/failed"/*.md \
  && grep -q 'thor-verify FAILED' "$KB8/doing/verify-fail.md" 2>/dev/null; then
  ok "card + thor-verify FAIL never lands in done/, exhausts retries into failed/ with escalate:true, card annotated"
else
  err "card + thor-verify FAIL was not routed through the existing failure path correctly"
fi

section "factory: task WITHOUT card: skips verification entirely"
FAC9="$TMP/factory-no-card"
mkdir -p "$FAC9/queue" "$FAC9/bin"
cat > "$FAC9/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  *"You are acting as @thor"*) echo "VERDICT: FAIL — should never be invoked for a cardless task" ;;
esac
exit 0
EOF
chmod +x "$FAC9/bin/claude"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe task, no card\n' "$TMP" > "$FAC9/queue/nocard.md"
env -i PATH="$FAC9/bin:/usr/bin:/bin" HOME="$HOME" \
  RDA_FACTORY="$FAC9" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if ls "$FAC9/done"/*.md >/dev/null 2>&1 \
  && [ -z "$(ls "$FAC9/logs"/*-thor-verify.log 2>/dev/null)" ]; then
  ok "task without card: lands in done/ with no thor-verify pass triggered (no verify log written)"
else
  err "task without card: either failed to complete or triggered an unwanted verification pass"
fi

section "factory: claude binary resolved even without the interactive alias in PATH"
FAC3="$TMP/factory-resolve"
mkdir -p "$FAC3/queue" "$FAC3/home/.local/bin"
cat > "$FAC3/home/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAC3/home/.local/bin/claude"
printf -- '---\ndir: %s\ntimeout: 5\n---\nprobe task\n' "$TMP" > "$FAC3/queue/resolveme.md"
# PATH deliberately excludes the .local/bin dir; only HOME is set, exercising the fallback lookup
env -i PATH="/usr/bin:/bin" HOME="$FAC3/home" \
  RDA_FACTORY="$FAC3" RDA_HANDOFF=/dev/null \
  bash factory/run.sh >/dev/null 2>&1
if ls "$FAC3/done"/*.md >/dev/null 2>&1; then
  ok "claude binary resolved via the \$HOME/.local/bin fallback (no PATH, no alias)"
else
  err "claude binary was not resolved via the fallback lookup"
fi

# ---------------------------------------------------------------------------
printf "\n"
if [ "$FAIL" -eq 0 ]; then echo "test-factory-kb: ✅ ALL GREEN"; exit 0; else echo "test-factory-kb: ❌ FAIL (see above)"; exit 1; fi
