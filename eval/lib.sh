#!/usr/bin/env bash
# eval/lib.sh — shared helpers for the eval/ harness (run-eval.sh, judge.sh, report.sh).
# Sourced, not executed. Mirrors the parsing/resolution conventions already established in
# factory/run.sh (frontmatter/field parsing, claude binary resolution, billing safety,
# timeout resolution) so the eval harness doesn't invent a second dialect for the same problem.

# --- frontmatter / field / section parsing (task fixtures use YAML frontmatter + ## headers) --
frontmatter() { sed -n '/^---$/,/^---$/p' "$1"; }
field() { frontmatter "$1" | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '"' || true; }

# section FILE "## Header" — prints the lines between a literal "## Header" line and the next
# "## " line (or EOF), trimmed of a single leading/trailing blank line. Task fixtures are
# structured as "## Prompt" / "## Canon-compliant checklist" / "## Naive-default risk".
section() {
  local file="$1" header="$2"
  awk -v h="$header" '
    $0==h { flag=1; next }
    /^## / && flag { flag=0 }
    flag { buf[++n]=$0 }
    END {
      start=1; end=n
      while (start<=end && buf[start]=="") start++
      while (end>=start && buf[end]=="") end--
      for (i=start; i<=end; i++) print buf[i]
    }
  ' "$file"
}

# --- claude binary resolution (identical pattern to factory/run.sh) ------------------------
# In --stub mode the caller (a test harness, see eval/test-eval-pipeline.sh) is expected to
# have already prepended a temp bin/ dir with a fake `claude` script onto PATH, exactly the
# way test/test-factory-kb.sh stubs factory/run.sh. --stub does not change resolution itself —
# it only relaxes the FATAL exit into a clearer message and stamps a "STUB MODE" banner into
# saved outputs so nobody mistakes a stub run for a real one.
eval_resolve_claude() {
  local c
  c="$(command -v claude 2>/dev/null || true)"
  if [ -z "$c" ] || [ ! -x "$c" ]; then
    for p in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude "$HOME/.bun/bin/claude" /usr/local/bin/claude; do
      [ -x "$p" ] && { c="$p"; break; }
    done
  fi
  printf '%s' "$c"
}

# BILLING SAFETY — identical rationale to factory/run.sh: in `-p` headless mode an
# ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN env var is ALWAYS used for per-token API billing.
# Unset both before every invocation so auth falls through to the Max subscription OAuth.
eval_unset_billing_env() {
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
}

# --- agent command override (tool-independence) ---------------------------------------------
# By default the harness drives headless Claude Code exactly like factory/run.sh:
# `claude -p "$prompt" --dangerously-skip-permissions --add-dir "$ROOT"`. That hardcodes the
# eval to one tool, which contradicts the tool-independence goal of the rest of this system
# (AGENTS.md is meant to work with any coding agent). Set RDA_EVAL_AGENT_CMD to point the
# harness at a different headless agent CLI instead, e.g.:
#   RDA_EVAL_AGENT_CMD="copilot -p"        eval/run-eval.sh
#   RDA_EVAL_AGENT_CMD="hermes chat -z"    eval/run-eval.sh
#
# CONVENTION (read before setting it):
#   - RDA_EVAL_AGENT_CMD is the FULL command: binary + any fixed flags, whitespace-split (no
#     quoting/escaping support — keep flags simple, one token each).
#   - The prompt is delivered over STDIN, never appended as a trailing CLI argument. Stdin was
#     chosen over "prompt as last arg" for two reasons: (1) it works across CLIs with unrelated
#     flag dialects without this harness having to learn each tool's prompt-flag name, as long as
#     the tool reads a prompt from stdin when invoked non-interactively (true of `copilot -p` and
#     `hermes chat -z` per their own docs); (2) condition B prompts embed a full canon file
#     (tens of KB) — stdin has no argv-length ceiling, a single CLI argument can.
#   - claude-specific flags (--dangerously-skip-permissions, --add-dir) are NEVER passed when
#     RDA_EVAL_AGENT_CMD is set — they are meaningless (or actively wrong) for a different tool.
#     The override is a fully separate invocation path, not the claude path with flags swapped.
#   - When RDA_EVAL_AGENT_CMD is unset, behavior is byte-for-byte unchanged: the default
#     `eval_resolve_claude` binary, `-p "$prompt"` as a CLI arg, same flags as before.
eval_agent_configured() {
  [ -n "${RDA_EVAL_AGENT_CMD:-}" ]
}

# eval_invoke_agent PROMPT OUTFILE ROOT TIMEOUT_S TIMEOUT_BIN CLAUDE_BIN
# Runs exactly one headless agent call, writing raw stdout+stderr to OUTFILE, returning the
# invoked process's exit code. Centralizes the RDA_EVAL_AGENT_CMD branch so run-eval.sh and
# judge.sh share one invocation path instead of each reimplementing it.
eval_invoke_agent() {
  local prompt="$1" outfile="$2" root="$3" timeout_s="$4" timeout_bin="$5" claude_bin="$6"
  local rc=0
  set +e
  if eval_agent_configured; then
    # shellcheck disable=SC2086  # RDA_EVAL_AGENT_CMD is intentionally whitespace-split — see the
    # documented convention above; it's a trusted local override, not untrusted input.
    if [ -n "$timeout_bin" ]; then
      printf '%s' "$prompt" | "$timeout_bin" "$timeout_s" $RDA_EVAL_AGENT_CMD > "$outfile" 2>&1
    else
      printf '%s' "$prompt" | $RDA_EVAL_AGENT_CMD > "$outfile" 2>&1
    fi
  else
    if [ -n "$timeout_bin" ]; then
      "$timeout_bin" "$timeout_s" "$claude_bin" -p "$prompt" --dangerously-skip-permissions --add-dir "$root" > "$outfile" 2>&1
    else
      "$claude_bin" -p "$prompt" --dangerously-skip-permissions --add-dir "$root" > "$outfile" 2>&1
    fi
  fi
  rc=$?
  set -e
  return $rc
}

eval_resolve_timeout() {
  local t
  t="$(command -v timeout 2>/dev/null || true)"
  if [ -z "$t" ] || [ ! -x "$t" ]; then
    for p in /opt/homebrew/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/timeout /usr/local/bin/gtimeout; do
      [ -x "$p" ] && { t="$p"; break; }
    done
  fi
  printf '%s' "$t"
}

# eval_strip_banner FILE — drops the leading "<!-- eval condition=... -->" banner (+ the blank
# line after it) that run-eval.sh stamps onto a.md/b.md for humans reading the raw output files.
# MUST be used before handing a.md/b.md content to the judge — the banner literally says
# "condition=A" / "condition=B", which would defeat blind judging if passed through verbatim.
eval_strip_banner() {
  awk '
    BEGIN { skipping = 1 }
    skipping && ($0 ~ /^<!--/ || $0 == "") { next }
    { skipping = 0; print }
  ' "$1"
}

# extract_json FILE — prints the first well-formed JSON object found in FILE (fenced ```json
# block preferred, bare {...} as fallback) as compact single-line JSON. Exits 1 if none parses.
# Used by judge.sh (to sanity-check the judge's own output before saving it) and report.sh (to
# aggregate verdicts). Uses python3 (already a dependency of test/leak-check.sh — not a new one).
extract_json() {
  python3 - "$1" <<'PY'
import sys, re, json
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()
m = re.search(r"```json\s*(\{.*?\})\s*```", text, re.S)
if not m:
    m = re.search(r"(\{.*\})", text, re.S)
if not m:
    sys.exit(1)
try:
    obj = json.loads(m.group(1))
except Exception:
    sys.exit(1)
print(json.dumps(obj))
PY
}
