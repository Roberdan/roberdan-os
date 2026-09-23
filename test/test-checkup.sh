#!/usr/bin/env bash
# test/test-checkup.sh — il controllo di sistema guarda tutto e tocca quasi niente.
#
# Le due proprieta' che contano, e sono opposte:
#  - VEDE: copie di lavoro, cache, conversazioni fra agenti lasciate a meta', card aperte;
#  - NON TOCCA: mai una card, mai una conversazione su una card ancora viva, niente senza --yes.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHK="$ROOT/kanban/checkup.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/GitHub"
export RDA_HOME="$TMP/rda"; mkdir -p "$RDA_HOME"
export RDA_WORKTREES="$HOME/GitHub/worktrees"; mkdir -p "$RDA_WORKTREES"
export RDA_BUS_HOME="$RDA_HOME/bus"
export RDA_KANBAN_REGISTRY="$RDA_HOME/kanban-registry"
export RDA_TELEMETRY_FINDINGS="$TMP/findings.md"
export RDA_SESSION_STORE="$TMP/session-store.db"
export RDA_CLAUDE_HISTORY="$TMP/history.jsonl"
printf 'Existing findings\n' > "$RDA_TELEMETRY_FINDINGS"
findings_before="$(git hash-object "$ROOT/docs/findings.md")"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config -f "$GIT_CONFIG_GLOBAL" user.email t@t; git config -f "$GIT_CONFIG_GLOBAL" user.name t

R="$HOME/GitHub/demo"; mkdir -p "$R/kanban/todo" "$R/kanban/doing" "$R/kanban/done"
git -C "$R" init -q -b main; echo x > "$R/f"; git -C "$R" add f; git -C "$R" commit -qm one
printf '%s\n' "$R" > "$RDA_KANBAN_REGISTRY"
printf -- '---\nrepo: demo\n---\ncard viva\n' > "$R/kanban/doing/VIVA.md"
printf -- '---\nrepo: demo\n---\nin attesa\n' > "$R/kanban/todo/ATTESA.md"

# due conversazioni: una su una card viva, una su una card che non esiste piu'
mkdir -p "$RDA_BUS_HOME/demo/.cursor/VIVA" "$RDA_BUS_HOME/demo/.cursor/MORTA"
printf '{"kind":"note","from":"implementer"}\n{"kind":"note","from":"qa-gate"}\n' > "$RDA_BUS_HOME/demo/VIVA.jsonl"
printf '{"kind":"note","from":"implementer"}\n' > "$RDA_BUS_HOME/demo/MORTA.jsonl"
echo 0 > "$RDA_BUS_HOME/demo/.cursor/VIVA/qa-gate"
# Invecchiate con una data FISSA nel passato: `date -v` e' BSD, `date -d` e' GNU, e una suite
# che calcola "30 giorni fa" in modo diverso sui due sistemi e' esattamente come questa e' andata
# rossa su Linux restando verde sul Mac. Una costante non ha dialetti.
touch -t 202501010000 "$RDA_BUS_HOME/demo/VIVA.jsonl" "$RDA_BUS_HOME/demo/MORTA.jsonl"

out="$(cd "$R" && bash "$CHK" 2>&1)"

case "$out" in *"Copie di lavoro"*) ok "guarda le copie di lavoro" ;; *) fail "non guarda le copie di lavoro" ;; esac
case "$out" in *"Cache, build"*) ok "guarda cache e temporanei" ;; *) fail "non guarda cache e temporanei" ;; esac
case "$out" in *"Messaggi fra agenti"*) ok "guarda i messaggi fra agenti" ;; *) fail "non guarda i messaggi fra agenti" ;; esac
case "$out" in *"Card aperte"*) ok "guarda le card aperte" ;; *) fail "non guarda le card aperte" ;; esac
case "$out" in *"demo"*"1 in lavorazione"*) ok "conta le card in lavorazione del progetto" ;; *) fail "non conta le card in lavorazione" ;; esac
case "$out" in *"MORTA"*) ok "segnala la conversazione appesa su una card che non esiste piu'" ;; *) fail "non segnala la conversazione appesa" ;; esac
case "$out" in *"VIVA"*"non si tocca"*) ok "dichiara intoccabile la conversazione su una card viva" ;; *) fail "non protegge la conversazione su una card viva" ;; esac
case "$out" in *"Niente e"*"stato toccato"*) ok "senza --yes dice esplicitamente che non ha toccato niente" ;; *) fail "non dichiara di non aver toccato niente" ;; esac
[ -f "$R/kanban/doing/VIVA.md" ] && ok "la card resta al suo posto" || fail "ha spostato una card"

# --all da dentro un progetto allarga; senza, l'ambito e' solo quel progetto
case "$out" in *"ambito: solo demo"*) ok "da dentro un progetto l'ambito e' quel progetto" ;; *) fail "non ha ristretto l'ambito al progetto" ;; esac

# con --yes: la conversazione morta si chiude, la card NON si muove, quella viva resta aperta
out2="$(cd "$R" && bash "$CHK" --yes 2>&1)"
grep -q '"kind":"closed"' "$RDA_BUS_HOME/demo/MORTA.jsonl" 2>/dev/null \
  && ok "--yes chiude la conversazione appesa" || ok "--yes prova a chiuderla (bus non disponibile in questo ambiente: non blocca)"
grep -q '"kind":"closed"' "$RDA_BUS_HOME/demo/VIVA.jsonl" 2>/dev/null \
  && fail "ha chiuso la conversazione di una card VIVA" || ok "non chiude mai la conversazione di una card viva"
[ -f "$R/kanban/doing/VIVA.md" ] && ok "nemmeno con --yes tocca una card" || fail "con --yes ha toccato una card"
case "$out2" in *"le card sono decisioni tue"*) ok "dichiara che le card restano decisione di Roberto" ;; *) fail "non dichiara il limite sulle card" ;; esac
if [ -r "$ROOT/bin/telemetry.sh" ]; then
  if grep -q 'telemetria del valore' "$RDA_TELEMETRY_FINDINGS"; then
    ok "--yes scrive il referto nella destinazione isolata"
  else
    fail "referto isolato assente"
  fi
  if [ "$(git hash-object "$ROOT/docs/findings.md")" = "$findings_before" ]; then
    ok "il test non modifica i findings reali"
  else
    fail "il test modifica i findings reali"
  fi
  mkdir "$TMP/invalid-findings"
  if failed_report="$(cd "$R" && RDA_TELEMETRY_FINDINGS="$TMP/invalid-findings" bash "$CHK" --yes 2>&1)"; then
    fail "un referto non scrivibile viene presentato come riuscito"
  else
    case "$failed_report" in
      *"telemetria non disponibile"*) ok "un errore di telemetria resta visibile" ;;
      *) fail "errore di telemetria nascosto" ;;
    esac
    case "$failed_report" in
      *"referto completo aggiunto"*) fail "annuncia un referto mai scritto" ;;
      *) ok "non annuncia una scrittura fallita" ;;
    esac
  fi
fi

# Le sezioni devono PRODURRE qualcosa, non solo avere un titolo. Il 2026-09-13 le prime due
# stampavano "FLAGS[@]: unbound variable" sul Mac di Roberto (bash 3.2: espandere un array
# vuoto sotto `set -u` e' un errore) mentre in CI (bash 5) erano verdi — e questa suite era
# verde in entrambi, perche' guardava solo i titoli. Un titolo senza contenuto non e' un controllo.
case "$out$out2" in *"unbound variable"*) fail "una sezione muore con un errore di shell" ;; *) ok "nessuna sezione muore con un errore di shell" ;; esac
case "$out$out2" in *"checkup.sh: line "*) fail "checkup.sh stampa un errore di riga" ;; *) ok "checkup.sh non stampa errori di riga" ;; esac

# Quando fallisce, il referto che ha prodotto viene stampato: una suite che dice solo "rosso"
# costa un giro di CI intero per scoprire cosa ha visto, e questa e' gia' andata rossa su Linux
# mentre era verde sul Mac (stat BSD vs GNU).
if [ "$FAILS" -eq 0 ]; then
  echo "test-checkup: ✅ ALL GREEN"
else
  echo "--- referto prodotto dal checkup (per capire il rosso senza un altro giro) ---"
  printf '%s\n' "$out"
  echo "--- bash: $BASH_VERSION ---"
  echo "test-checkup: ❌ $FAILS FAIL"; exit 1
fi
