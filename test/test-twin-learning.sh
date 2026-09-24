#!/usr/bin/env bash
# test-twin-learning.sh — the twin learns from the ledger without leaving the machine
# (docs/adr/0005-twin-decision-ledger.md, plan 2026-09-24 Fase 4 items 4.4 and 4.5, plus Jev).
# Fixture ledger + fixture board in mktemp. Proves: similar precedents reach the prediction
# prompt (and unrelated ones don't), `values` writes a PROPOSAL outside the repo and never
# touches identity/, "dati insufficienti" below the threshold with the next step, private cards
# never reach Jev, public ones get a dry-run only, and the twin code opens no network itself.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$ROOT/bin/twin-shadow.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
export RDA_HOME="$TMP/home" RDA_TWIN_BOARDS="$TMP/board" PYTHONDONTWRITEBYTECODE=1
unset RDA_TWIN_LEDGER_DIR RDA_TWIN_NOW RDA_TWIN_HOST_CMD RDA_KANBAN
mkdir -p "$TMP/board"/{todo,doing,done}
DIR="$RDA_HOME/private/decisions"; mkdir -p "$DIR"; chmod 700 "$DIR"
# The stub host records what it was sent: that file is the ONLY place card text may reach.
STUB="$TMP/host"; printf '#!/bin/sh\ncat > "%s/sent.txt"\necho '"'"'{"choice":"approve","confidence":0.6,"category":"tecnico"}'"'"'\n' "$TMP" > "$STUB"; chmod +x "$STUB"

python3 - "$DIR/ledger.jsonl" <<'EOF'
import json, sys
def r(i, cat, sit, choice, reason=None, att=True, pred="approve"):
    return {"id": f"P{i}", "card": f"P{i}", "board": "/nowhere", "category": cat, "situation": sit,
            "twin_prediction": {"choice": pred, "confidence": .7}, "roberto_choice": choice,
            "reason": reason, "attributed": att, "decided_at": "2026-09-10T10:00:00Z", "shown_at": None}
rows = [r(1, "tecnico", "aggiornare shellcheck nella pipeline CI", "approve", "sblocca la CI"),
        r(2, "tecnico", "migrare la pipeline CI a runner nuovi", "defer", "costa troppo adesso", pred="approve"),
        r(3, "soldi", "comprare licenza per il tool di design", "reject", "spesa non necessaria"),
        r(4, "persone", "cena di ringraziamento con il team partner", "approve", "relazione prima"),
        r(5, "comunicazione", "newsletter mensile ai sostenitori", "approve", "relazione prima"),
        r(6, "soldi", "abbonamento annuale al servizio di hosting", "defer", "spesa da rivedere", pred="approve"),
        r(7, "persone", "intro tra due founder", "approve", "relazione prima"),
        r(8, "tecnico", "refactor del modulo audit", "approve", None),
        r(9, "priorita", "aprire un secondo fronte sullo stesso progetto", "reject", "un progetto alla volta"),
        r(10, "tecnico", "aggiornare le dipendenze di test", "approve", "sblocca la CI"),
        r(11, "tecnico", "evento non attribuito: aggiornare actionlint nella pipeline CI", "approve", None, att=False)]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
EOF
chmod 600 "$DIR/ledger.jsonl"

echo "== 4.5 precedenti simili nel prompt della previsione =="
printf -- '---\ntitle: aggiornare actionlint nella pipeline CI\nrepo: roberdan-os\ncategory: tecnico\n---\n' > "$TMP/board/todo/N1.md"
RDA_TWIN_HOST_CMD="$STUB" bash "$TS" predict >/dev/null 2>&1
sent="$(cat "$TMP/sent.txt" 2>/dev/null)"
grep -q "aggiornare shellcheck nella pipeline CI" <<<"$sent" && ok "il precedente piu' simile entra nel prompt" || err "precedente simile assente dal prompt"
grep -q "scelta di Roberto: defer" <<<"$sent" && ok "il prompt porta la scelta vera e il motivo del precedente" || err "scelta del precedente assente"
grep -q "cena di ringraziamento" <<<"$sent" && err "un precedente estraneo e' entrato nel prompt" || ok "i precedenti estranei restano fuori"
grep -q "evento non attribuito" <<<"$sent" && err "un precedente non attribuito e' entrato nel prompt" || ok "solo decisioni attribuite a Roberto fanno da precedente"
sim="$(bash "$TS" similar --card N1)"
[ "$(head -1 <<<"$sim" | grep -c 'shellcheck')" = 1 ] && ok "'similar' mette per primo il caso piu' vicino" || err "similar: $sim"

echo "== nessun testo privato esce dalla macchina se non verso l'host locale =="
if grep -rEn '^\s*(import|from)\s+(urllib|http|socket|requests|ssl)' "$ROOT/bin/twin_shadow.py" "$ROOT/bin/twinlib" >/dev/null; then
  err "il codice del twin apre la rete da solo"; else ok "il codice del twin non importa moduli di rete"; fi
printf -- '---\ntitle: contratto riservato col cliente\nrepo: personal\n---\n' > "$TMP/board/todo/N2.md"
printf -- '---\ntitle: scegliere il colore del logo di un progetto demo\nrepo: roberdan-os\njev: synthetic\n---\n' > "$TMP/board/todo/N3.md"
RDA_TWIN_HOST_CMD="$STUB" bash "$TS" predict >/dev/null 2>&1
obs() { python3 -c "import json;print(next((json.loads(l).get('jev_observation') or {}).get('status','') for l in open('$DIR/ledger.jsonl') if json.loads(l)['card']=='$1'))"; }
[ "$(obs N2)" = "non inviato: privato" ] && ok "card privata: Jev non riceve nulla ('non inviato: privato')" || err "N2 jev: $(obs N2)"
[ "$(obs N3)" = "dry-run" ] && ok "card dichiarata synthetic: solo dry-run di Jev (nessuna rete, nessuna spesa)" || err "N3 jev: $(obs N3)"

echo "== 4.4 valori proposti, mai scritti in identity/ =="
before="$(cd "$ROOT" && find identity -type f -exec shasum {} + | sort | shasum)"
out="$(bash "$TS" values)"
after="$(cd "$ROOT" && find identity -type f -exec shasum {} + | sort | shasum)"
P="$DIR/values-proposal.md"
[ -f "$P" ] && ok "proposta scritta nel registro locale" || err "values-proposal.md mancante: $out"
[ "$before" = "$after" ] && ok "identity/ non e' stato toccato (gate #6)" || err "identity/ modificato"
grep -q "PROPOSTA" "$P" && grep -q "gate #6" "$P" && ok "il file dice che e' una proposta da approvare" || err "intestazione della proposta"
grep -q "relazione prima.*3 decisioni" "$P" && ok "ogni valore porta il numero di decisioni che lo sostengono" || err "conteggi mancanti: $(cat "$P")"
first="$(grep -m1 -E '^1\. ' "$P")"; grep -q "relazione prima" <<<"$first" && ok "ordinati per sostegno: 'relazione prima' (3 decisioni) viene prima" || err "ordine: $first"
grep -qi "soldi" "$P" && grep -q "Conflitti" "$P" && ok "regole di conflitto ricavate dai disaccordi (soldi)" || err "regole di conflitto mancanti"
grep -q "evento non attribuito" "$P" && err "decisioni non attribuite usate come valori" || ok "solo decisioni attribuite"
[ "$(python3 -c "import os,stat;print(oct(stat.S_IMODE(os.stat('$P').st_mode))[2:])")" = 600 ] && ok "proposta leggibile solo dal proprietario" || err "permessi proposta"
RDA_TWIN_LEDGER_DIR="$TMP/pochi" bash "$TS" values > "$TMP/few.txt" 2>&1
grep -q "dati insufficienti" "$TMP/few.txt" && [ ! -e "$TMP/pochi/values-proposal.md" ] && ok "sotto soglia: dati insufficienti, nessun file" || err "sotto soglia: $(cat "$TMP/few.txt")"
RDA_TWIN_LEDGER_DIR="$ROOT/.twin-values-probe" bash "$TS" values >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && [ ! -e "$ROOT/.twin-values-probe" ] && ok "proposta dentro un repo git: rifiutata" || err "values dentro il repo: rc=$rc"

echo "== 'dati insufficienti' dice il passo successivo =="
e="$(RDA_TWIN_LEDGER_DIR="$TMP/vuoto" bash "$ROOT/bin/twin-agreement.sh")"
grep -q "passo successivo: accendi.*auto-predict" <<<"$e" && ok "indica come accendere le previsioni automatiche" || err "manca il passo successivo: $e"

[ "$FAIL" -eq 0 ] && echo "test-twin-learning: PASS" || { echo "test-twin-learning: FAIL"; exit 1; }
