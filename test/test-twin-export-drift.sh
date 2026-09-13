#!/usr/bin/env bash
# test-twin-export-drift.sh — la skill twin esportata non resta indietro rispetto al canone.
#
# Perche' esiste: `.github/skills/roberto-twin/` e' derivata A MANO dal canone, non generata.
# Il 2026-09-13 si e' scoperto che era ferma al 21 agosto: il formato di risposta era cambiato
# in AGENTS.md e la skill — quella che viaggia in OGNI repo e in ogni chat — insegnava ancora
# il formato vecchio. Una copia a mano non ha nessun meccanismo che la tenga allineata: questo
# test e' quel meccanismo.
#
# Limite dichiarato: verifica che i MARCATORI del contratto corrente ci siano, non che il testo
# sia una traduzione fedele. Cattura la deriva strutturale (il contratto e' cambiato e la skill
# non lo sa), non una sfumatura di parole.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
t() { if [ "$2" = "ok" ]; then echo "  ok: $1"; else echo "  FAIL: $1"; fail=1; fi; }
has() { grep -q -- "$2" "$1" 2>/dev/null && echo ok || echo no; }

SK=".github/skills/roberto-twin/SKILL.md"
TH=".github/skills/roberto-twin/THINKING.md"

echo "== il formato di risposta corrente e' nella skill che viaggia ovunque =="
for part in "Stato" "Sto facendo" "Manca" "Mi serve da te"; do
  t "la skill insegna la sezione '$part'" "$(has "$SK" "$part")"
done
t "la skill esige la prova inline ('fatto e provato')" "$(has "$SK" "fatto e provato")"
t "il canone AGENTS.md usa lo stesso formato" "$(has AGENTS.md "Sto facendo")"

echo "== il vecchio contratto non sopravvive accanto a quello nuovo =="
# "verified / not verified" come SEZIONE separata e' stato rimosso il 2026-09-13: la garanzia
# vive dentro le righe di Stato. Se riappare, due contratti diversi convivono e vince il caso.
if grep -qi "verified / not verified" "$SK"; then
  t "nessuna sezione 'verified / not verified' residua" no
else
  t "nessuna sezione 'verified / not verified' residua" ok
fi

echo "== le lenti del canone sono nella skill =="
t "la lente dell'era AI e' presente" "$(has "$TH" "AI-era lens")"

echo "== il blocco globale insegna lo stesso formato (vale in ogni chat, non solo qui) =="
GB="bin/claude-global-block.md"
t "il blocco globale esiste" "$([ -f "$GB" ] && echo ok || echo no)"
for part in "Stato" "Sto facendo" "Manca" "Mi serve da te"; do
  t "il blocco globale insegna '$part'" "$(has "$GB" "$part")"
done
t "sync.sh propone quel blocco, non un testo suo" "$(has bin/sync.sh "claude-global-block.md")"

echo ""
[ "$fail" = 0 ] && echo "test-twin-export-drift: ALL GREEN" || echo "test-twin-export-drift: FAILED"
exit "$fail"
