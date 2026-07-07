#!/usr/bin/env bash
# learn/backfill-classify.sh — one-off migration: re-classify the quarantine candidates
# left at `class: TODO` by the OLD distill stub (before the meta-loop was completed).
# Those candidates' inbox sources are already consumed into _processed, so a plain
# re-run of distill.sh won't touch them — this reads each stuck candidate's own ## Signal
# body, applies the real classifier, and rewrites its `class:` in place. It NEVER promotes
# and NEVER flips `approved:` — the human gate stays Roberto's; this only unsticks the
# classification so an approved candidate can flow. Idempotent; ephemera get tombstoned.
# See ontology/ontology-protocol.md + the rex MED finding (2026-07-07).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=learn/classify.sh
. "$HERE/classify.sh"

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
quar="${RDA_QUARANTINE:-$RDA_HOME/learnings/quarantine}"
[ -d "$quar" ] || { echo "backfill: no quarantine at $quar — nothing to do" >&2; exit 0; }

_frontmatter() { awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f{print}' "$1"; }

reclassified=0 tombstoned=0 skipped=0
for c in "$quar"/*.md; do
  [ -e "$c" ] || continue
  cls="$(_frontmatter "$c" | grep -E '^class:' | head -1 | sed -E 's/^class:[[:space:]]*//;s/[[:space:]]*#.*//')"
  [ "$cls" = "TODO" ] || { skipped=$((skipped+1)); continue; }   # only fix the stub leftovers
  body="$(awk '/^## Signal/{f=1;next} /^## /{f=0} f && NF' "$c")"
  if [ -z "$body" ] || rda_is_ephemeral "$body"; then
    mv "$c" "$c.ephemeral" 2>/dev/null || true                  # noise → tombstoned, never a note
    tombstoned=$((tombstoned+1)); continue
  fi
  new="$(rda_classify "$body")"
  # rewrite ONLY the class: line in the frontmatter; leave approved:/body untouched.
  tmp="$c.tmp.$$"
  awk -v new="$new" '
    NR==1 && /^---$/{infm=1; print; next}
    infm && /^---$/{infm=0; print; next}
    infm && /^class:/{ sub(/^class:[[:space:]]*[^[:space:]#]*/, "class: " new); print; next}
    {print}
  ' "$c" > "$tmp" && mv "$tmp" "$c"
  reclassified=$((reclassified+1))
done

echo "backfill: $reclassified reclassified · $tombstoned ephemera tombstoned · $skipped already-classified skipped" >&2
echo "backfill: nothing promoted, no approvals changed — human gate untouched." >&2
