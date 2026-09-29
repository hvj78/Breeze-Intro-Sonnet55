#!/usr/bin/env python3
"""Frame exact video capture of the intro with VICE.

The emulator is stopped by a breakpoint at the first instruction of the raster IRQ (once per frame),
a screenshot is taken and the emulator continues.  The audio is recorded through VICE's WAV driver, so
emulated time and audio samples stay exactly in step no matter how slow the capture is.

usage: record_video.py out_dir [max_frames [prg]]
       -> out_dir/f00000.png ..., out_dir/audio.wav, out_dir/info.txt   (then run tools/encode_video.py)
The demo is left with the same action as pressing SPACE (exit flag) a few seconds after the scroller
text has run to its end.
"""
import os, re, socket, subprocess, sys, time

out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
max_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
lbl = {}
for l in open('build/intro.lbl'):
    m = re.match(r'al ([0-9a-f]+) \.(\w+)', l)
    if m: lbl[m.group(2)] = int(m.group(1), 16)
irq1, text_lbl = lbl['irq1'], lbl['scrolltext']
# length of the scroll text = bytes up to the terminator in the assembled program
prg = open('build/intro.prg', 'rb').read()[2:]
p = text_lbl - 0x801
while prg[p]: p += 1
text_end = 0x801 + p

wav = os.path.join(out, 'audio.wav')
for f in (wav,):
    if os.path.exists(f): os.remove(f)
mc = os.path.join(out, 'mon.txt')
open(mc, 'w').write(f'break {irq1:x}\n')
cmd = ['x64sc', '-moncommands', mc, '-VICIIborders', '0', '-remotemonitor', '-remotemonitoraddress', 'ip4://127.0.0.1:6511',
       '-autostartprgmode', '1', '-sound', '-sounddev', 'wav', '-soundarg', wav,
       '-autostart', sys.argv[3] if len(sys.argv) > 3 else 'build/breeze.prg']
proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
s = None
for _ in range(100):
    try: s = socket.create_connection(('127.0.0.1', 6511), timeout=2); break
    except OSError: time.sleep(0.2)
s.settimeout(30)

def recv_until(pat, timeout=60):
    buf = b''; t0 = time.time()
    while time.time() - t0 < timeout:
        try: chunk = s.recv(65536)
        except socket.timeout: break
        buf += chunk
        if re.search(pat, buf): return buf.decode(errors='replace')
    return buf.decode(errors='replace')

def send(c): s.sendall((c + '\n').encode())
def mon(c, pat=rb'\(C:\$[0-9a-f]{4}\) $'):
    send(c); return recv_until(pat)

recv_until(rb'\(C:', 3)
send('x')
frame = 0; c0 = None; wrapped_at = None; exit_sent = None
while frame < max_frames:
    txt = recv_until(rb'Stop on\s+exec[^\n]*\n[^\n]*\n\(C:\$[0-9a-f]{4}\) ', 120)
    if 'Stop on' not in txt:
        print('lost the breakpoint, frames so far', frame); break
    if c0 is None:
        r = mon('r'); c0 = int(r.strip().split('\n')[-2].split()[-1]); print('first frame at cycle', c0)
    send(f'screenshot "{out}/f{frame:05d}.png" 2')
    recv_until(rb'\(C:\$[0-9a-f]{4}\) $', 30)
    frame += 1
    if frame % 25 == 0:
        m = mon('m 003f 0040 ')
        mm = re.search(r'>C:003f\s+(\w\w)\s+(\w\w)', m)
        sp = int(mm.group(2), 16) << 8 | int(mm.group(1), 16) if mm else 0
        ex = re.search(r'>C:0031\s+(\w\w)', mon('m 0031 0031 '))
        exit_state = int(ex.group(1), 16) if ex else 0
        if wrapped_at is None and text_end - 3 <= sp <= text_end + 1:
            wrapped_at = frame; print('scroll text at its end, frame', frame)
        if wrapped_at is not None and exit_sent is None and frame >= wrapped_at + 50:
            mon('> 0031 01'); exit_sent = frame; print('exit flag set at frame', frame)
        if exit_sent and frame >= exit_sent + 70:      # fade (40 frames) + a moment of black
            print('finished at frame', frame); break
        if frame % 500 == 0: print('frame', frame, flush=True)
    send('x')
try: send('quit')
except Exception: pass
for _ in range(50):
    if proc.poll() is not None: break
    time.sleep(0.1)
if proc.poll() is None: proc.kill()
open(os.path.join(out, 'info.txt'), 'w').write(f'frames {frame}\nfirst_frame_cycle {c0}\nframe_cycles 19656\n')
print('frames', frame)
