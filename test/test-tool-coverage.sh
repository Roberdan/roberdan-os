#!/usr/bin/env bash
# test-tool-coverage.sh — per ogni strumento RILEVATO come installato su QUESTA macchina,
# verifica che il suo artefatto di cablaggio esista ancora.
#
# Il cablaggio marcisce in silenzio: Roberto reinstalla Copilot, cancella un puntatore, aggiorna
# un tool — e nessuno se ne accorge. E' la famiglia "sembra cablato ma non ha mai girato"
# (eval/tasks/12): la definizione c'e', il chiamante vivo no.
#
# Uno strumento NON installato e' uno skip pulito, mai un FAIL: su un clone fresco o su una
# macchina di CI senza niente installato questo file non deve dire nulla. E' anche il motivo per
# cui non puo' essere un test hermetico con fixture finte — misura la macchina vera, ed e'
# esattamente cio' che deve fare.
#
# Estratto da test/validate.sh il 2026-07-31 (era la sezione piu' grossa scritta dentro il gate,
# 114 righe su 623). Da qui si lancia anche da solo: `bash test/test-tool-coverage.sh`, che
# prima non si poteva — bisognava aspettare tre minuti e mezzo di suite intera per leggere
# queste righe.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
err() { printf "  FAIL: %s\n" "$1"; FAIL=1; }
ok()  { printf "  ok: %s\n" "$1"; }
REMEDIATE="run: bash bin/sync.sh --install"

# L'elenco delle skill del canon e' DERIVATO da skills/*/skill.md, non scritto a mano: una skill
# nuova entra nel gate da sola invece di aspettare che qualcuno si ricordi di aggiungerla qui.
#
# Fino al 2026-08-02 per claude erano elencate a mano solo 3 su 9, con la motivazione che 'ship' e
# 'review' collidevano con le omonime di gstack. Effetto misurato dal /doctor di quel giorno: il
# gate diceva PASS mentre 7 skill su 9 non erano raggiungibili in Claude Code — 2 puntavano alle
# skill di gstack, 3 erano copie statiche congelate di un sync.sh vecchio, 7 erano spente in
# skillOverrides. Un gate che si puo' soddisfare senza fare il lavoro e' peggio di nessun gate:
# rules/best-practices.md § No False Done, punto 3. La collisione e' stata risolta ripuntando i
# symlink al canon, quindi la restrizione non ha piu' ragione di esistere.
CANON_SKILLS="$(cd "$ROOT/skills" 2>/dev/null && for d in */; do [ -f "$d/skill.md" ] && printf '%s ' "${d%/}"; done)"
# Se la derivazione si rompe l'elenco resta vuoto e il gate passerebbe senza asserire NIENTE —
# esattamente il difetto che questo file esiste per impedire. Quindi vuoto = FAIL, non skip.
[ -n "${CANON_SKILLS// /}" ] || err "nessuna skill trovata in $ROOT/skills/ — la derivazione dell'elenco e' rotta e il gate non starebbe verificando nulla"

# Un solo controllo per tutti i tool: stessa forma di cablaggio (symlink dentro platforms/),
# stesso elenco derivato, cosi' claude e copilot non possono divergere in silenzio.
check_skills_wired() { # <label> <skills-dir>
  local label="$1" dir="$2" s _lnk
  for s in $CANON_SKILLS; do
    _lnk="$dir/$s/SKILL.md"
    if [ -e "$_lnk" ] && readlink "$_lnk" 2>/dev/null | grep -q "roberdan-os/platforms/"; then
      ok "$label skill '$s' wired (symlink resolves into roberdan-os platforms/)"
    elif [ -e "$_lnk" ]; then
      err "$label skill '$s' exists but is NOT the roberdan-os symlink (foreign same-name skill?) — $REMEDIATE"
    else
      err "$label skill '$s' missing at $_lnk — $REMEDIATE"
    fi
  done
}

if [ -d "$HOME/.claude" ]; then
  check_skills_wired claude "$HOME/.claude/skills"
else
  printf "  skip: claude not installed (no ~/.claude)\n"
fi

# copilot: le stesse skill del canon + gbrain dentro il suo mcp-config.json.
if [ -d "$HOME/.copilot" ]; then
  check_skills_wired copilot "$HOME/.copilot/skills"
  if [ -f "$HOME/.copilot/mcp-config.json" ]; then
    if grep -q "gbrain" "$HOME/.copilot/mcp-config.json" 2>/dev/null; then
      ok "copilot mcp-config.json has gbrain"
    else
      err "copilot mcp-config.json missing gbrain — add it manually (Copilot-owned file, sync.sh never writes it)"
    fi
  else
    printf "  skip: ~/.copilot/mcp-config.json not present yet (Copilot never run)\n"
  fi
  # agenti nativi copilot: ognuno symlinkato in ~/.copilot/agents. Il bersaglio si riconosce
  # dalla FORMA (…/platforms/copilot/agents/…) e non da un nome di cartella scritto a mano, cosi'
  # un'installazione da worktree o da fork (cartella non letteralmente "roberdan-os") resta
  # riconosciuta come davvero cablata.
  for ag in baccio board coach luca rex socrates thor twin wanda; do
    _agl="$HOME/.copilot/agents/$ag.md"
    if [ -L "$_agl" ] && readlink "$_agl" 2>/dev/null | grep -qE "/platforms/copilot/agents/"; then
      ok "copilot agent '$ag' wired (symlink resolves into a roberdan-os platforms/ checkout)"
    elif [ -e "$_agl" ]; then
      err "copilot agent '$ag' exists but is NOT a roberdan-os symlink (foreign same-name agent?) — $REMEDIATE"
    else
      err "copilot agent '$ag' missing at $_agl — $REMEDIATE"
    fi
  done
  # estensione nativa copilot: symlink in ~/.copilot/extensions/roberdan-os.
  _extl="$HOME/.copilot/extensions/roberdan-os/extension.mjs"
  if [ -L "$_extl" ] && readlink "$_extl" 2>/dev/null | grep -qE "/platforms/copilot/extension/"; then
    ok "copilot extension wired (symlink resolves into a roberdan-os platforms/ checkout)"
  elif [ -e "$_extl" ]; then
    err "copilot extension exists but is NOT a roberdan-os symlink — $REMEDIATE"
  else
    err "copilot extension missing at $_extl — $REMEDIATE"
  fi
else
  printf "  skip: copilot not installed (no ~/.copilot)\n"
fi

# codex: legge AGENTS.md nativamente — basta che il puntatore globale esista.
if [ -d "$HOME/.codex" ]; then
  if [ -s "$HOME/.codex/AGENTS.md" ]; then
    ok "codex pointer wired (~/.codex/AGENTS.md non-empty)"
  else
    err "codex pointer missing/empty at ~/.codex/AGENTS.md — $REMEDIATE"
  fi
else
  printf "  skip: codex not installed (no ~/.codex)\n"
fi

# opencode: legge AGENTS.md nativamente — rilevato dal binario O dalla cartella di config (la
# stessa rilevazione che usa sync.sh --install, cosi' gate e installer non si contraddicono).
if command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ]; then
  if [ -e "$HOME/.config/opencode/AGENTS.md" ]; then
    ok "opencode pointer wired (~/.config/opencode/AGENTS.md exists)"
  else
    err "opencode pointer missing at ~/.config/opencode/AGENTS.md — $REMEDIATE"
  fi
else
  printf "  skip: opencode not installed (command not found)\n"
fi

# tessuto di puntatori ~/GitHub: ha senso solo sulle macchine con il layout canonico — cioe'
# quando QUESTO repo sta sotto $HOME/GitHub. Su un runner di CI o con un altro layout la
# convenzione non si applica, quindi skip invece di FAIL (questo identico controllo ruppe la CI
# il 2026-07-03: il runner inciampava nella condizione $HOME/GitHub).
if [ "$(cd "$ROOT/.." 2>/dev/null && pwd)" = "$HOME/GitHub" ]; then
  if [ -f "$HOME/GitHub/AGENTS.md" ] && grep -q "roberdan-os" "$HOME/GitHub/AGENTS.md" 2>/dev/null; then
    ok "\$HOME/GitHub/AGENTS.md wired (mentions roberdan-os)"
  else
    err "\$HOME/GitHub/AGENTS.md missing or doesn't mention roberdan-os — $REMEDIATE"
  fi
else
  printf "  skip: repo not under \$HOME/GitHub (different layout, pointer convention n/a)\n"
fi

[ "$FAIL" -eq 0 ] && { echo "test-tool-coverage: PASS"; exit 0; }
echo "test-tool-coverage: FAIL"; exit 1
