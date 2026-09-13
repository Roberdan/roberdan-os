#!/usr/bin/env bash
# kanban/top.sh — la finestrella di stato: `kb top`.
#
# Disegna e basta. Ogni dato arriva da `snapshot.sh`, che gira in sottofondo: qui dentro non
# c'e' nessun comando lento, ed e' il motivo per cui puo' ridisegnarsi ogni due secondi senza
# scaldare il Mac. Se la fotografia e' vecchia, si vede scritto quanto e' vecchia — non si
# finge che sia fresca.
#
# Larghezza ~34 colonne: sta in una finestrella stretta accanto all'editor.
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
W="${RDA_TOP_WIDTH:-34}"
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

line() { printf "${D}%s${R}\n" "$(printf '─%.0s' $(seq 1 "$W"))"; }
hdr()  { local l="$1" r="${2:-}"; printf "${B}%s${R}${D}%*s${R}\n" "$l" $((W-${#l})) "$r"; }
cut_() { printf '%s' "$1" | cut -c1-$((W-4)); }
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
  here="$(v qui)"; branch="$(v branch)"; dirty="$(v dirty)"
  printf "${B}${C}%s${R} ${D}%s${R}\n" "$(cut_ "$REPO")" "$(cut_ "$branch")"
  [ "$here" != "$REPO" ] && printf "  ${D}sei in: %s${R}\n" "$(cut_ "$here")"
  line

  # --- LAVORO ---------------------------------------------------------------------------
  hdr "LAVORO" "$(v card_doing) in corso"
  vs card | while IFS='|' read -r id ti st; do
    printf "  ${G}●${R} %s\n" "$(cut_ "$ti")"
    printf "    ${D}da %s · %s${R}\n" "$(dur $(( now - ${st:-now} )) )" "$id"
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
    printf "  %b ${B}%s${R} ${D}%s${R}\n" "$local_dot" "$sid" "$kind"
    printf "    ${D}%s${R}\n" "$(cut_ "$where")"
    [ "${cmd:--}" = "-" ] || printf "    ${D}%s${R}\n" "$(cut_ "$cmd")"
    # "Quanto manca": passo raggiunto quando c'e', mai una previsione. Il trattino e' una
    # risposta onesta e voluta — un numero inventato qui e' peggio di nessun numero.
    if [ "${age:-999}" -le 60 ] 2>/dev/null; then
      printf "    ${D}passo %s · %s unita · attivo${R}\n" "${step:--}" "${units:--}"
    else
      printf "    ${D}passo %s · %s unita · fermo da %s${R}\n" "${step:--}" "${units:--}" "$(dur "${age:-}")"
    fi
  done
  [ "$(v agenti)" = "0" ] && printf "  ${D}nessuno in questo progetto${R}\n"
  line

  # --- GIT ------------------------------------------------------------------------------
  hdr "GIT" ""
  if [ "${dirty:-0}" = "0" ]; then printf "  ${G}✓${R} niente da salvare\n"
  elif [ "$dirty" = "1" ]; then printf "  ${Y}!${R} 1 cosa non salvata\n"
  else printf "  ${Y}!${R} %s cose non salvate\n" "$dirty"; fi
  [ "$(v unpushed)" != "0" ] && printf "  ${Y}!${R} %s commit non mandati\n" "$(v unpushed)"
  printf "  ${D}%s copie di lavoro${R}\n" "$(v worktrees)"
  vs wt | while IFS='|' read -r nm _ dty ah; do
    [ "${dty:-0}" = "0" ] && [ "${ah:-0}" = "0" ] && continue
    printf "  ${Y}!${R} %s\n" "$(cut_ "$nm")"
    printf "    ${D}%s da salvare · %s da integrare${R}\n" "$dty" "$ah"
  done
  line

  # --- CONTROLLI ------------------------------------------------------------------------
  hdr "CONTROLLI" ""
  vs ci | head -3 | while IFS='|' read -r st cc ti; do
    case "$st|$cc" in
      completed\|success) printf "  ${G}✓${R} %s\n" "$(cut_ "$ti")" ;;
      completed\|*)       printf "  ${RD}✗${R} %s\n" "$(cut_ "$ti")" ;;
      *)                  printf "  ${C}◐${R} %s\n" "$(cut_ "$ti")" ;;
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
        fatto) printf "  ${G}✓${R} %s\n" "$(cut_ "$txt")" ;;
        corso) printf "  ${C}◐${R} %s\n" "$(cut_ "$txt")" ;;
        *)     printf "  ${RD}○${R} %s\n" "$(cut_ "$txt")" ;;
      esac
    done
    line
  fi

  printf "  ${D}%s messaggi fra agenti${R}\n" "$(v bus)"
  printf "  ${D}%s richieste oggi · %s unita${R}\n" "$(v richieste_oggi)" "$(v unita_oggi)"
  if [ "$age" -gt $((EVERY*4)) ]; then
    printf "  ${Y}foto di %s fa${R}\n" "$(dur "$age")"
  else
    printf "  ${D}aggiornato %s fa · q esce${R}\n" "$(dur "$age")"
  fi
}

refresh_if_stale
if [ "$ONCE" = "1" ]; then draw; exit 0; fi

trap 'printf "\033[?25h\033[0m\n"; exit 0' INT TERM
printf '\033[?25l'
while :; do
  refresh_if_stale
  out="$(draw)"
  printf '\033[H\033[2J%s' "$out"
  read -r -t 2 -n 1 k 2>/dev/null && case "$k" in q|Q) break ;; esac
done
printf '\033[?25h\033[0m\n'
