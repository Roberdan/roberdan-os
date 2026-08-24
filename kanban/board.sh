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
# A board row is id + (repo) + ONE line saying what the card does / should do. The id is
# the key you pass to show/start/finish, so it is NEVER truncated: everything else gives
# way first. Fields are joined with US (\x1f) because a title may contain anything a human
# types except a control character.
_ROW_SEP=$'\x1f'

# The one line. `title:` is the card's own summary; when it is missing (legacy cards) fall
# back to the first clause of the Definition of Done — "what it should do" is literally
# what dod: records — rather than printing an opaque id with nothing next to it.
_card_summary() {
  local f="$1" s
  s="$(_field "$f" title)"
  if [ -z "$s" ]; then
    s="$(_field "$f" dod)"
    s="${s%%;*}"; s="${s%%. *}"
    [ -n "$s" ] && s="dod: $s"
  fi
  printf '%s' "${s:-(nessun titolo — kb show per il contenuto)}"
}

_board_row() {
  local f="$1"
  printf '%s%s%s%s%s' "$(basename "$f" .md)" "$_ROW_SEP" "$(_repo_tag "$f")" "$_ROW_SEP" "$(_card_summary "$f")"
}

# Pad/truncate by CHARACTERS, not bytes: printf '%-*s' counts bytes, so an accented title
# (perché, già) would shift every border to its right. ${#s} counts characters under a
# UTF-8 locale, and the ellipsis is written separately so the cut never splits a glyph.
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
    while IFS='|' read -r _ f; do [ -n "$f" ] && N+=("$(_board_row "$f")"); done \
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
  local sumw=$((cols - 4 - idw - 2 - rpw - 2))
  [ "$sumw" -lt 20 ] && sumw=20
  local rule; rule="$(printf '─%.0s' $(seq 1 $((idw + rpw + sumw + 8))))"

  printf '%s · DOING (%s) · %s\n' "TO DO ($nt)" "$nd" "$done_label"
  printf '%s\n' "$rule"
  _board_section "TO DO ($nt)"    "$idw" "$rpw" "$sumw" ${T[@]+"${T[@]}"}
  _board_section "DOING ($nd)"    "$idw" "$rpw" "$sumw" ${D[@]+"${D[@]}"}
  local done_hdr="$done_label"
  [ "$nn" -gt 0 ] && done_hdr="$done_label — le $nn più recenti"
  _board_section "$done_hdr" "$idw" "$rpw" "$sumw" ${N[@]+"${N[@]}"}
  _archive_hint
}

# one column of the board: a header, then one aligned line per card. Empty columns say so
# explicitly — a blank gap is indistinguishable from a render that failed.
_board_section() {
  local label="$1" idw="$2" rpw="$3" sumw="$4"; shift 4
  printf '\n  %s\n' "$label"
  if [ "$#" -eq 0 ]; then printf '    %s\n' "(vuota)"; return 0; fi
  local r id rp sum
  for r in "$@"; do
    id="${r%%$_ROW_SEP*}"; r="${r#*$_ROW_SEP}"
    rp="${r%%$_ROW_SEP*}"; sum="${r#*$_ROW_SEP}"
    printf '    %s  %s  %s\n' \
      "$(_pad "$id" "$idw")" \
      "$(_pad "$(_trunc "($rp)" "$rpw")" "$rpw")" \
      "$(_trunc "$sum" "$sumw")"
  done
}