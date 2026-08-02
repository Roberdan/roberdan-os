#!/usr/bin/env bash
# test-kb-autothor-board.sh — @thor deve cercare la card sul board dove la card VIVE.
#
# PERCHE' ESISTE, e perche' non bastava test-kb-autothor.sh. Quella suite prova il cablaggio del
# cancello sostituendo kanban/thor-verify.sh con uno stub che stampa il verdetto voluto: e'
# giusto (non si spende un `claude` per una card finta) ma ha un buco preciso — lo script
# sostituito e' proprio quello che contiene il difetto, quindi cosa faccia thor-verify.sh con il
# board resta non provato. Il difetto e' vissuto li' dentro dal 2026-07-31: kb.sh chiamava
# thor-verify.sh SENZA RDA_KANBAN, thor-verify.sh calcolava il proprio KB da dove sta lo script
# (sempre roberdan-os/kanban), e per ogni card di un repo federato verify_card rispondeva "card
# not found" -> SKIP -> REFUSED. Il cancello non rifiutava per merito: rifiutava per indirizzo.
# Nessuna delle 33 card chiuse in VirtualBPMFy27 porta l'evidenza "| @thor:" che il ramo PASS
# appende, che e' il modo in cui si vede DAI DATI che non e' mai scattato.
#
# QUI RDA_KANBAN NON VIENE ESPORTATA, ed e' la cosa piu' importante del file. La prima stesura
# di questa suite la esportava per comodita': thor-verify.sh se la ereditava dall'ambiente, il
# board giusto arrivava comunque, e la prova per mutazione restava VERDE con il difetto rimesso.
# Provava il proprio setup, non il codice. Dal vivo nessuno esporta RDA_KANBAN: si sta dentro un
# repo registrato e kb risolve il board dal registro. E' quella la situazione da riprodurre.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

# Il board NON si passa per ambiente: si lascia che kb lo risolva come fa dal vivo.
unset RDA_KANBAN

# Un repo federato vero: una directory git, registrata, con il proprio kanban/.
FED="$TMP/fedrepo"; mkdir -p "$FED"/kanban/{todo,doing,done}
git -C "$FED" init -q 2>/dev/null || { echo "  SKIP — git non disponibile"; exit 0; }
export RDA_KANBAN_REGISTRY="$TMP/reg"; printf '%s\n' "$FED" > "$RDA_KANBAN_REGISTRY"
BOARD="$FED/kanban"

# La copia del repo che fornisce gli script: kb.sh, thor-verify.sh e factory/lib.sh VERI.
REPO="$TMP/repo"; mkdir -p "$REPO/kanban" "$REPO/factory"
cp "$ROOT/kanban/"*.sh "$REPO/kanban/"
cp "$ROOT/factory/lib.sh" "$REPO/factory/"

# L'unico pezzo finto: un `claude` che scrive un verdetto leggibile e non costa niente. Cio' che
# si prova e' l'INDIRIZZO su cui la card viene cercata, non il giudizio di merito.
FAKE="$TMP/fake-claude"
printf '#!/usr/bin/env bash\nprintf "VERDICT: PASS — evidenza finta di prova\\n"\n' > "$FAKE"
chmod +x "$FAKE"
export CLAUDE="$FAKE"

EV="test/test-kb-autothor-board.sh: cablaggio del board, exit 0"
# Senza `worktree:`: il cancello del worktree pulito e' un'altra cosa e qui non c'entra.
card() {
  printf 'id: %s\nstatus: doing\ntitle: "fixture board federato"\nrepo: fedrepo\ndod: "che la card venga trovata"\nacceptance: "che la card venga trovata"\n' \
    "$1" > "$BOARD/doing/$1.md"
}
# kb va lanciato DA DENTRO il repo federato: e' cosi' che il board viene risolto dal vivo.
run_kb() { ( cd "$FED" && bash "$1/kanban/kb.sh" finish "$2" --thor "$EV" 2>&1 ); }

# --- 1. LA PROVA: una card che vive su un board federato viene TROVATA ----------------------
card FED1
out="$(run_kb "$REPO" FED1 || true)"
case "$out" in
  *"not found in kanban/"*)
    err "la card di un repo federato non viene trovata: @thor cerca ancora sul board sbagliato" ;;
  *)
    ok "una card che vive su un board federato viene trovata da @thor" ;;
esac
if [ -e "$BOARD/done/FED1.md" ]; then
  ok "e il cancello la chiude sul verdetto che @thor ha davvero espresso"
else
  err "la card non si e' chiusa nonostante il verdetto PASS — $out"
fi
# L'evidenza appesa e' cio' che sulle card vere mancava: e' la firma che la verifica e' avvenuta.
if grep -q '@thor: evidenza finta di prova' "$BOARD/done/FED1.md" 2>/dev/null; then
  ok "e l'evidenza di @thor finisce sulla card (la firma che sulle 33 card chiuse non c'era)"
else
  err "l'evidenza di @thor non e' stata appesa alla card"
fi

# --- 2. PROVA PER MUTAZIONE, dentro la suite -------------------------------------------------
# Un test che dimostra solo il caso buono non dice se sarebbe capace di accorgersi del male.
# Qui si rimette il difetto — la chiamata senza RDA_KANBAN — su una seconda copia degli script,
# e si pretende che il cancello TORNI a non trovare la card. Se questo blocco resta verde, il
# blocco 1 non stava provando niente: e' esattamente com'e' andata alla prima stesura.
MUT="$TMP/mutato"; mkdir -p "$MUT/kanban" "$MUT/factory"
cp "$REPO/kanban/"*.sh "$MUT/kanban/"; cp "$REPO/factory/lib.sh" "$MUT/factory/"
_mutate() { sed -e 's|tv="\$(RDA_KANBAN="\$KB" bash |tv="$(bash |' "$1" > "$1.new" && mv "$1.new" "$1"; }
_mutate "$MUT/kanban/kb.sh"
if grep -q 'RDA_KANBAN="\$KB" bash "\$ROOT/kanban/thor-verify.sh"' "$MUT/kanban/kb.sh"; then
  err "la mutazione non ha morso il file: il blocco 2 non sta provando niente"
else
  card FED2
  mout="$(run_kb "$MUT" FED2 || true)"
  case "$mout" in
    *"not found in kanban/"*) ok "rimesso il difetto, la card torna introvabile: il blocco 1 morde davvero" ;;
    *) err "con il difetto rimesso il cancello si comporta ancora bene: il test non sa accorgersene — $mout" ;;
  esac
  if [ -e "$BOARD/doing/FED2.md" ]; then
    ok "e la card mutata resta in doing, come deve fare un cancello che non ha potuto verificare"
  else
    err "la card mutata si e' chiusa lo stesso"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "test-kb-autothor-board: PASS"; exit 0; fi
echo "test-kb-autothor-board: FAIL ($fails)"; exit 1
