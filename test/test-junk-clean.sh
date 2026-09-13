#!/usr/bin/env bash
# test/test-junk-clean.sh — la pulizia di cache e temporanei tocca SOLO cio' che e' rigenerabile.
#
# Qui l'errore costa piu' che altrove: un file non versionato e' spesso l'unica copia che esiste.
# Quindi la regola e' doppia — ignorato da git **E** con un nome nella lista — e meta' di questo
# test verifica che UNA condizione sola non basti, nei due versi.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUNK="$ROOT/kanban/junk.sh"
FAILS=0
ok()   { printf '  ok   — %s\n' "$1"; }
fail() { printf '  FAIL — %s\n' "$1"; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/GitHub"
export RDA_WORKTREES="$HOME/GitHub/worktrees"; mkdir -p "$RDA_WORKTREES"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config -f "$GIT_CONFIG_GLOBAL" user.email t@t; git config -f "$GIT_CONFIG_GLOBAL" user.name t

R="$HOME/GitHub/demo"; mkdir -p "$R"
git -C "$R" init -q -b main
printf '__pycache__/\n.venv/\ndist/\n.env\ndati-veri/\n' > "$R/.gitignore"
echo x > "$R/f"; git -C "$R" add .gitignore f; git -C "$R" commit -qm one

mkdir -p "$R/__pycache__" "$R/.venv" "$R/dist" "$R/dati-veri"
echo c > "$R/__pycache__/a.pyc"          # ignorato + nome noto -> si toglie
echo v > "$R/.venv/x"                     # ignorato + nome noto -> si toglie
echo d > "$R/dist/bundle.js"              # ignorato + nome noto -> si toglie
echo k > "$R/.env"                        # IGNORATO ma sono credenziali -> non si tocca
echo p > "$R/dati-veri/export.csv"        # IGNORATO ma sono dati -> non si tocca (nome non in lista)
echo w > "$R/bozza.md"                    # non tracciato e NON ignorato -> lavoro di qualcuno
mkdir -p "$R/node_modules"; echo n > "$R/node_modules/pkg.js"   # nome noto ma NON ignorato qui

out="$(bash "$JUNK" --only demo 2>&1)"
case "$out" in *"__pycache__"*) ok "il referto nomina la cache trovata" ;; *) fail "il referto non nomina la cache" ;; esac
[ -d "$R/__pycache__" ] && ok "senza --yes non cancella niente" || fail "ha cancellato senza --yes"

bash "$JUNK" --only demo --yes >/dev/null 2>&1

[ -d "$R/__pycache__" ] && fail "__pycache__ non e' stato tolto" || ok "tolta la cache (ignorata + nome noto)"
[ -d "$R/.venv" ] && fail ".venv non e' stato tolto" || ok "tolto l'ambiente virtuale (si rigenera con un comando)"
[ -d "$R/dist" ] && fail "dist non e' stato tolto" || ok "tolta la cartella di build"
[ -f "$R/.env" ] && ok "il file di credenziali e' intatto (ignorato NON vuol dire inutile)" || fail "CANCELLATO un .env"
[ -f "$R/dati-veri/export.csv" ] && ok "i dati ignorati ma senza nome noto sono intatti" || fail "CANCELLATI dati ignorati"
[ -f "$R/bozza.md" ] && ok "il file non tracciato e non ignorato e' intatto (unica copia)" || fail "CANCELLATO un file mai versionato"
[ -f "$R/node_modules/pkg.js" ] && ok "nome noto ma non ignorato qui: intatto" || fail "CANCELLATO un node_modules che questo repo non ignora"
[ -f "$R/f" ] && ok "i file versionati non si toccano" || fail "CANCELLATO un file versionato"

# nessun rm -rf nel percorso di cancellazione: si passa da `git clean`, che rifiuta da solo
# qualunque cosa non sia ignorata, anche se il percorso fosse costruito male.
grep -v '^[[:space:]]*#' "$JUNK" | grep -q 'rm -rf' && fail "junk.sh contiene un rm -rf" || ok "cancella solo tramite git clean, mai rm -rf"

if [ "$FAILS" -eq 0 ]; then echo "test-junk-clean: ✅ ALL GREEN"; else echo "test-junk-clean: ❌ $FAILS FAIL"; exit 1; fi
