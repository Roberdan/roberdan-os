#!/usr/bin/env bash
# kanban/ask.sh — i pezzi di quello che Roberto ha chiesto, spuntati uno per uno.
#
# Nasce da una frase sua, il 2026-09-13: "mi manda ancora piu' in bestia quando gli agenti si
# scordano di fare pezzi di quello che gli ho chiesto". La card copre un lavoro intero; una
# richiesta parlata ne contiene spesso quattro o cinque, e i pezzi piccoli sono quelli che
# cadono — senza che nessuno se ne accorga, perche' l'unico che li ricordava era l'agente.
#
# Qui i pezzi stanno su un file, fuori dalla conversazione, e finiscono nella finestrella:
# li vede LUI, non solo l'agente che li ha scritti. E' il punto di tutto — un promemoria
# leggibile solo da chi dimentica non serve a niente.
#
# LIMITE DICHIARATO, e va detto: e' una disciplina, non una barriera. L'elenco lo scrive
# l'agente, quindi un agente che si scorda di scriverlo si scorda anche il pezzo. Quello che
# cambia e' che l'elenco e' VISIBILE: una dimenticanza diventa una riga mancante sullo schermo
# di Roberto invece di un silenzio. Rendere obbligatorio scriverlo e' un'altra decisione, sua.
set -uo pipefail
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
mkdir -p "$RDA_HOME" 2>/dev/null || true

_common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$_common" in "") REPO_PATH="$(pwd)" ;; /*) REPO_PATH="$(dirname "$_common")" ;; *) REPO_PATH="$(cd "$(dirname "$_common")" && pwd)" ;; esac
REPO="${RDA_ASK_REPO:-$(basename "$REPO_PATH")}"
F="${RDA_ASK_FILE:-$RDA_HOME/ask-$REPO.txt}"

usage() {
  cat <<'EOF'
kb ask — i pezzi della richiesta di Roberto, visibili nella finestrella `kb top`.

  kb ask set "pezzo" ["pezzo" ...]   sostituisce l'elenco (inizio di una richiesta nuova)
  kb ask add "pezzo"                 aggiunge un pezzo a quella in corso
  kb ask doing <n>                   segna il pezzo n come in lavorazione
  kb ask done  <n>                   segna il pezzo n come fatto
  kb ask list                        stampa l'elenco con i numeri
  kb ask clear                       svuota (richiesta chiusa)

Stati: aperto (o), corso (in lavorazione), fatto. Un pezzo non si cancella mai per
"toglierlo di mezzo": o e' fatto, o resta aperto e si vede che non lo e'.
EOF
}

_n() { [ -f "$F" ] && wc -l < "$F" | tr -d ' ' || echo 0; }

_set_state() { # <riga> <stato>
  local n="$1" st="$2" tmp
  case "$n" in ''|*[!0-9]*) echo "REFUSED: serve il numero del pezzo (kb ask list)"; exit 1 ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le "$(_n)" ] || { echo "REFUSED: il pezzo $n non esiste (ce ne sono $(_n))"; exit 1; }
  tmp="$F.tmp.$$"
  awk -F'|' -v n="$n" -v st="$st" 'BEGIN{OFS="|"} {if(NR==n) $1=st; print}' "$F" > "$tmp" && mv -f "$tmp" "$F"
  _list
}

_list() {
  [ -f "$F" ] || { echo "(nessuna richiesta in corso in $REPO)"; return 0; }
  local i=0
  while IFS='|' read -r st txt; do
    i=$((i+1))
    case "$st" in
      fatto) printf '  %d. [fatto] %s\n' "$i" "$txt" ;;
      corso) printf '  %d. [in corso] %s\n' "$i" "$txt" ;;
      *)     printf '  %d. [ ] %s\n' "$i" "$txt" ;;
    esac
  done < "$F"
  local tot done_
  tot="$(_n)"; done_="$(grep -c '^fatto|' "$F" 2>/dev/null || true)"
  printf '  %s/%s fatti — %s\n' "${done_:-0}" "$tot" "$REPO"
}

cmd="${1:-list}"; shift 2>/dev/null || true
case "$cmd" in
  set)
    [ "$#" -ge 1 ] || { echo "REFUSED: serve almeno un pezzo"; exit 1; }
    : > "$F"
    for a in "$@"; do printf 'aperto|%s\n' "$a" >> "$F"; done
    _list ;;
  add)
    [ "$#" -ge 1 ] || { echo "REFUSED: serve il testo del pezzo"; exit 1; }
    printf 'aperto|%s\n' "$1" >> "$F"; _list ;;
  doing) _set_state "${1:-}" corso ;;
  done)  _set_state "${1:-}" fatto ;;
  list)  _list ;;
  clear) rm -f "$F"; echo "elenco svuotato ($REPO)" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
