#!/usr/bin/env bash
# kanban/top.sh — la finestrella di stato: `kb top`.
#
# Disegna e basta. Ogni dato arriva da `snapshot.sh`, che gira in sottofondo: qui dentro non
# c'e' nessun comando lento, ed e' il motivo per cui puo' ridisegnarsi ogni due secondi senza
# scaldare il Mac. Se la fotografia e' vecchia, si vede scritto quanto e' vecchia — non si
# finge che sia fresca.
#
# Si prende la larghezza del riquadro in cui la apri, e la ri-legge quando lo ridimensioni:
# una larghezza fissa a 34 in un riquadro da 60 taglia le parole a meta' lasciando meta'
# schermo vuoto, che e' il primo difetto che si vede a occhio.
# `q` esce. Senza terminale interattivo (script, CI) disegna UNA volta e esce.
set -uo pipefail
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _d

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"

# La misura del riquadro, ri-letta a ogni ridimensionamento (segnale WINCH). Fuori da un
# terminale (prove, script) non c'e' niente da misurare: 34 colonne, il valore storico.
W=34; H=40
term_size() {
  local c r
  c="$(tput cols 2>/dev/null || echo 0)"; r="$(tput lines 2>/dev/null || echo 0)"
  [ "${c:-0}" -gt 0 ] 2>/dev/null || c=35
  [ "${r:-0}" -gt 0 ] 2>/dev/null || r=41
  W="${RDA_TOP_WIDTH:-$((c-1))}"; [ "$W" -lt 20 ] && W=20
  H="${RDA_TOP_HEIGHT:-$r}"
}
term_size
trap 'term_size' WINCH
EVERY="${RDA_TOP_REFRESH:-15}"     # ogni quanti secondi si rinfresca la fotografia
ONCE=0; [ -t 1 ] || ONCE=1
case "${1:-}" in --once) ONCE=1 ;; esac

if [ -t 1 ] && [ "${RDA_TOP_NO_COLOR:-0}" != "1" ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RD=$'\033[31m'; C=$'\033[36m'
else
  B=""; D=""; R=""; G=""; Y=""; RD=""; C=""
fi

_common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$_common" in "") REPO_PATH="$(pwd)" ;; /*) REPO_PATH="$(dirname "$_common")" ;; *) REPO_PATH="$(cd "$(dirname "$_common")" && pwd)" ;; esac
REPO="$(basename "$REPO_PATH")"
SNAP="${RDA_TOP_SNAP:-$RDA_HOME/top-$REPO.snap}"

# Dove sei TU, letto una volta sola all'avvio e mai nel ciclo di disegno.
# La fotografia e' una sola per progetto e la rinfresca chiunque stia lavorando: se l'intestazione
# leggesse il ramo da li', ti direbbe il ramo di un'ALTRA copia di lavoro — visto davvero, e una
# finestrella che sbaglia a dirti dove sei e' peggio di una che non lo dice.
HERE_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo -)"

line() { printf "${D}%s${R}\n" "$(printf '─%.0s' $(seq 1 "$W"))"; }
hdr()  { local l="$1" r="${2:-}"; printf "${B}%s${R}${D}%*s${R}\n" "$l" $((W-${#l})) "$r"; }
# Due modi di accorciare, perche' sono due cose diverse.
# `fit` e' per le stringhe che una macchina ha prodotto (un comando, un percorso): mandarle a
# capo non le rende piu' leggibili, quindi si tagliano e si dice che sono tagliate con "…".
fit() { local t="$1" m=$((W-4)); [ "$m" -lt 8 ] && m=8
        if [ "${#t}" -le "$m" ]; then printf '%s' "$t"; else printf '%s…' "${t:0:$((m-1))}"; fi; }
# `wrap` e' per le frasi scritte da una persona: si va a capo SULLE PAROLE. Tagliare una parola
# a meta' — "salva archivio card sul repo p" — non e' una riga corta, e' una riga sbagliata, ed
# e' esattamente cio' che Roberto ha visto per primo guardando la finestrella.
# NOTA bash 3.2: in un solo `local a=... b=$a` la seconda assegnazione non vede la prima e
# con `set -u` esplode "unbound variable". Due righe, e il difetto non torna.
wrap() { local ind="$1" txt="$2" cur="" w max
  max=$((W-${#ind}))
  [ "$max" -lt 8 ] && max=8
  for w in $txt; do
    while [ "${#w}" -gt "$max" ]; do printf '%s%s\n' "$ind" "${w:0:$max}"; w="${w:$max}"; done
    if [ -z "$cur" ]; then cur="$w"
    elif [ $((${#cur}+1+${#w})) -le "$max" ]; then cur="$cur $w"
    else printf '%s%s\n' "$ind" "$cur"; cur="$w"; fi
  done
  [ -n "$cur" ] && printf '%s%s\n' "$ind" "$cur"
  return 0; }
# Una voce con il pallino davanti: il pallino sta sulla prima riga, il resto rientra sotto.
bullet() { local dot="$1" txt="$2" ind="${3:-    }" first=1 l
  wrap "$ind" "$txt" | while IFS= read -r l; do
    if [ "$first" = 1 ]; then printf "  %b %s\n" "$dot" "${l#"$ind"}"; first=0
    else printf '%s\n' "$l"; fi
  done; }
# Durata in forma umana a partire da secondi. Senza misura stampa "-", mai una stima.
dur()  { local s="${1:-}"; case "$s" in ''|*[!0-9]*) printf -- '-'; return ;; esac
         if [ "$s" -lt 60 ]; then printf '%ds' "$s"
         elif [ "$s" -lt 3600 ]; then printf '%dm' $((s/60))
         else printf '%dh%02dm' $((s/3600)) $(((s%3600)/60)); fi; }

# Rinfresca la fotografia in sottofondo quando e' piu' vecchia di $EVERY. Mai in primo piano:
# un disegno che aspetta la raccolta e' esattamente la finestrella che si impalla.
refresh_if_stale() {
  local age=99999 now; now="$(date +%s)"
  [ -f "$SNAP" ] && age=$((now - $(awk -F'\t' '$1=="ts"{print $2; exit}' "$SNAP" 2>/dev/null || echo 0)))
  [ "$age" -ge "$EVERY" ] || return 0
  [ -f "$RDA_HOME/top.lock" ] && [ $(( now - $(stat -f %m "$RDA_HOME/top.lock" 2>/dev/null || stat -c %Y "$RDA_HOME/top.lock" 2>/dev/null || echo 0) )) -lt 120 ] && return 0
  : > "$RDA_HOME/top.lock"
  ( cd "$REPO_PATH" && RDA_TOP_QUIET=1 bash "$DIR/snapshot.sh" "$SNAP" >/dev/null 2>&1; rm -f "$RDA_HOME/top.lock" ) &
}

# Legge un valore singolo dalla fotografia; "-" quando non c'e'.
v() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$SNAP" 2>/dev/null; }
# Legge tutte le righe ripetute di una chiave.
vs() { awk -F'\t' -v k="$1" '$1==k{print $2}' "$SNAP" 2>/dev/null; }

draw() {
  local now age; now="$(date +%s)"
  if [ ! -f "$SNAP" ]; then
    printf "${B}%s${R}\n" "$REPO"; line
    printf "  ${D}prima raccolta in corso...${R}\n"; return
  fi
  age=$((now - $(v ts)))

  local here branch dirty
  here="$HERE_NAME"; branch="$BRANCH_NAME"; dirty="$(v dirty)"
  # A riquadro stretto il ramo va sotto invece di sfondare la riga.
  if [ $((${#REPO}+1+${#branch})) -le "$W" ]; then
    printf "${B}${C}%s${R} ${D}%s${R}\n" "$REPO" "$branch"
  else
    printf "${B}${C}%s${R}\n" "$(fit "$REPO")"; printf "  ${D}%s${R}\n" "$(fit "$branch")"
  fi
  [ "$here" != "$REPO" ] && printf "  ${D}sei in: %s${R}\n" "$(fit "$here")"
  line

  # --- LAVORO ---------------------------------------------------------------------------
  hdr "LAVORO" "$(v card_doing) in corso"
  vs card | while IFS='|' read -r id ti st; do
    bullet "${G}●${R}" "$ti"
    printf "${D}"; wrap "    " "da $(dur $(( now - ${st:-now} )) ) · $id"; printf "${R}"
  done
  [ "$(v card_todo)" != "0" ] && printf "  ${D}in attesa: %s${R}\n" "$(v card_todo)"
  line

  # --- AGENTI ---------------------------------------------------------------------------
  # Cosa stanno facendo DAVVERO: l'ultimo comando che il processo ha lanciato. Quando non ce
  # n'e' uno, la finestrella non inventa un'attivita': dice da quanto non ne lancia.
  hdr "AGENTI" "$(v agenti) $([ "$(v agenti)" = "1" ] && echo vivo || echo vivi)"
  vs agent | while IFS='|' read -r sid kind step units age where cmd; do
    # Il pallino dice UNA cosa sola: da quanto non fa niente. Verde si muove, giallo rallenta,
    # rosso e' fermo — ed e' il dato che a Roberto mancava del tutto quando doveva chiedere.
    local_dot="${G}▸${R}"
    case "${age:-0}" in ''|*[!0-9]*) local_dot="${D}▸${R}" ;;
      *) if   [ "$age" -gt 300 ]; then local_dot="${RD}▸${R}"
         elif [ "$age" -gt 60 ];  then local_dot="${Y}▸${R}"; fi ;;
    esac
    if [ $((4+${#sid}+1+${#kind})) -le "$W" ]; then
      printf "  %b ${B}%s${R} ${D}%s${R}\n" "$local_dot" "$sid" "$kind"
    else
      printf "  %b ${B}%s${R}\n" "$local_dot" "$sid"; printf "${D}"; wrap "    " "$kind"; printf "${R}"
    fi
    printf "    ${D}%s${R}\n" "$(fit "$where")"
    [ "${cmd:--}" = "-" ] || printf "    ${D}%s${R}\n" "$(fit "$cmd")"
    # "Quanto manca": passo raggiunto quando c'e', mai una previsione. Il trattino e' una
    # risposta onesta e voluta — un numero inventato qui e' peggio di nessun numero.
    printf "${D}"
    if [ "${age:-999}" -le 60 ] 2>/dev/null; then
      wrap "    " "passo ${step:--} · ${units:--} unita · attivo"
    else
      wrap "    " "passo ${step:--} · ${units:--} unita · fermo da $(dur "${age:-}")"
    fi
    printf "${R}"
  done
  [ "$(v agenti)" = "0" ] && { printf "${D}"; wrap "  " "nessuno in questo progetto"; printf "${R}"; }
  line

  # --- GIT ------------------------------------------------------------------------------
  hdr "GIT" ""
  if [ "${dirty:-0}" = "0" ]; then bullet "${G}✓${R}" "niente da salvare"
  elif [ "$dirty" = "1" ]; then bullet "${Y}!${R}" "1 cosa non salvata"
  else bullet "${Y}!${R}" "$dirty cose non salvate"; fi
  [ "$(v unpushed)" != "0" ] && bullet "${Y}!${R}" "$(v unpushed) commit non mandati"
  printf "${D}"; wrap "  " "$(v worktrees) copie di lavoro"; printf "${R}"
  vs wt | while IFS='|' read -r nm _ dty ah; do
    [ "${dty:-0}" = "0" ] && [ "${ah:-0}" = "0" ] && continue
    printf "  ${Y}!${R} %s\n" "$(fit "$nm")"
    printf "${D}"; wrap "    " "$dty da salvare · $ah da integrare"; printf "${R}"
  done
  line

  # --- CONTROLLI ------------------------------------------------------------------------
  hdr "CONTROLLI" ""
  vs ci | head -3 | while IFS='|' read -r st cc ti; do
    case "$st|$cc" in
      completed\|success) bullet "${G}✓${R}" "$ti" ;;
      completed\|*)       bullet "${RD}✗${R}" "$ti" ;;
      *)                  bullet "${C}◐${R}" "$ti" ;;
    esac
  done
  line

  # --- LA TUA RICHIESTA ------------------------------------------------------------------
  # Vuota di proposito quando l'agente non l'ha scritta: un elenco inventato qui varrebbe
  # meno di niente, perche' e' proprio il posto in cui Roberto va a vedere se e' stato
  # dimenticato un pezzo.
  local tot fatti
  tot="$(vs ask | wc -l | tr -d ' ')"
  if [ "${tot:-0}" != "0" ]; then
    fatti="$(vs ask | grep -c '^fatto|' || true)"
    hdr "LA TUA RICHIESTA" "$fatti/$tot"
    vs ask | while IFS='|' read -r stt txt; do
      case "$stt" in
        fatto) bullet "${G}✓${R}" "$txt" ;;
        corso) bullet "${C}◐${R}" "$txt" ;;
        *)     bullet "${RD}○${R}" "$txt" ;;
      esac
    done
    line
  fi

  printf "${D}"; wrap "  " "$(v bus) messaggi fra agenti"
  wrap "  " "$(v richieste_oggi) richieste oggi · $(v unita_oggi) unita"; printf "${R}"
  if [ "$age" -gt $((EVERY*4)) ]; then
    printf "${Y}"; wrap "  " "foto di $(dur "$age") fa"; printf "${R}"
  else
    printf "${D}"; wrap "  " "aggiornato $(dur "$age") fa · q esce"; printf "${R}"
  fi
}

refresh_if_stale
if [ "$ONCE" = "1" ]; then draw; exit 0; fi

trap 'printf "\033[?25h\033[0m\n"; exit 0' INT TERM
printf '\033[?25l\033[2J'
# Il ridisegno sta FERMO. Pulire tutto lo schermo e riscriverlo (\033[2J a ogni giro) fa
# sfarfallare la finestrella e, se il disegno e' anche solo una riga piu' alto del riquadro,
# la fa scorrere: il risultato e' quello che Roberto ha visto, uno scorrimento continuo.
# Qui si torna in alto, si riscrive riga per riga cancellando solo la coda di ciascuna
# (\033[K), e alla fine si pulisce quel che resta sotto (\033[J). E non si scrive mai
# sull'ultima riga del riquadro: e' scrivere li' che fa scorrere un terminale.
while :; do
  refresh_if_stale
  out="$(draw)"
  printf '\033[H'
  n=0
  while IFS= read -r l; do
    n=$((n+1)); [ "$n" -ge "$H" ] && break
    printf '%s\033[K\n' "$l"
  done <<EOF
$out
EOF
  printf '\033[J'
  read -r -t 2 -n 1 k 2>/dev/null && case "$k" in q|Q) break ;; esac
done
printf '\033[?25h\033[0m\n'
