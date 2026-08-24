#!/usr/bin/env bash
# test/private-marker-check.sh — rifiuta un commit che porta un file il quale DICHIARA
# DA SOLO di essere privato.
#
# PERCHE' ESISTE, e perche' gli altri due controlli non potevano prenderlo.
#
# Il 2026-08-24 `git add -A` in questo repo — che e' PUBBLICO — ha messo in commit due file
# che nessuno aveva scritto a mano: `people/roberto.md` e `claude-code/hooks/bash-guard-sh.md`,
# generati da gbrain, ciascuno con una tabella di "fatti" marcati `visibility: private`.
# Un terzo, `projects/virtualbpmfy27.md`, aspettava non tracciato con dentro numeri di PR,
# percentuali di margine e il nome di un cliente. Nessuno ha deciso di pubblicare niente:
# un tool ha scritto nella working tree, e `-A` ha preso tutto quello che ha trovato.
# Non e' arrivato su GitHub solo perche' il push non era ancora stato dato.
#
# leak-check.sh non poteva vederlo: e' una DENYLIST, sa i termini che qualcuno ha pensato
# di scrivere. Il testo di un fatto generato domani non e' su nessuna lista.
# directory-dump-check.sh nemmeno: cerca la FORMA di un estratto di rubrica (indirizzi,
# ruoli), e qui non ci sono indirizzi.
#
# Questo controllo fa la terza domanda, l'unica che si puo' fare senza sapere in anticipo
# i contenuti: **il file dichiara di essere privato?** Sono i file stessi a dirlo, in
# chiaro, in una colonna che il generatore compila. Un gate che legge quella dichiarazione
# non ha bisogno di inseguire i nomi delle cartelle: gbrain domani puo' inventare
# `orgs/` o `meetings/` e viene fermato lo stesso. Elencare le cartelle nel .gitignore
# ferma le tre di oggi; leggere il marcatore ferma la CLASSE.
#
# Cosa NON fa, di proposito:
#   - non cancella e non modifica niente: dice quali file e cosa fare;
#   - non guarda il contenuto dei fatti e non lo stampa. Un guardiano che incolla il
#     segreto nel proprio messaggio d'errore ha spostato la fuga, non fermata;
#   - non blocca un file che dichiara `visibility: public` — la dichiarazione si rispetta
#     in tutte e due le direzioni, altrimenti diventa un divieto di usare la parola.
#
# Uso:
#   private-marker-check.sh --staged   # solo l'indice (hook pre-commit)
#   private-marker-check.sh            # tutto cio' che e' tracciato (validate.sh)
#
# Ogni grep gira sotto `|| true`: con `set -e` e `pipefail`, "grep non ha trovato niente"
# (uscita 1) diventerebbe un abort — un fallimento che si legge come verde perche' non e'
# mai partito.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

MODE="${1:-}"

# LE ESENZIONI, e perche' stanno in un file invece che in un `case` qui dentro.
#
# Questo gate ha bloccato il proprio test al primo commit: `test/test-private-marker.sh`
# costruisce una nota finta con dentro il marcatore, che e' esattamente il suo mestiere.
# Un gate che ferma il file che lo dimostra e' un falso positivo — e i falsi positivi non
# vengono discussi, vengono aggirati con `--no-verify`, che qui spegnerebbe anche il
# leak-check nello stesso hook.
#
# La deroga sta in un file che si legge e si accorcia, come `.directory-dump-baseline`:
# concedere un'eccezione deve costare una riga visibile in un diff, non una condizione
# sepolta nello script. Una riga = un percorso esatto (niente glob: `test/*` sarebbe una
# porta aperta, non un'eccezione). `#` per i commenti.
ALLOW_FILE="${PRIVATE_MARKER_ALLOW:-test/.private-marker-allow}"
_esente() {
  [ -f "$ALLOW_FILE" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$ALLOW_FILE" 2>/dev/null | grep -qxF "$1"
}

# I due marcatori. Il primo e' la dichiarazione esplicita del file; il secondo e' la firma
# del generatore, che vale anche quando la tabella e' ancora vuota (un file appena creato
# non ha righe, ma la prossima sync gliele scrive: e' gia' un contenitore di roba privata).
_MARK_PRIVATE='^\|.*\| *private *\|'
_MARK_GBRAIN='<!--- *gbrain:facts:begin'

_files() {
  if [ "$MODE" = "--staged" ]; then
    git diff --cached --name-only --diff-filter=ACMR
  else
    git ls-files
  fi
}

_trovati=()
_perche=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  _esente "$f" && continue
  motivo=""
  if grep -qE "$_MARK_GBRAIN" "$f" 2>/dev/null; then
    motivo="tabella di fatti generata (gbrain:facts)"
  fi
  if grep -qE "$_MARK_PRIVATE" "$f" 2>/dev/null; then
    n="$(grep -cE "$_MARK_PRIVATE" "$f" 2>/dev/null || true)"
    motivo="${motivo:+$motivo, }$n riga/e marcate visibility: private"
  fi
  if [ -n "$motivo" ]; then
    _trovati+=("$f")
    _perche+=("$motivo")
  fi
done < <(_files)

if [ "${#_trovati[@]}" -eq 0 ]; then
  echo "private-marker-check: OK — nessun file che si dichiara privato ($([ "$MODE" = "--staged" ] && echo "indice" || echo "repo") pulito)."
  exit 0
fi

echo "" >&2
echo "private-marker-check: TROVATI ${#_trovati[@]} file che dichiarano contenuto PRIVATO in un repo PUBBLICO:" >&2
i=0
while [ "$i" -lt "${#_trovati[@]}" ]; do
  printf '    %s  — %s\n' "${_trovati[$i]}" "${_perche[$i]}" >&2
  i=$((i+1))
done
echo "" >&2
echo "  Questi file sono scritti da un tool (gbrain), non a mano. Restano sul disco: vanno" >&2
echo "  tolti da git, non cancellati." >&2
echo "  Toglili dall'indice:  git rm --cached <file>" >&2
echo "  e ignorali:           aggiungi la sua cartella a .gitignore" >&2
echo "  Se invece il contenuto e' davvero pubblicabile, cambia 'private' nel file: la" >&2
echo "  dichiarazione e' quello che questo gate legge, e va corretta li', non aggirata qui." >&2
exit 1
