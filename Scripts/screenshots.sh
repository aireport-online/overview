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
#   POINTER  what to do with the pointer first, as "click 357 296; move 395 368"
#            in points from the top left of the window. The positions are for
#            the window size in POINTER_WINDOW; with another size the picture
#            is skipped.
POINTER_WINDOW="1024 681"

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

    local skip=""
    if [[ -n "${POINTER:-}" ]]; then
        if [[ "$width $height" == "$POINTER_WINDOW" ]]; then
            local step action px py
            while IFS= read -r -d ';' step; do
                read -r action px py <<<"$step"
                swift Scripts/pointer.swift "$action" "$((x + px))" "$((y + py))"
                sleep 1
            done <<<"$POINTER;"
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

shoot welcome
DELAY=3 shoot scanning --args -scan /
shoot sunburst --args -appearance light -chartStyle sunburst -scan "$SAMPLE"
shoot treemap --args -appearance light -chartStyle treemap -scan "$SAMPLE"
shoot sunburst-dark --args -appearance dark -chartStyle sunburst -scan "$SAMPLE"
shoot treemap-dark --args -appearance dark -chartStyle treemap -scan "$SAMPLE"
# The way Finder opens a folder with the app: by Dock icon or "Open With".
shoot opened-folder "$SAMPLE"
# Click the Movies arc to open that folder, then point at its largest file.
POINTER="click 357 296; move 395 368" shoot zoomed --args -appearance light -chartStyle sunburst -scan "$SAMPLE"
# Click the Movies tile in the treemap, then point at a file.
POINTER="click 120 200; move 120 250" shoot zoomed-treemap --args -appearance dark -chartStyle treemap -scan "$SAMPLE"

# TEMPORARY: one complete scan of the startup disk, to check totals and timing.
DELAY=240 shoot full-disk --args -appearance light -chartStyle sunburst -scan /

rm -rf "$SAMPLE"
ls -l "$OUT"
