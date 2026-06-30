#!/usr/bin/env bash
# learn/distill.sh — batch periodico: legge la staging inbox, fa dedup-check via
# gbrain (keyword, affidabile), e stage i segnali come CANDIDATI in quarantena —
# mai diretto nel vault. Classifica/promozione = gated (curate.sh + umano).
# Vedi learn/learn-protocol.md. Lanciato da launchd. Non-blocking.
set -euo pipefail

inbox="${RDA_INBOX:-$HOME/.roberdan-os/learnings/inbox}"
quar="${RDA_QUARANTINE:-$HOME/.roberdan-os/learnings/quarantine}"
done_dir="$inbox/_processed"
mkdir -p "$quar" "$done_dir"
shopt -s nullglob

gbrain_search() {  # dedup-check keyword sul vault; vuoto se gbrain assente
  command -v gbrain >/dev/null 2>&1 || { echo ""; return; }
  ( cd "$HOME/.gbrain" 2>/dev/null && unset DATABASE_URL && \
    gbrain search "$1" --source vault --limit 3 2>/dev/null | head -3 ) || echo ""
}

n=0
for f in "$inbox"/*.md; do
  [ -e "$f" ] || continue
  while IFS= read -r line; do
    sig="${line#*] }"                       # togli il timestamp "- [ts] "
    [ -n "${sig// /}" ] || continue
    case "$sig" in *"/.roberdan-os/private/"*) continue ;; esac   # privacy hard-gate

    terms="$(printf '%s' "$sig" | tr -cs '[:alnum:]' ' ' | awk '{for(i=1;i<=NF&&i<=6;i++)printf "%s ",$i}')"
    dupes="$(gbrain_search "$terms")"
    n=$((n+1))
    cand="$quar/$(date +%Y%m%d-%H%M%S)-$n.md"
    {
      echo "---"
      echo "class: TODO    # tool-quirk|correction|decision|capability-gap|voice"
      echo "approved: false   # umano/curate gate — vedi learn-protocol"
      echo "source_inbox: $(basename "$f")"
      echo "---"
      echo
      echo "## Segnale"
      echo "$sig"
      echo
      echo "## Possibili duplicati nel vault (dedup-check keyword)"
      if [ -n "$dupes" ]; then echo '```'; echo "$dupes"; echo '```'
        echo "→ se match: MERGE/supersedes, non nota nuova."
      else echo "(nessun match — candidato a nota nuova)"; fi
    } > "$cand"
  done < "$f"
  mv "$f" "$done_dir/" 2>/dev/null || true
done

echo "distill: $n candidati → $quar (quarantena, gated)" >&2
