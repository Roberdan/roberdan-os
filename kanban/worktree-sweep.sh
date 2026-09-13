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
# sembra pulita: e' il posto dove qualcuno sta lavorando adesso.
_owned_by_doing_card() {
  local wt="$1" board
  for board in "${RDA_KANBAN:-$(dirname "${BASH_SOURCE[0]}")}" "$HOME/GitHub"/*/kanban; do
    [ -d "$board/doing" ] || continue
    grep -rlq "^worktree: $wt\$" "$board/doing" 2>/dev/null && return 0
  done
  return 1
}

# Il branch e' gia' finito nel ramo principale? Due modi, perche' uno solo mente:
#  - discendenza git: vale per i merge veri;
#  - PR in stato MERGED: e' l'unico modo di vedere uno squash-merge, che RISCRIVE i commit e
#    quindi rende la discendenza falsa. Senza questo controllo lo spazzino non rimuoverebbe
#    mai niente in un repo che fa squash — cioe' in quasi tutti.
_branch_integrated() {
  local repo="$1" branch="$2" base
  base="$(_base_ref "$repo")"
  git -C "$repo" merge-base --is-ancestor "$branch" "$base" 2>/dev/null && return 0
  # RDA_WT_FAST: risposta solo-git, nessuna rete. Il campanello di inizio sessione deve costare
  # millisecondi, non un minuto di chiamate a GitHub — e sbagliare per DIFETTO (conta meno copie
  # rimovibili del vero) e' l'unico verso in cui un contatore puo' sbagliare senza fare danno.
  [ "${RDA_WT_FAST:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1 || return 1
  [ -n "$(gh pr list --repo "$(git -C "$repo" remote get-url origin 2>/dev/null)" \
        --head "$branch" --state merged --json number -q '.[0].number' 2>/dev/null)" ]
}

# _verdict <path> <repo-name> -> "REMOVE" | "KEEP: <perche'>"
_verdict() {
  local wt="$1" name="$2" repo branch dirty
  case "$PWD/" in "$wt"/*) echo "KEEP: e' la cartella in cui stai lavorando adesso"; return 0 ;; esac
  [ -d "$wt" ] || { echo "REMOVE"; return 0; }
  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || { echo "KEEP: non e' un worktree git"; return 0; }
  _owned_by_doing_card "$wt" && { echo "KEEP: appartiene a una card in corso"; return 0; }
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | grep -c . || true)"
  [ "${dirty:-0}" -gt 0 ] && { echo "KEEP: $dirty file non salvati"; return 0; }
  repo="$(_repo_path "$name" || true)"
  [ -n "$repo" ] || { echo "KEEP: non trovo il checkout principale di $name"; return 0; }
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  _branch_integrated "$repo" "$branch" || { echo "KEEP: $branch ha lavoro non ancora integrato"; return 0; }
  echo "REMOVE"
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

_sweep() {
  local apply=0 junk=0 n=0 rm=0 kept=0 name wt v only
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) apply=1 ;;
      --all) RDA_WT_SCOPE_ALL=1 ;;
      --junk) junk=1 ;;
    esac; shift
  done
  only="$(_scope)"
  [ -n "$only" ] && printf 'ambito: solo %s (da roberdan-os, o con --all, guarda tutti i repo)\n' "$only"
  for repodir in "$WT_HOME"/*/; do
    [ -d "$repodir" ] || continue
    name="$(basename "$repodir")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    for wt in "$repodir"*/; do
      [ -d "$wt" ] || continue
      wt="${wt%/}"; n=$((n+1))
      v="$(_verdict "$wt" "$name")"
      if [ "$v" = "REMOVE" ]; then
        if [ "$apply" = "1" ]; then
          _remove "$wt" "$name" >/dev/null 2>&1 && { rm=$((rm+1)); printf '  rimossa   %s\n' "$wt"; } \
            || printf '  NON rimossa (git ha rifiutato) %s\n' "$wt"
        else
          rm=$((rm+1)); printf '  da rimuovere %s\n' "$wt"
        fi
      else
        kept=$((kept+1)); printf '  tenuta    %-58s %s\n' "$wt" "$v"
      fi
    done
  done
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
# e ambito ristretto al repo corrente. Disattivabile con RDA_NO_AUTOSWEEP=1.
_autosweep() {
  [ "${RDA_NO_AUTOSWEEP:-0}" = "1" ] && return 0
  local only stamp mins
  only="$(_scope)"
  [ -n "$only" ] || return 0          # fuori da un repo non si pulisce niente a sorpresa
  mins="${RDA_WT_AUTOSWEEP_MIN:-20}"
  stamp="$RDA_HOME/autosweep-$only"
  mkdir -p "$RDA_HOME" 2>/dev/null || true
  if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin "-$mins" 2>/dev/null)" ]; then return 0; fi
  : > "$stamp"
  local name wt
  for wt in "$WT_HOME/$only"/*/; do
    [ -d "${wt%/}" ] || continue
    wt="${wt%/}"
    [ "$(_verdict "$wt" "$only")" = "REMOVE" ] || continue
    _remove "$wt" "$only" >/dev/null 2>&1 && printf 'copia di lavoro non piu\ necessaria, rimossa: %s\n' "$wt"
  done
  return 0
}

# wt count — solo il numero di rimovibili, per il campanello di inizio sessione.
_count_removable() {
  local n=0 name wt
  export RDA_WT_FAST=1
  for repodir in "$WT_HOME"/*/; do
    [ -d "$repodir" ] || continue
    name="$(basename "$repodir")"
    for wt in "$repodir"*/; do
      [ -d "${wt%/}" ] || continue
      [ "$(_verdict "${wt%/}" "$name")" = "REMOVE" ] && n=$((n+1))
    done
  done
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
