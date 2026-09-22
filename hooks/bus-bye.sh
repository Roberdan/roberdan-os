#!/usr/bin/env bash
# hooks/bus-bye.sh — dire che te ne sei andato, quando te ne vai davvero.
#
# IL PROBLEMA. `context-inject.sh` presenta la sessione sul bus all'apertura
# (`bus hello`). Senza il congedo, chi arriva dopo trova un elenco di presenti
# che si allunga per sempre e in cui nessuno se n'e' mai andato: un elenco cosi'
# non dice piu' chi c'e', dice solo chi c'e' stato — ed e' il punto da cui questa
# riprogettazione e' partita.
#
# DOVE E' AGGANCIATO, E DOVE NO. Solo su `onSessionEnd` (Copilot CLI). NON su
# `Stop` ne' su `onAgentStop`: quelli scattano alla fine di OGNI TURNO, e una
# sessione che si dichiara finita dopo ogni turno riempie la vista di fantasmi.
# Claude Code non ha alcun evento di fine sessione — li' il congedo resta un
# comando che l'agente esegue, ed e' scritto in AGENTS.md.
#
# E' AL MEGLIO DELLE POSSIBILITA', e solo quello. Un crash, un kill o il coperchio
# chiuso non consegnano nessun callback. Per questo una presenza dichiarata e mai
# ritirata e' uno stato NORMALE, ed e' esattamente il motivo per cui `bus who`
# stampa la dichiarazione ACCANTO all'ultima attivita' osservata invece di
# crederle: la dichiarazione dice cosa la sessione ha detto di se', l'osservazione
# dice cosa ha fatto, e quando le due non coincidono chi legge vede la differenza.
#
# NON BLOCCA NIENTE e non puo' far fallire l'uscita: ogni via porta a exit 0.
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
sid="$(jq -r '.session_id // ""' <<<"$payload" 2>/dev/null | tr -cd 'A-Za-z0-9._-' || echo "")"

RDA_OS="${RDA_OS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUS="$RDA_OS/bus/bus.sh"
[ -f "$BUS" ] || exit 0

# Il nome del repo e' quello del CHECKOUT PRINCIPALE, mai quello della copia di
# lavoro per-card: stessa ragione, e stesso una-riga, di bus-doorbell.sh — dentro
# una copia `--show-toplevel` risponde <card-id>, e il congedo finirebbe in un
# repo diverso da quello in cui la sessione si era presentata.
top=""
common="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$common" ]; then
  case "$common" in /*) : ;; *) common="$cwd/$common";; esac
  top="$(cd "$common/.." 2>/dev/null && pwd || true)"
fi
[ -n "$top" ] || top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
repo="$(basename "${top:-$cwd}")"
case "$repo" in ''|.|..) exit 0;; esac

# Nessuna presenza per questo repo = niente da chiudere, e nessun record inventato.
BUS_HOME="${RDA_BUS_HOME:-${RDA_HOME:-$HOME/.roberdan-os}/bus}"
[ -f "$BUS_HOME/$repo/.presence.jsonl" ] || exit 0

# Il ruolo: quello dichiarato all'apertura. Si cerca RISALENDO DA `cwd`, non nel
# checkout principale: `bus hello` lascia `.bus-role` in cima alla COPIA DI LAVORO
# (e' li' che si lavora), mentre `$top` qui e' il progetto. Cercarlo in `$top`
# funzionava solo fuori dalle copie di lavoro — cioe' quasi mai, e in silenzio.
# Se non c'e' modo di sapere chi era questa sessione, non si scrive niente: un
# congedo a nome di un ruolo indovinato e' peggio di un congedo mancato.
role="${RDA_BUS_ROLE:-}"
if [ -z "$role" ]; then
  _d="$cwd"
  while [ -n "$_d" ] && [ "$_d" != "/" ]; do
    if [ -f "$_d/.bus-role" ]; then
      role="$(tr -d '[:space:]' < "$_d/.bus-role" 2>/dev/null || true)"
      break
    fi
    _d="${_d%/*}"
  done
fi
[ -n "$role" ] || exit 0

( cd "$cwd" 2>/dev/null || exit 0
  bash "$BUS" bye --repo "$repo" --as "$role" ${sid:+--session "$sid"} \
       --why "sessione chiusa" >/dev/null 2>&1 || true )
exit 0
