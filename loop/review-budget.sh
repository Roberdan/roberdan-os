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
#   review-budget.sh declare   <card> <rounds> "<property in scope>"
#   review-budget.sh record    <card> <verdict> "<what it found>" [class]
#   review-budget.sh discovery <card> "<work found that is not this card>"
#   review-budget.sh override  <card> "<exposure DEMONSTRATED, not feared>"
#   review-budget.sh check     <card>
#   review-budget.sh line      <card>
#
# Two failure modes, two brakes, because they are not the same defect:
#
#   Loop A — ROUNDS ON THE SAME CLASS. Seven rounds on one route check: each
#   round the reviewer found another INSTANCE of one class (two hand-written
#   descriptions that drift apart), each round patched the instance. That does
#   not end by exhausting the instances. It ended by changing the SHAPE of the
#   guarantee — one reader, and the gate asks it. So: the second round on the
#   same class stops the patching, here, by name.
#
#   Loop B — SCOPE DRIFT. A card that said "sort before cutting" produced a
#   +6153-line PR about macOS ACLs over 18 rounds. The work was good. It was not
#   the work asked for. So: anything found while doing card X becomes a NEW CARD,
#   never a commit in the PR of X.
#
# And the counterweight, without which this becomes a way to ship holes: a
# DEMONSTRATED live exposure overrides the cap. Demonstrated, not theoretical,
# and it has to be written down.
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
  review-budget.sh declare   <card> <rounds> "<property in scope>"
  review-budget.sh record    <card> <verdict> "<what it found>" [class]
  review-budget.sh discovery <card> "<work found that is not this card>"
  review-budget.sh override  <card> "<exposure DEMONSTRATED, not feared>"
  review-budget.sh check     <card>
  review-budget.sh line      <card>

verdict is free text (SHIP / DO NOT SHIP / ...). `class` names the KIND of defect
the round found: the second round on the same class stops the patching and asks
for a change of shape instead. Exit 3 = stop, the next round is a human decision.
Exit 2 = usage error.
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

# A class is a KIND of defect, not an instance of one. Normalised so that
# "route-desc" and "Route Desc " are the same class: the whole point is to
# notice the repeat, and a checker fooled by capitalisation notices nothing.
_slug_class() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' \
    | sed -E 's/^-+//; s/-+$//'
}

_class_count() {
  local f="$1" class="$2"
  [ -f "$f" ] || { printf '0\n'; return 0; }
  awk -F'\t' -v c="$class" '$1=="round" && $6==c {n++} END{print n+0}' "$f"
}

_overridden() {
  local f="$1"
  [ -f "$f" ] || return 1
  [ "$(awk -F'\t' '$1=="override"{n++} END{print n+0}' "$f")" != "0" ]
}

_discoveries() {
  local f="$1"
  [ -f "$f" ] || return 0
  awk -F'\t' '$1=="discovery"{printf "  discovery: %s\n", $3}' "$f"
}

# The number, on one line, made to be pasted into the PR body or the commit.
# Prose did not stop this happening, to me or to anyone else, and we can all
# read. A visible count does something prose cannot: it makes the eighteenth
# round embarrassing to WRITE DOWN, before anyone gets round to forbidding it.
_line() {
  local card="$1" f="$2" budget used classes disc
  budget="$(_budget_of "$f")"; budget="${budget:-$DEFAULT_ROUNDS (undeclared)}"
  used="$(_rounds_used "$f")"
  classes="$(awk -F'\t' '$1=="round" && $6!=""{print $6}' "$f" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')"
  disc="$(awk -F'\t' '$1=="discovery"{n++} END{print n+0}' "$f" 2>/dev/null)"
  printf 'Review rounds: %s/%s' "$used" "$budget"
  [ -n "$classes" ] && printf ' | classes: %s' "$classes"
  [ "${disc:-0}" != "0" ] && printf ' | %s discovery(ies) filed as separate cards' "$disc"
  _overridden "$f" && printf ' | CAP OVERRIDDEN (demonstrated exposure)'
  printf '\n'
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
    awk -F'\t' '$1=="round"{printf "  round %s: %s — %s%s\n", $2, $3, $4, ($6!=""?" [class: " $6 "]":"")}' "$f"
    _discoveries "$f"
    awk -F'\t' '$1=="override"{printf "  OVERRIDE: %s\n", $3}' "$f"
  fi
  if _overridden "$f"; then
    echo "review-budget: the cap is overridden by a DEMONSTRATED exposure (above). Keep going, and say so in the PR."
    return 0
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
    card="${1:-}"; verdict="${2:-}"; found="${3:-}"; class="${4:-}"
    [ -n "$card" ] && [ -n "$verdict" ] || usage
    _validate_card "$card"
    mkdir -p "$STATE_DIR"
    f="$(_card_file "$card")"
    class="$(_slug_class "${class:-}")"
    n=$(( $(_rounds_used "$f") + 1 ))
    printf 'round\t%s\t%s\t%s\t%s\t%s\n' "$n" "$verdict" "${found:-(nothing recorded)}" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$class" >> "$f"
    # The same-class stop comes BEFORE the budget report, because it fires
    # earlier and for a different reason: the count is fine, the METHOD is not.
    if [ -n "$class" ] && [ "$(_class_count "$f" "$class")" -ge 2 ] && ! _overridden "$f"; then
      cat <<EOF
review-budget: SECOND ROUND ON THE CLASS '$class'. Stop patching instances.
  Two rounds on one class is not bad luck, it is the wrong shape of guarantee:
  the reviewer will keep finding instances for as long as instances exist, and
  you will keep fixing them one at a time. A third round of instances is refused.
  Two ways out, both in ONE move:
    (a) change the shape so the class cannot occur — one source of truth the
        gate reads, a derived list instead of a written one, a property test
        instead of an example;
    (b) if you cannot, MINUTE IT: write the class down as a known limit, with
        what it costs and what would fix it, and stop.
  Whichever you choose, name it in the PR. A class closed by shape is a
  different claim from a class closed by three lucky patches.
EOF
      _line "$card" "$f"
      exit 3
    fi
    _report "$card" "$f"
    ;;
  discovery)
    card="${1:-}"; what="${2:-}"
    [ -n "$card" ] && [ -n "$what" ] || usage
    _validate_card "$card"
    mkdir -p "$STATE_DIR"
    f="$(_card_file "$card")"
    printf 'discovery\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$what" >> "$f"
    cat <<EOF
review-budget: recorded as a DISCOVERY on $card, which means it does NOT go in this PR.
  Work found while doing card $card is not card $card. A card that said "sort
  before cutting" once produced a +6153-line PR about macOS ACLs across 18
  rounds — good work, and not the work that was asked for. File it:
    kb add "$what"
  Then finish $card. The discovery keeps; the scope does not.
EOF
    ;;
  override)
    card="${1:-}"; exposure="${2:-}"
    [ -n "$card" ] && [ -n "$exposure" ] || usage
    _validate_card "$card"
    case "$exposure" in
      *[Mm]ight*|*[Cc]ould*|*[Tt]heoretical*|*[Pp]otential*|*[Ii]f\ someone*)
        die "that is a risk, not an exposure: '$exposure'. The cap is overridden by something DEMONSTRATED — say what you ran and what it did. A cap that yields to 'might' is not a cap.";;
    esac
    mkdir -p "$STATE_DIR"
    f="$(_card_file "$card")"
    printf 'override\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$exposure" >> "$f"
    echo "review-budget: cap overridden on $card by a demonstrated exposure:"
    echo "  $exposure"
    echo "  This is now on the record and appears in the PR line. Keep going."
    ;;
  line)
    card="${1:-}"; [ -n "$card" ] || usage
    _validate_card "$card"
    _line "$card" "$(_card_file "$card")"
    ;;
  check)
    card="${1:-}"; [ -n "$card" ] || usage
    _validate_card "$card"
    _report "$card" "$(_card_file "$card")"
    ;;
  *) usage;;
esac
