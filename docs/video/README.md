# The walkthrough video

`overview-walkthrough.mp4` (82 seconds) shows the app in use, with a Dutch voice-over and captions: the start screen, a scan, the sunburst, pointing at arcs and list rows, going into folders and back, the treemap, the largest files, and moving a file to the Trash.

- The picture is a screen recording of the real app, made by `Scripts/walkthrough.sh` on the macOS build machine with a scripted pointer. It plays at its real speed, uncut.
- The voice (`voice/`, text in `narration.txt`) is generated with ElevenLabs, and so are the app's sounds. A screen recording has no sound of its own, so the app's sounds are added at the moments the app plays them (`marks.txt` has those moments for this recording).

## Making it again

```bash
Scripts/build-app.sh && Scripts/walkthrough.sh build/walkthrough
```

```bash
Scripts/assemble-video.py build/walkthrough docs/video/overview-walkthrough.mp4
```

The first step needs a Mac and resets the app's preferences. The pointer positions in it are for a 1280 x 800 window, and the terminal needs Accessibility access to move the pointer. The second step needs ffmpeg, Python with Pillow, and the Inter font; it runs on Linux too.
