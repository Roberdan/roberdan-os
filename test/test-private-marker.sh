#!/usr/bin/env bash
# test/test-private-marker.sh — il gate che rifiuta i file che si dichiarano privati.
#
# Meta' di queste asserzioni verificano che il gate LASCI PASSARE. Un guardiano che non puo'
# piu' aprirsi e' peggio di uno che non si chiude mai: blocca commit onesti, e un gate che
# blocca commit onesti viene disattivato — e disattivarlo qui vuol dire disattivare anche il
# leak-check che sta nello stesso hook. E' la stessa lezione gia' scritta in
# directory-dump-check.sh ("un guardiano rosso all'arrivo viene aggirato entro un giorno").
#
# Il caso vero che l'ha fatto nascere: 2026-08-24, `git add -A` in questo repo PUBBLICO ha
# messo in commit due note generate da gbrain marcate `visibility: private`. Non sono uscite
# solo perche' il push non era stato ancora dato.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/test/private-marker-check.sh"

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Un repo finto: il gate gira SEMPRE dentro il repo che sta controllando (usa
# `git rev-parse --show-toplevel`), quindi va provato su un repo suo, mai su questo.
R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q -b main && git config user.email t@example.com && git config user.name t ) >/dev/null 2>&1
cp "$CHECK" "$R/private-marker-check.sh"

_facts() { # $1=file  $2=visibility
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
type: person
title: Tizio
---

## Facts

<!--- gbrain:facts:begin -->
| # | claim | kind | confidence | visibility | notability | valid_from | valid_until | source | context |
|---|-------|------|------------|------------|------------|------------|-------------|--------|---------|
| 1 | un fatto qualsiasi | fact | 1.0 | $2 | high | 2026-08-24 |  | sync:import |  |
<!--- gbrain:facts:end -->
EOF
}

# ---------------------------------------------------------------------------
section "un repo senza niente di generato passa (il gate nasce VERDE)"
echo "canone normale" > "$R/README.md"
( cd "$R" && git add README.md private-marker-check.sh && git commit -qm seed ) >/dev/null 2>&1
if out="$( cd "$R" && bash ./private-marker-check.sh 2>&1 )"; then
  ok "repo pulito: esce 0 e lo dice ($(printf '%s' "$out" | head -1))"
else
  err "il gate e' rosso su un repo pulito — got: $out"
fi

section "un file marcato visibility: private viene rifiutato"
_facts "$R/people/tizio.md" private
( cd "$R" && git add -f people/tizio.md ) >/dev/null 2>&1
out="$( cd "$R" && bash ./private-marker-check.sh --staged 2>&1 )"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'people/tizio.md'; then
  ok "il file private in indice blocca il commit e viene nominato"
else
  err "un file marcato private non e' stato fermato (rc=$rc) — got: $out"
fi

# Il messaggio deve dire cosa fare, non solo che c'e' un problema: un errore che non porta
# a un'azione produce `--no-verify`, che spegne anche il leak-check nello stesso hook.
if printf '%s' "$out" | grep -q 'git rm --cached' && printf '%s' "$out" | grep -q '.gitignore'; then
  ok "il messaggio dice come uscirne (git rm --cached + .gitignore)"
else
  err "il messaggio non indica una via d'uscita — got: $out"
fi

# ...e NON deve incollare il contenuto: un guardiano che stampa il segreto lo ha spostato.
if ! printf '%s' "$out" | grep -q 'un fatto qualsiasi'; then
  ok "il contenuto privato non viene ristampato nel messaggio d'errore"
else
  err "il gate ha incollato il fatto privato nel proprio output — got: $out"
fi

section "la dichiarazione si rispetta in ENTRAMBE le direzioni: public passa"
( cd "$R" && git rm -q --cached people/tizio.md && rm -rf people ) >/dev/null 2>&1
_facts "$R/docs/pubblico.md" public
( cd "$R" && git add -f docs/pubblico.md ) >/dev/null 2>&1
out="$( cd "$R" && bash ./private-marker-check.sh --staged 2>&1 )"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'docs/pubblico.md'; then
  ok "una tabella gbrain viene comunque segnalata (e' un contenitore di roba generata)"
else
  err "una tabella generata non e' stata notata affatto (rc=$rc) — got: $out"
fi
# ...ma il MOTIVO non deve essere "private": quello sarebbe il gate che ignora cio' che legge.
if ! printf '%s' "$out" | grep -q 'marcate visibility: private'; then
  ok "su un file public il motivo non e' 'private' — la dichiarazione viene letta davvero"
else
  err "un file public e' stato accusato di essere private — got: $out"
fi

section "un file scritto a mano che PARLA di privacy non viene toccato"
# La differenza fra leggere un marcatore e cercare una parola. Questo file dice 'private'
# in prosa: se il gate lo fermasse, diventerebbe un divieto di usare la parola, e il primo
# a saltare sarebbe questo repo, che di privacy scrive in continuazione.
cat > "$R/docs/prosa.md" <<'EOF'
# Privacy

Il dossier confidenziale vive solo in ~/.roberdan-os/private/ e non entra mai in git.
La colonna visibility di una tabella puo' valere private oppure public.
EOF
( cd "$R" && git add -f docs/prosa.md ) >/dev/null 2>&1
out="$( cd "$R" && bash ./private-marker-check.sh --staged 2>&1 )"
if ! printf '%s' "$out" | grep -q 'docs/prosa.md'; then
  ok "prosa che nomina 'private' non viene scambiata per un file generato"
else
  err "il gate ha fermato un documento scritto a mano che parla di privacy — got: $out"
fi

section "l'esenzione e' un file che si legge, e non e' una porta aperta"
# Il gate ha bloccato il proprio test al primo giro: quel file costruisce una nota finta,
# ed e' il suo mestiere. La deroga esiste, ma deve costare una riga visibile in un diff.
_AL="$R/allow"
# indice pulito: i fixture delle sezioni precedenti sono ancora in staging e verrebbero
# contati qui, facendo fallire l'asserzione per un file che non c'entra.
( cd "$R" && git rm -q --cached docs/pubblico.md docs/prosa.md ) >/dev/null 2>&1
_facts "$R/people/tizio2.md" private
( cd "$R" && git add -f people/tizio2.md ) >/dev/null 2>&1
printf 'people/tizio2.md\n' > "$_AL"
if ( cd "$R" && PRIVATE_MARKER_ALLOW="$_AL" bash ./private-marker-check.sh --staged >/dev/null 2>&1 ); then
  ok "un percorso elencato nell'allow-file passa"
else
  err "l'allow-file non esenta il percorso che elenca"
fi
# ...ma un glob NON deve valere come esenzione, altrimenti `test/*` apre tutto.
printf 'people/*\n' > "$_AL"
if ! ( cd "$R" && PRIVATE_MARKER_ALLOW="$_AL" bash ./private-marker-check.sh --staged >/dev/null 2>&1 ); then
  ok "un glob nell'allow-file non esenta niente (solo percorsi esatti)"
else
  err "un glob e' stato accettato come esenzione: l'allow-file e' una porta aperta"
fi
# ...e un allow-file assente non deve spegnere il gate.
if ! ( cd "$R" && PRIVATE_MARKER_ALLOW="$R/non-esiste" bash ./private-marker-check.sh --staged >/dev/null 2>&1 ); then
  ok "senza allow-file il gate controlla tutto (non fallisce aperto)"
else
  err "un allow-file mancante ha spento il gate"
fi
( cd "$R" && git rm -q --cached people/tizio2.md && rm -f people/tizio2.md ) >/dev/null 2>&1

# Il gate reale di QUESTO repo non deve esentare piu' di quello che serve: due file, i suoi.
_real_allow="$ROOT/test/.private-marker-allow"
_n="$(grep -vcE '^[[:space:]]*(#|$)' "$_real_allow" 2>/dev/null || echo 0)"
if [ -f "$_real_allow" ] && [ "$_n" -le 2 ]; then
  ok "l'allow-file di questo repo elenca $_n percorsi (il controllo e il suo test)"
else
  err "l'allow-file di questo repo e' cresciuto a $_n percorsi: le deroghe vanno discusse"
fi

section "il gate e' agganciato dove serve (hook + validate), non solo scritto"
if grep -q 'private-marker-check.sh' "$ROOT/hooks/pre-commit"; then
  ok "hooks/pre-commit lo chiama"
else
  err "hooks/pre-commit non chiama il gate: esiste ma non protegge niente"
fi
# validate.sh ha estratto i quattro gate in test/validate-privacy.sh (era al limite delle 300
# righe). La domanda vera non e' "in quale file sta la riga" ma "girando validate.sh, il gate
# parte?": si guarda validate.sh PIU' i file che sorgono da li'.
if grep -rq 'private-marker-check.sh' "$ROOT/test/validate.sh" "$ROOT/test/validate-privacy.sh" 2>/dev/null; then
  ok "test/validate.sh lo chiama (direttamente o via il file che sorge)"
else
  err "test/validate.sh non chiama il gate"
fi
# Fail-closed: se il file sparisce, l'hook deve BLOCCARE, non proseguire in silenzio.
if grep -A2 '_priv_check="\$ROOT/test/private-marker-check.sh"' "$ROOT/hooks/pre-commit" | grep -q 'exit 1\|! -f'; then
  ok "l'hook fallisce chiuso se il gate manca (non lo salta in silenzio)"
else
  err "l'hook non gestisce il caso 'gate mancante' — un check che non parte legge come verde"
fi

section "una nota NON TRACCIATA viene vista (e' lo stato normale di una nota generata)"
# Le sezioni precedenti lasciano in giro fixture che il gate segnala di suo (una tabella
# gbrain, anche `public`, resta un contenitore di roba generata). Si riparte da pulito,
# altrimenti questa sezione misura il rumore di quelle sopra invece della sua proprieta'.
( cd "$R" && git rm -q --cached docs/pubblico.md >/dev/null 2>&1 || true; rm -rf docs people projects orgs )
if ( cd "$R" && bash ./private-marker-check.sh >/dev/null 2>&1 ); then :; else
  err "il repo di prova non riparte verde: le asserzioni qui sotto misurerebbero altro"
fi
_facts "$R/orgs/acme.md" private
if out="$( cd "$R" && bash ./private-marker-check.sh 2>&1 )"; then
  err "una nota untracked col marcatore passa: il gate se ne accorgerebbe solo a commit fatto"
else
  ok "presa da untracked: $(printf '%s' "$out" | grep -c 'orgs/acme.md') riga/e la nominano"
fi

# ...ma il .gitignore va rispettato, altrimenti il rinforzo qui sopra diventa un falso
# positivo per chiunque abbia una cartella legittimamente ignorata.
( cd "$R" && echo "ignorata/" > .gitignore )
mkdir -p "$R/ignorata"; _facts "$R/ignorata/x.md" private
rm -f "$R/orgs/acme.md"
if ( cd "$R" && bash ./private-marker-check.sh >/dev/null 2>&1 ); then
  ok "un file dentro una cartella ignorata non e' un falso positivo (--exclude-standard)"
else
  err "il gate ignora il .gitignore: ogni cartella ignorata diventa un falso positivo"
fi
rm -rf "$R/ignorata" "$R/orgs"; ( cd "$R" && rm -f .gitignore )

section "le cartelle di gbrain NON sono ignorate da questo repo — e' una scelta"
# La prima versione le elencava nel .gitignore. Sbagliato: si ignora cio' che ha diritto di
# stare nell'albero e non va versionato. Queste li' non ci devono stare per niente, e
# ignorarle le rendeva invisibili in `git status` senza renderle piu' sicure. La casa vera
# e' ~/.roberdan-os/private/brain, fuori da git; se ricompaiono qui e' un bug DA VEDERE.
for d in people/ projects/ orgs/ claude-code/; do
  if grep -qE "^$d\$" "$ROOT/.gitignore"; then
    err ".gitignore elenca $d — la rende invisibile in git status senza renderla sicura"
  else
    ok "$d non e' ignorata: se ricompare, si vede"
  fi
done
if grep -q 'roberdan-os/private/brain' "$ROOT/.gitignore"; then
  ok ".gitignore dice DOVE devono stare invece"
else
  err ".gitignore toglie l'elenco senza dire dov'e' la casa: resta solo un divieto"
fi
if grep -q 'roberdan-os/private/brain' "$CHECK"; then
  ok "il messaggio d'errore del gate indirizza alla casa giusta"
else
  err "il gate dice cosa NON fare senza dire dove spostarlo"
fi

section "la casa del cervello privato e' fuori da git — e ci deve restare"
# QUESTA e' la proprieta' che fa il lavoro. Non il nome della cartella, non il .gitignore:
# il fatto che nessun `git add` possa raggiungerla perche' non esiste nessun repo sopra di
# lei. Se un giorno smette di essere vera, tutto il resto e' decorazione.
#
# E c'e' una trappola precisa che la renderebbe falsa in buona fede: `gbrain sources status`
# stampa "⚠ default: never synced — run gbrain sync --source default", ma quel comando li'
# dentro fallisce con "Not inside a git repository". La correzione ovvia a quell'errore e'
# `git init`. Sarebbe la mossa sbagliata, fatta per la ragione giusta — ed e' esattamente
# il tipo di errore che una riga di prosa non ferma e un'asserzione si'.
# Il comando giusto per quella sorgente e' `gbrain import`, che non vuole git ed e'
# additivo (misurato: 354 -> 357 pagine, nessuna cancellata).
# La regola in una funzione, cosi' si puo' provare che sa dire NO e non solo SI'.
_fuori_da_git() { ! git -C "$1" rev-parse --show-toplevel >/dev/null 2>&1; }

BRAIN_HOME="${PRIVATE_BRAIN_HOME:-$HOME/.roberdan-os/private/brain}"
if [ ! -d "$BRAIN_HOME" ]; then
  # Clone spoglio, CI, altra macchina: non c'e' niente da proteggere, e un test che
  # fallisce dove la cosa non esiste insegna solo a ignorarlo.
  ok "casa non presente su questa macchina: niente da verificare (skip onesto)"
elif ! _fuori_da_git "$BRAIN_HOME"; then
  top="$(git -C "$BRAIN_HOME" rev-parse --show-toplevel 2>/dev/null)"
  err "$BRAIN_HOME e' dentro un repo git ($top): un git add puo' raggiungere le note private. Se e' stato fatto per zittire l'avviso 'never synced', il comando giusto e' 'gbrain import', non 'gbrain sync'."
else
  ok "fuori da qualsiasi worktree git: nessun commit puo' raggiungerla"
fi
# Direzione opposta: un controllo che non sa fallire non protegge niente. `$R` E' un repo
# git, quindi la regola deve rifiutarlo. Senza questa riga, un `_fuori_da_git` rotto che
# risponde sempre "va bene" passerebbe come verde per sempre.
if _fuori_da_git "$R"; then
  err "la regola non riconosce una cartella DENTRO un repo git: e' verde qualunque cosa succeda"
else
  ok "la regola sa dire di no: una cartella dentro un repo git viene riconosciuta"
fi

if grep -q 'gbrain import' "$ROOT/docs/privacy-leak-check.md"; then
  ok "la doc dice quale comando usare al posto di 'gbrain sync' (la trappola e' scritta)"
else
  err "la doc non nomina 'gbrain import': l'avviso di gbrain resta un invito a fare git init"
fi

if [ "$FAIL" -eq 0 ]; then printf "\ntest-private-marker: ✅ ALL GREEN\n"; else printf "\ntest-private-marker: ❌ FAIL (see above)\n"; fi
exit "$FAIL"
