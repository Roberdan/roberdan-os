#!/usr/bin/env bash
# session-waste.sh — the "why", not the "how much". Reads the session traces THIS runtime
# already writes to disk (Copilot's ~/.copilot/session-state/*/events.jsonl) and flags a small
# set of recurring cost wastes, each with an ESTIMATED impact (labelled as such) and a concrete
# remedy. Zero setup, no network, no private data leaves the machine, nothing written back.
#
# Distilled from Uber Engineering's session-analysis lever: knowing how much you spent changes
# nothing; knowing WHY does. We flag 5 wastes, not 16 — only the ones the on-disk fields prove.
#
# SILENCE IS A FEATURE (kanban/README.md scar): a warning that always fires is noise you learn
# to skip, and the day it says something true nobody reads it. Clean sessions print nothing.
#
# The `-` principle (from kanban/dash.sh): never print a number we cannot derive from the trace.
# A detector whose fields are absent for a session is skipped for that session, not faked.
#
# Honest limits (see docs/USAGE.md § Session waste):
#   - Only Copilot events.jsonl is parsed. Claude (~/.claude/projects/**/*.jsonl) and Codex
#     traces carry per-turn usage but NOT the tool-schema / system-prompt token split this tool
#     leans on, so they are deliberately not analysed here rather than analysed with holes.
#   - Impacts are estimates in the trace's OWN units (tokens, nano-AIU, premium requests). No
#     dollar figure is printed — pricing is not in the trace. Cross-model savings are called out
#     as assumptions, never as a computed number.
set -uo pipefail

DIR="${RDA_SESSION_STATE:-$HOME/.copilot/session-state}"

usage() {
  cat <<'EOF'
session-waste.sh — flag recurring cost wastes in local session traces (Copilot).

Usage:
  session-waste.sh [--dir DIR]

  --dir DIR   Directory of session-state (default: ~/.copilot/session-state,
              or $RDA_SESSION_STATE). Also accepts a single events.jsonl file.
  --help      This help.

Silent when it finds nothing. Reads locally, sends nothing anywhere, writes nothing back.

Thresholds (env overrides, all optional):
  RDA_SW_LIGHT_TURNS=3      RDA_SW_LIGHT_OUTPUT=1500    (model-routing)
  RDA_SW_INIT_SHARE=0.6     RDA_SW_INIT_TURNS=2         (prompt-init overhead)
  RDA_SW_INIT_FLOOR=30000                               (min tool-schema tokens)
  RDA_SW_BLOAT_TOKENS=20000 RDA_SW_BLOAT_TURNS=8        (context bloat)
  RDA_SW_TTL=300  RDA_SW_COLD_GAP=1800  RDA_SW_COLD_GAPS=3  RDA_SW_COLD_REBUILD=20000
                                                       (cache expiration)
  RDA_SW_CHURN_MIN=50000    RDA_SW_CHURN_RATIO=1.0      (cache churn)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:?--dir needs a path}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'session-waste: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  # No analyzer available: say so on stderr and stay silent on stdout, so a pipeline that
  # greps stdout for findings sees the honest "nothing", never a fabricated clean bill.
  printf 'session-waste: python3 not found — cannot analyse traces.\n' >&2
  exit 3
fi

python3 - "$DIR" <<'PY'
import glob, json, os, sys

root = sys.argv[1]
if os.path.isfile(root):
    files = [root]
else:
    files = sorted(glob.glob(os.path.join(root, "*", "events.jsonl")))
    if not files:  # allow a flat dir of *.jsonl (test fixtures)
        files = sorted(glob.glob(os.path.join(root, "*.jsonl")))

def envf(name, d):
    try: return float(os.environ.get(name, d))
    except ValueError: return d
def envi(name, d):
    try: return int(float(os.environ.get(name, d)))
    except ValueError: return d

LIGHT_TURNS  = envi("RDA_SW_LIGHT_TURNS", 3)
LIGHT_OUTPUT = envi("RDA_SW_LIGHT_OUTPUT", 1500)
INIT_SHARE   = envf("RDA_SW_INIT_SHARE", 0.6)
INIT_TURNS   = envi("RDA_SW_INIT_TURNS", 2)
INIT_FLOOR   = envi("RDA_SW_INIT_FLOOR", 30000)
BLOAT_TOKENS = envi("RDA_SW_BLOAT_TOKENS", 20000)
BLOAT_TURNS  = envi("RDA_SW_BLOAT_TURNS", 8)
TTL          = envi("RDA_SW_TTL", 300)
COLD_GAP     = envi("RDA_SW_COLD_GAP", 1800)
COLD_GAPS    = envi("RDA_SW_COLD_GAPS", 3)
COLD_REBUILD = envi("RDA_SW_COLD_REBUILD", 20000)
CHURN_MIN    = envi("RDA_SW_CHURN_MIN", 50000)
CHURN_RATIO  = envf("RDA_SW_CHURN_RATIO", 1.0)

EXPENSIVE = ("opus",)  # substring match on model id

def parse_ts(s):
    if not s: return None
    try:
        from datetime import datetime
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None

def analyse(path):
    """Return a list of findings for one session, or [] (silence) when clean."""
    lines = []
    for l in open(path, encoding="utf-8", errors="replace"):
        l = l.strip()
        if not l: continue
        try: lines.append(json.loads(l))
        except json.JSONDecodeError: continue
    if not lines: return []

    sid = None
    assistant_models = []
    user_ts = []
    inter_ts = []       # user + assistant timestamps, for gap detection
    tool_events = []    # (index_among_assistant_turns_before, approx_tokens)
    assistant_seen = 0
    shutdown = None
    ttl = None

    for d in lines:
        t = d.get("type")
        data = d.get("data") or {}
        if sid is None:
            sid = d.get("sessionId") or data.get("sessionId")
        ts = parse_ts(d.get("timestamp"))
        if t == "user.message":
            if ts is not None: user_ts.append(ts); inter_ts.append(ts)
        elif t == "assistant.message":
            assistant_seen += 1
            m = data.get("model")
            if m: assistant_models.append(m)
            if ts is not None: inter_ts.append(ts)
        elif t == "tool.execution_complete":
            res = data.get("result")
            if res is not None:
                approx = len(json.dumps(res, ensure_ascii=False)) // 4
                tool_events.append((assistant_seen, approx))
        elif t == "session.usage_checkpoint":
            for c in (data.get("modelCacheState") or []):
                v = c.get("cacheTtlSeconds")
                if isinstance(v, (int, float)):
                    ttl = v if ttl is None else min(ttl, v)
        elif t == "session.shutdown":
            shutdown = data

    sid_short = (sid or os.path.basename(os.path.dirname(path)) or "session")[:8]
    n_user = len(user_ts)
    findings = []

    # --- D1: suboptimal model routing --------------------------------------
    # A light session (few turns, little output) run entirely on an expensive model.
    if assistant_models and shutdown:
        mm = shutdown.get("modelMetrics") or {}
        exp = [m for m in mm if any(e in m for e in EXPENSIVE)]
        all_exp = assistant_models and all(any(e in m for e in EXPENSIVE) for m in assistant_models)
        out_tok = sum((mm.get(m, {}).get("usage", {}) or {}).get("outputTokens", 0) for m in mm)
        if all_exp and exp and n_user <= LIGHT_TURNS and out_tok <= LIGHT_OUTPUT:
            prem = sum((mm.get(m, {}).get("requests", {}) or {}).get("cost", 0) for m in exp)
            aiu = sum(mm.get(m, {}).get("totalNanoAiu", 0) for m in exp) / 1e9
            findings.append((
                "model-routing",
                f"light session ({n_user} user turn(s), {out_tok} output tokens) ran entirely on "
                f"{', '.join(sorted(exp))}",
                f"~{prem} premium request(s), ~{aiu:.2f} AIU on the expensive model "
                f"(estimate; a cheaper tier's exact cost is not in the trace)",
                "route simple/short sessions to a cheaper model (e.g. sonnet/haiku); reserve "
                "opus for hard reasoning",
            ))

    # --- D2: prompt initialization overhead --------------------------------
    if shutdown and "toolDefinitionsTokens" in shutdown:
        sys_tok  = shutdown.get("systemTokens", 0)
        tool_tok = shutdown.get("toolDefinitionsTokens", 0)
        cur_tok  = shutdown.get("currentTokens", 0)
        fixed = sys_tok + tool_tok
        if (cur_tok > 0 and fixed / cur_tok >= INIT_SHARE and 1 <= n_user <= INIT_TURNS
                and tool_tok >= INIT_FLOOR):
            share = 100 * fixed / cur_tok
            findings.append((
                "prompt-init-overhead",
                f"fixed prompt (system {sys_tok} + tool schemas {tool_tok} = {fixed} tokens) is "
                f"{share:.0f}% of context over only {n_user} user turn(s)",
                f"~{fixed} tokens of fixed overhead re-billed each turn, amortized over little "
                f"work (estimate; based on the session's own token split)",
                "batch several small asks into one session; trim unused tool schemas / MCP "
                "servers to shrink the fixed prefix",
            ))

    # --- D3: context window bloat ------------------------------------------
    if tool_events and assistant_seen:
        idx, approx = max(tool_events, key=lambda x: x[1])
        turns_after = assistant_seen - idx
        if approx >= BLOAT_TOKENS and turns_after >= BLOAT_TURNS:
            findings.append((
                "context-bloat",
                f"a ~{approx}-token tool payload stayed in context for ~{turns_after} later turns",
                f"~{approx * turns_after} token-turns re-billed (estimate = payload tokens x "
                f"turns after; assumes it persisted in the cached prefix)",
                "avoid dumping large tool outputs; head/paginate/summarise, or drop the payload "
                "once used",
            ))

    # --- D4: cache expiration inefficiency ---------------------------------
    # Not a single break (you cannot tell someone "don't step away") but a RECURRING pattern:
    # the same session left to go cold several times, each resume past the ~TTL paying full
    # prefix. Needs a substantial prefix to rebuild, or the waste is negligible.
    used_ttl = ttl if ttl else TTL
    if len(inter_ts) >= 2:
        inter_ts.sort()
        gaps = [b - a for a, b in zip(inter_ts, inter_ts[1:])]
        cold = [g for g in gaps if g >= COLD_GAP]
        rebuilt = None
        if shutdown and "toolDefinitionsTokens" in shutdown:
            rebuilt = shutdown.get("systemTokens", 0) + shutdown.get("toolDefinitionsTokens", 0)
        if len(cold) >= COLD_GAPS and rebuilt and rebuilt >= COLD_REBUILD:
            longest = int(max(cold))
            findings.append((
                "cache-expiration",
                f"{len(cold)} idle gaps over {COLD_GAP}s (longest {longest}s) — well past the "
                f"~{int(used_ttl)}s prompt-cache TTL; the session repeatedly went cold and resumed",
                f"~{rebuilt} tokens of prefix rebuilt at full price on each of ~{len(cold)} cold "
                f"resumes (estimate; the cached prefix expires after the TTL)",
                "do long-idle work in one continuous stretch, or start a fresh focused session "
                "instead of resuming a cold one out of habit",
            ))

    # --- D5: cache churn (poor prefix reuse) -------------------------------
    if shutdown:
        mm = shutdown.get("modelMetrics") or {}
        read  = sum((mm.get(m, {}).get("usage", {}) or {}).get("cacheReadTokens", 0) for m in mm)
        write = sum((mm.get(m, {}).get("usage", {}) or {}).get("cacheWriteTokens", 0) for m in mm)
        if write >= CHURN_MIN and read >= 0 and write >= read * CHURN_RATIO:
            excess = write - read
            ratio = (write / read) if read else float("inf")
            rtxt = "inf" if ratio == float("inf") else f"{ratio:.1f}x"
            findings.append((
                "cache-churn",
                f"cache writes ({write} tokens) >= reads ({read} tokens), ratio {rtxt} — the prefix "
                f"kept being rebuilt instead of reused",
                f"~{excess if excess > 0 else write} tokens written to cache that reuse would have "
                f"avoided (measured cache_write vs cache_read)",
                "keep the early context stable; avoid editing/inserting near the top of the prompt, "
                "which invalidates the whole downstream cache",
            ))

    return [(sid_short,) + f for f in findings]

all_findings = []
for f in files:
    try:
        all_findings.extend(analyse(f))
    except (OSError, ValueError):
        continue

# Silence is a feature: nothing found -> nothing printed, exit 0.
if not all_findings:
    sys.exit(0)

by_session = {}
for sid, name, what, impact, remedy in all_findings:
    by_session.setdefault(sid, []).append((name, what, impact, remedy))

print(f"session-waste: {len(all_findings)} finding(s) across "
      f"{len(by_session)} session(s) in {root}\n")
for sid in sorted(by_session):
    print(f"session {sid}")
    for name, what, impact, remedy in by_session[sid]:
        print(f"  [{name}] {what}")
        print(f"     impact (estimate): {impact}")
        print(f"     remedy: {remedy}")
    print()
PY
