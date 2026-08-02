#!/usr/bin/env bash
# test-install-git-hooks.sh — il controllo installato deve sopravvivere alla cartella da cui
# lo si e' installato.
#
# IL DIFETTO (rilievo 2, 30 luglio 2026). `bin/install-git-hooks.sh` incideva nel controllo
# generato il percorso della cartella da cui era stato lanciato. Il canone impone **un worktree
# per card**, quindi lanciarlo da un worktree e' il caso NORMALE — e quel percorso e' garantito
# sparire alla chiusura della card. E' successo: rimosso `worktrees/roberdan-os/260730-092839`,
# **ogni commit in roberdan-os si e' bloccato** con "pre-commit: BLOCCATO — .../260730-092839/
# hooks/pre-commit non esiste".
#
# La quarta istanza di una famiglia sola in due giorni: **il controllo e il posto da cui lo
# installi non sono la stessa cosa.** Le altre tre riguardavano `--git-dir` contro `--git-path`.
#
# Il test lavora su cloni usa-e-getta in $TMPDIR: mai sul repo vero, dove installare un controllo
# sbagliato bloccherebbe i commit di Roberto.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

command -v git >/dev/null 2>&1 || { echo "  skip: git non disponibile"; echo "test-install-git-hooks: PASS"; exit 0; }
TMP="$(mktemp -d)"; trap 'git -C "$TMP/main" worktree remove --force "$TMP/wt" 2>/dev/null; rm -rf "$TMP"' EXIT

# Un repo finto minimo: serve solo hooks/pre-commit e lo script. Un clone del repo vero
# costerebbe secondi e porterebbe dentro i suoi hook veri.
mkdir -p "$TMP/main/bin" "$TMP/main/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/main/hooks/pre-commit"; chmod +x "$TMP/main/hooks/pre-commit"
cp "$ROOT/bin/install-git-hooks.sh" "$TMP/main/bin/"
git -C "$TMP/main" init -q
git -C "$TMP/main" config user.email t@t; git -C "$TMP/main" config user.name t
git -C "$TMP/main" add -A >/dev/null 2>&1
git -C "$TMP/main" -c commit.gpgsign=false commit -q -m base --no-verify
git -C "$TMP/main" worktree add -q "$TMP/wt" -b prova
cp "$ROOT/bin/install-git-hooks.sh" "$TMP/wt/bin/"

inciso() { # -> il percorso scritto dentro il controllo installato
  local h; h="$(git -C "$TMP/main" rev-parse --path-format=absolute --git-path hooks)"
  grep -oE '/[^ "]*/hooks/pre-commit' "$h/pre-commit" 2>/dev/null | head -1
}

printf '\n=== lanciato dal WORKTREE: incide il checkout principale ===\n'
( cd "$TMP/wt" && bash bin/install-git-hooks.sh ) >/dev/null 2>&1
p="$(inciso)"
case "$p" in
  *"/wt/"*)   err "incide ancora il worktree: $p — sparira' con la card" ;;
  *"/main/"*) ok  "incide il checkout principale, non il worktree" ;;
  *)          err "percorso inatteso nel controllo: '$p'" ;;
esac

printf '\n=== e il controllo regge dopo che il worktree e sparito ===\n'
git -C "$TMP/main" worktree remove --force "$TMP/wt" 2>/dev/null
( cd "$TMP/main" && echo x > z.txt && git add z.txt \
  && git -c commit.gpgsign=false commit -q -m "dopo la rimozione" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "il commit passa (prima si bloccava a ogni commit, per sempre)" \
                || err "il commit e' ancora bloccato dopo la rimozione del worktree (exit $rc)"

printf '\n=== lanciato dal checkout PRINCIPALE: si comporta come prima ===\n'
( cd "$TMP/main" && bash bin/install-git-hooks.sh ) >/dev/null 2>&1
p="$(inciso)"
case "$p" in
  *"/main/"*) ok "incide se stesso, nessuna regressione" ;;
  *)          err "dal principale ha inciso '$p'" ;;
esac

printf '\n=== il salto al principale e CONDIZIONATO: se laggiu non c e questo repo, non ci va ===\n'
# Caso vero: lo script finisce dentro il worktree di un ALTRO repo (copiato, o un layout diverso).
# Il checkout principale di quel repo non ha hooks/pre-commit: risolvere li' inciderebbe un
# percorso peggiore di quello che stiamo riparando. Deve restare dov'e'.
mkdir -p "$TMP/altro"
git -C "$TMP/altro" init -q
git -C "$TMP/altro" config user.email t@t; git -C "$TMP/altro" config user.name t
echo base > "$TMP/altro/f.txt"; git -C "$TMP/altro" add -A >/dev/null 2>&1
git -C "$TMP/altro" -c commit.gpgsign=false commit -q -m base --no-verify
git -C "$TMP/altro" worktree add -q "$TMP/altro-wt" -b w2
mkdir -p "$TMP/altro-wt/bin" "$TMP/altro-wt/hooks"      # solo il worktree ha il repo-tipo
cp "$ROOT/bin/install-git-hooks.sh" "$TMP/altro-wt/bin/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/altro-wt/hooks/pre-commit"
( cd "$TMP/altro-wt" && bash bin/install-git-hooks.sh ) >/dev/null 2>&1
h2="$(git -C "$TMP/altro" rev-parse --path-format=absolute --git-path hooks)"
p2="$(grep -oE '/[^ "]*/hooks/pre-commit' "$h2/pre-commit" 2>/dev/null | head -1)"
case "$p2" in
  *"/altro-wt/"*) ok "il principale non ha questo repo -> resta sulla cartella dello script" ;;
  "")             err "non ha installato niente: '$p2'" ;;
  *)              err "e saltato su un principale che non ha il repo: $p2" ;;
esac
git -C "$TMP/altro" worktree remove --force "$TMP/altro-wt" 2>/dev/null

printf '\n=== fuori da un repo git non esplode ===\n'
mkdir -p "$TMP/norepo/bin" "$TMP/norepo/hooks"
cp "$ROOT/bin/install-git-hooks.sh" "$TMP/norepo/bin/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/norepo/hooks/pre-commit"
( cd "$TMP/norepo" && timeout 30 bash bin/install-git-hooks.sh ) >/dev/null 2>&1
rc=$?
[ "$rc" -le 1 ] && ok "fuori da un repo esce senza bloccarsi (exit $rc)" \
                || err "fuori da un repo e' esploso (exit $rc)"

[ "$FAIL" -eq 0 ] && { echo "test-install-git-hooks: PASS"; exit 0; }
echo "test-install-git-hooks: FAIL"; exit 1
