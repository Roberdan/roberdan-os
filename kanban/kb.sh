#!/usr/bin/env bash
# kb — fast, GATED kanban CLI for roberdan-os. Cards are files in todo/ doing/ done/.
# Gates: todo->doing needs Roberto approval; doing->done needs @thor validation + evidence.
# Every card carries a Definition of Done + Acceptance criteria. See kanban/README.md.
set -euo pipefail

RDA_HOME="${RDA_HOME:-$HOME/.roberdan-os}"
# repo ROOT (independent of $KB, which under tests points at a temp fixture
# dir) — needed so `kb plans`/`kb plan`/`kb sched` resolve docs/ and
# proposals/ from the real repo no matter what directory `kb` is invoked from.
#
# Resolve the symlink chain FIRST. `kb` is installed as ~/.local/bin/kb -> this
# file, and bash does not resolve symlinks for BASH_SOURCE: it reports the link
# path. So the naive `dirname "${BASH_SOURCE[0]}"/..` computed ~/.local on every
# PATH invocation — i.e. essentially always. Nothing crashed, because every
# consumer of $ROOT either fails soft or writes a directory into existence,
# which is why it survived from install until 2026-07-29:
#   - `kb lint` looked for ~/.local/kanban/lint-cards.sh and reported it missing
#     (the one loud symptom; filed 2026-07-07, never traced to its cause);
#   - RDA_LEAKCHECK pointed at a privacy check that was not there;
#   - the worktree calls swallow their own failure with `2>/dev/null || true`;
#   - and the fallback board `$ROOT/kanban` became ~/.local/kanban, which the
#     `mkdir -p` below duly CREATED — so 32 real cards accumulated on a board
#     nobody chose and no view aggregated.
# `pwd -P` would not have helped: the wrong path is the argument, not the way it
# is printed. Keep this ahead of every other use of $ROOT.
_kb_src="${BASH_SOURCE[0]}"
while [ -L "$_kb_src" ]; do
  _kb_dir="$(cd -P "$(dirname "$_kb_src")" && pwd)"
  _kb_src="$(readlink "$_kb_src")"
  case "$_kb_src" in /*) ;; *) _kb_src="$_kb_dir/$_kb_src" ;; esac
done
ROOT="$(cd -P "$(dirname "$_kb_src")/.." && pwd)"
unset _kb_src _kb_dir

# --- Federation read-path (design §2a/§2b) ---------------------------------
# The registry (~/.roberdan-os/kanban-registry, local-only, one repo path per
# line, written by `kb init`) is the source of truth for "which repos have a
# federated, privacy-initialized board". A blind filesystem scan cannot tell an
# initialized board (gitignored + leak-check) from a raw kanban/ dir made by
# hand (the MirrorBuddy hazard) — so discovery is the explicit registry, never a
# scan. Parsing degrades to empty, never crashes.
REGISTRY="${RDA_KANBAN_REGISTRY:-$RDA_HOME/kanban-registry}"
_registry_repos() {
  [ -f "$REGISTRY" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$REGISTRY" 2>/dev/null || true
}
_in_registry() {
  local p="$1" line
  while IFS= read -r line; do
    [ -n "$line" ] && [ "$line" = "$p" ] && return 0
  done < <(_registry_repos)
  return 1
}
# Board resolution (gbrain-pin style, design §2b):
#   RDA_KANBAN env  →  cwd's git repo IF it is roberdan-os itself OR registered
#                   →  else roberdan-os's own board (today's default — additive).
# KB_MATCHED=1: cwd resolved to a concrete recognized board (home or registered)
# or RDA_KANBAN was set. KB_MATCHED=0: we fell back — so the default `view`
# outside any recognized repo shows the aggregated board instead of home.
KB_MATCHED=0
KB=""
# Assigns the globals KB + KB_MATCHED directly (NOT via command substitution —
# a $(...) subshell would discard the KB_MATCHED assignment).
_resolve_kb() {
  # Compute the repo's OWN board first (registry-based), even when RDA_KANBAN is
  # set, so an override that silently diverges from it can be flagged. This is
  # the fix for the 2026-07-13 incident: a session exported RDA_KANBAN pointing
  # at an unrelated directory, and every `kb` call for days afterward wrote real
  # card content there instead of trading-os's own registered board — with zero
  # warning, discovered only when the board looked stale days later.
  local root natural=""
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ] && { [ "$root" = "$ROOT" ] || _in_registry "$root"; }; then
    natural="$root/kanban"
  fi
  if [ -n "${RDA_KANBAN:-}" ]; then
    KB_MATCHED=1; KB="$RDA_KANBAN"
    # A mismatch is only worth flagging when we're inside a repo that HAS its own
    # resolvable board — outside any such repo there is nothing to diverge from
    # (e.g. deliberate cross-repo aggregation use from a scratch directory).
    if [ -n "$natural" ] && [ "$KB" != "$natural" ]; then
      echo "kb: WARNING — RDA_KANBAN=$KB overrides this repo's own board ($natural)." >&2
      echo "kb:   Writes will NOT land in the repo's board. Unset RDA_KANBAN to use it." >&2
    fi
    return 0
  fi
  if [ -n "$natural" ]; then
    KB_MATCHED=1; KB="$natural"; return 0
  fi
  KB_MATCHED=0; KB="$ROOT/kanban"
}
_resolve_kb
mkdir -p "$KB/todo" "$KB/doing" "$KB/done"
cmd="${1:-view}"; [ $# -gt 0 ] && shift || true

# portable mtime (macOS BSD stat first, GNU stat fallback, else 0)
# GNU (-c) FIRST: on macOS `stat -c` fails cleanly (unknown flag → exit 1, empty stdout) so the
# BSD `-f` fallback runs; the reverse order breaks on Linux, where `stat -f` means --file-system
# and prints multi-line garbage for `%m`+file instead of failing (CI-only bug, seen 2026-07-06).
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
# unique repo roots for aggregation: roberdan-os home first, then registry entries.
_board_roots() {
  printf '%s\n' "$ROOT"
  _registry_repos | while IFS= read -r r; do
    [ -n "$r" ] && [ "$r" != "$ROOT" ] && printf '%s\n' "$r"
  done
}

_field() { grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//; s/^\"//; s/\"\$//"; }

# _repo_qui — COME SI CHIAMA il progetto in cui sto, anche da dentro un worktree.
#
# `basename $(git rev-parse --show-toplevel)` sembra la risposta e non lo e': dentro un worktree
# quel percorso e' `worktrees/<repo>/<card-id>`, quindi il "repo" risultava chiamarsi come la
# CARD. `kb pending` filtrava su un nome che nessuna card porta e mostrava zero righe; `kb queue`
# avrebbe fotografato una lista vuota. E il canone impone un worktree per card, cioe' il difetto
# colpiva esattamente dove il lavoro avviene.
#
# Quinta istanza in due giorni della stessa famiglia — il hook installato col percorso del
# worktree, `--git-dir` invece di `--git-path` in due file, il pre-commit inciso su un worktree
# rimosso. La forma e' sempre quella: **si chiede a git DOVE guarda, non si deduce dal cwd**.
# `--git-common-dir` punta sempre al `.git` del checkout principale, anche da un worktree.
_repo_qui() {
  local comune
  comune="$(git rev-parse --git-common-dir 2>/dev/null)" || { basename "$PWD"; return; }
  case "$comune" in /*) ;; *) comune="$PWD/$comune" ;; esac
  basename "$(dirname "$comune")"
}
# Shared regex for "bot authors" in PR views. Both kb.sh and tests consume this exact value.
_PR_BOT_FILTER_RE='dependabot|renovate|github-actions|\[bot\]|-bot$'
_pr_bot_filter_regex() { printf '%s\n' "$_PR_BOT_FILTER_RE"; }

# --- The done-gate's mechanical half (2026-07-13) --------------------------------
# Until now `kb finish --thor "<ev>"` accepted ANY non-empty string: `--thor ok`
# closed a card and stamped `verified_by: thor`. That is an honor-system gate, and
# best-practices.md § No False Done says the opposite ("prefer a mechanical gate
# over your own assurance; move the evidence OUT of your words"). The trading-os
# audit (2026-07-13) showed where that shape leads: its merge gate accepted
# `evidence.ci == "pass"` as a self-declared string, 40 PRs merged with no CI, and
# the product shipped 33 green cards while producing zero value.
#
# So the evidence must now RESOLVE to something that exists outside the sentence:
#   - a commit SHA that git can actually find (in any registered repo), or
#   - a PR/issue ref that gh can resolve, or
#   - a file path that exists, or
#   - real test/command output (a count of passed tests, a coverage number, OK/exit 0).
# A cited SHA that resolves NOWHERE is a hard refusal: that is forged evidence.
# This does not make @thor honest — it makes a *lie about an artifact* fail.
_evidence_denylist='^(ok|okay|done|fatto|fine|finito|tutto ok|tutto a posto|a posto|works|funziona|it works|should work|dovrebbe funzionare|lgtm|verified|verificato|passed|green|verde|yes|si|sì|completed|completato)\.?$'

_sha_resolves() {
  local sha="$1" repo
  git cat-file -e "${sha}^{commit}" 2>/dev/null && return 0
  while IFS= read -r repo; do
    [ -d "$repo/.git" ] || continue
    git -C "$repo" cat-file -e "${sha}^{commit}" 2>/dev/null && return 0
  done < <(_registry_repos)
  # The BOARD itself can be a git repo, and since 2026-07-28 this one is: the
  # cards are versioned in a private repo nested at kanban/, because the repo
  # that holds them is public and they carry real names and clients. That repo
  # is deliberately NOT in the registry — the registry lists boards, and adding
  # it there would make kb resolve a board inside a board.
  #
  # Without this line a REAL commit is refused as forged. Reproduced, not
  # deduced: `git cat-file -e a1c5f41` fails in the public repo and succeeds in
  # kanban/, and a1c5f41 is the commit that recorded @thor's certification.
  #
  # This does not widen the gate. The property stays "the sha must resolve to a
  # commit that exists on this machine" — the opposite of the trading-os failure
  # cited above, where `evidence.ci == "pass"` was accepted as a self-declared
  # string. A gate that refuses true evidence teaches people to cite weaker
  # evidence, which is how it ends up accepting strings again.
  [ -n "${KB:-}" ] && [ -d "$KB/.git" ] && \
    git -C "$KB" cat-file -e "${sha}^{commit}" 2>/dev/null && return 0
  return 1
}

_verify_evidence() {
  local ev="$1" lower anchors=0 sha
  lower="$(printf '%s' "$ev" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  if printf '%s' "$lower" | grep -qE "$_evidence_denylist"; then
    echo "REFUSED: '$ev' is a rubber-stamp, not evidence." >&2
    echo "  Cite something that EXISTS: a commit SHA, a PR (#123), a file path, or real test output." >&2
    return 1
  fi
  if [ "${#ev}" -lt 12 ]; then
    echo "REFUSED: evidence too thin ('$ev'). Cite a commit SHA, a PR, a file path, or test output." >&2
    return 1
  fi

  # A cited SHA that resolves nowhere = forged evidence. Hard fail.
  for sha in $(printf '%s' "$ev" | grep -oE '\b[0-9a-f]{7,40}\b' || true); do
    if _sha_resolves "$sha"; then
      anchors=$((anchors + 1))
    else
      echo "REFUSED: commit '$sha' does not resolve in any registered repo — evidence cites a commit that does not exist." >&2
      return 1
    fi
  done

  # A PR/issue ref must resolve too (skipped when gh is unavailable/offline).
  local pr
  for pr in $(printf '%s' "$ev" | grep -oE '#[0-9]+' | tr -d '#' || true); do
    if command -v gh >/dev/null 2>&1; then
      if gh pr view "$pr" --json state >/dev/null 2>&1 || gh issue view "$pr" --json state >/dev/null 2>&1; then
        anchors=$((anchors + 1))
      else
        echo "REFUSED: PR/issue #$pr does not resolve — evidence cites something that does not exist." >&2
        return 1
      fi
    fi
  done

  # An existing file path is a valid anchor.
  local tok
  for tok in $ev; do
    tok="${tok%,}"; tok="${tok%.}"
    [ -e "$tok" ] && anchors=$((anchors + 1))
  done

  # Real command/test output: a count, a coverage %, an explicit pass/fail line.
  printf '%s' "$lower" | grep -qE '([0-9]+[[:space:]]*(passed|passing|tests?|ok\b|assertions))|([0-9]+(\.[0-9]+)?%[[:space:]]*(coverage|cov))|(exit[[:space:]]*(code[[:space:]]*)?0)|(0[[:space:]]*(failed|failures|errors))|(receipt ok)|(checked=[0-9]+)' \
    && anchors=$((anchors + 1))

  if [ "$anchors" -eq 0 ]; then
    echo "REFUSED: evidence names nothing verifiable." >&2
    echo "  It must resolve to something outside the sentence: a commit SHA, a PR (#123)," >&2
    echo "  an existing file path, or real output (e.g. '148 passed', 'coverage 100%', 'exit 0')." >&2
    return 1
  fi
  return 0
}
# Portable in-place status edit: `sed -i ''` is BSD-only syntax (macOS) and breaks under
# GNU sed (Linux) — it treats the empty string as the script and the real script as a
# filename, dying with "No such file or directory". Redirect-to-temp-then-move works
# identically on both.
_set_status() {
  local f="$1" v="$2" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/rda-kb.XXXXXX")"
  sed "s/^status:.*/status: $v/" "$f" > "$tmp" && mv "$tmp" "$f"
}
_new_card_id() {
  local base="${1:?base id required}" id n=1
  id="$base"
  while [ -e "$KB/todo/$id.md" ] || [ -e "$KB/doing/$id.md" ] || [ -e "$KB/done/$id.md" ]; do
    id="${base}-${n}"
    n=$((n+1))
  done
  printf '%s' "$id"
}
_repo_tag() {
  # ASCII "-" (not an em-dash) for a missing repo: box cells are padded with printf %-*s,
  # which counts BYTES, so a multibyte glyph would shift that row's right border. Keep the
  # whole board ASCII (1 byte = 1 char = 1 cell) → alignment holds on any font/terminal.
  local repo; repo="$(_field "$1" repo)"
  printf '%s' "${repo:--}"
}
# board cells are id-first (the id is the key you pass to show/start/finish — it must
# never be truncated). Append " (repo)" only when it fits within the column's content
# width; otherwise degrade to the bare id rather than corrupt it. Full repo+title is
# always available via `kb list`/`kb show`.
_board_cell() {
  local f="$1" w="$2" id repo cell
  id="$(basename "$f" .md)"
  repo="$(_repo_tag "$f")"
  cell="$id ($repo)"
  if [ "${#cell}" -le "$w" ]; then printf '%s' "$cell"; else printf '%s' "$id"; fi
}
_list() {
  local c="$1" any=0 f
  for f in "$KB/$c"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    any=1
    printf '  [%s] (%s) %s\n' "$(basename "$f" .md)" "$(_repo_tag "$f")" "$(_field "$f" title)"
  done
  if [ "$any" -eq 0 ]; then echo "  (empty)"; fi
  return 0
}

# DONE (0) doesn't mean "nothing was ever done" — closed cards get periodically rolled up
# into _archive-*.md (audit trail, not loaded every session) and removed as individual files.
# Print a one-line pointer so a 0 count isn't mistaken for an empty history.
_archive_hint() {
  local f archives=()
  for f in "$KB/done"/_*.md; do [ -e "$f" ] && archives+=("$(basename "$f")"); done
  [ "${#archives[@]}" -eq 0 ] && return 0
  echo "  (past work archived in kanban/done/${archives[*]} — read on demand, not counted above)"
}

# visual kanban: three columns side by side. Default: the current-repo board ($KB). With
# --all: the SAME three-column shape but aggregated across every registered board (home +
# registry), each card still tagged with its repo: via _board_cell. This is what `kb all`
# and `kb` outside a repo render — a real kanban, not a flat list.
_board() {
  local W=34 f i bd
  local w=$((W-2))
  local -a boards=()
  if [ "${1:-}" = "--all" ]; then
    echo "=== AGGREGATED BOARD — active cards across all registered repos ==="
    while IFS= read -r bd; do
      [ -n "$bd" ] && [ -d "$bd/kanban" ] && boards+=("$bd/kanban")
    done < <(_board_roots)
  fi
  [ "${#boards[@]}" -eq 0 ] && boards=("$KB")
  local -a T=() D=() N=()
  for bd in "${boards[@]}"; do
    for f in "$bd/todo"/*.md;  do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; T+=("$(_board_cell "$f" "$w")"); done
    for f in "$bd/doing"/*.md; do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; D+=("$(_board_cell "$f" "$w")"); done
  done
  # done: newest 10 across ALL selected boards, by mtime desc (cross-repo when aggregated)
  local -a drows=()
  for bd in "${boards[@]}"; do
    for f in "$bd/done"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in _*) continue;; esac
      drows+=("$(_mtime "$f")|$f")
    done
  done
  local ntot=${#drows[@]}
  if [ "$ntot" -gt 0 ]; then
    while IFS='|' read -r _ f; do [ -n "$f" ] && N+=("$(_board_cell "$f" "$w")"); done \
      < <(printf '%s\n' "${drows[@]}" | sort -t'|' -k1,1 -rn | head -10)
  fi
  # archived goals: one numbered table row each in _archive-*.md (rolled-up history).
  # Pre-existing bug found while testing this function on a fixture with zero archive
  # files: the bare glob passed straight to grep/pipefail died under `set -e` when it
  # didn't match anything (grep tried to open the literal string "_archive-*.md",
  # failed, and pipefail propagated that failure into killing the whole script) — never
  # triggered on the real board because it always has at least one archive file. Loop
  # with an existence check instead, same convention as _archive_hint/_archive_cmd below.
  local narch=0 _af
  for bd in "${boards[@]}"; do
    for _af in "$bd/done"/_archive-*.md; do
      [ -e "$_af" ] || continue
      narch=$((narch + $(grep -cE '^\| [0-9]+ \|' "$_af" 2>/dev/null || true)))
    done
  done
  local done_label=" DONE ($ntot"
  [ "$narch" -gt 0 ] && done_label="$done_label +$narch arch"
  done_label="$done_label)"
  local nt=${#T[@]} nd=${#D[@]} nn=${#N[@]} rows
  rows=$nt; [ $nd -gt $rows ] && rows=$nd; [ $nn -gt $rows ] && rows=$nn
  [ $rows -eq 0 ] && rows=1
  local ln; ln="$(printf '─%.0s' $(seq 1 $W))"
  printf '┌%s┬%s┬%s┐\n' "$ln" "$ln" "$ln"
  # Header labels are ASCII-only (no emoji): emoji render 2 cells wide but printf counts them
  # as 1 (or as their byte length), so they'd desync the header's │ separators from the rows.
  printf '│%-*s│%-*s│%-*s│\n' $W " TO DO ($nt)" $W " DOING ($nd)" $W "$done_label"
  printf '├%s┼%s┼%s┤\n' "$ln" "$ln" "$ln"
  for ((i=0; i<rows; i++)); do
    printf '│ %-*.*s │ %-*.*s │ %-*.*s │\n' \
      $w $w "${T[$i]:-}" $w $w "${D[$i]:-}" $w $w "${N[$i]:-}"
  done
  printf '└%s┴%s┴%s┘\n' "$ln" "$ln" "$ln"

  # Legend: what each ACTIVE card (todo + doing) is — so the IDs in the box aren't opaque.
  # It lives BELOW the box because titles are long and may be non-ASCII, which would desync the
  # box's │ column separators if placed inside a fixed-width cell. Done cards are omitted (many,
  # and finished). Same board order as the columns above, so an ID is easy to look up.
  # When the dashboard follows (bare `kb`) it details every DOING card just below, so the legend
  # drops that column rather than printing each doing title twice.
  local _lf _legend=0 _lhdr="TO DO / DOING — cosa fa ogni card:"
  local -a _lcols=("todo" "doing")
  if [ "${KB_LEGEND_TODO_ONLY:-0}" = "1" ]; then
    _lcols=("todo"); _lhdr="TO DO — cosa fa ogni card (le DOING sono dettagliate sotto):"
  fi
  local _lc
  for bd in "${boards[@]}"; do
   for _lc in "${_lcols[@]}"; do
    for _lf in "$bd/$_lc"/*.md; do
      [ -e "$_lf" ] || continue; case "$(basename "$_lf")" in _*) continue ;; esac
      [ "$_legend" -eq 0 ] && { echo; echo "$_lhdr"; _legend=1; }
      printf '  %s (%s) — %s\n' "$(basename "$_lf" .md)" "$(_repo_tag "$_lf")" "$(_field "$_lf" title)"
    done
   done
  done
  _archive_hint
}

# --- migrating the cards that already exist --------------------------------
# Nothing has to be migrated for the board to keep working: every field added by the worktree /
# dashboard work is optional, and a card without it degrades to "-" by design. But two things CAN
# be recovered, and a dashboard is worth more when the cards already on the board answer too:
#   1. the start TIME of every card in doing — `kb start` has been appending a UTC audit line
#      since long before started_epoch existed, so the number is already on disk, unparsed;
#   2. a worktree an agent created by hand for a card, which the card does not know about.
# Dry-run by default. It never touches done/ (the append-only audit archive) and never invents a
# time it cannot read — a card with no audit line is listed as such, not backfilled with "now".
_migrate() {
  local apply=0; [ "${1:-}" = "--apply" ] && apply=1
  local f id iso ep n_ts=0 n_wt=0
  echo "kb migrate — cards in doing/ ($([ "$apply" = 1 ] && echo 'APPLICO' || echo 'prova, non scrivo niente: usa --apply'))"
  for f in "$KB/doing"/*.md; do
    [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac
    id="$(basename "$f" .md)"
    if ! grep -q '^started_epoch:' "$f"; then
      iso="$(grep 'kb_start_audit' "$f" 2>/dev/null | tail -1 | sed 's/.*at=\([^ ]*\).*/\1/')"
      ep=""
      [ -n "$iso" ] && ep="$(date -d "$iso" +%s 2>/dev/null || TZ=UTC date -jf '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null || true)"
      if [ -n "$ep" ]; then
        n_ts=$((n_ts+1))
        printf '  %s — ora di inizio recuperabile dall audit: %s\n' "$id" \
          "$(date -d "@$ep" '+%d/%m/%Y %H:%M %Z' 2>/dev/null || date -r "$ep" '+%d/%m/%Y %H:%M %Z' 2>/dev/null)"
        if [ "$apply" = 1 ]; then
          { echo "started_at: $(date -d "@$ep" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$ep" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
            echo "started_epoch: $ep"; } >> "$f"
        fi
      else
        printf '  %s — nessuna ora di inizio recuperabile (nessuna riga di audit): restera "-"\n' "$id"
      fi
    fi
    if ! grep -q '^worktree:' "$f" && ! grep -q '^worktree_none:' "$f"; then
      n_wt=$((n_wt+1))
      printf '  %s — nessun worktree registrato. Se ne esiste gia uno: kb wt attach %s <path>\n' "$id" "$id"
      printf '     altrimenti la card resta senza isolamento (la spesa sara attribuita per finestra).\n'
    fi
  done
  echo "  -- $n_ts card con ora recuperabile · $n_wt card senza worktree · done/ non viene mai toccato"
  [ "$apply" = 0 ] && echo "  (niente scritto. Per applicare: kb migrate --apply)"
  return 0
}

# kb wt attach <id> <path> — record a worktree that already exists (one an agent made by hand)
# onto a card in doing. The path must really be a git worktree: a card that claims one which is
# not there would make `kb finish` refuse forever, on evidence that was never true.
_wt_attach() {
  local id="${1:?card id}" path="${2:?worktree path}" f
  f="$KB/doing/$id.md"; [ -e "$f" ] || { echo "no doing card $id" >&2; return 1; }
  path="$(cd "$path" 2>/dev/null && pwd)" || { echo "REFUSED: '$2' non esiste" >&2; return 1; }
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || { echo "REFUSED: '$path' non e un worktree git" >&2; return 1; }
  grep -q '^worktree:' "$f" && { echo "REFUSED: la card $id ha gia un worktree registrato" >&2; return 1; }
  { echo "worktree: $path"; echo "branch: $(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)"; } >> "$f"
  echo "worktree registrato sulla card $id: $path"
}

# The boards the current invocation reports on — the same selection _board makes, exposed so
# `kb dash` details exactly the cards the box above it just listed.
_selected_boards() {
  local bd
  if [ "$KB_MATCHED" -eq 0 ]; then
    while IFS= read -r bd; do
      [ -n "$bd" ] && [ -d "$bd/kanban" ] && printf '%s\n' "$bd/kanban"
    done < <(_board_roots)
  else
    printf '%s\n' "$KB"
  fi
}
# kb dash — the informative view (start times, elapsed, spend, evidence, worktree).
# Kept out of `kb view`: that one is injected into every session by the SessionStart hook and
# must stay token-lean. Rendering lives in kanban/dash.sh.
_dash() {
  local -a dboards=()
  local bd
  while IFS= read -r bd; do [ -n "$bd" ] && dboards+=("$bd"); done < <(_selected_boards)
  [ "${#dboards[@]}" -eq 0 ] && dboards=("$KB")
  bash "$ROOT/kanban/dash.sh" "${dboards[@]}"
}

usage() {
  echo 'kb — gated kanban. Commands:'
  echo ' view:'
  echo '  kb                            board + dashboard: inizio/durata delle DOING, durata+spesa+esito delle DONE'
  echo '  kb view                       lean board only (what the SessionStart hook injects)'
  echo '  kb dash                       dashboard only (no box)'
  echo '  kb all | kb g                 AGGREGATED view across every registered board (cards tagged repo:)'
  echo '  kb handoff                    per-repo handoff/latest.md (in a repo) or aggregated (outside)'
  echo '  kb pause ["next step"]        write a resume checkpoint for this repo (safe to leave/reboot)'
  echo '  kb resume [--all|--done]      read the checkpoint (--all aggregates; --done clears it)'
  echo '  kb list | kb ls                plain vertical list, all columns'
  echo '  kb todo | kb doing | kb done  view one column'
  echo '  kb show <id>                  show a card'
  echo '  kb migrate [--apply]          card gia esistenti: recupera l ora di inizio, elenca chi non ha worktree'
  echo '  kb wt attach <id> <path>      registra sulla card un worktree gia creato a mano'
  echo ' federation:'
  echo '  kb init [repo]                make a repo safe to hold cards (local-exclude+de-track+hook+register; idempotent)'
  echo '  kb lint                       schema lint: runner: grammar + human_gates:↔human-only'
  echo '  kb dispatch <id> [cli]        restricted external-CLI dispatcher — DORMANT (hard-wired to refuse)'
  echo ' gates:'
  echo '  kb add "<title>" --repo <r> [dod] [acc]  new card in todo (repo = ~/GitHub dir-name, or "personal")'
  echo '  kb edit <id>                  edit a card (fill dod/acceptance)'
  echo '  kb start <id> --by roberto [--no-worktree "<why>"]   GATE: todo->doing (+ crea il worktree della card)'
  echo '  kb finish <id> --thor "<ev>" [--keep-worktree "<why>"]  GATE: doing->done (worktree pulito, poi rimosso)'
  echo '  kb block <id> "<reason>"      mark a card blocked, move back to todo/'
  echo ' detail (everything ever done, on demand):'
  echo '  kb history                    ALL work: done/ cards + every archived goal, newest first'
  echo '  kb archive [YYYY-MM-DD]       list archive files (counts) | cat one archive'
  echo '  kb plans                      list docs/plan-*.md (+ docs/archive/) with H1 + line count'
  echo '  kb plan <match>               print the plan whose filename contains <match>'
  echo ' ops:'
  echo '  kb sched                      launchd jobs + schedules + factory queue/failed + evolve proposals'
}

# ---------------------------------------------------------------------------
# kb history — everything ever done: individual done/ cards + every row rolled
# up into done/_archive-*.md. Most recent first. Read-only, on-demand detail
# (never loaded at session start — that budget is owned by todo/doing only).
_history() {
  echo "=== HISTORY — individual done/ cards (most recent verified first) ==="
  local f rows=() vat title id repo
  for f in "$KB/done"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in _*) continue;; esac
    vat="$(_field "$f" verified_at)"; [ -n "$vat" ] || vat="$(_field "$f" created)"
    title="$(_field "$f" title)"
    repo="$(_repo_tag "$f")"
    id="$(basename "$f" .md)"
    rows+=("${vat:-0000-00-00}|$id|$repo|$title")
  done
  if [ "${#rows[@]}" -eq 0 ]; then
    echo "  (no individual done cards right now — see archives below)"
  else
    printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -r | while IFS='|' read -r vat id repo title; do
      printf '  [%s] (%s) %s (verified %s)\n' "$id" "$repo" "$title" "$vat"
    done || true
  fi
  echo
  echo "=== HISTORY — archived goals (newest archive first) ==="
  local afiles=()
  for f in "$KB/done"/_archive-*.md; do [ -e "$f" ] && afiles+=("$f"); done
  if [ "${#afiles[@]}" -eq 0 ]; then
    echo "  (no archives yet)"
    return 0
  fi
  local num goal status evidence
  for f in $(printf '%s\n' "${afiles[@]}" | sort -r); do
    echo
    echo "-- $(basename "$f") --"
    grep -E '^\| [0-9]+ \|' "$f" 2>/dev/null | while IFS='|' read -r _ num goal status evidence _; do
      num="$(echo "$num" | tr -d ' ')"
      goal="$(echo "$goal" | sed 's/^ *//; s/ *$//')"
      status="$(echo "$status" | sed 's/^ *//; s/ *$//')"
      evidence="$(echo "$evidence" | sed 's/^ *//; s/ *$//')"
      printf '  %s. %s [%s] — %s\n' "$num" "$goal" "$status" "$evidence"
    done || true
  done
  return 0
}

# kb archive [DATE] — list archive files with goal counts, or cat one by date.
_archive_cmd() {
  local date="${1:-}"
  if [ -z "$date" ]; then
    echo "ARCHIVES:"
    local f found=0 n
    for f in "$KB/done"/_archive-*.md; do
      [ -e "$f" ] || continue
      found=1
      n="$(grep -cE '^\| [0-9]+ \|' "$f" 2>/dev/null || true)"
      printf '  %-32s %s goal(s)\n' "$(basename "$f")" "${n:-0}"
    done
    [ "$found" -eq 0 ] && echo "  (no archives yet)"
    return 0
  fi
  local f="$KB/done/_archive-$date.md"
  if [ -e "$f" ]; then cat "$f"; else echo "no archive for '$date' (looked for $f)" >&2; return 1; fi
}

# kb plans — list docs/plan-*.md + docs/archive/plan-*.md (name, H1, line count).
_plans_list() {
  echo "PLANS:"
  local f h1 lines found=0
  for f in "$ROOT"/docs/plan-*.md "$ROOT"/docs/archive/plan-*.md; do
    [ -e "$f" ] || continue
    found=1
    h1="$(grep -m1 '^# ' "$f" 2>/dev/null || true)"; h1="${h1#\# }"
    lines="$(wc -l < "$f" | tr -d ' ')"
    printf '  %-60s %-4s lines  %s\n' "${f#"$ROOT"/}" "$lines" "$h1"
  done
  [ "$found" -eq 0 ] && echo "  (no plans found under docs/plan-*.md or docs/archive/plan-*.md)"
}

# kb plan <match> — print the plan whose filename contains <match>.
_plan_show() {
  local match="${1:?match required (e.g. kb plan tool-ind)}" f
  local -a matches=()
  for f in "$ROOT"/docs/plan-*.md "$ROOT"/docs/archive/plan-*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"$match"*) matches+=("$f") ;; esac
  done
  case "${#matches[@]}" in
    0) echo "no plan matches '$match'" >&2; return 1 ;;
    1) cat "${matches[0]}" ;;
    *) echo "multiple plans match '$match':"; for f in "${matches[@]}"; do printf '  %s\n' "${f#"$ROOT"/}"; done ;;
  esac
}

# kb sched — one operative view of everything scheduled: launchd jobs +
# their human-readable schedule (from the plist) + factory queue/failed +
# latest evolve proposals. Every piece degrades to "n/a", never crashes.
_sched() {
  echo "=== SCHEDULED JOBS (launchctl) ==="
  local found=0
  if command -v launchctl >/dev/null 2>&1; then
    while IFS=$'\t' read -r pid exitcode label; do
      [ -n "${label:-}" ] || continue
      found=1
      printf '  %-8s exit=%-5s %s\n' "${pid:-?}" "${exitcode:-?}" "$label"
    done < <(launchctl list 2>/dev/null | awk -F'\t' '$3 ~ /^com\.roberdan\./' || true)
  fi
  [ "$found" -eq 0 ] && echo "  n/a (no com.roberdan.* jobs visible via launchctl list)"

  echo
  echo "=== SCHEDULES (from ~/Library/LaunchAgents plists) ==="
  local plist_dir="$HOME/Library/LaunchAgents" p label sched hour minute weekday interval hh mm
  if [ -d "$plist_dir" ] && command -v plutil >/dev/null 2>&1; then
    found=0
    for p in "$plist_dir"/com.roberdan.*.plist; do
      [ -e "$p" ] || continue
      found=1
      label="$(basename "$p" .plist)"
      hour="$(plutil -extract StartCalendarInterval.Hour raw "$p" 2>/dev/null || true)"
      minute="$(plutil -extract StartCalendarInterval.Minute raw "$p" 2>/dev/null || true)"
      weekday="$(plutil -extract StartCalendarInterval.Weekday raw "$p" 2>/dev/null || true)"
      interval="$(plutil -extract StartInterval raw "$p" 2>/dev/null || true)"
      if [ -n "$hour" ] || [ -n "$minute" ]; then
        hh="$(printf '%02d' "${hour:-0}")"; mm="$(printf '%02d' "${minute:-0}")"
        if [ -n "$weekday" ]; then sched="weekly (dow=$weekday) $hh:$mm"; else sched="daily $hh:$mm"; fi
      elif [ -n "$interval" ]; then
        sched="every ${interval}s"
      else
        sched="n/a (no StartCalendarInterval/StartInterval)"
      fi
      printf '  %-38s %s\n' "$label" "$sched"
    done
    [ "$found" -eq 0 ] && echo "  n/a (no com.roberdan.*.plist in $plist_dir)"
  else
    echo "  n/a (no $plist_dir or plutil unavailable)"
  fi

  echo
  echo "=== FACTORY STATE ==="
  local fdir="${RDA_FACTORY:-$RDA_HOME/factory}" qn fn
  if [ -d "$fdir" ]; then
    qn="$(ls "$fdir/queue" 2>/dev/null | wc -l | tr -d ' ' || true)"
    fn="$(ls "$fdir/failed" 2>/dev/null | wc -l | tr -d ' ' || true)"
    printf '  queue:  %s file(s) — %s\n' "${qn:-0}" "$fdir/queue"
    printf '  failed: %s file(s) — %s\n' "${fn:-0}" "$fdir/failed"
  else
    echo "  n/a (no factory dir at $fdir)"
  fi

  echo
  echo "=== EVOLVE PROPOSALS (latest 3) ==="
  if [ -d "$ROOT/proposals" ]; then
    local any=0 x
    for x in $(ls -t "$ROOT/proposals/" 2>/dev/null | head -3 || true); do any=1; echo "  $x"; done
    [ "$any" -eq 0 ] && echo "  n/a (proposals/ empty)"
  else
    echo "  n/a (no proposals/ dir at $ROOT/proposals)"
  fi
  return 0
}

# kb pause [note] — write a lean, overwritten resume checkpoint for the CURRENT repo (cwd-scoped,
# same resolution as kb/kb handoff). Per-repo, gitignored, ephemeral. Fixed sections, never a log.
_pause() {
  local root rf note head subj dirty dcard f
  root="${KB%/kanban}"; rf="$root/handoff/resume.md"; mkdir -p "$root/handoff"
  if [ "${1:-}" = "--auto" ]; then
    # lean auto-save (Stop hook): refresh mechanical state, PRESERVE the human next-step note.
    note=""
    [ -f "$rf" ] && note="$(awk '/^## Next step/{f=1;next} /^## Mechanical state/{f=0} f' "$rf" | sed '/^[[:space:]]*$/d')"
    note="${note:-(auto-checkpoint — no explicit note yet; on resume re-read handoff/latest.md + \`kb\`)}"
  else
    note="${1:-}"
  fi
  head="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo '?')"
  subj="$(git -C "$root" log -1 --format=%s 2>/dev/null || echo '?')"
  dirty="$(git -C "$root" status --porcelain 2>/dev/null | grep -c . || true)"
  dcard=""; for f in "$KB/doing"/*.md; do [ -e "$f" ] && { dcard="$(basename "$f" .md) — $(_field "$f" title)"; break; }; done
  {
    echo "# RESUME — $(basename "$root")  (paused $(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo
    echo "## Next step (what I was doing)"
    echo "${note:-(no note — on resume, re-read handoff/latest.md + \`kb\`)}"
    echo
    echo "## Mechanical state"
    echo "- HEAD: $head $subj"
    echo "- uncommitted files: $dirty"
    echo "- doing card: ${dcard:-(none)}"
    echo
    echo "_Resume: say \"continua\". Clear when resumed: \`kb resume --done\`._"
  } > "$rf"
  echo "paused → $rf"
  echo "safe to reboot / leave; say \"continua\" to resume."
}
# kb resume [--all|--done] — read the checkpoint (current repo; --all or outside a repo aggregates)
_resume() {
  local root rf r any=0
  root="${KB%/kanban}"; rf="$root/handoff/resume.md"
  if [ "${1:-}" = "--done" ]; then rm -f "$rf"; echo "resume checkpoint cleared"; return 0; fi
  if [ "${1:-}" = "--all" ] || [ "$KB_MATCHED" -eq 0 ]; then
    while IFS= read -r r; do
      [ -n "$r" ] && [ -f "$r/handoff/resume.md" ] && { echo "=== $(basename "$r") ==="; cat "$r/handoff/resume.md"; echo; any=1; }
    done < <(_board_roots)
    [ "$any" -eq 0 ] && echo "(no active pause checkpoints across registered repos)"
    return 0
  fi
  if [ -f "$rf" ]; then cat "$rf"; else echo "(no active pause checkpoint in $(basename "$root"))"; fi
  # Resume is the WHOLE plan, not just the checkpoint above. The checkpoint is the
  # re-entry POINT (where I was); the board + handoff are the SCOPE (everything in
  # flight). Surface the live backlog here so a restart re-hydrates all of it, not
  # only the paused task — the failure mode this exists to prevent.
  echo
  echo "── Resume the WHOLE plan, not just the checkpoint above — live backlog: ──"
  echo "  TO DO:";  _list todo
  echo "  DOING:";  _list doing
  echo "  Open threads + decisions live in handoff/latest.md — read it before restarting."
  echo "  Gates still apply on resume: todo->doing is Roberto's; never auto-cross a human gate."
}

# kb all / kb g — the aggregated view is `_board --all` (real three-column kanban across
# every registered board, cards tagged with repo:). A flat-list variant used to live here;
# it was replaced by the board shape (design §2b, @rex #2; Roberto's preference for the
# kanban form). `kb list`/`kb ls` remains the plain vertical list.

# kb handoff — inside a recognized repo: that repo's handoff/latest.md. Otherwise
# (aggregate): concatenate every registered repo's handoff/latest.md newest-first
# by mtime, each section tagged with its repo (design §2b). handoff-protocol.md /
# context-primer.md stay versioned canon and are not touched here.
_handoff() {
  if [ "$KB_MATCHED" -eq 1 ]; then
    local root="${KB%/kanban}" hf
    hf="$root/handoff/latest.md"
    if [ -f "$hf" ]; then cat "$hf"; else echo "(no handoff/latest.md in $(basename "$root"))"; fi
    return 0
  fi
  local root hf rows=() any=0
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    hf="$root/handoff/latest.md"
    [ -f "$hf" ] || continue
    any=1
    rows+=("$(_mtime "$hf")|$root")
  done < <(_board_roots)
  if [ "$any" -eq 0 ]; then echo "(no handoff/latest.md across registered boards)"; return 0; fi
  printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -r | while IFS='|' read -r _ root; do
    echo "=== handoff — $(basename "$root") ==="
    cat "$root/handoff/latest.md"
    echo
  done
  return 0
}

# kb init [repo] — the single act that makes a repo safe to hold federated cards
# (design §2e). Idempotent. GATE: never point this at a shared external repo
# (MirrorBuddy / FightTheStroke) — federating those is a human decision. It only
# scaffolds the repo path you pass (default: roberdan-os itself).
_kb_init() {
  local target="${1:-$ROOT}" root gi line f tracked_handoff=0
  root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$root" ]; then echo "kb init: '$target' is not inside a git repo" >&2; return 1; fi
  echo "kb init: initializing federated board in $root"

  # 1) scaffold
  mkdir -p "$root/kanban/todo" "$root/kanban/doing" "$root/kanban/done" "$root/handoff"

  # CARD content lives ONLY in the three column subdirs — NEVER bare kanban/,
  # which in roberdan-os also holds tracked tooling (kb.sh, README.md). De-track
  # and the history scan therefore target the columns, not kanban/.
  local -a card_paths=(kanban/todo/ kanban/doing/ kanban/done/)

  # is handoff/latest.md already TRACKED? roberdan-os tracks it as canon-ish live
  # state — design §5 note: do NOT silently change that tracking. When tracked we
  # FLAG it and leave gitignore/de-track/history-scan of it alone.
  if git -C "$root" ls-files --error-unmatch handoff/latest.md >/dev/null 2>&1; then
    tracked_handoff=1
  fi

  # 2) ignore-write to .git/info/exclude — LOCAL, per-repo, NEVER the committed
  #    .gitignore (Roberto 2026-07-07): federation noise must not pollute a shared
  #    repo's history. A local exclude keeps kb init self-sufficient on any machine
  #    it runs on (unlike a global core.excludesfile) without touching shared git
  #    state. Shared across worktrees via the common git dir. Idempotent.
  gi="$(git -C "$root" rev-parse --git-path info/exclude 2>/dev/null)"
  case "$gi" in /*) ;; *) gi="$root/$gi";; esac
  mkdir -p "$(dirname "$gi")"; touch "$gi"
  # handoff/resume.md is the per-repo pause checkpoint `kb pause` writes — ephemeral,
  # NEVER the tracked handoff/latest.md canon file. Always exclude it (never tracked).
  local -a need=(kanban/todo/ kanban/doing/ kanban/done/ handoff/resume.md)
  for line in "${need[@]}"; do
    if ! grep -qxF "$line" "$gi" 2>/dev/null; then
      printf '%s\n' "$line" >> "$gi"; echo "  exclude += $line"
    fi
  done
  if [ "$tracked_handoff" -eq 1 ]; then
    echo "  FLAG: handoff/latest.md is TRACKED in $(basename "$root") — left untouched"
    echo "        (federating it as ignored state is a SEPARATE human decision; §5 note)."
  fi

  # 3) de-track already-committed CARD content (git rm --cached, keep working copy)
  local tracked
  tracked="$(git -C "$root" ls-files "${card_paths[@]}" 2>/dev/null || true)"
  if [ -n "$tracked" ]; then
    printf '%s\n' "$tracked" | while IFS= read -r f; do
      [ -n "$f" ] && git -C "$root" rm --cached --quiet "$f" 2>/dev/null || true
    done
    echo "  de-tracked already-committed card content (working copies kept)"
  fi
  if [ "$tracked_handoff" -eq 0 ] && git -C "$root" ls-files --error-unmatch handoff/latest.md >/dev/null 2>&1; then
    git -C "$root" rm --cached --quiet handoff/latest.md 2>/dev/null || true
    echo "  de-tracked handoff/latest.md"
  fi

  # 4) scan LOCAL history for card content already committed (the blob survives
  #    git rm --cached). pushed -> HUMAN GATE #4 (refuse); local-only -> loud warn.
  local -a scan_paths=("${card_paths[@]}")
  [ "$tracked_handoff" -eq 0 ] && scan_paths+=(handoff/latest.md)
  local hits pushed_hits="" local_hits="" sha
  hits="$(git -C "$root" log --all --pretty=%H -- "${scan_paths[@]}" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      if [ -n "$(git -C "$root" branch -r --contains "$sha" 2>/dev/null)" ]; then
        pushed_hits="$pushed_hits $sha"
      else
        local_hits="$local_hits $sha"
      fi
    done <<EOF_SCAN
$hits
EOF_SCAN
  fi
  if [ -n "$pushed_hits" ]; then
    {
      echo ""
      echo "kb init: REFUSED — card/handoff content is in PUSHED history (human gate #4):"
      for sha in $pushed_hits; do git -C "$root" --no-pager log -1 --oneline "$sha"; done
      echo "  This is deletion of already-published data — escalate to Roberto (git filter-repo"
      echo "  or repo recreate). kb init does NOT scrub published history automatically."
    } >&2
    return 1
  fi
  if [ -n "$local_hits" ]; then
    {
      echo ""
      echo "kb init: WARNING — card/handoff content in LOCAL-ONLY (un-pushed) commits:"
      for sha in $local_hits; do git -C "$root" --no-pager log -1 --oneline "$sha"; done
      echo "  git rm --cached de-tracks forward, but the blob REMAINS in local history."
      echo "  Do NOT push these branches; scrub (git filter-repo / rebase) before any push."
    } >&2
  fi

  # 5) pre-commit hook: roberdan-os leak-check on the staged tree (interactive
  #    safety; --no-verify-bypassable, so NOT the runner's gate — design §2e#5).
  #    Idempotent — never clobber an existing leak-check hook.
  local hookdir hook
  hookdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)/hooks"; hook="$hookdir/pre-commit"
  mkdir -p "$hookdir"
  if [ -f "$hook" ] && grep -q 'leak-check' "$hook" 2>/dev/null; then
    echo "  pre-commit hook already runs leak-check (left as-is)"
  else
    cat > "$hook" <<HOOK
#!/usr/bin/env bash
# installed by roberdan-os \`kb init\` — runs roberdan-os leak-check on the STAGED files of
# THIS repo before every commit (interactive safety; bypassable with --no-verify, so it is
# NOT the runner's gate — that lives in the dispatcher, design §2e#5).
# Scans only the staged files (--only), NOT the whole tree: leak-check's default target is
# roberdan-os's own tree, so a bare call from another repo scanned the WRONG files and hung
# on large blobs (2026-07-08 scar). Zero staged files → nothing to check.
set -euo pipefail
RDA_LEAKCHECK="$ROOT/test/leak-check.sh"
[ -x "\$RDA_LEAKCHECK" ] || exit 0
_root="\$(git rev-parse --show-toplevel 2>/dev/null)"
staged=()
while IFS= read -r f; do [ -n "\$f" ] && staged+=("\$_root/\$f"); done \\
  < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
[ \${#staged[@]} -eq 0 ] && exit 0
if ! bash "\$RDA_LEAKCHECK" --only "\${staged[@]}"; then
  echo "pre-commit: BLOCKED — confidential term(s) detected (see above)." >&2
  exit 1
fi
HOOK
    chmod +x "$hook"
    echo "  installed pre-commit leak-check hook -> $hook"
  fi

  # 6) register (idempotent)
  mkdir -p "$(dirname "$REGISTRY")"; touch "$REGISTRY"
  if ! grep -qxF "$root" "$REGISTRY" 2>/dev/null; then
    printf '%s\n' "$root" >> "$REGISTRY"; echo "  registered $root in $REGISTRY"
  else
    echo "  already registered in $REGISTRY"
  fi
  echo "kb init: done (idempotent). This does NOT make the repo runner-eligible"
  echo "         (that is the separate, narrower runner-allowlist)."
  return 0
}

# kb pending — the "approval inbox": ONE place aggregating everything waiting on Roberto,
# so nothing (a learning to approve, an open PR, a gated card) sits unseen. Read-only; the
# same aggregation the proactive digest (bin/pending-digest.sh) and the SessionStart count use.
# Prints a trailing "PENDING: N" line as the machine-readable total (grepped by the hook/digest).
_pending() {
  local total=0 n f cls body bd quar repo_root
  local -a boards=() repo_roots=()
  while IFS= read -r bd; do
    [ -n "$bd" ] || continue
    repo_roots+=("$bd")
    [ -d "$bd/kanban" ] && boards+=("$bd/kanban")
  done < <(_board_roots)
  # Include the resolved board ($KB, which respects RDA_KANBAN) if _board_roots didn't already —
  # matters for a non-registered cwd and for isolated tests that point RDA_KANBAN at a temp board.
  local _in=0 _b kb_repo_root
  for _b in "${boards[@]}"; do [ "$_b" = "$KB" ] && _in=1; done
  [ "$_in" -eq 0 ] && boards+=("$KB")
  kb_repo_root="$(dirname "$KB")"
  _in=0; for _b in "${repo_roots[@]}"; do [ "$_b" = "$kb_repo_root" ] && _in=1; done
  [ "$_in" -eq 0 ] && repo_roots+=("$kb_repo_root")
  quar="${RDA_QUARANTINE:-$RDA_HOME/learnings/quarantine}"

  # --count: fast LOCAL total (todo + unapproved learning, no gh) — for the SessionStart hook,
  # which must stay quick. Prints only the number.
  if [ "${1:-}" = "--count" ]; then
    n=0
    for bd in "${boards[@]}"; do for f in "$bd/todo"/*.md; do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac; n=$((n+1)); done; done
    if [ -d "$quar" ]; then for f in "$quar"/*.md; do [ -e "$f" ] || continue
      awk 'NR==1&&/^---$/{fm=1;next} fm&&/^---$/{exit} fm' "$f" | grep -qE '^approved:[[:space:]]*true' && continue; n=$((n+1)); done; fi
    echo "$n"; return 0
  fi

  echo "## Pending — cosa aspetta te (Roberto)"

  # 1) Kanban todo cards across every registered board — gate: todo->doing is your approval.
  echo
  # REGOLA 5 — un progetto alla volta, quello dove sei.
  #
  # Questo elenco impilava OTTO board in un muro unico. Il 2026-07-30 erano 33 righe, di cui
  # 19 su un solo progetto, mescolate a MirrorHR, MirrorBuddy, trading-os e ConvergioEdu2030
  # senza un ordine leggibile. Il risultato osservato non e' che Roberto approvasse le cose
  # sbagliate: e' che non ne approvava nessuna, perche' un muro di 33 righe non si smista.
  #
  # Ora il progetto del cwd viene per primo e per intero; gli altri si contano, non si
  # elencano, e `kb pending --tutti` li apre. Un permesso si da' su una coda, non su 33 pezzi.
  echo "### Kanban todo — approvazione todo→doing"
  _p_qui="$(_repo_qui)"
  _p_tutti=""; case "${1:-}" in --tutti|--all) _p_tutti=1 ;; esac
  n=0; _p_qui_n=0; _p_altri_n=0; _p_altri_repo=""
  for bd in "${boards[@]}"; do
    for f in "$bd/todo"/*.md; do
      [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac
      n=$((n+1))
      _p_r="$(_repo_tag "$f")"
      if [ -n "$_p_tutti" ] || [ "$_p_r" = "$_p_qui" ]; then
        printf '  • %s (%s) — %s\n' "$(basename "$f" .md)" "$_p_r" "$(_field "$f" title)"
        _p_qui_n=$((_p_qui_n+1))
      else
        _p_altri_n=$((_p_altri_n+1))
        case " $_p_altri_repo " in *" $_p_r "*) ;; *) _p_altri_repo="$_p_altri_repo $_p_r" ;; esac
      fi
    done
  done
  [ "$n" -eq 0 ] && echo "  (nessuna)"
  if [ "$_p_qui_n" -eq 0 ] && [ "$n" -gt 0 ]; then
    echo "  (nessuna per '$_p_qui', dove sei adesso)"
  fi
  if [ "$_p_altri_n" -gt 0 ]; then
    echo "  + $_p_altri_n su altri progetti:$_p_altri_repo — \`kb pending --tutti\` per vederle"
  fi
  total=$((total+n))

  # 2) Learning candidates awaiting your approval (approved: false in quarantine) — flip
  #    approved: true on the ones worth keeping, then `bash ontology/curate.sh` promotes them.
  echo
  echo "### Learning da approvare — flip approved:true + \`bash ontology/curate.sh\`"
  n=0
  if [ -d "$quar" ]; then
    for f in "$quar"/*.md; do
      [ -e "$f" ] || continue
      awk 'NR==1&&/^---$/{fm=1;next} fm&&/^---$/{exit} fm' "$f" | grep -qE '^approved:[[:space:]]*true' && continue
      cls="$(awk 'NR==1&&/^---$/{fm=1;next} fm&&/^---$/{exit} fm&&/^class:/{sub(/^class:[[:space:]]*/,"");sub(/[[:space:]]*#.*/,"");print}' "$f")"
      body="$(awk '/^## Signal/{s=1;next} /^## /{s=0} s&&NF' "$f" | head -1)"
      printf '  • [%s] %s — %s\n' "${cls:-?}" "$(basename "$f" .md)" "$(printf '%s' "$body" | cut -c1-72)"
      n=$((n+1))
    done
  fi
  [ "$n" -eq 0 ] && echo "  (nessuno)"
  total=$((total+n))

  # 3) Open PRs awaiting review/merge, aggregated across EVERY registered repo (not just cwd —
  #    the digest runs from no repo, so a cwd-scoped check was dead on the push path, rex/thor
  #    2026-07-08). Bot PRs (Dependabot/renovate/actions) are excluded: they're not what "needs
  #    Roberto" means — a raw dump of dozens of dep-bumps would be noise, the opposite failure.
  #    Best-effort: per-repo gh call, skipped silently where gh/remote is absent.
  echo
  echo "### PR aperte (review/merge — bot esclusi, tutti i repo)"
  n=0
  if command -v gh >/dev/null 2>&1; then
    for repo_root in "${repo_roots[@]}"; do
      [ -d "$repo_root/.git" ] || continue
      while IFS=$'\t' read -r num title; do
        [ -n "$num" ] || continue
        printf '  • %s#%s — %s\n' "$(basename "$repo_root")" "$num" "$title"; n=$((n+1))
      done < <(cd "$repo_root" 2>/dev/null && gh pr list --state open --json number,title,author \
        --jq ".[]|select((.author.login // \"\")|test(\"$_PR_BOT_FILTER_RE\")|not)|\"\\(.number)\\t\\(.title)\"" 2>/dev/null)
    done
  fi
  [ "$n" -eq 0 ] && echo "  (nessuna non-bot / gh non disponibile)"
  total=$((total+n))

  # Discursive human-gate threads live in handoff/latest.md (open threads / gates) — pointer,
  # not parsed: they're prose, and a false count is worse than a pointer.
  echo
  echo "### Gate discorsivi / thread aperti"
  echo "  vedi $ROOT/handoff/latest.md (§ open threads / human gates)"

  echo
  echo "PENDING: $total"
}

# resolve a repo name to its path: a registry entry basenamed <name>, else ~/GitHub/<name>.
_repo_path() {
  local name="$1" r
  if [ -f "$REGISTRY" ]; then
    while IFS= read -r r; do [ -n "$r" ] && [ "$(basename "$r")" = "$name" ] && { printf '%s' "$r"; return 0; }; done < "$REGISTRY"
  fi
  [ -d "$HOME/GitHub/$name" ] && printf '%s' "$HOME/GitHub/$name"
}
# kb repo <name> — a per-repo dashboard ON TOP of the kanban: git state, open (non-bot) PRs,
# and this repo's cards grouped doing / todo / done. Read-only. Complements `kb`/`kb all`.
_repo_view() {
  local name="$1" p b dirty last ln rc c kbd f n
  p="$(_repo_path "$name")"
  [ -n "$p" ] && [ -d "$p" ] || { echo "kb repo: '$name' not found (not in the registry, no ~/GitHub/$name)" >&2; return 1; }
  echo "## $name — $p"

  # git state
  if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    b="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    dirty="$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    last="$(git -C "$p" log -1 --format='%h %s' 2>/dev/null || echo '(no commits)')"
    # ahead/behind only when the branch actually has an upstream on origin (local-only repos
    # like Fabrica have none — computing it would fail and, under set -e, abort the whole view).
    ln=""
    if git -C "$p" rev-parse --verify -q "origin/$b" >/dev/null 2>&1; then
      ln="$(git -C "$p" rev-list --left-right --count "origin/$b...$b" 2>/dev/null | awk '{printf "behind %s, ahead %s", $1, $2}')"
    fi
    printf '### git\n  %s · %s uncommitted · last: %s%s\n' "$b" "$dirty" "$last" "${ln:+ · $ln}"
  else
    printf '### git\n  (not a git repo)\n'
  fi

  # open PRs (non-bot), best-effort
  printf '### open PRs (review/merge — bot excluded)\n'
  n=0
  if command -v gh >/dev/null 2>&1 && git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS=$'\t' read -r pn pt; do [ -n "$pn" ] && { printf '  #%s — %s\n' "$pn" "$pt"; n=$((n+1)); }; done \
      < <(cd "$p" 2>/dev/null && gh pr list --state open --json number,title,author \
          --jq ".[]|select((.author.login // \"\")|test(\"$_PR_BOT_FILTER_RE\")|not)|\"\\(.number)\\t\\(.title)\"" 2>/dev/null)
  fi
  [ "$n" -eq 0 ] && echo "  (none / gh unavailable)"

  # cards, grouped: doing (in essere) · todo (da fare) · done (fatte, newest 5)
  kbd="$p/kanban"
  if [ -d "$kbd" ]; then
    for c in doing todo; do
      printf '### %s\n' "$([ "$c" = doing ] && echo 'DOING (in essere)' || echo 'TODO (da fare)')"
      rc=0
      for f in "$kbd/$c"/*.md; do
        [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac
        printf '  %s — %s\n' "$(basename "$f" .md)" "$(_field "$f" title)"; rc=1
      done
      [ "$rc" -eq 0 ] && echo "  (none)"
    done
    printf '### DONE (fatte — newest 5)\n'
    rc=0
    local _dtmp=""
    for f in "$kbd/done"/*.md; do
      [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac
      _dtmp="$_dtmp$(_mtime "$f")|$f"$'\n'
    done
    while IFS='|' read -r _ f; do
      [ -n "${f:-}" ] || continue
      printf '  %s — %s\n' "$(basename "$f" .md)" "$(_field "$f" title)"; rc=1
    done < <(printf '%s' "$_dtmp" | sort -t'|' -k1,1 -rn | head -5)
    [ "$rc" -eq 0 ] && echo "  (none)"
  else
    printf '### board\n  (repo not kb-init'"'"'d — no board; run `kb init` from inside it)\n'
  fi
}

# --- kb queue / kb next — l'autorizzazione permanente di Roberto ------------------------------
#
# DECISIONE DI ROBERTO, 2026-07-30, presa dopo che gli avevo proposto una versione più stretta
# e lui ha chiesto questa: *"fai sì che completi tutte le card che ci sono quando comincia una
# sessione e poi si fermi solo quando ha finito quella lista, così io poi vedo solo se ha
# aggiunto altro."*
#
# COSA CAMBIA, DETTO CHIARO: il gate umano `todo → doing` non è più per singola card. Una
# sessione fotografa la lista all'inizio e la percorre TUTTA senza chiedere.
#
# PERCHÉ NON È UN GATE TOLTO MA SPOSTATO. Il gate serviva a impedire che un agente si scegliesse
# il lavoro da solo. La fotografia lo impedisce lo stesso, in un modo che costa a Roberto una
# lettura invece di trentatré: una card creata DOPO lo scatto NON è nella lista e non parte.
# Quindi ciò che un agente aggiunge mentre lavora resta fuori, ed è esattamente la cosa che
# Roberto vuole vedere — "vedo solo se ha aggiunto altro". Il gate è passato da *quali card*
# a *quale lista*, e la lista è scritta su file, con data, prima che parta qualcosa.
#
# IL RISCHIO, DICHIARATO: se la lista contiene una card che non voleva, parte lo stesso. Si
# revoca cancellando la fotografia (`kb queue --stop`), e `kb queue` la stampa per intero prima
# di scattarla, così è leggibile in dieci secondi.
_queue_file() { printf '%s/.coda-%s.md' "$KB" "$1"; }

_queue_repo() { _repo_qui; }  # stessa risoluzione di `kb pending`

_queue() {
  local repo="" arg
  for arg in "$@"; do case "$arg" in --*) ;; *) repo="$arg" ;; esac; done
  [ -n "$repo" ] || repo="$(_queue_repo)"
  local qf; qf="$(_queue_file "$repo")"

  case " $* " in
    *" --stop "*|*" --revoca "*)
      [ -f "$qf" ] && { rm -f "$qf"; echo "coda revocata per '$repo' — si torna all'approvazione per singola card."; } \
                   || echo "nessuna coda attiva per '$repo'."
      return 0 ;;
  esac

  local rinnova=0
  case " $* " in *" --nuova "*|*" --new "*) rinnova=1 ;; esac

  if [ -f "$qf" ] && [ "$rinnova" -eq 0 ]; then
    local fatte=0 restanti=0 id
    while read -r id; do
      case "$id" in ''|\#*) continue ;; esac
      if [ -e "$KB/todo/$id.md" ] || [ -e "$KB/doing/$id.md" ]; then restanti=$((restanti+1)); else fatte=$((fatte+1)); fi
    done < "$qf"
    echo "coda '$repo': $fatte chiuse, $restanti da fare  ($(sed -n '2p' "$qf"))"
    [ "$restanti" -gt 0 ] && echo "  prossima: \`kb next\`" || echo "  LISTA FINITA — vedi \`kb queue --aggiunte\` per cosa e' nato dopo."
    return 0
  fi

  # Lo scatto. Solo le card del repo chiesto: una board puo' tenerne di piu' d'uno, e una coda
  # che mescolasse i repo farebbe partire lavoro su un progetto che non e' quello dove sei.
  local ids="" n=0 f
  for f in "$KB/todo"/*.md; do
    [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac
    [ "$(_field "$f" repo)" = "$repo" ] || continue
    ids="$ids$(basename "$f" .md)
"; n=$((n+1))
  done
  if [ "$n" -eq 0 ]; then echo "nessuna card in attesa per '$repo': niente da fotografare."; return 0; fi
  { echo "# CODA AUTORIZZATA — $repo"
    echo "# scattata il $(date '+%Y-%m-%d %H:%M:%S %Z') · autorizzazione permanente di Roberto del 2026-07-30"
    echo "# Le card qui sotto partono senza chiedere. Quelle nate DOPO questo scatto no."
    printf '%s' "$ids"; } > "$qf"
  echo "coda '$repo' fotografata: $n card, in quest'ordine."
  local id
  while read -r id; do
    case "$id" in ''|\#*) continue ;; esac
    printf '  • %s — %s\n' "$id" "$(_field "$KB/todo/$id.md" title)"
  done < "$qf"
  echo "  parti con \`kb next\` · revoca con \`kb queue --stop\`"
}

_next() {
  local repo="" arg
  for arg in "$@"; do case "$arg" in --*) ;; *) repo="$arg" ;; esac; done
  [ -n "$repo" ] || repo="$(_queue_repo)"
  local qf; qf="$(_queue_file "$repo")"
  [ -f "$qf" ] || { echo "REFUSED: nessuna coda per '$repo'. Scattala con \`kb queue\`." >&2; return 1; }

  # La regola 1 vale ancora: se c'e' gia' una card in corso su questo repo, non se ne apre un'altra.
  local d
  for d in "$KB/doing"/*.md; do
    [ -e "$d" ] || continue; case "$(basename "$d")" in _*) continue ;; esac
    if [ "$(_field "$d" repo)" = "$repo" ]; then
      echo "'$repo' ha gia' una card in corso: $(basename "$d" .md) — $(_field "$d" title)" >&2
      echo "  finiscila (kb finish ...) e poi richiama kb next." >&2
      return 1
    fi
  done

  local id
  while read -r id; do
    case "$id" in ''|\#*) continue ;; esac
    [ -e "$KB/todo/$id.md" ] || continue
    echo "kb next: prendo $id — $(_field "$KB/todo/$id.md" title)"
    # Si richiama lo STESSO script invece di duplicare il corpo di `start`: quel corpo scrive
    # la riga di audit, controlla dod/acceptance/repo, applica la regola 1 e crea il worktree.
    # Riscriverlo qui vorrebbe dire avere due gate che devono restare d'accordo, ed e' cosi'
    # che un gate smette di valere senza che nessuno se ne accorga.
    RDA_KANBAN="$KB" bash "${BASH_SOURCE[0]}" start "$id" \
      --by "roberto (coda autorizzata, scatto del $(sed -n '2p' "$qf" | sed 's/^# scattata il //;s/ ·.*//'))"
    return $?
  done < "$qf"

  # Lista finita. Qui il report deve dire cosa e' NATO DOPO: e' l'unica cosa che Roberto ha
  # chiesto di vedere, e se questo blocco tace il gate spostato diventa un gate tolto.
  echo "LISTA FINITA per '$repo': tutte le card della fotografia sono chiuse."
  local scatto nate=0 f
  scatto="$(sed -n '2p' "$qf" | sed 's/^# scattata il //;s/ ·.*//')"
  for f in "$KB/todo"/*.md; do
    [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue ;; esac
    [ "$(_field "$f" repo)" = "$repo" ] || continue
    grep -qx "$(basename "$f" .md)" "$qf" && continue
    [ "$nate" -eq 0 ] && echo "" && echo "NATE DOPO lo scatto del $scatto — queste aspettano TE:"
    nate=$((nate+1))
    printf '  • %s — %s\n' "$(basename "$f" .md)" "$(_field "$f" title)"
  done
  [ "$nate" -eq 0 ] && echo "Nessuna card nuova: la sessione non ha aggiunto niente." \
                    || echo "  ($nate nuove. Per autorizzarle: \`kb queue --nuova\`.)"
  return 0
}

# --- kb cover — the plan→card gate (rules/best-practices.md § Carded End-to-End) -------------
# Every gate in this system operates DOWNSTREAM of the card: kb, @thor, the merge-gate and CI all
# verify a card. A requirement that never BECOMES a card is invisible to all four simultaneously.
# The plan→card translation is the only link in the chain with no gate — and it is exactly where
# requirements die (trading-os, 2026-07-13: the signed plan mandated "SEC EDGAR/RSS, company IR and
# GDELT"; the one card that could have delivered it said "at least one mandatory free live source",
# closed honestly green, and the news evaporated. An audit then found 77 of 149 normative clauses
# never reached the product).
#
# The canon named this command before it existed — a rule against unwired requirements that itself
# cited an unwired command. This is that command.
#
# It walks FROM THE PLAN, never from the board: a board can only show you the cards that exist, and
# cannot show you the ABSENCE of one, which is the entire failure mode.
_cover() {
  local plan="${1:-}"
  [ -n "$plan" ] || { echo "usage: kb cover <plan.md>   (try: kb plans)" >&2; return 2; }
  [ -f "$plan" ] || plan="$ROOT/$plan"
  [ -f "$plan" ] || { echo "no such plan: ${1}" >&2; return 2; }

  # Normative clauses: numbered list items, continued on indented lines. Same extractor shape as
  # trading-os's plan_coverage gate, which was validated against a 2946-line signed plan.
  # The committed decision sidecar: `<plan>.coverage`, one line per clause:
  #   2#28  not_normative   # why: a human gate, not a deliverable
  # It is COMMITTED (unlike the board, which is local-only), so the decision survives the session
  # and is reviewable. A clause with no card AND no written exemption fails the gate.
  local sidecar="${plan}.coverage"
  local clauses total=0 uncovered=0 weakened=0 exempt=0
  # The clause's section is captured WHEN THE CLAUSE STARTS (csect), not when it is flushed. Using
  # the live heading at flush time meant a clause buffered at EOF took the name of whatever section
  # was appended next — so every exemption key would silently rebind on the next edit of the plan.
  # A fragile key is worse than no key: it rots quietly, which is the exact failure this gate exists
  # to catch. (Found by running it, not by reading it.)
  clauses="$(awk '
    /^#/                 { sect = $0; sub(/^#+[ ]*/, "", sect) }
    /^[0-9]+\.[ ]+/      { if (buf != "") print id "\t" csect "\t" buf
                           id = $1; sub(/\./, "", id); csect = sect
                           buf = substr($0, index($0, " ") + 1); next }
    /^[ ]{3,}[^ ]/       { if (buf != "") { sub(/^[ ]+/, "", $0); buf = buf " " $0 } ; next }
    /^[ ]*$/             { next }
                         { if (buf != "") { print id "\t" csect "\t" buf; buf = "" } }
    END                  { if (buf != "") print id "\t" csect "\t" buf }
  ' "$plan" | awk -F'\t' 'length($3) > 40')"

  # Weakening quantifiers: a plan that says "X, Y AND Z are mandatory" and a card that says
  # "at least one" is a DOWNGRADE that closes green while deleting Y and Z from the product.
  local weaken_re='at least one|almeno una|almeno uno|any one of|one or more|not_applicable'
  local mandatory_re='obbligator|mandator|required|deve|must'

  echo "plan-coverage: $(basename "$plan")"
  while IFS=$'\t' read -r num sect text; do
    [ -n "$num" ] || continue
    total=$((total + 1))
    local key="${sect%% *}#${num}"
    # An explicit, COMMITTED decision may exempt a clause. Every clause must be decided — a gate
    # that fires on prose it was never meant to police is one you learn to ignore, and an ignored
    # gate is the same as no gate. The sidecar forces the decision to be WRITTEN, not remembered.
    if [ -f "$sidecar" ] && grep -qE "^${key}[[:space:]]+(not_normative|exempt)\b" "$sidecar" 2>/dev/null; then
      exempt=$((exempt + 1))
      continue
    fi
    # A card claims a clause with `satisfies: <key>[,<key>]` in its frontmatter.
    local hits
    hits="$(grep -ils "^satisfies:.*${key}" "$KB"/todo/*.md "$KB"/doing/*.md "$KB"/done/*.md 2>/dev/null || true)"
    if [ -z "$hits" ]; then
      uncovered=$((uncovered + 1))
      printf '  UNCOVERED  %-14s %s\n' "$key" "$(echo "$text" | cut -c1-72)"
      continue
    fi
    # Covered — but does the card WEAKEN what the clause demands?
    if echo "$text" | grep -qiE "$mandatory_re"; then
      local card
      while IFS= read -r card; do
        [ -n "$card" ] || continue
        if grep -qiE "$weaken_re" "$card"; then
          weakened=$((weakened + 1))
          printf '  WEAKENED   %-14s card %s reads as a weakening escape\n' \
            "$key" "$(basename "$card" .md)"
        fi
      done <<< "$hits"
    fi
  done <<< "$clauses"

  echo "  --"
  echo "  $total clause(s) · $((total - uncovered - exempt)) carded · $uncovered uncovered · $weakened weakened · $exempt exempt"
  if [ "$uncovered" -gt 0 ] || [ "$weakened" -gt 0 ]; then
    echo "  A requirement that never becomes a card is not planned — it is a wish that looks planned." >&2
    echo "  Card it:   kb add \"<title>\" --repo <r> --satisfies \"<clause-id>\" \"<dod>\" \"<acc>\"" >&2
    echo "  Or decide: echo '<clause-id>  not_normative  # why' >> ${sidecar}" >&2
    return 1
  fi
  echo "  every normative clause maps to a card"
  return 0
}

case "$cmd" in
  "")                              # bare `kb` (a human typed it): board + the detail blocks
    KB_LEGEND_TODO_ONLY=1
    if [ "$KB_MATCHED" -eq 0 ]; then _board --all; else _board; fi
    _dash
    ;;
  view|board)                      # lean board only — what the SessionStart hook injects
    if [ "$KB_MATCHED" -eq 0 ]; then _board --all; else _board; fi
    ;;
  dash) _dash ;;                   # detail blocks alone (no box)
  migrate) _migrate "${1:-}" ;;    # backfill start times / list cards with no worktree (dry-run)
  wt)                              # per-card worktrees: attach an existing one, or inspect
    case "${1:-}" in
      attach) shift; _wt_attach "${1:-}" "${2:-}" ;;
      *) echo "usage: kb wt attach <card-id> <path>" >&2; exit 2 ;;
    esac ;;
  repo|status) _repo_view "${1:?repo name required (kb repo <name>)}" ;;  # per-repo dashboard: git + PRs + cards
  pending|inbox) _pending "$@" ;;  # the approval inbox: everything waiting on Roberto (--count = fast total)
  queue|coda) _queue "$@" ;;       # fotografa la lista di inizio sessione (autorizzazione permanente)
  next|prossima) _next "$@" ;;     # prende la prossima card della fotografia, senza chiedere
  bot-filter-regex) _pr_bot_filter_regex ;;
  init) _kb_init "${1:-$ROOT}" ;;  # scaffold + privatize a repo's board (idempotent)
  lint) RDA_KANBAN="$KB" bash "$ROOT/kanban/lint-cards.sh" ;;  # runner/human_gates schema lint
  dispatch) bash "$ROOT/factory/dispatch-runner.sh" "$@" ;;   # restricted external-CLI dispatcher (DORMANT — always refuses)
  all|g) _board --all ;;           # aggregated three-column board across the registry
  handoff) _handoff ;;             # per-repo (in a repo) or aggregated live state
  pause) _pause "${1:-}" ;;         # write a resume checkpoint (safe to leave)
  resume) _resume "${1:-}" ;;       # read it (--all aggregates, --done clears)
  list|ls)                         # plain vertical list
    echo "TO DO:";  _list todo
    echo "DOING:";  _list doing
    n=$(ls "$KB/done"/*.md 2>/dev/null | grep -vc '/_' || true)
    echo "DONE ($n):"; _list done; _archive_hint
    ;;

  show)
    id="${1:?id required}"; f=""
    for c in todo doing done; do [ -e "$KB/$c/$id.md" ] && f="$KB/$c/$id.md"; done
    [ -n "$f" ] && cat "$f" || { echo "no card $id" >&2; exit 1; }
    ;;

  add)
    # --repo can appear anywhere among the args; everything else stays positional
    # (title, then optional dod, then optional acceptance), same as before.
    repo=""; satisfies=""; args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        # The plan clause(s) this card delivers (e.g. --satisfies "2#28"). This is the link `kb
        # cover` walks: without it a plan requirement has no card, and no gate can see the absence.
        --satisfies) satisfies="${2:-}"; shift 2 ;;
        # An UNKNOWN --flag must never be swallowed as positional text. It used to be, and the
        # result was silent data loss: `kb add "t" --repo r --dod "<real dod>" --acc "<real acc>"`
        # produced dod="--dod", acceptance="<real dod>", and dropped the acceptance criteria
        # entirely — while still passing the "a card can't start without all three filled" rule,
        # because the literal string "--dod" is filled. A gate satisfiable without doing the work.
        # Caught by @thor on card 260721-135440, 2026-07-21.
        --*) echo "REFUSED: unknown flag '$1' for kb add." >&2
             echo "  dod and acceptance are POSITIONAL, not flags:" >&2
             echo "    kb add \"<title>\" --repo <repo> \"<dod>\" \"<acceptance>\"" >&2
             exit 1 ;;
        *) args+=("$1"); shift ;;
      esac
    done
    title="${args[0]:?title required}"; dod="${args[1]:-FILL: definition of done}"; acc="${args[2]:-FILL: acceptance criteria (how @thor verifies)}"
    if [ "${#args[@]}" -gt 3 ]; then
      echo "REFUSED: kb add takes at most 3 positional args (title, dod, acceptance); got ${#args[@]}." >&2
      echo "  Extra args would be silently dropped. Quote each field as a single argument." >&2
      exit 1
    fi
    if [ -z "$repo" ]; then
      echo "REFUSED: --repo required — which repo/scope is this card about? e.g.:" >&2
      echo "  kb add \"$title\" --repo roberdan-os [dod] [acc]" >&2
      echo "  (use the ~/GitHub dir-name for a code repo, or 'personal' for non-repo work)" >&2
      exit 1
    fi
    # REGOLA 4 — un criterio di chiusura, uno solo, verificabile.
    #
    # Misurato il 2026-07-30, non supposto: una card in `doing` aveva 491 caratteri di
    # acceptance con nove condizioni in fila ("aggiorna/versioning/libreria/slideshow
    # funzionano; invarianti e audit bloccano il caso fancoil; ..."). Card cosi' non si
    # chiudono MAI, e una card che non si chiude produce, la sessione dopo, una card nuova
    # sullo stesso argomento: quel giorno ce n'erano quattro identiche, aperte da sette
    # giorni. Le congiunzioni sono il posto dove i requisiti muoiono, in due modi opposti:
    # una lista con "e" non si chiude mai, e una lista con "almeno uno di" chiude verde
    # cancellando il resto.
    #
    # Il controllo e' un RATCHET, non una retroattivita': vale solo su card NUOVE. Le card
    # esistenti non vengono toccate, perche' un gate rosso il giorno in cui nasce e' un
    # gate che viene aggirato — la stessa famiglia di difetti chiusa tre volte in due giorni
    # in questo repo.
    if [ -n "${args[2]:-}" ]; then
      _clausole=0
      case "$acc" in *";"*) _clausole=1 ;; esac
      case "$acc" in *" e "*) _clausole=1 ;; esac
      case "$acc" in *" and "*) _clausole=1 ;; esac
      case "$acc" in *"1)"*|*"2)"*) _clausole=1 ;; esac
      if [ "$_clausole" = "1" ] && [ -z "${RDA_KB_ALLOW_MULTI_CLAUSE:-}" ]; then
        echo "REFUSED: l'acceptance ha piu' di una condizione." >&2
        echo "  Trovato uno fra: ';'  ' e '  ' and '  '1)'  '2)'" >&2
        echo "  Una card = una condizione verificabile. Se ce ne sono tre, sono tre card." >&2
        echo "  Motivo: una card con nove condizioni non si chiude mai, e la sessione dopo" >&2
        echo "  qualcuno ne apre un'altra sullo stesso argomento. Il 2026-07-30 ce n'erano 4." >&2
        echo "  Scritto: \"$acc\"" >&2
        echo "  Se e' davvero una condizione sola e la frase contiene 'e': RDA_KB_ALLOW_MULTI_CLAUSE=1 kb add ..." >&2
        exit 1
      fi
    fi
    base_id="${RDA_KB_ID_BASE:-$(date +%y%m%d-%H%M%S)}"
    id="$(_new_card_id "$base_id")"
    { echo '---'; echo "title: $title"; echo "repo: $repo"; echo "dod: \"$dod\""; echo "acceptance: \"$acc\"";
      [ -n "$satisfies" ] && echo "satisfies: $satisfies"
      echo 'status: todo'; echo "created: $(date +%Y-%m-%d)"; echo '---'; } > "$KB/todo/$id.md"
    if [ "$id" = "$base_id" ]; then
      echo "added todo/$id (repo: $repo)"
    else
      echo "added todo/$id (repo: $repo, collision on $base_id resolved with suffix)"
    fi
    ;;

  start)
    id="${1:?id required}"; shift || true
    by=""; no_wt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --by) by="${2:-}"; shift 2 ;;
        # A card that is not code work (repo: personal, an approval, a decision) has nothing to
        # isolate — but the reason is written on the card, so "no worktree" is a decision on the
        # record rather than a silent absence.
        --no-worktree) no_wt="${2:-non serve isolamento per questa card}"; shift 2 ;;
        *) shift ;;
      esac
    done
    f="$KB/todo/$id.md"; [ -e "$f" ] || { echo "no todo card $id" >&2; exit 1; }
    # DISCIPLINE gate, not a security boundary: --by is honor-system — any caller can pass
    # `--by roberto`. There is deliberately no blocking check here (that would break the
    # documented "do all the todos" autonomous flow). Instead, every kb start ATTEMPT — even
    # a refused one — gets an audit line appended to the card: who claimed it, when, and
    # whether it came from an interactive terminal. Bypasses are honor-system but not
    # invisible; see kanban/README.md.
    interactive=no; [ -t 0 ] && interactive=yes
    printf 'kb_start_audit: "at=%s by=%s interactive=%s"\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${by:-(unset)}" "$interactive" >> "$f"
    if [ -z "$by" ]; then echo "REFUSED: todo->doing is a human gate. Approve with: kb start $id --by roberto" >&2; exit 1; fi
    if _field "$f" dod | grep -q 'FILL:' || _field "$f" acceptance | grep -q 'FILL:'; then
      echo "REFUSED: fill Definition of Done + Acceptance first (kb edit $id)" >&2; exit 1
    fi
    repo_val="$(_field "$f" repo)"
    if [ -z "$repo_val" ] || printf '%s' "$repo_val" | grep -q 'FILL:'; then
      echo "REFUSED: fill repo first (kb edit $id) — e.g. repo: roberdan-os, repo: convergio, repo: personal" >&2; exit 1
    fi
    # REGOLA 1 — una card in corso per progetto.
    #
    # Misurato il 2026-07-30: sette card in `doing`, di cui quattro sullo stesso lavoro
    # ("Casa Martucci"), aperte da sette giorni, mentre il progetto principale
    # (VirtualBPMFy27) aveva ZERO card in corso e diciannove in attesa. `doing` non
    # raccontava cosa era in corso: raccontava cosa era stato iniziato e mai chiuso.
    #
    # Il limite e' per REPO, non globale, perche' lavorare su due progetti diversi in
    # parallelo e' legittimo; aprire il secondo fronte sullo STESSO progetto e' il modo in
    # cui nascono i duplicati. Le card senza worktree (approvazioni, decisioni) contano
    # comunque: il problema non e' il conflitto di file, e' non sapere cosa e' in corso.
    if [ -z "${RDA_KB_ALLOW_PARALLEL:-}" ]; then
      _gia_in_corso=""
      for _dc in "$KB/doing"/*.md; do
        [ -e "$_dc" ] || continue
        case "$(basename "$_dc")" in _*) continue ;; esac
        if [ "$(_field "$_dc" repo)" = "$repo_val" ]; then
          _gia_in_corso="$(basename "$_dc" .md)"
          break
        fi
      done
      if [ -n "$_gia_in_corso" ]; then
        echo "REFUSED: '$repo_val' ha gia' una card in corso: $_gia_in_corso" >&2
        echo "  $(_field "$KB/doing/$_gia_in_corso.md" title)" >&2
        echo "  Chiudila (kb finish $_gia_in_corso --thor \"...\") o parcheggiala prima di aprire questa." >&2
        echo "  Motivo: il 2026-07-30 c'erano 4 card aperte sullo stesso lavoro e 0 sul progetto vero." >&2
        echo "  Se servono davvero due fronti sullo stesso progetto: RDA_KB_ALLOW_PARALLEL=1 kb start $id --by roberto" >&2
        exit 1
      fi
    fi
    _set_status "$f" doing
    # started_at is LOCAL and human-readable (Roberto reads it), started_epoch is the machine
    # value every duration is computed from — epoch renders portably on both BSD and GNU date,
    # which parsing a formatted string does not (the _mtime scar, kb.sh §portable mtime).
    { echo "approved_by: $by"; echo "approved_at: $(date +%Y-%m-%d)"
      echo "started_at: $(date '+%Y-%m-%d %H:%M:%S %Z')"; echo "started_epoch: $(date +%s)"; } >> "$f"
    mv "$f" "$KB/doing/"
    d="$KB/doing/$id.md"
    # One worktree per card (rules/best-practices.md § Parallel work): the card is exactly the
    # unit that can run in parallel with another card, so it is the unit of isolation — and a
    # dedicated cwd is what makes this card's token spend attributable instead of guessed.
    if [ -n "$no_wt" ]; then
      echo "worktree_none: \"$no_wt\"" >> "$d"
      echo "doing/$id started (approved by $by; nessun worktree: $no_wt)"
    else
      # worktree.sh already distinguishes its failures on stderr — not a git repo, git
      # refused to attach the branch, git refused to create it from the base. The old
      # `2>/dev/null || true` threw all three away and then asserted ONE of them, so a repo
      # that IS a git repo was told it was not. A false message costs more than an error:
      # you believe it and go looking for the problem where it isn't. Reproduced before
      # fixing — a repo whose worktree path was occupied by a file reported "non e un git
      # repo" while worktree.sh had said "git refused to create card/TEST-3 from master".
      # So: keep the stderr and report what actually failed. `|| true` stays because a card
      # must still start without a worktree (worktree.sh's own contract, its header) — what
      # changes is that the reason is now carried instead of invented.
      _wt_err="$(mktemp)"
      if [ ! -f "$ROOT/kanban/worktree.sh" ]; then
        wt=""; printf 'worktree.sh non trovato in %s/kanban/\n' "$ROOT" > "$_wt_err"
      else
        wt="$(bash "$ROOT/kanban/worktree.sh" create "$repo_val" "$id" 2>"$_wt_err" || true)"
      fi
      if [ -n "$wt" ]; then
        { echo "worktree: $wt"; echo "branch: card/$id"; } >> "$d"
        echo "doing/$id started (approved by $by)"
        echo "  worktree: $wt   (branch card/$id — lavora QUI, non nel checkout principale)"
      else
        # Strip worktree.sh's own prefix and its "card runs without a worktree" tail: the
        # caller already says that. What is worth keeping is the cause.
        # Prefer worktree.sh's OWN lines (it prefixes them "worktree: ") over whatever else
        # landed on stderr. The first version just took the last line, which quietly assumed
        # the cause is always last — @thor produced a case where a later unrelated warning
        # became the reported cause. An assumption about the callee does not belong in the
        # caller, so ask for the callee's own prefix and only then fall back.
        #
        # Every stage ends in `|| true` because kb runs under `set -euo pipefail`: on EMPTY
        # stderr `grep -v` exits 1, pipefail propagates it, and set -e killed kb start
        # mid-way — card already moved to doing, no message, no worktree_none, rc=1. That
        # made the fallback line below unreachable: scaffolding that bought confidence it
        # had not earned, in the exact branch written so kb would not go silent. Found by
        # @thor, reproduced here before fixing.
        _wt_why="$(grep '^worktree: ' "$_wt_err" 2>/dev/null | tail -1 || true)"
        [ -n "$_wt_why" ] || _wt_why="$(grep -v '^[[:space:]]*$' "$_wt_err" 2>/dev/null | tail -1 || true)"
        _wt_why="$(printf '%s' "$_wt_why" | sed -e 's/^worktree: //' \
                     -e 's/ — card runs without a worktree$//' -e 's/"/\x27/g' || true)"
        [ -n "$_wt_why" ] || _wt_why="worktree.sh e' fallito senza dire perche' (stderr vuoto, rc diverso da 0)"
        echo "worktree_none: \"$_wt_why\"" >> "$d"
        echo "doing/$id started (approved by $by; nessun worktree — $_wt_why)"
      fi
      rm -f "$_wt_err"; unset _wt_err _wt_why
    fi
    ;;

  block)
    id="${1:?id required}"; reason="${2:?reason required}"
    f=""
    [ -e "$KB/todo/$id.md" ] && f="$KB/todo/$id.md"
    [ -e "$KB/doing/$id.md" ] && f="$KB/doing/$id.md"
    [ -n "$f" ] || { echo "no todo/doing card $id" >&2; exit 1; }
    _set_status "$f" blocked
    { echo "blocked_reason: \"$reason\""; echo "blocked_at: $(date +%Y-%m-%d)"; } >> "$f"
    [ "$(dirname "$f")" = "$KB/todo" ] || mv "$f" "$KB/todo/"
    echo "todo/$id blocked: $reason"
    ;;

  todo|doing) echo "$(echo "$cmd" | tr a-z A-Z):"; _list "$cmd" ;;
  done) n=$(ls "$KB/done"/*.md 2>/dev/null | grep -vc '/_' || true); echo "DONE ($n):"; _list done; _archive_hint ;;

  finish)
    id="${1:?id required}"; shift || true
    ev=""; keep_wt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --thor) ev="${2:-}"; shift 2 ;;
        # The escape hatch from the clean-worktree gate — it costs a written reason, stamped on
        # the card, so "I left a mess behind" is a decision on the record and not the default.
        --keep-worktree) keep_wt="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    f="$KB/doing/$id.md"; [ -e "$f" ] || { echo "no doing card $id" >&2; exit 1; }
    if [ -z "$ev" ]; then
      echo "REFUSED: doing->done needs @thor validation with EVIDENCE (not a rubber-stamp)." >&2
      echo "  Run @thor vs the acceptance criteria, then: kb finish $id --thor '<commit/test/output>'" >&2
      exit 1
    fi
    if ! _verify_evidence "$ev"; then exit 1; fi
    # Closing a card means nothing is left behind: the worktree must be committed AND merged, or
    # the close is refused. Checked BEFORE any state is written, so a refusal leaves the card
    # exactly where it was — in doing, with its worktree intact.
    # `|| true`: _field ends in grep, which exits 1 when the key is ABSENT — under `set -e` an
    # assignment carrying that status kills the script mid-close. Every card created before this
    # feature has no `worktree:` key, so without this guard `kb finish` would have silently
    # refused all of them. Found by test-kb-done-gate, which closes cards that have no worktree.
    wt="$(_field "$f" worktree || true)"
    if [ -n "$wt" ] && [ -z "$keep_wt" ]; then
      if ! bash "$ROOT/kanban/worktree.sh" remove "$wt" "$(_field "$f" repo)"; then exit 1; fi
      wt_removed=1
    else
      wt_removed=0
    fi
    _set_status "$f" done
    fin_epoch="$(date +%s)"
    { echo 'verified_by: thor'; echo "verified_evidence: $ev"; echo "verified_at: $(date +%Y-%m-%d)"
      echo "finished_at: $(date '+%Y-%m-%d %H:%M:%S %Z')"; echo "finished_epoch: $fin_epoch"; } >> "$f"
    # Freeze the spend now: the transcripts it is computed from grow forever, so a closed card
    # that recomputed on every `kb dash` would get slower and slower for an answer that cannot
    # change. Best-effort — a card with no attributable session simply carries no spend line.
    sp="$(bash "$ROOT/kanban/dash.sh" --spend-line "$f" "$fin_epoch" 2>/dev/null || true)"
    [ -n "$sp" ] && echo "spend: $sp" >> "$f"
    [ "$wt_removed" = "1" ] && echo "worktree_removed_at: $(date '+%Y-%m-%d %H:%M %Z')" >> "$f"
    [ -n "$keep_wt" ] && [ -n "$wt" ] && echo "worktree_kept_why: \"$keep_wt\"" >> "$f"
    mv "$f" "$KB/done/"; echo "done/$id verified by @thor ($ev)"
    ;;

  edit)
    id="${1:?id required}"; f=""
    for c in todo doing done; do [ -e "$KB/$c/$id.md" ] && f="$KB/$c/$id.md"; done
    [ -n "$f" ] || { echo "no card $id" >&2; exit 1; }
    "${EDITOR:-open}" "$f"
    ;;

  history) _history ;;
  archive) _archive_cmd "${1:-}" ;;
  plans)   _plans_list ;;
  plan)    _plan_show "${1:-}" ;;
  cover)   _cover "${1:-}" ;;
  sched)   _sched ;;

  *) usage ;;
esac
