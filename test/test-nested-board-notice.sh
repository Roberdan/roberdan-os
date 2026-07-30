#!/usr/bin/env bash
# test/test-nested-board-notice.sh — the pre-commit hook must tell you when the commit you
# are making does NOT include the card you just edited.
#
# The failure this pins is silent, which is why it needs a test at all. `kanban/` is a
# separate private git repo nested inside this one. `git add -A` here stages nothing under
# it (git treats a nested repo as an opaque entry, and it is ignored on top of that), and
# `git status` here reports nothing either. So on 2026-07-29 a card amendment was written,
# committed alongside three other files, reported as "3 files changed", and was not in the
# commit. Nothing errored. The same shape as the $ROOT bug that built a second board at
# ~/.local/kanban and went unnoticed for three weeks.
#
# The hook WARNS and lets the commit through, and the tests below pin that choice as much
# as the message itself: a dirty board is the normal state while a card is in progress, so
# blocking would fire constantly and train `--no-verify`, which would also disable the
# leak check that shares this hook. If someone later "upgrades" this to a block, case 2
# fails and says why.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A miniature of the real layout: an outer repo with a DIFFERENT git repo at kanban/.
# The hook is copied in verbatim, but leak-check.sh is stubbed to pass — this test is
# about the board notice, and depending on the real leak check would make it fail for
# reasons that have nothing to do with what it claims to prove.
OUT="$TMP/outer"
mkdir -p "$OUT/test" "$OUT/.git"
git init -q "$OUT"
git -C "$OUT" config user.name t; git -C "$OUT" config user.email t@t
printf '#!/usr/bin/env bash\nexit 0\n' > "$OUT/test/leak-check.sh"
# Anche la gamba anti-dump va stubbata, per la stessa ragione della leak-check: questo
# test parla della board. Senza lo stub il hook BLOCCA ogni commit del fixture perche' il
# controllo manca, e i casi qui sotto diventano verdi/rossi per un motivo che non c'entra
# — cosa successa davvero: aggiunta la gamba, questa suite e' rimasta rotta.
printf '#!/usr/bin/env bash\nexit 0\n' > "$OUT/test/directory-dump-check.sh"
cp "$ROOT/hooks/pre-commit" "$OUT/.git/hooks/pre-commit"
chmod +x "$OUT/.git/hooks/pre-commit" "$OUT/test/leak-check.sh" "$OUT/test/directory-dump-check.sh"
echo seed > "$OUT/file.txt"
git -C "$OUT" add -A >/dev/null 2>&1
git -C "$OUT" commit -q -m seed >/dev/null 2>&1

git init -q "$OUT/kanban"
git -C "$OUT/kanban" config user.name t; git -C "$OUT/kanban" config user.email t@t
mkdir -p "$OUT/kanban/todo"
echo "carta" > "$OUT/kanban/todo/X.md"
git -C "$OUT/kanban" add -A >/dev/null 2>&1
git -C "$OUT/kanban" commit -q -m cards >/dev/null 2>&1

section "board pulita: il hook tace"
echo change1 >> "$OUT/file.txt"
git -C "$OUT" add -A >/dev/null 2>&1
out="$(git -C "$OUT" commit -m c1 2>&1)"
case "$out" in
  *"la board"*) err "avvisa anche con la board pulita: $out" ;;
  *) ok "nessun rumore quando non c'e' niente da dire" ;;
esac

section "card modificata e non committata: il commit deve dirlo"
echo "modifica" >> "$OUT/kanban/todo/X.md"
echo change2 >> "$OUT/file.txt"
git -C "$OUT" add -A >/dev/null 2>&1
out="$(git -C "$OUT" commit -m c2 2>&1)"
case "$out" in
  *"NON la include"*) ok "avvisa che il commit non include la board" ;;
  *) err "silenzioso mentre la card si perde: $out" ;;
esac
case "$out" in
  *"todo/X.md"*) ok "nomina il file preciso, non un avviso generico" ;;
  *) err "non dice QUALE card: $out" ;;
esac

section "il commit passa comunque: e' un avviso, non un blocco"
# Pinned deliberately. Blocking would train `--no-verify`, which also disables the
# leak check in the same hook — trading a confidentiality control for a bookkeeping one.
if git -C "$OUT" log --oneline | grep -q ' c2$'; then
  ok "c2 e' stato committato nonostante la board sporca"
else
  err "il commit e' stato bloccato: l'avviso e' diventato un blocco"
fi

section "il leak check resta il controllo che BLOCCA"
printf '#!/usr/bin/env bash\nexit 1\n' > "$OUT/test/leak-check.sh"
echo change3 >> "$OUT/file.txt"
git -C "$OUT" add -A >/dev/null 2>&1
git -C "$OUT" commit -m c3 >/dev/null 2>&1
if git -C "$OUT" log --oneline | grep -q ' c3$'; then
  err "il commit e' passato con leak-check fallito: il hook non blocca piu'"
else
  ok "leak-check fallito blocca ancora il commit"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$OUT/test/leak-check.sh"

section "install-git-hooks installa uno SHIM, non una copia"
# @thor: nessun test vincolava questa proprieta'. Rimettendo `cp` in
# bin/install-git-hooks.sh tutta la suite restava verde, e la regressione sarebbe
# emersa solo alla prima modifica di hooks/pre-commit — cioe' nel momento in cui uno
# crede di aver cambiato il hook e non ha cambiato niente. E' esattamente il difetto
# del 2 luglio, che e' rimasto invisibile per quattro settimane.
# COPIA del working tree, non `git clone`: clone prende lo stato COMMITTATO, quindi il
# primo draft di questo caso verificava HEAD e restava verde anche rimettendo `cp`
# nell'installer. Un test che non vede le tue modifiche non testa le tue modifiche.
CL="$TMP/clone"
cp -R "$ROOT" "$CL" 2>/dev/null
rm -rf "$CL/.git" "$CL/kanban"
git init -q "$CL" 2>/dev/null
if [ -d "$CL/bin" ]; then
  ( cd "$CL" && bash bin/install-git-hooks.sh >/dev/null 2>&1 )
  _ih="$CL/.git/hooks/pre-commit"
  if grep -q '^# GENERATED by bin/install-git-hooks.sh' "$_ih" 2>/dev/null; then
    ok "il hook installato e' uno shim generato"
  else
    err "il hook installato non e' uno shim: una copia invecchia e nessuno se ne accorge"
  fi
  # La prova che conta non e' la forma dello shim, e' la proprieta': modifico il sorgente
  # versionato e il hook installato deve cambiare comportamento SENZA reinstallare.
  printf '\necho "MARKER-SHIM-RILETTO" >&2\n' >> "$CL/hooks/pre-commit"
  if bash "$_ih" 2>&1 | grep -q 'MARKER-SHIM-RILETTO'; then
    ok "modificare hooks/pre-commit cambia il hook senza reinstallare"
  else
    err "il hook installato non rilegge il sorgente: puo' andare fuori sincrono"
  fi
else
  err "clone fallito: impossibile verificare l'installer"
fi

section "una verifica ASSENTE non deve spacciarsi per un ritrovamento"
# Il hook deve fallire chiuso se il controllo anti-dump manca — ma dicendo la verita'.
# Stampare "corporate directory data" per un controllo mai eseguito insegna al lettore
# che quel messaggio non vuol dire niente, e il giorno in cui e' un leak vero lo bypassa.
mv "$OUT/test/directory-dump-check.sh" "$TMP/dump-parcheggiato.sh"
echo change4 >> "$OUT/file.txt"
git -C "$OUT" add -A >/dev/null 2>&1
out="$(git -C "$OUT" commit -m c4 2>&1)"
if git -C "$OUT" log --oneline | grep -q ' c4$'; then
  err "commit passato con il controllo anti-dump mancante: la guardia si spegne da sola"
else
  ok "controllo mancante = commit bloccato (fail closed)"
fi
case "$out" in
  *"nothing was checked"*) ok "dice che non ha controllato, invece di accusare un leak" ;;
  *) err "messaggio fuorviante per un controllo mai eseguito: $out" ;;
esac
mv "$TMP/dump-parcheggiato.sh" "$OUT/test/directory-dump-check.sh"

section "worktree: nessun falso allarme sulla board"
# Il difetto opposto, ed e' quello che ha davvero morso. git esporta GIT_DIR ai suoi
# hook e un `git -C kanban` annidato lo EREDITA: in un worktree — dove kanban/ esiste
# come directory ma senza `.git` — la sonda rispondeva sul repo PADRE, elencando i file
# del commit stesso come "card non salvate". Un avviso che grida al lupo in ogni
# worktree e' un avviso che nessuno legge nel checkout dove e' vero.
WT="$TMP/wt"
git -C "$OUT" worktree add -q "$WT" -b wt-case >/dev/null 2>&1
mkdir -p "$WT/kanban/todo"          # la directory c'e' (script tracciati), il repo no
echo "non e' una card" > "$WT/sporco.txt"
if [ -e "$WT/kanban/.git" ]; then
  err "il fixture non riproduce il worktree: kanban/.git non dovrebbe esistere qui"
else
  out="$( cd "$WT" && GIT_DIR="$(git rev-parse --absolute-git-dir)" \
          ROOT="$WT" bash "$OUT/.git/hooks/pre-commit" 2>&1 || true )"
  case "$out" in
    *"la board"*) err "falso allarme nel worktree: la sonda risponde sul repo padre: $out" ;;
    *) ok "tace dove non c'e' nessuna board da guardare" ;;
  esac
fi

printf "\n"
[ "$FAIL" = 0 ] && echo "test-nested-board-notice: PASS" || echo "test-nested-board-notice: FAIL"
exit "$FAIL"
