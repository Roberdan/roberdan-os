#!/usr/bin/env bash
# test-kb-title-quote.sh — un titolo con ':' e '"' e' YAML valido e torna identico.
#
# IL DIFETTO. `kb add "Rob: usare \"questo\" davvero" --repo x ...` scriveva
#   title: Rob: usare "questo" davvero
# senza quoting: un ':' dentro un valore non quotato rompe la mappa YAML (il parser legge
# "Rob" come chiave e il resto come rumore), e una '"' dentro un dod/acceptance gia' quotato
# chiude la stringa a meta'. gbrain (che legge le card come YAML vero) vedeva un file rotto o
# un titolo troncato — non un errore di battitura di chi scrive la card, un difetto del
# serializzatore. Il fix quota sempre title/dod/acceptance ed escapa \ e " (kanban/kb.sh
# _yaml_dq); _field le des-escapa in kb.sh, dash.sh, lint-cards.sh; snapshot.sh fa lo stesso
# inline. Questo file fissa la proprieta' nei due sensi: round-trip esatto per il caso nuovo,
# e le card vecchie non quotate continuano a leggersi come prima (nessuna retroattivita' rotta).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KBSH="$ROOT/kanban/kb.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }
section() { printf '\n=== %s ===\n' "$1"; }

# Fixture SEMPRE in mktemp — mai la board vera di roberdan-os.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
KB="$TMP/board"; mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
kb() { RDA_KANBAN="$KB" RDA_KANBAN_REGISTRY="$TMP/registry" bash "$KBSH" "$@"; }

TITLE='Rob: usare "questo" davvero — con \ e àccénti'
DOD='una dod con "virgolette" e un backslash \fine'
ACC='il comando stampa esattamente il testo originale'

section "kb add quota title/dod/acceptance: il file e' YAML valido"
out="$(kb add "$TITLE" --repo provarepo "$DOD" "$ACC" 2>&1)"
id="$(printf '%s\n' "$out" | grep -oE 'todo/[0-9a-zA-Z_-]+' | head -1 | cut -d/ -f2)"
if [ -z "$id" ]; then
  err "kb add non ha restituito un id — output: $out"
else
  ok "kb add ha creato $id"
fi
CARD="$KB/todo/$id.md"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  py_out="$(python3 - "$CARD" <<'PY'
import sys, yaml
text = open(sys.argv[1], encoding="utf-8").read()
block = text.split("---", 2)[1]
try:
    data = yaml.safe_load(block)
except Exception as e:
    print("PARSE-ERROR: %s" % str(e).splitlines()[0]); sys.exit(0)
if not isinstance(data, dict) or "title" not in data:
    print("NOT-A-MAPPING-OR-NO-TITLE"); sys.exit(0)
print("title=%s" % data.get("title"))
print("dod=%s" % data.get("dod"))
print("acceptance=%s" % data.get("acceptance"))
PY
)"
  case "$py_out" in
    PARSE-ERROR*|NOT-A-MAPPING-OR-NO-TITLE*)
      err "il frontmatter non e' YAML valido per un parser vero: $py_out" ;;
    *) ok "il frontmatter parsa come YAML reale (pyyaml)" ;;
  esac
  if printf '%s\n' "$py_out" | grep -qxF "title=$TITLE"; then
    ok "pyyaml legge title identico all'originale (':' e '\"' inclusi)"
  else
    err "pyyaml legge un title diverso: $(printf '%s' "$py_out" | grep '^title=')"
  fi
  if printf '%s\n' "$py_out" | grep -qxF "dod=$DOD"; then
    ok "pyyaml legge dod identico (virgolette e backslash inclusi)"
  else
    err "pyyaml legge un dod diverso: $(printf '%s' "$py_out" | grep '^dod=')"
  fi
else
  printf '  skip: python3 + pyyaml non disponibili — non posso parsare come un loader vero\n'
fi

section "_field (kb.sh) des-escapa esattamente: round-trip identico"
got_title="$(kb show "$id" 2>/dev/null | grep -m1 '^title:' | sed 's/^title:[[:space:]]*//')"
# kb show stampa il file grezzo (ancora quotato) — verifica solo che sia quotato e coerente.
case "$got_title" in
  \"*\") ok "kb show: il title e' scritto quotato (regola dello YAML valido rispettata)" ;;
  *) err "kb show: il title NON e' quotato — torneremmo al difetto: $got_title" ;;
esac

# board.sh chiama _field internamente: il valore che finisce sul cruscotto deve essere quello
# ORIGINALE, non la forma con \" e \\ ancora dentro.
board_out="$(kb view 2>&1)"
if printf '%s\n' "$board_out" | grep -qF "$TITLE"; then
  ok "kb view mostra il title esatto (des-escaping corretto in board.sh via _field)"
else
  err "kb view non mostra il title originale — output: $(printf '%s' "$board_out" | tr '\n' '¶')"
fi

section "dash.sh: la stessa card, lo stesso title esatto"
mkdir -p "$KB/doing"
mv "$CARD" "$KB/doing/$id.md"
dash_out="$(HOME="$TMP" bash "$ROOT/kanban/dash.sh" "$KB" 2>&1 || true)"
if printf '%s\n' "$dash_out" | grep -qF "$TITLE"; then
  ok "dash.sh mostra il title esatto (stessa correzione di _field)"
else
  err "dash.sh non mostra il title originale — output: $(printf '%s' "$dash_out" | tr '\n' '¶')"
fi
mv "$KB/doing/$id.md" "$KB/todo/$id.md"

section "lint-cards.sh: una card quotata con virgolette non spacca il lint"
if RDA_KANBAN="$KB" bash "$ROOT/kanban/lint-cards.sh" >/dev/null 2>&1; then
  ok "lint-cards.sh passa su una card con title/dod quotati ed escapati"
else
  err "lint-cards.sh fallisce su una card valida — la sua copia di _field non des-escapa bene"
fi

section "snapshot.sh: lo stesso title, dalla sua copia inline di des-escaping"
# snapshot.sh deriva REPO dal checkout git corrente (git-common-dir), non da RDA_KANBAN: una
# card conta solo se il suo `repo:` combacia. Stessa derivazione qui, per non indovinare.
_snap_common="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)"
case "$_snap_common" in
  "") _snap_repo_path="$ROOT" ;;
  /*) _snap_repo_path="$(dirname "$_snap_common")" ;;
  *)  _snap_repo_path="$(cd "$ROOT/$(dirname "$_snap_common")" && pwd)" ;;
esac
SNAP_REPO="$(basename "$_snap_repo_path")"
SNAP_CARD="$KB/doing/SNAP1.md"
{ echo '---'; echo "title: $(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/^/"/; s/$/"/')"
  echo "repo: $SNAP_REPO"; echo 'status: doing'; echo '---'; } > "$SNAP_CARD"
SNAP_OUT="$TMP/snapshot.tsv"
# Fixture-only: HOME/RDA_COPILOT_STORE point away from the real ~/.copilot session store and
# RDA_TOP_NO_NET skips `gh` — this reads nothing of Roberto's real session, ever.
( cd "$ROOT" && HOME="$TMP" RDA_HOME="$TMP/rda-home" RDA_KANBAN="$KB" RDA_COPILOT_STORE="$TMP/no-such-store.db" \
  RDA_TOP_NO_NET=1 bash kanban/snapshot.sh "$SNAP_OUT" >/dev/null 2>&1 ) || true
if [ -s "$SNAP_OUT" ] && grep -qF "$TITLE" "$SNAP_OUT"; then
  ok "snapshot.sh scrive il title esatto (des-escaping inline coerente con _field)"
else
  err "snapshot.sh non scrive il title esatto — vedi $SNAP_OUT: $(cat "$SNAP_OUT" 2>/dev/null | tr '\n' '¶')"
fi
rm -f "$SNAP_CARD"

section "bin/twinlib/board.py: il lettore del twin (terza implementazione di _field) des-escapa uguale"
# Non elencato nel task originale, ma legge lo stesso formato: il suo stesso docstring dice
# "same rule as kb.sh _field". Senza questo fix il twin avrebbe mostrato \" e \\ letterali su
# ogni card nuova con virgolette — trovato in revisione, non nella lista di partenza.
if command -v python3 >/dev/null 2>&1; then
  py2_out="$(ROOT_FOR_TWINLIB="$ROOT" CARD_TEXT="$(cat "$CARD")" python3 - "$TITLE" <<'PY'
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location("board", os.path.join(os.environ["ROOT_FOR_TWINLIB"], "bin/twinlib/board.py"))
board = importlib.util.module_from_spec(spec); spec.loader.exec_module(board)
got = board.field(os.environ["CARD_TEXT"], "title")
print("MATCH" if got == sys.argv[1] else "MISMATCH got=%r want=%r" % (got, sys.argv[1]))
PY
)"
  case "$py2_out" in
    MATCH) ok "bin/twinlib/board.py field() legge il title identico (stessa correzione di _field)" ;;
    *) err "bin/twinlib/board.py field() non des-escapa: $py2_out" ;;
  esac
else
  printf '  skip: python3 non disponibile\n'
fi

section "compatibilita': una card VECCHIA (non quotata, senza escaping) legge ancora giusto"
OLDTITLE='Fix the bug in foo.sh'
cat > "$KB/todo/OLD1.md" <<CARD
---
title: $OLDTITLE
repo: provarepo
dod: "una dod semplice"
acceptance: "il comando stampa il risultato"
status: todo
created: 2026-07-30
---
CARD
old_board="$(kb view 2>&1)"
if printf '%s\n' "$old_board" | grep -qF "$OLDTITLE"; then
  ok "una card pre-esistente, mai quotata, continua a leggersi identica"
else
  err "il fix ha rotto le card vecchie non quotate — output: $(printf '%s' "$old_board" | tr '\n' '¶')"
fi

section "kanban/kb.sh non e' cresciuto oltre la baseline (nessun ratchet rotto da questo fix)"
n="$(wc -l < "$ROOT/kanban/kb.sh" | tr -d ' ')"
base="$(awk -v p="kanban/kb.sh" '/^[0-9]/ && $2==p{print $1}' "$ROOT/test/file-size-baseline.txt")"
if [ -n "$base" ] && [ "$n" -le "$base" ]; then
  ok "kb.sh e' a $n righe, baseline $base: non cresciuto"
else
  err "kb.sh e' a $n righe (baseline $base): questo fix ha fatto crescere un file ratchettato"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && echo "test-kb-title-quote: PASS" || echo "test-kb-title-quote: FAIL"
exit "$FAIL"
