#!/bin/bash
# Starts the built app on a sample folder and saves a picture of its window in
# each view. CI runs this to check that the app launches and draws; the
# pictures are also the ones in the README.
#
#   Scripts/build-app.sh && Scripts/screenshots.sh [output folder]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/screenshots}"
BINARY="$PWD/build/Overview.app/Contents/MacOS/Overview"
SAMPLE="$(mktemp -d)/Home"
mkdir -p "$OUT"
Scripts/make-sample-folder.sh "$SAMPLE"

# shoot <name> [arguments for the app...]
shoot() {
    local name="$1"
    shift
    "$BINARY" "$@" &
    local pid=$!
    sleep 8
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Overview quit unexpectedly ($name)" >&2
        exit 1
    fi
    local window
    if window="$(swift Scripts/window-id.swift "$pid")"; then
        screencapture -x -o -l "$window" "$OUT/$name.png"
    else
        echo "No window found for $name; capturing the whole screen" >&2
        screencapture -x "$OUT/$name.png"
    fi
    kill "$pid"
    wait "$pid" 2>/dev/null || true
}

shoot welcome
shoot sunburst -chartStyle sunburst "$SAMPLE"
shoot treemap -chartStyle treemap "$SAMPLE"
shoot sunburst-dark -AppleInterfaceStyle Dark -chartStyle sunburst "$SAMPLE"
shoot treemap-dark -AppleInterfaceStyle Dark -chartStyle treemap "$SAMPLE"

rm -rf "$SAMPLE"
ls -l "$OUT"
