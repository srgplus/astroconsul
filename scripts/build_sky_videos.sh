#!/usr/bin/env bash
#
# Rebuilds the cosmic-weather sky clips from their stock sources.
#
# The finished clips are committed (they have to ship inside the app bundle:
# they are the background of the home screen, needed instantly and offline).
# The sources are not — they are large, and this script is the recipe that
# turns one into the other, so a re-grade does not mean guessing at the numbers
# again.
#
# Usage:  scripts/build_sky_videos.sh ~/Downloads/big3.me
#
# Needs ffmpeg with hevc_videotoolbox (macOS): brew install ffmpeg
#
# Re-running produces equivalent clips, not byte-identical ones —
# hevc_videotoolbox is a hardware encoder and does not repeat itself exactly.
# So a plain re-run leaves eight modified files that differ in nothing that
# matters. Commit the result only when the recipe actually changed; otherwise
# `git restore` them.

set -euo pipefail

SRC=${1:?"pass the folder holding the stock sources"}
DST=$(cd "$(dirname "$0")/.." && pwd)/frontend/ios/App/App/Native/Design/Sky

# Screen clips match the tallest phone we target; card clips are a wide band at
# about an eighth of the pixels, because a profile row is a 358x108pt sliver.
SCREEN_W=1170 SCREEN_H=2532
CARD_W=1080   CARD_H=326

# --- Grades ---------------------------------------------------------------
#
# Each clip is graded to its TII zone's palette (see WeatherSky.swift), not to
# whatever the stock footage happened to be: the sky is the reading, so a blue
# clip in the hot zone would say the wrong thing.
#
# quiet and hot are duotones — luminance mapped into the zone's ramp. Rotating
# hue instead moves neutral tones too, which is what turned the sun clip's
# white clouds olive on the first attempt. active and extreme came in already
# coloured with no neutrals to protect, so a hue rotation is safe there.

G_QUIET="format=gray,curves=r='0/0.03 0.5/0.20 1/0.72':g='0/0.09 0.5/0.36 1/0.85':b='0/0.16 0.5/0.52 1/1.0',eq=contrast=1.02:brightness=-0.10"
G_ACTIVE="hue=h=-25:s=0.75,colorbalance=gs=0.10:bs=0.08,eq=brightness=-0.10:contrast=1.05"
G_HOT="format=gray,curves=r='0/0.13 0.5/0.62 1/1':g='0/0.06 0.5/0.31 1/0.86':b='0/0.03 0.5/0.11 1/0.62',eq=contrast=1.08:brightness=-0.08"
G_EXTREME="hue=h=75:s=0.85,colorbalance=rm=0.12:bm=-0.10:rs=0.06:bs=-0.05,eq=brightness=-0.10:contrast=1.05:saturation=0.92"

# --- Encoder --------------------------------------------------------------
#
# Stock loops do not loop: their first and last frames are unrelated, which
# reads as a jump every few seconds. Crossfading the tail back over the head
# hides the seam, at the cost of FADE seconds of running time.

FADE=1.0

build() {
  local in=$1 out=$2 ss=$3 dur=$4 crop=$5 extra=$6 grade=$7 w=$8 h=$9 bitrate=${10}
  local mid
  mid=$(echo "$dur - $FADE" | bc)

  ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$in" -filter_complex \
"[0:v]${crop},scale=${w}:${h}:flags=lanczos,${extra}${grade},fps=30,split=3[h][m][t];\
[h]trim=0:${FADE},setpts=PTS-STARTPTS[head];\
[m]trim=${FADE}:${mid},setpts=PTS-STARTPTS[mid];\
[t]trim=${mid}:${dur},setpts=PTS-STARTPTS[tail];\
[tail][head]blend=all_expr='A*(1-T/${FADE})+B*(T/${FADE})'[bl];\
[bl][mid]concat=n=2:v=1:a=0[v]" \
    -map "[v]" -c:v hevc_videotoolbox -tag:v hvc1 -b:v "$bitrate" -pix_fmt yuv420p -an "$out"

  # du reports allocated blocks, which rounds every one of these to the same
  # number and hides a clip that ballooned. Count the bytes.
  printf '  %-18s %5d KB\n' "$(basename "$out")" "$(( $(stat -f%z "$out") / 1024 ))"
}

mkdir -p "$DST"
echo "Building into $DST"

# quiet — cloud bank. The screen crop is a 3.5x upscale off a 404px-wide
# source, which only works because the grade leaves contrast alone: pushing it
# is what turns soft cloud into mush, not the missing pixels. gblur hides the
# rest. The card crop comes off the untouched landscape original instead, so it
# is a downscale with nothing to hide.
build "$SRC/1481304_Cloud_Clouds_1280x720.mov" "$DST/sky_quiet.mp4" \
  10 7.0 "crop=333:720:35:0" "gblur=sigma=0.6," "$G_QUIET" $SCREEN_W $SCREEN_H 1600k
build "$SRC/Archived/1481304_Cloud_Clouds_1280x720.mp4" "$DST/card_quiet.mp4" \
  10 7.0 "crop=1280:387:0:180" "" "$G_QUIET" $CARD_W $CARD_H 500k

# active — rain on water.
build "$SRC/0_Rain_Raindrops_720x1280.mp4" "$DST/sky_active.mp4" \
  0 5.875 "crop=591:1280:64:0" "" "$G_ACTIVE" $SCREEN_W $SCREEN_H 1600k
build "$SRC/0_Rain_Raindrops_720x1280.mp4" "$DST/card_active.mp4" \
  0 5.875 "crop=720:218:0:620" "" "$G_ACTIVE" $CARD_W $CARD_H 500k

# hot — sun through cloud.
build "$SRC/0_Sun_Sky_720x1280.mp4" "$DST/sky_hot.mp4" \
  0 7.0 "crop=591:1280:64:0" "" "$G_HOT" $SCREEN_W $SCREEN_H 1600k
build "$SRC/0_Sun_Sky_720x1280.mp4" "$DST/card_hot.mp4" \
  0 7.0 "crop=720:218:0:480" "" "$G_HOT" $CARD_W $CARD_H 500k

# extreme — lightning.
build "$SRC/0_Vertical_Video_Lightning_Bolt_720x1280.mp4" "$DST/sky_extreme.mp4" \
  0 5.208 "crop=591:1280:64:0" "" "$G_EXTREME" $SCREEN_W $SCREEN_H 1600k
build "$SRC/0_Vertical_Video_Lightning_Bolt_720x1280.mp4" "$DST/card_extreme.mp4" \
  0 5.208 "crop=720:218:0:380" "" "$G_EXTREME" $CARD_W $CARD_H 500k

# --- Check ----------------------------------------------------------------
#
# The screens draw white text straight onto the footage, so the top of the
# frame has to stay dark. 45% is where white starts to struggle; every shipped
# clip sits between 17% and 31%. Re-grade anything this flags.

echo
echo "Brightness where the hero text sits (ceiling 45%):"
for f in "$DST"/sky_*.mp4; do
  printf '  %-18s ' "$(basename "$f")"
  ffmpeg -v error -i "$f" \
    -vf "crop=iw:ih*0.4:0:0,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
    -f null /dev/null 2>/dev/null \
  | grep YAVG \
  | awk -F= '{s+=$2; n++} END {printf "%.0f%%%s\n", s/n/255*100, (s/n/255*100 > 45 ? "  TOO BRIGHT" : "")}'
done
