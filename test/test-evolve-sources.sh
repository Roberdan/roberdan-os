#!/usr/bin/env bash
# test-evolve-sources.sh — il watcher sorveglia un URL per sorgente e, quando cambia, apre una
# card che dice a un agente "vai a leggere questa fonte". Finora nessuno controllava che quella
# fonte fosse ANCORA LEGGIBILE. Il 31 luglio 2026 il changelog di Warp e' passato a una pagina
# costruita nel browser: il watcher continuava a rilevare il delta — la parte che regge — e ad
# aprire card su una pagina che via curl restituisce solo menu e script. Il modo silenzioso di
# rompersi.
#
# Qui si verifica la proprieta' che serve davvero: il corpo scaricato contiene TESTO con
# marcatori di rilascio (date o numeri di versione), non solo impalcatura di navigazione.
# Senza rete il test SALTA a voce alta: un gate che diventa verde perche' non ha potuto
# controllare e' peggio di uno rosso.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$ROOT/evolve/watch.sh"
fails=0
ok()   { printf '  ok   — %s\n' "$1"; }
err()  { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }
skip() { printf '  SKIP — %s\n' "$1"; }

[ -f "$W" ] || { echo "  FAIL: $W non esiste"; exit 1; }

# Gli URL si leggono da watch.sh: se qualcuno ne cambia uno, questo test segue quello nuovo.
urls="$(awk '/^sources_urls=\(/{f=1;next} /^\)/{f=0} f' "$W" | tr -d ' "' | grep -E '^https?://')"
[ -n "$urls" ] || { echo "  FAIL: nessun URL estratto da sources_urls in watch.sh"; exit 1; }
n_urls="$(printf '%s\n' "$urls" | wc -l | tr -d ' ')"
ok "estratti $n_urls URL da sources_urls in watch.sh"

# Rete raggiungibile? Un solo colpo, breve. Se no, si salta tutto dicendolo.
if ! curl -fsSL --max-time 8 -o /dev/null "https://example.com" 2>/dev/null; then
  skip "nessuna rete: le fonti non sono state controllate (questo NON e' un verde)"
  echo "test-evolve-sources: SKIP"
  exit 0
fi

for u in $urls; do
  body="$(curl -fsSL --max-time 25 "$u" 2>/dev/null || true)"
  if [ -z "$body" ]; then
    skip "$u irraggiungibile in questo momento (non conteggiato)"
    continue
  fi

  # Testo vero: via script/style, via tag, e si guarda cosa resta.
  text="$(printf '%s' "$body" \
          | sed -e 's/<script[^>]*>/\'$'\n''/gI' -e 's/<\/script>/\'$'\n''/gI' \
          | awk 'BEGIN{IGNORECASE=1} /<script/{s=1} /<\/script>/{s=0;next} !s' \
          | sed -e 's/<[^>]*>/ /g' -e 's/&[a-z]*;/ /g' \
          | tr -s ' \t' ' ')"

  # Marcatori di rilascio: una data 2026-07 / 2026.07 oppure una versione 1.2.3 / v0.2026...
  distinct="$(printf '%s' "$text" | grep -oE '20[0-9]{2}[-.][0-9]{2}([-.][0-9]{2})?|v?[0-9]+\.[0-9]+\.[0-9]+' | sort -u | wc -l | tr -d ' ')"
  chars="$(printf '%s' "$text" | wc -c | tr -d ' ')"

  # Soglia su marcatori DISTINTI, non totali: una pagina-guscio ne ripete due o tre nel menu e
  # passerebbe un conteggio grezzo. Misure del 2026-07-31: warp rotto 2, copilot 17, warp
  # riparato 70, claude-code raw 101. La soglia 8 sta larga sul caso rotto e lascia margine al
  # piu' magro dei tre buoni.
  if [ "$distinct" -ge 8 ] && [ "$chars" -ge 2000 ]; then
    ok "$u — leggibile via curl ($distinct marcatori distinti, ${chars}c di testo)"
  else
    err "$u — scaricabile ma NON leggibile come note di rilascio ($distinct marcatori distinti, ${chars}c): la card che ne nasce mandera' un agente su una pagina che non puo' leggere"
  fi
done

echo
if [ "$fails" -eq 0 ]; then echo "test-evolve-sources: PASS"; exit 0; fi
echo "test-evolve-sources: FAIL ($fails)"; exit 1
