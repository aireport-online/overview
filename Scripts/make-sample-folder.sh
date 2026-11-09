#!/bin/bash
# Creates a folder that looks like a small home folder (about 1.2 GB of real
# data), for trying the app and for the screenshots.
#
#   Scripts/make-sample-folder.sh /path/to/new/folder
set -euo pipefail

ROOT="${1:?usage: make-sample-folder.sh <new folder>}"
mkdir -p "$ROOT"

# file <relative path> <size in kB>
file() {
    mkdir -p "$ROOT/$(dirname "$1")"
    head -c "$(($2 * 1024))" /dev/zero > "$ROOT/$1"
}

# files <folder> <prefix> <extension> <count> <smallest kB> <step kB>
files() {
    local index
    for ((index = 1; index <= $4; index++)); do
        file "$1/$2$(printf '%03d' "$index").$3" "$(($5 + (index * 7919 % 13) * $6))"
    done
}

file "Movies/Holiday in Norway.mov" 92000
file "Movies/Birthday party.mp4" 41000
file "Movies/Drone footage.mov" 27000
file "Movies/Wedding.fcpbundle/Original Media/Ceremony.mov" 18000
file "Movies/Wedding.fcpbundle/Original Media/Speeches.mov" 14000
file "Movies/Wedding.fcpbundle/Original Media/Dance floor.mov" 11000
file "Movies/Wedding.fcpbundle/Render Files/High Quality Media.dat" 22000
file "Movies/Wedding.fcpbundle/Render Files/Thumbnails.dat" 6000

files "Pictures/Photos Library.photoslibrary/originals/2023" IMG_ heic 14 900 160
files "Pictures/Photos Library.photoslibrary/originals/2024" IMG_ heic 18 1100 170
files "Pictures/Photos Library.photoslibrary/originals/2025" IMG_ heic 22 1300 150
files "Pictures/Photos Library.photoslibrary/resources/derivatives" thumb_ jpg 40 120 20
file "Pictures/Photos Library.photoslibrary/database/Photos.sqlite" 9000
files "Pictures/Screenshots" Screenshot_ png 12 300 60
file "Pictures/Scans/Passport.tiff" 7000

files "Music/Music/Media/Nils Frahm/All Melody" track_ m4a 9 5200 300
files "Music/Music/Media/Khruangbin/Mordechai" track_ m4a 8 4800 260
files "Music/Music/Media/Voice Memos" memo_ m4a 6 900 400
file "Music/GarageBand/Demo song.band" 17000

file "Documents/Presentations/Keynote 2025.key" 24000
file "Documents/Presentations/Workshop.key" 13000
files "Documents/Taxes" Statement_ pdf 9 400 150
files "Documents/Projects/website/node_modules/react/cjs" chunk_ js 14 60 30
files "Documents/Projects/website/node_modules/typescript/lib" lib_ js 12 500 260
files "Documents/Projects/website/node_modules/esbuild/bin" bin_ node 3 2800 900
files "Documents/Projects/website/src" page_ tsx 25 4 2
file "Documents/Projects/website/.git/objects/pack/pack-4f1a.pack" 15000
file "Documents/Archive/Backup 2022.zip" 21000

file "Developer/Xcode/DerivedData/Overview-abc/Build/Products/Release/Overview.app/Contents/MacOS/Overview" 9000
files "Developer/Xcode/DerivedData/Overview-abc/Build/Intermediates.noindex/Objects" unit_ o 30 350 220
files "Developer/Xcode/DerivedData/Overview-abc/Index.noindex/DataStore" shard_ db 10 1500 500
file "Developer/Xcode/iOS DeviceSupport/18.1/Symbols/dyld_shared_cache_arm64e" 34000
files "Developer/overview/.build/release" module_ swiftmodule 16 200 180

file "Library/Application Support/Slack/Cache/Cache_Data/data_1" 16000
file "Library/Application Support/Slack/Cache/Cache_Data/data_2" 9000
files "Library/Application Support/Code/CachedExtensions" ext_ vsix 7 1400 600
files "Library/Caches/com.apple.Safari/WebKitCache" blob_ bin 30 180 110
files "Library/Caches/Homebrew/downloads" bottle_ tar.gz 6 2500 1400
file "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/Annual report.pdf" 12000
file "Library/Mail/V10/MailData/Envelope Index" 19000

file "Downloads/Xcode_16.2.xip" 110000
file "Downloads/ubuntu-24.04-desktop-arm64.iso" 76000
file "Downloads/Installer.dmg" 33000
files "Downloads" Invoice_ pdf 8 150 90

file "Desktop/Notes.txt" 12
file "Desktop/Budget.numbers" 1800

echo "Created $ROOT"
