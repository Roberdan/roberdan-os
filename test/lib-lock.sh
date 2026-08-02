#!/usr/bin/env bash
# lib-lock.sh — il lucchetto delle suite bus, con dentro il nome di chi lo tiene.
#
# PERCHE' (rilievo 23, due occorrenze il 2 agosto 2026). `mkdir` come lucchetto e' giusto —
# atomico, funziona su bash 3.2 di macOS dove `flock` non c'e'. Il difetto e' che veniva
# rilasciato SOLO da un `trap ... EXIT`, e un trap non gira quando il processo viene ucciso.
# Due volte in un giorno una verifica di @thor finita male ha lasciato la cartella li', e il
# `validate.sh` successivo e' uscito **rosso su test-bus**, che non c'entrava niente.
#
# E' il caso peggiore per una protezione: il rosso non e' sul difetto, e' su un innocente. Chi lo
# incontra impara a cancellare i lucchetti a mano — cioe' impara a disarmare la protezione. Un
# lucchetto che nessuno si fida di rispettare non protegge piu' niente.
#
# La riparazione: il lucchetto dice CHI lo tiene. Se quel processo non esiste piu', e' un orfano
# e si puo' riusare. Se esiste, il rifiuto e' vero e va rispettato.
#
# Limite dichiarato: un PID puo' essere riusato dal sistema operativo. Se il numero e' stato
# riassegnato a un processo vivo qualunque, questo codice legge "occupato" e rifiuta — sbaglia
# verso il lato prudente, che e' quello giusto per un lucchetto.

# bus_lock_acquire <cartella>  ->  0 preso, 1 occupato davvero
bus_lock_acquire() {
  local d="$1" p=""
  if mkdir "$d" 2>/dev/null; then
    printf '%s\n' "$$" > "$d/pid" 2>/dev/null
    return 0
  fi

  p="$(cat "$d/pid" 2>/dev/null || true)"
  case "$p" in
    ''|*[!0-9]*)
      # Nessun PID leggibile. Puo' essere (a) un lucchetto di una versione vecchia, (b) un
      # orfano, oppure (c) il proprietario ha appena fatto mkdir e non ha ancora scritto il
      # file: una finestra di microsecondi. Aspetto un secondo e rileggo, invece di dichiarare
      # orfano un lucchetto legittimo nato un istante fa.
      sleep 1
      p="$(cat "$d/pid" 2>/dev/null || true)"
      case "$p" in ''|*[!0-9]*) p="" ;; esac
      ;;
  esac

  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    return 1                      # occupato davvero: il proprietario e' vivo
  fi

  # Orfano: chi l'ha preso non esiste piu'. Lo riuso.
  rm -rf "$d" 2>/dev/null || true
  if mkdir "$d" 2>/dev/null; then
    printf '%s\n' "$$" > "$d/pid" 2>/dev/null
    return 0
  fi
  return 1                        # qualcun altro l'ha preso nel frattempo: rifiuto vero
}

# bus_lock_owner <cartella> -> stampa il PID scritto dentro, o "sconosciuto"
bus_lock_owner() {
  local p; p="$(cat "$1/pid" 2>/dev/null || true)"
  case "$p" in ''|*[!0-9]*) printf 'sconosciuto\n' ;; *) printf '%s\n' "$p" ;; esac
}
