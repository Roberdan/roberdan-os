#!/usr/bin/env bash
# test/test-worktree-registry.sh — @thor F2 (card 260924-085105-3, seguito -3b): un worktree si
# trova dal REGISTRO di git (`git worktree list --porcelain`), non da dove "dovrebbe" vivere per
# convenzione. Misurato sulla macchina reale: MirrorHR_Set/MirrorHR possiede 4 worktree due
# livelli sotto $WT_HOME/MirrorHR/ (prima: una riga sola "cartella orfana, N elementi"), un
# fratello di VirtualBPMFy27 vive a ~/GitHub/VirtualBPMFy27-hls2-scope (mai in nessuna delle 4
# convenzioni), un worktree di ParkingLot/MirrorScopio vive dentro
# ~/GitHub/copilot-worktrees/MirrorScopio/... (nidificato sotto una cartella che non e' un repo).
# File separato da test-worktree-sweep.sh: quello era gia' al limite delle 300 righe.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="$ROOT/kanban/worktree.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

# Stessa fotografia di sicurezza di test-worktree-sweep.sh: vedi li' il perche'.
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
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"

mkrepo() { # mkrepo <path> — repo minimo, un commit su main
  mkdir -p "$1"; git -C "$1" init -q -b main
  echo one > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm one
}

# (a) nidificato DUE livelli sotto la convenzione (1): il contenitore non e' mai "orfano".
NESTREPO="$HOME/GitHub/nestrepo"; mkrepo "$NESTREPO"
git -C "$NESTREPO" worktree add -q -b nest/merged "$RDA_WORKTREES/nestrepo/contenitore/merged" main
git -C "$NESTREPO" worktree add -q -b nest/unmerged "$RDA_WORKTREES/nestrepo/contenitore/unmerged" main
echo z > "$RDA_WORKTREES/nestrepo/contenitore/unmerged/f"; git -C "$RDA_WORKTREES/nestrepo/contenitore/unmerged" commit -qam z

# (b) sotto una cartella-stile-copilot-worktrees, nidificato due livelli, il repo altrove.
COPREPO="$HOME/GitHub/coprepo"; mkrepo "$COPREPO"
git -C "$COPREPO" worktree add -q -b cop/merged "$HOME/GitHub/copilot-worktrees/coprepo/session1" main

# (c) fratello di primo livello, mai dentro nessuna delle quattro convenzioni.
SIBREPO="$HOME/GitHub/sibrepo"; mkrepo "$SIBREPO"
git -C "$SIBREPO" worktree add -q -b sib/unmerged "$HOME/GitHub/sibrepo-extra-scope" main
echo z > "$HOME/GitHub/sibrepo-extra-scope/f"; git -C "$HOME/GitHub/sibrepo-extra-scope" commit -qam z

# (d) un repo del REGISTRO (kanban-registry), fuori da ~/GitHub del tutto — _repo_path lo trova
# gia' da prima di questa card; _discover_repos deve trovarlo anche lui, non solo per convenzione.
REGREPO="$TMP/altrove/regrepo"; mkrepo "$REGREPO"
echo "$REGREPO" >> "$RDA_KANBAN_REGISTRY"
git -C "$REGREPO" worktree add -q -b reg/merged "$RDA_WORKTREES/regrepo/x" main

# (e) un worktree il cui repo NON e' scopribile affatto (fuori da ~/GitHub, non nel registro): la
# cartella che lo contiene non deve mai diventare "orfana" solo perche' la scansione non conosce
# il proprietario — git lo conosce, e questo basta per non toccarla.
GHOSTREPO="$TMP/introvabile/ghostrepo"; mkrepo "$GHOSTREPO"
git -C "$GHOSTREPO" worktree add -q -b ghost/y "$RDA_WORKTREES/ghost/cont/y" main

# (f) simlink verso un repo annidato in un contenitore: deve comparire UNA sola volta, non due
# (una per il simlink, una per il percorso vero) — la deduplica e' per path FISICO.
mkdir -p "$HOME/GitHub/Contenitore2"
NESTED2="$HOME/GitHub/Contenitore2/nested2repo"; mkrepo "$NESTED2"
ln -s "$NESTED2" "$HOME/GitHub/linkrepo"
git -C "$NESTED2" worktree add -q -b link/unmerged "$RDA_WORKTREES/nested2repo/y" main
echo z > "$RDA_WORKTREES/nested2repo/y/f"; git -C "$RDA_WORKTREES/nested2repo/y" commit -qam z

# (g) MirrorBuddy: la fase B (caccia agli orfani) deve escludere MirrorBuddy quanto _wt_verdict
# gia' fa per la fase A — Claude Code tiene cartelle VUOTE sotto .claude/worktrees/ mentre un
# agente ci scrive dentro, e una `--yes` non deve mai poterle `rmdir`.
MB="$HOME/GitHub/MirrorBuddy"; mkrepo "$MB"
mkdir -p "$MB/.claude/worktrees/vuota" "$RDA_WORKTREES/MirrorBuddy/vuota"

out="$(cd "$TMP" && bash "$WT" sweep --yes --all 2>&1)"

[ -d "$RDA_WORKTREES/nestrepo/contenitore/merged" ] && fail "worktree nidificato 2 livelli sotto WT_HOME non rimosso" || ok "worktree nidificato 2 livelli sotto WT_HOME (pulito e integrato) rimosso dal registro di git"
[ -d "$RDA_WORKTREES/nestrepo/contenitore/unmerged" ] && ok "worktree nidificato 2 livelli con lavoro non integrato tenuto, con la sua riga propria" || fail "RIMOSSO un worktree nidificato con lavoro non integrato"
# Match sul path esatto seguito da spazio/a-capo (mai da uno slash, che introduce un figlio
# vero): "orfana" compare in output per altre ragioni, un *contenitore*orfan* darebbe un falso
# "fallito" a distanza.
CONTDIR="$RDA_WORKTREES/nestrepo/contenitore"
case "$out" in
  *"$CONTDIR "*|*"$CONTDIR"$'\n'*) fail "il CONTENITORE (che ha worktree veri dentro) e' comparso come riga propria" ;;
  *) ok "il contenitore con worktree veri dentro non compare mai come riga propria (mai orfano)" ;;
esac
[ -d "$HOME/GitHub/copilot-worktrees/coprepo/session1" ] && fail "worktree stile copilot-worktrees (nidificato, repo altrove) non rimosso" || ok "worktree stile copilot-worktrees trovato e rimosso via registro di git"
[ -d "$HOME/GitHub/sibrepo-extra-scope" ] && ok "worktree fratello di primo livello tenuto: lavoro non integrato" || fail "RIMOSSO un worktree fratello con lavoro non integrato"
n_sib="$(grep -oF "$HOME/GitHub/sibrepo-extra-scope" <<<"$out" | wc -l | tr -d ' ')"
[ "$n_sib" -eq 1 ] && ok "il worktree fratello compare UNA sola volta (niente doppio conteggio via .git-file)" || fail "il worktree fratello compare $n_sib volte — doppio conteggio"

[ -d "$RDA_WORKTREES/regrepo/x" ] && fail "un repo del kanban-registry (fuori da ~/GitHub) non e' stato scoperto — la sua copia pulita e integrata non e' stata rimossa" \
  || ok "repo del kanban-registry scoperto e la sua copia pulita/integrata rimossa"

CONT2="$RDA_WORKTREES/ghost/cont"
# riga per riga (grep, non un case-glob su tutto $out): "orfana" compare in output per altre
# ragioni (es. il full-orphan piu' sotto), e un case-glob *A*B* combacia anche se B sta su una
# riga diversa e successiva — falso "fallito" a distanza, misurato in questa stessa card.
cont2_line="$(grep -F "$CONT2 " <<<"$out" | head -1)"
case "$cont2_line" in
  *orfan*) fail "la cartella che contiene un worktree di un repo introvabile e' stata chiamata orfana" ;;
  *) ok "la cartella che contiene un worktree di un repo introvabile NON e' orfana (git lo conosce comunque)" ;;
esac
[ -d "$RDA_WORKTREES/ghost/cont/y" ] && ok "il worktree di un repo introvabile non e' stato toccato" || fail "RIMOSSO un worktree il cui repo non era scopribile — mai dovrebbe succedere senza verdetto esplicito"

n_link="$(grep -oF "$RDA_WORKTREES/nested2repo/y" <<<"$out" | wc -l | tr -d ' ')"
[ "$n_link" -eq 1 ] && ok "repo raggiunto anche via symlink: il suo worktree compare UNA sola volta" || fail "il worktree del repo simlinkato compare $n_link volte — simlink non deduplicato"

[ -d "$MB/.claude/worktrees/vuota" ] && ok "cartella vuota dentro MirrorBuddy/.claude/worktrees NON rmdir'ata" || fail "RIMOSSA una cartella vuota dentro MirrorBuddy — regola di sicurezza violata dalla fase B"
[ -d "$RDA_WORKTREES/MirrorBuddy/vuota" ] && ok "cartella vuota dentro \$WT_HOME/MirrorBuddy NON rmdir'ata" || fail "RIMOSSA una cartella vuota sotto \$WT_HOME/MirrorBuddy — regola di sicurezza violata dalla fase B"

REAL_WT_AFTER="$(ls -1d "$REAL_HOME/GitHub/worktrees"/*/ 2>/dev/null | sort)"
[ "$REAL_WT_BEFORE" = "$REAL_WT_AFTER" ] && ok "la suite non ha toccato il parco vero delle copie di lavoro" \
  || fail "la suite ha creato o tolto qualcosa in $REAL_HOME/GitHub/worktrees"

if [ "$FAILS" -eq 0 ]; then echo "test-worktree-registry: ✅ ALL GREEN"; else echo "test-worktree-registry: ❌ $FAILS FAIL"; exit 1; fi
