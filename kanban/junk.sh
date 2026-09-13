#!/usr/bin/env bash
# kanban/junk.sh — cache, build e temporanei: li mostra, li misura, li toglie SOLO se glielo dici.
#
# Regola unica, e vale per qualsiasi repo senza saperne niente: si tocca solo cio' che e'
# **ignorato da git** (quindi rigenerabile per dichiarazione del repo stesso) **E** ha un nome
# nella lista qui sotto. Le due condizioni insieme, mai una sola:
#   - solo "ignorato" cancellerebbe un .env con le chiavi, o un file di dati che qualcuno ha
#     messo li' apposta: ignorato vuol dire "non versionato", non "non serve";
#   - solo il nome cancellerebbe un `dist/` che in QUEL repo e' versionato sul serio.
# Cosa NON tocca mai, di proposito: i file non tracciati e NON ignorati (sono lavoro di qualcuno,
# mai versionato = unica copia) e qualunque cosa dentro .git.
set -uo pipefail

# I nomi. `node_modules` e le venv stanno qui perche' si rigenerano con un comando; i file di
# credenziali (.env*) NON ci stanno e non devono starci, anche se quasi sempre sono ignorati.
JUNK_NAMES='node_modules .venv venv __pycache__ .pytest_cache .mypy_cache .ruff_cache .next .turbo .parcel-cache .gradle .tox target/debug dist build .DS_Store .swiftpm DerivedData .cache coverage .nyc_output htmlcov'

_human() { # byte -> qualcosa che si legge
  awk -v b="${1:-0}" 'BEGIN{s="B KB MB GB TB"; split(s,u," "); i=1; while(b>=1024 && i<5){b/=1024;i++} printf "%.1f%s", b, u[i]}'
}

# _repo_junk <repo-path> — elenca i percorsi spazzatura di UN repo (uno per riga).
# `git clean -Xdn` e' git stesso a dire cosa considera ignorato: nessuna euristica nostra.
_repo_junk() {
  local repo="$1" line path base
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$repo" clean -Xdn 2>/dev/null | sed 's/^Would remove //' | while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line%/}"
    base="$(basename "$path")"
    case " $JUNK_NAMES " in
      *" $base "*) printf '%s/%s\n' "$repo" "$path" ;;
    esac
  done
}

_size_of() { du -sk "$1" 2>/dev/null | awk '{print $1*1024}'; }

# Tutti i posti da guardare: i checkout principali sotto ~/GitHub e le copie di lavoro.
_places() {
  local only="${1:-}" d
  for d in "$HOME/GitHub"/*/; do
    [ -d "$d/.git" ] || continue
    [ -n "$only" ] && [ "$(basename "$d")" != "$only" ] && continue
    printf '%s\n' "${d%/}"
  done
  for d in "${RDA_WORKTREES:-$HOME/GitHub/worktrees}"/*/*/; do
    [ -d "${d%/}" ] || continue
    [ -n "$only" ] && [ "$(basename "$(dirname "${d%/}")")" != "$only" ] && continue
    printf '%s\n' "${d%/}"
  done
}

APPLY=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) APPLY=1 ;;
    --only) ONLY="${2:-}"; shift ;;
  esac; shift
done

tot=0; cnt=0
TOPN="${RDA_JUNK_TOP:-12}"
TMPL="$(mktemp)"; trap 'rm -f "$TMPL"' EXIT
echo "=== cache, build e temporanei (solo file che git dichiara ignorati E con un nome noto) ==="
while IFS= read -r place; do
  [ -n "$place" ] || continue
  while IFS= read -r j; do
    [ -n "$j" ] || continue
    sz="$(_size_of "$j")"; tot=$((tot + ${sz:-0})); cnt=$((cnt+1))
    if [ "$APPLY" = "1" ]; then
      # git clean, non rm -rf: e' git a rifiutare qualunque cosa non sia ignorata, anche se
      # questo script sbagliasse a costruire il percorso.
      ( cd "$place" && git clean -Xdfq -- "${j#"$place"/}" >/dev/null 2>&1 ) || printf '  NON tolto (git ha rifiutato) %s\n' "$j"
    fi
    printf '%s\t%s\t%s\n' "${sz:-0}" "$(basename "$place")" "$j" >> "$TMPL"
  done <<EOF
$(_repo_junk "$place")
EOF
done <<EOF
$(_places "$ONLY")
EOF

# Un elenco di 2764 righe non lo legge nessuno, e una cosa che nessuno legge non e' un referto.
# Quindi: totale per repo, piu' i pochi elementi che pesano davvero.
if [ "$cnt" -gt 0 ]; then
  echo "  per progetto:"
  awk -F'\t' '{s[$2]+=$1; n[$2]++} END{for(r in s) printf "%d\t%s\t%d\n", s[r], r, n[r]}' "$TMPL" \
    | sort -rn | while IFS=$'\t' read -r b r n; do printf '    %-22s %-9s (%s elementi)\n' "$r" "$(_human "$b")" "$n"; done
  printf '  i %s piu pesanti:\n' "$TOPN"
  sort -rn "$TMPL" | head -n "$TOPN" | while IFS=$'\t' read -r b _ p; do printf '    %-9s %s\n' "$(_human "$b")" "$p"; done
fi

if [ "$cnt" -eq 0 ]; then
  echo "  niente da togliere."
elif [ "$APPLY" = "1" ]; then
  printf '\n%s elementi · %s liberati\n' "$cnt" "$(_human "$tot")"
else
  printf '\n%s elementi · %s occupati — per toglierli: kb checkup --yes (oppure kb wt --junk --yes)\n' "$cnt" "$(_human "$tot")"
fi
