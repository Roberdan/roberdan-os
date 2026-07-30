#!/usr/bin/env bash
# test-kb-queue.sh — l'autorizzazione permanente di Roberto, e il suo unico limite.
#
# DECISIONE DI ROBERTO, 2026-07-30: "completa tutte le card che ci sono quando comincia una
# sessione e poi fermati, così io vedo solo se hai aggiunto altro." Il gate umano
# `todo → doing` non è più per singola card: è per LISTA, fotografata all'inizio.
#
# La proprietà che rende questo uno spostamento del gate e non una rimozione è UNA SOLA, ed è
# quella che questo file esiste per proteggere: **una card creata dopo lo scatto non parte**.
# Se quella proprietà cade, un agente può crearsi il lavoro da solo e autorizzarselo — cioè
# esattamente ciò che il gate impediva. Ogni asserzione qui è nei due sensi.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KBSH="$ROOT/kanban/kb.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
KB="$TMP/board"; mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
kb() { RDA_KANBAN="$KB" RDA_KANBAN_REGISTRY="$TMP/registry" bash "$KBSH" "$@" 2>&1; }
_dice() { local atteso="$1"; shift; shift; local o; o="$("$@")"; case "$o" in *"$atteso"*) return 0 ;; *) return 1 ;; esac; }

_card() { cat > "$KB/todo/$1.md" <<CARD
---
title: card $1
repo: ${2:-provarepo}
dod: "una dod"
acceptance: "il comando stampa il risultato"
status: todo
created: 2026-07-30
---
CARD
}
_chiudi() { mv "$KB/doing/$1.md" "$KB/done/" 2>/dev/null; }

printf '\n=== lo scatto ===\n'

_card C1; _card C2; _card C3
_card X1 altrorepo   # un altro progetto sulla stessa board: non deve entrare nella coda
if _dice "3 card" -- kb queue provarepo; then
  ok "fotografa solo le card del repo chiesto (3, non 4)"
else
  err "la coda ha preso card di un altro progetto: farebbe partire lavoro dove non sei"
fi

printf '\n=== camminare da soli ===\n'

if _dice "prendo C1" -- kb next provarepo; then
  ok "kb next prende la prima SENZA chiedere approvazione"
else
  err "kb next non parte: l'autorizzazione permanente non funziona, e Roberto resta il collo di bottiglia"
fi

# La riga di audit sulla card deve dire da DOVE viene l'approvazione. Un'autorizzazione che non
# lascia traccia è indistinguibile da un agente che si è approvato il lavoro da solo.
if grep -q 'coda autorizzata' "$KB/doing/C1.md"; then
  ok "la card registra che l'approvazione viene dalla coda, non da un --by inventato"
else
  err "la card non dice da dove viene l'approvazione: l'audit non distingue la coda da un bypass"
fi

if _dice "gia' una card in corso" -- kb next provarepo; then
  ok "la regola 'una card per progetto' vale ancora dentro la coda"
else
  err "kb next apre un secondo fronte: la coda ha scavalcato la regola 1"
fi

_chiudi C1
if _dice "prendo C2" -- kb next provarepo; then
  ok "chiusa la prima, prende la seconda da sola"
else
  err "la coda si ferma dopo una card: non cammina"
fi
_chiudi C2; kb next provarepo >/dev/null; _chiudi C3

printf '\n=== IL LIMITE: cio che nasce dopo NON e autorizzato ===\n'

_card NUOVA1; _card NUOVA2
out="$(kb next provarepo)"
case "$out" in
  *"LISTA FINITA"*) ok "a lista esaurita si ferma, invece di continuare all'infinito" ;;
  *) err "non si ferma a lista finita: '$out'" ;;
esac
case "$out" in
  *"NATE DOPO"*NUOVA1*NUOVA2*) ok "elenca per nome le card nate dopo lo scatto — l'unica cosa che Roberto vuole vedere" ;;
  *) err "NON mostra le card nate dopo: il gate spostato diventa un gate TOLTO. Output: $out" ;;
esac
# E soprattutto: non le ha fatte partire.
if [ -e "$KB/todo/NUOVA1.md" ] && [ ! -e "$KB/doing/NUOVA1.md" ]; then
  ok "una card creata DOPO lo scatto resta in attesa: non se l'e' autorizzata da sola"
else
  err "una card creata dopo lo scatto E' PARTITA: un agente puo' crearsi e approvarsi il lavoro"
fi

printf '\n=== revoca ===\n'

if _dice "coda revocata" -- kb queue provarepo --stop; then
  ok "si revoca"
else
  err "non si revoca: un'autorizzazione permanente senza uscita non e' un'autorizzazione, e' una resa"
fi
if _dice "REFUSED" -- kb next provarepo; then
  ok "revocata, kb next rifiuta e si torna all'approvazione per card"
else
  err "dopo la revoca kb next parte lo stesso: la revoca non revoca niente"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-kb-queue: PASS" || echo "test-kb-queue: FAIL"
exit "$FAIL"
