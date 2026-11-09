# The walkthrough video

`overview-walkthrough.mp4` shows the app in use, with a Dutch voice-over and captions.

- The picture is a screen recording of the real app, made by `Scripts/walkthrough.sh` on the macOS build machine. It plays at its real speed.
- The voice (`voice/`, text in `narration.txt`) and the sounds are generated with ElevenLabs. A screen recording has no sound of its own, so the app's sounds are added at the moments the app plays them.

## State of the current video

This is a first cut of 46 seconds. The first recording ran slower than planned and stopped during the fifth of its eight parts, so the cut covers the start screen, a scan, the sunburst, pointing at arcs and list rows, and opening a folder. The treemap, the list of largest files and moving a file to the Trash are in the narration and in the recording script, but not yet in the video.

`first-cut.py` is the edit list of this cut. For a complete recording, use `Scripts/assemble-video.py`:

```bash
Scripts/build-app.sh && Scripts/walkthrough.sh build/walkthrough
```

```bash
Scripts/assemble-video.py build/walkthrough docs/video/overview-walkthrough.mp4
```

The second step needs ffmpeg, Python with Pillow, and the Inter font.
