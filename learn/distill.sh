#!/usr/bin/env bash
# learn/distill.sh — periodic batch: reads the staging inbox, does a dedup-check via
# gbrain (keyword, reliable), and stages signals as CANDIDATES in quarantine —
# never directly into the vault. Classify/promote = gated (curate.sh + human).
# See learn/learn-protocol.md. Launched by launchd. Non-blocking.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
inbox="${RDA_INBOX:-$RDA_HOME/learnings/inbox}"
quar="${RDA_QUARANTINE:-$RDA_HOME/learnings/quarantine}"
done_dir="$inbox/_processed"
mkdir -p "$quar" "$done_dir"
shopt -s nullglob

gbrain_search() {  # keyword dedup-check on the vault; empty if gbrain is absent
  command -v gbrain >/dev/null 2>&1 || { echo ""; return; }
  ( cd "$HOME/.gbrain" 2>/dev/null && unset DATABASE_URL && \
    gbrain search "$1" --source vault --limit 3 2>/dev/null | head -3 ) || echo ""
}

n=0
for f in "$inbox"/*.md; do
  [ -e "$f" ] || continue
  while IFS= read -r line; do
    sig="${line#*] }"                       # strip the timestamp "- [ts] "
    [ -n "${sig// /}" ] || continue
    case "$sig" in *"/${RDA_HOME##*/}/private/"*) continue ;; esac   # privacy hard-gate (follows RDA_HOME, see capture.sh)

    terms="$(printf '%s' "$sig" | tr -cs '[:alnum:]' ' ' | awk '{for(i=1;i<=NF&&i<=6;i++)printf "%s ",$i}')"
    dupes="$(gbrain_search "$terms")"
    n=$((n+1))
    cand="$quar/$(date +%Y%m%d-%H%M%S)-$n.md"
    {
      echo "---"
      echo "class: TODO    # tool-quirk|correction|decision|capability-gap|voice"
      echo "approved: false   # human/curate gate — see learn-protocol"
      echo "source_inbox: $(basename "$f")"
      echo "---"
      echo
      echo "## Signal"
      echo "$sig"
      echo
      echo "## Possible duplicates in the vault (keyword dedup-check)"
      if [ -n "$dupes" ]; then echo '```'; echo "$dupes"; echo '```'
        echo "→ if match: MERGE/supersedes, not a new note."
      else echo "(no match — candidate for a new note)"; fi
    } > "$cand"
  done < "$f"
  mv "$f" "$done_dir/" 2>/dev/null || true
done

echo "distill: $n candidates → $quar (quarantine, gated)" >&2
