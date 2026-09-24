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

# Fotografia della cartella VERA delle copie di lavoro, presa PRIMA di dirottare HOME. Una
# suite gira sulla macchina di Roberto: se sbaglia una variabile scrive nel suo parco vero, e
# lo scopre lui guardando l'editor. E' successo il 2026-09-13 — una riga rimasta indietro
# creava "$ROOT/../fake", cioe' ~/GitHub/worktrees/roberdan-os/fake, a ogni esecuzione.
REAL_HOME="$HOME"
# `-d`: l'ELENCO DELLE COPIE, non il loro contenuto. Senza, `ls -1 .../*/` elenca
# i FILE dentro ogni copia di ogni progetto, e questo controllo — che dichiara di
# accorgersi se la suite "ha creato o tolto" una copia — falliva perche' un'altra
# sessione, su un altro progetto, aveva salvato un file mentre la suite girava.
# Misurato il 2026-09-22: VirtualBPMFy27/glance-kpis-live/README.md, toccato da
# chi ci stava lavorando in quel momento. Un controllo che accusa il lavoro di
# qualcun altro e' un controllo che si impara a ignorare, e in una macchina dove
# girano piu' sessioni insieme falliva a caso — cioe' nel modo piu' costoso.
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

# --- le altre tre convenzioni (<repo>/worktrees, <repo>/.worktrees, <repo>/.claude/worktrees),
# i repo annidati in una cartella contenitore (tipo WareHouse/ParkingLot sulla macchina reale),
# le cartelle orfane, i registri prunable di git, e MirrorBuddy che va SEMPRE tenuto anche se
# altrimenti rimovibile — card 260924-085105-3: prima di questa sezione `kb wt` guardava solo
# $RDA_WORKTREES/<repo>/*, cioe' la convenzione (1). Rosso prima di questo commit, verde dopo.
REPO3="$HOME/GitHub/demo3"; mkdir -p "$REPO3"
git -C "$REPO3" init -q -b main
echo one > "$REPO3/f"; git -C "$REPO3" add f; git -C "$REPO3" commit -qm one

mk3() { # mk3 <repo-dir> <loc-subdir> <name> — worktree su wt/<name>, ramo integrato in main
  local repo="$1" loc="$2" nm="$3"
  local wt="$repo/$loc/$nm"   # riga a parte: sotto `set -u` un `local a=1 b=$a` legge $a
                               # PRIMA che `local` lo definisca — bash espande gli argomenti
                               # prima di eseguire il builtin, non riga per riga.
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

# repo annidato dentro una cartella-contenitore (WareHouse, ParkingLot, MirrorHR_Set sulla
# macchina reale non sono repo: sono cartelle CHE CONTENGONO repo)
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
case "$out5" in *"repo/worktrees"*) ok "il referto etichetta la convenzione trovata" ;; *) fail "il referto non etichetta la convenzione" ;; esac

# --- una cartella PIANA (senza .git suo) dentro <repo>/worktrees non e' un worktree: e'
# semplicemente dentro l'albero di lavoro del repo principale. `git -C <cartella> rev-parse
# --git-dir` risale ai genitori e trova comunque il .git del repo — senza _is_worktree_root il
# verdetto sarebbe quello del REPO (pulito, su main -> REMOVE), non quello della cartella, e una
# cartella con dati veri (mai versionati) finirebbe segnalata rimovibile per errore.
mkdir -p "$REPO3/worktrees/plain-full"; echo dato > "$REPO3/worktrees/plain-full/f.txt"
mkdir -p "$REPO3/.worktrees/plain-empty"
out5b="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
[ -d "$REPO3/worktrees/plain-full" ] && ok "cartella piana con dati tenuta (non e' un worktree, solo una sottocartella del repo)" || fail "RIMOSSA una cartella piana con dati veri — letta come stato del repo, non suo"
case "$out5b" in *"plain-full"*"orfana"*) ok "dice PERCHE' tiene la cartella piana (orfana)" ;; *) fail "non chiama 'orfana' la cartella piana con dati" ;; esac
[ -d "$REPO3/.worktrees/plain-empty" ] && fail "cartella piana VUOTA non rimossa" || ok "cartella piana vuota rimossa (non ha niente da perdere)"

# --- un worktree LOCKATO non si tocca, anche se pulito e integrato — Claude Code tiene il
# lock mentre un agente ci gira dentro (docs/en/worktrees), e "0 file modificati" non e' prova
# che l'agente abbia finito (rules/best-practices.md § No False Done).
LOCKED="$(mk locked)"
git -C "$REPO" worktree lock "$LOCKED"
out6="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
git -C "$REPO" worktree unlock "$LOCKED" >/dev/null 2>&1 || true
[ -d "$LOCKED" ] && ok "un worktree lockato sopravvive a --yes anche se pulito e integrato" || fail "RIMOSSO un worktree lockato — un agente poteva averci sessione aperta"
case "$out6" in *lockato*) ok "dice PERCHE' tiene un worktree lockato" ;; *) fail "non spiega perche' tiene un worktree lockato" ;; esac

# --- "merged" non basta: se la PR merged non e' l'HEAD locale, c'e' lavoro non ancora pushato
# dopo il merge — la card lo chiama esplicitamente "no unpushed commits". Il ramo non e'
# discendenza diretta di main (per simulare uno squash-merge, che riscrive i commit), quindi
# _branch_integrated deve passare da gh; un mock di gh risponde per nome di branch.
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

# --- MirrorBuddy per IDENTITA' di repo, non solo per path: una copia registrata sotto la
# convenzione (1) ($WT_HOME/MirrorBuddy/<card>, quella che usa kb) deve restare esclusa quanto
# quelle sotto MirrorBuddy/worktrees/ — il git-common-dir la ricollega al repo comunque.
mkdir -p "$RDA_WORKTREES/MirrorBuddy"
git -C "$MB" worktree add -q -b card/mb-by-id "$RDA_WORKTREES/MirrorBuddy/mb-by-id" main
(cd "$TMP" && bash "$WT" sweep --yes --all >/dev/null 2>&1)
[ -d "$RDA_WORKTREES/MirrorBuddy/mb-by-id" ] && ok "MirrorBuddy escluso anche registrato altrove, per identita' di repo (git-common-dir)" || fail "RIMOSSA una copia di MirrorBuddy registrata sotto \$WT_HOME — la regola di sicurezza va per PATH soltanto"

# --- HEAD staccata (`git worktree add --detach`): `rev-parse --abbrev-ref HEAD` restituisce la
# stringa letterale "HEAD", e un ancestor-check fatto con "-C $repo" su quella stringa legge
# l'HEAD del checkout PRINCIPALE (di solito main), non quello del worktree — un worktree
# staccato con un commit proprio, mai integrato, risulterebbe sempre "integrato" per errore.
# Una copia in ciascun posto che ha il proprio confronto di ramo: location (1) via _verdict,
# location (4) via _verdict_at.
git -C "$REPO" worktree add --detach -q "$RDA_WORKTREES/demo/detached" main
echo d1 > "$RDA_WORKTREES/demo/detached/f"; git -C "$RDA_WORKTREES/demo/detached" commit -qam "mai integrato, HEAD staccata"
git -C "$REPO3" worktree add --detach -q "$REPO3/.claude/worktrees/detached2" main
echo d2 > "$REPO3/.claude/worktrees/detached2/f"; git -C "$REPO3/.claude/worktrees/detached2" commit -qam "mai integrato, HEAD staccata"

out9="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"
[ -d "$RDA_WORKTREES/demo/detached" ] && ok "HEAD staccata con commit proprio tenuta in location (1)" || fail "RIMOSSA una HEAD staccata con lavoro non integrato — location (1)"
[ -d "$REPO3/.claude/worktrees/detached2" ] && ok "HEAD staccata con commit proprio tenuta in location (4)" || fail "RIMOSSA una HEAD staccata con lavoro non integrato — location (4)"
case "$out9" in *"HEAD ha lavoro non ancora integrato"*) ok "dice PERCHE' tiene una HEAD staccata" ;; *) fail "non spiega perche' tiene una HEAD staccata" ;; esac

REAL_WT_AFTER="$(ls -1d "$REAL_HOME/GitHub/worktrees"/*/ 2>/dev/null | sort)"
[ "$REAL_WT_BEFORE" = "$REAL_WT_AFTER" ] && ok "la suite non ha toccato il parco vero delle copie di lavoro" \
  || fail "la suite ha creato o tolto qualcosa in $REAL_HOME/GitHub/worktrees"

if [ "$FAILS" -eq 0 ]; then echo "test-worktree-sweep: ✅ ALL GREEN"; else echo "test-worktree-sweep: ❌ $FAILS FAIL"; exit 1; fi
