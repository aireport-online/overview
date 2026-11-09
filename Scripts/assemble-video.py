#!/usr/bin/env python3
"""Turns a walkthrough recording into the tutorial video.

Takes what Scripts/walkthrough.sh recorded (walkthrough.mov, marks.txt,
window.txt), cuts out the app window, sets it on a blurred backdrop, and adds
the voice-over, captions and the app's own sounds at the moments the app
plays them (a screen recording has no sound of its own).

    Scripts/assemble-video.py <walkthrough folder> <output.mp4>

Needs ffmpeg and ffprobe, and Pillow for lining up the recording.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
VOICE = ROOT / "docs/video/voice"
SOUNDS = ROOT / "Resources/Sounds"
NARRATION = ROOT / "docs/video/narration.txt"
FONT = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"

# The sound the app plays at each mark, and how long after it.
SOUND_AT_MARK = {
    "scan": [("scan-start", 0.0), ("scan-complete", 1.45)],
    "zoom-in": [("zoom-in", 0.0)],
    "zoom-out": [("zoom-out", 0.0)],
    "select": [("select", 0.0)],
    "trash": [("trash", 0.0)],
}
VOICE_DELAY = 0.5     # the voice starts this long after its mark
LEAD_IN = 1.0         # video before the first mark
CANVAS = (1920, 1080)


def run(*command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"{command[0]} failed ({result.returncode}): {result.stderr[-2000:]}")
    return result.stdout


def duration(path):
    return float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)))


def read_marks(path):
    marks = []
    for line in path.read_text().split("\n"):
        if line.strip():
            label, time = line.split()
            marks.append((label, float(time)))
    return marks


def find_scan_frame(video, window, guess):
    """The moment the scanning screen appears: the first frame after the click
    in which the window as a whole differs from how it looked before. (The
    pointer and hover effects only change small parts of it.) Returns seconds
    into the recording."""
    x, y, width, height = window
    start = max(guess - 1.5, 0)
    with tempfile.TemporaryDirectory() as folder:
        run("ffmpeg", "-v", "error", "-ss", f"{start}", "-t", "8", "-i", str(video),
            "-vf", f"fps=30,crop={width}:{height}:{x}:{y},scale=320:-1", f"{folder}/f%04d.png")
        frames = sorted(Path(folder).glob("f*.png"))
        reference = Image.open(frames[0]).convert("L")
        for index, frame in enumerate(frames):
            histogram = ImageChops.difference(Image.open(frame).convert("L"), reference).histogram()
            change = sum(level * count for level, count in enumerate(histogram)) / sum(histogram)
            if change > 3:
                return start + index / 30
    raise SystemExit("could not find the start of the scan in the recording")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    folder, output = Path(sys.argv[1]), Path(sys.argv[2])
    video = folder / "walkthrough.mov"
    marks = read_marks(folder / "marks.txt")
    window = [int(value) for value in (folder / "window.txt").read_text().split()]
    times = dict(reversed(marks))  # first occurrence of each label

    # Line up the clock of the marks with the clock of the recording.
    guess = times["scan"] - times["recording"] + 2.0
    scan_frame = find_scan_frame(video, window, guess)
    offset = scan_frame - 0.05 - times["scan"]
    start = times["intro"] + offset - LEAD_IN
    end = min(times["end"] + offset, duration(video) - 0.1)
    length = end - start

    def at(mark_time):
        return mark_time + offset - start

    # Voice-over and captions.
    audio_inputs, delays, captions = [], [], []
    parts = [line for line in NARRATION.read_text().split("\n") if line and not line.startswith("#")]
    for number, line in enumerate(parts, start=1):
        label, text = [piece.strip() for piece in line.split("|")]
        voice = VOICE / f"part{number}.mp3"
        begin = at(times[label]) + VOICE_DELAY
        audio_inputs.append((voice, 1.0))
        delays.append(begin)
        sentences = [sentence.strip() for sentence in text.split("/")]
        total = sum(len(sentence) for sentence in sentences)
        cursor = begin
        for sentence in sentences:
            share = duration(voice) * len(sentence) / total
            captions.append((sentence, cursor, cursor + share))
            cursor += share

    # The app's sounds.
    for label, time in marks:
        for sound, delay in SOUND_AT_MARK.get(label, []):
            audio_inputs.append((SOUNDS / f"{sound}.wav", 0.55))
            delays.append(at(time) + delay)

    x, y, width, height = window
    left = (CANVAS[0] - width) // 2
    top = 70
    filters = [
        f"[0:v]trim=start={start:.3f}:end={end:.3f},setpts=PTS-STARTPTS,fps=30,split[full][forwindow]",
        f"[full]crop={width}:{height}:{x}:{y},scale={CANVAS[0]}:{CANVAS[1]}:force_original_aspect_ratio=increase,"
        f"crop={CANVAS[0]}:{CANVAS[1]},boxblur=50:4,eq=brightness=-0.22:saturation=1.1[backdrop]",
        f"[forwindow]crop={width}:{height}:{x}:{y}[window]",
        f"[backdrop][window]overlay={left}:{top}[composed]",
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
        filters.append(f"{chain}fade=t=in:d=0.6,fade=t=out:st={length - 0.8:.2f}:d=0.8[video]")

        command = ["ffmpeg", "-v", "error", "-y", "-i", str(video)]
        mix = []
        for index, ((path, volume), delay) in enumerate(zip(audio_inputs, delays), start=1):
            command += ["-i", str(path)]
            milliseconds = int(max(delay, 0) * 1000)
            filters.append(f"[{index}:a]aresample=48000,volume={volume},adelay={milliseconds}:all=1[a{index}]")
            mix.append(f"[a{index}]")
        filters.append(f"{''.join(mix)}amix=inputs={len(mix)}:normalize=0,apad,atrim=end={length:.3f}[audio]")
        command += [
            "-filter_complex", ";".join(filters), "-map", "[video]", "-map", "[audio]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", str(output),
        ]
        run(*command)
    print(f"{output}: {duration(output):.1f} s")


if __name__ == "__main__":
    main()
