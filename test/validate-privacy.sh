#!/usr/bin/env bash
# test/validate-privacy.sh — i QUATTRO cancelli di privacy, verificati insieme.
#
# Non e' eseguibile da solo: viene SOURCED da test/validate.sh, che porta `section`, `ok`,
# `err`, `_suite` e la variabile FAIL. Vive in un file suo per la stessa ragione per cui
# `kanban/dash.sh` e `kanban/board.sh` sono usciti da `kb.sh`: validate.sh era esattamente
# sul limite delle 300 righe, e il ratchet e' li' apposta per far dividere invece di far
# crescere. Tenerli insieme ha anche un valore di lettura — i quattro gate sono un sistema
# solo, e si leggono in fila.
#
# I quattro, e la domanda di ciascuno (mechanics: docs/privacy-leak-check.md):
#   leak-check.sh            VOCABOLARIO   "e' un segreto gia' in lista?"
#   directory-dump-check.sh  FORMA         "ha la forma di una rubrica?"
#   private-marker-check.sh  DICHIARAZIONE "dice da solo di essere privato?"
#   new-area-check.sh        IL POSTO      "sta dove nessuno ha mai messo niente?"

# leak-check ha solo il self-test: girarlo sul repo qui sarebbe la terza volta nello stesso
# minuto (gira gia' nell'hook pre-commit), e costa minuti.
section "leak-check self-test — tier (b) salted-hash catches a planted leak"
if _suite test-leak-check; then ok "leak-check tiers verified (see bash test/test-leak-check.sh)"; else err "test-leak-check — see bash test/test-leak-check.sh"; fi

# Gli altri tre hanno la stessa forma: si fanno girare sul repo com'e' (dev'essere pulito) e
# poi si fa girare il loro self-test (dev'essere verde). Un giro solo, non tre coppie copiate.
while IFS='|' read -r _gate _suitename _cosa; do
  [ -n "$_gate" ] || continue
  section "$_gate — $_cosa"
  if bash "test/$_gate.sh" >/dev/null 2>&1; then ok "repo pulito secondo $_gate"; else err "$_gate e' rosso sul repo — see bash test/$_gate.sh"; fi
  if _suite "$_suitename"; then ok "$_suitename verde"; else err "$_suitename — see bash test/$_suitename.sh"; fi
done <<'GATES'
directory-dump-check|test-directory-dump-check|rubriche aziendali, che nessuna denylist puo' nominare in anticipo
private-marker-check|test-private-marker|file generati che si dichiarano privati, in un repo pubblico
new-area-check|test-new-area-check|un file in una zona del repo che nessuno ha mai aperto (IL POSTO)
GATES
