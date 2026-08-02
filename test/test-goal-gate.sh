#!/usr/bin/env bash
# test-goal-gate.sh — l'unico hook di questo repo che BLOCCA, e i suoi freni.
#
# Due difetti opposti, e questo file deve prenderli tutti e due:
#   (a) NON blocca quando c'e' ancora lavoro autorizzato -> la sessione muore alle 20:57 e
#       riparte alle 11:33 del giorno dopo perche' Roberto scrive "vai" (misurato su
#       VirtualBPM, 14h 36m di silenzio dopo "Non aspetto niente da te").
#   (b) blocca e non smette mai -> peggio di (a): una sessione che non si puo' chiudere.
#
# Meta' delle asserzioni qui sotto verificano che il cancello LASCI PASSARE. Un cancello che
# blocca sempre passerebbe un test scritto solo sul caso (a), ed e' il difetto piu' pericoloso
# dei due — quindi ogni freno ha la sua asserzione, nei due sensi.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/goal-gate.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; KB="$REPO/kanban"
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
git -C "$TMP" init -q repo 2>/dev/null
cp "$ROOT/kanban/kb.sh" "$KB/kb.sh"; chmod +x "$KB/kb.sh"
for aux in precheck.sh thor-verify.sh lib.sh; do
  [ -f "$ROOT/kanban/$aux" ] && cp "$ROOT/kanban/$aux" "$KB/$aux"
done
export RDA_HOME="$TMP/home"; mkdir -p "$RDA_HOME"
# Stato dei contatori isolato nel temp: senza questo la suite eredita i contatori della
# esecuzione precedente e fallisce al secondo giro sulla stessa macchina.
export RDA_GOAL_GATE_STATE="$TMP/gate-state"

_card() { cat > "$KB/todo/$1.md" <<CARD
---
title: card $1
repo: repo
dod: "una dod"
acceptance: "il comando stampa il risultato"
status: todo
created: 2026-08-02
---
CARD
}
_coda() { { echo "# CODA"; echo "# scattata"; for i in "$@"; do echo "$i"; done; } > "$KB/.coda-repo.md"; }

# Lancia l'hook come lo lancerebbe Claude Code: JSON su stdin, dentro il repo.
run() { (cd "$REPO" && printf '{"session_id":"%s","hook_event_name":"Stop"}' "${SID:-s1}" \
         | bash "$HOOK" 2>"$TMP/err"); }

printf '\n=== (a) blocca quando resta lavoro autorizzato ===\n'
_card C1; _card C2; _coda C1 C2
SID=sA; run; rc=$?
[ "$rc" -eq 2 ] && ok "2 card aperte nella coda -> exit 2 (il turno non si chiude)" \
                || err "2 card aperte nella coda -> atteso exit 2, ottenuto $rc"
grep -q "kb next" "$TMP/err" && ok "dice all'agente COME continuare, non solo che deve" \
                             || err "il motivo non nomina \`kb next\`"
grep -q "kb queue --aggiunte" "$TMP/err" && ok "ricorda che cio' che e' nato dopo resta a Roberto" \
                                         || err "non protegge la proprieta' della coda"

printf '\n=== (b) LASCIA PASSARE: i casi terminali ===\n'
mv "$KB/todo/C1.md" "$KB/done/"; mv "$KB/todo/C2.md" "$KB/done/"
SID=sB; run; rc=$?
[ "$rc" -eq 0 ] && ok "coda finita -> exit 0 (condizione terminale)" \
                || err "coda finita -> atteso exit 0, ottenuto $rc"

rm -f "$KB/.coda-repo.md"; _card C3
SID=sC; run; rc=$?
[ "$rc" -eq 0 ] && ok "card aperte ma NESSUNA coda autorizzata -> exit 0 (il gate di Roberto regge)" \
                || err "senza coda autorizzata il cancello ha bloccato lo stesso (exit $rc)"

_coda C3
SID=sD RDA_NO_GOAL_GATE=1 run; rc=$?
[ "$rc" -eq 0 ] && ok "interruttore RDA_NO_GOAL_GATE=1 -> exit 0" \
                || err "l'interruttore non spegne il cancello (exit $rc)"

touch "$RDA_HOME/goal-gate.off"
SID=sE; run; rc=$?
[ "$rc" -eq 0 ] && ok "interruttore su file goal-gate.off -> exit 0" \
                || err "il file interruttore non spegne il cancello (exit $rc)"
rm -f "$RDA_HOME/goal-gate.off"

printf '\n=== (b) LASCIA PASSARE: i freni contro il loop infinito ===\n'
# FRENO nessun-progresso: la coda non si accorcia -> al secondo giro deve mollare.
SID=sF; run; rc1=$?
SID=sF; run; rc2=$?
SID=sF; run; rc3=$?
[ "$rc1" -eq 2 ] && ok "primo giro con una card aperta -> blocca" || err "primo giro: atteso 2, ottenuto $rc1"
[ "$rc3" -eq 0 ] && ok "coda ferma per due giri -> exit 0, e dice cosa e' incastrato" \
                 || err "coda ferma: il cancello non molla (giro2=$rc2 giro3=$rc3)"
grep -q "non si accorcia" "$TMP/err" && ok "il motivo dell'uscita nomina la mancanza di progresso" \
                                     || err "esce senza dire perche'"

# FRENO tetto: con progresso a ogni giro il freno stallo non scatta, quindi deve fermarlo il tetto.
SID=sG
for i in 1 2 3 4; do _card "P$i"; done
_coda P1 P2 P3 P4
RDA_GOAL_GATE_MAX=2 run >/dev/null; r1=$?
mv "$KB/todo/P1.md" "$KB/done/"          # progresso vero: la coda si accorcia
RDA_GOAL_GATE_MAX=2 run >/dev/null; r2=$?
mv "$KB/todo/P2.md" "$KB/done/"
RDA_GOAL_GATE_MAX=2 run; r3=$?
[ "$r1" -eq 2 ] && [ "$r2" -eq 2 ] && ok "finche' la coda si accorcia, continua a bloccare" \
                                   || err "con progresso reale doveva bloccare (r1=$r1 r2=$r2)"
[ "$r3" -eq 0 ] && ok "tetto di ripartenze raggiunto -> exit 0 anche con card aperte" \
               || err "il tetto non ferma il cancello (r3=$r3)"
grep -q "tetto" "$TMP/err" && ok "il motivo dell'uscita nomina il tetto" || err "tetto: esce muto"

printf '\n=== fuori da un repo git non dice niente ===\n'
out="$(cd "$TMP" && printf '{"session_id":"sH"}' | bash "$HOOK" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "fuori da un repo -> exit 0 e silenzio" \
                                 || err "fuori da un repo: exit $rc, output '$out'"

[ "$FAIL" -eq 0 ] && { echo "test-goal-gate: PASS"; exit 0; }
echo "test-goal-gate: FAIL"; exit 1
