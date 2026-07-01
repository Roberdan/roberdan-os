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
section "factory: billing guard (no API-key billing on the Max plan)"
if grep -q 'unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN' factory/run.sh; then
  ok "factory/run.sh unsets ANTHROPIC_API_KEY/ANTHROPIC_AUTH_TOKEN"
else
  err "factory/run.sh does not unset the API-key env vars"
fi

section "factory: context-primer injection"
if grep -q 'context-primer.md' factory/run.sh; then
  ok "factory/run.sh references handoff/context-primer.md"
else
  err "factory/run.sh does not inject the context-primer"
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
if [ "$FAIL" -eq 0 ]; then echo "test-factory-kb: ✅ TUTTO VERDE"; exit 0; else echo "test-factory-kb: ❌ FAIL (vedi sopra)"; exit 1; fi
