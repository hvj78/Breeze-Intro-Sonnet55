#!/usr/bin/env python3
"""Cycle profile of the per-frame update routine (py65 emulation of build/intro.prg).

usage: profile.py [frames]      prints per-frame cycle statistics and the worst frames
The raster block itself is not emulated; only  update  (music + engine).
"""
import re, sys, collections
from py65.devices.mpu6502 import MPU

frames = int(sys.argv[1]) if len(sys.argv) > 1 else 2500
prg = open('build/intro.prg', 'rb').read()
lbl = {}
for l in open('build/intro.lbl'):
    m = re.match(r'al ([0-9a-f]+) \.(\w+)', l)
    if m: lbl[m.group(2)] = int(m.group(1), 16)

class Mem(list):
    def __init__(s):
        super().__init__([0] * 65536)
    def __getitem__(s, i):
        if i == 0xdc01: return 0xff        # no key
        return super().__getitem__(i)

mem = Mem()
la = prg[0] | prg[1] << 8
for i, b in enumerate(prg[2:]): list.__setitem__(mem, la + i, b)
mpu = MPU(memory=mem)

def call(addr, limit=400000):
    mpu.memory[0x1ff] = 0x02; mpu.memory[0x1fe] = 0xff; mpu.sp = 0xfd
    mpu.pc = addr
    mem[0x300] = 0x00
    c0 = mpu.processorCycles; n = 0
    while mpu.pc != 0x300 and n < limit:
        mpu.step(); n += 1
    return mpu.processorCycles - c0

# boot: what start does, minus hardware
call(lbl['init_all'])
call(0x1000)                 # music init
call(lbl['frame_logic'])

# per routine accounting through instruction hooks
names = ['do_timeline','do_logo','do_scroller','do_bars','do_fade_tasks','patch_dtab','set_entries','sc0a','sc0b','sc0c','sc1a','sc1b','sc1c','do_input']
addr2name = {lbl[n]: n for n in names}
stat = collections.defaultdict(list)
tot = []
for f in range(frames):
    mem[0x14] = (f + 1) & 0xff; mem[0x15] = ((f + 1) >> 8) & 0xff   # zp_frame (inc happens in update)
    # emulate update body with profiling: run step by step
    mpu.memory[0x1ff] = 0x02; mpu.memory[0x1fe] = 0xff; mpu.sp = 0xfd
    mpu.pc = lbl['update']
    c0 = mpu.processorCycles
    cur = None; cstart = c0; per = collections.Counter()
    depth = []
    n = 0
    music = 0
    while mpu.pc != 0x300 and n < 400000:
        pc = mpu.pc
        if pc == 0x1003:
            m0 = mpu.processorCycles
            # run until return
            sp0 = mpu.sp
            while True:
                mpu.step()
                if mpu.sp > sp0: break
            music = mpu.processorCycles - m0
            continue
        if pc in addr2name:
            depth.append((addr2name[pc], mpu.processorCycles, mpu.sp))
        mpu.step(); n += 1
        if depth and mpu.sp > depth[-1][2]:
            nm, t0, _ = depth.pop()
            per[nm] += mpu.processorCycles - t0
    total = mpu.processorCycles - c0
    tot.append(total)
    for k, v in per.items(): stat[k].append(v)
    stat['music'].append(music)
    stat['total'].append(total)
    if f % 400 == 0: pass

print(f'frames {frames}:  total/frame avg {sum(tot)//len(tot)}  max {max(tot)}  (budget ~5900)')
for k, v in stat.items():
    print(f'  {k:16s} avg {sum(v)//len(v):5d}  max {max(v):5d}')
ss=[t for f,t in enumerate(tot) if f>1300]
print('steady state (frame>1300): avg',sum(ss)//len(ss),'max',max(ss))
worst = sorted(range(len(tot)), key=lambda i: -tot[i])[:8]
print('worst frames:', [(w + 1, tot[w]) for w in worst])
over = sum(1 for t in tot if t > 5900)
print('frames over 5900:', over)
