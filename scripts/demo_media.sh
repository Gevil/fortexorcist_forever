#!/usr/bin/env bash
# demo_media.sh -- regenerate every file under docs/demo/ from scratch (idempotent).
#
# Scenes run headless in wow-ui-sim (Osso). Each scene is scripts/demo/<body>.lua
# concatenated onto scripts/demo/prelude.lua and passed as ONE inline --exec-lua
# chunk (chunks > ~1.2 KB are silently ignored by the sim -- PLAN §10.6 -- so the
# build step asserts every assembled chunk fits). The prelude names a readout
# frame FXD whose FontString carries the crop box(es) (computed from the frames'
# GetRect + 12 px padding, owner rule) and the scene-content census; the same
# chunk runs once as `dump-tree` (that log is the scene proof + the box source)
# and once as `screenshot`. Loops backdate the scene's cast stamps per frame
# (@K@ substitution, one sim run per frame) exactly like the SplashLaw captures.
#
# Screenshots are 1600x1200 at ui-scale 1.0: UI units map 1:1 to PNG pixels, so
# the crop box needs no scale factor. Crops go through ffmpeg crop= + a 3x
# lanczos upscale; loops become GIFs (palettegen/paletteuse, 12 fps) + MP4s.
#
# Usage: scripts/demo_media.sh [name ...]     (default: everything)
# Budget: every file <= 3 MB, total <= 12 MB -- the script fails if exceeded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM="${WOW_UI_SIM:-$(dirname "$ROOT")/wow-ui-sim/run.sh}"
ADDONS="$ROOT/addon"
SDIR="$ROOT/scripts/demo"
OUT="$ROOT/docs/demo"
TMP="${DEMO_TMP:-/tmp/fx_demo}"
W=1600; H=1200
rm -rf "$TMP"; mkdir -p "$TMP" "$OUT"
CH="$TMP/chunk.lua"

[ -x "$SIM" ] || { echo "wow-ui-sim not found at $SIM" >&2; exit 1; }

# mkchunk <body.lua> [K]  -> $CH, asserting the 1.2 KB sim cap
mkchunk() {
  python3 - "$SDIR/prelude.lua" "$1" "${2-}" "$CH" <<'PYEOF'
import sys
pre=open(sys.argv[1]).read(); body=open(sys.argv[2]).read()
if sys.argv[3]: body=body.replace('@K@',sys.argv[3])
c=pre+body
assert len(c)<=1200, 'chunk %d B exceeds 1200' % len(c)
open(sys.argv[4],'w').write(c)
PYEOF
  [ -n "${2-}" ] || echo "  chunk $(basename "$1") = $(wc -c < "$CH") B"
}

# runsim <class> <chunkfile> <sim-args...>
runsim() {
  local class=$1 chunk=$2; shift 2
  ( cd /tmp && "$SIM" wow-sim --allow-ui-version-mismatch \
      --addons-path "$ADDONS" --class "$class" --delay 3500 \
      --exec-lua "$(cat "$chunk")" "$@" )
}

# dtbox <dt.log...>  -> "x y w h" union of the FXD boxes across the logs
dtbox() {
  python3 - "$@" <<'PYEOF'
import sys,re
boxes=[]
for path in sys.argv[1:]:
    txt=open(path,encoding='utf8',errors='replace').read()
    m=re.search(r'text="FXD ([^"]*)"',txt)
    assert m,'no FXD readout in '+path
    boxes+=[tuple(map(int,b)) for b in re.findall(r'(\d+),(\d+),(\d+),(\d+)',m.group(1))]
assert boxes,'no boxes'
x0=min(b[0] for b in boxes); y0=min(b[1] for b in boxes)
x1=max(b[0]+b[2] for b in boxes); y1=max(b[1]+b[3] for b in boxes)
w=x1-x0; h=y1-y0
if w%2: w-=1
if h%2: h-=1
print(x0,y0,w,h)
PYEOF
}

# warlock dt log boxes come off the four named anchors' visible dump rects
warlockbox() {
  python3 - "$1" <<'PYEOF'
import sys,re
txt=open(sys.argv[1],encoding='utf8',errors='replace').read()
pat=re.compile(r'^\s*(ForteXorcistWarlock(?:Shards|Soulstone|Healthstone|Summon)Anchor) \[\w+\] \((\d+)x(\d+)\) visible [^\n]*x=(-?\d+), y=(-?\d+)',re.M)
rs=[(int(m[3]),int(m[4]),int(m[1]),int(m[2])) for m in pat.findall(txt)]
assert len(rs)==4,'warlock anchors visible: %d' % len(rs)
pad=12
x0=min(r[0] for r in rs)-pad; y0=min(r[1] for r in rs)-pad
x1=max(r[0]+r[2] for r in rs)+pad; y1=max(r[1]+r[3] for r in rs)+pad
w=x1-x0; h=y1-y0
if w%2: w-=1
if h%2: h-=1
print(x0,y0,w,h)
PYEOF
}

# crop3 <in.png> <x> <y> <w> <h> <out.png>   (crop + 3x lanczos)
crop3() {
  ffmpeg -hide_banner -loglevel error -y -i "$1" \
    -vf "crop=$4:$5:$2:$3,scale=iw*3:ih*3:flags=lanczos" "$6"
}

# report <file> [frames]
report() {
  local f=$1 fr=${2--} sz w h nf dim
  sz=$(wc -c < "$f")
  read -r w h nfj < <(ffprobe -v error -print_format json -show_streams "$f" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["streams"] if x.get("codec_type")=="video"][0]
print(s["width"],s["height"],s.get("nb_read_frames","-"))')
  nf=$fr
  if [ "$fr" = - ]; then
    nf=$(ffprobe -v error -count_frames -print_format json -show_streams "$f" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["streams"] if x.get("codec_type")=="video"][0]
print(s.get("nb_read_frames","?"))')
  fi
  printf 'FILE %s %sx%s %sB frames=%s\n' "$f" "$w" "$h" "$sz" "$nf"
}

# scene <outname> <class> <body.lua> [K]
scene() {
  local name=$1 class=$2 body=$3 k=${4-}
  echo "== scene $name ($class, $body${k:+, K=$k})"
  mkchunk "$SDIR/$body" "$k"
  runsim "$class" "$CH" dump-tree > "$TMP/$name.dt.log" 2>&1
  local boxf="$TMP/$name.box"
  if [ "$name" = warlock-plates ]; then warlockbox "$TMP/$name.dt.log" > "$boxf"
  else dtbox "$TMP/$name.dt.log" > "$boxf"; fi
  read -r x y w h < "$boxf"
  if [ "$name" = splash ]; then
    x=$((x-32)); [ "$x" -lt 0 ] && x=0; y=$((y-32)); [ "$y" -lt 0 ] && y=0
    w=$((w+64)); h=$((h+64))
    [ $((x+w)) -gt "$W" ] && w=$((W-x)); [ $((y+h)) -gt "$H" ] && h=$((H-y))
  fi
  echo "  crop x=$x y=$y w=$w h=$h (px, from frame GetRect +12 pad)"
  grep -o 'text="FXD [^"]*"' "$TMP/$name.dt.log" | sed 's/^/  proof: /'
  runsim "$class" "$CH" screenshot --png -o "$TMP/$name.raw.png" --width "$W" --height "$H"
  crop3 "$TMP/$name.raw.png" "$x" "$y" "$w" "$h" "$OUT/$name.png"
  report "$OUT/$name.png" 1
}

# loop <outbase> <class> <body.lua> <frames> [boxframe]
loop() {
  local name=$1 class=$2 body=$3 n=$4 boxk=${5:-0} k
  echo "== loop $name ($class, $body, $n frames)"
  mkdir -p "$TMP/$name"
  for ((k=0;k<n;k++)); do
    mkchunk "$SDIR/$body" "$k"
    if [ "$k" = 0 ] || [ "$k" = "$boxk" ]; then
      runsim "$class" "$CH" dump-tree > "$TMP/$name.f$k.dt.log" 2>&1
      grep -o 'text="FXD [^"]*"' "$TMP/$name.f$k.dt.log" | sed "s/^/  proof f$k: /"
    fi
    runsim "$class" "$CH" screenshot --png -o "$(printf "$TMP/$name/raw_%03d.png" "$k")" --width "$W" --height "$H"
  done
  echo "  $n captures done"
  local boxf="$TMP/$name.box"
  if [ "$boxk" = 0 ]; then dtbox "$TMP/$name.f0.dt.log" > "$boxf"
  else dtbox "$TMP/$name.f0.dt.log" "$TMP/$name.f$boxk.dt.log" > "$boxf"; fi
  read -r x y w h < "$boxf"
  if [ "$body" = splashpop.lua ]; then
    x=$((x-32)); [ "$x" -lt 0 ] && x=0; y=$((y-32)); [ "$y" -lt 0 ] && y=0
    w=$((w+64)); h=$((h+64))
    [ $((x+w)) -gt "$W" ] && w=$((W-x)); [ $((y+h)) -gt "$H" ] && h=$((H-y))
  fi
  echo "  crop x=$x y=$y w=$w h=$h (held for all frames)"
  for ((k=0;k<n;k++)); do
    ffmpeg -hide_banner -loglevel error -y -i "$(printf "$TMP/$name/raw_%03d.png" "$k")" \
      -vf "crop=$w:$h:$x:$y" "$(printf "$TMP/$name/fr_%03d.png" "$k")"
  done
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$TMP/$name/fr_%03d.png" \
    -vf "scale=iw*3:ih*3:flags=lanczos,palettegen=stats_mode=full" "$TMP/$name.pal.png"
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$TMP/$name/fr_%03d.png" -i "$TMP/$name.pal.png" \
    -lavfi "[0:v]scale=iw*3:ih*3:flags=lanczos[s];[s][1:v] paletteuse=dither=sierra2_4a [v]" -map "[v]" "$OUT/$name.gif"
  ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$TMP/$name/fr_%03d.png" \
    -vf "scale=trunc(iw*3/2)*2:trunc(ih*3/2)*2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset veryslow -crf 20 -movflags +faststart "$OUT/$name.mp4"
  report "$OUT/$name.gif" "$n"
  report "$OUT/$name.mp4" "$n"
}

only="${*:-}"
want() { [ -z "$only" ] && return 0; local n; for n in $only; do [ "$n" = "$1" ] && return 0; done; return 1; }

if want warlock-plates; then scene warlock-plates Warlock warlock.lua;       fi
if want splash;         then scene splash         Hunter  splashpop.lua 6;   fi
if want profiles;       then scene profiles       Hunter  profiles.lua;      fi
if want splash-pop;     then loop  splash-pop     Hunter  splashpop.lua 13 6; fi

echo "== budget check"
python3 - "$OUT" <<'PYEOF'
import sys,os,glob
tot=0; fail=0
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*'))):
    sz=os.path.getsize(f); tot+=sz
    lim=3*1024*1024
    ok='ok ' if sz<=lim else 'OVER'
    if sz>lim: fail+=1
    print('  %s %-22s %8d B' % (ok,os.path.basename(f),sz))
print('  total %d B (cap 12582912)' % tot)
assert tot<=12*1024*1024 and not fail,'BUDGET EXCEEDED'
PYEOF
echo "== done"
