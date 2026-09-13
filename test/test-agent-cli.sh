#!/usr/bin/env bash
# test-agent-cli.sh — quale CLI agentica viene scelta, e con quali opzioni viene lanciata.
#
# IL FATTO CHE QUESTO FILE ESISTE PER RICORDARE. Il 2026-09-13, a meta' mattina, `claude` ha
# risposto "hai raggiunto il limite di spesa mensile" e il cancello @thor e' diventato
# ineseguibile: non un NO, proprio NESSUN verdetto, con la card ferma in doing e il lavoro
# fermo dietro. Il difetto non era il limite: era che un solo fornitore era cablato in cinque
# file diversi, e quando e' caduto non c'era nessun altro da chiamare. Roberto: il default
# dev'essere Copilot e i modelli disponibili li'.
#
# COSA PRETENDE, e sono tre cose diverse:
#   1. il DEFAULT e' copilot — se questo smette di valere, la decisione di Roberto e' stata
#      annullata da qualcuno senza dirlo;
#   2. la PRECEDENZA regge in tutti i casi, incluso quello che nessuno guarda mai: un binario
#      messo apposta nel PATH deve battere un binario vero trovato per percorso assoluto, o i
#      test di mezzo repo inietterebbero un finto CLI e verrebbe eseguito quello vero;
#   3. le OPZIONI sono quelle del fornitore scelto. `--permission-mode` non esiste in copilot e
#      `--allow-all-tools` non esiste in claude: passare le une all'altro non e' un dettaglio
#      cosmetico, e' un'invocazione che muore all'avvio.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
section() { printf '\n=== %s ===\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-agent-cli.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# LA FUNZIONE VERA, non una riscrittura: una copia passa verde mentre l'originale e' rotto.
# shellcheck source=../factory/agent-cli.sh
. "$ROOT/factory/agent-cli.sh"

# Due finti binari, uno per fornitore, in cartelle separate: cosi' si puo' comporre il PATH
# caso per caso e vedere CHI vince, senza dipendere da cosa e' installato sulla macchina.
mkdir -p "$TMP/bin-copilot" "$TMP/bin-claude" "$TMP/bin-both" "$TMP/empty"
for d in "$TMP/bin-copilot" "$TMP/bin-both"; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "${CAPARGV:-/dev/null}"\nexit 0\n' > "$d/copilot"
  chmod +x "$d/copilot"
done
for d in "$TMP/bin-claude" "$TMP/bin-both"; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "${CAPARGV:-/dev/null}"\nexit 0\n' > "$d/claude"
  chmod +x "$d/claude"
done

# risolvi <PATH> [env...] -> "kind bin"
risolvi() {
  local p="$1"; shift
  env -u RDA_AGENT_CLI -u CLAUDE PATH="$p" HOME="$TMP/empty" "$@" \
    bash -c ". '$ROOT/factory/agent-cli.sh'; rda_agent_resolve" | tr '\t' ' '
}

section "il default: con tutti e due installati, si sceglie copilot"
r="$(risolvi "$TMP/bin-both:/usr/bin:/bin")"
case "$r" in
  "copilot $TMP/bin-both/copilot") ok "copilot e' il default quando ci sono entrambi" ;;
  *) err "il default NON e' copilot: [$r] — la decisione del 2026-09-13 e' stata annullata" ;;
esac

section "il ripiego: senza copilot si usa claude, perche' un verificatore e' meglio di nessuno"
r="$(risolvi "$TMP/bin-claude:/usr/bin:/bin")"
case "$r" in
  "claude $TMP/bin-claude/claude") ok "senza copilot si ripiega su claude" ;;
  *) err "senza copilot non si e' ripiegato su claude: [$r]" ;;
esac

section "nessun CLI: stringa vuota, mai un binario inventato"
r="$(risolvi "/usr/bin:/bin")"
if [ -z "$r" ]; then ok "senza nessun CLI non si stampa niente (chi chiama decide: SKIP o fatale)"
else err "senza nessun CLI ha comunque risolto qualcosa: [$r]"; fi

section "le forzature esplicite vincono sul default"
r="$(risolvi "$TMP/bin-both:/usr/bin:/bin" RDA_AGENT_CLI=claude)"
case "$r" in
  "claude $TMP/bin-both/claude") ok "RDA_AGENT_CLI=claude riporta a claude anche con copilot presente" ;;
  *) err "RDA_AGENT_CLI=claude ignorato: [$r]" ;;
esac
r="$(env -u RDA_AGENT_CLI PATH="$TMP/bin-both:/usr/bin:/bin" HOME="$TMP/empty" CLAUDE="$TMP/bin-claude/claude" \
      bash -c ". '$ROOT/factory/agent-cli.sh'; rda_agent_resolve" | tr '\t' ' ')"
case "$r" in
  "claude $TMP/bin-claude/claude") ok "un \$CLAUDE gia' valorizzato resta valido (compatibilita' con i test esistenti)" ;;
  *) err "\$CLAUDE preesistente ignorato: [$r] — le suite che iniettano un finto binario si romperebbero" ;;
esac
r="$(risolvi "/usr/bin:/bin" RDA_AGENT_CLI="$TMP/bin-copilot/copilot")"
case "$r" in
  "copilot $TMP/bin-copilot/copilot") ok "un percorso esplicito che si chiama copilot e' trattato come copilot" ;;
  *) err "percorso esplicito mal classificato: [$r]" ;;
esac

section "IL CASO CHE NESSUNO GUARDA: il PATH batte i percorsi assoluti, per ENTRAMBI"
# I percorsi assoluti (~/.local/bin, /opt/homebrew) esistono solo per launchd, che ha un PATH
# minimo. Se si provassero subito dopo il PATH di copilot, un copilot VERO installato sulla
# macchina batterebbe un `claude` messo apposta nel PATH — ed e' esattamente cosi' che
# test-factory-kb.sh e le suite autothor iniettano il loro finto CLI. Chi mette qualcosa nel
# PATH sta dichiarando una scelta; un percorso assoluto e' solo una supposizione.
mkdir -p "$TMP/homefinto/.local/bin"
cp "$TMP/bin-copilot/copilot" "$TMP/homefinto/.local/bin/copilot"
r="$(env -u RDA_AGENT_CLI -u CLAUDE PATH="$TMP/bin-claude:/usr/bin:/bin" HOME="$TMP/homefinto" \
      bash -c ". '$ROOT/factory/agent-cli.sh'; rda_agent_resolve" | tr '\t' ' ')"
case "$r" in
  "claude $TMP/bin-claude/claude")
    ok "un claude nel PATH batte un copilot vero trovato per percorso assoluto" ;;
  *) err "il percorso assoluto ha scavalcato il PATH: [$r] — le suite che stubbano il CLI eseguirebbero quello vero" ;;
esac
r="$(env -u RDA_AGENT_CLI -u CLAUDE PATH="/usr/bin:/bin" HOME="$TMP/homefinto" \
      bash -c ". '$ROOT/factory/agent-cli.sh'; rda_agent_resolve" | tr '\t' ' ')"
case "$r" in
  "copilot $TMP/homefinto/.local/bin/copilot")
    ok "con un PATH minimo (launchd) il percorso assoluto trova comunque copilot" ;;
  *) err "con PATH minimo non ha trovato copilot per percorso assoluto: [$r]" ;;
esac

section "i nomi dei modelli sono tradotti per fornitore, non passati grezzi"
[ "$(rda_agent_model copilot sonnet)" = "claude-sonnet-5" ] \
  && ok "sonnet -> claude-sonnet-5 su copilot" || err "sonnet non tradotto su copilot: $(rda_agent_model copilot sonnet)"
[ "$(rda_agent_model copilot opus)" = "claude-opus-5" ] \
  && ok "opus -> claude-opus-5 su copilot" || err "opus non tradotto su copilot: $(rda_agent_model copilot opus)"
[ "$(rda_agent_model claude sonnet)" = "sonnet" ] \
  && ok "su claude i nomi logici restano quelli" || err "su claude sonnet e' stato cambiato"
[ "$(RDA_AGENT_MODEL_SONNET=un-altro rda_agent_model copilot sonnet)" = "un-altro" ] \
  && ok "RDA_AGENT_MODEL_SONNET permette di cambiare modello senza toccare il codice" \
  || err "RDA_AGENT_MODEL_SONNET ignorato"

section "le opzioni sono quelle del fornitore scelto (argv catturato davvero)"
CAP="$TMP/argv-copilot.txt"
# export, non un prefisso davanti alla chiamata: davanti a una FUNZIONE bash imposta la
# variabile nella shell corrente ma non la esporta, e il processo figlio non la vedrebbe.
( export CAPARGV="$CAP"; rda_agent_run copilot "$TMP/bin-copilot/copilot" claude-sonnet-5 "$TMP" "PROMPT-SENTINELLA" ) >/dev/null 2>&1
if [ -f "$CAP" ] \
  && grep -qx -- '--allow-all-tools' "$CAP" \
  && grep -A1 -x -- '--model' "$CAP" | grep -qx 'claude-sonnet-5' \
  && grep -qx -- 'PROMPT-SENTINELLA' "$CAP" \
  && ! grep -qx -- '--permission-mode' "$CAP"; then
  ok "copilot riceve --allow-all-tools + --model, e NESSUNA opzione di claude"
else
  err "argv copilot sbagliato: $(tr '\n' ' ' < "$CAP" 2>/dev/null)"
fi

CAP2="$TMP/argv-claude.txt"
( export CAPARGV="$CAP2"; rda_agent_run claude "$TMP/bin-claude/claude" sonnet "$TMP" "PROMPT-SENTINELLA" ) >/dev/null 2>&1
if [ -f "$CAP2" ] \
  && grep -A1 -x -- '--permission-mode' "$CAP2" | grep -qx 'auto' \
  && grep -A1 -x -- '--permission-prompts' "$CAP2" | grep -qx 'none' \
  && ! grep -qx -- '--allow-all-tools' "$CAP2" \
  && ! grep -qx -- '--dangerously-skip-permissions' "$CAP2"; then
  ok "claude riceve i suoi permessi non interattivi, e nessuna opzione di copilot"
else
  err "argv claude sbagliato: $(tr '\n' ' ' < "$CAP2" 2>/dev/null)"
fi

section "il lavoro parte DENTRO la cartella dichiarata, non dove e' stato lanciato lo script"
# --add-dir concede l'accesso, non cambia la cartella di lavoro. Senza il cd, un task ha
# davvero scritto il proprio file dentro il checkout di roberdan-os invece che nel suo.
mkdir -p "$TMP/cartella-del-lavoro"
printf '#!/usr/bin/env bash\npwd > "${CAPPWD:?}"\nexit 0\n' > "$TMP/bin-copilot/copilot-pwd"
chmod +x "$TMP/bin-copilot/copilot-pwd"
( export CAPPWD="$TMP/pwd.txt"; rda_agent_run copilot "$TMP/bin-copilot/copilot-pwd" m "$TMP/cartella-del-lavoro" p ) >/dev/null 2>&1
if [ "$(cd "$TMP/cartella-del-lavoro" && pwd -P)" = "$(cd "$(cat "$TMP/pwd.txt" 2>/dev/null || echo /)" 2>/dev/null && pwd -P)" ]; then
  ok "il processo figlio parte nella cartella dichiarata"
else
  err "il figlio e' partito in $(cat "$TMP/pwd.txt" 2>/dev/null), non in $TMP/cartella-del-lavoro"
fi

section "senza nessun CLI, thor-verify dice SKIP e non nomina un fornitore solo"
FAKE="$TMP/fakerepo"; mkdir -p "$FAKE/kanban" "$FAKE/factory"
cp "$ROOT/kanban/thor-verify.sh" "$FAKE/kanban/"
cp "$ROOT/factory/agent-cli.sh" "$FAKE/factory/"
printf 'verify_card() { printf "PASS\\tmai raggiunto\\n"; }\n' > "$FAKE/factory/lib.sh"
out="$(env -u RDA_AGENT_CLI -u CLAUDE PATH="/usr/bin:/bin" HOME="$TMP/empty" RDA_IN_THOR_VERIFY=0 \
        bash "$FAKE/kanban/thor-verify.sh" QUALSIASI 2>/dev/null || true)"
case "$out" in
  SKIP*copilot*claude*) ok "SKIP nomina entrambi i CLI: chi legge sa cosa installare" ;;
  SKIP*) err "SKIP, ma il messaggio nomina un fornitore solo: $out" ;;
  *)    err "senza nessun CLI thor-verify non ha detto SKIP: $out" ;;
esac

printf '\n'
if [ "$FAIL" -eq 0 ]; then printf 'test-agent-cli: ✅ ALL GREEN\n'; else printf 'test-agent-cli: FAIL\n'; fi
exit "$FAIL"
