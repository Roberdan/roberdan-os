#!/usr/bin/env bash
# test-edge-only.sh — Playwright parla con Edge, e se non c'è si ferma.
#
# LIMITE DICHIARATO IN CIMA, perché è la cosa che rende onesto il verde di questo file:
# **oggi in roberdan-os non c'è una riga di codice Playwright.** Quindi questo gate non sta
# verificando che qualcosa usi Edge — sta impedendo che il primo codice browser che entrerà
# qui nasca puntato su Chrome. Un PASS qui significa "nessuno ha violato la regola", non
# "abbiamo visto Edge funzionare". Leggerlo nell'altro modo sarebbe un done falso.
#
# `test/test-canon-guardrails.sh` protegge già la FRASE nel canone. Questo protegge il
# COMPORTAMENTO, ed è una distinzione che in questo repo è già costata: una regola scritta e
# mai misurata è un'opinione ben scritta (vedi il limite delle 300 righe, dichiarato per
# settimane mentre undici file lo superavano).
#
# L'ECCEZIONE È PREVISTA E VA SCRITTA: la card dice che il test cross-browser chiesto da
# Roberto è l'unico caso legittimo. Si dichiara con il marcatore qui sotto, sulla riga stessa o
# su quella prima — così l'eccezione vive nel diff che una persona legge, non nella memoria di
# chi l'ha introdotta.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
MARCATORE='cross-browser: richiesto da Roberto'
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

# I file di documentazione nominano Chrome per VIETARLO: cercarli qui renderebbe il gate rosso
# sul canone che lo istituisce. Si guarda il codice.
_codice() {
  git ls-files 2>/dev/null | grep -vE '\.(md|txt|json|lock)$' | grep -vE '^(docs/|CHANGELOG)'
}

# Le forme con cui Playwright sceglie il browser, scritte QUI SPEZZATE di proposito:
#   chromium ⟨punto⟩ launch()   ·   channel ⟨due punti⟩ "chrome"
#   --browser ⟨spazio⟩ chromium ·   browser_type ⟨uguale⟩ "chromium"
#
# Spezzate perché la prima stesura le scriveva per esteso e **questo file faceva fallire se
# stesso**: la CI diventava rossa citando le righe di commento che spiegavano cosa cercare.
# La tentazione era escludere questo file dalla scansione — sarebbe stato un gate cieco
# proprio su se stesso, cioè il posto più comodo dove nascondere una violazione vera.
# Si cercano le FORME, non la parola sola: "chromium" dentro una frase che spiega perché non
# si usa è legittimo, ed è esattamente ciò che stai leggendo.
_violazioni() {
  local f n riga
  while read -r f; do
    [ -f "$f" ] || continue
    grep -nE 'chromium[[:space:].]*\.?launch|channel[[:space:]]*[:=][[:space:]]*.?(chrome|chromium)|--browser[[:space:]]+(chrome|chromium)|browser_type[[:space:]]*=[[:space:]]*.?(chrome|chromium)' \
      "$f" 2>/dev/null | while IFS=: read -r n riga; do
        # L'eccezione, sulla riga stessa o su quella prima.
        case "$riga" in *"$MARCATORE"*) continue ;; esac
        [ "$n" -gt 1 ] && case "$(sed -n "$((n-1))p" "$f")" in *"$MARCATORE"*) continue ;; esac
        printf '%s:%s: %s\n' "$f" "$n" "$(printf '%s' "$riga" | sed 's/^[[:space:]]*//' | cut -c1-70)"
      done
  done <<EOF
$(_codice)
EOF
}

printf '\n'
v="$(_violazioni)"
if [ -z "$v" ]; then
  ok "nessun codice avvia Chrome o Chromium ($(_codice | wc -l | tr -d ' ') file esaminati)"
else
  printf '%s\n' "$v" | while read -r riga; do
    err "avvia un browser che non è Edge: $riga"
  done
  FAIL=1
fi

# La regola vale solo se l'assenza di Edge è un BLOCCO, non un ripiego silenzioso. Qui non c'è
# codice da controllare, quindi si protegge la clausola che lo impone: è l'unica cosa che
# esiste oggi, e dirlo è più onesto che inventare un controllo che non misura niente.
if grep -q 'If Edge is unavailable, stop and report the blocker' rules/best-practices.md; then
  ok "il canone impone di FERMARSI quando Edge manca, invece di ripiegare in silenzio"
else
  err "il canone non impone più il blocco su Edge assente: senza quella clausola il ripiego torna legittimo"
fi

# E l'eccezione deve restare esprimibile, altrimenti il gate verrebbe aggirato commentandolo.
if grep -q 'override only for Roberto-requested cross-browser tests' rules/best-practices.md; then
  ok "l'eccezione cross-browser resta prevista dal canone, e si dichiara con: $MARCATORE"
else
  err "l'eccezione non è più nel canone: un gate senza uscita dichiarata viene aggirato, non rispettato"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-edge-only: PASS" || echo "test-edge-only: FAIL"
exit "$FAIL"
