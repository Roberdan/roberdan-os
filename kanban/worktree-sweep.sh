#!/usr/bin/env bash
# kanban/worktree-sweep.sh — la meta' "inventario" di worktree.sh: guarda TUTTE le copie di
# lavoro (non solo quelle nate da una card), dice quali non hanno piu' niente dentro, le toglie
# quando glielo chiedi, e le toglie DA SOLA appena un ramo viene integrato (autosweep).
# Vive in un file suo perche' worktree.sh, con dentro anche questo, superava le 300 righe che
# rules/best-practices.md impone ai file scritti a mano.
# Non si lancia a mano: ci si arriva da `worktree.sh sweep|autosweep|count` (o da `kb wt`).
set -uo pipefail
# Il percorso puo' arrivare da un symlink (~/.local/bin, wrapper di piattaforma): senza questo
# giro di risoluzione lo script cercherebbe i suoi fratelli accanto al link, non accanto a se'.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _d="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
done
DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _d
# shellcheck source=kanban/worktree.sh
RDA_WT_NO_DISPATCH=1 . "$DIR/worktree.sh"
# La scoperta dei repo, il registro di git come fonte di verita' su dove vivono i worktree, e il
# verdetto: vedi l'intestazione di quel file per il perche' (@thor F2, card 260924-085105-3b).
# shellcheck source=kanban/worktree-locations.sh
. "$DIR/worktree-locations.sh"
# Numero di copie rimovibili gia' calcolato: scritto dal job notturno e da ogni `kb wt`, letto
# (mai calcolato) dal campanello di inizio sessione.
CACHE="${RDA_WT_COUNT_CACHE:-$RDA_HOME/worktrees-count}"

# --- inventario e pulizia di TUTTE le copie di lavoro, non solo quelle delle card ----------
# La radice del problema misurata il 2026-09-13: 99 worktree vivi sotto ~/GitHub/worktrees,
# 96 di repo diversi da questo, nessuno chiuso da chi l'aveva aperto. `kb start`/`kb finish`
# governano solo le copie NATE da una card: tutto il resto (agenti, sessioni manuali, altri
# strumenti) non passa di qui e quindi non veniva mai raccolto da nessuno.
# La risposta e' di STATO, non di proprieta': non importa chi l'ha creata, importa se contiene
# qualcosa da perdere. Cosi' funziona anche per i worktree che nessuno di questi script ha mai
# visto nascere — e per quelli che nasceranno domani da uno strumento che ancora non esiste.

# Una copia di lavoro appartiene a una card ANCORA IN CORSO? Allora non si tocca, nemmeno se
# sembra pulita: e' il posto dove qualcuno sta lavorando adesso. Confronto per percorso FISICO
# (_realpath), non stringa esatta: $wt qui arriva dal registro di git (_wt_registry), che
# risolve i symlink, mentre `worktree: <path>` sulla card e' quello che `kb start` ha scritto
# (non risolto) — su macOS (/var -> /private/var) i due non combaciano mai come stringhe.
_owned_by_doing_card() {
  local wt="$1" board f stored wt_real stored_real
  wt_real="$(_realpath "$wt")" || wt_real="$wt"
  for board in "${RDA_KANBAN:-$(dirname "${BASH_SOURCE[0]}")}" "$HOME/GitHub"/*/kanban; do
    [ -d "$board/doing" ] || continue
    for f in "$board/doing"/*.md; do
      [ -f "$f" ] || continue
      stored="$(grep '^worktree: ' "$f" 2>/dev/null | head -1)"; stored="${stored#worktree: }"
      [ -n "$stored" ] || continue
      stored_real="$(_realpath "$stored")" || stored_real="$stored"
      [ "$stored_real" = "$wt_real" ] && return 0
    done
  done
  return 1
}

# Il branch e' gia' finito nel ramo principale? Due modi, perche' uno solo mente:
#  - discendenza git: vale per i merge veri;
#  - PR in stato MERGED: e' l'unico modo di vedere uno squash-merge, che RISCRIVE i commit e
#    quindi rende la discendenza falsa. Senza questo controllo lo spazzino non rimuoverebbe
#    mai niente in un repo che fa squash — cioe' in quasi tutti.
# Il confronto con headRefOid (non solo "esiste una PR merged") e' il pezzo che manca a "not
# ancestor -> chiedi a gh se e' merged": una PR merged NON dice che il worktree e' allineato a
# quel merge — puo' avere commit locali aggiunti DOPO, mai pushati. Quei commit spariscono con
# il worktree se non si controlla che HEAD sia ESATTAMENTE il commit che gh dice merged.
# <oid> arriva gia' risolto dal chiamante (dal registro di git, _wt_registry): vale per un ramo
# normale quanto per una HEAD staccata, che non ha un nome di ramo da risolvere.
_branch_integrated() {
  local repo="$1" oid="$2" branch="$3" base merged_oid
  base="$(_base_ref "$repo")"
  git -C "$repo" merge-base --is-ancestor "$oid" "$base" 2>/dev/null && return 0
  # RDA_WT_FAST: risposta solo-git, nessuna rete. Il campanello di inizio sessione deve costare
  # millisecondi, non un minuto di chiamate a GitHub — e sbagliare per DIFETTO (conta meno copie
  # rimovibili del vero) e' l'unico verso in cui un contatore puo' sbagliare senza fare danno.
  [ "${RDA_WT_FAST:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1 || return 1
  merged_oid="$(gh pr list --repo "$(git -C "$repo" remote get-url origin 2>/dev/null)" \
        --head "$branch" --state merged --json headRefOid -q '.[0].headRefOid' 2>/dev/null)"
  [ -n "$merged_oid" ] || return 1
  [ "$merged_oid" = "$oid" ]
}

# wt audit — dice cosa c'e' e cosa farebbe, senza toccare niente.
# wt sweep [--yes] — rimuove SOLO i REMOVE. Senza --yes stampa e basta: uno spazzino che
# cancella prima di essere guardato e' esattamente il difetto che stiamo chiudendo.
# _scope — di QUALE repo parliamo. Dentro roberdan-os (la casa del sistema) l'ambito e' TUTTO,
# perche' li' stai facendo manutenzione del parco; dentro un progetto qualsiasi l'ambito e'
# SOLO quel progetto, perche' li' stai lavorando e un comando che ti tocca anche gli altri 3
# repo e' un comando che nessuno lancia piu'. `--all` forza tutto, da qualunque posto.
# Stampa il nome del repo su cui restringere, o vuoto per "tutti".
_scope() {
  local top name
  [ "${RDA_WT_SCOPE_ALL:-0}" = "1" ] && return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 0
  name="$(basename "$top")"
  # dentro una copia di lavoro il toplevel e' la copia, non il repo: il nome vero e' la
  # cartella che la contiene sotto $WT_HOME.
  case "$top/" in "$WT_HOME"/*) name="$(basename "$(dirname "$top")")" ;; esac
  [ "$name" = "roberdan-os" ] && return 0
  printf '%s' "$name"
}

# _sweep: fase A (_scan_repo, per ogni repo scoperto — il REGISTRO di git dice dove sono i suoi
# worktree, ovunque vivano) poi fase B (_scan_orphans — le quattro cartelle convenzionali, solo
# per cartelle che la fase A non ha gia' spiegato). known e' il file che collega le due fasi:
# _scan_repo ci scrive ogni path vero, _scan_orphans lo legge per non chiamare "orfano" ne' un
# worktree vero ne' un contenitore che ne ha dentro. n/rm/kept sono lette e scritte da entrambe
# le fasi per scope dinamico di bash (nessun valore di ritorno da unire).
_sweep() {
  local apply=0 junk=0 n=0 rm=0 kept=0 name repo only known
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) apply=1 ;;
      --all) RDA_WT_SCOPE_ALL=1 ;;
      --junk) junk=1 ;;
    esac; shift
  done
  only="$(_scope)"
  [ -n "$only" ] && printf 'ambito: solo %s (da roberdan-os, o con --all, guarda tutti i repo)\n' "$only"
  known="$(mktemp 2>/dev/null)" || known="${TMPDIR:-/tmp}/kb-wt-known.$$"
  : > "$known"
  trap 'rm -f "$known"' RETURN
  while IFS=$'\t' read -r name repo; do
    [ -n "$repo" ] || continue
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    _scan_repo "$repo" "$name" "$apply"
  done < <(_discover_repos)
  _scan_orphans "$apply" "$only"
  mkdir -p "$RDA_HOME" 2>/dev/null || true
  [ "$apply" = "1" ] && [ -z "$only" ] && { printf '%s' "0" > "$CACHE" 2>/dev/null || true; }
  if [ "$apply" = "1" ]; then
    printf '\n%s copie esaminate · %s rimosse · %s tenute (con motivo)\n' "$n" "$rm" "$kept"
  else
    printf '\n%s copie esaminate · %s rimovibili · %s da tenere — per rimuoverle: kb wt --yes\n' "$n" "$rm" "$kept"
  fi
  if [ "$junk" = "1" ]; then
    echo
    local jf=(); [ "$apply" = "1" ] && jf+=(--yes); [ -n "$only" ] && jf+=(--only "$only")
    bash "$DIR/junk.sh" "${jf[@]}"
  fi
}

# wt autosweep — la pulizia A MONTE, quella che evita di arrivare a 99 copie abbandonate.
# Gira da sola a fine turno e a inizio sessione, e' SILENZIOSA, tocca solo il repo in cui sei e
# rimuove solo cio' che il verdetto dichiara senza niente dentro (quindi: appena un ramo viene
# integrato, la copia sparisce al primo turno successivo, senza che nessuno se ne ricordi).
# Due protezioni contro il costo: un solo giro ogni RDA_WT_AUTOSWEEP_MIN minuti (default 20),
# e ambito ristretto al repo corrente. Disattivabile con RDA_NO_AUTOSWEEP=1. Non tocca cartelle
# prunable/orfane — mai lo ha fatto: resta compito esplicito di `kb wt --yes`.
_autosweep() {
  [ "${RDA_NO_AUTOSWEEP:-0}" = "1" ] && return 0
  local only stamp mins name repo repo_real path oid branch locked prunable path_real v
  only="$(_scope)"
  [ -n "$only" ] || return 0          # fuori da un repo non si pulisce niente a sorpresa
  mins="${RDA_WT_AUTOSWEEP_MIN:-20}"
  stamp="$RDA_HOME/autosweep-$only"
  mkdir -p "$RDA_HOME" 2>/dev/null || true
  if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin "-$mins" 2>/dev/null)" ]; then return 0; fi
  : > "$stamp"
  while IFS=$'\t' read -r name repo; do
    [ "$name" = "$only" ] || continue
    repo_real="$(_realpath "$repo")" || continue
    while IFS=$'\t' read -r path oid branch locked prunable; do
      [ -n "$path" ] || continue
      path_real="$(_realpath "$path")" || continue
      [ "$path_real" = "$repo_real" ] && continue
      v="$(_wt_verdict "$path" "$repo" "$oid" "$branch" "$locked" "$prunable")"
      if [ "$v" = "REMOVE" ] && git -C "$repo" worktree remove "$path" 2>/dev/null; then
        printf 'copia di lavoro non piu\ necessaria, rimossa: %s\n' "$path"
        case "$branch" in HEAD|BARE) ;; *) git -C "$repo" branch -d "$branch" >/dev/null 2>&1 ;; esac
      fi
    done < <(_wt_registry "$repo")
  done < <(_discover_repos)
  return 0
}

# wt count — solo il numero di rimovibili, per il campanello di inizio sessione. Non conta le
# cartelle orfane (fase B): sarebbe un altro giro di `ls` su tutto il parco per un numero che
# deve restare economico — sbagliare per DIFETTO qui e' la direzione sicura (vedi sopra).
_count_removable() {
  local n=0 name repo repo_real path oid branch locked prunable path_real v
  export RDA_WT_FAST=1
  while IFS=$'\t' read -r name repo; do
    [ -n "$repo" ] || continue
    repo_real="$(_realpath "$repo")" || continue
    while IFS=$'\t' read -r path oid branch locked prunable; do
      [ -n "$path" ] || continue
      path_real="$(_realpath "$path")" || continue
      [ "$path_real" = "$repo_real" ] && continue
      v="$(_wt_verdict "$path" "$repo" "$oid" "$branch" "$locked" "$prunable")"
      case "$v" in REMOVE|PRUNE) n=$((n+1)) ;; esac
    done < <(_wt_registry "$repo")
  done < <(_discover_repos)
  mkdir -p "$RDA_HOME" 2>/dev/null || true
  printf '%s' "$n" > "$CACHE" 2>/dev/null || true
  printf '%s' "$n"
}

# wt count --cached — quello che legge il campanello di inizio sessione. Contare davvero costa
# ~10s su un centinaio di copie: un'attesa del genere all'apertura di ogni sessione verrebbe
# tolta entro la settimana, e un avviso tolto non avvisa piu' nessuno. Quindi qui si LEGGE un
# numero gia' calcolato (dal job notturno o dall'ultimo `kb wt`) e, se manca o e' vecchio, si
# rinfresca in sottofondo e per stavolta non si dice niente. Mai far aspettare per un avviso.
_count_cached() {
  if [ -n "$(find "$CACHE" -mtime -1 2>/dev/null)" ]; then cat "$CACHE"; return 0; fi
  ( _count_removable >/dev/null 2>&1 & ) >/dev/null 2>&1
  printf '0'
}

case "${1:-}" in
  audit)     shift; _sweep ;;
  sweep)     shift; _sweep "$@" ;;
  autosweep) shift; _autosweep ;;
  count)     shift; [ "${1:-}" = "--cached" ] && _count_cached || _count_removable ;;
  *) echo "usage: worktree-sweep.sh {audit|sweep [--yes|--all|--junk]|autosweep|count [--cached]}" >&2; exit 2 ;;
esac
