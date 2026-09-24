#!/usr/bin/env bash
# kanban/worktree-locations.sh — le ALTRE tre convenzioni di worktree oltre a $WT_HOME/<repo>/<card>
# (quella che worktree-sweep.sh gia' scandisce), piu' i repo "annidati" in una cartella
# contenitore, i registri git ormai prunable e le cartelle che git non conosce piu'.
#
# Misurato il 2026-09-24: `kb wt` guardava SOLO ~/GitHub/worktrees/<repo>/*. Il resto del parco
# vive altrove e nessun comando lo nominava mai: MirrorBuddy tiene 7 copie (3.4 GB) sotto
# <repo>/worktrees/ (layout bare), Claude Code apre sotto <repo>/.claude/worktrees/, altri
# strumenti sotto <repo>/.worktrees/, e ~/GitHub/worktrees/MirrorHR/completion-20260906-f144e5a4
# e' una cartella che git non conosce affatto (il repo si chiama MirrorHR_Set ora).
#
# File separato perche' worktree-sweep.sh, con dentro anche questo, supererebbe le 300 righe che
# rules/best-practices.md impone ai file scritti a mano. Sourced da worktree-sweep.sh, che a sua
# volta e' sourced/exec-ato da worktree.sh: quando questo file gira, WT_HOME, _repo_path,
# _base_ref, _owned_by_doing_card e _branch_integrated esistono gia' nel processo.
set -uo pipefail

# GH_HOME — la cartella che contiene i repo. Derivata da WT_HOME (che e' sempre <GH_HOME>/
# worktrees) cosi' i test, che dirottano RDA_WORKTREES, dirottano anche questa senza una
# seconda variabile da tenere allineata a mano.
GH_HOME="$(dirname "$WT_HOME")"

# Roberto ci sta lavorando ORA con un altro agente: si vede nel referto, non si tocca MAI,
# nemmeno se una copia li' dentro sarebbe altrimenti rimovibile (pulita e integrata) — la
# regola e' scritta sulla card, non e' un giudizio di questo script sul contenuto.
# Due controlli, non uno solo: il PATH prende <repo>/worktrees/* (la convenzione (2), dove
# vivono le 7 copie vere di MirrorBuddy); il git-common-dir prende anche una copia registrata
# altrove per NOME (es. $WT_HOME/MirrorBuddy/<card>, la convenzione (1)) — senza il secondo
# controllo una copia cosi' sfuggirebbe all'esclusione e finirebbe rimossa.
_wt_hard_exclude() {
  local wt="$1" gcd mb_real
  case "$wt" in "$GH_HOME/MirrorBuddy"|"$GH_HOME/MirrorBuddy/"*) return 0 ;; esac
  [ -d "$wt" ] || return 1
  gcd="$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$gcd" in /*) : ;; *) gcd="$(cd "$wt" && cd "$gcd" 2>/dev/null && pwd)" ;; esac
  # git risolve i symlink (macOS: /var -> /private/var, e studio3_emea sulla macchina reale
  # e' esso stesso un symlink), quindi il confronto va fatto sul percorso FISICO di entrambi i
  # lati — altrimenti un git-common-dir corretto non combacia mai con $GH_HOME non risolto.
  mb_real="$(cd -P "$GH_HOME/MirrorBuddy" 2>/dev/null && pwd)"
  [ -n "$mb_real" ] || return 1
  case "$gcd" in "$mb_real/"*) return 0 ;; esac
  return 1
}

# Un worktree lockato (`git worktree lock`) e' quello che Claude Code tiene mentre un agente
# ci gira dentro (vedi docs/en/worktrees § Clean up subagent and background-session worktrees).
# "0 file modificati" non e' prova che l'agente ha finito — il lock e' il segnale che conta, e
# va controllato PRIMA di qualunque altro verdetto: uno spazzino che rimuove un worktree lockato
# toglie il tappeto da sotto un agente ancora in corsa.
_wt_locked() {
  local gd
  gd="$(git -C "$1" rev-parse --git-dir 2>/dev/null)" || return 1
  case "$gd" in /*) : ;; *) gd="$1/$gd" ;; esac
  [ -f "$gd/locked" ]
}

# _is_worktree_root <path> — vero SOLO se questa cartella e' la RADICE di un worktree (ha un
# proprio .git). Distinzione che conta esattamente in queste tre convenzioni: <repo>/worktrees,
# <repo>/.worktrees e <repo>/.claude/worktrees vivono DENTRO l'albero di lavoro del repo
# principale, quindi una cartella semplice li' dentro (senza .git suo) supera comunque
# `git -C <cartella> rev-parse --git-dir`: git risale ai genitori e trova il .git del repo
# principale. Senza questo controllo una cartella cosi' viene letta come "pulita e integrata"
# (lo stato del REPO, non suo) invece che come orfana — e finisce REMOVE per errore. Un worktree
# collegato ha SEMPRE un .git proprio (un FILE "gitdir: ..."), quindi -e "$1/.git" e' la guardia.
_is_worktree_root() {
  [ -e "$1/.git" ] && git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# Una cartella e' un repo se ha .git (anche come FILE, per i worktree annidati) o se e' in
# layout bare (HEAD+refs+objects senza .git — il layout di MirrorBuddy).
_is_repo_dir() {
  [ -e "$1/.git" ] && return 0
  [ -f "$1/HEAD" ] && [ -d "$1/refs" ] && [ -d "$1/objects" ] && return 0
  return 1
}

# _discover_repos — un repo per riga: "<nome>\t<path>". Le cartelle che non sono repo ma li
# CONTENGONO (WareHouse, ParkingLot, MirrorHR_Set, copilot-worktrees sulla macchina reale) si
# aprono di un livello: senza questo passo i repo parcheggiati li' dentro restano invisibili.
_discover_repos() {
  local d name sub sname
  for d in "$GH_HOME"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; name="$(basename "$d")"
    [ "$d" = "$WT_HOME" ] && continue   # location 1 stessa: la scandisce gia' worktree-sweep.sh
    if _is_repo_dir "$d"; then
      printf '%s\t%s\n' "$name" "$d"
      continue
    fi
    for sub in "$d"/*/; do
      [ -d "$sub" ] || continue
      sub="${sub%/}"; sname="$(basename "$sub")"
      _is_repo_dir "$sub" && printf '%s\t%s\n' "$sname" "$sub"
    done
  done
}

# _location_dirs <repo-path> — le tre convenzioni RELATIVE al repo (la quarta e' globale sotto
# $WT_HOME e la scandisce gia' worktree-sweep.sh). Stampa "<etichetta>\t<path>" per quelle che
# esistono davvero — niente falsi positivi su repo che non le usano.
_location_dirs() {
  local repo="$1"
  [ -d "$repo/worktrees" ] && printf 'repo/worktrees\t%s/worktrees\n' "$repo"
  [ -d "$repo/.worktrees" ] && printf 'repo/.worktrees\t%s/.worktrees\n' "$repo"
  [ -d "$repo/.claude/worktrees" ] && printf 'repo/.claude/worktrees\t%s/.claude/worktrees\n' "$repo"
}

# _verdict_at <wt-path> <repo-path> <repo-name> — come _verdict di worktree-sweep.sh ma prende
# il repo per PATH: i repo annidati sotto una cartella contenitore non si risolvono per nome
# (_repo_path guarda solo $HOME/GitHub/<nome> o il registro). Stessa logica di sicurezza:
# esclusione dura prima di tutto, poi cartella in uso, poi orfana (vuota si toglie, altrimenti
# si tiene e si dice), poi card in corso, sporca, non integrata.
_verdict_at() {
  local wt="$1" repo="$2" name="$3" branch dirty
  _wt_hard_exclude "$wt" && { echo "KEEP: MirrorBuddy — Roberto ci lavora ora con un altro agente, mai toccare"; return 0; }
  case "$PWD/" in "$wt"/*) echo "KEEP: e' la cartella in cui stai lavorando adesso"; return 0 ;; esac
  if [ ! -d "$wt" ]; then echo "REMOVE"; return 0; fi
  if ! _is_worktree_root "$wt"; then
    if [ -z "$(ls -A "$wt" 2>/dev/null)" ]; then echo "REMOVE"; else
      echo "KEEP: cartella orfana (git non la conosce), non vuota — $(ls -A "$wt" 2>/dev/null | wc -l | tr -d ' ') elementi"
    fi
    return 0
  fi
  _wt_locked "$wt" && { echo "KEEP: lockato (un agente potrebbe averci ancora sessione aperta)"; return 0; }
  _owned_by_doing_card "$wt" && { echo "KEEP: appartiene a una card in corso"; return 0; }
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | grep -c . || true)"
  [ "${dirty:-0}" -gt 0 ] && { echo "KEEP: $dirty file non salvati"; return 0; }
  [ -n "$repo" ] || { echo "KEEP: non trovo il repo principale di $name"; return 0; }
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  _branch_integrated "$repo" "$branch" "$wt" || { echo "KEEP: $branch ha lavoro non ancora integrato"; return 0; }
  echo "REMOVE"
}

# _scan_extra_locations <apply> <only> — le convenzioni 2/3/4 per ogni repo scoperto, piu' i
# registri "prunable" di git (la cartella e' gia' sparita: pulirli e' `git worktree prune`, non
# una rm — non c'e' niente da perdere). Aggiorna n/rm/kept del chiamante: bash e' a scope
# dinamico, quindi le variabili `local` di _sweep restano visibili (e modificabili) qui dentro
# perche' NON le ridichiariamo locali — e' la stessa cosa che fa gia' _verdict con quelle sue.
_scan_extra_locations() {
  local apply="$1" only="$2" repo name label dir wt v prune_out
  while IFS=$'\t' read -r name repo; do
    [ -n "$repo" ] || continue
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    while IFS=$'\t' read -r label dir; do
      [ -n "$dir" ] || continue
      for wt in "$dir"/*/; do
        [ -d "$wt" ] || continue
        wt="${wt%/}"; n=$((n+1))
        v="$(_verdict_at "$wt" "$repo" "$name")"
        if [ "$v" = "REMOVE" ]; then
          if [ "$apply" = "1" ]; then
            # MAI una `rm -rf` di riserva: se git rifiuta (es. lock preso da un agente dopo il
            # verdetto, o submodule non pulito) e' un rifiuto da rispettare, non da scavalcare.
            if _is_worktree_root "$wt"; then
              git -C "$repo" worktree remove "$wt" 2>/dev/null
            else
              rmdir "$wt" 2>/dev/null || true
            fi
            [ -d "$wt" ] && printf '  NON rimossa (git ha rifiutato) %s [%s]\n' "$wt" "$label" \
              || { rm=$((rm+1)); printf '  rimossa   %s [%s]\n' "$wt" "$label"; }
          else
            rm=$((rm+1)); printf '  da rimuovere %s [%s]\n' "$wt" "$label"
          fi
        else
          kept=$((kept+1)); printf '  tenuta    %-58s %s [%s]\n' "$wt" "$v" "$label"
        fi
      done
    done < <(_location_dirs "$repo")
    prune_out="$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
      /^worktree /{p=$2} /^prunable/{print p}')"
    [ -n "$prune_out" ] || continue
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      n=$((n+1))
      # La cartella prunable non esiste piu' (e' il senso di "prunable"), quindi l'esclusione
      # si controlla sul REPO — tutte le voci di questo giro appartengono allo stesso $repo.
      if _wt_hard_exclude "$repo"; then
        kept=$((kept+1)); printf '  tenuta    %-58s %s\n' "$wt" "KEEP: MirrorBuddy — mai toccare, nemmeno il registro git"
      elif [ "$apply" = "1" ]; then
        git -C "$repo" worktree prune -v >/dev/null 2>&1
        rm=$((rm+1)); printf '  pulita (prunable)  %s [git worktree list]\n' "$wt"
      else
        rm=$((rm+1)); printf '  da pulire (prunable) %s [git worktree list]\n' "$wt"
      fi
    done <<< "$prune_out"
  done < <(_discover_repos)
}
