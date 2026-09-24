#!/usr/bin/env bash
# test-twin-approve.sh — plan 2026-09-24 item 4.6: Roberto approves the whole block in ONE
# command, minus the exceptions. The gate stays his: the command refuses without a terminal
# (agents, schedulers, pipes), asks one confirmation, and then runs the NORMAL
# `kb start <id> --by roberto` per card, so every existing gate and audit line still applies.
# Fixture board + ledger in mktemp; the terminal is a real pseudo-terminal (python pty).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$ROOT/bin/twin-shadow.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
export RDA_HOME="$TMP/home" RDA_KANBAN="$TMP/board" RDA_KANBAN_REGISTRY="$TMP/registry"
export RDA_TWIN_BOARDS="$TMP/board" RDA_NO_PRECHECK=1 RDA_KB_ALLOW_PARALLEL=1 PYTHONDONTWRITEBYTECODE=1
unset RDA_TWIN_LEDGER_DIR RDA_TWIN_NOW CLAUDECODE
mkdir -p "$RDA_KANBAN"/{todo,doing,done} "$RDA_HOME"; : > "$RDA_KANBAN_REGISTRY"
card() { printf -- '---\ntitle: %s\nrepo: personal\nstatus: todo\ndod: fatto\nacceptance: visto\n---\n' "$1" > "$RDA_KANBAN/todo/$1.md"; }
host() { printf '#!/bin/sh\ncat >/dev/null\necho '"'"'{"choice":"%s","confidence":0.8,"category":"tecnico"}'"'"'\n' "$1" > "$TMP/h-$1"; chmod +x "$TMP/h-$1"; }
host approve; host reject
card A1; card A2; card A3
RDA_TWIN_HOST_CMD="$TMP/h-approve" bash "$TS" predict >/dev/null
card R1; RDA_TWIN_HOST_CMD="$TMP/h-reject" bash "$TS" predict >/dev/null
# tty <input> <args...>: run twin-shadow inside a real pseudo-terminal, typing <input>.
tty() { local input="$1"; shift
  printf '%b' "$input" | python3 -c 'import pty,sys; sys.exit(pty.spawn(sys.argv[1:]) >> 8)' bash "$TS" "$@"; }
led() { python3 -c "import json; print({json.loads(l)['card']: json.loads(l) for l in open('$RDA_HOME/private/decisions/ledger.jsonl')}$1)"; }

echo "== senza terminale: rifiutato, nulla parte =="
out="$(bash "$TS" approve </dev/null 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "terminale" <<<"$out" && [ -z "$(ls "$RDA_KANBAN/doing")" ] && ok "non interattivo: rifiutato (rc $rc), nessuna card avviata" || err "non-TTY accettato: rc=$rc $out"
out="$(CLAUDECODE=1 tty "si\n" approve 2>&1)"
grep -q "agente" <<<"$out" && [ -z "$(ls "$RDA_KANBAN/doing")" ] && ok "dentro una sessione agente: rifiutato anche con un terminale" || err "sessione agente accettata: $out"

echo "== con terminale, senza conferma: nulla parte =="
out="$(tty "no\n" approve 2>&1)"
[ -z "$(ls "$RDA_KANBAN/doing")" ] && grep -q "Nessuna card avviata" <<<"$out" && ok "risposta diversa da 'si': nessuna card avviata" || err "partite senza conferma: $out"

echo "== con terminale e conferma: il blocco parte, meno le eccezioni =="
out="$(tty "si\n" approve --except A2 2>&1)"
grep -q "A1" <<<"$out" && grep -q "A3" <<<"$out" && ok "mostra il blocco con le raccomandazioni prima di chiedere" || err "lista non mostrata: $out"
[ -e "$RDA_KANBAN/doing/A1.md" ] && [ -e "$RDA_KANBAN/doing/A3.md" ] && ok "le card del blocco sono partite" || err "blocco non partito: $out"
[ -e "$RDA_KANBAN/todo/A2.md" ] && ok "l'eccezione (--except A2) resta in attesa" || err "l'eccezione e' partita"
[ -e "$RDA_KANBAN/todo/R1.md" ] && ok "fuori dal blocco cio' che il twin non consiglia di approvare" || err "partita una card sconsigliata"
grep -q '^approved_by: roberto$' "$RDA_KANBAN/doing/A1.md" && grep -q 'kb_start_audit: .*by=roberto interactive=yes' "$RDA_KANBAN/doing/A1.md" \
  && ok "ogni card passa dal normale kb start --by roberto (audit interattivo scritto da kb)" || err "kb start non usato: $(cat "$RDA_KANBAN/doing/A1.md")"
[ "$(led "['A1']['roberto_choice']")" = approve ] && ok "l'esito e' nel registro" || err "esito non registrato"
[ "$(led "['A1']['batch']")" = True ] && ok "marcata come approvata in blocco" || err "flag batch mancante"
w="$(bash "$ROOT/bin/twin-agreement.sh")"
grep -q "decise dopo aver visto il consiglio del twin" <<<"$w" && ! grep -q "N=" <<<"$w" && ok "le approvazioni in blocco non contano nell'accordo (viste prima)" || err "contate nell'accordo: $w"

[ "$FAIL" -eq 0 ] && echo "test-twin-approve: PASS" || { echo "test-twin-approve: FAIL"; exit 1; }
