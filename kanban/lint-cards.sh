#!/usr/bin/env bash
# kanban/lint-cards.sh — additive schema lint for the federated card fields
# (design §2c/§3, docs/plan-2026-07-05-federated-kanban-multi-cli.md). This is a
# Layer-1 filter (a fallible label — the REAL gate is the dispatcher's Layer-2
# code, §0 corollary). Lints todo/ + doing/ cards in the target board:
#   - runner: grammar — <cli>/<model> | human-only, cli ∈ claude|copilot-cli|ollama
#   - human_gates: non-empty  =>  runner: MUST be human-only, else a gated-surface
#     card would be (wrongly) runner-eligible (@thor acceptance test §6.6).
# Existing cards without these OPTIONAL fields pass unchanged. Exit non-zero on any
# violation. Honest limit: human_gates: is read as an INLINE value; a YAML block
# list (items on following lines) is not detected — consistent with §2c framing
# the label as fallible-by-omission (Layer-2 is the guarantee, not this lint).
set -euo pipefail
KB="${RDA_KANBAN:-${1:-$HOME/GitHub/roberdan-os/kanban}}"

_field() {
  grep -m1 "^$2:" "$1" 2>/dev/null \
    | sed "s/^$2:[[:space:]]*//; s/^\"//; s/\"[[:space:]]*\$//; s/[[:space:]]*\$//"
}

fail=0
for col in todo doing; do
  for c in "$KB/$col"/*.md; do
    [ -e "$c" ] || continue
    case "$(basename "$c")" in _*) continue;; esac
    id="$(basename "$c" .md)"
    runner="$(_field "$c" runner || true)"
    gates="$(_field "$c" human_gates || true)"

    if [ -n "$runner" ]; then
      case "$runner" in
        human-only) : ;;
        claude/*|copilot-cli/*|ollama/*) : ;;
        *) echo "LINT FAIL: $id runner: '$runner' invalid (want <claude|copilot-cli|ollama>/<model> or human-only)" >&2; fail=1 ;;
      esac
    fi

    if [ -n "$gates" ] && [ "$runner" != "human-only" ]; then
      echo "LINT FAIL: $id declares human_gates: '$gates' but runner: is '${runner:-<absent>}' — a gated-surface card MUST be runner: human-only" >&2
      fail=1
    fi
  done
done

[ "$fail" -eq 0 ] && echo "lint-cards: OK — runner/human_gates schema clean"
exit "$fail"
