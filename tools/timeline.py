#!/usr/bin/env python3
"""timeline.py prg out_prefix t1 t2 ... : take screenshots at wall-clock seconds after start"""
import sys,time
sys.path.insert(0,'tools')
from vicetool import Vice
prg,prefix=sys.argv[1],sys.argv[2]
ts=[float(x) for x in sys.argv[3:]]
v=Vice(prg)
t0=time.time()
for i,t in enumerate(ts):
    # the monitor pauses emulation while a command runs: resume before waiting
    time.sleep(max(0,t-(time.time()-t0)))
    v.shot(f'{prefix}_{i}.png')
    v.go()
v.close()
