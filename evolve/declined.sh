#!/usr/bin/env bash
# evolve/declined.sh — the rejected-proposal buffer for the weekly watcher.
#
# WHY: the watcher fingerprints a whole changelog page, so any page change drops a new card —
# but the NOVELTIES an agent then extracts are often the same ones already assessed and declined.
# Measured, 2026-07-21: proposals/2026-07-{11,18,19}-claude-code.md each re-raised "/verify and
# /code-review are explicit" + "permission-check hardening", and each concluded "no additional
# patch required now". Three weeks, one question, three answers.
#
# This buffer records what was already assessed-and-declined, per source. watch.sh injects it
# into every card body so the agent picking the card up sees it before re-deriving it.
#
# It INFORMS, it never blocks: matching is deliberately fuzzy (token overlap, so a reworded
# repeat still matches), and a fuzzy matcher must not be allowed to silently drop a real novelty.
#
# usage:
#   evolve/declined.sh add <source> "<one-line novelty summary>"
#   evolve/declined.sh list <source>          # tab-separated lines for that source
#   evolve/declined.sh render <source>        # markdown bullets for a card body ("" if none)
#   evolve/declined.sh has <source> "<summary>"   # exit 0 + print match, 1 if none
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
state_dir="${RDA_EVOLVE_STATE:-$RDA_HOME/evolve}"
store="$state_dir/declined"
# Overlap coefficient (|A∩B| / min(|A|,|B|)) over significant tokens, NOT Jaccard.
# Measured on the real repeat case: the three claude-code proposals share {verify, code, review,
# explicit} but each adds its own filler, so Jaccard lands at 0.36 and misses a repeat that is
# obviously the same item. Overlap coefficient scores it 0.57 while the unrelated control
# ("new JSON output format for SessionStart hooks") stays at 0.00 — a wide, safe margin.
# MIN_SHARED guards the failure mode overlap coefficient has and Jaccard doesn't: a one-token
# summary is trivially a subset of everything and would otherwise score 1.00.
THRESHOLD="${RDA_DECLINED_THRESHOLD:-0.5}"
MIN_SHARED="${RDA_DECLINED_MIN_SHARED:-3}"

mkdir -p "$state_dir"
touch "$store"

# Normalize a summary to a bag of significant tokens: lowercase, split on non-alphanumerics,
# drop tokens shorter than 3 chars and generic filler. Kept intentionally small and readable —
# a stopword list nobody can audit is worse than a few false matches.
_tokens() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c '[:alnum:]' '\n' \
    | grep -Ev '^.{0,2}$' \
    | grep -Evx 'the|and|for|its|with|that|this|are|was|were|has|have|had|not|but|from|into|now|new|also|any|all|per|via|when|then|than|only|more|most|some|such|does|did|will|would|should|could|may|might|must|can|use|used|uses|add|adds|added|update|updates|updated|change|changes|changed|support|supports|release|releases|version|versions' \
    | sort -u
}

_overlap() {
  # _overlap "<a>" "<b>" -> prints "<ratio> <shared>": overlap coefficient with 2 decimals,
  # and the absolute number of shared tokens (so the caller can enforce MIN_SHARED).
  local a b inter na nb smaller
  a="$(_tokens "$1")"; b="$(_tokens "$2")"
  [ -n "$a" ] && [ -n "$b" ] || { echo "0.00 0"; return; }
  inter="$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -c . || true)"
  na="$(printf '%s\n' "$a" | grep -c . || true)"
  nb="$(printf '%s\n' "$b" | grep -c . || true)"
  smaller=$(( na < nb ? na : nb ))
  [ "$smaller" -gt 0 ] || { echo "0.00 0"; return; }
  awk -v i="$inter" -v m="$smaller" 'BEGIN{printf "%.2f %d", i/m, i}'
}

cmd="${1:-}"
case "$cmd" in
  add)
    src="${2:?source required}"; summary="${3:?summary required}"
    # Collapse the summary to a single line — the store is line-oriented.
    summary="$(printf '%s' "$summary" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')"
    [ -n "$summary" ] || { echo "declined: empty summary, nothing recorded" >&2; exit 2; }
    if existing="$("$0" has "$src" "$summary" 2>/dev/null)"; then
      echo "declined: already recorded for $src → $existing" >&2
      exit 0
    fi
    sig="$(printf '%s' "$(_tokens "$summary" | tr '\n' ' ')" | shasum -a 256 | cut -c1-8)"
    printf '%s\t%s\t%s\t%s\n' "$src" "$sig" "$(date +%Y-%m-%d)" "$summary" >> "$store"
    echo "declined: recorded for $src ($sig)" >&2
    ;;
  list)
    src="${2:?source required}"
    awk -F'\t' -v s="$src" '$1==s' "$store"
    ;;
  render)
    src="${2:?source required}"
    lines="$(awk -F'\t' -v s="$src" '$1==s{printf "- (declined %s) %s\n", $3, $4}' "$store")"
    [ -n "$lines" ] || exit 0
    printf '%s\n' "$lines"
    ;;
  has)
    src="${2:?source required}"; summary="${3:?summary required}"
    best=""; best_score="0.00"; best_shared=0
    while IFS=$'\t' read -r s _sig date text; do
      [ "$s" = "$src" ] || continue
      read -r score shared <<< "$(_overlap "$summary" "$text")"
      if awk -v a="$score" -v b="$best_score" 'BEGIN{exit !(a>b)}'; then
        best_score="$score"; best_shared="$shared"; best="$date: $text"
      fi
    done < "$store"
    if awk -v a="$best_score" -v t="$THRESHOLD" 'BEGIN{exit !(a>=t)}' \
       && [ "$best_shared" -ge "$MIN_SHARED" ]; then
      echo "$best (overlap $best_score, $best_shared shared tokens)"
      exit 0
    fi
    exit 1
    ;;
  *)
    sed -n '/^# usage:/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; /^set -euo/d'
    exit 2
    ;;
esac
