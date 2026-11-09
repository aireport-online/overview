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
shoot() {
    local name="$1"
    shift
    open -n -a "$APP" "$@"
    sleep 8
    local pid
    if ! pid="$(pgrep -n -x Overview)"; then
        echo "Overview is not running ($name)" >&2
        exit 1
    fi
    local window
    if window="$(swift Scripts/window-id.swift "$pid")"; then
        screencapture -x -o -l "$window" "$OUT/$name.png"
    else
        echo "Overview shows no window ($name); saving the whole screen" >&2
        screencapture -x "$OUT/$name-failed.png"
        kill "$pid"
        exit 1
    fi
    kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
}

shoot welcome
shoot sunburst --args -chartStyle sunburst -scan "$SAMPLE"
shoot treemap --args -chartStyle treemap -scan "$SAMPLE"
shoot sunburst-dark --args -AppleInterfaceStyle Dark -chartStyle sunburst -scan "$SAMPLE"
shoot treemap-dark --args -AppleInterfaceStyle Dark -chartStyle treemap -scan "$SAMPLE"
# The way Finder opens a folder with the app: by Dock icon or "Open With".
shoot opened-folder "$SAMPLE"

rm -rf "$SAMPLE"
ls -l "$OUT"
