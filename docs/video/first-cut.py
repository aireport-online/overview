#!/usr/bin/env python3
"""Edits the first cut of the walkthrough video.

The first recording of Scripts/walkthrough.sh ran slower than planned and
stopped during the fifth of its eight parts. This script cuts the usable
footage (all at its real speed) to the voice-over of parts 1 to 5 and the
closing line. Scripts/assemble-video.py is the one to use for a complete
recording.

    docs/video/first-cut.py <walkthrough folder> <output.mp4>
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
VOICE = ROOT / "docs/video/voice"
SOUNDS = ROOT / "Resources/Sounds"
FONT = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"
CANVAS = (1920, 1080)
FADE = 0.35

# Pieces of the recording, in seconds: (start, end, seconds to hold the last frame).
PIECES = [
    (1.6, 5.4, 0),      # start screen, the disc leaning towards the pointer
    (19.4, 33.0, 0),    # to the Scan button, the scan, the chart opening
    (44.5, 53.0, 0),    # pointing at arcs around the chart
    (60.0, 64.5, 0),    # pointing at the largest folders
    (69.5, 74.5, 0),    # pointing at rows of the list
    (77.8, 83.25, 1.2), # clicking Movies, which opens
    (36.0, 42.5, 0),    # the whole folder again
]
SCAN_CLICK = 25.36   # in the recording
ZOOM_CLICK = 81.48

# (voice part, piece it starts in, seconds after the start of that piece, sentences)
VOICE_OVER = [
    (1, 0, 0.6, ["Dit is Overview.", "De app laat zien wat er ruimte inneemt op je Mac.", "Kies een schijf of een map, en klik op Scan."]),
    (2, 1, 6.45, ["Overview telt nu alle bestanden.", "Dat duurt meestal maar een paar seconden."]),
    (3, 1, 11.25, ["Het resultaat is een zonnediagram.", "In het midden staat de map, en elke ring is een niveau dieper.", "Hoe groter het vlak, hoe meer ruimte het inneemt."]),
    (4, 3, 0.35, ["Wijs een vlak aan, en onderin zie je wat het is.", "De lijst rechts toont dezelfde inhoud, van groot naar klein."]),
    (5, 5, 0.35, ["Klik op een vlak om in die map te duiken.", "Klik op het midden om weer een niveau terug te gaan."]),
    (8, 6, 0.65, ["Zo zie je in één oogopslag waar je schijfruimte blijft.", "Dat is Overview."]),
]


def run(*command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{command[0]} failed ({result.returncode}): {result.stderr[-2000:]}")
    return result.stdout


def duration(path):
    return float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)))


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    folder, output = Path(sys.argv[1]), Path(sys.argv[2])
    video = folder / "walkthrough.mov"
    x, y, width, height = [int(value) for value in (folder / "window.txt").read_text().split()]

    # Where each piece starts in the edit, with the pieces overlapping by FADE.
    starts, cursor = [], 0.0
    for begin, end, hold in PIECES:
        starts.append(cursor)
        cursor += end - begin + hold - FADE
    length = cursor + FADE

    def in_edit(piece, recording_time):
        return starts[piece] + recording_time - PIECES[piece][0]

    # Cut every piece to a file of its own first: taking them all from one
    # input makes ffmpeg hold the whole recording in memory.
    scratch_folder = tempfile.TemporaryDirectory()
    pieces = []
    for index, (begin, end, hold) in enumerate(PIECES):
        piece = Path(scratch_folder.name) / f"piece{index}.mp4"
        pad = f",tpad=stop_mode=clone:stop_duration={hold}" if hold else ""
        run("ffmpeg", "-v", "error", "-y", "-ss", f"{begin}", "-t", f"{end - begin}", "-i", str(video),
            "-vf", f"fps=30,crop={width}:{height}:{x}:{y}{pad}", "-an",
            "-c:v", "libx264", "-preset", "fast", "-crf", "12", "-pix_fmt", "yuv420p", str(piece))
        pieces.append(piece)

    filters = []
    chain = "[0:v]"
    for index in range(1, len(PIECES)):
        filters.append(f"{chain}[{index}:v]xfade=transition=fade:duration={FADE}:offset={starts[index]:.3f}[joined{index}]")
        chain = f"[joined{index}]"

    left, top = (CANVAS[0] - width) // 2, 70
    filters += [
        f"{chain}split[forbackdrop][window]",
        f"[forbackdrop]scale={CANVAS[0]}:{CANVAS[1]}:force_original_aspect_ratio=increase,"
        f"crop={CANVAS[0]}:{CANVAS[1]},boxblur=50:4,eq=brightness=-0.22:saturation=1.1[backdrop]",
        f"[backdrop][window]overlay={left}:{top}[composed]",
    ]

    audio = []  # (file, volume, seconds into the edit)
    captions = []
    for part, piece, delay, sentences in VOICE_OVER:
        voice = VOICE / f"part{part}.mp3"
        begin = starts[piece] + delay
        audio.append((voice, 1.0, begin))
        total = sum(len(sentence) for sentence in sentences)
        for sentence in sentences:
            share = duration(voice) * len(sentence) / total
            captions.append((sentence, begin, begin + share))
            begin += share
    audio += [
        (SOUNDS / "scan-start.wav", 0.55, in_edit(1, SCAN_CLICK)),
        (SOUNDS / "scan-complete.wav", 0.55, in_edit(1, SCAN_CLICK) + 1.45),
        (SOUNDS / "zoom-in.wav", 0.55, in_edit(5, ZOOM_CLICK)),
    ]

    with tempfile.TemporaryDirectory() as scratch:
        chain = "[composed]"
        for index, (sentence, begin, finish) in enumerate(captions):
            text_file = Path(scratch) / f"caption{index}.txt"
            text_file.write_text(sentence)
            filters.append(
                f"{chain}drawtext=fontfile={FONT}:textfile={text_file}:fontsize=40:fontcolor=white:"
                f"x=(w-text_w)/2:y={top + height + 62}:shadowcolor=black@0.6:shadowx=0:shadowy=2:"
                f"enable='between(t,{begin:.2f},{finish:.2f})'[captioned{index}]"
            )
            chain = f"[captioned{index}]"
        filters.append(f"{chain}fade=t=in:d=0.6,fade=t=out:st={length - 0.9:.2f}:d=0.9[video]")

        command = ["ffmpeg", "-v", "error", "-y"]
        for piece in pieces:
            command += ["-i", str(piece)]
        mix = []
        for index, (path, volume, begin) in enumerate(audio, start=len(pieces)):
            command += ["-i", str(path)]
            filters.append(f"[{index}:a]aresample=48000,volume={volume},adelay={int(begin * 1000)}:all=1[a{index}]")
            mix.append(f"[a{index}]")
        filters.append(f"{''.join(mix)}amix=inputs={len(mix)}:normalize=0,apad,atrim=end={length:.3f}[audio]")
        command += [
            "-filter_complex", ";".join(filters), "-map", "[video]", "-map", "[audio]", "-t", f"{length:.3f}",
            "-threads", "2", "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(output),
        ]
        run(*command)
    print(f"{output}: {duration(output):.1f} s")
    for sentence, begin, finish in captions:
        print(f"  {begin:5.1f}-{finish:5.1f}  {sentence}")


if __name__ == "__main__":
    main()
