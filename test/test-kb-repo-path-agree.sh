#!/usr/bin/env bash
# test-kb-repo-path-agree.sh — le copie di "dove sta il checkout di <nome>?" devono rispondere
# tutte la stessa cosa.
#
# PERCHE' ESISTE, e perche' NON e' un file condiviso. La risposta vive in tre punti: kb.sh
# (`_repo_path`), worktree.sh (che lo dice per scritto: "kept here so this script stands alone")
# e thor-verify.sh, che ne ha avuto bisogno con la card 260802-212646. La mossa ovvia era
# estrarla in kanban/repo-path.sh e sorgerla da tutti e tre. E' stata provata, e misurata:
# con quel file assente — un fixture che non lo copia, un'installazione parziale — `kb.sh` muore
# a meta', `kb queue --restanti` stampa NIENTE invece del conteggio, e hooks/goal-gate.sh, che
# quel numero lo legge, SMETTE DI BLOCCARE. Cioe' la dipendenza tra file falliva in silenzio e
# in senso permissivo: il verso peggiore, e per giunta lontano dal punto del guasto.
#
# Quindi si tiene la copia, e si toglie alla copia la sua unica vera insidia: che le copie
# divergano senza che nessuno se ne accorga. Qui si interroga OGNI implementazione con gli
# stessi ingressi e si pretende la stessa risposta. Se qualcuno cambia una regola in un punto
# solo, questo test lo dice — che e' esattamente il servizio che il file condiviso prometteva,
# senza il guasto silenzioso che portava in dote.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { printf '  ok   — %s\n' "$1"; }
err() { printf '  FAIL — %s\n' "$1"; fails=$((fails+1)); }

# Un registro finto con un repo vero dentro.
REGISTERED="$TMP/registrato"; mkdir -p "$REGISTERED"
export RDA_KANBAN_REGISTRY="$TMP/reg"
# kb.sh e worktree.sh leggono $REGISTRY dallo scope del file, non dall'ambiente: qui si
# riproduce quello che i due script fanno all'avvio, altrimenti l'estrazione non e' fedele.
# shellcheck disable=SC2034  # la leggono le funzioni estratte da kb.sh/worktree.sh via eval
REGISTRY="$TMP/reg"
COMMENT_LINE="# un commento"
{ printf '%s\n' "$COMMENT_LINE"; echo ""; printf '%s\n' "$REGISTERED"; } > "$RDA_KANBAN_REGISTRY"

# Le implementazioni, estratte dai file veri e chiamate con lo stesso nome.
# kb.sh e worktree.sh definiscono `_repo_path`; thor-verify.sh definisce `_tv_repo_path`
# dentro un `if`, quindi si estrae il corpo e lo si rinomina.
_extract() {  # <file> <nome funzione> <nome di destinazione>
  awk -v fn="$2" '
    $0 ~ "^[[:space:]]*"fn"\\(\\)" { inside=1 }
    inside { print }
    inside && /^[[:space:]]*}[[:space:]]*$/ { exit }
  ' "$1" | sed "s/^[[:space:]]*$2()/$3()/"
}

for spec in "kanban/kb.sh:_repo_path:kb" "kanban/worktree.sh:_repo_path:wt" "kanban/thor-verify.sh:_tv_repo_path:tv"; do
  f="${spec%%:*}"; rest="${spec#*:}"; fn="${rest%%:*}"; tag="${rest##*:}"
  body="$(_extract "$ROOT/$f" "$fn" "impl_$tag")"
  if [ -z "$body" ]; then err "non sono riuscito a estrarre $fn da $f: il test non sta provando niente"; continue; fi
  eval "$body" || err "il corpo estratto da $f non e' valutabile"
done

_impls() { echo "kb wt tv"; }

# risposta normalizzata: il percorso, oppure la stringa vuota. Le implementazioni differiscono
# nel CODICE DI USCITA (chi torna 1, chi stampa e basta) e va bene: cio' che deve coincidere e'
# la risposta. Un chiamante che confondesse "" con un percorso avrebbe gia' il difetto.
_ask() { local tag="$1" name="$2"; "impl_$tag" "$name" 2>/dev/null || true; }

_agree() { # <descrizione> <nome> <atteso>
  local what="$1" name="$2" want="$3" tag got bad=""
  for tag in $(_impls); do
    command -v "impl_$tag" >/dev/null 2>&1 || continue
    got="$(_ask "$tag" "$name")"
    [ "$got" = "$want" ] || bad="$bad $tag=<$got>"
  done
  if [ -z "$bad" ]; then ok "$what — tutte rispondono <$want>"; else err "$what — atteso <$want>, ma:$bad"; fi
}

_agree "un repo nel registro si risolve al suo percorso" "$(basename "$REGISTERED")" "$REGISTERED"
_agree "un nome che nessuno conosce non si risolve" "repo-inesistente-xyz" ""
_agree "un nome vuoto non si risolve" "" ""

# Una riga di commento nel registro non e' un repo.
# Va interrogata col basename REALE della riga ("commento", da "# un commento"): e' quello
# che le implementazioni confrontano. Interrogare "#" non prova nulla — nessuna riga ha mai
# quel basename, quindi l'asserzione resterebbe verde anche togliendo il comment-skip.
_agree "una riga di commento nel registro non diventa un repo" \
  "$(basename "$COMMENT_LINE")" ""

echo
if [ "$fails" -eq 0 ]; then echo "test-kb-repo-path-agree: PASS"; exit 0; fi
echo "test-kb-repo-path-agree: FAIL ($fails)"; exit 1
