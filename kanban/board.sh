#!/usr/bin/env bash
# kanban/board.sh — how `kb` / `kb view` / `kb all` DRAW the board.
#
# Sourced (never executed) by kanban/kb.sh, lazily, the first time a board is actually
# rendered. It uses kb.sh's own helpers — _field, _repo_tag, _mtime, _board_roots,
# _archive_hint, $KB — so it has no meaning on its own; it lives in a separate file because
# kb.sh is already far past the 300-line rule and a table renderer is a self-contained unit.
#
# The one property worth restating: a board exists to say WHAT each card is. An id with no
# sentence next to it forces a `kb show` per card, which is the wall of opaque timestamps
# this file was written to delete.

# --- board row primitives ---------------------------------------------------
# A board row is id + (repo) + a COMPLETE SENTENCE saying what the card does / should do.
# The id is the key you pass to show/start/finish, so it is NEVER truncated; the sentence
# is never truncated either — it WRAPS under its own column (see _board_section). Fields
# are joined with US (\x1f) because a title may contain anything a human types except a
# control character.
_ROW_SEP=$'\x1f'

# One sentence, not a fragment. `title:` is what the card is; `dod:` is the condition that
# would make it finished — together they answer "cosa fa / cosa dovrebbe fare", which is the
# question a board exists to answer. A card with no title: (legacy) is described by its dod:
# alone rather than left blank, and a card with neither says so explicitly instead of showing
# an id with nothing next to it.
#
# The dod: is cut at its first clause and capped: some are 300+ characters of acceptance
# prose, and pasting all of it onto the board would bury the ten other cards. `kb show` is
# still the place for the full text — this is the synthesis, not the card.
_DOD_MAX=200
_card_summary() {
  local f="$1" want_dod="${2:-1}" t d
  t="$(_field "$f" title)"
  # DONE is history: there the sentence is enough, and ten cards x "Fatta quando: ..." would
  # make the archive the longest part of the board. The condition matters where the work is
  # still ahead of you — todo/doing. It stays a FALLBACK everywhere, though: a legacy card
  # with no title: must still be described, in done/ as much as anywhere else.
  d=""
  if [ "$want_dod" = "1" ] || [ -z "$t" ]; then d="$(_field "$f" dod)"; fi
  case "$d" in FILL:*|"") d="" ;; esac
  # first clause only: dod: are written as "A; B; C" or "A. B. C"
  d="${d%%;*}"; d="${d%% . *}"
  case "$d" in *". "*) d="${d%%. *}." ;; esac
  if [ "${#d}" -gt "$_DOD_MAX" ]; then d="${d:0:$_DOD_MAX}…"; elif [ -n "$d" ]; then d="$(_sentence "$d")"; fi
  if [ -n "$t" ] && [ -n "$d" ]; then
    printf '%s%sFatta quando: %s' "$(_sentence "$t")" "$_ROW_SEP" "$d"
  elif [ -n "$t" ]; then
    printf '%s' "$(_sentence "$t")"
  elif [ -n "$d" ]; then
    printf 'Fatta quando: %s' "$d"
  else
    printf '(nessun titolo e nessun dod: — kb show %s per il contenuto)' "$(basename "$f" .md)"
  fi
}

# A title is often written as a fragment ("evolve: analyze copilot updates"). Closing it with
# a full stop is the cheapest thing that makes the board read as prose instead of as labels;
# it is cosmetic and deliberately does nothing else — rewriting a human's words to sound like
# a sentence is how a summary starts lying about what the card says.
_sentence() {
  local s="$1"
  case "$s" in *.|*!|*\?|*:|*…) printf '%s' "$s" ;; *) printf '%s.' "$s" ;; esac
}

_board_row() {
  local f="$1" want_dod="${2:-1}"
  printf '%s%s%s%s%s' "$(basename "$f" .md)" "$_ROW_SEP" "$(_repo_tag "$f")" "$_ROW_SEP" "$(_card_summary "$f" "$want_dod")"
}

# Pad by CHARACTERS, not bytes: printf '%-*s' counts bytes, so an accented title (perché,
# già) would shift every column to its right. ${#s} counts characters under a UTF-8 locale.
_pad() {
  local s="$1" w="$2" n
  n=$((w - ${#s}))
  [ "$n" -lt 0 ] && n=0
  printf '%s%*s' "$s" "$n" ''
}
_trunc() {
  local s="$1" w="$2"
  [ "$w" -lt 1 ] && { printf ''; return; }
  if [ "${#s}" -le "$w" ]; then printf '%s' "$s"; else printf '%s…' "${s:0:$((w-1))}"; fi
}

# Word wrap, in bash, by characters. Not `fold`: fold on macOS counts BYTES, so it breaks a
# line early — and mid-glyph — as soon as a summary contains an accent, which is most of them
# here. A single word longer than the column (a URL, a path) is hard-split rather than allowed
# to blow the column open. Emits one wrapped line per line of output.
_wrap() {
  local text="$1" w="$2" line="" word
  [ "$w" -lt 8 ] && w=8
  for word in $text; do
    while [ "${#word}" -gt "$w" ]; do
      [ -n "$line" ] && { printf '%s\n' "$line"; line=""; }
      printf '%s\n' "${word:0:$w}"
      word="${word:$w}"
    done
    if [ -z "$line" ]; then line="$word"
    elif [ "$(( ${#line} + 1 + ${#word} ))" -le "$w" ]; then line="$line $word"
    else printf '%s\n' "$line"; line="$word"
    fi
  done
  [ -n "$line" ] && printf '%s\n' "$line"
  return 0
}

# visual kanban, stacked by column so every card gets ONE readable line:
#
#     260802-135739  (VirtualBPMFy27)  Sort before cutting: the queue must stay stable
#
# WHY NOT SIDE-BY-SIDE ANYMORE. Three 34-wide columns could only hold "id (repo)", so the
# board printed a wall of opaque timestamps: to learn what 260802-135739 was you had to run
# `kb show` on each one. A card's whole point is the sentence saying what it does / should
# do, and that sentence does not fit next to two other columns. Stacking gives it the full
# terminal width, and the id/repo columns stay aligned across ALL three sections so the
# board still reads as a table. The three counts are printed once, on a single summary line
# (also what `kb counts` mirrors — test-kb-views pins them equal).
#
# Default: the current-repo board ($KB). With --all: the same shape aggregated across every
# registered board (home + registry), each card still tagged with its repo:.
_board() {
  local f bd
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
    for f in "$bd/todo"/*.md;  do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; T+=("$(_board_row "$f")"); done
    for f in "$bd/doing"/*.md; do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; D+=("$(_board_row "$f")"); done
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
    while IFS='|' read -r _ f; do [ -n "$f" ] && N+=("$(_board_row "$f" 0)"); done \
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
  local nt=${#T[@]} nd=${#D[@]} nn=${#N[@]}
  local done_label="DONE ($ntot"
  [ "$narch" -gt 0 ] && done_label="$done_label +$narch arch"
  done_label="$done_label)"

  # Column widths measured on the rows actually printed, so nothing is padded to a width
  # no card uses. The id column never truncates (it is the key you type back); repo and
  # the summary absorb the pressure, in that order.
  local -a ALL=()
  ALL+=(${T[@]+"${T[@]}"}); ALL+=(${D[@]+"${D[@]}"}); ALL+=(${N[@]+"${N[@]}"})
  local idw=2 rpw=4 r _id _rp
  for r in ${ALL[@]+"${ALL[@]}"}; do
    _id="${r%%$_ROW_SEP*}"; r="${r#*$_ROW_SEP}"; _rp="${r%%$_ROW_SEP*}"
    [ "${#_id}" -gt "$idw" ] && idw="${#_id}"
    _rp="($_rp)"; [ "${#_rp}" -gt "$rpw" ] && rpw="${#_rp}"
  done
  [ "$rpw" -gt 24 ] && rpw=24
  local cols="${COLUMNS:-0}"
  [ "$cols" -lt 20 ] && cols="$(tput cols 2>/dev/null || echo 100)"
  [ "$cols" -lt 60 ] && cols=60
  [ "$cols" -gt 160 ] && cols=160
  # Two shapes, one rule: the sentence must have room to BE a sentence. While it gets 40+
  # characters, id and (repo) stay in their own columns and the text wraps beside them (a
  # table). Below that — a narrow terminal, or very long ids — the columns would squeeze the
  # text into a ragged 25-character ribbon, so the card becomes a block instead: id + (repo)
  # on their own line, the sentence indented underneath with nearly the whole width.
  local sumw=$((cols - 4 - idw - 2 - rpw - 2)) blockw=0
  if [ "$sumw" -lt 40 ]; then blockw=$((cols - 6)); sumw="$blockw"; fi
  [ "$sumw" -lt 20 ] && sumw=20
  local rulew=$((idw + rpw + sumw + 8))
  [ "$blockw" -gt 0 ] && rulew=$((blockw + 4))
  local rule; rule="$(printf '─%.0s' $(seq 1 $rulew))"

  printf '%s · DOING (%s) · %s\n' "TO DO ($nt)" "$nd" "$done_label"
  printf '%s\n' "$rule"
  _board_section "TO DO ($nt)" "$idw" "$rpw" "$sumw" 1 "$blockw" ${T[@]+"${T[@]}"}
  _board_section "DOING ($nd)" "$idw" "$rpw" "$sumw" 1 "$blockw" ${D[@]+"${D[@]}"}
  local done_hdr="$done_label"
  [ "$nn" -gt 0 ] && done_hdr="$done_label — le $nn più recenti"
  _board_section "$done_hdr" "$idw" "$rpw" "$sumw" 0 "$blockw" ${N[@]+"${N[@]}"}
  _archive_hint
}

# One column of the board. Each card is a block: id + (repo) on the first line, and the
# card's sentence WRAPPED under its own column — never cut. A `dod:` follows as a second,
# indented paragraph ("Fatta quando: …"), because "what it does" and "when it is finished"
# are two different statements and running them together reads as one confused one.
#
# Blocks are separated by a blank line for the columns a human acts on (todo/doing); DONE
# is finished work and stays compact. Empty columns say "(vuota)" — a blank gap is
# indistinguishable from a render that died halfway.
_board_section() {
  local label="$1" idw="$2" rpw="$3" sumw="$4" spaced="$5" blockw="$6"; shift 6
  printf '\n  %s\n' "$label"
  if [ "$#" -eq 0 ]; then printf '    %s\n' "(vuota)"; return 0; fi
  local r id rp sum head cont first=1 ln para
  # continuation lines start exactly under the summary column, so a wrapped sentence reads
  # as one paragraph instead of drifting back under the id.
  cont="$(printf '    %*s  %*s  ' "$idw" '' "$rpw" '')"
  [ "$blockw" -gt 0 ] && cont="      "
  for r in "$@"; do
    id="${r%%$_ROW_SEP*}"; r="${r#*$_ROW_SEP}"
    rp="${r%%$_ROW_SEP*}"; sum="${r#*$_ROW_SEP}"
    [ "$first" -eq 0 ] && [ "$spaced" = "1" ] && echo
    first=0
    if [ "$blockw" -gt 0 ]; then
      printf '    %s  (%s)\n' "$id" "$rp"
      head="      "
    else
      head="$(printf '    %s  %s  ' "$(_pad "$id" "$idw")" "$(_pad "$(_trunc "($rp)" "$rpw")" "$rpw")")"
    fi
    # the summary may carry a second paragraph (the dod:), separated by the same US byte
    while [ -n "$sum" ]; do
      case "$sum" in
        *"$_ROW_SEP"*) para="${sum%%$_ROW_SEP*}"; sum="${sum#*$_ROW_SEP}" ;;
        *)             para="$sum"; sum="" ;;
      esac
      [ -n "$para" ] || continue
      while IFS= read -r ln; do
        printf '%s%s\n' "$head" "$ln"
        head="$cont"
      done < <(_wrap "$para" "$sumw")
    done
  done
}
