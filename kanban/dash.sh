#!/usr/bin/env bash
# kanban/dash.sh — the informative half of `kb`: for every DOING card when it started (in
# Roberto's local time) and how long it has been running; for every DONE card how long it took,
# what it cost, what was actually done, and where its worktree went.
#
# It is a SEPARATE command from `kb view` on purpose. `view` is what the SessionStart hook
# injects into every session in every repo — that output is a per-session token tax and stays
# lean (best-practices.md § Context & Token Economy). `kb` typed by a human runs this.
#
# Honest limits, printed as such and never hidden behind a plausible number:
#   - Old cards carry date-only stamps (`approved_at`/`verified_at`), so their times render as
#     a date and their duration as "-". A computed "0m" would be a fabricated fact.
#   - Token spend is attributed by the session's WORKING DIRECTORY. A card with its own
#     worktree therefore gets its own real number; a card without one falls back to a time
#     window over the repo, which is shared with every other card open in that window — that
#     case is labelled "condivisa con N card", never printed as if it were the card's own.
#   - No network calls. PR references come from the evidence string the card already carries,
#     never from `gh` (same precedent as `kb pending --count`).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="$ROOT/kanban/worktree.sh"
DONE_N="${RDA_DASH_DONE:-5}"   # how many closed cards to detail

_field() { grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//; s/^\"//; s/\"\$//"; }

# --- time ------------------------------------------------------------------
# GNU (-d) first, BSD (-r/-jf) second: on macOS the GNU form fails cleanly, while on Linux
# `date -r` means "read format from file" and prints garbage instead of failing. Same ordering
# discipline (and the same scar) as kb.sh's _mtime.
_now() { date +%s; }
_local() { # epoch -> "28/07/2026 11:41 CEST" in the local timezone
  # Numeric + timezone name on purpose: month/day names come out in whatever LC_TIME the shell
  # happens to carry (English on a default macOS shell), and a dashboard Roberto reads should
  # not change language with the environment.
  local e="$1" fmt='+%d/%m/%Y %H:%M %Z'
  date -d "@$e" "$fmt" 2>/dev/null || date -r "$e" "$fmt" 2>/dev/null || echo '-'
}
_epoch_iso() { # 2026-07-25T18:18:15Z -> epoch
  local s="$1"
  date -d "$s" +%s 2>/dev/null || TZ=UTC date -jf '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null || echo ''
}
_dur() { # seconds -> "3g 4h" / "2h 13m" / "45m"
  local s="${1:-}"; [ -n "$s" ] && [ "$s" -ge 0 ] 2>/dev/null || { echo '-'; return; }
  local d=$((s/86400)) h=$(((s%86400)/3600)) m=$(((s%3600)/60))
  if [ "$d" -gt 0 ]; then printf '%dg %dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}
_num() { # 1234567 -> 1.2M ; 412345 -> 412k
  local n="${1:-0}"
  if [ "$n" -ge 1000000 ] 2>/dev/null; then awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
  elif [ "$n" -ge 1000 ] 2>/dev/null; then awk -v n="$n" 'BEGIN{printf "%dk", n/1000}'
  else printf '%s' "$n"; fi
}

# A card's start epoch, best available source first:
#   started_epoch (stamped by today's kb start) > the LAST kb_start_audit line > "".
# The audit line is appended on every attempt INCLUDING refused ones (kb.sh:1087), so the
# first one can be a refusal from days earlier — the last one is the attempt that succeeded.
_start_epoch() {
  local f="$1" e iso
  e="$(_field "$f" started_epoch)"; [ -n "$e" ] && { printf '%s' "$e"; return; }
  iso="$(grep 'kb_start_audit' "$f" 2>/dev/null | tail -1 | sed 's/.*at=\([^ ]*\).*/\1/')"
  [ -n "$iso" ] && _epoch_iso "$iso"
}
_end_epoch() { _field "$1" finished_epoch; }

# --- spend -----------------------------------------------------------------
# Reads Claude Code's own session transcripts (~/.claude/projects/<slugified-cwd>/*.jsonl) and
# sums the usage each assistant message already records. Bounded twice: only project dirs whose
# name matches the slug of the directory we care about, and only files touched after the window
# opened. Prints "total out turns sessions", or nothing when it cannot tell (no python3, no
# transcripts) — the caller then prints "-" rather than a zero that looks like a measurement.
_spend() { # <cwd-prefix> <since-epoch> [<until-epoch>]
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$1" "${2:-0}" "${3:-0}" "${CLAUDE_PROJECTS:-$HOME/.claude/projects}" <<'PY' 2>/dev/null
import json, os, re, sys
prefix, since, until, root = sys.argv[1], int(sys.argv[2] or 0), int(sys.argv[3] or 0), sys.argv[4]
if not os.path.isdir(root): sys.exit(1)
slug = re.sub(r'[^A-Za-z0-9]', '-', prefix.rstrip('/'))
tot = out = turns = 0; sessions = set()
def ts(s):
    # transcript timestamps are UTC ISO ("...Z"); compare in epoch seconds, never naive-local
    from datetime import datetime, timezone
    try:
        return int(datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S')
                   .replace(tzinfo=timezone.utc).timestamp())
    except Exception:
        return 0
for d in os.listdir(root):
    if not d.startswith(slug): continue
    p = os.path.join(root, d)
    if not os.path.isdir(p): continue
    for fn in os.listdir(p):
        if not fn.endswith('.jsonl'): continue
        fp = os.path.join(p, fn)
        try:
            if since and os.path.getmtime(fp) < since: continue
            fh = open(fp, encoding='utf-8', errors='replace')
        except OSError:
            continue
        with fh:
            for line in fh:
                try: o = json.loads(line)
                except Exception: continue
                cwd = o.get('cwd') or ''
                if cwd and not cwd.startswith(prefix): continue
                t = o.get('timestamp')
                if t and (since or until):
                    e = ts(t)
                    if e:
                        if since and e < since: continue
                        if until and e > until: continue
                u = (o.get('message') or {}).get('usage') or {}
                if not u: continue
                turns += 1
                if o.get('sessionId'): sessions.add(o['sessionId'])
                out += u.get('output_tokens', 0)
                tot += (u.get('input_tokens', 0) + u.get('output_tokens', 0)
                        + u.get('cache_creation_input_tokens', 0) + u.get('cache_read_input_tokens', 0))
if not turns: sys.exit(1)
print(tot, out, turns, len(sessions))
PY
}

# The spend line for one card. Exactly three cases, and the difference between them is the
# whole point — a number whose meaning is not stated is worse than no number:
#   1. `spend:` already frozen on the card by `kb finish` -> print it verbatim.
#   2. the card has its OWN worktree -> the sessions that ran in that directory ARE this card's
#      work, so the number is the card's own.
#   3. no worktree -> the best available answer is every session in the repo during the card's
#      window, which also contains whatever else was open then. Printed only with how many other
#      cards shared that window, never as if it belonged to this card.
# Anything else (no start time, no transcripts, no python3) returns non-zero: the caller prints
# "-", because a fabricated zero reads exactly like a measured one.
_spend_line() { # <card-file> <start-epoch> <end-epoch> <n-other-cards-in-window>
  local f="$1" s="${2:-}" e="${3:-0}" others="${4:-0}" stamped wt sp tot o tr ss
  stamped="$(_field "$f" spend)"
  [ -n "$stamped" ] && { printf '%s' "$stamped"; return 0; }
  [ -n "$s" ] || return 1
  wt="$(_field "$f" worktree)"
  if [ -n "$wt" ]; then
    sp="$(_spend "$wt" "$s" "$e")" || return 1
    read -r tot o tr ss <<<"$sp"
    printf '~%s token (out %s) · %s turni · %s sessioni — worktree della card, spesa sua' \
      "$(_num "$tot")" "$(_num "$o")" "$tr" "$ss"
    return 0
  fi
  local repo path
  repo="$(_field "$f" repo)"; path="$HOME/GitHub/$repo"
  [ -d "$path" ] || return 1
  sp="$(_spend "$path" "$s" "$e")" || return 1
  read -r tot o tr ss <<<"$sp"
  if [ "${others:-0}" -gt 0 ]; then
    printf '~%s token · %s turni nella FINESTRA del repo — condivisa con altre %s card aperte insieme, non e la spesa di questa card' \
      "$(_num "$tot")" "$tr" "$others"
  else
    printf '~%s token (out %s) · %s turni · %s sessioni — attribuiti per finestra sul repo (card senza worktree)' \
      "$(_num "$tot")" "$(_num "$o")" "$tr" "$ss"
  fi
}

_wt_line() { # <card-file>
  local f="$1" wt st
  wt="$(_field "$f" worktree)"
  [ -n "$wt" ] || { printf '%s' "$(_field "$f" worktree_none)"; return; }
  st="$(bash "$WT" status "$wt" "$(_field "$f" repo)" 2>/dev/null || echo '?')"
  printf '%s — %s' "${wt/#$HOME/~}" "$st"
}

_row() { printf '      %-9s %s\n' "$1" "$2"; }

# --- the two detail blocks -------------------------------------------------
_doing_block() {
  local boards=("$@") bd f n=0 s now line conc=0
  now="$(_now)"
  for bd in "${boards[@]}"; do
    for f in "$bd/doing"/*.md; do [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac; conc=$((conc+1)); done
  done
  for bd in "${boards[@]}"; do
    for f in "$bd/doing"/*.md; do
      [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac
      [ "$n" -eq 0 ] && { echo; echo "DOING — in corso adesso (ora locale):"; }
      n=$((n+1))
      printf '  %s (%s) — %s\n' "$(basename "$f" .md)" "$(_field "$f" repo)" "$(_field "$f" title)"
      s="$(_start_epoch "$f")"
      if [ -n "$s" ]; then
        _row "iniziata" "$(_local "$s") · gira da $(_dur $((now - s)))"
      else
        _row "iniziata" "$(_field "$f" approved_at) (solo data — card avviata prima che kb registrasse l'ora)"
      fi
      line="$(_wt_line "$f")"; [ -n "$line" ] && _row "worktree" "$line"
      line="$(_spend_line "$f" "$s" 0 "$((conc - 1))")" && _row "spesa" "$line" || _row "spesa" "- (nessuna sessione attribuibile)"
    done
  done
}

_done_block() {
  local boards=("$@") bd f rows=() n=0
  for bd in "${boards[@]}"; do
    for f in "$bd/done"/*.md; do
      [ -e "$f" ] || continue; case "$(basename "$f")" in _*) continue;; esac
      rows+=("$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)|$f")
    done
  done
  [ "${#rows[@]}" -eq 0 ] && return 0
  echo
  echo "DONE — ultime $DONE_N chiuse (cosa e stato fatto, quanto e costato):"
  while IFS='|' read -r _ f; do
    [ -n "${f:-}" ] || continue
    n=$((n+1))
    printf '  %s (%s) — %s\n' "$(basename "$f" .md)" "$(_field "$f" repo)" "$(_field "$f" title)"
    local s e ev pr line
    s="$(_start_epoch "$f")"; e="$(_end_epoch "$f")"
    if [ -n "$e" ]; then
      if [ -n "$s" ]; then _row "chiusa" "$(_local "$e") · durata $(_dur $((e - s)))"
      else _row "chiusa" "$(_local "$e")"; fi
    else
      _row "chiusa" "$(_field "$f" verified_at) (solo data — durata non registrata)"
    fi
    # A closed card reports the spend FROZEN onto it at `kb finish`, or the exact number from its
    # own worktree — never a recomputed window. Recomputing over a closed window would silently
    # bill this card for everything else that was open at the same time; the 55 cards closed
    # before this command existed would all have shown the same plausible, wrong total.
    if [ -n "$(_field "$f" spend)" ] || { [ -n "$(_field "$f" worktree)" ] && [ -n "$e" ]; }; then
      line="$(_spend_line "$f" "$s" "${e:-0}" 0)" && _row "spesa" "$line"
    else
      _row "spesa" "- (non misurata: card chiusa prima che kb registrasse la spesa)"
    fi
    ev="$(_field "$f" verified_evidence)"
    [ -n "$ev" ] && _row "fatto" "$(printf '%s' "$ev" | cut -c1-110)$([ "${#ev}" -gt 110 ] && printf '...')"
    # PR/issue refs come from the evidence the card already carries — no gh call, no network.
    pr="$(printf '%s' "$ev" | grep -oE '#[0-9]+' | tr '\n' ' ' | sed 's/ $//')"
    [ -n "$pr" ] && _row "PR" "$pr"
    line="$(_wt_line "$f")"
    [ -n "$line" ] && _row "worktree" "$line"
    [ -n "$(_field "$f" worktree_removed_at)" ] && _row "worktree" "rimosso il $(_field "$f" worktree_removed_at) — niente lasciato indietro"
  done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1 -rn | head -"$DONE_N")
  return 0
}

# --spend-line <card-file> [<until-epoch>] — one card's spend string, for `kb finish` to freeze
# onto the card at close time (see kb.sh finish). Prints nothing when nothing is attributable.
if [ "${1:-}" = "--spend-line" ]; then
  shift
  _card="${1:?card file}"; _until="${2:-0}"
  _spend_line "$_card" "$(_start_epoch "$_card")" "$_until" 1 || true
  echo
  exit 0
fi

# Boards to report on are passed in by kb.sh (it owns board resolution).
[ "$#" -gt 0 ] || { echo "usage: dash.sh <kanban-dir> [<kanban-dir>...]" >&2; exit 2; }
_doing_block "$@"
_done_block "$@"
exit 0
