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
