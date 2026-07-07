#!/usr/bin/env bash
# ontology/curate.sh — SINGLE-WRITER: promotes APPROVED candidates from quarantine
# to typed notes in the vault (type: agent-learning), with retry on the Tolaria AutoGit lock.
# Never auto-promotes (requires approved: true). Also produces a hygiene report.
# See ontology/ontology-protocol.md. Launched by launchd. bash-3.2 + BSD-safe.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
quar="${RDA_QUARANTINE:-$RDA_HOME/learnings/quarantine}"
default_vault="$HOME/Obsidian/Roberdan's Vault"   # apostrophe is fine in plain double quotes
vault="${RDA_VAULT:-$default_vault}"              # ...but NOT inside ${:-} (breaks bash)
dest="$vault/agent-learnings"
state="${RDA_EVOLVE_STATE:-$RDA_HOME/evolve}"
report="$state/hygiene-$(date +%Y-%m-%d).md"
mkdir -p "$dest" "$state"

# Lock guard: a single writer on the vault. Retry on .git/index.lock.
git_safe() {
  local tries=0
  while [ -f "$vault/.git/index.lock" ] && [ "$tries" -lt 10 ]; do sleep 3; tries=$((tries+1)); done
  git -C "$vault" "$@"
}

promoted=0
for c in "$quar"/*.md; do
  [ -e "$c" ] || continue
  grep -qE '^approved:[[:space:]]*true' "$c" || continue
  cls="$(grep -E '^class:' "$c" | head -1 | sed -E 's/^class:[[:space:]]*//;s/[[:space:]]*#.*//')"
  [ -n "$cls" ] && [ "$cls" != "TODO" ] || continue
  body="$(awk '/^## Signal/{f=1;next} /^## /{f=0} f && NF' "$c")"
  [ -n "$body" ] || continue
  # Privacy hard-gate before writing to the vault (real deny-list, defense-in-depth).
  denylist=""
  for d in "$RDA_HOME/private/.denylist" "$(dirname "$0")/../private/.denylist"; do
    [ -f "$d" ] && { denylist="$d"; break; }
  done
  if [ -n "$denylist" ] && printf '%s' "$body" | grep -iEf <(grep -vE '^[[:space:]]*($|#)' "$denylist") >/dev/null 2>&1; then
    echo "curate: privacy block (deny-list) on $c, skip" >&2; continue
  fi

  slug="agent-learning-$(date +%Y%m%d-%H%M%S)-$promoted"
  note="$dest/$slug.md"
  printf -- '---\n_organized: true\ntype: agent-learning\nclass: %s\nworkspace: agent-learnings\ncaptured: %s\n---\n\n# %s\n\n%s\n' \
    "$cls" "$(date +%Y-%m-%d)" "$slug" "$body" > "$note"
  # Atomic per-candidate: commit the note first; consume the quarantine source ONLY on
  # a verified commit. A failed/killed commit leaves the candidate in quarantine for retry
  # (before: one cumulative commit after the loop could orphan already-consumed sources).
  if git_safe add "agent-learnings/$slug.md" 2>/dev/null && git_safe commit -q -m "chore(memory): promote agent-learning $slug" 2>/dev/null; then
    mv "$c" "$c.promoted" 2>/dev/null || true
    promoted=$((promoted+1))
  else
    rm -f "$note"
    echo "curate: vault commit failed for $c — left in quarantine for retry" >&2
  fi
done

# robust counts: find doesn't fail on an empty dir (unlike ls glob + set -e)
total="$(find "$dest" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
pending=0
for q in "$quar"/*.md; do
  [ -e "$q" ] || continue
  grep -qE '^approved:[[:space:]]*true' "$q" || pending=$((pending+1))
done
printf -- '# memory hygiene — %s\n\n- promoted this run: %s\n- total agent-learning notes: %s\n- unapproved quarantine candidates: %s\n\n## Proposals (gated, human decides)\n- semantic near-dup dedup once the embedding provider is active\n- tombstone retire: RESOLVED/pre-v3 notes → agent-learnings/_archive/\n' \
  "$(date +%Y-%m-%d)" "$promoted" "$total" "$pending" > "$report"
echo "curate: $promoted promoted · report → $report" >&2
exit 0
