#!/usr/bin/env bash
# test-twin-shadow.sh — the twin's decision ledger (docs/adr/0005-twin-decision-ledger.md).
# Fixture board + fixture ledger in mktemp; never the real ~ nor the real board. Proves: hidden
# prediction recorded, kb start records the outcome through the real hook, kb survives a broken
# helper, reconcile, agreement math, "dati insufficienti", batch approves nothing, and no ledger
# text can land in the repo.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KBSH="$ROOT/kanban/kb.sh"; TS="$ROOT/bin/twin-shadow.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
CANARY="canarino-twin-7f3a"

export RDA_HOME="$TMP/home" RDA_KANBAN="$TMP/board" RDA_KANBAN_REGISTRY="$TMP/registry"
export RDA_TWIN_BOARDS="$TMP/board" RDA_NO_PRECHECK=1 RDA_KB_ALLOW_PARALLEL=1 PYTHONDONTWRITEBYTECODE=1
unset RDA_TWIN_LEDGER_DIR RDA_TWIN_SHADOW RDA_TWIN_NOW
mkdir -p "$RDA_KANBAN"/{todo,doing,done} "$RDA_HOME"; : > "$RDA_KANBAN_REGISTRY"
LEDGER="$RDA_HOME/private/decisions/ledger.jsonl"
card() { printf -- '---\ntitle: %s %s\nrepo: personal\nstatus: todo\ndod: fatto\nacceptance: visto\n---\n' "$2" "$CANARY" > "$RDA_KANBAN/todo/$1.md"; }
jq_py() { python3 -c "import json,sys; recs=[json.loads(l) for l in open('$LEDGER')]; $1"; }
STUB="$TMP/stub-host"; printf '#!/bin/sh\ncat >/dev/null\necho '"'"'{"choice":"approve","confidence":0.9,"category":"tecnico","why":"x"}'"'"'\n' > "$STUB"; chmod +x "$STUB"

# 1) predict records a hidden prediction, and prints only counts (shadow: Roberto doesn't see it)
card C1 "primo"; card C2 "secondo"
out="$(RDA_TWIN_HOST_CMD="$STUB" bash "$TS" predict)"
[ "$(jq_py 'print(sum(1 for r in recs if r["twin_prediction"]))')" = 2 ] && ok "predict: previsione registrata per ogni card in attesa" || err "predict non ha registrato 2 previsioni: $out"
case "$out" in *approve*|*tecnico*) err "predict mostra la previsione: $out" ;; *) ok "predict stampa solo i conteggi, non la previsione" ;; esac
[ "$(stat -f %Lp "$LEDGER" 2>/dev/null || stat -c %a "$LEDGER")" = 600 ] && ok "registro leggibile solo dal proprietario (600)" || err "permessi del registro non 600"

# 2) no host / broken host -> "no prediction", rc 0, never an invented one
card C3 "terzo"
RDA_TWIN_HOST_CMD="false" bash "$TS" predict >/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$(jq_py 'print([r for r in recs if r["card"]=="C3"][0]["twin_prediction"])')" = None ] \
  && ok "host rotto: nessuna previsione inventata, rc 0" || err "host rotto: rc=$rc o previsione inventata"
unset RDA_TWIN_HOST_CMD
RDA_TWIN_HOST=none PATH="/usr/bin:/bin" bash "$TS" predict >/dev/null \
  && [ "$(jq_py 'print([r for r in recs if r["card"]=="C3"][0].get("prediction_note",""))')" = "nessun host disponibile" ] \
  && ok "nessun host: registrata come 'nessun host disponibile'" || err "nessun host: nota mancante"

# 3) the REAL entry point: kb start --by roberto records the outcome against the prediction
bash "$KBSH" start C1 --by roberto --no-worktree "test" >/dev/null 2>&1 < /dev/null
got="$(jq_py 'r=[r for r in recs if r["card"]=="C1"][0]; print(r["roberto_choice"], r["decided_by"], r["interactive"], r["attributed"])')"
[ "$got" = "approve roberto no False" ] && ok "kb start registra l'esito (non interattivo = non attribuito a Roberto)" || err "kb start: esito sbagliato: $got"
python3 -c "import sys; sys.path.insert(0,'$ROOT/bin'); from twinlib.ledger import is_roberto as f; assert f('roberto','yes') and not f('roberto (coda autorizzata)','yes') and not f('roberto','no') and not f('claude','yes')" \
  && ok "attribuzione: conta solo '--by roberto' da terminale (coda, agente, non interattivo esclusi)" || err "regola di attribuzione sbagliata"

# 4) kb is unaffected when the helper fails, is missing, or the ledger is refused
card K1 "k1"; card K2 "k2"; card K3 "k3"
printf '#!/bin/sh\necho SPAZZATURA; echo SPAZZATURA >&2; exit 7\n' > "$TMP/bad"; chmod +x "$TMP/bad"
o1="$(RDA_TWIN_SHADOW="$TMP/bad" bash "$KBSH" start K1 --by roberto --no-worktree t 2>&1 </dev/null)"; r1=$?
o2="$(RDA_TWIN_SHADOW="$TMP/assente.sh" bash "$KBSH" start K2 --by roberto --no-worktree t 2>&1 </dev/null)"; r2=$?
o3="$(RDA_TWIN_LEDGER_DIR="$ROOT/.twin-ledger-probe" bash "$KBSH" start K3 --by roberto --no-worktree t 2>&1 </dev/null)"; r3=$?
if [ "$r1$r2$r3" = 000 ] && [ -e "$RDA_KANBAN/doing/K1.md" ] && [ -e "$RDA_KANBAN/doing/K2.md" ] && [ -e "$RDA_KANBAN/doing/K3.md" ] \
   && ! grep -q SPAZZATURA <<<"$o1$o2$o3"; then ok "kb start funziona con helper rotto, assente o registro rifiutato"; else err "kb disturbato dall'helper: rc=$r1$r2$r3 $o1 $o2 $o3"; fi
[ ! -e "$ROOT/.twin-ledger-probe" ] && ok "registro dentro il repo rifiutato anche dal hook di kb" || err "creato un registro dentro il repo"

# 5) outcome is update-only: a card nobody shadowed writes nothing, not even the directory
RDA_HOME="$TMP/vuota" bash "$TS" outcome --board "$RDA_KANBAN" --card ZZ --choice approve --by roberto --interactive yes
[ ! -e "$TMP/vuota" ] && ok "outcome senza previsione aperta non crea nulla" || err "outcome ha creato un registro"

# 6) reconcile: approval the hook missed (audit says interactive=yes) and a vanished card
mv "$RDA_KANBAN/todo/C2.md" "$RDA_KANBAN/doing/C2.md"
printf 'kb_start_audit: "at=2026-09-24T10:00:00Z by=roberto interactive=yes"\napproved_by: roberto\n' >> "$RDA_KANBAN/doing/C2.md"
rm "$RDA_KANBAN/todo/C3.md"
bash "$TS" reconcile >/dev/null
got="$(jq_py 'd={r["card"]:(r["roberto_choice"],r["attributed"]) for r in recs}; print(d["C2"], d["C3"])')"
[ "$got" = "('approve', True) ('reject', False)" ] && ok "reconcile: approvazione mancata registrata, card sparita = rifiuto non attribuito" || err "reconcile: $got"

# 7) batch sorts by the twin's advice, stamps shown_at, and approves NOTHING
card B1 "b1"; card B2 "b2"
printf '#!/bin/sh\ncat >/dev/null\necho '"'"'{"choice":"reject","confidence":0.7,"category":"persone"}'"'"'\n' > "$TMP/rej"; chmod +x "$TMP/rej"
RDA_TWIN_HOST_CMD="$TMP/rej" bash "$TS" predict --max 1 >/dev/null   # B1 -> reject
RDA_TWIN_HOST_CMD="$STUB" bash "$TS" predict >/dev/null              # B2 -> approve
before="$(ls "$RDA_KANBAN"/*/ | shasum)"
out="$(bash "$TS" batch)"
after="$(ls "$RDA_KANBAN"/*/ | shasum)"
[ "$before" = "$after" ] && ok "batch non sposta nessuna card" || err "batch ha cambiato il board"
b2="$(grep -n '• B2' <<<"$out" | cut -d: -f1)"; b1="$(grep -n '• B1' <<<"$out" | cut -d: -f1)"
[ -n "$b2" ] && [ -n "$b1" ] && [ "$b2" -lt "$b1" ] && grep -q "NON approva" <<<"$out" && ok "batch: prima gli 'approve', poi i 'reject'" || err "batch: ordine sbagliato: $out"
[ "$(jq_py 'print(all(r["shown_at"] for r in recs if r["card"] in ("B1","B2")))')" = True ] && ok "batch marca le voci mostrate (non conteranno nell'accordo)" || err "shown_at non marcato"

# 8) agreement math on a fixture ledger, with a pinned clock
FIX="$TMP/fix"; mkdir -p "$FIX"
python3 - "$FIX/ledger.jsonl" <<'EOF'
import json, sys
def r(i, cat, pred, choice, att=True, dec="2026-09-20T10:00:00Z", shown=None, jev=None):
    return {"id": f"F{i}", "category": cat, "twin_prediction": {"choice": pred, "confidence": .8} if pred else None,
            "roberto_choice": choice, "attributed": att, "decided_at": dec, "shown_at": shown,
            "jev_prediction": {"choice": jev} if jev else None}
rows = [r(i, "tecnico", "approve", "approve") for i in range(5)] + [r(5, "tecnico", "approve", "reject", jev="reject")]
rows += [r(6, "persone", "defer", "defer"), r(7, "persone", "approve", "reject")]
rows += [r(8, "tecnico", "approve", "approve", att=False), r(9, "tecnico", None, "approve"),
         r(10, "tecnico", "approve", "reject", shown="2026-09-19T00:00:00Z"),
         r(11, "tecnico", "approve", "approve", dec="2026-08-01T00:00:00Z")]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
EOF
week="$(RDA_TWIN_LEDGER_DIR="$FIX" RDA_TWIN_NOW=2026-09-24T12:00:00Z bash "$ROOT/bin/twin-agreement.sh")"
grep -q "tecnico        N=6   accordo 83% (5 su 6)" <<<"$week" && ok "accordo per categoria: 5 su 6 = 83%" || err "tecnico sbagliato: $week"
grep -q "persone        N=2   dati insufficienti" <<<"$week" && ok "N<5 -> dati insufficienti" || err "persone: $week"
grep -q "totale         N=8   accordo 75% (6 su 8)" <<<"$week" && ok "totale 6 su 8 = 75%, escluse le 4 da non contare" || err "totale: $week"
grep -q "1 senza previsione del twin, 1 non attribuibili a Roberto (coda, agente, o card sparita), 1 decise dopo" <<<"$week" && ok "le escluse sono dichiarate, non nascoste" || err "escluse: $week"
grep -A1 "^Jev" <<<"$week" | grep -q "N=1   dati insufficienti" && ok "Jev misurato a parte" || err "Jev: $week"
all="$(RDA_TWIN_LEDGER_DIR="$FIX" RDA_TWIN_NOW=2026-09-24T12:00:00Z bash "$ROOT/bin/twin-agreement.sh" --all)"
grep -q "totale         N=9   accordo 78% (7 su 9)" <<<"$all" && ok "--all include la decisione fuori settimana" || err "--all: $all"
empty="$(RDA_TWIN_LEDGER_DIR="$TMP/nessuno" bash "$ROOT/bin/twin-agreement.sh")"
grep -q "dati insufficienti" <<<"$empty" && ok "registro vuoto: dati insufficienti" || err "vuoto: $empty"

# 9) the weekly summary (pending digest) shows the agreement — aggregates only, no card text
RDA_TWIN_LEDGER_DIR="$FIX" RDA_TWIN_NOW=2026-09-24T12:00:00Z bash "$ROOT/bin/pending-digest.sh" --always >/dev/null 2>&1
d="$RDA_HOME/pending-digest.txt"
grep -q "Twin — accordo con Roberto (ultimi 7 giorni)" "$d" && grep -q "accordo 75%" "$d" && ok "il riepilogo mostra la percentuale di accordo twin/Roberto" || err "digest senza accordo: $(tail -8 "$d")"

# 10) privacy: ledger refused inside a git tree; no canary anywhere in the repo
RDA_TWIN_LEDGER_DIR="$ROOT/.twin-ledger-probe" bash "$TS" agreement >/dev/null 2>&1; rc=$?
RDA_TWIN_LEDGER_DIR="$ROOT/.twin-ledger-probe" RDA_TWIN_HOST_CMD="$STUB" bash "$TS" predict >/dev/null 2>&1; rc2=$?
[ "$rc$rc2" = 33 ] && [ ! -e "$ROOT/.twin-ledger-probe" ] && ok "registro dentro un repo git: rifiutato (rc 3), nulla creato" || err "privacy: rc=$rc$rc2"
grep -q "$CANARY" "$LEDGER" && ok "il canarino sta nel registro locale (il test prova qualcosa)" || err "canarino assente dal registro"
if git -C "$ROOT" grep -q "$CANARY" -- ':!test/test-twin-shadow.sh' 2>/dev/null; then err "testo del registro trovato nel repo"; else ok "nessun testo del registro nel repo"; fi
# Ignored files too (git grep sees only tracked ones): a .gitignore is not a privacy boundary.
if grep -rIl --exclude-dir=.git --exclude-dir=node_modules --exclude=test-twin-shadow.sh "$CANARY" "$ROOT" >/dev/null 2>&1; then
  err "testo del registro in un file del repo (anche ignorato)"; else ok "nessun file del repo, nemmeno ignorato, contiene testo del registro"; fi

[ "$FAIL" -eq 0 ] && echo "test-twin-shadow: PASS" || { echo "test-twin-shadow: FAIL"; exit 1; }
