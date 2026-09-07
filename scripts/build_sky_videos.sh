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
# Usage:  scripts/build_sky_videos.sh ~/Downloads/big3.me [zone...]
#
# Needs ffmpeg built with libx265: brew install ffmpeg
#
# Encoding all eight takes a few minutes — libx265 on `slow` is not fast. That
# is the trade this script makes deliberately; see the encoder note below.

set -euo pipefail

SRC=${1:?"pass the folder holding the stock sources"}
shift
DST=$(cd "$(dirname "$0")/.." && pwd)/frontend/ios/App/App/Native/Design/Sky

# Naming zones limits the rebuild to those. Re-grading one sky is the common
# case, and re-encoding the other six would rewrite six committed binaries that
# nobody touched — a diff that hides the one clip that actually changed.
ZONES="$*"
wanted() {
  if [ -z "$ZONES" ]; then return 0; fi
  case " $ZONES " in (*" $1 "*) return 0 ;; (*) return 1 ;; esac
}

# Screen clips match the tallest phone we target; card clips are a wide band at
# about an eighth of the pixels, because a profile row is a 358x108pt sliver.
SCREEN_W=1170 SCREEN_H=2532
CARD_W=1080   CARD_H=326

# --- Grades ---------------------------------------------------------------
#
# Clips are graded to their TII zone's palette (see WeatherSky.swift) rather
# than to whatever the stock footage happened to be: the sky is the reading, so
# a blue clip in the hot zone would say the wrong thing.
#
# quiet and hot are duotones — luminance mapped into the zone's ramp. Rotating
# hue instead moves neutral tones too, which is what turned the sun clip's
# white clouds olive on the first attempt. active came in already coloured with
# no neutrals to protect, so a hue rotation is safe there.
#
# extreme is the exception: it keeps the footage's own colour. Its storm reads
# as extreme on movement and contrast rather than on hue, and pushing the blue
# into the zone's red turned a night sky into a furnace. So the curve is a
# levels move, not a duotone — one channel-neutral ramp that stretches the
# source's 0..0.6 into the full range. Without it nothing rises past the middle
# of the scale and the storm reads as fog; with it the lit cloud separates from
# the dark mass behind it and the top of the frame stays dark under the text.
# The saturation cut goes with the stretch rather than against the footage:
# pulling the channels apart pulls the colour apart too, and 1.0 came back a
# vivid electric blue the source never had.

G_QUIET="format=gray,curves=r='0/0.03 0.5/0.20 1/0.72':g='0/0.09 0.5/0.36 1/0.85':b='0/0.16 0.5/0.52 1/1.0',eq=contrast=1.02:brightness=-0.10"
G_ACTIVE="hue=h=-25:s=0.75,colorbalance=gs=0.10:bs=0.08,eq=brightness=-0.10:contrast=1.05"
G_HOT="format=gray,curves=r='0/0.13 0.5/0.62 1/1':g='0/0.06 0.5/0.31 1/0.86':b='0/0.03 0.5/0.11 1/0.62',eq=contrast=1.08:brightness=-0.08"
G_EXTREME="curves=all='0/0.01 0.10/0.09 0.25/0.31 0.40/0.61 0.55/0.91 1/1',eq=contrast=1.05:saturation=0.80"

# --- Encoder --------------------------------------------------------------
#
# Stock loops do not loop: their first and last frames are unrelated, which
# reads as a jump every few seconds. Crossfading the tail back over the head
# hides the seam, at the cost of FADE seconds of running time.

FADE=1.0

# libx265 rather than hevc_videotoolbox. Measured on a storm clip against a
# lossless reference: at the same 1.3MB the hardware encoder scored VMAF 36
# and libx265 scored 69. The video chip is built for speed, not for density,
# and nothing here is encoded at runtime, so the slower encoder is free.
#
# CRF, not a target bitrate: the clips differ wildly in how much motion they
# carry (drifting cloud against driving rain), and a fixed bitrate either
# starves one or wastes bits on the other.
CRF_SCREEN=32
CRF_CARD=32

build() {
  local in=$1 out=$2 ss=$3 dur=$4 crop=$5 extra=$6 grade=$7 w=$8 h=$9 crf=${10}
  local mid
  mid=$(echo "$dur - $FADE" | bc)

  ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$in" -filter_complex \
"[0:v]${crop},scale=${w}:${h}:flags=lanczos,${extra}${grade},fps=30,split=3[h][m][t];\
[h]trim=0:${FADE},setpts=PTS-STARTPTS[head];\
[m]trim=${FADE}:${mid},setpts=PTS-STARTPTS[mid];\
[t]trim=${mid}:${dur},setpts=PTS-STARTPTS[tail];\
[tail][head]blend=all_expr='A*(1-T/${FADE})+B*(T/${FADE})'[bl];\
[bl][mid]concat=n=2:v=1:a=0[v]" \
    -map "[v]" -c:v libx265 -tag:v hvc1 -crf "$crf" -preset slow \
    -x265-params log-level=error -pix_fmt yuv420p -an "$out"

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
if wanted quiet; then
build "$SRC/1481304_Cloud_Clouds_1280x720.mov" "$DST/sky_quiet.mp4" \
  10 7.0 "crop=333:720:35:0" "gblur=sigma=0.6," "$G_QUIET" $SCREEN_W $SCREEN_H $CRF_SCREEN
build "$SRC/Archived/1481304_Cloud_Clouds_1280x720.mp4" "$DST/card_quiet.mp4" \
  10 7.0 "crop=1280:387:0:180" "" "$G_QUIET" $CARD_W $CARD_H $CRF_CARD
fi

# active — rain on water.
if wanted active; then
build "$SRC/0_Rain_Raindrops_720x1280.mp4" "$DST/sky_active.mp4" \
  0 5.875 "crop=591:1280:64:0" "" "$G_ACTIVE" $SCREEN_W $SCREEN_H $CRF_SCREEN
build "$SRC/0_Rain_Raindrops_720x1280.mp4" "$DST/card_active.mp4" \
  0 5.875 "crop=720:218:0:620" "" "$G_ACTIVE" $CARD_W $CARD_H $CRF_CARD
fi

# hot — sun through cloud.
if wanted hot; then
build "$SRC/0_Sun_Sky_720x1280.mp4" "$DST/sky_hot.mp4" \
  0 7.0 "crop=591:1280:64:0" "" "$G_HOT" $SCREEN_W $SCREEN_H $CRF_SCREEN
build "$SRC/0_Sun_Sky_720x1280.mp4" "$DST/card_hot.mp4" \
  0 7.0 "crop=720:218:0:480" "" "$G_HOT" $CARD_W $CARD_H $CRF_CARD
fi

# extreme — a storm lighting itself up from inside. The only landscape source
# here, and 4K, so both crops are windows into one frame rather than the same
# frame cut twice: the screen crop takes a right-hand column where the lit edge
# of the cloud sits two thirds down and the top stays dark under the hero text,
# the card crop a band across the middle wide enough to hold that lit edge and
# the dark mass beside it. The column is 780px for the framing and goes up 1.5x
# — no portrait crop of a 2160-tall frame reaches 2532 without one, and the
# extra pixels would have bought a worse composition.
#
# 1.5s in, and 7.0 long, because of where the strikes fall. The source flashes
# at 0.6, 1.2, 2.6, 3.0, 4.9, 5.4, 8.8 and 9.2 seconds, and a window is only
# usable if its first and last second are dark: those two seconds are what the
# crossfade blends, so a strike inside either one plays back at half strength
# on top of calm sky, and a strike in the last frames before the loop point
# reads as a flash cut off mid-air. 1.5-8.5 keeps four strikes in the clear
# middle and leaves both ends quiet. The two brightest, at 0.6 and 9.2, sit too
# close to the ends of the footage for any window to hold them cleanly.
if wanted extreme; then
build "$SRC/Archived/1967950_Lapse_Moody_3840x2160.mp4" "$DST/sky_extreme.mp4" \
  1.5 7.0 "crop=780:1688:2960:472" "" "$G_EXTREME" $SCREEN_W $SCREEN_H $CRF_SCREEN
build "$SRC/Archived/1967950_Lapse_Moody_3840x2160.mp4" "$DST/card_extreme.mp4" \
  1.5 7.0 "crop=2600:785:1240:1180" "" "$G_EXTREME" $CARD_W $CARD_H $CRF_CARD
fi

# --- Check ----------------------------------------------------------------
#
# The screens draw white text straight onto the footage, so the top of the
# frame has to stay dark. 45% is where white starts to struggle; every shipped
# clip sits between 13% and 31%. Re-grade anything this flags.

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
