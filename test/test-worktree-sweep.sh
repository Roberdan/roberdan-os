#!/usr/bin/env bash
# test/test-worktree-sweep.sh — lo spazzino rimuove SOLO cio' che non ha nulla da perdere.
#
# Il difetto che questo test chiude e' misurato, non ipotetico: il 2026-09-13 c'erano 99 copie
# di lavoro vive sotto ~/GitHub/worktrees, di 4 repo diversi, nessuna chiusa da chi l'aveva
# aperta. Uno spazzino che sbaglia in questa direzione cancella l'ultima copia di un lavoro,
# quindi meta' di questo file verifica che RIFIUTI, non che rimuova.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="$ROOT/kanban/worktree.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/GitHub"
export RDA_WORKTREES="$HOME/GitHub/worktrees"
export RDA_HOME="$TMP/rdahome"
export RDA_KANBAN_REGISTRY="$RDA_HOME/kanban-registry"; mkdir -p "$RDA_HOME"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config -f "$GIT_CONFIG_GLOBAL" user.email t@t; git config -f "$GIT_CONFIG_GLOBAL" user.name t
export PATH="$TMP/bin:$PATH"; mkdir -p "$TMP/bin"
# gh assente di proposito: lo spazzino deve funzionare (in modo conservativo) anche senza.
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"

REPO="$HOME/GitHub/demo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
echo one > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm one

mk() { # mk <card-id> — una copia di lavoro nuova sul branch card/<id>
  git -C "$REPO" worktree add -q -b "card/$1" "$RDA_WORKTREES/demo/$1" main
  printf '%s' "$RDA_WORKTREES/demo/$1"
}

CLEAN="$(mk clean)"                       # pulita e allineata a main -> rimovibile
DIRTY="$(mk dirty)"; echo x > "$DIRTY/nuovo"
AHEAD="$(mk ahead)"; echo y > "$AHEAD/f"; git -C "$AHEAD" commit -qam ahead
CARD="$(mk carded)"
UNTRACKED_ONLY="$(mk untracked)"; echo z > "$UNTRACKED_ONLY/scratch"

# una card in doing che rivendica $CARD: e' il posto dove qualcuno sta lavorando ADESSO
mkdir -p "$ROOT/../fake" 2>/dev/null || true
BOARD="$TMP/board"; mkdir -p "$BOARD/doing"
printf -- '---\nrepo: demo\nworktree: %s\n---\n' "$CARD" > "$BOARD/doing/carded.md"
export RDA_KANBAN="$BOARD"

out="$(cd "$TMP" && bash "$WT" sweep --yes 2>&1)"

[ -d "$CLEAN" ] && fail "la copia pulita e integrata NON e' stata rimossa" || ok "rimossa la copia pulita e integrata"
[ -d "$DIRTY" ] && ok "intatta la copia con modifiche non salvate" || fail "RIMOSSA una copia con modifiche non salvate"
[ -d "$AHEAD" ] && ok "intatta la copia con commit non integrati" || fail "RIMOSSA una copia con commit non integrati"
[ -d "$CARD" ]  && ok "intatta la copia di una card in corso" || fail "RIMOSSA la copia di una card in corso"
[ -d "$UNTRACKED_ONLY" ] && ok "intatta la copia con soli file non tracciati" || fail "RIMOSSA una copia con file non tracciati (dati mai versionati, unica copia)"
[ -d "$REPO/.git" ] && ok "il checkout principale non e' stato toccato" || fail "TOCCATO il checkout principale"

case "$out" in *"$DIRTY"*) ok "dice PERCHE' ha tenuto la copia sporca" ;; *) fail "non spiega perche' ha tenuto la copia sporca" ;; esac
grep -q -- "--force\|-D \|rm -rf \"\$wt\"" <<<"$(sed -n '/_sweep()/,/^}/p' "$WT")" \
  && fail "lo spazzino contiene un percorso forzato" || ok "nessun percorso forzato nello sweep"

# senza --yes non tocca niente: uno spazzino che cancella prima di essere guardato
# e' esattamente il difetto che stiamo chiudendo.
CLEAN2="$(mk clean2)"
(cd "$TMP" && bash "$WT" sweep >/dev/null 2>&1)
[ -d "$CLEAN2" ] && ok "senza --yes non rimuove niente (solo referto)" || fail "ha rimosso senza --yes"

# la cartella in cui stai lavorando adesso non si tocca, nemmeno se e' pulita
CWDWT="$(mk cwdwt)"
(cd "$CWDWT" && bash "$WT" sweep --yes >/dev/null 2>&1)
[ -d "$CWDWT" ] && ok "non rimuove la copia in cui sei dentro" || fail "ha rimosso la copia in cui era dentro"

# --- ambito: dentro un progetto si guarda SOLO quel progetto ------------------------------
REPO2="$HOME/GitHub/altro"; mkdir -p "$REPO2"
git -C "$REPO2" init -q -b main; echo a > "$REPO2/f"; git -C "$REPO2" add f; git -C "$REPO2" commit -qm a
git -C "$REPO2" worktree add -q -b card/x "$RDA_WORKTREES/altro/x" main
CLEAN3="$(mk clean3)"
out2="$(cd "$REPO2" && bash "$WT" sweep 2>&1)"
case "$out2" in *"/demo/"*) fail "da dentro 'altro' ha guardato anche demo" ;; *) ok "da dentro un progetto guarda solo quel progetto" ;; esac
case "$out2" in *"/altro/"*) ok "da dentro un progetto guarda le SUE copie" ;; *) fail "da dentro 'altro' non ha guardato nemmeno le sue" ;; esac
out3="$(cd "$REPO2" && bash "$WT" sweep --all 2>&1)"
case "$out3" in *"/demo/"*) ok "--all guarda tutto anche da dentro un progetto" ;; *) fail "--all non ha guardato gli altri repo" ;; esac

# --- pulizia A MONTE: autosweep toglie da solo cio' che e' stato integrato ------------------
rm -f "$RDA_HOME"/autosweep-*
(cd "$REPO" && bash "$WT" autosweep >/dev/null 2>&1)
[ -d "$CLEAN3" ] && fail "autosweep non ha tolto la copia integrata" || ok "autosweep toglie da solo la copia integrata"
[ -d "$DIRTY" ] && ok "autosweep non tocca una copia con lavoro dentro" || fail "autosweep ha tolto una copia con lavoro dentro"
CLEAN4="$(mk clean4)"
(cd "$REPO" && bash "$WT" autosweep >/dev/null 2>&1)
[ -d "$CLEAN4" ] && ok "autosweep non rigira prima del tempo (un giro ogni 20 minuti)" || fail "autosweep ha rigirato subito: a ogni turno costerebbe"
rm -f "$RDA_HOME"/autosweep-*
RDA_NO_AUTOSWEEP=1 bash -c "cd '$REPO' && bash '$WT' autosweep >/dev/null 2>&1"
[ -d "$CLEAN4" ] && ok "RDA_NO_AUTOSWEEP=1 lo spegne davvero" || fail "ha pulito anche con RDA_NO_AUTOSWEEP=1"

if [ "$FAILS" -eq 0 ]; then echo "test-worktree-sweep: ✅ ALL GREEN"; else echo "test-worktree-sweep: ❌ $FAILS FAIL"; exit 1; fi
