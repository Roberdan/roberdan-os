#!/usr/bin/env bash
# test/new-area-check.sh — rifiuta un commit che APRE UNA ZONA NUOVA del repo senza che
# nessun essere umano l'abbia mai riconosciuta.
#
# PERCHE' ESISTE — la domanda che i primi tre gate non possono fare.
#
# Gli altri tre chiedono qualcosa AL FILE:
#   leak-check.sh            -> "e' un segreto che ho gia' scritto in lista?"   (VOCABOLARIO)
#   directory-dump-check.sh  -> "ha la forma di un estratto di rubrica?"        (FORMA)
#   private-marker-check.sh  -> "dice DA SOLO di essere privato?"               (DICHIARAZIONE)
#
# Tutte e tre dipendono dalla BUONA EDUCAZIONE di chi ha scritto il file. Un tool che
# deposita dati riservati senza mettere nessun marcatore, con parole che non sono su nessuna
# lista e senza indirizzi dentro, passa tutti e tre — e passa correttamente: hanno risposto
# alla loro domanda, e la risposta era no.
#
# Questo ne fa una quarta, che non guarda il contenuto per niente:
#
#   *** questo file sta in una zona del repo che nessuno ha mai aperto? ***     (IL POSTO)
#
# Il 2026-08-24 tre note generate da gbrain sono atterrate qui dentro — repo PUBBLICO — in
# `people/`, `projects/`, `claude-code/`. Non e' un dettaglio del caso: e' la sua forma.
# Un generatore che non ha una destinazione dichiarata scrive relativo alla CWD, e cio' che
# scrive finisce in un posto che nel repo NON ESISTEVA. Nessun umano aveva mai messo un file
# li' dentro. Quella e' l'impronta della provenienza, e si legge senza aprire il file.
#
# COSA NON NOMINA, di proposito (e' il requisito che l'ha fatto nascere):
#   - nessuna cartella specifica: non c'e' `people/` ne' `projects/` in questo script. La
#     regola e' "una zona con zero file in HEAD", quindi vale per la cartella che il tool
#     invented ieri e per quella che inventera' domani;
#   - nessun tool specifico: non c'e' `gbrain`. Vale per qualunque cosa scriva nella
#     working tree, compreso un agente, uno script, un export di un'app;
#   - nessun marcatore dentro al file: non legge il contenuto. Non puo' essere aggirato
#     omettendo una colonna, e non puo' sbagliare per un contenuto che sembra qualcos'altro.
#
# IL LIMITE, detto per intero. Questo gate vede la zona, non il file. Un tool che deposita
# dentro una zona GIA' ESISTENTE (`docs/`, `skills/`) non lo fa scattare — li' rispondono gli
# altri tre, o nessuno. E' una difesa in piu', non la difesa definitiva: chiude la strada
# osservata il 2026-08-24 (una cartella nuova comparsa dal nulla) e lascia aperta quella di un
# deposito mimetizzato in casa d'altri. Scriverlo qui e' meglio che scoprirlo dopo.
#
# PERCHE' NON BASTA IL .gitignore. Le cartelle di quel giorno sono ignorate, ed e' giusto.
# Ma il .gitignore ferma i NOMI DI OGGI: la prossima sync puo' inventarne un altro, e quel
# file tornerebbe untracked-ma-committabile. Questo ferma la CLASSE "zona mai vista".
#
# Uso:
#   new-area-check.sh --staged   # solo cio' che il commit AGGIUNGE (hook pre-commit)
#   new-area-check.sh            # igiene del repo + non tracciati (validate.sh)
#
# Come private-marker-check.sh: non cancella e non modifica niente, e non stampa il
# contenuto dei file. Un guardiano che incolla il segreto nel proprio errore ha spostato la
# fuga, non fermata.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

MODE="${1:-}"

# LE ZONE RICONOSCIUTE, e perche' stanno in un file invece che in un `case` qui dentro.
#
# Aprire una zona nuova e' una cosa che si fa davvero, ogni tanto, e di proposito. Il costo
# di farlo dev'essere UNA RIGA VISIBILE IN UN DIFF — non una condizione sepolta nello script,
# e nemmeno `--no-verify`, che qui spegnerebbe anche il leak-check nello stesso hook.
# Stessa scelta di `.private-marker-allow` e `.directory-dump-baseline`.
#
# Una riga = una zona esatta (niente glob: `*` sarebbe una porta aperta, non un'eccezione).
# Una zona e' il PRIMO pezzo del percorso: `docs` per `docs/x/y.md`, `README.md` per un file
# in radice. `#` per i commenti.
ACK_FILE="${NEW_AREA_ACK:-test/.new-area-ack}"
_riconosciuta() {
  [ -f "$ACK_FILE" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$ACK_FILE" 2>/dev/null | grep -qxF "$1"
}

# La zona di un percorso: il primo componente. Per un file in radice la zona e' il file
# stesso — anche un `roberto.md` depositato in cima al repo e' un posto che nessuno ha
# aperto, e sarebbe un buco stupido lasciarlo passare solo perche' non ha una cartella.
_zona() { printf '%s' "${1%%/*}"; }

# "Esiste gia'?" si chiede a **HEAD**, non all'indice. `git ls-files` legge l'indice, e in
# modalita' --staged il file appena messo in stage e' GIA' li': la zona risulterebbe
# popolata da se stessa e il gate direbbe sempre di si'. HEAD e' l'unica fotografia del
# "prima" che il commit non puo' contaminare.
_ha_storia() {
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || return 1   # primo commit: niente storia
  [ -n "$(git ls-tree -r --name-only HEAD -- "$1" 2>/dev/null | head -1)" ]
}

# In modalita' repo si guardano anche i file NON TRACCIATI (e non ignorati): e' quello lo
# stato normale di una nota appena deposta, e accorgersene solo quando e' gia' in commit
# vuol dire accorgersene esattamente quando non serviva piu'. `--exclude-standard` tiene
# buono il .gitignore, cosi' cio' che e' davvero ignorato non diventa un falso positivo.
_files() {
  if [ "$MODE" = "--staged" ]; then
    git diff --cached --name-only --diff-filter=A
  else
    git ls-files
    git ls-files --others --exclude-standard
  fi
}

_zone_nuove=()
_esempi=()
_conta=()

_indice_di() {
  local z="$1" i=0
  while [ "$i" -lt "${#_zone_nuove[@]}" ]; do
    [ "${_zone_nuove[$i]}" = "$z" ] && { printf '%s' "$i"; return 0; }
    i=$((i+1))
  done
  return 1
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  z="$(_zona "$f")"
  [ -n "$z" ] || continue
  _riconosciuta "$z" && continue
  _ha_storia "$z" && continue
  if i="$(_indice_di "$z")"; then
    _conta[$i]=$(( ${_conta[$i]} + 1 ))
  else
    _zone_nuove+=("$z")
    _esempi+=("$f")
    _conta+=(1)
  fi
done < <(_files)

if [ "${#_zone_nuove[@]}" -eq 0 ]; then
  echo "new-area-check: OK — nessuna zona nuova non riconosciuta ($([ "$MODE" = "--staged" ] && echo "indice" || echo "repo"))."
  exit 0
fi

echo "" >&2
echo "new-area-check: ${#_zone_nuove[@]} zona/e del repo che nessuno ha mai aperto:" >&2
i=0
while [ "$i" -lt "${#_zone_nuove[@]}" ]; do
  printf '    %-24s %s file, es. %s\n' "${_zone_nuove[$i]}" "${_conta[$i]}" "${_esempi[$i]}" >&2
  i=$((i+1))
done
echo "" >&2
echo "  Nessun file e' mai stato in queste zone in tutta la storia del repo. La forma piu'" >&2
echo "  comune di questo evento NON e' una scelta: e' un tool che ha scritto nella working" >&2
echo "  tree (senza local_path scrive relativo alla CWD) e un 'git add -A' che ha preso" >&2
echo "  quello che ha trovato. E' successo qui il 2026-08-24, in un repo pubblico." >&2
echo "" >&2
echo "  SE NON LI HAI SCRITTI TU — non cancellarli: possono essere l'UNICA copia." >&2
echo "      git rm --cached -r <zona>            # fuori da git, restano sul disco" >&2
echo "      mkdir -p ~/.roberdan-os/private/brain/<zona>" >&2
echo "      mv <zona>/* ~/.roberdan-os/private/brain/<zona>/" >&2
echo "  Quella cartella e' fuori da qualsiasi worktree git: nessun commit la raggiunge." >&2
echo "  Poi cerca la causa, non il sintomo: quale generatore ha scritto li', e perche' non" >&2
echo "  aveva una destinazione dichiarata. Finche' non lo sistemi, domani riscrive." >&2
echo "  Il caso gia' successo, con i comandi esatti: docs/privacy-leak-check.md" >&2
echo "" >&2
echo "  SE INVECE LA ZONA E' TUA e la stai aprendo apposta: aggiungi il suo nome, una riga," >&2
echo "  a $ACK_FILE. Deve costare una riga visibile in un diff — questo e' il punto." >&2
exit 1
