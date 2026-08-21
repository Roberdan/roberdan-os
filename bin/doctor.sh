#!/usr/bin/env bash
# doctor.sh — check what roberdan-os needs, say what breaks without it, and
# print the exact command that fixes each gap.
#
# The README already listed the dependencies in prose. Prose does not tell you
# whether YOUR machine has them, and it does not tell you what actually degrades
# when one is missing. This does both, and it never installs anything on its
# own: it prints the command and lets a human run it.
#
# Exit codes: 0 = every REQUIRED dependency present (optional ones may be
# missing), 1 = at least one required dependency missing.
#
# Usage:
#   bin/doctor.sh              # human-readable report
#   bin/doctor.sh --quiet      # only problems
#   bin/doctor.sh --json       # machine-readable, for CI or a hook

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="report"
for arg in "$@"; do
  case "$arg" in
    --json)  MODE="json" ;;
    --quiet) MODE="quiet" ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'doctor: unknown flag %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

# Colour only when a human is watching a terminal.
if [ -t 1 ] && [ "$MODE" != "json" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

MISSING_REQUIRED=0
MISSING_OPTIONAL=0
JSON_ROWS=""

# emit TIER NAME STATUS DETAIL IMPACT FIX
emit() {
  # impact and fix are only meaningful for a missing dependency, so callers
  # reporting `ok` pass four arguments and the rest default to empty.
  local tier="$1" name="$2" status="$3" detail="${4:-}" impact="${5:-}" fix="${6:-}"
  case "$status" in
    ok)      [ "$tier" = required ] || true ;;
    missing) if [ "$tier" = required ]; then MISSING_REQUIRED=$((MISSING_REQUIRED+1));
             else MISSING_OPTIONAL=$((MISSING_OPTIONAL+1)); fi ;;
  esac

  if [ "$MODE" = json ]; then
    local row
    row=$(printf '{"tier":"%s","name":"%s","status":"%s","detail":"%s","impact":"%s","fix":"%s"}' \
      "$tier" "$name" "$status" "${detail//\"/\\\"}" "${impact//\"/\\\"}" "${fix//\"/\\\"}")
    JSON_ROWS="${JSON_ROWS:+$JSON_ROWS,}$row"
    return
  fi

  if [ "$MODE" = quiet ] && [ "$status" = ok ]; then return; fi

  local mark colour
  case "$status" in
    ok)      mark="ok   "; colour="$C_OK" ;;
    missing) if [ "$tier" = required ]; then mark="MISS "; colour="$C_BAD";
             else mark="skip "; colour="$C_WARN"; fi ;;
    *)       mark="?    "; colour="$C_WARN" ;;
  esac

  printf '%s%s%s %-14s %s\n' "$colour" "$mark" "$C_OFF" "$name" "${C_DIM}${detail}${C_OFF}"
  if [ "$status" = missing ]; then
    printf '       %swithout it:%s %s\n' "$C_DIM" "$C_OFF" "$impact"
    printf '       %sfix:%s        %s\n' "$C_DIM" "$C_OFF" "$fix"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Prefer Homebrew when it is actually present, so the printed fix is runnable
# on this machine rather than generically true.
if have brew; then PKG="brew install"; elif have apt-get; then PKG="sudo apt-get install -y";
else PKG="(install via your package manager)"; fi

check_cmd() {
  local tier="$1" name="$2" impact="$3" fix="$4"
  if have "$name"; then
    local ver
    ver=$("$name" --version 2>/dev/null | head -1 | cut -c1-52)
    emit "$tier" "$name" ok "${ver:-present}" "" ""
  else
    emit "$tier" "$name" missing "not on PATH" "$impact" "$fix"
  fi
}

if [ "$MODE" != json ]; then
  printf '\n%sroberdan-os doctor%s  %s%s%s\n\n' "$C_OFF" "$C_OFF" "$C_DIM" "$ROOT" "$C_OFF"
  printf '%s--- required (the engine does not work without these)%s\n' "$C_DIM" "$C_OFF"
fi

check_cmd required git     "no repo operations, no kb, no citation resolution in the bus" "$PKG git"
check_cmd required jq      "the kanban, the bus and every JSON path in the engine break"  "$PKG jq"
check_cmd required bash    "nothing runs"                                                 "$PKG bash"
check_cmd required python3 "the eval pipeline and the leak-check hash tier degrade to a silent skip" "$PKG python3"

if [ "$MODE" != json ]; then
  printf '\n%s--- optional (each degrades cleanly; nothing hard-fails)%s\n' "$C_DIM" "$C_OFF"
fi

check_cmd optional shellcheck "the lint gate falls back to 'bash -n', which catches far less" "$PKG shellcheck"
check_cmd optional prettier   "autofmt silently no-ops on JS/TS/MD/CSS (Python/Rust still format)" "npm i -g prettier"
check_cmd optional gbrain     "semantic recall is unavailable; skills fall back to grep" \
  "see README 'Prerequisites' — official upstream github.com/garrytan/gbrain (embedder set by config, no fork)"
# `ollama --version` exits 0 even when nothing is listening, printing a warning
# to stdout. Reporting that as "ok" would be a false green of exactly the kind
# this script exists to remove, so the daemon is probed instead of the binary.
if have ollama; then
  if ollama list >/dev/null 2>&1; then
    emit optional ollama ok "daemon responding"
  else
    emit optional ollama missing "binary present, daemon not responding" \
      "gbrain's configured embedder (ollama:bge-m3) cannot run; recall degrades to grep" \
      "ollama serve   (or start the Ollama app)"
  fi
else
  emit optional ollama missing "not on PATH" \
    "gbrain's configured embedder (ollama:bge-m3) cannot run" "$PKG ollama"
fi

# An agent CLI is required in the sense that the canon needs a reader, but ANY
# one of several satisfies it, so it cannot be checked with check_cmd.
FOUND_CLI=""
for cli in claude codex copilot cursor opencode warp hermes; do
  have "$cli" && FOUND_CLI="${FOUND_CLI:+$FOUND_CLI }$cli"
done
if [ -n "$FOUND_CLI" ]; then
  emit required agent-cli ok "$FOUND_CLI"
else
  emit required agent-cli missing "no AGENTS.md-reading CLI found" \
    "nothing reads the canon; the repo is documentation only" \
    "install Claude Code (primary target), or any of codex / copilot / cursor / opencode"
fi

# --- wiring, not binaries: installed but not connected is its own failure mode,
# and it is the one that fails silently.
if [ "$MODE" != json ]; then
  printf '\n%s--- wiring (installed is not the same as connected)%s\n' "$C_DIM" "$C_OFF"
fi

if [ -L "$HOME/.local/bin/kb" ] || [ -x "$HOME/.local/bin/kb" ]; then
  emit optional kb-link ok "$HOME/.local/bin/kb"
else
  emit optional kb-link missing "kb is not on PATH" \
    "the kanban CLI has to be called by full path" "bin/bootstrap.sh"
fi

if [ -f "$HOME/.claude/settings.json" ] && grep -q 'roberdan-os\|hooks' "$HOME/.claude/settings.json" 2>/dev/null; then
  emit optional hooks ok "merged into ~/.claude/settings.json"
else
  emit optional hooks missing "hook set not merged" \
    "guards and auto-checkpoint never fire" "bin/install-hooks.sh --apply"
fi

if [ -d "$HOME/.claude/agents" ]; then
  emit optional agents ok "$(find "$HOME/.claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ') linked"
else
  emit optional agents missing "$HOME/.claude/agents missing" \
    "thor, twin, rex and the rest are not invokable" "bin/bootstrap.sh"
fi

if grep -q 'roberdan-os' "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  emit optional pointer ok "personal CLAUDE.md points at the canon"
else
  emit optional pointer missing "pointer block absent from ~/.claude/CLAUDE.md" \
    "sessions start without the canon; this is the one step bootstrap deliberately never automates" \
    "run bin/bootstrap.sh and paste the block it prints"
fi

# The bus MCP server is registered in the *client's* config, never by us: those
# files belong to Claude/Copilot/Codex and sync.sh has never written one. So the
# only honest thing doctor can do is look and say which clients see it.
BUS_MCP_SEEN=""
for cfg in "$HOME/.claude.json" "$HOME/.copilot/mcp-config.json" "$HOME/.codex/config.toml"; do
  if grep -q 'bus-mcp' "$cfg" 2>/dev/null; then
    BUS_MCP_SEEN="$BUS_MCP_SEEN $(basename "$(dirname "$cfg")")/$(basename "$cfg")"
  fi
done
if [ -n "$BUS_MCP_SEEN" ]; then
  emit optional bus-mcp ok "registered in:$BUS_MCP_SEEN"
else
  emit optional bus-mcp missing "no MCP client references bus/bus-mcp.py" \
    "agents can still use bus/bus.sh directly, but the typed tool surface is not exposed to any of them" \
    "claude mcp add --scope user roberdan-bus -- $ROOT/bus/bus-mcp.py"
fi

if [ "$MODE" = json ]; then
  printf '{"required_missing":%d,"optional_missing":%d,"checks":[%s]}\n' \
    "$MISSING_REQUIRED" "$MISSING_OPTIONAL" "$JSON_ROWS"
elif [ "$MISSING_REQUIRED" -gt 0 ]; then
  printf '\n%s%d required dependency missing.%s %d optional gap(s).\n\n' \
    "$C_BAD" "$MISSING_REQUIRED" "$C_OFF" "$MISSING_OPTIONAL"
else
  printf '\n%severything required is present.%s %d optional gap(s) — each degrades cleanly.\n\n' \
    "$C_OK" "$C_OFF" "$MISSING_OPTIONAL"
fi

# Installed-and-present is not the same as working. toolchain-doctor.sh checks
# the agent toolchain for failures that produce no error message at all. It is
# reported, never fatal here: this script's exit code keeps its documented
# meaning (required dependencies only). Skipped in json mode so the machine-
# readable output stays a single valid object.
if [ "$MODE" != json ] && [ -x "$ROOT/bin/toolchain-doctor.sh" ]; then
  "$ROOT/bin/toolchain-doctor.sh" --quiet || true
fi

[ "$MISSING_REQUIRED" -eq 0 ]
