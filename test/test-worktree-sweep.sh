#!/usr/bin/env bash
# test/test-worktree-sweep.sh — lo spazzino rimuove SOLO cio' che non ha nulla da perdere.
#
# Misurato, non ipotetico: il 2026-09-13 c'erano 99 copie vive sotto ~/GitHub/worktrees, di 4
# repo, nessuna chiusa da chi l'aveva aperta. Uno spazzino che sbaglia in questa direzione
# cancella l'ultima copia di un lavoro, quindi meta' di questo file verifica che RIFIUTI.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="$ROOT/kanban/worktree.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

# Fotografia della cartella VERA delle copie di lavoro, presa PRIMA di dirottare HOME (scar
# 2026-09-13: una variabile sbagliata scrisse nel parco vero). `-d`: l'ELENCO delle copie, non
# il loro contenuto — senza, un file toccato da un'ALTRA sessione durante la corsa (misurato
# 2026-09-22) faceva fallire questo controllo a caso.
REAL_HOME="$HOME"
REAL_WT_BEFORE="$(ls -1d "$REAL_HOME/GitHub/worktrees"/*/ 2>/dev/null | sort)"
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
# Il vecchio controllo leggeva _sweep() da worktree.sh: _sweep vive in worktree-sweep.sh da
# quando questo file e' stato staccato per le 300 righe, quindi il grep non trovava mai niente
# e "passava" a vuoto. Punta ai file veri (_sweep in worktree-sweep.sh, _scan_extra_locations in
# worktree-locations.sh — card 260924-085105-3): entrambi avevano una `rm -rf "$wt"` di riserva
# quando `git worktree remove` rifiutava — tolta apposta perche' un rifiuto di git (lock,
# submodule sporco) va rispettato, non scavalcato. worktree.sh non e' toccato qui: la sua
# `_remove` e' condivisa con `kb finish` ed e' fuori dallo scope di questa card (escalation nel
# referto, non fix silenzioso).
SWEEP="$ROOT/kanban/worktree-sweep.sh"
LOCS="$ROOT/kanban/worktree-locations.sh"
grep -q -- 'rm -rf "\$wt"' "$SWEEP" "$LOCS" \
  && fail "una rm -rf di riserva e' tornata in worktree-sweep.sh o worktree-locations.sh" \
  || ok "nessuna rm -rf di riserva in worktree-sweep.sh/worktree-locations.sh"

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

# --- le altre tre convenzioni, i repo annidati in una cartella contenitore (WareHouse/
# ParkingLot sulla macchina reale), le cartelle orfane, i prunable, e MirrorBuddy sempre tenuto.
REPO3="$HOME/GitHub/demo3"; mkdir -p "$REPO3"
git -C "$REPO3" init -q -b main
echo one > "$REPO3/f"; git -C "$REPO3" add f; git -C "$REPO3" commit -qm one

mk3() { # mk3 <repo-dir> <loc-subdir> <name> — worktree su wt/<name>, ramo integrato in main
  local repo="$1" loc="$2" nm="$3"
  local wt="$repo/$loc/$nm"   # riga a parte: sotto `set -u`, `local a=1 b=$a` legge $a PRIMA
                              # che `local` lo definisca (bash espande gli argomenti prima).
  mkdir -p "$(dirname "$wt")"
  git -C "$repo" worktree add -q -b "wt/$nm" "$wt" main
}

mk3 "$REPO3" worktrees merged1          # convenzione (2) <repo>/worktrees
mk3 "$REPO3" .worktrees merged2         # convenzione (3) <repo>/.worktrees
mk3 "$REPO3" .claude/worktrees merged3  # convenzione (4) <repo>/.claude/worktrees
mk3 "$REPO3" worktrees dirty3
echo x > "$REPO3/worktrees/dirty3/nuovo"
mk3 "$REPO3" worktrees ahead3
echo y > "$REPO3/worktrees/ahead3/f"; git -C "$REPO3/worktrees/ahead3" commit -qam ahead3

# repo annidato dentro una cartella-contenitore (non un repo essa stessa)
mkdir -p "$HOME/GitHub/Contenitore"
NESTED="$HOME/GitHub/Contenitore/nested"; mkdir -p "$NESTED"
git -C "$NESTED" init -q -b main
echo one > "$NESTED/f"; git -C "$NESTED" add f; git -C "$NESTED" commit -qm one
mk3 "$NESTED" worktrees mergedN

# cartella orfana sotto la convenzione (1): git non la conosce affatto (l'esempio reale e'
# ~/GitHub/worktrees/MirrorHR/completion-20260906-f144e5a4 — il repo si chiama MirrorHR_Set ora)
mkdir -p "$RDA_WORKTREES/OrphanRepo/empty-orphan"
mkdir -p "$RDA_WORKTREES/OrphanRepo/full-orphan"; echo keep > "$RDA_WORKTREES/OrphanRepo/full-orphan/dato"

# MirrorBuddy: esclusione DURA, anche se il worktree sarebbe altrimenti rimovibile (pulito e
# integrato) — la regola HARD SAFETY della card, non un giudizio sul contenuto.
MB="$HOME/GitHub/MirrorBuddy"; mkdir -p "$MB"
git -C "$MB" init -q -b main
echo one > "$MB/f"; git -C "$MB" add f; git -C "$MB" commit -qm one
mk3 "$MB" worktrees should-survive

# registrazione "prunable": un worktree creato e poi tolto A MANO, senza dirlo a git
mk3 "$REPO3" worktrees toprune
rm -rf "$REPO3/worktrees/toprune"

out4="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"

[ -d "$REPO3/worktrees/merged1" ] && fail "convenzione <repo>/worktrees non rimossa" || ok "convenzione <repo>/worktrees rimossa se pulita e integrata"
[ -d "$REPO3/.worktrees/merged2" ] && fail "convenzione <repo>/.worktrees non rimossa" || ok "convenzione <repo>/.worktrees rimossa se pulita e integrata"
[ -d "$REPO3/.claude/worktrees/merged3" ] && fail "convenzione <repo>/.claude/worktrees non rimossa" || ok "convenzione <repo>/.claude/worktrees rimossa se pulita e integrata"
[ -d "$REPO3/worktrees/dirty3" ] && ok "convenzione <repo>/worktrees non tocca una copia sporca" || fail "RIMOSSA una copia sporca in <repo>/worktrees"
[ -d "$REPO3/worktrees/ahead3" ] && ok "convenzione <repo>/worktrees non tocca commit non integrati" || fail "RIMOSSA una copia non integrata in <repo>/worktrees"
[ -d "$NESTED/worktrees/mergedN" ] && fail "repo annidato in una cartella contenitore NON scoperto" || ok "repo annidato in una cartella contenitore (tipo WareHouse) scoperto e ripulito"
[ -d "$RDA_WORKTREES/OrphanRepo/empty-orphan" ] && fail "cartella orfana VUOTA non rimossa" || ok "cartella orfana vuota rimossa"
[ -d "$RDA_WORKTREES/OrphanRepo/full-orphan" ] && ok "cartella orfana con dentro qualcosa tenuta" || fail "RIMOSSA una cartella orfana non vuota"
[ -d "$MB/worktrees/should-survive" ] && ok "MirrorBuddy MAI toccato anche se il worktree sarebbe altrimenti rimovibile" || fail "RIMOSSO qualcosa dentro MirrorBuddy — regola di sicurezza violata"
case "$out4" in *"should-survive"*"MirrorBuddy"*) ok "dice PERCHE' tiene MirrorBuddy" ;; *) fail "non spiega perche' tiene MirrorBuddy" ;; esac
case "$out4" in *prunable*) ok "segnala le registrazioni prunable di git" ;; *) fail "non segnala le registrazioni prunable" ;; esac
[ "$(git -C "$REPO3" worktree list --porcelain | grep -c '^prunable')" -eq 0 ] \
  && ok "--yes pulisce il registro prunable (git worktree prune)" || fail "il registro prunable e' rimasto sporco dopo --yes"

# senza --yes il referto vede le stesse quattro convenzioni ma non tocca niente
mk3 "$REPO3" worktrees merged4
out5="$(cd "$TMP" && bash "$WT" sweep --all 2>&1)"
[ -d "$REPO3/worktrees/merged4" ] && ok "senza --yes il referto non rimuove nella convenzione (2)" || fail "ha rimosso senza --yes nella convenzione (2)"
# Card 260924-085105-3b: il referto non etichetta piu' la CONVENZIONE (il worktree si trova dal
# registro di git, non dalla cartella in cui vive), ma nomina sempre il PATH esatto trovato.
case "$out5" in *"$REPO3/worktrees/merged4"*) ok "il referto nomina il path esatto trovato in convenzione (2)" ;; *) fail "il referto non nomina il path trovato" ;; esac

# --- una cartella PIANA (senza .git suo, mai registrata da git) dentro <repo>/worktrees non e'
# un worktree — deve restare "orfana", mai confusa con lo stato del repo che la contiene.
mkdir -p "$REPO3/worktrees/plain-full"; echo dato > "$REPO3/worktrees/plain-full/f.txt"
mkdir -p "$REPO3/.worktrees/plain-empty"
out5b="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
[ -d "$REPO3/worktrees/plain-full" ] && ok "cartella piana con dati tenuta (non e' un worktree, solo una sottocartella del repo)" || fail "RIMOSSA una cartella piana con dati veri — letta come stato del repo, non suo"
case "$out5b" in *"plain-full"*"orfana"*) ok "dice PERCHE' tiene la cartella piana (orfana)" ;; *) fail "non chiama 'orfana' la cartella piana con dati" ;; esac
[ -d "$REPO3/.worktrees/plain-empty" ] && fail "cartella piana VUOTA non rimossa" || ok "cartella piana vuota rimossa (non ha niente da perdere)"

# --- un worktree LOCKATO non si tocca, anche pulito e integrato (§ No False Done).
LOCKED="$(mk locked)"
git -C "$REPO" worktree lock "$LOCKED"
out6="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
git -C "$REPO" worktree unlock "$LOCKED" >/dev/null 2>&1 || true
[ -d "$LOCKED" ] && ok "un worktree lockato sopravvive a --yes anche se pulito e integrato" || fail "RIMOSSO un worktree lockato — un agente poteva averci sessione aperta"
case "$out6" in *lockato*) ok "dice PERCHE' tiene un worktree lockato" ;; *) fail "non spiega perche' tiene un worktree lockato" ;; esac

# --- "merged" non basta: se la PR merged non e' l'HEAD locale, c'e' lavoro non ancora pushato
# dopo il merge. Ramo non discendenza diretta di main (simula uno squash-merge) -> passa da gh;
# un mock di gh risponde per nome di branch.
SQREPO="$HOME/GitHub/demo5"; mkdir -p "$SQREPO"
git -C "$SQREPO" init -q -b main
echo one > "$SQREPO/f"; git -C "$SQREPO" add f; git -C "$SQREPO" commit -qm one

git -C "$SQREPO" worktree add -q -b sq/matched "$RDA_WORKTREES/demo5/matched" main
echo m > "$RDA_WORKTREES/demo5/matched/f"; git -C "$RDA_WORKTREES/demo5/matched" commit -qam m
MATCHED_SHA="$(git -C "$RDA_WORKTREES/demo5/matched" rev-parse HEAD)"

git -C "$SQREPO" worktree add -q -b sq/mismatched "$RDA_WORKTREES/demo5/mismatched" main
echo n > "$RDA_WORKTREES/demo5/mismatched/f"; git -C "$RDA_WORKTREES/demo5/mismatched" commit -qam n
MERGED_SHA="$(git -C "$RDA_WORKTREES/demo5/mismatched" rev-parse HEAD)"   # cio' che gh dice merged
echo x > "$RDA_WORKTREES/demo5/mismatched/extra"; git -C "$RDA_WORKTREES/demo5/mismatched" add extra
git -C "$RDA_WORKTREES/demo5/mismatched" commit -qm "lavoro dopo il merge, mai pushato"

cat > "$TMP/bin/gh" <<EOF
#!/bin/sh
head=""
while [ \$# -gt 0 ]; do case "\$1" in --head) head="\$2"; shift 2 ;; *) shift ;; esac; done
case "\$head" in
  sq/matched)    printf '%s\n' "$MATCHED_SHA" ;;
  sq/mismatched) printf '%s\n' "$MERGED_SHA" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

out7="$(cd "$SQREPO" && bash "$WT" sweep --yes 2>&1)"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"   # ripristinato per igiene

[ -d "$RDA_WORKTREES/demo5/matched" ] && fail "non rimossa la copia il cui HEAD combacia con l'headRefOid della PR merged" || ok "rimossa: HEAD combacia con l'headRefOid della PR merged (gh, squash-merge)"
[ -d "$RDA_WORKTREES/demo5/mismatched" ] && ok "tenuta: HEAD ha un commit DOPO l'headRefOid della PR merged (mai pushato)" || fail "RIMOSSA una copia con lavoro dopo il merge mai pushato"
case "$out7" in *"non ancora integrato"*) ok "dice PERCHE' tiene la copia con lavoro dopo il merge" ;; *) fail "non spiega perche' tiene la copia con lavoro dopo il merge" ;; esac

# --- MirrorBuddy per IDENTITA' di repo, non solo per path: registrata sotto $WT_HOME (kb) deve
# restare esclusa quanto sotto MirrorBuddy/worktrees/.
mkdir -p "$RDA_WORKTREES/MirrorBuddy"
git -C "$MB" worktree add -q -b card/mb-by-id "$RDA_WORKTREES/MirrorBuddy/mb-by-id" main
(cd "$TMP" && bash "$WT" sweep --yes --all >/dev/null 2>&1)
[ -d "$RDA_WORKTREES/MirrorBuddy/mb-by-id" ] && ok "MirrorBuddy escluso anche registrato altrove, per identita' di repo (git-common-dir)" || fail "RIMOSSA una copia di MirrorBuddy registrata sotto \$WT_HOME — la regola di sicurezza va per PATH soltanto"

# --- HEAD staccata (`git worktree add --detach`): un ancestor-check sul nome letterale "HEAD"
# eseguito con "-C $repo" legge l'HEAD del checkout PRINCIPALE, non quello del worktree — una
# HEAD staccata con un commit proprio, mai integrato, risulterebbe sempre "integrata" per errore.
git -C "$REPO" worktree add --detach -q "$RDA_WORKTREES/demo/detached" main
echo d1 > "$RDA_WORKTREES/demo/detached/f"; git -C "$RDA_WORKTREES/demo/detached" commit -qam "mai integrato, HEAD staccata"
git -C "$REPO3" worktree add --detach -q "$REPO3/.claude/worktrees/detached2" main
echo d2 > "$REPO3/.claude/worktrees/detached2/f"; git -C "$REPO3/.claude/worktrees/detached2" commit -qam "mai integrato, HEAD staccata"

out9="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
[ -d "$RDA_WORKTREES/demo/detached" ] && ok "HEAD staccata con commit proprio tenuta in location (1)" || fail "RIMOSSA una HEAD staccata con lavoro non integrato — location (1)"
[ -d "$REPO3/.claude/worktrees/detached2" ] && ok "HEAD staccata con commit proprio tenuta in location (4)" || fail "RIMOSSA una HEAD staccata con lavoro non integrato — location (4)"
case "$out9" in *"HEAD ha lavoro non ancora integrato"*) ok "dice PERCHE' tiene una HEAD staccata" ;; *) fail "non spiega perche' tiene una HEAD staccata" ;; esac

# --- @thor F2 (card 260924-085105-3b): un worktree si trova dal REGISTRO di git, non da dove
# "dovrebbe" vivere per convenzione. Misurato sulla macchina reale: MirrorHR_Set/MirrorHR
# possiede 4 worktree due livelli sotto $WT_HOME/MirrorHR/ (prima: una riga "cartella orfana, N
# elementi"), un fratello di VirtualBPMFy27 vive a ~/GitHub/VirtualBPMFy27-hls2-scope (mai in
# nessuna delle 4 convenzioni), un worktree di ParkingLot/MirrorScopio vive dentro
# ~/GitHub/copilot-worktrees/MirrorScopio/... (nidificato sotto una cartella che non e' un repo).

# (a) nidificato DUE livelli sotto la convenzione (1): il contenitore non e' mai "orfano".
NESTREPO="$HOME/GitHub/nestrepo"; mkdir -p "$NESTREPO"
git -C "$NESTREPO" init -q -b main
echo one > "$NESTREPO/f"; git -C "$NESTREPO" add f; git -C "$NESTREPO" commit -qm one
git -C "$NESTREPO" worktree add -q -b nest/merged "$RDA_WORKTREES/nestrepo/contenitore/merged" main
git -C "$NESTREPO" worktree add -q -b nest/unmerged "$RDA_WORKTREES/nestrepo/contenitore/unmerged" main
echo z > "$RDA_WORKTREES/nestrepo/contenitore/unmerged/f"; git -C "$RDA_WORKTREES/nestrepo/contenitore/unmerged" commit -qam z

# (b) sotto una cartella-stile-copilot-worktrees, nidificato due livelli, il repo altrove.
COPREPO="$HOME/GitHub/coprepo"; mkdir -p "$COPREPO"
git -C "$COPREPO" init -q -b main
echo one > "$COPREPO/f"; git -C "$COPREPO" add f; git -C "$COPREPO" commit -qm one
git -C "$COPREPO" worktree add -q -b cop/merged "$HOME/GitHub/copilot-worktrees/coprepo/session1" main

# (c) fratello di primo livello, mai dentro nessuna delle quattro convenzioni.
SIBREPO="$HOME/GitHub/sibrepo"; mkdir -p "$SIBREPO"
git -C "$SIBREPO" init -q -b main
echo one > "$SIBREPO/f"; git -C "$SIBREPO" add f; git -C "$SIBREPO" commit -qm one
git -C "$SIBREPO" worktree add -q -b sib/unmerged "$HOME/GitHub/sibrepo-extra-scope" main
echo z > "$HOME/GitHub/sibrepo-extra-scope/f"; git -C "$HOME/GitHub/sibrepo-extra-scope" commit -qam z

out10="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"

[ -d "$RDA_WORKTREES/nestrepo/contenitore/merged" ] && fail "worktree nidificato 2 livelli sotto WT_HOME non rimosso" || ok "worktree nidificato 2 livelli sotto WT_HOME (pulito e integrato) rimosso dal registro di git"
[ -d "$RDA_WORKTREES/nestrepo/contenitore/unmerged" ] && ok "worktree nidificato 2 livelli con lavoro non integrato tenuto, con la sua riga propria" || fail "RIMOSSO un worktree nidificato con lavoro non integrato"
# Match sul path esatto seguito da spazio/a-capo (mai da uno slash, che introduce un figlio
# vero): "orfana" compare gia' altrove nell'output (full-orphan, ancora presente), quindi un
# semplice *contenitore*orfan* darebbe un falso "fallito" a distanza.
CONTDIR="$RDA_WORKTREES/nestrepo/contenitore"
case "$out10" in
  *"$CONTDIR "*|*"$CONTDIR"$'\n'*) fail "il CONTENITORE (che ha worktree veri dentro) e' comparso come riga propria" ;;
  *) ok "il contenitore con worktree veri dentro non compare mai come riga propria (mai orfano)" ;;
esac
[ -d "$HOME/GitHub/copilot-worktrees/coprepo/session1" ] && fail "worktree in stile copilot-worktrees (nidificato, repo altrove) non rimosso" || ok "worktree in stile copilot-worktrees trovato e rimosso via registro di git, non via scansione di cartelle"
[ -d "$HOME/GitHub/sibrepo-extra-scope" ] && ok "worktree fratello di primo livello (mai in nessuna delle 4 convenzioni) tenuto: lavoro non integrato" || fail "RIMOSSO un worktree fratello con lavoro non integrato"
case "$out10" in *"$HOME/GitHub/sibrepo-extra-scope"*) ok "il worktree fratello compare nel referto (trovato dal registro, non da una cartella nominata)" ;; *) fail "il worktree fratello non compare nel referto" ;; esac
n_occ="$(grep -oF "$HOME/GitHub/sibrepo-extra-scope" <<<"$out10" | wc -l | tr -d ' ')"
[ "$n_occ" -eq 1 ] && ok "il worktree fratello compare UNA sola volta (il suo .git-file non lo fa contare due volte come repo a se')" || fail "il worktree fratello compare $n_occ volte nel referto — doppio conteggio"

REAL_WT_AFTER="$(ls -1d "$REAL_HOME/GitHub/worktrees"/*/ 2>/dev/null | sort)"
[ "$REAL_WT_BEFORE" = "$REAL_WT_AFTER" ] && ok "la suite non ha toccato il parco vero delle copie di lavoro" \
  || fail "la suite ha creato o tolto qualcosa in $REAL_HOME/GitHub/worktrees"

if [ "$FAILS" -eq 0 ]; then echo "test-worktree-sweep: ✅ ALL GREEN"; else echo "test-worktree-sweep: ❌ $FAILS FAIL"; exit 1; fi
