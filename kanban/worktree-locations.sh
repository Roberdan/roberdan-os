#!/usr/bin/env bash
# kanban/worktree-locations.sh — primitive: repo discovery e il REGISTRO DI GIT come fonte di
# verita' su dove vivono i worktree, non le quattro cartelle convenzionali per nome.
#
# @thor F2 (card 260924-085105-3, seguito -3b): la prima versione scandiva SOLO quattro
# cartelle per convenzione ($WT_HOME/<repo>/*, <repo>/worktrees, <repo>/.worktrees,
# <repo>/.claude/worktrees). Misurato che questo perde worktree REALI e REGISTRATI da git in
# posti arbitrari: ~/GitHub/VirtualBPMFy27-hls2-scope (un fratello di primo livello, mai dentro
# nessuna delle quattro convenzioni) e ~/GitHub/copilot-worktrees/MirrorScopio/roberdan-...
# (nidificato due livelli sotto una cartella che non e' nemmeno un repo). Entrambi appartengono
# a un repo scoperto altrove (VirtualBPMFy27, ParkingLot/MirrorScopio) e compaiono per intero in
# `git -C <quel repo> worktree list --porcelain`, eseguito da OVUNQUE nella stessa famiglia.
# La correzione di fondo: per ogni repo scoperto, si CHIEDE A GIT dove sono i suoi worktree
# (_wt_registry) invece di indovinarlo dal filesystem — cosi' un worktree si trova ovunque git
# lo sappia, non solo nelle quattro cartelle per nome. Le quattro cartelle restano scandite (in
# worktree-sweep.sh, fase B) ma SOLO per trovare cartelle che git non conosce affatto: un
# worktree che il registro gia' conosce non e' mai "orfano", nemmeno se una fase successiva lo
# incontra di nuovo per nome.
#
# File separato perche' worktree-sweep.sh, con dentro anche questo, supererebbe le 300 righe che
# rules/best-practices.md impone ai file scritti a mano. Sourced da worktree-sweep.sh, che a sua
# volta e' sourced/exec-ato da worktree.sh: quando questo file gira, WT_HOME esiste gia' nel
# processo.
set -uo pipefail

# GH_HOME — la cartella che contiene i repo. Derivata da WT_HOME (che e' sempre <GH_HOME>/
# worktrees) cosi' i test, che dirottano RDA_WORKTREES, dirottano anche questa senza una
# seconda variabile da tenere allineata a mano.
GH_HOME="$(dirname "$WT_HOME")"

# _realpath <path> — il percorso FISICO, symlink risolti. macOS: /var e' un symlink verso
# /private/var, quindi $HOME (che passa per /var/folders nei test via mktemp) e un
# `git rev-parse`/`cd -P` sullo stesso posto NON combaciano come stringhe se uno dei due non e'
# risolto. Ogni confronto fra "questo path" e "quel path" in questo file passa da qui — mai un
# confronto testuale diretto fra un path costruito a mano e uno che e' passato per git o per cd.
_realpath() { (cd -P "$1" 2>/dev/null && pwd) || return 1; }

# Roberto ci sta lavorando ORA con un altro agente: si vede nel referto, non si tocca MAI,
# nemmeno se una copia li' dentro sarebbe altrimenti rimovibile (pulita e integrata) — la
# regola e' scritta sulla card, non e' un giudizio di questo script sul contenuto. Confronto per
# IDENTITA' DI REPO (il repo che possiede questo worktree e' fisicamente MirrorBuddy), non per
# path del worktree: una copia vive per convenzione sotto MirrorBuddy/worktrees/*, ma potrebbe
# in teoria vivere altrove pur appartenendo allo stesso repo.
_wt_hard_exclude() {
  local repo="$1" wt="$2" mb_real repo_real
  case "$wt" in "$GH_HOME/MirrorBuddy"|"$GH_HOME/MirrorBuddy/"*) return 0 ;; esac
  mb_real="$(_realpath "$GH_HOME/MirrorBuddy")" || return 1
  repo_real="$(_realpath "$repo")" || return 1
  [ "$repo_real" = "$mb_real" ]
}

# Un repo VERO (radice principale), non un worktree collegato che si spaccia per repo: ha .git
# come CARTELLA (mai come file — quello e' il puntatore di un worktree collegato, la cui
# famiglia si scopre gia' interrogando il repo principale) o e' in layout bare (HEAD+refs+
# objects senza .git — il layout di MirrorBuddy). Senza il `-d` (invece di `-e`) un fratello
# come VirtualBPMFy27-hls2-scope verrebbe letto come un secondo repo e la sua intera famiglia di
# worktree, gia' vista interrogando VirtualBPMFy27, ricomparirebbe duplicata nel referto.
_is_repo_dir() {
  [ -d "$1/.git" ] && return 0
  [ -f "$1/HEAD" ] && [ -d "$1/refs" ] && [ -d "$1/objects" ] && return 0
  return 1
}

# _discover_repos — un repo VERO per riga: "<nome>\t<path>". Le cartelle che non sono repo ma li
# CONTENGONO (WareHouse, ParkingLot, MirrorHR_Set, copilot-worktrees sulla macchina reale) si
# aprono di un livello: senza questo passo i repo parcheggiati li' dentro (es. MirrorHR_Set/
# MirrorHR, che possiede i worktree sotto ~/GitHub/worktrees/MirrorHR/completion-.../*) restano
# invisibili — e con loro tutti i worktree che possiedono, ovunque vivano davvero. Il REGISTRO
# (kanban-registry, la stessa fonte di _repo_path in worktree.sh) copre quello che NEMMENO
# questo trova: un repo fuori da ~/GitHub o annidato piu' di un livello. Deduplicato per path
# FISICO — un repo trovato sia per convenzione sia per registro (il caso comune: quasi tutto il
# registro vive gia' sotto ~/GitHub) non deve uscire due volte, o ogni suo worktree raddoppierebbe.
_discover_repos() {
  local d name sub sname r real seen
  seen="$(mktemp 2>/dev/null)" || seen="${TMPDIR:-/tmp}/kb-wt-seen.$$"
  : > "$seen"
  trap 'rm -f "$seen"' RETURN
  for d in "$GH_HOME"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; name="$(basename "$d")"
    [ "$d" = "$WT_HOME" ] && continue   # location 1 stessa, non un repo
    if _is_repo_dir "$d"; then
      real="$(_realpath "$d")" || real="$d"
      grep -qxF "$real" "$seen" 2>/dev/null || { printf '%s\n' "$real" >> "$seen"; printf '%s\t%s\n' "$name" "$d"; }
      continue
    fi
    # Un .git (file, non cartella: gia' escluso da _is_repo_dir sopra) qui significa "e' un
    # worktree collegato di un altro repo" — la sua famiglia si scopre gia' interrogando QUEL
    # repo, ovunque viva (_wt_registry). Non e' un contenitore: non scendere dentro a cercarci
    # repo annidati, sarebbe solo guardare dentro un checkout di lavoro altrui.
    [ -e "$d/.git" ] && continue
    for sub in "$d"/*/; do
      [ -d "$sub" ] || continue
      sub="${sub%/}"; sname="$(basename "$sub")"
      _is_repo_dir "$sub" || continue
      real="$(_realpath "$sub")" || real="$sub"
      grep -qxF "$real" "$seen" 2>/dev/null || { printf '%s\n' "$real" >> "$seen"; printf '%s\t%s\n' "$sname" "$sub"; }
    done
  done
  if [ -f "${REGISTRY:-}" ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      case "$r" in \#*) continue ;; esac
      [ -d "$r" ] || continue
      _is_repo_dir "$r" || continue
      real="$(_realpath "$r")" || real="$r"
      grep -qxF "$real" "$seen" 2>/dev/null || { printf '%s\n' "$real" >> "$seen"; printf '%s\t%s\n' "$(basename "$r")" "$r"; }
    done < "$REGISTRY"
  fi
}

# _location_dirs <repo-path> — le tre convenzioni RELATIVE al repo, usate ORA SOLO dalla fase B
# (caccia agli orfani) in worktree-sweep.sh: ogni worktree VERO, anche dentro queste cartelle,
# si trova gia' via _wt_registry, indipendentemente da dove vive. Stampa "<etichetta>\t<path>"
# per quelle che esistono davvero — niente falsi positivi su repo che non le usano.
_location_dirs() {
  local repo="$1"
  [ -d "$repo/worktrees" ] && printf 'repo/worktrees\t%s/worktrees\n' "$repo"
  [ -d "$repo/.worktrees" ] && printf 'repo/.worktrees\t%s/.worktrees\n' "$repo"
  [ -d "$repo/.claude/worktrees" ] && printf 'repo/.claude/worktrees\t%s/.claude/worktrees\n' "$repo"
}

# _wt_registry <repo-path> — interroga IL REGISTRO DI GIT (`worktree list --porcelain`), non il
# filesystem: un record per worktree collegato, "<path>\t<HEAD-sha>\t<branch>\t<locked>\t
# <prunable>". Il checkout principale (o l'entry "bare" per un repo in layout bare) resta nel
# flusso — e' compito del chiamante scartarlo confrontando il path col repo stesso. "branch" e'
# "HEAD" per una HEAD staccata e "BARE" per l'entry bare stessa, mai vuoto (un branch vuoto
# romperebbe `git branch -d ""` piu' avanti).
_wt_registry() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() {
      if (path != "") printf "%s\t%s\t%s\t%s\t%s\n", path, head, branch, locked, prunable
      path=""; head=""; branch="HEAD"; locked="0"; prunable="0"
    }
    /^worktree /{ flush(); path=substr($0,10) }
    /^HEAD /{ head=substr($0,6) }
    /^branch /{ b=substr($0,8); sub(/^refs\/heads\//,"",b); branch=b }
    /^bare$/{ branch="BARE" }
    /^locked/{ locked="1" }
    /^prunable/{ prunable="1" }
    END{ flush() }
  '
}

# _wt_verdict <wt-path> <repo-path> <head-oid> <branch> <locked> <prunable> -> "PRUNE" |
# "REMOVE" | "KEEP: <perche'>". Il repo e' gia' NOTO (viene dalla riga del registro, non da un
# nome da risolvere), quindi non c'e' piu' bisogno di distinguere "trovato per nome" da "trovato
# per path" come nella versione precedente (_verdict vs _verdict_at): un'unica funzione basta.
_wt_verdict() {
  local wt="$1" repo="$2" oid="$3" branch="$4" locked="$5" prunable="$6" dirty wt_real pwd_real
  _wt_hard_exclude "$repo" "$wt" && { echo "KEEP: MirrorBuddy — Roberto ci lavora ora con un altro agente, mai toccare"; return 0; }
  # Confronto sul percorso FISICO (vedi _realpath): un worktree lockato dentro proprio QUESTO
  # checkout deve sopravvivere anche se $PWD e $wt arrivano da forme diverse dello stesso posto.
  wt_real="$(_realpath "$wt")" || wt_real="$wt"
  pwd_real="$(_realpath "$PWD")" || pwd_real="$PWD"
  case "$pwd_real/" in "$wt_real"/*) echo "KEEP: e' la cartella in cui stai lavorando adesso"; return 0 ;; esac
  [ "$prunable" = "1" ] && { echo "PRUNE"; return 0; }
  [ "$locked" = "1" ] && { echo "KEEP: lockato (un agente potrebbe averci ancora sessione aperta)"; return 0; }
  _owned_by_doing_card "$wt" && { echo "KEEP: appartiene a una card in corso"; return 0; }
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | grep -c . || true)"
  [ "${dirty:-0}" -gt 0 ] && { echo "KEEP: $dirty file non salvati"; return 0; }
  _branch_integrated "$repo" "$oid" "$branch" || { echo "KEEP: $branch ha lavoro non ancora integrato"; return 0; }
  echo "REMOVE"
}

# _scan_repo <repo-path> <repo-name> <apply> — un verdetto e una riga per OGNI worktree che
# `git -C <repo-path> worktree list` conosce, OVUNQUE viva: e' cosi' che un fratello come
# VirtualBPMFy27-hls2-scope o un nipote come copilot-worktrees/MirrorScopio/roberdan-... finisce
# nel referto senza che nessuna delle quattro cartelle convenzionali venga nominata. Appende ogni
# path VERO (risolto) al file $known, cosi' la fase B (caccia agli orfani) sa cosa NON e' orfano.
# Aggiorna n/rm/kept del chiamante per scope dinamico — vedi la nota in _sweep. $known e' lo
# stesso: dichiarata `local` in _sweep, mai in questo file di proposito (shellcheck non lo vede
# attraverso il confine dinamico, da qui i disable qui sotto — non e' un refuso).
# shellcheck disable=SC2154
_scan_repo() {
  local repo="$1" name="$2" apply="$3" repo_real path oid branch locked prunable path_real v
  repo_real="$(_realpath "$repo")" || return 0
  while IFS=$'\t' read -r path oid branch locked prunable; do
    [ -n "$path" ] || continue
    path_real="$(_realpath "$path")" || path_real="$path"   # prunable: la cartella non c'e' piu'
    [ "$path_real" = "$repo_real" ] && continue              # il checkout principale, non un candidato
    printf '%s\n' "$path_real" >> "$known"
    n=$((n+1))
    v="$(_wt_verdict "$path" "$repo" "$oid" "$branch" "$locked" "$prunable")"
    case "$v" in
      PRUNE)
        if [ "$apply" = "1" ]; then
          git -C "$repo" worktree prune -v >/dev/null 2>&1
          rm=$((rm+1)); printf '  pulita (prunable)  %s\n' "$path"
        else
          rm=$((rm+1)); printf '  da pulire (prunable) %s\n' "$path"
        fi ;;
      REMOVE)
        if [ "$apply" = "1" ]; then
          # MAI una `rm -rf` di riserva: se git rifiuta (lock preso nel frattempo, submodule
          # sporco...) e' un rifiuto da rispettare, non da scavalcare.
          if git -C "$repo" worktree remove "$path" 2>/dev/null; then
            rm=$((rm+1)); printf '  rimossa   %s\n' "$path"
            case "$branch" in HEAD|BARE) ;; *) git -C "$repo" branch -d "$branch" >/dev/null 2>&1 ;; esac
          else
            printf '  NON rimossa (git ha rifiutato) %s\n' "$path"
          fi
        else
          rm=$((rm+1)); printf '  da rimuovere %s\n' "$path"
        fi ;;
      *) kept=$((kept+1)); printf '  tenuta    %-58s %s\n' "$path" "$v" ;;
    esac
  done < <(_wt_registry "$repo")
}

# _orphan_check <path> <apply> — fase B: una cartella che SEMBRA un worktree per posizione (una
# delle quattro convenzioni) ma che ne' e' una ne' ne contiene: git non la conosce affatto (es.
# ~/GitHub/worktrees/MirrorHR/completion-20260906-f144e5a4/integration PRIMA che MirrorHR_Set
# fosse scoperto come proprietario — ora quella entry ha gia' il suo verdetto vero da _scan_repo
# e finisce nel file $known, quindi qui non ricompare). Una cartella che CONTIENE worktree veri
# (il contenitore completion-20260906-f144e5a4 stesso) non e' mai chiamata orfana: i suoi figli
# hanno gia' la loro riga, il contenitore e' solo un percorso, non un candidato.
# shellcheck disable=SC2154
_orphan_check() {
  local wt="$1" apply="$2" wt_real sub pwd_real
  wt_real="$(_realpath "$wt")" || return 0
  # PRIMA di tutto: gia' segnalato da _scan_repo (fase A)? Allora niente altro, MAI — precede
  # MirrorBuddy/cwd qui sotto apposta: un worktree vero dentro MirrorBuddy o quello in cui sei
  # ora ha GIA' la sua riga dalla fase A, e ripeterla qui la duplicherebbe (misurato: la card
  # gira nel proprio worktree, che la fase B rincontra per cartella).
  grep -qxF "$wt_real" "$known" 2>/dev/null && return 0        # e' un worktree vero: gia' segnalato
  grep -qF "$wt_real/" "$known" 2>/dev/null && return 0        # CONTIENE worktree veri: non e' orfana
  # _wt_verdict fa questi due controlli per ogni worktree VERO che passa da _scan_repo; una
  # cartella orfana (non ancora esclusa sopra) li salta del tutto se non li si ripete anche qui —
  # e MirrorBuddy tiene proprio cartelle VUOTE sotto .claude/worktrees/ mentre un agente ci
  # scrive dentro: senza questo controllo una `--yes` le rmdir'erebbe, contro la regola della card.
  case "$wt" in "$GH_HOME/MirrorBuddy/"*|"$WT_HOME/MirrorBuddy/"*)
    n=$((n+1)); kept=$((kept+1))
    printf '  tenuta    %-58s KEEP: MirrorBuddy — Roberto ci lavora ora con un altro agente, mai toccare\n' "$wt"
    return 0 ;;
  esac
  pwd_real="$(_realpath "$PWD")" || pwd_real="$PWD"
  case "$pwd_real/" in "$wt_real"/*)
    n=$((n+1)); kept=$((kept+1))
    printf '  tenuta    %-58s KEEP: e'"'"' la cartella in cui stai lavorando adesso\n' "$wt"
    return 0 ;;
  esac
  # Guardia di sicurezza: _discover_repos puo' comunque non trovare un repo (fuori da ~/GitHub,
  # nel registro ma con un path rotto, annidato piu' di un livello...). Se QUESTA cartella o un
  # suo figlio diretto ha un .git che git sa risolvere, non e' orfana — e' un repo/worktree
  # vero che la scansione non ha raggiunto, non "git non lo conosce affatto".
  if [ -e "$wt/.git" ] && git -C "$wt" rev-parse --git-common-dir >/dev/null 2>&1; then
    n=$((n+1)); kept=$((kept+1))
    printf '  tenuta    %-58s KEEP: repo/worktree registrato ma fuori dalla scansione (git lo conosce)\n' "$wt"
    return 0
  fi
  for sub in "$wt"/*/; do
    [ -d "$sub" ] || continue
    if [ -e "$sub/.git" ] && git -C "$sub" rev-parse --git-common-dir >/dev/null 2>&1; then
      n=$((n+1)); kept=$((kept+1))
      printf '  tenuta    %-58s KEEP: contiene un repo/worktree registrato fuori dalla scansione\n' "$wt"
      return 0
    fi
  done
  n=$((n+1))
  if [ -z "$(ls -A "$wt" 2>/dev/null)" ]; then
    if [ "$apply" = "1" ]; then
      rmdir "$wt" 2>/dev/null && { rm=$((rm+1)); printf '  rimossa (orfana)  %s\n' "$wt"; } \
        || printf '  NON rimossa (cartella orfana non vuota) %s\n' "$wt"
    else
      rm=$((rm+1)); printf '  da rimuovere (orfana) %s\n' "$wt"
    fi
  else
    kept=$((kept+1))
    printf '  tenuta    %-58s KEEP: cartella orfana (git non la conosce), non vuota — %s elementi\n' \
      "$wt" "$(ls -A "$wt" 2>/dev/null | wc -l | tr -d ' ')"
  fi
}

# _scan_orphans <apply> <only> — le stesse quattro cartelle convenzionali di prima, ma solo per
# trovare cartelle che _scan_repo non ha gia' spiegato (vedi _orphan_check).
_scan_orphans() {
  local apply="$1" only="$2" d name repo dir wt
  for d in "$WT_HOME"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "${d%/}")"
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    for wt in "$d"*/; do
      [ -d "$wt" ] || continue
      _orphan_check "${wt%/}" "$apply"
    done
  done
  while IFS=$'\t' read -r name repo; do
    [ -n "$repo" ] || continue
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    while IFS=$'\t' read -r _ dir; do   # 1o campo (l'etichetta della convenzione) non serve qui
      [ -n "$dir" ] || continue
      for wt in "$dir"/*/; do
        [ -d "$wt" ] || continue
        _orphan_check "${wt%/}" "$apply"
      done
    done < <(_location_dirs "$repo")
  done < <(_discover_repos)
}
