# Recording a video of the demo

The video is rendered **frame-exact** instead of being screen-captured. That needs no screen-recording
permission, cannot drop frames, and keeps picture and sound perfectly in step, however slow the capture is.

Requirements: VICE 3.x (`x64sc`), `ffmpeg`, Python 3 (standard library only), and the built
`build/breeze.prg` (`make packed`) plus `build/intro.lbl` (written by `make`).

```sh
make && make packed                                   # build/intro.lbl + build/breeze.prg
python3 tools/record_video.py build/frames            # ~4 minutes: PNG per frame + audio.wav
python3 tools/encode_video.py build/frames demo.mp4   # 1080p H.264 + AAC, ready for YouTube
```

## How it works

1. **Frames.** `record_video.py` starts VICE with the remote monitor and a start-up script containing one breakpoint,
   `break <irq1>`: the first instruction of the raster interrupt, which runs exactly once per frame (every 19,656 cycles).
   At each stop the script sends `screenshot "fNNNNN.png" 2` and continues. The canvas at that moment holds the
   previous, completely drawn frame. (The breakpoint has to be set at start-up: in warp mode the demo would otherwise
   run minutes of emulated time before the script connects.)
2. **Audio.** VICE records its sound with `-sounddev wav`. The emulator only produces samples while it runs, so the
   pauses for screenshots do not disturb the audio. The WAV driver writes nothing in warp mode, so the capture
   runs at normal speed.
3. **Ending the demo.** Every 25 frames the script reads the scroll-text pointer (`$3F/$40`) from RAM. About one second
   after it reaches the end of the text it pokes `$31 = 1`, which is exactly what pressing SPACE does, and captures 70
   more frames: the fade-out and a moment of black.
4. **Encoding.** `encode_video.py` needs the audio offset. VICE starts recording when its boot-time warp phase ends, not
   at power-on, so the offset is computed from the emulated cycle counter: the audio ends at the cycle of the last
   captured frame, hence `offset = first_frame_cycle − (last_frame_cycle − samples · 985248 / 48000)`.
   It was cross-checked against the music onset (fade-in step of the SID volume); both agree within ~50 ms.
   Video: crop 384x272 to 384x270, scale x4 with nearest neighbour (1536x1080), centre on 1920x1080, 50.1245 fps
   (the true PAL frame rate, `985248 / 19656`); audio: mono to stereo AAC 256 kbit/s.

## Notes

* The capture script starts `build/breeze.prg` by default; another PRG can be given as the 3rd argument.
* Frames end up in `build/frames` (about 3,600 small PNGs, ignored by git). The finished video is not part of the
  repository (`release-video/` is git-ignored).
* Uploading is a manual step (YouTube Studio → Create → Upload); nothing here needs any account.
* The automatic exit stands in for the key press; the SPACE key scan itself is not exercised by this method.
* The wave/bob timings do not depend on wall-clock time, so every capture is identical frame by frame.
