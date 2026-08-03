#!/usr/bin/env bash
# test-kb-autothor-dir.sh — @thor deve guardare il checkout del repo che la card NOMINA.
#
# PERCHE' ESISTE. test-kb-autothor-board.sh prova su quale BOARD la card viene cercata. Questo
# prova una cosa diversa e piu' pericolosa: in quale CARTELLA @thor va a guardare. Il difetto
# (260802-212646) era una riga sola in thor-verify.sh — `dir="${2:-$ROOT}"` — e $2 e' quello che
# kb finish passa, cioe' `_field <card> worktree`: VUOTO per una card senza worktree, o con il
# worktree gia' rimosso. Il fallback mandava @thor dentro roberdan-os.
#
# E' il gemello CATTIVO del difetto sul board. Quello rifiutava per indirizzo: fastidioso, ma
# rumoroso e innocuo. Questo APPROVA per indirizzo — @thor guarda codice che non c'entra niente
# con la card, non trova nulla che contraddica i criteri, e firma un PASS sincero e sbagliato.
# Un cancello che sbaglia in senso permissivo non si vede da fuori: si vede solo quando qualcosa
# passa che non doveva.
#
# Cosa si finge e cosa no: si finge SOLO `claude`, e lo si finge in modo che dica DOVE si trova
# (`cwd=$PWD`). Il giudizio di merito qui non interessa; interessa l'indirizzo. Tutto il resto —
# kb.sh, thor-verify.sh, factory/lib.sh, il registro — e' quello vero.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

# Come dal vivo: il board non si passa per ambiente, lo risolve kb dal registro.
unset RDA_KANBAN

FED="$TMP/fedrepo"; mkdir -p "$FED"/kanban/{todo,doing,done}
git -C "$FED" init -q 2>/dev/null || { echo "  SKIP — git non disponibile"; exit 0; }
export RDA_KANBAN_REGISTRY="$TMP/reg"; printf '%s\n' "$FED" > "$RDA_KANBAN_REGISTRY"
BOARD="$FED/kanban"

REPO="$TMP/repo"; mkdir -p "$REPO/kanban" "$REPO/factory"
cp "$ROOT/kanban/"*.sh "$REPO/kanban/"
cp "$ROOT/factory/lib.sh" "$REPO/factory/"

# L'unico pezzo finto: un `claude` che dichiara la propria cwd dentro il verdetto.
FAKE="$TMP/fake-claude"
printf '#!/usr/bin/env bash\nprintf "VERDICT: PASS — cwd=%%s\\n" "$PWD"\n' > "$FAKE"
chmod +x "$FAKE"
export CLAUDE="$FAKE"

EV="test/test-kb-autothor-dir.sh: indirizzo della cartella, exit 0"
# SENZA `worktree:` — e' il caso che il difetto colpiva.
card() {
  printf 'id: %s\nstatus: doing\ntitle: "fixture cartella"\nrepo: %s\ndod: "che @thor guardi il repo giusto"\nacceptance: "che @thor guardi il repo giusto"\n' \
    "$1" "${2:-fedrepo}" > "$BOARD/doing/$1.md"
}
run_kb() { ( cd "$FED" && bash "$1/kanban/kb.sh" finish "$2" --thor "$EV" 2>&1 ); }

# --- 1. LA PROVA: @thor guarda il checkout del repo che la card nomina -----------------------
card DIR1
out="$(run_kb "$REPO" DIR1 || true)"
ev="$(grep -m1 'cwd=' "$BOARD/done/DIR1.md" 2>/dev/null || true)"
case "$ev" in
  *"cwd=$FED"*) ok "senza worktree, @thor guarda il checkout del repo NOMINATO dalla card" ;;
  *"cwd=$REPO"*) err "@thor ha guardato il checkout degli script invece del repo della card: il difetto e' vivo" ;;
  "") err "nessuna evidenza con la cwd sulla card: la verifica non e' arrivata in fondo — $out" ;;
  *) err "@thor ha guardato una cartella inattesa: $ev" ;;
esac

# --- 2. un worktree DICHIARATO ma gia' rimosso vale come non dichiarato ----------------------
# E' il caso vero: `kb finish` rimuove il worktree, e la card puo' portarne il percorso morto.
card DIR2
printf 'worktree: %s\n' "$TMP/worktree-che-non-esiste" >> "$BOARD/doing/DIR2.md"
out2="$(run_kb "$REPO" DIR2 || true)"
ev2="$(grep -m1 'cwd=' "$BOARD/done/DIR2.md" 2>/dev/null || true)"
case "$ev2" in
  *"cwd=$FED"*) ok "un worktree gia' rimosso non manda @thor a caso: si ricade sul repo della card" ;;
  "") err "con un worktree morto la verifica non e' arrivata in fondo — $out2" ;;
  *) err "con un worktree morto @thor ha guardato: $ev2" ;;
esac

# --- 3. repo non risolvibile: il cancello RIFIUTA, non deduce --------------------------------
card DIR3 repo-che-non-esiste-da-nessuna-parte
out3="$(run_kb "$REPO" DIR3 || true)"
if [ -e "$BOARD/doing/DIR3.md" ]; then
  ok "repo non risolvibile: la card resta in doing"
else
  err "repo non risolvibile e la card si e' chiusa lo stesso — $out3"
fi
case "$out3" in
  *"non risolvibile"*) ok "e il motivo dice che non si e' potuto risolvere il repo, non un giudizio di merito" ;;
  *) err "il rifiuto non spiega che il repo non e' risolvibile — $out3" ;;
esac
if grep -q 'cwd=' "$BOARD/doing/DIR3.md" 2>/dev/null; then
  err "@thor e' stato eseguito comunque su una cartella dedotta"
else
  ok "e @thor non e' stato eseguito affatto: meglio nessun verdetto che uno su codice a caso"
fi

# --- 4. PROVA PER MUTAZIONE ------------------------------------------------------------------
# Si rimette la riga esatta del difetto e si pretende che il blocco 1 TORNI rosso. Se questo
# resta verde, il blocco 1 non stava provando niente.
MUT="$TMP/mutato"; mkdir -p "$MUT/kanban" "$MUT/factory"
cp "$REPO/kanban/"*.sh "$MUT/kanban/"; cp "$REPO/factory/lib.sh" "$MUT/factory/"
_mutate() { sed -e 's|^dir="\${2:-}"|dir="${2:-$ROOT}"|' "$1" > "$1.new" && mv "$1.new" "$1"; }
_mutate "$MUT/kanban/thor-verify.sh"
if ! grep -q 'dir="\${2:-\$ROOT}"' "$MUT/kanban/thor-verify.sh"; then
  err "la mutazione non ha morso il file: il blocco 4 non sta provando niente"
else
  card DIR4
  mout="$(run_kb "$MUT" DIR4 || true)"
  mev="$(grep -m1 'cwd=' "$BOARD/done/DIR4.md" 2>/dev/null || true)"
  case "$mev" in
    *"cwd=$MUT"*) ok "rimesso il difetto, @thor torna a guardare il checkout sbagliato: il blocco 1 morde davvero" ;;
    *"cwd=$FED"*) err "con il difetto rimesso @thor guarda ancora il repo giusto: il test non sa accorgersene" ;;
    *) err "mutazione: evidenza inattesa — $mev / $mout" ;;
  esac
fi

echo
if [ "$fails" -eq 0 ]; then echo "test-kb-autothor-dir: PASS"; exit 0; fi
echo "test-kb-autothor-dir: FAIL ($fails)"; exit 1
