#!/usr/bin/env bash
# test-kb-diet.sh — i tre freni al board che cresce come le ninfee.
#
# Il 2026-07-30 il board aveva 33 card in attesa dell'approvazione di Roberto, sette in
# `doing` di cui quattro sullo stesso lavoro aperte da sette giorni, e ZERO card in corso sul
# progetto principale. Nessun gate era rotto: mancavano. `review-budget.sh` limita i GIRI
# dentro una card, il meta-card budget limita le card di auto-miglioramento; niente limitava
# quante card esistono, quanto vecchie sono, e quante ne girano insieme sullo stesso progetto.
#
# Ogni asserzione qui e' in DUE DIREZIONI: il caso che deve essere rifiutato E il caso
# legittimo che deve continuare a passare. Un gate provato in una sola direzione e' un gate
# che nessuno ha visto distinguere.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KBSH="$ROOT/kanban/kb.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
KB="$TMP/board"; mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
kb() { RDA_KANBAN="$KB" RDA_KANBAN_REGISTRY="$TMP/registry" bash "$KBSH" "$@" 2>&1; }

# `kb ... | grep -q` NON si puo' usare qui, e la ragione e' istruttiva: con `set -o pipefail`
# la catena eredita l'uscita non-zero di `kb` (1, perche' ha rifiutato), quindi un `if`
# sulla catena prende il ramo ELSE anche quando grep ha trovato la riga. La prima stesura di
# questo file faceva esattamente questo e riportava "ACCETTATA" su tre gate che funzionavano:
# un test che sbaglia nella direzione "tutto rotto" e' fortunato, uno che sbaglia nella
# direzione opposta stampa PASS su un gate spento. Si cattura l'output, poi si cerca dentro.
_dice() { # _dice <testo-atteso> -- <comando...>
  local atteso="$1"; shift; shift
  local o; o="$("$@")"
  case "$o" in *"$atteso"*) return 0 ;; *) return 1 ;; esac
}

printf '\n=== regola 4: una card, una condizione verificabile ===\n'

# Rifiutato: il punto e virgola e la congiunzione sono i due modi in cui una acceptance
# diventa una lista, e una lista non si chiude mai.
for cattiva in "il comando X stampa Y; anche Z passa" \
               "il comando X stampa Y e anche Z passa" \
               "1) X passa 2) Y passa"; do
  if _dice "REFUSED" -- kb add "prova" --repo alfa "una dod" "$cattiva"; then
    ok "rifiuta l'acceptance a piu' condizioni: \"$(printf '%s' "$cattiva" | cut -c1-38)...\""
  else
    err "ACCETTATA un'acceptance a piu' condizioni: \"$cattiva\" — la card non si chiudera' mai"
  fi
done

# La direzione opposta, che e' quella che rende il gate utile invece che solo severo.
if _dice "added todo/" -- kb add "prova buona" --repo alfa "una dod" "il comando X stampa Y"; then
  ok "accetta una condizione sola"
else
  err "RIFIUTA una acceptance legittima a una condizione — il gate e' inutilizzabile"
fi

# L'uscita di sicurezza esiste, perche' una frase italiana legittima puo' contenere " e ".
if RDA_KB_ALLOW_MULTI_CLAUSE=1 _dice "added todo/" -- kb add "con esenzione" --repo beta "dod" "X e Y sono la stessa cosa"; then
  ok "RDA_KB_ALLOW_MULTI_CLAUSE apre la strada quando serve"
else
  err "l'esenzione non funziona: un gate senza uscita di sicurezza viene aggirato, non rispettato"
fi

# Le card VECCHIE non vengono toccate: il controllo e' un ratchet, non una retroattivita'.
# Un gate rosso il giorno in cui nasce e' un gate spento — tre istanze di questa famiglia
# sono state chiuse in questo repo il 29 e il 30 luglio 2026.
cat > "$KB/todo/VECCHIA.md" <<'CARD'
---
title: card storica
repo: gamma
dod: "qualcosa"
acceptance: "A passa; B passa; C passa"
status: todo
created: 2026-07-01
---
CARD
if _dice "doing/VECCHIA started" -- kb start VECCHIA --by roberto --no-worktree "card storica"; then
  ok "una card preesistente a piu' condizioni parte comunque (ratchet, non retroattivita')"
else
  err "il gate e' retroattivo: rompe le card che esistevano prima. Nasce rosso, quindi nasce spento"
fi

printf '\n=== regola 1: una card in corso per progetto ===\n'

_card() { # _card <id> <repo>
  cat > "$KB/todo/$1.md" <<CARD
---
title: card $1
repo: $2
dod: "una dod"
acceptance: "il comando stampa il risultato"
status: todo
created: 2026-07-30
---
CARD
}

_card D1 delta
kb start D1 --by roberto --no-worktree "prova" >/dev/null
_card D2 delta
if _dice "REFUSED" -- kb start D2 --by roberto --no-worktree "prova"; then
  ok "rifiuta la seconda card sullo STESSO progetto"
else
  err "APERTO un secondo fronte su 'delta' — e' cosi' che nascono 4 card sullo stesso lavoro"
fi

# Due progetti diversi in parallelo sono legittimi: il limite e' per repo, non globale.
_card E1 epsilon
if _dice "doing/E1 started" -- kb start E1 --by roberto --no-worktree "prova"; then
  ok "un progetto DIVERSO parte comunque"
else
  err "il limite e' globale invece che per progetto: blocca lavoro legittimo su un altro repo"
fi

if RDA_KB_ALLOW_PARALLEL=1 _dice "doing/D2 started" -- kb start D2 --by roberto --no-worktree "prova"; then
  ok "RDA_KB_ALLOW_PARALLEL apre la strada quando due fronti servono davvero"
else
  err "l'esenzione non funziona"
fi

printf '\n=== regola 5: pending mostra un progetto alla volta ===\n'

# Il muro di 33 righe non veniva smistato: veniva ignorato. Il progetto del cwd per intero,
# gli altri contati.
cat > "$KB/todo/Z1.md" <<'CARD'
---
title: card di un altro progetto
repo: un-altro-progetto
dod: "d"
acceptance: "il comando stampa il risultato"
status: todo
created: 2026-07-30
---
CARD
out="$(cd "$TMP" && kb pending)"
if grep -q 'su altri progetti' <<<"$out"; then
  ok "le card degli altri progetti sono contate, non elencate"
else
  err "pending impila ancora tutti i progetti: $(printf '%s' "$out" | head -4)"
fi
if [ "$(cd "$TMP" && kb pending --tutti | grep -c '^  • ')" \
     -gt "$(cd "$TMP" && kb pending | grep -c '^  • ')" ]; then
  ok "--tutti apre l'elenco completo"
else
  err "--tutti non mostra piu' di quanto mostri la vista ristretta: l'opzione non serve a niente"
fi
# Il conteggio totale non deve cambiare: e' quello che finisce nell'hook di inizio sessione e
# nel digest, e un conteggio che cala perche' la VISTA e' cambiata e' un conteggio che mente.
n_tot="$(cd "$TMP" && kb pending --count)"
n_righe="$(cd "$TMP" && kb pending --tutti | grep -c '^  • ')"
if [ "$n_tot" -ge "$n_righe" ]; then
  ok "il conteggio totale ($n_tot) non e' stato ristretto dalla vista ($n_righe elencate)"
else
  err "il conteggio ($n_tot) e' minore delle card elencate ($n_righe): la vista ha nascosto anche il numero"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-kb-diet: PASS" || echo "test-kb-diet: FAIL"
exit "$FAIL"
