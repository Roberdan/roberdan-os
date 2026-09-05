#!/usr/bin/env bash
# lib-models.sh — the ONLY reader of skills/model-selection-policy/models.tsv.
#
# Sourced by bin/models.sh (the CLI), bin/copilot-agent.sh (the launcher) and bin/sync.sh
# (wrapper generation). Nothing else parses the registry: one parser, one set of answers.
#
# Design rules this file obeys, because each has already cost something somewhere:
#   - UNKNOWN IS NOT SAFE. An id that is not in the registry resolves to nothing and classes
#     as `unknown`; callers that must pick a side treat `unknown` as frontier (needs a written
#     reason), never as cheap.
#   - A SNAPSHOT IS NOT A PROBE. Nothing here claims a model is enabled for this account.
#   - NO SILENT FALLBACK. A bad token produces a message on stderr and a non-zero return, not
#     a quiet substitution — a launcher that swaps your model for another one without saying
#     so is worse than one that refuses to start.
#   - Functions never call `exit` and never assume `set -e`: sync.sh sources this.
#
# All functions return 0 on success, 2 on "refused / not in the reviewed set".
#
# --- why sync.sh emits no effort/context -------------------------------------------------
# bin/sync.sh generates Copilot custom agents and pins `model:` there, but deliberately emits
# NO effort or context key. Copilot's custom-agent schema has neither, and it ignores unknown
# frontmatter keys IN SILENCE — the `metadata:` scar, where nine "unknown field ignored" lines
# per session were the only sign. A key that looks like configuration and behaves like a
# comment is worse than no key at all: it stops the next person from looking for the setting
# that works. The two knobs have exactly two real homes, and both are in this repo:
#   - bin/copilot-agent.sh          -> `--effort` / `--context` on the actual command line
#   - platforms/copilot/subagents.json -> `subagents.agents.<name>.effortLevel/.contextTier`,
#     applied only by the explicit `bin/models.sh apply-subagents --yes`
# The tier -> id map used to be an 18-line `case` inside sync.sh. It lives here now so the
# generator, the launcher and the tests answer from one table instead of three copies.

# Resolve the repo root once, from THIS file's location (works when sourced from any cwd).
_RDA_MODELS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Registry location, overridable for isolated tests.
models_registry() {
  printf '%s\n' "${RDA_MODELS_REGISTRY:-$_RDA_MODELS_ROOT/skills/model-selection-policy/models.tsv}"
}

# Every data row, comments and blanks stripped. Deterministic order = file order.
models_rows() {
  local reg; reg="$(models_registry)"
  [ -f "$reg" ] || { echo "models: registry not found at $reg" >&2; return 2; }
  grep -v '^[[:space:]]*#' "$reg" | grep -v '^[[:space:]]*$'
}

# models_row <id> -> the whole tab-separated row, or empty + rc 2.
models_row() {
  local want="$1" row
  row="$(models_rows | awk -F'\t' -v w="$want" '$1==w{print; exit}')" || return 2
  [ -n "$row" ] || return 2
  printf '%s\n' "$row"
}

# models_field <id> <column-number> -> one field (empty + rc 2 if the id is unknown).
models_field() {
  local row; row="$(models_row "$1")" || return 2
  printf '%s\n' "$row" | cut -f "$2"
}

# models_alias_id <alias> -> the concrete id an alias points at.
models_alias_id() {
  local a="$1" id
  id="$(models_rows | awk -F'\t' -v a="$a" '$3!="-" && $3==a && $8=="current"{print $1; exit}')"
  [ -n "$id" ] || return 2
  printf '%s\n' "$id"
}

# models_resolve <token> [host] -> the concrete id to pass to that host's model flag.
#
# The host split is the point, not decoration:
#   copilot  wants a CONCRETE id (`--model claude-opus-5`). An alias is expanded; a concrete id
#            is accepted only if the registry says this host takes it.
#   claude   wants the TIER ALIAS (`--model opus`). A concrete Copilot id is REFUSED rather
#            than passed through, because Claude Code would reject it at run time anyway.
#   codex    has no canon model pin: resolving for codex is explicitly refused, not faked.
# A brand word ("Astra", "opus 5", "the new GPT") is not an identifier and never resolves.
models_resolve() {
  local token="${1:-}" host="${2:-copilot}" id hosts
  if [ -z "$token" ]; then echo "models: empty model token" >&2; return 2; fi
  case "$host" in
    copilot|copilot-task|claude|codex) ;;
    *) echo "models: unknown host '$host' (copilot|claude|codex)" >&2; return 2 ;;
  esac
  if [ "$host" = "codex" ]; then
    echo "models: host 'codex' has no model pin in this canon — nothing to resolve" >&2; return 2
  fi
  if [ "$host" = "claude" ]; then
    # An alias IS the answer for Claude Code; a concrete id is not.
    if models_alias_id "$token" >/dev/null 2>&1; then printf '%s\n' "$token"; return 0; fi
    echo "models: '$token' is not a Claude Code tier alias (expected one of: $(models_aliases | tr '\n' ' '))" >&2
    return 2
  fi
  if id="$(models_alias_id "$token" 2>/dev/null)"; then token="$id"; fi
  hosts="$(models_field "$token" 7 2>/dev/null)" || {
    echo "models: '$token' is not in the reviewed registry ($(models_registry)) — refusing to guess. Add a reviewed row or pass a listed id; 'bin/models.sh list' shows them." >&2
    return 2
  }
  if [ "$(models_status "$token")" != current ]; then
    echo "models: '$token' is a legacy model; select the current generation with 'bin/models.sh list --status current'." >&2
    return 2
  fi
  case ",$hosts," in
    *",$host,"*) printf '%s\n' "$token" ;;
    *) echo "models: '$token' is not marked as accepted by host '$host' (registry says: $hosts)" >&2; return 2 ;;
  esac
}

models_aliases() { models_rows | awk -F'\t' '$3!="-" && $8=="current"{print $3}'; }

# models_class <token> -> frontier | mid | cheap | unknown.
# UNKNOWN IS DELIBERATE AND CONSERVATIVE: an id nobody reviewed is not "probably cheap".
models_class() {
  local token="${1:-}" id c
  if id="$(models_alias_id "$token" 2>/dev/null)"; then token="$id"; fi
  c="$(models_field "$token" 4 2>/dev/null)" || { echo unknown; return 0; }
  printf '%s\n' "${c:-unknown}"
}

# models_efforts <id> -> comma list, or `none` when the model exposes no reasoning knob.
models_efforts()  { models_field "$1" 5 2>/dev/null || { echo unknown; return 2; }; }
models_contexts() { models_field "$1" 6 2>/dev/null || { echo unknown; return 2; }; }
models_status()   { models_field "$1" 8 2>/dev/null || { echo unknown; return 2; }; }
models_family()   { models_field "$1" 2 2>/dev/null || { echo unknown; return 2; }; }

# The host's own vocabulary for these two flags. Kept separate from the registry: this is what
# the CLI *parses*, the registry is what a given MODEL *supports*. Both must agree for a run.
# Verified: `copilot --help` on 1.0.84-1 (--effort/--reasoning-effort, --context).
models_host_efforts() { printf 'none minimal low medium high xhigh max\n'; }
models_host_contexts(){ printf 'default long_context\n'; }

_models_in_list() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# models_check_effort <id> <effort> — is this effort BOTH a host level and supported here?
models_check_effort() {
  local id="$1" e="$2" sup
  case " $(models_host_efforts) " in *" $e "*) ;; *)
    echo "models: effort '$e' is not a Copilot CLI level ($(models_host_efforts))" >&2; return 2 ;;
  esac
  sup="$(models_efforts "$id")" || { echo "models: unknown model '$id' — cannot check effort" >&2; return 2; }
  if [ "$sup" = "none" ]; then
    echo "models: model '$id' has no reasoning-effort knob — passing --effort would be a lie about it" >&2; return 2
  fi
  _models_in_list "$e" "$sup" && return 0
  echo "models: model '$id' does not support effort '$e' (registry says: $sup)" >&2; return 2
}

# models_check_context <id> <tier>
models_check_context() {
  local id="$1" c="$2" sup
  case " $(models_host_contexts) " in *" $c "*) ;; *)
    echo "models: context tier '$c' is not a Copilot CLI tier ($(models_host_contexts))" >&2; return 2 ;;
  esac
  sup="$(models_contexts "$id")" || { echo "models: unknown model '$id' — cannot check context tier" >&2; return 2; }
  _models_in_list "$c" "$sup" && return 0
  echo "models: model '$id' does not offer context tier '$c' (registry says: $sup)" >&2; return 2
}

# --- canon agent -> the three knobs -------------------------------------------------------
# Reads ONE agent file. The Copilot-specific override (`copilot_model:`) wins over the canon
# tier (`model:`) for the copilot host only, so pinning an experiment on Copilot never moves
# the Claude Code side of the same agent. Claude keeps the tier alias, unchanged.
_models_fm() { grep -m1 -E "^$2:" "$1" 2>/dev/null | sed -E "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"; }

models_agent_model() {   # <agent-file> [host]
  local f="$1" host="${2:-copilot}" tok
  if [ "$host" = "copilot" ]; then tok="$(_models_fm "$f" copilot_model)"; fi
  [ -n "${tok:-}" ] || tok="$(_models_fm "$f" model)"
  [ -n "$tok" ] || return 2
  models_resolve "$tok" "$host"
}

models_agent_effort() {  # <agent-file>  -> declared effort, defaulting to the canon `medium`
  local f="$1" e
  e="$(_models_fm "$f" copilot_effort)"; [ -n "$e" ] || e="$(_models_fm "$f" effort)"
  printf '%s\n' "${e:-medium}"
}

models_agent_context() { # <agent-file> -> declared context tier, defaulting to `default`
  local f="$1" c
  c="$(_models_fm "$f" copilot_context)"
  printf '%s\n' "${c:-default}"
}

# models_agent_args <agent-file> — the argv tokens for `copilot`, ONE PER LINE (never a string:
# a flat string re-splits on spaces and that is how a launcher starts lying about its flags).
# Emits --effort only when the model actually has the knob, and --context only when the model
# has more than one tier — a flag that cannot mean anything is noise, and noise gets copied.
models_agent_args() {
  local f="$1" id eff ctx sup_e sup_c
  id="$(models_agent_model "$f" copilot)" || return 2
  printf -- '--model\n%s\n' "$id"
  eff="$(models_agent_effort "$f")"; sup_e="$(models_efforts "$id")"
  if [ "$sup_e" != "none" ]; then
    models_check_effort "$id" "$eff" || return 2
    printf -- '--effort\n%s\n' "$eff"
  fi
  ctx="$(models_agent_context "$f")"; sup_c="$(models_contexts "$id")"
  models_check_context "$id" "$ctx" || return 2
  if [ "$sup_c" != "default" ]; then
    printf -- '--context\n%s\n' "$ctx"
  fi
}

# Built-in profiles are policy, not another model catalog. Resolve their aliases through
# the same registry as custom agents, including for grandchildren spawned by a subagent.
models_builtin_profiles() {
  local f="$_RDA_MODELS_ROOT/skills/model-selection-policy/delegation.tsv"
  [ -f "$f" ] || { echo "models: delegation profiles missing: $f" >&2; return 2; }
  awk -F'\t' '!/^[[:space:]]*(#|$)/ {print}' "$f"
}
