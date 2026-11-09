#!/bin/bash
# Starts the built app on a sample folder and saves a picture of its window in
# each view. CI runs this to check that the app launches and draws; the
# pictures are also the ones in the README.
#
#   Scripts/build-app.sh && Scripts/screenshots.sh [output folder]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/screenshots}"
APP="$PWD/build/Overview.app"
SAMPLE="$(mktemp -d)/Home"
mkdir -p "$OUT"
Scripts/make-sample-folder.sh "$SAMPLE"

# shoot <name> [arguments for `open`...]
#
# Optional variables:
#   DELAY    seconds between launch and picture (default 8)
#   POINTER  steps for Scripts/pointer.swift to run first, separated by ";",
#            such as "move 529 310 0.5; click; wait 1.5". The positions are
#            for a window of POINTER_WINDOW points; with another size the
#            picture is skipped.
POINTER_WINDOW="1280 800"

shoot() {
    local name="$1"
    shift
    open -n -a "$APP" "$@"
    sleep "${DELAY:-8}"
    local pid
    if ! pid="$(pgrep -n -x Overview)"; then
        echo "Overview is not running ($name)" >&2
        exit 1
    fi
    local window x y width height
    if ! read -r window x y width height <<<"$(swift Scripts/window-id.swift "$pid")" || [[ -z "$window" ]]; then
        echo "Overview shows no window ($name); saving the whole screen" >&2
        screencapture -x "$OUT/$name-failed.png"
        kill "$pid"
        exit 1
    fi

    echo "$name: window at $x,$y size $width x $height"
    local skip=""
    if [[ -n "${POINTER:-}" ]]; then
        if [[ "$width $height" == "$POINTER_WINDOW" ]]; then
            printf '%s\n' "$POINTER" | tr ';' '\n' | swift Scripts/pointer.swift "$x" "$y"
        else
            echo "Skipping $name: the window is $width x $height, not $POINTER_WINDOW" >&2
            skip=1
        fi
    fi
    if [[ -z "$skip" ]]; then
        screencapture -x -o -l "$window" "$OUT/$name.png"
    fi
    kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
}

# The build machine starts with a small screen; ask for a larger one.
if [[ -n "${CI:-}" ]]; then
    swift Scripts/display-mode.swift 1920 1080 || true
    sleep 2
fi
# A fixed window size, and animations on even where the system reduces motion.
OPTIONS="-windowSize 1280x800 -animations on"

# shellcheck disable=SC2086
{
shoot welcome --args $OPTIONS
DELAY=3 shoot scanning --args $OPTIONS -scan /
shoot sunburst --args $OPTIONS -chartStyle sunburst -scan "$SAMPLE"
shoot treemap --args $OPTIONS -chartStyle treemap -scan "$SAMPLE"
# The way Finder opens a folder with the app: by Dock icon or "Open With".
shoot opened-folder "$SAMPLE"
# Click the Movies arc to open that folder, then point at its largest file.
POINTER="move 529 310 0.5; click; wait 1.5; move 574 368 0.5; wait 0.8" \
    shoot sunburst-zoomed --args $OPTIONS -chartStyle sunburst -scan "$SAMPLE"
# Click a tile in Movies to open that folder in the treemap, then point at a file.
POINTER="move 133 180 0.5; click; wait 1.5; move 300 300 0.5; wait 0.8" \
    shoot treemap-zoomed --args $OPTIONS -chartStyle treemap -scan "$SAMPLE"
# The Dutch translation, with the list of largest files.
shoot welcome-nl --args $OPTIONS -AppleLanguages "(nl)"
shoot largest-files-nl --args $OPTIONS -AppleLanguages "(nl)" -chartStyle sunburst -sidebarTab largest -scan "$SAMPLE"
}

rm -rf "$SAMPLE"
ls -l "$OUT"
