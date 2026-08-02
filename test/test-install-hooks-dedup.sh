#!/usr/bin/env bash
# test-install-hooks-dedup.sh — due scritture dello stesso comando sono lo stesso comando.
#
# IL DIFETTO (rilievo 24, 2026-08-02). `bin/install-hooks.sh` dichiara di essere
# "non-destructive by construction" e "idempotent: a second run is a no-op". Sulla macchina di
# Roberto non lo era: il dedup confrontava la stringa GREZZA del comando, e la configurazione
# viva usa forme equivalenti ma diverse da quelle che il generatore produce oggi.
#
#   in ~/.claude/settings.json          generato da sync.sh
#   bash $HOME/.../auto-checkpoint.sh   bash /Users/Roberdan/.../auto-checkpoint.sh
#   bash ~/.../context-inject.sh …      bash /Users/Roberdan/.../context-inject.sh …
#   bash /Users/.../verify-done.sh      /Users/.../verify-done.sh      (senza `bash`)
#
# Il dry-run annunciava "would add 11 hook command(s)" quando DIECI erano gia' installati, e
# `--apply` avrebbe fatto girare ogni controllo DUE VOLTE a ogni evento: due checkpoint, due gate
# di pre-completamento, due formattatori. E chi lo lancia lo fa proprio fidandosi di quella riga.
#
# IL DIFETTO OPPOSTO HA PIU' ASSERZIONI DI QUESTO, ed e' il motivo per cui il test esiste: un
# dedup troppo generoso non aggiungerebbe un controllo che serve, e sparirebbe in silenzio
# dichiarando "already wired". `X` e `X 2>/dev/null || true` NON sono lo stesso comando: hanno
# comportamenti diversi davanti a un errore.
#
# Ermetico: configurazione finta in $TMPDIR, mai ~/.claude/settings.json.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
command -v python3 >/dev/null 2>&1 || { echo "  skip: python3 assente"; echo "test-install-hooks-dedup: PASS"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# La funzione norm() VERA, estratta da bin/install-hooks.sh e non riscritta: se la si riscrive,
# il test passa verde mentre l'originale e' rotto. E' il difetto trovato oggi dentro
# test-thor-verdict.sh, e non si ripete qui.
python3 - "$ROOT/bin/install-hooks.sh" "$TMP/norm.py" <<'PYX'
import sys
src = open(sys.argv[1]).read()
i = src.index("def norm(cmd):")
# La funzione finisce alla sua ultima riga rientrata: "    return c". Prendere fino a un
# marcatore piu' lontano (com'era la prima versione) trascina dentro il resto dello script,
# l'import esplode, e ogni confronto diventa "diversi" — cioe' meta' delle asserzioni
# passavano verdi PER UN ERRORE. Un test che passa perche' e' rotto e' peggio di uno assente.
j = src.index("    return c\n", i) + len("    return c\n")
open(sys.argv[2], "w").write("import re, os\nHOME = os.path.expanduser('~')\n" + src[i:j])
PYX
if python3 -c "import sys; sys.path.insert(0,'$TMP'); from norm import norm; norm('x')" 2>/dev/null; then
  ok "norm() si importa e gira da sola"
else
  err "norm() estratta non e importabile: ogni confronto qui sotto sarebbe un falso verde"
  echo "test-install-hooks-dedup: FAIL"; exit 1
fi
grep -q "def norm" "$TMP/norm.py" && ok "norm() estratta da bin/install-hooks.sh, non riscritta" \
                                  || err "non sono riuscito a estrarre norm() dal file vero"

# 0 = uguali, 1 = diversi, 2 = ERRORE. Un errore non deve mai leggersi come "diversi": era
# cosi' nella prima versione di questo file, e cinque asserzioni passavano verdi per un import
# rotto.
uguali() {
  local out rc
  out="$(python3 -c "
import sys; sys.path.insert(0,'$TMP')
from norm import norm
print('SI' if norm(sys.argv[1]) == norm(sys.argv[2]) else 'NO')
" "$1" "$2" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then err "confronto ESPLOSO su '$1' vs '$2': $out"; return 2; fi
  [ "$out" = "SI" ]
}
H="$HOME"

printf '\n=== le forme che hanno causato il difetto: stesso comando ===\n'
uguali "bash \$HOME/GitHub/roberdan-os/hooks/auto-checkpoint.sh" \
       "bash $H/GitHub/roberdan-os/hooks/auto-checkpoint.sh" \
  && ok "\$HOME contro percorso assoluto" || err "\$HOME non riconosciuto"
uguali "bash ~/GitHub/roberdan-os/hooks/context-inject.sh 2>/dev/null || true" \
       "bash $H/GitHub/roberdan-os/hooks/context-inject.sh 2>/dev/null || true" \
  && ok "tilde contro percorso assoluto" || err "tilde non riconosciuta"
uguali "bash $H/x/hooks/verify-done.sh" "$H/x/hooks/verify-done.sh" \
  && ok "con e senza \`bash\` davanti" || err "il \`bash\` iniziale conta ancora"
uguali "bash  $H/x/y.sh   --flag" "bash $H/x/y.sh --flag" \
  && ok "spazi multipli" || err "gli spazi multipli contano ancora"
uguali "\${HOME}/x/y.sh" "$H/x/y.sh" && ok "\${HOME} con le graffe" || err "\${HOME} non riconosciuto"

printf '\n=== NON deve appiattire comandi che sono davvero diversi ===\n'
uguali "$H/x/y.sh" "$H/x/y.sh 2>/dev/null || true" \
  && err "ha appiattito X e X 2>/dev/null || true: due comportamenti diversi su errore" \
  || ok "la redirezione e il || true restano una differenza"
uguali "$H/x/y.sh" "$H/x/z.sh" && err "due script diversi appiattiti" || ok "script diversi restano diversi"
uguali "$H/x/y.sh --a" "$H/x/y.sh --b" && err "argomenti diversi appiattiti" || ok "argomenti diversi restano diversi"
uguali "$H/x/y.sh" "$H/x/y.sh --a" && err "con e senza argomento appiattiti" || ok "un argomento in piu resta una differenza"
uguali "cd /tmp/~x && y.sh" "cd /tmp/$H/x && y.sh" \
  && err "ha espanso una tilde in mezzo a un percorso" || ok "la tilde in mezzo a un percorso non viene toccata"

printf '\n=== e sul percorso vero: una configurazione scritta con \$HOME non fa aggiungere niente ===\n'
mkdir -p "$TMP/fake"
cat > "$TMP/settings.json" <<JSON
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "bash \$HOME/prova/hooks/auto-checkpoint.sh", "timeout": 30 },
  { "type": "command", "command": "$H/prova/hooks/verify-done.sh", "timeout": 15 }
] } ] } }
JSON
cat > "$TMP/snippet.json" <<JSON
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "bash $H/prova/hooks/auto-checkpoint.sh", "timeout": 30 },
  { "type": "command", "command": "bash $H/prova/hooks/verify-done.sh", "timeout": 15 }
] } ] } }
JSON
# Il blocco python vero di install-hooks.sh, estratto e lanciato sui due file finti.
python3 - "$ROOT/bin/install-hooks.sh" "$TMP/merge.py" <<'PY'
import sys
src = open(sys.argv[1]).read()
i = src.index("import json, re, sys, os, time")
j = src.index("PY\n", i)
open(sys.argv[2], "w").write(src[i:j])
PY
out="$(python3 "$TMP/merge.py" "$TMP/settings.json" "$TMP/snippet.json" 0 2>&1)"
case "$out" in
  *"already wired"*) ok "due forme diverse dello stesso comando -> niente da aggiungere" ;;
  *)                 err "vorrebbe ancora aggiungere: $out" ;;
esac

printf '\n=== ma un comando DAVVERO nuovo viene ancora aggiunto ===\n'
cat > "$TMP/snippet2.json" <<JSON
{ "hooks": { "Stop": [ { "hooks": [
  { "type": "command", "command": "bash $H/prova/hooks/auto-checkpoint.sh", "timeout": 30 },
  { "type": "command", "command": "bash $H/prova/hooks/goal-gate.sh", "timeout": 15 }
] } ] } }
JSON
out="$(python3 "$TMP/merge.py" "$TMP/settings.json" "$TMP/snippet2.json" 0 2>&1)"
case "$out" in
  *"goal-gate"*) ok "il controllo nuovo viene ancora proposto (il dedup non lo mangia)" ;;
  *)             err "un controllo NUOVO e sparito: $out" ;;
esac

[ "$FAIL" -eq 0 ] && { echo "test-install-hooks-dedup: PASS"; exit 0; }
echo "test-install-hooks-dedup: FAIL"; exit 1
