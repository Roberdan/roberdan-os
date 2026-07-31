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
dir="${2:-$ROOT}"
tmo="${3:-600}"
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

verify_card "$card" "$dir" "$tmo" "$vlog"
