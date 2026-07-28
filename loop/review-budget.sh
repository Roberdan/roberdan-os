#!/usr/bin/env bash
# review-budget.sh — a review loop needs a brake that is not the reviewer's opinion.
#
# Component 4 of loop/loop-protocol.md stops a loop that keeps FAILING. This
# stops a loop that keeps SUCCEEDING and still never ends: every round finds
# something real, so every round justifies the next one, and the cost scales
# with rounds while the value does not.
#
# It exists because proving one property of one 640-line script ran EIGHT
# adversarial rounds over one night. Every round returned a true blocker. That
# is exactly why nothing ever looked like the moment to stop.
#
#   review-budget.sh declare <card> <rounds> "<property in scope>"
#   review-budget.sh record  <card> <verdict> "<what it found>"
#   review-budget.sh check   <card>
#
# `record` and `check` exit 3 once the budget is spent. Exit 3 is not a failure
# of the work: it means the next round is a HUMAN DECISION, not a default.
set -euo pipefail

STATE_DIR="${RDA_REVIEW_BUDGET_DIR:-${RDA_HOME:-$HOME/.roberdan-os}/state/review-budget}"
DEFAULT_ROUNDS="${RDA_REVIEW_BUDGET_DEFAULT:-2}"
HARD_CAP="${RDA_REVIEW_BUDGET_CAP:-3}"

die() { echo "review-budget: $*" >&2; exit 2; }
usage() {
  cat >&2 <<'USAGE'
usage:
  review-budget.sh declare <card> <rounds> "<property in scope>"
  review-budget.sh record  <card> <verdict> "<what it found>"
  review-budget.sh check   <card>

verdict is free text (SHIP / DO NOT SHIP / ...). Exit 3 = budget spent: the next
round is a human decision. Exit 2 = usage error.
USAGE
  exit 2
}

# Validation is its OWN function, called from the branches, because a `die`
# inside $( ) dies in the subshell: the caller carries on with an empty string
# and the refusal is printed while the command succeeds. Refusing loudly and
# proceeding anyway is worse than not checking at all.
_validate_card() {
  case "$1" in
    ''|*/*|*..*|-*) die "invalid card id: '$1' (expected an id like 260727-171633)";;
  esac
}
_card_file() { printf '%s/%s.tsv' "$STATE_DIR" "$1"; }

_budget_of() {
  local f="$1"
  [ -f "$f" ] || return 0        # no file, no declared budget — say so, don't assume it
  awk -F'\t' '$1=="declare"{b=$3} END{if(b!="") print b}' "$f"
}

_rounds_used() {
  local f="$1"
  [ -f "$f" ] || { printf '0\n'; return 0; }
  awk -F'\t' '$1=="round"{n++} END{print n+0}' "$f"
}

_report() {
  local card="$1" f="$2" budget used
  budget="$(_budget_of "$f")"
  used="$(_rounds_used "$f")"
  if [ -z "$budget" ]; then
    budget="$DEFAULT_ROUNDS"
    echo "review-budget: $card has NO DECLARED BUDGET — assuming the default of $budget."
    echo "  An undeclared budget is an infinite one. Declare it before round 1:"
    echo "  review-budget.sh declare $card <rounds> \"<property in scope>\""
  fi
  echo "review-budget: $card — $used/$budget rounds used."
  if [ -f "$f" ]; then
    awk -F'\t' '$1=="round"{printf "  round %s: %s — %s\n", $2, $3, $4}' "$f"
  fi
  if [ "$used" -ge "$budget" ]; then
    cat <<EOF
review-budget: BUDGET SPENT. Do not start another round by default.
  Hand Roberto a DECISION with the evidence, exactly three options:
    (a) ship as it stands, listing the findings still open;
    (b) ONE more round, with the single named question it must answer;
    (c) cut the scope of the property being proven.
  Silence is not (b). A standing "keep going until it's done" authorises
  finishing the DECLARED SCOPE — when the scope itself keeps growing, that
  instruction has expired and Roberto has to be asked again.
EOF
    return 3
  fi
  return 0
}

cmd="${1:-}"; shift || usage
case "$cmd" in
  declare)
    card="${1:-}"; rounds="${2:-}"; prop="${3:-}"
    [ -n "$card" ] && [ -n "$rounds" ] && [ -n "$prop" ] || usage
    _validate_card "$card"
    case "$rounds" in ''|*[!0-9]*) die "rounds must be a number, got '$rounds'";; esac
    [ "$rounds" -ge 1 ] || die "a budget of $rounds rounds is not a review"
    if [ "$rounds" -gt "$HARD_CAP" ]; then
      die "$rounds exceeds the hard cap of $HARD_CAP. If the property genuinely needs more, it is the PROPERTY that is unbounded, not the review: narrow its scope and declare the rest as a known limit."
    fi
    mkdir -p "$STATE_DIR"
    f="$(_card_file "$card")"
    [ -f "$f" ] && die "$card already has a budget. Re-declaring mid-loop is how a bounded review becomes an unbounded one; if the scope really changed, that is a human decision."
    printf 'declare\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rounds" "$prop" > "$f"
    echo "review-budget: $card — $rounds rounds to prove: $prop"
    ;;
  record)
    card="${1:-}"; verdict="${2:-}"; found="${3:-}"
    [ -n "$card" ] && [ -n "$verdict" ] || usage
    _validate_card "$card"
    mkdir -p "$STATE_DIR"
    f="$(_card_file "$card")"
    n=$(( $(_rounds_used "$f") + 1 ))
    printf 'round\t%s\t%s\t%s\t%s\n' "$n" "$verdict" "${found:-(nothing recorded)}" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$f"
    _report "$card" "$f"
    ;;
  check)
    card="${1:-}"; [ -n "$card" ] || usage
    _validate_card "$card"
    _report "$card" "$(_card_file "$card")"
    ;;
  *) usage;;
esac
