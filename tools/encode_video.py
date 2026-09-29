#!/usr/bin/env python3
"""Encode the frames + audio written by tools/record_video.py into a YouTube-ready MP4.

usage: encode_video.py frames_dir out.mp4

* video: 384x272 PAL frames -> crop to 384x270, x4 nearest neighbour = 1536x1080, centred on 1920x1080
* frame rate: exactly the C64's PAL rate 985248 / 19656 = 50.1245 fps
* audio: VICE's WAV starts when its boot-time warp phase ends, so its start is placed on the emulated
  cycle counter: the audio ends at the cycle of the last captured frame, hence
  offset = (first_frame_cycle - (last_frame_cycle - samples * 985248 / 48000)) / 985248
"""
import os, subprocess, sys

d, out = sys.argv[1], sys.argv[2]
info = dict(l.split() for l in open(os.path.join(d, 'info.txt')))
frames, c0, fc = int(info['frames']), int(info['first_frame_cycle']), int(info['frame_cycles'])
CPS = 985248.0
wav = os.path.join(d, 'audio.wav')
n = (os.path.getsize(wav) - 44) // 2                       # 16 bit mono samples
c_last = c0 + (frames - 1) * fc
offset = (c0 - (c_last - n * CPS / 48000)) / CPS
print(f'{frames} frames, audio {n / 48000:.2f} s, audio offset {offset:.3f} s')
fps = f'{int(CPS)}/{fc}'.replace('985248/19656', '123156/2457')
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-framerate', fps, '-i', os.path.join(d, 'f%05d.png'),
                '-ss', f'{offset:.4f}', '-i', wav,
                '-vf', 'crop=384:270:0:1,scale=1536:1080:flags=neighbor,pad=1920:1080:192:0:black,format=yuv420p',
                '-af', 'aresample=48000,pan=stereo|c0=c0|c1=c0',
                '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-r', fps,
                '-c:a', 'aac', '-b:a', '256k', '-shortest', '-movflags', '+faststart', out], check=True)
print('written', out, f'{os.path.getsize(out) / 1e6:.1f} MB')
