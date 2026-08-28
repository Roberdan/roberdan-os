#!/usr/bin/env bash
# test/test-new-area-check.sh — il quarto gate: il POSTO, non il contenuto.
#
# La prova che conta e' l'ultima sezione: la fixture del 2026-08-24 riprodotta SENZA nessun
# marcatore, con parole che nessuna denylist puo' avere e senza indirizzi dentro. Gli altri
# tre gate la lasciano passare — correttamente, hanno risposto alla loro domanda. Questo la
# ferma. Se un giorno quella sezione diventa verde su tutti e quattro, vuol dire che qualcuno
# ha reso questo gate ridondante e va riletto tutto, non "aggiustato" il test.
#
# Meta' delle asserzioni verificano che il gate LASCI PASSARE. Un guardiano che non puo' piu'
# aprirsi e' peggio di uno che non si chiude mai: blocca commit onesti, i commit onesti
# vengono forzati con --no-verify, e --no-verify qui spegne anche il leak-check.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/test/new-area-check.sh"

FAIL=0
section() { printf "\n=== %s ===\n" "$1"; }
ok()      { printf "  ok: %s\n" "$1"; }
err()     { printf "  FAIL: %s\n" "$1"; FAIL=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Un repo finto: il gate gira SEMPRE dentro il repo che controlla (`git rev-parse
# --show-toplevel`), quindi va provato su un repo suo, mai su questo.
R="$TMP/repo"; mkdir -p "$R"
( cd "$R" && git init -q -b main && git config user.email t@example.com && git config user.name t ) >/dev/null 2>&1
cp "$CHECK" "$R/new-area-check.sh"

_g() { ( cd "$R" && "$@" ) >/dev/null 2>&1; }

# Il repo "prima": due zone con storia vera, piu' il gate stesso.
mkdir -p "$R/docs" "$R/test"
echo "canone" > "$R/README.md"
echo "prosa" > "$R/docs/nota.md"
: > "$R/test/.new-area-ack"
_g git add -A
_g git commit -qm seed

# ---------------------------------------------------------------------------
section "un repo con la sua storia passa (il gate nasce VERDE)"
if out="$( cd "$R" && bash ./new-area-check.sh 2>&1 )"; then
  ok "repo pulito: esce 0 e lo dice ($(printf '%s' "$out" | head -1))"
else
  err "il gate e' rosso su un repo pulito — got: $out"
fi

section "un file dentro una zona che ha gia' storia passa"
echo "altra prosa" > "$R/docs/nota2.md"
_g git add docs/nota2.md
if out="$( cd "$R" && bash ./new-area-check.sh --staged 2>&1 )"; then
  ok "docs/ ha storia in HEAD: nessun allarme"
else
  err "falso positivo su una zona esistente — got: $out"
fi
_g git commit -qm nota2

section "modificare un file esistente non e' aprire una zona"
echo "cambiato" >> "$R/docs/nota.md"
_g git add docs/nota.md
if ( cd "$R" && bash ./new-area-check.sh --staged >/dev/null 2>&1 ); then
  ok "una M non e' una A: il gate guarda solo cio' che viene AGGIUNTO"
else
  err "il gate ha bloccato una semplice modifica"
fi
_g git checkout -- docs/nota.md; _g git reset

# ---------------------------------------------------------------------------
# LA FIXTURE: il 2026-08-24, spogliato di ogni cosa che gli altri tre gate sanno leggere.
#
# Niente `visibility: private`, niente firma del generatore, niente indirizzi, niente nomi
# che una denylist possa avere in lista. Solo tre file in tre posti dove nessuno e' mai
# stato. E' il caso peggiore per gli altri tre e il caso normale per questo.
_deposito_muto() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
---
type: note
title: Nota
---

## Appunti

- una riga qualunque, senza marcatori e senza indirizzi
- il margine della commessa e' 41 e il PR di riferimento e' 118
EOF
}

section "LA FIXTURE 2026-08-24: tre zone mai aperte, depositate da un tool, prese da add -A"
_deposito_muto "$R/people/tizio.md"
_deposito_muto "$R/projects/commessa.md"
_deposito_muto "$R/claude-code/hooks/guard.md"
_g git add -A
if out="$( cd "$R" && bash ./new-area-check.sh --staged 2>&1 )"; then
  err "IL CASO DEL 2026-08-24 E' PASSATO — il gate non serve a niente"
else
  ok "bloccato (uscita 1)"
  for z in people projects claude-code; do
    printf '%s' "$out" | grep -q "$z" \
      && ok "l'errore nomina la zona $z" \
      || err "l'errore non nomina $z — got: $out"
  done
  printf '%s' "$out" | grep -q "41" \
    && err "il gate ha stampato il CONTENUTO del file: ha spostato la fuga, non fermata" \
    || ok "non stampa niente del contenuto"
fi

section "la logica non nomina nessuna cartella, nessun tool, nessun marcatore"
# E' il requisito letterale della card 260824-182954, e va verificato sul CODICE, non
# sull'intenzione: si guarda lo script senza i commenti, che invece il caso lo raccontano.
_codice() { grep -vE '^[[:space:]]*#' "$CHECK"; }
for parola in people projects claude-code orgs gbrain visibility; do
  if _codice | grep -qi "$parola"; then
    err "la logica nomina '$parola': e' di nuovo una lista di nomi"
  else
    ok "la logica non nomina '$parola'"
  fi
done

section "la deroga esiste, costa una riga, e si vede in un diff"
printf 'people\nprojects\nclaude-code\n' > "$R/test/.new-area-ack"
mkdir -p "$R/test"
_g git add -A
if ( cd "$R" && bash ./new-area-check.sh --staged >/dev/null 2>&1 ); then
  ok "tre righe riconoscono le tre zone: il gate si riapre"
else
  err "la deroga non funziona: un gate che non si riapre viene aggirato"
fi

section "la deroga e' esatta, non un glob"
printf '*\n' > "$R/test/.new-area-ack"
if ( cd "$R" && bash ./new-area-check.sh --staged >/dev/null 2>&1 ); then
  err "'*' ha aperto tutto: la deroga e' una porta, non un'eccezione"
else
  ok "'*' non vale come deroga"
fi
printf 'people\nprojects\nclaude-code\n' > "$R/test/.new-area-ack"
_g git add -A
_g git commit -qm "apri le tre zone di proposito"

section "una volta che la zona ha storia, la deroga non serve piu'"
: > "$R/test/.new-area-ack"
_deposito_muto "$R/people/caio.md"
_g git add -A
if ( cd "$R" && bash ./new-area-check.sh --staged >/dev/null 2>&1 ); then
  ok "people/ ha storia in HEAD: passa da sola, l'ack non si accumula"
else
  err "l'ack file dovrebbe potersi svuotare quando la zona e' nata"
fi
_g git commit -qm caio

section "anche un file depositato in RADICE e' un posto che nessuno ha aperto"
_deposito_muto "$R/roberto.md"
_g git add -A
if ( cd "$R" && bash ./new-area-check.sh --staged >/dev/null 2>&1 ); then
  err "un deposito in radice e' passato solo perche' non ha una cartella"
else
  ok "bloccato anche senza cartella"
fi
_g git reset; rm -f "$R/roberto.md"

section "in modalita' repo vede anche i NON TRACCIATI (prima del commit, non dopo)"
_deposito_muto "$R/meetings/2026-08-24.md"
if ( cd "$R" && bash ./new-area-check.sh >/dev/null 2>&1 ); then
  err "una zona nuova non tracciata e' invisibile: se ne accorgerebbe solo a commit fatto"
else
  ok "una nota appena deposta e ancora untracked viene vista"
fi

section "cio' che git ignora non e' un falso positivo"
# La regola di esclusione va in .git/info/exclude e non in un .gitignore: un .gitignore
# nuovo sarebbe esso stesso un file mai visto in radice, e il gate lo segnalerebbe — cosa
# giusta che qui falserebbe la misura.
echo "meetings/" >> "$R/.git/info/exclude"
if ( cd "$R" && bash ./new-area-check.sh >/dev/null 2>&1 ); then
  ok "ignorato = non segnalato"
else
  err "il gate segnala roba ignorata: diventerebbe rumore e verrebbe spento"
fi
rm -rf "$R/meetings"; : > "$R/.git/info/exclude"

# ---------------------------------------------------------------------------
# LA PROVA CHE GIUSTIFICA L'ESISTENZA DEL GATE.
section "sulla stessa fixture, gli altri gate passano — questo e' l'unico che la prende"
P="$ROOT/test/private-marker-check.sh"
D="$ROOT/test/directory-dump-check.sh"
S="$TMP/muto"; mkdir -p "$S"
( cd "$S" && git init -q -b main && git config user.email t@example.com && git config user.name t ) >/dev/null 2>&1
echo x > "$S/README.md"
( cd "$S" && git add README.md && git commit -qm seed ) >/dev/null 2>&1
_deposito_muto "$S/people/tizio.md"
( cd "$S" && git add -A ) >/dev/null 2>&1

if [ -f "$P" ]; then
  cp "$P" "$S/p.sh"
  if ( cd "$S" && bash ./p.sh --staged >/dev/null 2>&1 ); then
    ok "private-marker-check: PASSA (nessun marcatore da leggere) — come previsto"
  else
    err "private-marker-check ha bloccato una fixture senza marcatori: allora legge altro"
  fi
else
  err "manca $P: non posso dimostrare che il buco esiste"
fi

if [ -f "$D" ]; then
  cp "$D" "$S/d.sh"
  if ( cd "$S" && bash ./d.sh --staged >/dev/null 2>&1 ); then
    ok "directory-dump-check: PASSA (nessun indirizzo, nessun ruolo) — come previsto"
  else
    err "directory-dump-check ha bloccato una fixture senza rubrica: allora legge altro"
  fi
else
  err "manca $D: non posso dimostrare che il buco esiste"
fi

cp "$CHECK" "$S/n.sh"
if ( cd "$S" && bash ./n.sh --staged >/dev/null 2>&1 ); then
  err "e nemmeno il quarto la prende: la card non e' risolta"
else
  ok "new-area-check: BLOCCA. Il buco descritto nella card 260824-182954 e' chiuso."
fi

section "il gate e' agganciato dove serve (hook + validate), non solo scritto"
# Uno script perfetto che nessuno chiama e' una decorazione. Questa sezione e' la stessa di
# test-private-marker.sh, per la stessa ragione: il giorno in cui qualcuno riorganizza
# validate.sh o l'hook, il gate deve diventare rosso, non silenzioso.
if grep -q 'new-area-check.sh' "$ROOT/hooks/pre-commit"; then
  ok "hooks/pre-commit lo chiama"
else
  err "hooks/pre-commit non chiama il gate: esiste ma non protegge niente"
fi
if grep -rq 'new-area-check' "$ROOT/test/validate.sh" "$ROOT/test/validate-privacy.sh" 2>/dev/null; then
  ok "test/validate.sh lo chiama (direttamente o via il file che sorge)"
else
  err "test/validate.sh non chiama il gate"
fi
# Fail-closed: se il file sparisce, l'hook deve BLOCCARE, non proseguire in silenzio.
if grep -A2 '_area_check="\$ROOT/test/new-area-check.sh"' "$ROOT/hooks/pre-commit" | grep -q 'exit 1\|! -f'; then
  ok "l'hook fallisce chiuso se il gate manca (non lo salta in silenzio)"
else
  err "l'hook non fallisce chiuso: un gate mancante passerebbe per un commit pulito"
fi

section "la doc racconta il quarto gate e il suo limite"
DOC="$ROOT/docs/privacy-leak-check.md"
grep -q 'new-area-check' "$DOC" && ok "docs/privacy-leak-check.md lo descrive" || err "il gate non e' nella doc dei gate"
grep -qi 'quattro' "$DOC" && ok "la doc dice che i gate sono quattro" || err "la doc conta ancora tre gate"
grep -q 'new-area-check' "$ROOT/AGENTS.md" && ok "AGENTS.md § Privacy lo elenca" || err "AGENTS.md non lo elenca"

printf "\n"
[ "$FAIL" -eq 0 ] && { echo "test-new-area-check: tutto verde"; exit 0; }
echo "test-new-area-check: ci sono FAIL sopra"; exit 1
