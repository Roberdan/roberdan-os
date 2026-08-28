#!/usr/bin/env bash
# goal-gate.sh — Stop hook. L'UNICO hook di questo repo che BLOCCA.
#
# Perche' esiste (misurato, non ipotizzato — sessione VirtualBPM 31 lug -> 2 ago):
# 46,5 ore di sessione, 4,4 ore di lavoro vero. Il 90% e' stato silenzio. E l'agente non era
# bloccato da un gate: prima di ogni pausa aveva scritto da solo cosa avrebbe fatto dopo.
#   "Non mi serve niente da te. Quando la CI passa: merge, @thor, e vado sulla #2."  -> 3h 00m
#   "Rilancio @thor appena la CI passa. La #2 parte subito dopo."                    -> 7h 20m
#   "Non aspetto niente da te."                                                      -> 14h 36m
# Ogni pausa si e' chiusa perche' Roberto ha scritto "vai". Un turno finisce quando l'agente
# SCRIVE: "poi faccio la #2" non e' un piano che il sistema tiene, e' l'ultima frase prima del
# silenzio. Gli altri due hook su Stop guardano il repo (file non committati, PR aperte,
# worktree orfani) e dichiarano entrambi di non bloccare mai. Nessuno guardava la LAVAGNA,
# che e' l'unico posto dove il lavoro e' scritto.
#
# Contratto: exit 2 + motivo su stderr = Claude Code NON chiude il turno e rimanda il motivo
# all'agente. Exit 0 = il turno si chiude. Il meccanismo e' lo stesso che il comando integrato
# /goal installa a mano per una sessione sola; qui e' il default e la condizione non e' una
# frase in prosa ma la coda che Roberto ha gia' autorizzato.
#
# TERMINALE (esce 0 e lascia chiudere): coda finita, oppure uno dei freni qui sotto.
# I freni sono il punto: un hook che blocca senza uscite e' peggio di uno che non blocca mai.
set -u

exit_pass() { exit 0; }
GATE_HOME="${RDA_HOME:-$HOME/.roberdan-os}"

# --- FRENO 0: interruttore. Deve esistere e deve essere ovvio. -------------------------------
[ "${RDA_NO_GOAL_GATE:-0}" = "1" ] && exit_pass
[ -e "$GATE_HOME/goal-gate.off" ] && exit_pass

payload="$(cat 2>/dev/null || true)"
session="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$session" ] || session="nosession"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit_pass
[ -n "$repo_root" ] || exit_pass

KBSH="$repo_root/kanban/kb.sh"
[ -x "$KBSH" ] || KBSH="$HOME/GitHub/roberdan-os/kanban/kb.sh"
[ -x "$KBSH" ] || exit_pass

# Quante card restano nella coda che Roberto ha autorizzato. La conta la fa kb, non questo file.
restanti="$(cd "$repo_root" && "$KBSH" queue --restanti 2>/dev/null | tr -cd '0-9')"
[ -n "$restanti" ] || exit_pass
[ "$restanti" -gt 0 ] || exit_pass          # <-- CONDIZIONE TERMINALE: lista finita, si chiude.

# --- stato per sessione: quante volte ho gia' bloccato, e a che punto era la coda ------------
# Sovrascrivibile perche' altrimenti il test non e' ermetico: con lo stato in un percorso fisso
# due esecuzioni della suite si passano i contatori e la seconda fallisce da sola. Un test che
# passa solo a macchina pulita non e' un test, e' una coincidenza.
STATE_DIR="${RDA_GOAL_GATE_STATE:-${TMPDIR:-/tmp}/rda-goal-gate}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit_pass
# LA CHIAVE E' SESSIONE **PIU' REPO**, e il "piu' repo" non e' un dettaglio di igiene.
# I tre contatori qui sotto (blocchi, coda precedente, giri fermi) descrivono UNA coda, e la coda
# e' per repo: `restanti` arriva da `kb queue --restanti` eseguito dentro $repo_root. Con la
# chiave sulla sola sessione, una sessione che tocca due repo li faceva scrivere sullo stesso
# file: `prec` del repo A confrontato con `restanti` del repo B produce un progresso o uno stallo
# che non e' avvenuto, quindi il FRENO 1 scatta (o non scatta) sulla misura di un altro repo, e
# il tetto del FRENO 2 si consuma in comune. Il difetto e' silenzioso nel modo peggiore: il
# cancello continua a funzionare, decide solo sul numero sbagliato.
# `cksum` e' POSIX (a differenza di shasum/sha1sum, che si dividono per piattaforma) e qui serve
# soltanto una chiave STABILE per un percorso. La chiave e' il percorso INTERO, non il nome della
# cartella: due worktree dello stesso repo sono due code diverse (`kb start` ne crea uno per
# card), e condividerebbero i contatori se la chiave fosse il nome.
scope="$(printf '%s' "$repo_root" | cksum 2>/dev/null | tr -cd '0-9')"
sf="$STATE_DIR/$(printf '%s' "$session" | tr -cd 'A-Za-z0-9._-').${scope:-norepo}"
blocchi=0; prec=-1; fermi=0
[ -f "$sf" ] && read -r blocchi prec fermi < "$sf" 2>/dev/null
case "$blocchi$prec$fermi" in *[!0-9-]*|'') blocchi=0; prec=-1; fermi=0 ;; esac

MAX_BLOCCHI="${RDA_GOAL_GATE_MAX:-12}"
MAX_FERMI="${RDA_GOAL_GATE_STALL:-2}"

# --- FRENO 1: nessun progresso. Il freno che conta davvero. ----------------------------------
# Se la coda non si e' accorciata dall'ultimo blocco, l'agente non sta avanzando: o e' fermo su
# una decisione di Roberto (gate umano), o e' incastrato. In tutti e due i casi continuare a
# rimandarlo dentro non produce lavoro, produce giri. E' la regola di loop-protocol: due
# passaggi consecutivi senza progresso -> fermati e di' cosa e' incastrato.
if [ "$prec" -ge 0 ] && [ "$restanti" -ge "$prec" ]; then
  fermi=$((fermi+1))
else
  fermi=0
fi

if [ "$fermi" -ge "$MAX_FERMI" ]; then
  printf '%s %s %s\n' "$blocchi" "$restanti" "0" > "$sf" 2>/dev/null
  echo "⚠️  GOAL-GATE: mi fermo. $restanti card ancora aperte ma la coda non si accorcia da $fermi giri — o aspettano una tua decisione, o qualcosa e' incastrato. \`kb queue\` per vedere quali." >&2
  exit_pass
fi

# --- FRENO 2: tetto ai blocchi per sessione. ------------------------------------------------
if [ "$blocchi" -ge "$MAX_BLOCCHI" ]; then
  echo "⚠️  GOAL-GATE: tetto di $MAX_BLOCCHI ripartenze raggiunto in questa sessione, con $restanti card ancora aperte. Mi fermo: continuare oltre e' una decisione di spesa, e la prende Roberto." >&2
  exit_pass
fi

blocchi=$((blocchi+1))
printf '%s %s %s\n' "$blocchi" "$restanti" "$fermi" > "$sf" 2>/dev/null

# exit 2 = il turno NON si chiude, e questo testo torna all'agente come istruzione.
cat >&2 <<EOF
GOAL-GATE: il turno non si chiude — restano $restanti card nella coda che Roberto ha gia'
autorizzato (ripartenza $blocchi di $MAX_BLOCCHI).

Non chiedergli il permesso: la coda E' il permesso, dato il 2026-07-30. Continua da solo:

  kb next                 la prossima card della lista autorizzata
  kb queue                cosa resta
  kb queue --aggiunte     cio' che e' nato DOPO lo scatto: quello resta a Roberto, non partirlo

Fermati da solo, senza aspettare questo hook, solo per: uno degli 8 gate umani di AGENTS.md
(spesa reale, pubblicazione esterna, decisione strategica, merge che tocca release/sicurezza),
oppure una card che non puo' avanzare — in quel caso scrivi PERCHE' sulla card con \`kb block\`,
cosi' il giro dopo la coda non si accorcia e questo cancello ti lascia uscire.
EOF
exit 2
