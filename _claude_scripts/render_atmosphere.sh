#!/bin/bash
set -euo pipefail

# Atmospheric clip renderer for Deep Yellow Level 0.
# Uses the real in-game scene and Godot's AVI movie writer, then trims off
# loading/warm-up and encodes MP4/GIF. AVI is much faster than PNG sequences.
#
# Usage:
#   _claude_scripts/render_atmosphere.sh [CLIP_COUNT]
#
# Environment overrides:
#   GODOT=/path/to/godot
#   DY_CAPTURE_DURATION=60
#   DY_CAPTURE_WARMUP=30
#   DY_CAPTURE_FPS=30
#   DY_CAPTURE_RESOLUTION=640x480
#   DY_CAPTURE_GIF=1       # set 0 to skip GIF encoding
#   DY_CAPTURE_KEEP_RAW=0  # set 1 to keep raw AVI working files

GODOT="${GODOT:-/home/drew/projects/godot-tracy/godot-4.6/bin/godot.linuxbsd.editor.x86_64}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/build/atmosphere_clips"
CLIP_COUNT="${1:-5}"

DURATION="${DY_CAPTURE_DURATION:-60}"
WARMUP="${DY_CAPTURE_WARMUP:-30}"
FPS="${DY_CAPTURE_FPS:-30}"
RESOLUTION="${DY_CAPTURE_RESOLUTION:-640x480}"
MAKE_GIF="${DY_CAPTURE_GIF:-1}"
KEEP_RAW="${DY_CAPTURE_KEEP_RAW:-0}"

mkdir -p "$OUTPUT_DIR"

echo "============================================================"
echo "  Deep Yellow — Atmospheric Clip Renderer"
echo "  actual game scene → locked-off no-HUD viewport → MP4/GIF"
echo "  ${CLIP_COUNT} clips × ${DURATION}s @ target ${FPS}fps (${RESOLUTION})"
echo "  Warmup before encoded clip: ${WARMUP}s + load/settle marker"
echo "  Output: ${OUTPUT_DIR}"
echo "============================================================"
echo ""

for i in $(seq 1 "$CLIP_COUNT"); do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    CLIP_NAME="atmo_${TIMESTAMP}_${i}"
    WORK_DIR="${OUTPUT_DIR}/${CLIP_NAME}_work"
    MARKER_FILE="${WORK_DIR}/capture_start_frame.txt"
    RAW_MOVIE="${WORK_DIR}/${CLIP_NAME}_raw.avi"

    mkdir -p "$WORK_DIR"

    echo "[$i/${CLIP_COUNT}] Rendering ${CLIP_NAME}..."

    # IMPORTANT: pass engine/movie flags before scene path.
    # Use AVI instead of PNG sequence: Godot's PNG movie writer was the huge
    # bottleneck and made long batches fragile.
    DY_CAPTURE_MARKER_DIR="$WORK_DIR" \
    DY_CAPTURE_DURATION="$DURATION" \
    DY_CAPTURE_WARMUP="$WARMUP" \
    "$GODOT" --path "$PROJECT_DIR" \
        --windowed --resolution "$RESOLUTION" \
        --fixed-fps "$FPS" \
        --write-movie "$RAW_MOVIE" \
        "scenes/movie_capture.tscn"

    if [[ ! -f "$MARKER_FILE" ]]; then
        echo "ERROR: capture marker not written: $MARKER_FILE" >&2
        exit 1
    fi
    if [[ ! -f "$RAW_MOVIE" ]]; then
        echo "ERROR: raw movie not written: $RAW_MOVIE" >&2
        exit 1
    fi

    START_FRAME="$(tr -dc '0-9' < "$MARKER_FILE")"
    if [[ -z "$START_FRAME" ]]; then
        echo "ERROR: capture marker was empty: $MARKER_FILE" >&2
        exit 1
    fi

    # Detect actual movie FPS. Some Godot builds ignore --movie-fps; --fixed-fps
    # should work, but ffprobe keeps trimming correct either way.
    SOURCE_FPS="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nokey=1:noprint_wrappers=1 "$RAW_MOVIE" | head -1)"
    if [[ -z "$SOURCE_FPS" || "$SOURCE_FPS" == "0/0" ]]; then
        SOURCE_FPS="$FPS/1"
    fi

    START_SECONDS="$(python3 - "$START_FRAME" "$SOURCE_FPS" <<'PY'
import sys
from fractions import Fraction
frame = int(sys.argv[1])
fps = Fraction(sys.argv[2])
print(float(Fraction(frame, 1) / fps))
PY
)"

    echo "  → Trimming from frame ${START_FRAME} (${START_SECONDS}s at ${SOURCE_FPS})..."

    # ── Encode MP4 (high quality H.264) ─────────────────────────
    echo "  → Encoding MP4..."
    ffmpeg -y -hide_banner -loglevel error \
        -ss "$START_SECONDS" -t "$DURATION" -i "$RAW_MOVIE" \
        -c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium \
        -movflags +faststart \
        "${OUTPUT_DIR}/${CLIP_NAME}.mp4"

    # ── Encode GIF (optimized for social sharing) ───────────────
    if [[ "$MAKE_GIF" != "0" ]]; then
        echo "  → Encoding GIF..."
        ffmpeg -y -hide_banner -loglevel error \
            -ss "$START_SECONDS" -t "$DURATION" -i "$RAW_MOVIE" \
            -vf "fps=15,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
            -loop 0 \
            "${OUTPUT_DIR}/${CLIP_NAME}.gif"
        echo "  ✓ Done: ${CLIP_NAME}.mp4 + .gif"
    else
        echo "  ✓ Done: ${CLIP_NAME}.mp4"
    fi

    if [[ "$KEEP_RAW" != "1" ]]; then
        rm -rf "$WORK_DIR"
    else
        echo "  raw kept: $WORK_DIR"
    fi
    echo ""
done

echo "============================================================"
echo "  All clips rendered!"
echo "============================================================"
ls -lh "$OUTPUT_DIR"/*.mp4 2>/dev/null || true
