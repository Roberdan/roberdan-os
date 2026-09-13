#!/usr/bin/env bash
# factory/agent-cli.sh — quale CLI agentica esegue un passaggio headless, e con quali opzioni.
#
# PERCHE' ESISTE. Fino al 2026-09-13 ogni passaggio headless — il cancello @thor del kanban, la
# fabbrica, le valutazioni — cercava il binario `claude` e basta. Quel giorno quel CLI ha esaurito
# il limite di spesa mensile a meta' mattina e il cancello e' diventato ineseguibile: non un
# verdetto NO, proprio nessun verdetto, con la card bloccata in doing e il lavoro fermo. Roberto
# ha deciso che il default deve essere Copilot e i modelli gia' disponibili li'. Questo file e'
# l'unico posto dove quella scelta e' scritta: i chiamanti non nominano piu' un fornitore.
#
# E' SORGENTE, MAI ESEGUITO: non imposta opzioni di shell (le possiede lo script che lo sorge).
#
# ORDINE DI RISOLUZIONE, dal piu' esplicito al default:
#   1. $RDA_AGENT_CLI          nome (`copilot`|`claude`) o percorso assoluto — vince su tutto
#   2. $CLAUDE                 gia' valorizzato ed eseguibile — compatibilita': i test esistenti
#                              iniettano qui il loro finto binario e devono continuare a valere
#   3. `copilot` nel PATH      IL DEFAULT
#   4. `claude` nel PATH       ripiego: meglio un verificatore che nessuno
#   5. percorsi assoluti noti  ultima spiaggia, per launchd che ha un PATH minimo (copilot, poi
#                              claude) — DOPO il PATH di entrambi, vedi il commento in fondo
#   6. niente                  stringa vuota: chi chiama decide se saltare o fallire
#
# I due CLI non condividono ne' le opzioni ne' i nomi dei modelli, quindi qui si traducono
# entrambi. Chi chiama parla per intenzione (`sonnet`|`opus`), non per nome commerciale.

# rda_agent_resolve -> stampa "KIND<TAB>BINARIO", o niente se non c'e' nessun CLI
rda_agent_resolve() {
  local want="${RDA_AGENT_CLI:-}" bin="" p=""

  if [ -n "$want" ]; then
    case "$want" in
      copilot)
        bin="$(command -v copilot 2>/dev/null || true)"
        [ -n "$bin" ] && printf 'copilot\t%s\n' "$bin"
        return 0 ;;
      claude)
        bin="$(command -v claude 2>/dev/null || true)"
        [ -n "$bin" ] && printf 'claude\t%s\n' "$bin"
        return 0 ;;
      *)
        # percorso esplicito: il tipo si deduce dal nome del file, non si indovina
        [ -x "$want" ] || return 0
        case "$(basename "$want")" in
          *copilot*) printf 'copilot\t%s\n' "$want" ;;
          *)         printf 'claude\t%s\n'  "$want" ;;
        esac
        return 0 ;;
    esac
  fi

  # $CLAUDE preesistente: i test lo usano per iniettare un finto binario. Resta valido.
  if [ -n "${CLAUDE:-}" ] && [ -x "${CLAUDE}" ]; then
    printf 'claude\t%s\n' "$CLAUDE"
    return 0
  fi

  # ORDINE, e non e' un dettaglio: prima il PATH per ENTRAMBI, poi i percorsi assoluti per
  # entrambi. I percorsi assoluti esistono solo perche' sotto launchd il PATH e' minimo e non
  # contiene ne' l'uno ne' l'altro. Se li si provasse subito dopo il PATH di copilot, un binario
  # vero trovato per percorso assoluto batterebbe un binario messo apposta nel PATH — che e'
  # esattamente come i test iniettano il loro finto CLI, e come si lancia un runner alternativo.
  # Chi mette qualcosa nel PATH sta dichiarando una scelta: viene prima di una supposizione.
  bin="$(command -v copilot 2>/dev/null || true)"
  if [ -n "$bin" ] && [ -x "$bin" ]; then
    printf 'copilot\t%s\n' "$bin"
    return 0
  fi

  bin="$(command -v claude 2>/dev/null || true)"
  if [ -n "$bin" ] && [ -x "$bin" ]; then
    printf 'claude\t%s\n' "$bin"
    return 0
  fi

  for p in "$HOME/.local/bin/copilot" /opt/homebrew/bin/copilot /usr/local/bin/copilot; do
    [ -x "$p" ] && { printf 'copilot\t%s\n' "$p"; return 0; }
  done

  for p in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude "$HOME/.bun/bin/claude" /usr/local/bin/claude; do
    [ -x "$p" ] && { printf 'claude\t%s\n' "$p"; return 0; }
  done

  return 0
}

# rda_agent_model KIND LOGICO -> nome del modello per quel CLI.
# I nomi commerciali cambiano; l'intenzione no. Override per macchina:
# RDA_AGENT_MODEL_SONNET / RDA_AGENT_MODEL_OPUS.
rda_agent_model() {
  local kind="$1" logical="$2"
  case "$logical" in
    opus)
      if [ -n "${RDA_AGENT_MODEL_OPUS:-}" ]; then printf '%s' "$RDA_AGENT_MODEL_OPUS"
      elif [ "$kind" = "copilot" ]; then printf 'claude-opus-5'
      else printf 'opus'; fi ;;
    *)
      if [ -n "${RDA_AGENT_MODEL_SONNET:-}" ]; then printf '%s' "$RDA_AGENT_MODEL_SONNET"
      elif [ "$kind" = "copilot" ]; then printf 'claude-sonnet-5'
      else printf 'sonnet'; fi ;;
  esac
}

# rda_agent_run KIND BIN MODEL DIR PROMPT [TIMEOUT_BIN] [TIMEOUT_S]
# Esegue il passaggio headless dentro DIR, su stdout/stderr: il reindirizzamento sul file di log
# resta a chi chiama, com'era prima.
#
# Il `cd "$dir"` non e' ridondante rispetto a --add-dir: --add-dir concede l'ACCESSO al percorso,
# non cambia la cartella di lavoro del processo. Senza il cd, "la cartella corrente" dentro un
# prompt si risolveva dove era stato lanciato lo script chiamante — misurato dal vivo, con un
# file finito nel repo sbagliato.
#
# Permessi: un passaggio headless non puo' rispondere a una domanda. Su claude,
# `--permission-mode auto --permission-prompts none` approva il lavoro ordinario e NEGA cio' che
# richiederebbe conferma. Su copilot, `--allow-all-tools` e' l'unica modalita' non interattiva
# supportata: e' piu' permissiva, e va saputo. Il contenimento vero resta la cartella dichiarata
# piu' i controlli del repo, non la gentilezza del prompt.
rda_agent_run() {
  local kind="$1" bin="$2" model="$3" dir="$4" prompt="$5" tbin="${6:-}" tmo="${7:-}"
  local -a pre=()
  if [ -n "$tbin" ] && [ -n "$tmo" ]; then pre=("$tbin" "$tmo"); fi
  # ${pre[@]+"${pre[@]}"} e non "${pre[@]}": chi ci chiama gira sotto `set -u`, e su bash 3.2 —
  # quello di serie su macOS, quindi quello di launchd — espandere un array VUOTO con "${a[@]}"
  # e' un "unbound variable" che uccide la subshell. Misurato qui: senza timeout il comando non
  # partiva affatto, e con stdout e stderr gia' rediretti sul log l'errore era invisibile.
  if [ "$kind" = "copilot" ]; then
    ( cd "$dir" && ${pre[@]+"${pre[@]}"} "$bin" -p "$prompt" --model "$model" \
        --allow-all-tools --add-dir "$dir" --no-color )
  else
    ( cd "$dir" && ${pre[@]+"${pre[@]}"} "$bin" -p "$prompt" --model "$model" \
        --permission-mode auto --permission-prompts none --add-dir "$dir" )
  fi
}
