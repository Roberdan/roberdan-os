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

# claude: solo le 3 skill roberdan-os che si sa NON collidere con un altro sistema di skill
# (gstack ne vende 'review' e 'ship' con lo stesso nome — documentato, apposta non asserito).
if [ -d "$HOME/.claude" ]; then
  for s in auto-checkpoint sync verify-done; do
    _lnk="$HOME/.claude/skills/$s/SKILL.md"
    if [ -e "$_lnk" ] && readlink "$_lnk" 2>/dev/null | grep -q "roberdan-os/platforms/"; then
      ok "claude skill '$s' wired (symlink resolves into roberdan-os platforms/)"
    elif [ -e "$_lnk" ]; then
      err "claude skill '$s' exists but is NOT the roberdan-os symlink (foreign same-name skill?) — $REMEDIATE"
    else
      err "claude skill '$s' missing at $_lnk — $REMEDIATE"
    fi
  done
else
  printf "  skip: claude not installed (no ~/.claude)\n"
fi

# copilot: tutte e 8 le skill roberdan-os + gbrain dentro il suo mcp-config.json.
if [ -d "$HOME/.copilot" ]; then
  for s in auto-checkpoint focus-group premortem problem-validation review ship sync verify-done; do
    _lnk="$HOME/.copilot/skills/$s/SKILL.md"
    if [ -e "$_lnk" ] && readlink "$_lnk" 2>/dev/null | grep -q "roberdan-os/platforms/"; then
      ok "copilot skill '$s' wired (symlink resolves into roberdan-os platforms/)"
    elif [ -e "$_lnk" ]; then
      err "copilot skill '$s' exists but is NOT the roberdan-os symlink (foreign same-name skill?) — $REMEDIATE"
    else
      err "copilot skill '$s' missing at $_lnk — $REMEDIATE"
    fi
  done
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
