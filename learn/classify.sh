#!/usr/bin/env bash
# learn/classify.sh — shared taxonomy + deterministic classifier for the meta-loop.
# SOURCED (not executed) by learn/capture.sh (validate --class) and learn/distill.sh
# (classify + drop ephemera). Single source of truth for the 5-class taxonomy of
# ADR-0001 §Consequence — so capture and distill can never drift apart.
#
# Deliberately dependency-light: pure bash string ops, no network, no LLM. This is
# what runs in CI and on the nightly launchd job. An optional LLM-assisted path can be
# layered on later behind an env flag; the DEFAULT is and stays this deterministic one.

# The 5 classes (ADR-0001). The order here is ALSO the classifier's precedence.
RDA_LEARN_CLASSES="tool-quirk correction capability-gap voice decision"

# rda_class_valid <class> -> 0 if <class> is one of the taxonomy classes.
rda_class_valid() {
  case " $RDA_LEARN_CLASSES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# rda_is_ephemeral <signal> -> 0 (true) when the signal is noise that must NEVER
# become a note: per-session boilerplate markers and bare cwd pings. This is what
# kills the ~615/619 "session <ts> cwd=<pwd>" records that used to drown distill.
rda_is_ephemeral() {
  local s="$1"
  case "$s" in "{kind:session}"*) return 0 ;; esac        # explicit capture --session marker
  # legacy Stop-hook boilerplate: "session <ts> cwd=<path>" carrying no real lesson
  printf '%s' "$s" | grep -qiE '^[[:space:]]*session[[:space:]].*cwd=' && return 0
  return 1
}

# rda_strip_token <signal> -> the signal with a leading "{...} " control token
# (e.g. "{class:correction} " or "{kind:session} ") removed, so the note body is clean.
rda_strip_token() {
  local s="$1"
  case "$s" in
    "{"*"} "*) printf '%s' "${s#*\} }" ;;
    *)         printf '%s' "$s" ;;
  esac
}

# rda_classify <signal> -> echoes EXACTLY ONE taxonomy class. Never "TODO".
# An explicit "{class:X}" token from capture.sh --class wins outright; otherwise
# first-match keyword heuristics in taxonomy precedence order; a real (non-ephemeral)
# learning that matches nothing defaults to the most general reusable class, `decision`
# — the human curator can retag before approving, since promotion is human-gated.
rda_classify() {
  local s="$1" low c
  case "$s" in
    "{class:"*"}"*)
      c="${s#\{class:}"; c="${c%%\}*}"
      if rda_class_valid "$c"; then printf '%s' "$c"; return 0; fi ;;
  esac
  low="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    *tool*|*" cli"*|*flag*|*quirk*|*workaround*|*silently*|*"exit code"*|*hangs*|*timeout*|*shellcheck*|*launchd*|*gbrain*)
      printf 'tool-quirk'; return 0 ;;
  esac
  case "$low" in
    *forgot*|*"should have"*|*mistake*|*wrong*|*"don't "*|*"do not "*|*correction*|*"instead of"*|*"remember to"*)
      printf 'correction'; return 0 ;;
  esac
  case "$low" in
    *"can't"*|*cannot*|*"no way to"*|*missing*|*"not supported"*|*unable*|*lacks*|*"would be nice"*|*"there's no"*|*"need a "*)
      printf 'capability-gap'; return 0 ;;
  esac
  case "$low" in
    *voice*|*tone*|*phrasing*|*wording*|*persona*)
      printf 'voice'; return 0 ;;
  esac
  case "$low" in
    *decided*|*decision*|*chose*|*"we will"*|*"going with"*|*"prefer "*|*adr*)
      printf 'decision'; return 0 ;;
  esac
  printf 'decision'   # non-ephemeral, no keyword hit → general reusable lesson (human retags)
}
