#!/usr/bin/env bash
# thor-verify.sh — esegue @thor su UNA card e stampa una riga sola:
#     PASS<TAB><evidenza>     i criteri della card risultano soddisfatti
#     FAIL<TAB><motivo>       non lo sono, oppure la verifica non e' andata a buon fine
#     SKIP<TAB><perche>       @thor non e' eseguibile qui (non e' un verdetto, e non va letto come tale)
#
# PERCHE' ESISTE. Il cancello doing->done e' di @thor, ma finora thor lo attraversava solo se
# qualcuno glielo chiedeva: `kb finish --thor "<evidenza>"` accettava la frase di chi chiudeva,
# e il sistema stampava "verified by @thor" comunque. Roberto, 2026-07-31: "fai in modo che
# thor vada avanti a validare le card anche senza che io debba dirgli niente."
#
# La verifica vera esisteva gia' — `verify_card()` in factory/lib.sh, usata dalla factory per i
# task autonomi. Qui non se ne scrive una seconda: si riusa quella. Due implementazioni dello
# stesso cancello divergono, e quella meno usata diventa la piu' permissiva.
#
# SKIP e FAIL sono tenuti distinti apposta. "Non ho potuto verificare" e "ho verificato e non va
# bene" sono fatti diversi, e confonderli e' esattamente il modo in cui un cancello diventa un
# timbro: chi chiama decide cosa fare di uno SKIP, ma non puo' scambiarlo per un PASS.
set -uo pipefail

# Risoluzione della catena di symlink PRIMA di calcolare ROOT: bash non risolve i symlink per
# BASH_SOURCE, riporta il path del link. Stessa medicina di kanban/kb.sh, e c'e' un test che la
# pretende su ogni script di kanban/ (test-kb-root-resolution.sh) proprio perche' il difetto e'
# silenzioso: non rompe niente, punta solo alla cartella sbagliata.
_tv_src="${BASH_SOURCE[0]}"
while [ -L "$_tv_src" ]; do
  _tv_dir="$(cd -P "$(dirname "$_tv_src")" && pwd)"
  _tv_src="$(readlink "$_tv_src")"
  case "$_tv_src" in /*) ;; *) _tv_src="$_tv_dir/$_tv_src" ;; esac
done
ROOT="$(cd -P "$(dirname "$_tv_src")/.." && pwd)"
card="${1:?id card richiesto}"
# LA CARTELLA SI RISOLVE, NON SI DEDUCE. Qui c'era `dir="${2:-$ROOT}"`, ed era il difetto
# 260802-212646: `kb finish` passa `$(_field ... worktree)`, che e' VUOTO per una card senza
# worktree — o con il worktree gia' rimosso — e il fallback mandava @thor dentro il checkout di
# roberdan-os. Non e' un cancello che si rompe: e' un cancello che RISPONDE, sincero, su codice
# che non c'entra niente con la card. E' il gemello cattivo del difetto sul board: quello
# rifiutava per indirizzo, questo APPROVAVA per indirizzo.
#
# L'ordine e': la cartella che chi chiama ha dichiarato, se esiste davvero; altrimenti il
# checkout del repo che LA CARD nomina; altrimenti si rifiuta. Mai $ROOT per deduzione.
dir="${2:-}"
tmo="${3:-1200}"   # 600s non bastava su una card grossa: misurato il 2026-07-31
vlog="${4:-${TMPDIR:-/tmp}/thor-verify-$card-$$.log}"

# Il boccone amaro: thor gira come un processo `claude` separato. Se non c'e', non si finge.
CLAUDE="${CLAUDE:-$(command -v claude 2>/dev/null || true)}"
[ -n "$CLAUDE" ] || { printf 'SKIP\tbinario claude non trovato: @thor non e eseguibile su questa macchina\n' ; exit 0; }

# La ricorsione e il modo ovvio di sbagliare: thor che chiude una card chiamando kb finish che
# chiama thor. Il flag e" ereditato dai figli e taglia la catena al primo giro.
if [ "${RDA_IN_THOR_VERIFY:-0}" = "1" ]; then
  printf 'SKIP\tgia dentro una verifica @thor: non si annida\n'; exit 0
fi
export RDA_IN_THOR_VERIFY=1

TIMEOUT_BIN="$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)"
# shellcheck disable=SC2034  # KB/CLAUDE/TIMEOUT_BIN sono letti da factory/lib.sh dopo il source
KB="${RDA_KANBAN:-$ROOT/kanban}"
export CLAUDE TIMEOUT_BIN KB

# shellcheck source=/dev/null
. "$ROOT/factory/lib.sh" 2>/dev/null || { printf 'SKIP\tfactory/lib.sh non caricabile: la verifica headless non e disponibile\n'; exit 0; }
command -v verify_card >/dev/null 2>&1 || { printf 'SKIP\tverify_card non definita in factory/lib.sh\n'; exit 0; }

# --- la cartella su cui @thor guardera' -----------------------------------------------------
# Una cartella dichiarata ma inesistente non e' una dichiarazione: e' un worktree gia' rimosso.
# Vale quanto il campo vuoto, e prende la stessa strada.
[ -n "$dir" ] && [ ! -d "$dir" ] && dir=""
if [ -z "$dir" ]; then
  # La risoluzione sta QUI dentro, come in kanban/worktree.sh ("kept here so this script stands
  # alone"), e non in un file condiviso. Non e' pigrizia: la prima stesura di questa correzione
  # aveva estratto la funzione in kanban/repo-path.sh e fatto sorgere il file da kb.sh. Misurato:
  # con quel file assente `kb queue --restanti` non stampa il conteggio ma NIENTE, exit 1 muto —
  # e hooks/goal-gate.sh, che legge quel numero, smetteva di bloccare. Una dipendenza tra file
  # che fallisce in senso permissivo e in silenzio e' peggio della copia che voleva evitare.
  # La copia, invece, e' tenuta onesta da test/test-kb-repo-path-agree.sh, che pretende che
  # tutte le implementazioni rispondano identico sugli stessi ingressi.
  _tv_repo_path() {
    local name="$1" reg r
    [ -n "$name" ] || return 1
    reg="${RDA_KANBAN_REGISTRY:-${RDA_HOME:-$HOME/.roberdan-os}/kanban-registry}"
    if [ -f "$reg" ]; then
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        case "$r" in \#*) continue ;; esac
        [ "$(basename "$r")" = "$name" ] && { printf '%s' "$r"; return 0; }
      done < "$reg"
    fi
    [ -d "$HOME/GitHub/$name" ] && { printf '%s' "$HOME/GitHub/$name"; return 0; }
    return 1
  }
  _tv_card_file=""
  for _tv_c in todo doing "done"; do
    [ -e "$KB/$_tv_c/$card.md" ] && _tv_card_file="$KB/$_tv_c/$card.md"
  done
  # SE LA CARD NON SI TROVA, QUI NON SI PARLA. La frase canonica per "card introvabile" e'
  # quella di verify_card(), e viene gia' tradotta in SKIP piu' sotto. Una seconda frase, detta
  # prima e con parole diverse, e' la stessa malattia che questo file combatte: la prima stesura
  # di questa correzione ne aveva aggiunta una, e ha fatto cadere tre suite che si aspettavano —
  # giustamente — la voce di verify_card. Si lascia passare $dir vuoto: verify_card cerca la
  # card PRIMA di guardare la cartella, quindi risponde lei, come ha sempre fatto.
  if [ -n "$_tv_card_file" ]; then
    _tv_repo="$(grep -m1 '^repo:' "$_tv_card_file" 2>/dev/null | sed 's/^repo:[[:space:]]*//; s/^"//; s/"$//')"
    if [ -z "$_tv_repo" ]; then
      printf 'SKIP\tla card %s non dichiara un repo: e non c'"'"'e un worktree: rifiuto invece di dedurre una cartella\n' "$card"; exit 0
    fi
    dir="$(_tv_repo_path "$_tv_repo" || true)"
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
      printf 'SKIP\trepo %s non risolvibile (non nel registro, nessun ~/GitHub/%s): @thor non guardera'"'"' una cartella a caso\n' "$_tv_repo" "$_tv_repo"; exit 0
    fi
  fi
fi

# UN TIMEOUT NON E' UN VERDETTO. verify_card() restituisce FAIL sia quando @thor ha guardato e
# dice no, sia quando la verifica non e' andata a termine (timeout, output illeggibile). Sono i
# due fatti che questo file esiste per tenere separati, e li conflondeva proprio qui: il
# 2026-07-31 una verifica uscita in timeout (exit=124) e' arrivata a chi chiudeva come "@thor ha
# verificato e dice NO". E' la stessa sostituzione che il resto di questo file rifiuta, solo
# nell'altro verso: li' uno SKIP non deve diventare un PASS, qui non deve diventare un FAIL.
out="$(verify_card "$card" "$dir" "$tmo" "$vlog")"
case "$out" in
  FAIL*unparseable*|FAIL*exit=124*|FAIL*"not found in kanban"*)
    printf 'SKIP\t%s\n' "${out#FAIL	}" ;;
  *) printf '%s\n' "$out" ;;
esac
