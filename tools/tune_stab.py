#!/usr/bin/env python3
"""Search the stabiliser parameters: for every setting build with DEBUG_EDGE, take several
screenshots and print the column at which the calibration stripe starts on the mid-zone
lines.  A stable raster shows the SAME column in every screenshot (8 px = 1 cycle)."""
import subprocess, sys, time, collections
sys.path.insert(0, 'tools')
from vicetool import Vice
from PIL import Image

def measure(cfg, shots=5):
    subprocess.run(['make', '-s', f'CFG=DEBUG_EDGE=1 {cfg}'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    v = Vice('build/intro.prg'); t0 = time.time(); cols = []
    for i in range(shots):
        time.sleep(max(0, 7 + 1.37 * i - (time.time() - t0)))
        v.shot(f'build/tune_{i}.png'); v.go()
    v.close()
    for i in range(shots):
        im = Image.open(f'build/tune_{i}.png').convert('RGB'); cnt = collections.Counter()
        W = lambda r: r[0] > 240 and r[1] > 240 and r[2] > 240
        for y in range(70, 212):
            if W(im.getpixel((40, y))): continue          # white copper bar line
            for x in range(41, 300):
                if W(im.getpixel((x, y))) and all(W(im.getpixel((x + d, y))) for d in (10, 20, 30, 40)):
                    cnt[x] += 1; break
        cols.append(cnt.most_common(1)[0][0] if cnt else None)
    return cols

if __name__ == '__main__':
    for cfg in sys.argv[1:]:
        print(cfg, '->', measure(cfg), flush=True)
