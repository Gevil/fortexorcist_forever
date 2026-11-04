#!/usr/bin/env bash
# demo_media.sh -- regenerate every file under docs/demo/ from scratch (idempotent).
#
# HOW A CLIP IS MADE (v3, headless -- the v2 GUI path is gone, see below)
#   One scene file per clip: scripts/scenarios/<clip>.lua on
#   scripts/scenarios/fxdemo_lib.lua. The scene seeds the module at clock 0
#   (FXD.SET), scripts its event beats (FXD.EV[k]) and names the frames the
#   clip owns (FXD.BOX).
#   Frame k is a SEPARATE wow-sim process: the same chunk replays beats
#   0..k on the manual clock (A_Admin.SetManualClock(0) + one
#   A_Admin.AdvanceTime(1/30) per beat, docs/reference/wow-ui-sim-specs/
#   time-and-capture.md) and renders `screenshot --png --width 1600 --height
#   1200 --ui-scale 1.6875 --crop WxH+X+Y`. Deterministic by construction: the
#   clock is scripted, so frame k is the same picture in every run, and no
#   live window, window manager, mouse cursor or boot-time UI scale can enter
#   the picture. 30 fps, one frame per 1/30 s of scene time.
#   ffmpeg builds the GIF (palette) and the MP4 from the cropped PNGs.
#
# WHY v2'S CROPS WERE WRONG (measured 2026-11-03, wow-ui-sim v0.1.39)
#   `f:GetRect()` answers in UI UNITS; `screenshot --ui-scale S --width W
#   --height H` lays the UI out at W/S units wide and writes a W x H image, so
#   1 UI unit = S px; the same run's --dump-tree prints frames in device px
#   (a 250x24 bar at uiScale 1.6875: (421x40) x=589, y=832, from GetRect
#   l=349.074 b=193.556 -- 349.074*1.6875 = 589.0). v2 fed GetRect-sized boxes
#   to a --ui-scale 1.6875 capture, so every crop sat up-left of its frame and
#   was 1/1.6875 of the size it needed; its live-GUI path also captured the
#   Blizzard boot UI (issue-report button, action bars) and the cursor, which
#   headless rendering does not have. fxdemo_lib's FXD.B multiplies by the
#   measured factor, scripts/demo/geometry.py re-proves it against the
#   dump-tree rects, and the driver FAILS a clip whose crop a visible Blizzard
#   frame overlaps.
#
# Every run passes --no-saved-vars (the gate's rule: captures set live
# settings, and the sim's SavedVariables store is shared with test runs).
#
# Usage: scripts/demo_media.sh [clip|scene ...]   (default: everything)
# Env:   DEMO_TMP=/tmp/fx_demo   DEMO_JOBS=2 (parallel captures)
#        DEMO_MAXFRAMES=n        (smoke runs)
#        DEMO_SAMPLES=dir        (start/middle/end PNGs of every clip)
# Budget: GIFs <= 8 MB, other files <= 3 MB, total <= 26 MB -- fails if over.
set -euo pipefail

# The pipeline runs when the script is EXECUTED. Sourcing it (a reader probing
# a function) must not start a 20-minute render.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  FXD_DEMO_SOURCED=1
  return 0 2>/dev/null || exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="${WOW_UI_SIM:-$(dirname "$ROOT")/wow-ui-sim/run.sh}"
ADDONS="$ROOT/addon"
SDIR="$ROOT/scripts/demo"
SCEN="$ROOT/scripts/scenarios"
OUT="$ROOT/docs/demo"
GEO="$SDIR/geometry.py"
TMP="${DEMO_TMP:-/tmp/fx_demo}"
W=1600; H=1200
UISCALE=1.6875          # 1440p at uiScale 0.9; >=1.0 selects the 2x atlas art
FPS=30
JOBS="${DEMO_JOBS:-2}"
rm -rf "$TMP"; mkdir -p "$TMP" "$OUT"
[ -x "$SIM" ] || { echo "wow-ui-sim not found at $SIM" >&2; exit 1; }
[ -f "$GEO" ] || { echo "missing $GEO" >&2; exit 1; }

# ------------------------------------------------------------------- shared
# report <file> [frames]
report() {
  local f=$1 fr=${2:-} sz w h nf
  sz=$(wc -c < "$f")
  case "$f" in
    (*.png) w=$(pngsize "$f" 0); h=$(pngsize "$f" 1) ;;
    (*) eval "$(ffprobe -v error -count_frames -select_streams v:0 \
            -print_format json -show_streams "$f" \
            | python3 -c '
import json, sys
d = json.load(sys.stdin)
s = [x for x in d.get("streams", []) if x.get("codec_type") == "video"][0]
print("w=%s; h=%s; nf_probe=%s" % (s.get("width", "?"), s.get("height", "?"),
      s.get("nb_read_frames") or s.get("nb_frames") or "?"))')" ;;
  esac
  nf=$fr
  [ -n "$fr" ] || nf=$(ffprobe -v error -count_frames -print_format json -show_streams "$f" \
    | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["streams"] if x.get("codec_type")=="video"][0]
print(s.get("nb_read_frames","?"))')
  [ -n "${nf:-}" ] || nf=${nf_probe:-?}
  printf 'FILE %s %sx%s %sB frames=%s\n' "$(basename "$f")" "$w" "$h" "$sz" "$nf"
}

# pngsize <png> <0=width|1=height>
pngsize() {
  python3 -c '
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print(im.size[int(sys.argv[2])])' "$1" "$2"
}

# boot_lines <frames> [slots]  -> the chunk tail: the clip's numbers, the seed,
# the beat replay, the final box pass.
boot_lines() {
  printf 'FXD.SLOTS=%s FXD.PEAK=%s FXD.SECONDS=%s\n' "${2:-0}" "${1:-0}" \
    "$(python3 -c "print(${2:-30}/$FPS)")"
  printf 'FXD.SET() FXD.b={} FXD.U() FXD.BOX()\n'
  printf 'for fk=0,%s do FXD.Frame(fk) end\n' "${1:-0}"
  printf 'FXD.BOX()\n'
}

# capture_boot <frames> [slots]: the capture's chunk tail. The probe host and
# its markers paint nothing, so they need no hiding; the clip's own frames are
# the only art in the crop.
capture_boot() { boot_lines "$@"; }

# scene_of <name> -> $TMP/<name>.scene.lua (lib + scene)
scene_of() {
  local name=$1
  local scene="$SCEN/$name.lua"
  [ -f "$scene" ] || { echo "no scene $scene" >&2; return 1; }
  cat "$SCEN/fxdemo_lib.lua" "$scene" > "$TMP/$name.scene.lua"
}

# runsim <class> <chunk> <subcommand args...>
runsim() {
  local class=$1 chunk=$2; shift 2
  ( cd /tmp && "$SIM" wow-sim --allow-ui-version-mismatch --no-saved-vars \
      --addons-path "$ADDONS" --class "$class" --delay 3000 \
      --exec-lua "@$chunk" "$@" )
}

# geometry <dt.log> -> "x y w h" + the proof lines (fails on an intruder)
geometry() { python3 "$GEO" box "$1"; }

# --------------------------------------------------------------------- clips
# CROP is exported so the parallel workers see it.
# The parallel captures run as `bash -c` children of xargs: every variable a
# function they inherit reads MUST be exported (an unexported $FPS once built
# a per-frame chunk with an empty FXD.SECONDS -- a Lua syntax error, a scene
# that never ran, and a clip of blank frames that looked fine by byte size).
export ROOT SIM ADDONS SDIR SCEN OUT GEO W H UISCALE TMP FPS JOBS
capture_frame() {                       # <name> <class> <k> <out.png>
  local name=$1 class=$2 k=$3 out=$4
  local chunk="$TMP/$name.f$k.lua"
  { cat "$TMP/$name.scene.lua"; capture_boot "$k" "$NSLOTS"; } > "$chunk"
  runsim "$class" "$chunk" screenshot --png -o "$out" \
    --width "$W" --height "$H" --ui-scale "$UISCALE" --crop "$CROP" \
    > "$TMP/$name.f$k.log" 2>&1
}
export -f capture_frame capture_boot boot_lines runsim pngsize

# clip <name> <class> <frames> <gifscale>
clip() {
  local name=$1 class=$2 n=$3 gs=$4
  if [ -n "${DEMO_MAXFRAMES:-}" ] && [ "$n" -gt "${DEMO_MAXFRAMES:-0}" ]; then
    n=$DEMO_MAXFRAMES
  fi
  local peak=$((n * 85 / 100)); [ "$peak" -gt 0 ] || peak=1
  echo "== clip $name ($class, $n frames @ ${FPS} fps = $(python3 -c "print($n/$FPS)")s, box from frame $peak)"
  scene_of "$name"

  # 1. the geometry run: the scene at frame $peak, dump-tree + readout boxes.
  export NSLOTS=$n
  { cat "$TMP/$name.scene.lua"; boot_lines "$peak" "$n"; } > "$TMP/$name.box.lua"
  runsim "$class" "$TMP/$name.box.lua" screenshot --png -o "$TMP/$name.box.png" \
    --width "$W" --height "$H" --ui-scale "$UISCALE" --dump-tree \
    > "$TMP/$name.dt.log" 2>&1
  local bx by bw bh
  if ! read -r bx by bw bh <<< "$(geometry "$TMP/$name.dt.log")"; then
    echo "  geometry gate failed for $name" >&2; return 1
  fi
  case "$bx$by$bw$bh" in (*[!0-9]*|'') echo "  no crop box for $name" >&2; return 1;; esac
  CROP="${bw}x${bh}+${bx}+${by}"
  export CROP
  echo "  crop $CROP"
  python3 "$GEO" facts "$TMP/$name.dt.log"

  # 2. the frames, $JOBS at a time.
  local od="$TMP/$name.frames"; rm -rf "$od"; mkdir -p "$od"
  seq 0 $((n - 1)) | xargs -P "$JOBS" -I{} bash -c \
    'capture_frame "$1" "$2" {} "$3/$(printf "f_%04d.png" {})"' _ "$name" "$class" "$od"
  local got; got=$(printf '%s\n' "$od"/f_*.png | wc -l)
  [ "$got" = "$n" ] || { echo "  captured $got of $n frames" >&2; return 1; }
  # Every capture must be exactly the crop, and no capture may be blank.
  local pw ph blank k
  pw=$(pngsize "$od/f_0000.png" 0); ph=$(pngsize "$od/f_0000.png" 1)
  [ "$pw" = "$bw" ] && [ "$ph" = "$bh" ] \
    || { echo "  capture ${pw}x${ph} does not match the crop ${bw}x${bh}" >&2; return 1; }
  blank=0
  for k in "$od"/f_*.png; do
    [ "$(wc -c < "$k")" -gt 4096 ] || blank=$((blank + 1))
  done
  [ "$blank" = 0 ] || { echo "  $blank frame(s) are (near) empty" >&2; return 1; }

  # 3. GIF (palette, downscaled until it fits the budget) + MP4.
  while :; do
    ffmpeg -hide_banner -loglevel error -y -framerate "$FPS" -start_number 0 \
      -i "$od/f_%04d.png" \
      -vf "scale=trunc(iw*$gs/2)*2:trunc(ih*$gs/2)*2:flags=lanczos,palettegen=stats_mode=full" \
      "$TMP/$name.pal.png"
    ffmpeg -hide_banner -loglevel error -y -framerate "$FPS" -start_number 0 \
      -i "$od/f_%04d.png" -i "$TMP/$name.pal.png" \
      -lavfi "[0:v]scale=trunc(iw*$gs/2)*2:trunc(ih*$gs/2)*2:flags=lanczos[s];[s][1:v]paletteuse=dither=none[v]" \
      -map "[v]" "$OUT/$name.gif"
    local sz; sz=$(wc -c < "$OUT/$name.gif")
    if [ "$sz" -le 8388608 ] || [ "$gs" -le 1 ]; then break; fi
    echo "  gif ${sz}B over budget at scale $gs -> $((gs - 1))"
    gs=$((gs - 1))
  done
  ffmpeg -hide_banner -loglevel error -y -framerate "$FPS" -start_number 0 \
    -i "$od/f_%04d.png" \
    -vf "scale=trunc(iw*$gs/2)*2:trunc(ih*$gs/2)*2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset veryslow -crf 20 -movflags +faststart "$OUT/$name.mp4"
  report "$OUT/$name.gif" "$n"
  report "$OUT/$name.mp4" "$n"

  # 4. review samples: start / middle / end.
  if [ -n "${DEMO_SAMPLES:-}" ]; then
    mkdir -p "$DEMO_SAMPLES"
    local s
    for s in 0 $((n / 2)) $((n - 1)); do
      cp "$(printf "$od/f_%04d.png" "$s")" \
         "$DEMO_SAMPLES/$name-$(printf '%02dpct' $((s * 100 / (n - 1)))))".png
    done
  fi
}

# -------------------------------------------------------------------- scenes
# scene <outname> <class> <body.lua>   (static PNG via scripts/demo/prelude.lua)
scene() {
  local name=$1 class=$2 body=$3
  echo "== scene $name ($class, $body)"
  local chunk="$TMP/$name.chunk.lua"
  cat "$SDIR/prelude.lua" "$SDIR/$body" > "$chunk"
  # ui-scale 1: the static PNGs keep the 1:1 UI-unit-to-pixel map, so the
  # prelude's boxes are already device pixels.
  runsim "$class" "$chunk" dump-tree -v --visible-only \
    > "$TMP/$name.dt.log" 2>&1
  local x y w h
  if ! read -r x y w h <<< "$(geometry "$TMP/$name.dt.log")"; then
    echo "  geometry gate failed for $name" >&2; return 1
  fi
  python3 "$GEO" facts "$TMP/$name.dt.log"
  echo "  crop ${w}x${h}+${x}+${y} (device px, frame GetRect x scale + pad)"
  runsim "$class" "$chunk" screenshot --png -o "$TMP/$name.raw.png" \
    --width "$W" --height "$H" --crop "${w}x${h}+${x}+${y}" \
    > "$TMP/$name.png.log" 2>&1
  ffmpeg -hide_banner -loglevel error -y -i "$TMP/$name.raw.png" \
    -vf "scale=iw*2:ih*2:flags=lanczos" "$OUT/$name.png"
  report "$OUT/$name.png" 1
}

# ---------------------------------------------------------------------- main
only="${*:-}"
want() { [ -z "$only" ] && return 0; local w; for w in $only; do [ "$w" = "$1" ] && return 0; done; return 1; }
run() {
  local tag=$1; shift
  want "$tag" || return 0
  "$@" || { echo "  FAILED: $tag" >&2; fails=$((fails + 1)); }
}

echo "== demo_media v3 (headless, ${FPS} fps, ui-scale $UISCALE, jobs=$JOBS)"
# One media item failing must not hide the state of the rest: the run does them
# all (each through the `want` filter) and reports the tally at the budget gate.
fails=0
run cooldown-bar   clip  cooldown-bar        Hunter  150 3
run spell-timer    clip  spell-timer         Warlock 150 3
run hunter-swing   clip  hunter-swing        Hunter  180 3
run warlock-plates clip  warlock-plates      Warlock 150 2
run bar-and-timer  scene cooldown-bar-and-timer Hunter  barandtimer.lua
run warlock-png    scene warlock-plates      Warlock warlock.lua
run options-png    scene options-window      Hunter  options.lua
[ "$fails" = 0 ] || { echo "== $fails media item(s) failed" >&2; exit 1; }

echo "== budget check"
python3 - "$OUT" <<'PYEOF'
import sys, os, glob
tot, fail = 0, 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*'))):
    sz = os.path.getsize(f); tot += sz
    lim = 8 * 1024 * 1024 if f.endswith('.gif') else (3 * 1024 * 1024)
    ok = 'ok  ' if sz <= lim else 'OVER'
    if sz > lim: fail += 1
    print('  %s %-30s %9d B' % (ok, os.path.basename(f), sz))
print('  total %d B (cap 26 MB)' % tot)
assert tot <= 26 * 1024 * 1024 and not fail, 'BUDGET EXCEEDED'
PYEOF
echo "== done"
