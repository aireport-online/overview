#!/bin/bash
# Records a walkthrough of the app: starts a screen recording, launches the
# app in Dutch on a sample folder and drives the pointer through its main
# features. The result is the raw material for the tutorial video:
#
#   <output>/walkthrough.mov   the screen recording
#   <output>/marks.txt         "<label> <unix time>" for every step worth a sound
#   <output>/window.txt        where the window was: "x y width height"
#
#   Scripts/build-app.sh && Scripts/walkthrough.sh [output folder]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/walkthrough}"
APP="$PWD/build/Overview.app"
SAMPLE="$(mktemp -d)/Home"
mkdir -p "$OUT"
Scripts/make-sample-folder.sh "$SAMPLE"

if [[ -n "${CI:-}" ]]; then
    swift Scripts/display-mode.swift 1920 1080 || true
    sleep 2
fi

# Start from a clean slate, with the sample folder as the one recent folder.
# Note: this resets the preferences of the app.
pkill -x Overview || true
defaults delete online.aireport.overview 2>/dev/null || true
defaults write online.aireport.overview recentFolders -array "$SAMPLE"

open -n -a "$APP" --args -windowSize 1280x800 -animations on -AppleLanguages "(nl)"
sleep 4
PID="$(pgrep -n -x Overview)"
read -r _ X Y WIDTH HEIGHT <<<"$(swift Scripts/window-id.swift "$PID")"
echo "$X $Y $WIDTH $HEIGHT" > "$OUT/window.txt"
echo "window at $X,$Y size $WIDTH x $HEIGHT"

# Compile the pointer driver first, so the steps start on time.
swiftc -O -o "$OUT/pointer" Scripts/pointer.swift

# Long enough for all the steps below (about 76 seconds) and a little more.
screencapture -x -C -k -v -V 84 "$OUT/walkthrough.mov" &
RECORDER=$!
sleep 2
python3 -c 'import time; print("recording", "%.3f" % time.time())' > "$OUT/marks.txt"

"$OUT/pointer" "$X" "$Y" >> "$OUT/marks.txt" <<'STEPS'
# 1. The start screen: the disc leans towards the pointer; go to the recent folder.
mark intro
move 420 330 1.0
wait 0.8
move 820 250 1.6
wait 0.6
move 640 300 1.0
wait 1.6
move 893 572 1.4
wait 1.6
# 2. Scan.
mark scan
click
wait 5.0
# 3. The sunburst: a slow sweep around it.
mark results
move 700 200 1.2
wait 1.5
move 760 520 1.6
wait 1.5
move 300 560 1.6
wait 1.5
move 250 300 1.4
wait 1.2
# 4. Point at arcs, then at rows of the list.
mark hover
move 529 310 1.0
wait 1.3
move 579 428 0.8
wait 1.2
move 1050 248 1.2
wait 1.0
move 1050 292 0.5
wait 1.0
move 1050 336 0.5
wait 1.0
# 5. Into Movies, into the wedding project, and back up twice.
mark zoom
move 529 310 1.0
wait 0.4
mark zoom-in
click
wait 1.8
move 423 519 0.8
wait 0.4
mark zoom-in
click
wait 1.8
move 463 408 0.8
wait 0.3
mark zoom-out
click
wait 1.5
mark zoom-out
click
wait 1.6
# 6. The treemap.
mark treemap
move 1141 46 1.0
wait 0.3
mark select
click
wait 2.2
move 133 180 1.0
wait 0.8
mark zoom-in
click
wait 2.0
move 67 46 0.9
wait 0.3
mark zoom-out
click
wait 1.8
# 7. Largest files, and the menu of one of them.
mark largest
move 1173 102 1.0
wait 0.3
mark select
click
wait 1.6
move 1067 206 0.9
wait 0.8
rightclick
wait 2.2
key 125
wait 0.3
key 125
wait 0.3
key 125
wait 0.8
mark menu
key 36
wait 3.0
mark dialog
key 53
wait 1.5
# 8. Back to the sunburst.
mark outro
move 1049 46 1.0
wait 0.3
mark select
click
wait 5.0
mark end
STEPS

# The recording stops by itself when its time is up.
for _ in $(seq 1 40); do
    kill -0 "$RECORDER" 2>/dev/null || break
    sleep 1
done
kill "$RECORDER" 2>/dev/null || true
pkill -x Overview || true
rm -rf "$SAMPLE" "$OUT/pointer"
cat "$OUT/marks.txt"
ls -l "$OUT"
