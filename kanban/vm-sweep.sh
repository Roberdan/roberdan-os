#!/usr/bin/env bash
# kanban/vm-sweep.sh — Colima (Docker via VM) ferme e dimenticate: le mostra, le misura, le
# toglie SOLO con --yes. Stessa filosofia di worktree-sweep.sh, applicata a un problema gemello.
#
# Scar 2026-09-27: un disco virtuale Colima fermo e' passato da 20GB a 192GB dentro le
# istantanee di RustyMacBackup, perche' cambia troppo spesso perche' l'hard-link lo deduplichi.
# Nessuno l'aveva avviato "per usarlo": un agente l'ha creato per un test isolato durante il
# rilascio di ConvergioEdu2030 (260920-090907) e non l'ha mai smontato dopo. Il fix nel prodotto
# (RustyMacBackup non backuppa piu' .colima/.lima/.orbstack di default) chiude la falla nei
# backup; questo file chiude la falla a monte, sul Mac: un agente che crea un ambiente isolato
# e lo dimentica non deve restare invisibile fino al prossimo giro di `du`.
#
# A differenza dei worktree, un'istanza Colima non appartiene a un repo: il nome puo' suggerirlo
# (convergio-release-260920) ma non e' garantito, quindi qui non esiste scope per progetto —
# gira sempre su TUTTE le istanze, come la sezione 5 (telemetria) di checkup.sh.
set -uo pipefail

_human() { # byte -> qualcosa che si legge
  awk -v b="${1:-0}" 'BEGIN{s="B KB MB GB TB"; split(s,u," "); i=1; while(b>=1024 && i<5){b/=1024;i++} printf "%.1f%s", b, u[i]}'
}

# Stessa trappola BSD/GNU di checkup.sh: su GNU `stat -f` esiste ma vuol dire un'altra cosa
# (formato del filesystem), quindi il primo tentativo puo' "riuscire" rispondendo una sciocchezza.
# Si accetta solo una risposta fatta di cifre.
_mtime() {
  local v
  v="$(stat -c %Y "$1" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) v="$(stat -f %m "$1" 2>/dev/null)" ;; esac
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  printf '%s' "$v"
}
_giorni_fa() { awk -v t="${1:-0}" -v n="$(date +%s)" 'BEGIN{ if(t<=0){print 0} else {printf "%d", (n-t)/86400} }'
}

_size_of() { du -sk "$1" 2>/dev/null | awk '{print $1*1024} END{if(NR==0) print 0}'; }

# Il nome che lima usa internamente per l'istanza dati di un profilo: "colima" per il profilo
# default, "colima-<profilo>" per tutti gli altri — verificato sui profili reali del 2026-09-27,
# non dedotto dai sorgenti di colima (che possono cambiare formato senza avviso).
_lima_name() {
  local profile="$1"
  [ "$profile" = "default" ] && printf 'colima' || printf 'colima-%s' "$profile"
}

# _sweep [--yes] [--stale-days N] — un profilo FERMO (mai uno in esecuzione, mai) e piu' vecchio
# della soglia viene mostrato; con --yes viene tolto con `colima delete`, il comando ufficiale
# (non `rm -rf`: e' colima stesso a sapere se un'istanza ha ancora qualcosa in mano).
_sweep() {
  local apply=0 stale="${RDA_VM_STALE_DAYS:-3}" home="${HOME:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) apply=1 ;;
      --stale-days) stale="${2:-3}"; shift ;;
    esac; shift
  done
  if ! command -v colima >/dev/null 2>&1; then
    printf '  Colima non installato: niente da controllare.\n'
    return 0
  fi
  local colima_home="${COLIMA_HOME:-$home/.colima}"
  [ -d "$colima_home" ] || { printf '  Nessuna istanza Colima presente.\n'; return 0; }

  local n=0 rm=0 kept=0 freed=0
  while IFS=$'\t' read -r profile status; do
    [ -n "$profile" ] || continue
    n=$((n+1))
    local dir="$colima_home/$profile"
    local eta; eta="$(_giorni_fa "$(_mtime "$dir")")"
    case "$status" in
      Running|running)
        kept=$((kept+1))
        printf '  in esecuzione, non si tocca: %s\n' "$profile"
        continue
        ;;
    esac
    if [ "$eta" -lt "$stale" ]; then
      kept=$((kept+1))
      printf '  ferma da %s giorni (sotto soglia %s): %s\n' "$eta" "$stale" "$profile"
      continue
    fi
    local lima_dir="$colima_home/_lima/$(_lima_name "$profile")"
    local disk_dir="$colima_home/_lima/_disks/$(_lima_name "$profile")"
    local sz=0
    sz=$(( ${sz:-0} + $(_size_of "$dir") + $(_size_of "$lima_dir") + $(_size_of "$disk_dir") ))
    if [ "$apply" = "1" ]; then
      if colima delete "$profile" --force >/dev/null 2>&1; then
        # `colima delete` a volte lascia il disco dati orfano (vedi scar in testa al file):
        # se colima stesso non lo conosce piu' (limactl disk list non lo elenca), e' sicuro
        # toglierlo a mano.
        if [ -d "$disk_dir" ] && ! limactl disk list 2>/dev/null | grep -q "^$(_lima_name "$profile")\b"; then
          rm -rf "$disk_dir"
        fi
        rm=$((rm+1)); freed=$((freed + sz))
        printf '  tolta   %s (ferma da %s giorni, %s liberati)\n' "$profile" "$eta" "$(_human "$sz")"
      else
        printf '  NON tolta %s (colima ha rifiutato — controlla a mano: colima delete %s)\n' "$profile" "$profile"
      fi
    else
      rm=$((rm+1))
      printf '  ferma da %s giorni, rimovibile: %-28s %s\n' "$eta" "$profile" "$(_human "$sz")"
    fi
  done < <(colima list 2>/dev/null | awk 'NR>1 && NF>=2 {print $1"\t"$2}')

  if [ "$n" -eq 0 ]; then
    printf '  nessuna istanza Colima.\n'
  elif [ "$apply" = "1" ]; then
    printf '\n  %s istanze esaminate · %s tolte · %s tenute · %s liberati\n' "$n" "$rm" "$kept" "$(_human "$freed")"
  else
    printf '\n  %s istanze esaminate · %s rimovibili · %s tenute — per toglierle: kb checkup --yes\n' "$n" "$rm" "$kept"
  fi
}

case "${1:-}" in
  audit) shift; _sweep "$@" ;;
  sweep) shift; _sweep "$@" ;;
  *) echo "usage: vm-sweep.sh {audit|sweep} [--yes] [--stale-days N]" >&2; exit 2 ;;
esac
