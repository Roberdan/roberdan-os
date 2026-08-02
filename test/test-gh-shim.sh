#!/usr/bin/env bash
# test-gh-shim.sh — lo shim sceglie l'account dal repo, e soprattutto NON rompe niente.
#
# Due difetti opposti, e il secondo è molto peggio del primo:
#   (a) sceglie l'account sbagliato -> torna il rilievo 3 (PR non create, merge rifiutati, un
#       "Repository not found" su un repo che esiste).
#   (b) rompe `gh` -> Roberto lo usa cento volte al giorno, e uno shim che si mette in mezzo a
#       tutto non può essere l'anello che si spezza.
# Per questo la maggioranza delle asserzioni qui verifica che LASCI PASSARE il gh vero
# invariato: fuori da un repo, remote non GitHub, proprietario sconosciuto, cartella assente,
# interruttore, GH_CONFIG_DIR già scelto dal chiamante.
#
# Ermetico: nessuna chiamata di rete, nessun account vero. Il "gh" è un finto che stampa quello
# che ha ricevuto — ed è l'unico modo di asserire sia la cartella scelta SIA che gli argomenti
# arrivino interi (il primo bug scritto in questo file: un `set -- $line` che riscriveva "$@").
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$ROOT/bin/gh-shim.sh"
FAIL=0
ok()  { printf '  ok: %s\n' "$1"; }
err() { printf '  FAIL: %s\n' "$1"; FAIL=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# gh finto: stampa la cartella scelta e gli argomenti ricevuti.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/gh" <<'FAKE'
#!/bin/sh
echo "DIR=${GH_CONFIG_DIR:-<nessuna>}"
echo "ARGS=$*"
FAKE
chmod +x "$TMP/fakebin/gh"

# due cartelle di configurazione finte, con il file che lo shim controlla
for d in roberdan microsoft; do mkdir -p "$TMP/cfg-$d"; echo "github.com:" > "$TMP/cfg-$d/hosts.yml"; done
cat > "$TMP/map.conf" <<EOF
# proprietario -> cartella
Roberdan            $TMP/cfg-roberdan
microsoft           $TMP/cfg-microsoft
EOF

mkrepo() { # <nome> <url-origin>
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q 2>/dev/null
  [ -n "${2:-}" ] && git -C "$d" remote add origin "$2"
  echo "$d"
}
run() { # <cwd> <args...>
  local cwd="$1"; shift
  (cd "$cwd" && PATH="$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/map.conf" bash "$SHIM" "$@" 2>&1)
}
_dir()  { printf '%s' "$1" | sed -n 's/^DIR=//p'; }
_args() { printf '%s' "$1" | sed -n 's/^ARGS=//p'; }

printf '\n=== (a) sceglie la cartella dal proprietario del remote ===\n'
R1="$(mkrepo mio    git@github.com:Roberdan/roberdan-os.git)"
R2="$(mkrepo lavoro https://github.com/microsoft/qualcosa.git)"
o="$(run "$R1" api user)"
[ "$(_dir "$o")" = "$TMP/cfg-roberdan" ] && ok "repo di Roberdan (ssh) -> cartella di Roberdan" \
                                         || err "repo di Roberdan -> ha scelto '$(_dir "$o")'"
o="$(run "$R2" api user)"
[ "$(_dir "$o")" = "$TMP/cfg-microsoft" ] && ok "repo di microsoft (https) -> cartella microsoft" \
                                          || err "repo di microsoft -> ha scelto '$(_dir "$o")'"

printf '\n=== gli argomenti arrivano INTERI (il primo bug di questo file) ===\n'
o="$(run "$R1" pr list --limit 1 --state all --json number -q '.[].number')"
[ "$(_args "$o")" = "pr list --limit 1 --state all --json number -q .[].number" ] \
  && ok "sei argomenti passano invariati al gh vero" \
  || err "argomenti alterati: '$(_args "$o")'"

printf '\n=== -R sulla riga di comando vince sul cwd ===\n'
o="$(run "$R2" pr list -R Roberdan/roberdan-os)"
[ "$(_dir "$o")" = "$TMP/cfg-roberdan" ] && ok "dentro un repo microsoft, -R Roberdan/... usa Roberdan" \
                                         || err "-R ignorato: '$(_dir "$o")'"
o="$(run "$R1" pr list --repo=microsoft/x)"
[ "$(_dir "$o")" = "$TMP/cfg-microsoft" ] && ok "anche nella forma --repo=proprietario/nome" \
                                          || err "--repo= ignorato: '$(_dir "$o")'"

printf '\n=== (b) FALLISCE APERTO: tutti i casi in cui non deve toccare niente ===\n'
NOREPO="$TMP/vuoto"; mkdir -p "$NOREPO"
o="$(run "$NOREPO" api user)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "fuori da un repo -> gh vero invariato" \
                                 || err "fuori da un repo ha imposto '$(_dir "$o")'"

R3="$(mkrepo altrove git@gitlab.com:tizio/x.git)"
o="$(run "$R3" api user)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "remote non GitHub -> gh vero invariato" \
                                 || err "remote gitlab ha imposto '$(_dir "$o")'"

R4="$(mkrepo sconosciuto git@github.com:tizio-mai-visto/x.git)"
o="$(run "$R4" api user)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "proprietario non in mappa -> gh vero invariato (nessuna wildcard)" \
                                 || err "proprietario sconosciuto ha imposto '$(_dir "$o")'"

rm -f "$TMP/cfg-roberdan/hosts.yml"
o="$(run "$R1" api user)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "cartella in mappa ma non pronta -> gh vero invariato" \
                                 || err "cartella incompleta ha imposto '$(_dir "$o")'"
echo "github.com:" > "$TMP/cfg-roberdan/hosts.yml"

o="$(cd "$R1" && PATH="$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/map.conf" RDA_GH_SHIM_OFF=1 bash "$SHIM" api user 2>&1)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "interruttore RDA_GH_SHIM_OFF=1 -> gh vero invariato" \
                                 || err "l'interruttore non spegne lo shim"

o="$(cd "$R1" && PATH="$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/map.conf" GH_CONFIG_DIR="$TMP/scelta-mia" bash "$SHIM" api user 2>&1)"
[ "$(_dir "$o")" = "$TMP/scelta-mia" ] && ok "GH_CONFIG_DIR gia' scelto dal chiamante -> rispettato" \
                                       || err "ha sovrascritto la scelta del chiamante: '$(_dir "$o")'"

o="$(cd "$R1" && PATH="$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/map.conf" GH_TOKEN=finto bash "$SHIM" api user 2>&1)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "GH_TOKEN esplicito -> non tocca niente" \
                                 || err "con GH_TOKEN ha imposto '$(_dir "$o")'"

o="$(cd "$R1" && PATH="$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/mappa-che-non-esiste" bash "$SHIM" api user 2>&1)"
[ "$(_dir "$o")" = "<nessuna>" ] && ok "mappa assente -> gh vero invariato" \
                                 || err "senza mappa ha imposto '$(_dir "$o")'"

printf '\n=== non chiama mai se stesso ===\n'
mkdir -p "$TMP/selfbin"; ln -sf "$SHIM" "$TMP/selfbin/gh"
o="$(cd "$R1" && PATH="$TMP/selfbin:$TMP/fakebin:$PATH" RDA_GH_MAP="$TMP/map.conf" timeout 15 bash "$TMP/selfbin/gh" api user 2>&1)"; rc=$?
[ "$rc" -ne 124 ] && ok "invocato tramite il symlink installato, non ricorre (niente timeout)" \
                  || err "RICORSIONE: lo shim ha chiamato se stesso"
[ "$(_dir "$o")" = "$TMP/cfg-roberdan" ] && ok "e sceglie comunque la cartella giusta" \
                                         || err "tramite symlink ha scelto '$(_dir "$o")'"

[ "$FAIL" -eq 0 ] && { echo "test-gh-shim: PASS"; exit 0; }
echo "test-gh-shim: FAIL"; exit 1
