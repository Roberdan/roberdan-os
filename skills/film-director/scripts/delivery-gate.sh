#!/usr/bin/env bash
# delivery-gate.sh — objective checks before a film is shown to anyone.
#   delivery-gate.sh master.mp4 [target_seconds]
# Exit 0 = pass. Every failure prints the measured value, never a guess.
set -uo pipefail

FILM="${1:?usage: delivery-gate.sh <master.mp4> [target_seconds]}"
TARGET="${2:-120}"
[[ -f "$FILM" ]] || { echo "no such file: $FILM" >&2; exit 2; }

FAIL=0
ok()   { printf '  pass  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "== $FILM"

# ---- container / picture --------------------------------------------------
probe() { ffprobe -v error -select_streams v:0 -show_entries "stream=$1" -of default=nw=1:nk=1 "$FILM" | head -1; }
W=$(probe width); H=$(probe height); RATE=$(probe r_frame_rate); VCODEC=$(probe codec_name)
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FILM")
FPS=$(awk -F/ '{printf "%.2f", ($2?$1/$2:0)}' <<<"${RATE:-0/1}")

printf '  %sx%s  %s fps  %s  %.1fs\n' "$W" "$H" "$FPS" "$VCODEC" "$DUR"

awk -v d="$DUR" -v t="$TARGET" 'BEGIN{exit !(d <= t + 3 && d >= t * 0.6)}' \
  && ok "duration within target ${TARGET}s" || bad "duration ${DUR}s vs target ${TARGET}s"
(( W >= 1920 && H >= 1080 )) && ok "resolution >= 1080p" || bad "resolution ${W}x${H} below 1080p"
awk -v f="$FPS" 'BEGIN{exit !(f >= 23.9)}' && ok "frame rate ok" || bad "frame rate $FPS"
[[ "$VCODEC" == "h264" || "$VCODEC" == "hevc" ]] && ok "codec $VCODEC" || warn "codec $VCODEC may not play everywhere"

# ---- audio ----------------------------------------------------------------
ACODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$FILM")
if [[ -z "$ACODEC" ]]; then
  bad "no audio stream"
else
  ok "audio stream ($ACODEC)"
  EBU=$(ffmpeg -nostats -i "$FILM" -af ebur128=peak=true -f null - 2>&1 | tail -20)
  I=$(grep -E '^\s*I:' <<<"$EBU" | tail -1 | grep -oE '\-?[0-9]+\.[0-9]+' | head -1)
  TP=$(grep -E 'Peak:' <<<"$EBU" | tail -1 | grep -oE '\-?[0-9]+\.[0-9]+' | head -1)
  LRA=$(grep -E '^\s*LRA:' <<<"$EBU" | tail -1 | grep -oE '\-?[0-9]+\.[0-9]+' | head -1)
  printf '  I %s LUFS  TP %s dBTP  LRA %s\n' "${I:-?}" "${TP:-?}" "${LRA:-?}"
  [[ -n "$I" ]] && awk -v i="$I" 'BEGIN{exit !(i <= -12.5 && i >= -15.5)}' \
    && ok "loudness within -14 +/- 1.5 LUFS" || bad "integrated loudness ${I:-unmeasured} LUFS (target -14)"
  [[ -n "$TP" ]] && awk -v t="$TP" 'BEGIN{exit !(t <= -1.0)}' \
    && ok "true peak <= -1 dBTP" || bad "true peak ${TP:-unmeasured} dBTP (target <= -1)"
  # silence check: a film that is quiet for a third of its length is unfinished
  SIL=$(ffmpeg -nostats -i "$FILM" -af silencedetect=n=-50dB:d=1.5 -f null - 2>&1 \
        | grep -oE 'silence_duration: [0-9.]+' | awk '{s+=$2} END{printf "%.1f", s+0}')
  awk -v s="$SIL" -v d="$DUR" 'BEGIN{exit !(s < d*0.25)}' \
    && ok "silence ${SIL}s acceptable" || warn "silence ${SIL}s of ${DUR}s — missing ambience bed?"
fi

# ---- rhythm ---------------------------------------------------------------
# metadata=print writes to stdout and collides with -f null -; showinfo on stderr is reliable.
# Dissolve-heavy films score low here: a tiny count IS the slideshow signal, not a measuring error.
CUTS=$(ffmpeg -nostats -i "$FILM" -vf "select='gt(scene,0.25)',showinfo" -f null - 2>&1 \
       | grep -c 'pts_time' || true)
SHOTS=$((CUTS + 1))
ASL=$(awk -v d="$DUR" -v n="$SHOTS" 'BEGIN{printf "%.2f", d/n}')
PER120=$(awk -v n="$SHOTS" -v d="$DUR" 'BEGIN{printf "%.0f", n/d*120}')
printf '  %s detected shots  ASL %ss  %s per 120s\n' "$SHOTS" "$ASL" "$PER120"
awk -v a="$ASL" 'BEGIN{exit !(a >= 1.3 && a <= 4.5)}' \
  && ok "ASL in band" || bad "ASL ${ASL}s outside 1.5-4s (slideshow or trailer)"
(( SHOTS < 5 )) && warn "near-zero hard cuts: either a single long take, or a dissolve-driven slideshow" || true
(( PER120 >= 30 )) && ok "shot density" || bad "${PER120} shots per 120s: slideshow"

# ---- contact sheet at cut points ------------------------------------------
SHEET="${FILM%.*}-contact.jpg"
ffmpeg -nostats -loglevel error -y -i "$FILM" \
  -vf "select='gt(scene,0.25)+not(mod(n,90))',scale=480:-1,tile=5x5" -frames:v 1 "$SHEET" 2>/dev/null \
  && ok "contact sheet -> $SHEET  (open it: text ghosting and crops only show here)" \
  || warn "contact sheet not generated"

echo
if (( FAIL )); then
  echo "GATE FAILED — fix the above, then a human still has to watch it end to end."
  exit 1
fi
echo "Gate passed. Machine checks only — now watch it end to end with sound on."
