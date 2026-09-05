#!/usr/bin/env bash
# models.sh — list / resolve / validate the reviewed model registry, and generate the ONE
# artifact a host actually reads for per-subagent model settings.
#
#   bin/models.sh list [--host H] [--status current|legacy] [--class C]
#   bin/models.sh resolve <alias|id> [--host copilot|claude]     # -> concrete id, rc 2 if unknown
#   bin/models.sh class <alias|id>                               # frontier|mid|cheap|unknown
#   bin/models.sh validate --model M [--effort E] [--context C] [--host H]
#   bin/models.sh agents [--host copilot]                        # every canon agent's resolved knobs
#   bin/models.sh agent-args <agent>                             # argv tokens, one per line
#   bin/models.sh subagents-json                                 # the Copilot settings FRAGMENT
#   bin/models.sh apply-subagents --yes [--config PATH]          # explicit, atomic, backed up
#   bin/models.sh snapshot                                       # provenance + refresh command
#
# It reports a SNAPSHOT. It never probes the host, never claims a model is enabled for your
# account, and never prints a price — this repo holds no price data.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/lib-models.sh
. "$ROOT/bin/lib-models.sh"

usage() { sed -n '2,20p' "$0"; }

agent_file() { # <name> -> path, rc 2 if there is no such canon agent
  case "$1" in ""|*[!a-zA-Z0-9_-]*) echo "models: invalid agent name '$1'" >&2; return 2 ;; esac
  local f="$ROOT/agents/$1.md"
  [ -f "$f" ] || { echo "models: no canon agent '$1' (agents/$1.md)" >&2; return 2; }
  printf '%s\n' "$f"
}

need_value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "models: $1 requires a value" >&2; exit 2; }
}

cmd="${1:-}"; shift 2>/dev/null || true

case "$cmd" in
  ""|-h|--help|help) usage; exit 0 ;;

  list)
    host=""; status=""; klass=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --host) need_value "$@"; host="$2"; shift 2 ;;
        --status) need_value "$@"; status="$2"; shift 2 ;;
        --class) need_value "$@"; klass="$2"; shift 2 ;;
        *) echo "models list: unknown flag '$1'" >&2; exit 2 ;;
      esac
    done
    printf '%-20s %-16s %-8s %-9s %-30s %-22s %s\n' ID FAMILY ALIAS CLASS EFFORTS CONTEXTS STATUS
    models_rows | while IFS=$'\t' read -r id fam ali cls eff ctx hosts st _src; do
      [ -n "$host" ] && ! _models_in_list "$host" "$hosts" && continue
      [ -n "$status" ] && [ "$status" != "$st" ] && continue
      [ -n "$klass" ] && [ "$klass" != "$cls" ] && continue
      printf '%-20s %-16s %-8s %-9s %-30s %-22s %s\n' "$id" "$fam" "$ali" "$cls" "$eff" "$ctx" "$st"
    done
    ;;

  resolve)
    tok="${1:-}"; shift 2>/dev/null || true
    host="copilot"
    while [ $# -gt 0 ]; do
      case "$1" in --host) need_value "$@"; host="$2"; shift 2 ;; *) echo "models resolve: unknown flag '$1'" >&2; exit 2 ;; esac
    done
    models_resolve "$tok" "$host" || exit 2
    ;;

  class) models_class "${1:-}" ;;

  validate)
    model=""; effort=""; context=""; host="copilot"
    while [ $# -gt 0 ]; do
      case "$1" in
        --model) need_value "$@"; model="$2"; shift 2 ;;
        --effort|--reasoning-effort) need_value "$@"; effort="$2"; shift 2 ;;
        --context) need_value "$@"; context="$2"; shift 2 ;;
        --host) need_value "$@"; host="$2"; shift 2 ;;
        *) echo "models validate: unknown flag '$1'" >&2; exit 2 ;;
      esac
    done
    id="$(models_resolve "$model" "$host")" || exit 2
    [ -n "$effort" ]  && { models_check_effort  "$id" "$effort"  || exit 2; }
    [ -n "$context" ] && { models_check_context "$id" "$context" || exit 2; }
    echo "ok: $id${effort:+ effort=$effort}${context:+ context=$context} (host=$host, registry snapshot — NOT a live availability check)"
    ;;

  agents)
    host="copilot"
    while [ $# -gt 0 ]; do
      case "$1" in --host) need_value "$@"; host="$2"; shift 2 ;; *) echo "models agents: unknown flag '$1'" >&2; exit 2 ;; esac
    done
    rc=0
    printf '%-10s %-20s %-9s %-8s %s\n' AGENT MODEL CLASS EFFORT CONTEXT
    for a in $(find "$ROOT/agents" -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
      n="$(basename "$a" .md)"
      if id="$(models_agent_model "$a" "$host" 2>/dev/null)"; then
        printf '%-10s %-20s %-9s %-8s %s\n' "$n" "$id" "$(models_class "$id")" \
          "$(models_agent_effort "$a")" "$(models_agent_context "$a")"
      else
        printf '%-10s %-20s %-9s %-8s %s\n' "$n" "UNRESOLVED" unknown - -; rc=1
      fi
    done
    exit "$rc"
    ;;

  agent-args)
    f="$(agent_file "${1:-}")" || exit 2
    models_agent_args "$f" || exit 2
    ;;

  subagents-json)
    # The FRAGMENT only — `subagents.agents.<name>` — so it can be merged into a settings file
    # that belongs to Copilot, not replaced by one that belongs to us. Deterministic (sorted).
    printf '{\n  "subagents": {\n    "agents": {\n'
    first=1
    profiles="$(models_builtin_profiles)"
    while IFS=$'\t' read -r n tok eff ctx reason; do
      [ -n "$reason" ] || { echo "models: missing rationale for built-in $n" >&2; exit 2; }
      id="$(models_resolve "$tok" copilot)"
      models_check_effort "$id" "$eff"
      models_check_context "$id" "$ctx"
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '      "%s": { "model": "%s", "modelPolicy": "required", "effortLevel": "%s", "contextTier": "%s" }' "$n" "$id" "$eff" "$ctx"
    done <<< "$profiles"
    for a in $(find "$ROOT/agents" -maxdepth 1 -name '*.md' | LC_ALL=C sort); do
      n="$(basename "$a" .md)"
      grep -qE '^providers:.*copilot' "$a" || continue
      id="$(models_agent_model "$a" copilot)"
      eff="$(models_agent_effort "$a")"; ctx="$(models_agent_context "$a")"
      # "inherit" is Copilot's own word for "use the parent session's value". We use it for a
      # knob the model does not expose, instead of inventing a level it would ignore.
      [ "$(models_efforts "$id")"  = "none" ] && eff="inherit"
      [ "$eff" = inherit ] || models_check_effort "$id" "$eff"
      models_check_context "$id" "$ctx"
      [ "$first" -eq 1 ] || printf ',\n'
      first=0
      printf '      "%s": { "model": "%s", "modelPolicy": "required", "effortLevel": "%s", "contextTier": "%s" }' "$n" "$id" "$eff" "$ctx"
    done
    printf '\n    }\n  }\n}\n'
    ;;

  apply-subagents)
    # EXPLICIT, never part of `sync.sh --install`. Merges the fragment into Copilot's settings
    # with python3's json (an atomic temp-file rename), preserving every unrelated key, and
    # keeps a timestamped backup it never deletes — backups here are not regenerable.
    yes=0; cfg="${RDA_COPILOT_SETTINGS:-${COPILOT_HOME:-$HOME/.copilot}/settings.json}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --yes) yes=1; shift ;;
        --config) need_value "$@"; cfg="$2"; shift 2 ;;
        *) echo "models apply-subagents: unknown flag '$1'" >&2; exit 2 ;;
      esac
    done
    if [ "$yes" -ne 1 ]; then
      echo "models apply-subagents: refusing without --yes. This WRITES $cfg (Copilot's own file)." >&2
      echo "Preview the fragment first: bin/models.sh subagents-json" >&2
      exit 2
    fi
    [ -f "$cfg" ] || { echo "models apply-subagents: $cfg not found (is Copilot CLI installed?)" >&2; exit 2; }
    command -v python3 >/dev/null 2>&1 || { echo "models apply-subagents: python3 required for an atomic, structure-preserving merge" >&2; exit 2; }
    frag="$("$0" subagents-json)" || exit 2
    fragfile="$(mktemp)"; trap 'rm -f "$fragfile"' EXIT
    printf '%s\n' "$frag" > "$fragfile"
    python3 - "$cfg" "$fragfile" <<'PY'
import json, os, sys, tempfile
cfg, fragfile = sys.argv[1], sys.argv[2]
if os.path.islink(cfg):
    raise SystemExit("models: refusing to replace a symlinked settings file")
with open(fragfile, encoding="utf-8") as fh:
    frag = json.load(fh)
with open(cfg, encoding="utf-8") as fh:
    original = fh.read()
data = json.loads(original)
agents = data.setdefault("subagents", {}).setdefault("agents", {})
for name, knobs in frag["subagents"]["agents"].items():
    agents.setdefault(name, {}).update(knobs)
content = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
fd, bak = tempfile.mkstemp(prefix=os.path.basename(cfg) + ".bak-rdos-", dir=os.path.dirname(cfg) or ".")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    fh.write(original)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg) or ".", suffix=".rdos")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(content)
    with open(cfg, encoding="utf-8") as fh:
        if fh.read() != original:
            raise SystemExit("models: settings changed during apply; not overwriting them")
    os.replace(tmp, cfg)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
print("APPLIED: %s (backup %s) — %d subagent(s)" % (cfg, bak, len(frag["subagents"]["agents"])))
PY
    ;;

  snapshot)
    echo "registry : $(models_registry)"
    echo "rows     : $(models_rows | wc -l | tr -d ' ')"
    echo "reviewed : see the header of the registry file (host + CLI version it was read from)"
    echo "refresh  : copilot help config   # prints the authoritative model: id list for the INSTALLED CLI"
    echo ""
    echo "This is a snapshot, not a probe: an id listed here can still be refused by your account,"
    echo "and the host's task/agent tool may expose a different catalog than its --model flag."
    ;;

  *) echo "models.sh: unknown command '$cmd'" >&2; usage >&2; exit 2 ;;
esac
