#!/usr/bin/env bash
# test-thor-verdict.sh — come si legge il verdetto di @thor, e cosa si dice quando non c'e'.
#
# IL DIFETTO (rilievo 20, DUE volte il 2026-08-02, promosso da Roberto). `kb finish --thor` ha
# rifiutato due verifiche RIUSCITE, per due cause diverse:
#
#   (a) @thor aveva scritto `**VERDICT: PASS** — <evidenza>` e la vecchia espressione pretendeva
#       `VERDICT: PASS — ` esatto: il `**` dopo PASS non combaciava. Il verdetto c'era, la
#       verifica era andata, e il gate ha risposto "non e' avvenuta".
#   (b) @thor ha scritto "aspetto l'esito del test completo, non blocco su questo, arrivera' una
#       notifica" e ha FINITO IL TURNO senza verdetto.
#
# Tutte e due finivano nello stesso messaggio, `unparseable thor-verify output`, che manda a
# cercare un difetto di formato anche quando il problema e' che il verificatore si e' fermato a
# meta'. E tutte e due si sono risolte rilanciando identico — che e' la lezione peggiore che un
# cancello possa insegnare: davanti a un rifiuto, ritenta. Un cancello che cede al secondo
# tentativo non e' un cancello.
#
# QUESTO FILE TIENE INSIEME DUE COSE OPPOSTE, e la seconda ha piu' asserzioni della prima:
#   - tollerante sulla FORMA (grassetto, trattino semplice, nessun separatore)
#   - inflessibile sul CONTENUTO: nessun verdetto inventato dove @thor non l'ha scritto. Un
#     lettore troppo generoso trasformerebbe una frase di passaggio in un PASS, e quello
#     chiuderebbe card mai verificate.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/factory/lib.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

# LA FUNZIONE VERA, presa da factory/lib.sh. Non una copia: la prima versione di questo file
# riscriveva la logica a mano, e tre mutanti su cinque applicati al codice vero passavano VERDI
# perche' il test non lo stava nemmeno toccando. Era il difetto che questo file esiste per
# riparare, commesso dentro il file che lo ripara.
# shellcheck source=../factory/lib.sh
. "$LIB"
leggi() { # <testo del log> -> "PASS<TAB>ev" | "FAIL<TAB>ev" | ""
  local vlog; vlog="$(mktemp)"; printf '%s\n' "$1" > "$vlog"
  thor_read_verdict "$vlog"
  rm -f "$vlog"
}
esito() { printf '%s' "$1" | cut -f1; }
prova() { printf '%s' "$1" | cut -f2; }

printf '\n=== il lettore vive nel file vero, non in una copia ===\n'
command -v thor_read_verdict >/dev/null 2>&1 \
  && ok "il test chiama thor_read_verdict di factory/lib.sh, non una copia" \
  || err "thor_read_verdict non e definita: il test starebbe provando una copia"
grep -q "NON RINVIARE" "$LIB" \
  && ok "il prompt di @thor gli vieta di rinviare il verdetto" \
  || err "il prompt non contiene il divieto di rinviare"

printf '\n=== tollerante sulla FORMA: le versioni che @thor scrive davvero ===\n'
r="$(leggi 'VERDICT: PASS — tutto verificato')"
[ "$(esito "$r")" = PASS ] && ok "forma pulita del contratto" || err "forma pulita: '$r'"

r="$(leggi '**VERDICT: PASS** — wc -l = 212, mutazione 4 su 4 rossa')"
[ "$(esito "$r")" = PASS ] && ok "grassetto — IL CASO VERO che ha rifiutato un PASS il 2 ago" \
                           || err "grassetto ancora non letto: '$r'"
[ "$(prova "$r")" = "wc -l = 212, mutazione 4 su 4 rossa" ] \
  && ok "e l'evidenza esce pulita, senza il separatore" || err "evidenza estratta male: '$(prova "$r")'"

r="$(leggi 'VERDICT: FAIL - manca il test')"
[ "$(esito "$r")" = FAIL ] && ok "trattino semplice invece dell'em dash" || err "trattino semplice: '$r'"

r="$(leggi 'VERDICT: PASS')"
[ "$(esito "$r")" = PASS ] && ok "nessun separatore, solo la parola" || err "senza separatore: '$r'"

r="$(leggi 'Conclusione finale: **VERDICT: FAIL** — il gate non e wired')"
[ "$(esito "$r")" = FAIL ] && ok "verdetto con testo prima, sulla stessa riga" || err "testo prima: '$r'"

printf '\n=== INFLESSIBILE sul contenuto: nessun verdetto inventato ===\n'
for testo in \
  "aspetto l'esito del test completo prima di scrivere il verdetto finale" \
  "il VERDICT lo scrivo dopo che la CI ha finito" \
  "Non blocco su questo, arrivera una notifica" \
  "ho controllato tutto e sembra a posto"; do
  r="$(leggi "$testo")"
  [ -z "$r" ] && ok "nessun verdetto in: \"${testo:0:44}...\"" \
              || err "ha INVENTATO un verdetto ($(esito "$r")) da: \"$testo\""
done

printf '\n=== l ULTIMO verdetto vince: @thor puo discuterne senza cambiare il proprio ===\n'
r="$(leggi 'Un VERDICT: FAIL sarebbe stato giusto ieri.
Oggi no.
VERDICT: PASS — il gate ora fallisce sulla mutazione')"
[ "$(esito "$r")" = PASS ] && ok "cita un FAIL nel ragionamento, conclude PASS -> vince l ultimo" \
                           || err "ha preso il verdetto sbagliato: '$r'"

printf '\n=== i due fallimenti si dicono DIVERSI (era lo stesso messaggio per tutti e due) ===\n'
grep -q "SENZA scrivere un verdetto" "$LIB" \
  && ok "turno finito senza verdetto: messaggio suo" \
  || err "manca il messaggio per il turno finito senza verdetto"
grep -q "non e arrivato in fondo" "$LIB" \
  && ok "processo morto o in timeout: messaggio suo" \
  || err "manca il messaggio per il processo non arrivato in fondo"
grep -q "unparseable thor-verify output" "$LIB" \
  && err "il messaggio unico di prima e' ancora li': i due casi restano confusi" \
  || ok "il messaggio unico che confondeva i due casi non c'e' piu'"

[ "$FAIL" -eq 0 ] && { echo "test-thor-verdict: PASS"; exit 0; }
echo "test-thor-verdict: FAIL"; exit 1
