#!/usr/bin/env bash
# gh-shim.sh — sceglie l'account GitHub dal REPO in cui sei, non da uno stato globale.
# Installato come ~/.local/bin/gh (symlink), che nel PATH viene prima di /opt/homebrew/bin.
# Quindi si digita `gh` normale: non c'e' niente da ricordarsi. Era il vincolo del twin —
# "un helper in bin/ che uno puo' scavalcare dimenticandosene" e' il difetto § Wired End-to-End.
#
# IL PROBLEMA (rilievo 3, 30 luglio 2026). Roberto ha due identita': `Roberdan` (personale) e
# `roberdan_microsoft` (Enterprise Managed User). `gh auth switch` scrive l'account attivo in una
# configurazione GLOBALE: quando una sessione cambia account, tutte le altre si ritrovano sotto
# quello sbagliato. Incidenti veri: due PR non create, un merge rifiutato, un 401 con credenziali
# valide, e un push che diceva "Repository not found" su un repo che esisteva — GitHub risponde
# 404 e non 403 a chi non e' autorizzato, apposta per non rivelare che il repo c'e'. Cioe'
# l'errore diceva letteralmente il contrario della verita', e la diagnosi naturale ("credenziali
# scadute") era falsa. Il piu' caro dei quattro e' il merge rifiutato: la sessione lo ha
# raccontato come fatto.
#
# LA SOLUZIONE. Niente stato globale: una cartella di configurazione per account
# (GH_CONFIG_DIR), scelta dal proprietario del remote. Due sessioni su due repo diversi usano
# due account nello stesso istante senza toccarsi.
#
# LA PROPRIETA' CHE LO RENDE SICURO: **fallisce APERTO**. Ogni caso che non sa gestire — fuori da
# un repo, remote non GitHub, proprietario non in mappa, cartella assente — lancia il gh vero
# INVARIATO. Uno shim su un comando che Roberto usa cento volte al giorno non puo' permettersi di
# essere l'anello che si rompe: al massimo non aiuta, mai impedisce.
set -u

# --- il gh VERO: il primo nel PATH che non sia questo file (mai ricorsione) ------------------
_self="$0"
case "$_self" in /*) ;; *) _self="$(command -v -- "$_self" 2>/dev/null || echo "$_self")" ;; esac
_self_real="$(cd "$(dirname "$_self")" 2>/dev/null && pwd -P)/$(basename "$_self")"
REAL=""
_ifs="$IFS"; IFS=:
for _p in $PATH; do
  [ -n "$_p" ] || continue
  _c="$_p/gh"
  [ -x "$_c" ] && [ ! -d "$_c" ] || continue
  _cr="$(cd "$(dirname "$_c")" 2>/dev/null && pwd -P)/gh"
  # salta sia questo file sia il symlink che lo punta
  [ "$_cr" = "$_self_real" ] && continue
  [ -L "$_c" ] && [ "$(cd "$(dirname "$_c")" && cd "$(dirname "$(readlink "$_c")")" 2>/dev/null && pwd -P)/$(basename "$(readlink "$_c")")" = "$_self_real" ] && continue
  REAL="$_c"; break
done
IFS="$_ifs"
# Ultima spiaggia: i posti noti, quando il PATH non contiene gh. Non e' teoria — git lancia i
# credential helper con l'ambiente che ha, e un helper che esce 127 non "non aiuta": blocca il
# push. Questo file promette di non essere mai l'anello che si rompe, e un PATH povero e' il
# modo piu' banale di romperlo. Restano esclusi questo stesso file e i symlink che lo puntano.
if [ -z "$REAL" ]; then
  for _c in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
    [ -x "$_c" ] && [ ! -d "$_c" ] || continue
    [ "$(cd "$(dirname "$_c")" 2>/dev/null && pwd -P)/gh" = "$_self_real" ] && continue
    REAL="$_c"; break
  done
fi
[ -n "$REAL" ] || { echo "gh-shim: non trovo il gh vero nel PATH" >&2; exit 127; }

# --- interruttori: chi ha gia' scelto, ha scelto --------------------------------------------
[ "${RDA_GH_SHIM_OFF:-0}" = "1" ] && exec "$REAL" "$@"

# GH_CONFIG_DIR gia' impostata sono DUE casi opposti, e confonderli era un difetto vero
# (30 luglio -> 20 agosto 2026): Roberto apre la sessione con `gh copilot`, questo shim risolve
# il repo e riparte con `exec env GH_CONFIG_DIR=...`, e da quel momento OGNI processo figlio —
# la sessione dell'agente, e tutto cio' che ci gira dentro — nasce con la variabile gia' messa.
# La regola "chi ha gia' scelto, ha scelto" scattava percio' sempre, e `gh` restava inchiodato
# all'account del PRIMO repo per il resto della sessione: dentro un repo personale usava
# l'account di lavoro, cioe' esattamente il rilievo 3 che questo file esiste per impedire.
# La distinzione: quando decide, lo shim firma la propria scelta in RDA_GH_SHIM_SET. Se ritrova
# la PROPRIA firma, quella variabile non e' la volonta' di nessuno — e' un residuo, si azzera e
# si ridecide da capo. Una variabile senza firma, o con una firma che non combacia, e' invece la
# scelta di un chiamante umano e resta intoccabile come prima.
if [ -n "${GH_CONFIG_DIR:-}" ]; then
  if [ "$GH_CONFIG_DIR" = "${RDA_GH_SHIM_SET:-}" ]; then
    unset GH_CONFIG_DIR RDA_GH_SHIM_SET
  else
    exec "$REAL" "$@"   # il chiamante ha gia' deciso
  fi
fi

[ -n "${GH_TOKEN:-}${GH_ENTERPRISE_TOKEN:-}" ] && exec "$REAL" "$@"  # token esplicito: non toccare

# --- 1. `-R owner/nome` sulla riga di comando vince sul cwd ----------------------------------
owner=""; prev=""
for a in "$@"; do
  case "$prev" in -R|--repo) owner="${a%%/*}"; break ;; esac
  case "$a" in --repo=*) owner="${a#--repo=}"; owner="${owner%%/*}"; break ;; esac
  prev="$a"
done

# --- 2. altrimenti il proprietario del remote origin del repo in cui siamo -------------------
if [ -z "$owner" ]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  case "$url" in
    *github.com*) o="${url#*github.com}"; o="${o#[:/]}"; owner="${o%%/*}" ;;
  esac
fi
[ -n "$owner" ] || exec "$REAL" "$@"

# --- 3. mappa proprietario -> cartella. Nessuna wildcard: cio' che non conosco non lo tocco. --
MAP="${RDA_GH_MAP:-$HOME/.roberdan-os/gh-accounts.conf}"
[ -f "$MAP" ] || exec "$REAL" "$@"
# `read -r o d` e NON `set -- $line`: set -- riscriverebbe "$@", cioe' gli argomenti che devo
# ancora passare a gh. Sarebbe un `gh pr list` trasformato in `gh` nudo, in silenzio.
dir=""
while read -r _o _d _rest; do
  case "$_o" in ''|\#*) continue ;; esac
  [ "$_o" = "$owner" ] && { dir="$_d"; break; }
done < "$MAP"
[ -n "$dir" ] || exec "$REAL" "$@"
case "$dir" in "~"/*) dir="$HOME/${dir#\~/}" ;; esac
[ -f "$dir/hosts.yml" ] || exec "$REAL" "$@"     # cartella non pronta: fallisci APERTO

exec env GH_CONFIG_DIR="$dir" RDA_GH_SHIM_SET="$dir" "$REAL" "$@"
