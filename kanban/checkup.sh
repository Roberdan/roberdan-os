#!/usr/bin/env bash
# kanban/checkup.sh — il controllo di TUTTO il sistema, in un comando solo: `kb checkup`.
#
# Il difetto che chiude non e' "sporco": e' INVISIBILE. Il 2026-09-13 c'erano 99 copie di lavoro
# abbandonate, conversazioni fra agenti lasciate a meta' su card gia' chiuse, e card aperte da
# giorni in repo che nessuno guardava piu'. Nessuna di queste cose era rotta: nessuna schermata
# le nominava. Un sistema che non si guarda addosso accumula, e accumula in silenzio.
#
# Quattro sezioni, quattro proprieta' diverse, una sola regola comune:
#   REFERTO di default, RIMOZIONE solo con --yes — e solo di cio' che non ha niente da perdere.
# L'ambito segue dove sei: dentro roberdan-os guarda tutto il parco, dentro un progetto guarda
# solo quel progetto (--all forza tutto). Un comando che da dentro un progetto ti tocca anche
# gli altri e' un comando che non si lancia piu'.
set -uo pipefail
# Il percorso puo' arrivare da un symlink (~/.local/bin, wrapper di piattaforma): senza questo
# giro di risoluzione lo script cercherebbe i suoi fratelli accanto al link, non accanto a se'.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _d
ROOT="$(cd -P "$DIR/.." && pwd)"
RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
BUS_HOME="${RDA_BUS_HOME:-$RDA_HOME/bus}"
WT_HOME="${RDA_WORKTREES:-$HOME/GitHub/worktrees}"
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"
FERME_GIORNI="${RDA_CHECKUP_STALE_DAYS:-3}"

APPLY=0; ALL=0
for a in "$@"; do
  case "$a" in
    --yes) APPLY=1 ;;
    --all) ALL=1 ;;
  esac
done

# Di quale repo parliamo: stessa regola di worktree-sweep.sh, ripetuta qui perche' questo
# script deve poter girare anche da solo.
_scope() {
  local top name
  [ "$ALL" = "1" ] && return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 0
  name="$(basename "$top")"
  case "$top/" in "$WT_HOME"/*) name="$(basename "$(dirname "$top")")" ;; esac
  [ "$name" = "roberdan-os" ] && return 0
  printf '%s' "$name"
}
ONLY="$(_scope)"

_hr() { printf '\n\033[1m%s\033[0m\n' "$1"; }
# L'ora di modifica di un file: `stat -f` e' BSD (macOS), `stat -c` e' GNU (Linux/CI). Qui gira
# in tutti e due i posti, e un referto che su CI stampa 0 giorni per tutto non e' un referto.
_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

_giorni_fa() { # <epoch> -> giorni interi
  awk -v t="${1:-0}" -v n="$(date +%s)" 'BEGIN{ if(t<=0){print 0} else {printf "%d", (n-t)/86400} }'
}

if [ -n "$ONLY" ]; then
  printf 'controllo del sistema — ambito: solo %s (da roberdan-os, o con --all, guarda tutto)\n' "$ONLY"
else
  printf 'controllo del sistema — ambito: tutti i repo\n'
fi

# --- 1) copie di lavoro ------------------------------------------------------------------
_hr "1. Copie di lavoro"
FLAGS=(); [ "$APPLY" = "1" ] && FLAGS+=(--yes); [ "$ALL" = "1" ] && FLAGS+=(--all)
bash "$DIR/worktree-sweep.sh" sweep "${FLAGS[@]}" | sed 's/^/  /'

# --- 2) cache, build, temporanei ---------------------------------------------------------
_hr "2. Cache, build e temporanei"
JFLAGS=(); [ "$APPLY" = "1" ] && JFLAGS+=(--yes); [ -n "$ONLY" ] && JFLAGS+=(--only "$ONLY")
bash "$DIR/junk.sh" "${JFLAGS[@]}" | sed 's/^/  /'

# --- 3) conversazioni fra agenti lasciate a meta' ----------------------------------------
# Una conversazione e' "appesa" quando e' ancora aperta, nessuno la tocca da giorni, e la card
# di cui parla non e' piu' in lavorazione. Chiuderla non cancella NIENTE: `bus log` continua a
# leggere tutto il filo: e' il motivo per cui questa e' l'unica delle quattro azioni che puo'
# essere automatica senza rischio. Un messaggio non letto su una card VIVA non si tocca mai.
_hr "3. Messaggi fra agenti"
_card_viva() { # <repo> <card-id> -> 0 se esiste una card in todo/ o doing/
  local repo="$1" id="$2" base
  for base in "$HOME/GitHub/$repo/kanban" "$ROOT/kanban"; do
    [ -d "$base" ] || continue
    [ -f "$base/doing/$id.md" ] || [ -f "$base/todo/$id.md" ] && return 0
  done
  return 1
}
n_app=0; n_chiusi=0; n_vivi=0
for repodir in "$BUS_HOME"/*/; do
  [ -d "$repodir" ] || continue
  repo="$(basename "$repodir")"
  [ -n "$ONLY" ] && [ "$repo" != "$ONLY" ] && continue
  for log in "$repodir"*.jsonl; do
    [ -f "$log" ] || continue
    card="$(basename "$log" .jsonl)"
    grep -q '"kind":"closed"' "$log" 2>/dev/null && continue        # gia' chiusa
    eta="$(_giorni_fa "$(_mtime "$log")")"
    # non letti: messaggi totali meno il cursore piu' avanzato fra i ruoli coinvolti
    tot="$(grep -c . "$log" 2>/dev/null || echo 0)"
    piu_indietro="$tot"
    for c in "$repodir.cursor/$card"/*; do
      [ -f "$c" ] || continue
      v="$(tr -dc '0-9' < "$c")"; v="${v:-0}"
      [ "$v" -lt "$piu_indietro" ] && piu_indietro="$v"
    done
    non_letti=$(( tot - piu_indietro )); [ "$non_letti" -lt 0 ] && non_letti=0
    if _card_viva "$repo" "$card"; then
      n_vivi=$((n_vivi+1))
      [ "$non_letti" -gt 0 ] && printf '  %s/%s — %s messaggi non letti, la card e\x27 VIVA: non si tocca\n' "$repo" "$card" "$non_letti"
      continue
    fi
    [ "$eta" -lt "$FERME_GIORNI" ] && continue
    n_app=$((n_app+1))
    if [ "$APPLY" = "1" ]; then
      if bash "$ROOT/bus/bus.sh" close --repo "$repo" --card "$card" --by implementer >/dev/null 2>&1; then
        n_chiusi=$((n_chiusi+1)); printf '  chiusa   %s/%s (ferma da %s giorni, card non piu\x27 in lavorazione)\n' "$repo" "$card" "$eta"
      else
        printf '  NON chiusa %s/%s (il bus ha rifiutato)\n' "$repo" "$card"
      fi
    else
      printf '  aperta da %s giorni  %s/%s — %s messaggi, card non piu\x27 in lavorazione\n' "$eta" "$repo" "$card" "$tot"
    fi
  done
done
if [ "$n_app" -eq 0 ]; then
  printf '  nessuna conversazione appesa (%s su card ancora vive, giustamente intatte)\n' "$n_vivi"
elif [ "$APPLY" = "1" ]; then
  printf '\n  %s conversazioni chiuse (il testo resta leggibile con bus log)\n' "$n_chiusi"
else
  printf '\n  %s conversazioni da chiudere — per chiuderle: kb checkup --yes\n' "$n_app"
fi

# --- 4) card aperte, repo per repo -------------------------------------------------------
# Qui NON si tocca niente, mai, nemmeno con --yes: una card e' una decisione di Roberto, e
# "ferma da giorni" non vuol dire "da buttare" — vuol dire "guardala". L'unica cosa che questa
# sezione produce e' visibilita'.
_hr "4. Card aperte"
_boards() {
  [ -f "$REGISTRY" ] && grep -v '^#' "$REGISTRY" | grep -v '^$'
  printf '%s\n' "$ROOT"
}
tot_doing=0; tot_todo=0
while IFS= read -r repo_path; do
  [ -d "$repo_path/kanban" ] || continue
  nome="$(basename "$repo_path")"
  [ -n "$ONLY" ] && [ "$nome" != "$ONLY" ] && continue
  n_doing=0; n_todo=0
  for c in doing todo; do
    for f in "$repo_path/kanban/$c"/*.md; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in _*) continue ;; esac
      [ "$c" = doing ] && n_doing=$((n_doing+1)) || n_todo=$((n_todo+1))
    done
  done
  tot_doing=$((tot_doing + n_doing)); tot_todo=$((tot_todo + n_todo))
  [ "$n_doing" -eq 0 ] && [ "$n_todo" -eq 0 ] && continue
  printf '  %-22s %s in lavorazione · %s in attesa\n' "$nome" "$n_doing" "$n_todo"
  for f in "$repo_path/kanban/doing"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _*) continue ;; esac
    eta="$(_giorni_fa "$(_mtime "$f")")"
    [ "$eta" -ge "$FERME_GIORNI" ] && printf '      ferma da %s giorni: %s\n' "$eta" "$(basename "$f" .md)"
  done
done <<EOF
$(_boards | sort -u)
EOF
printf '\n  %s card in lavorazione · %s in attesa. Nessuna viene toccata da qui: le card sono decisioni tue.\n' "$tot_doing" "$tot_todo"

if [ "$APPLY" != "1" ]; then
  printf '\n\033[1mNiente e\x27 stato toccato.\033[0m Per applicare le pulizie proposte: kb checkup --yes\n'
fi
