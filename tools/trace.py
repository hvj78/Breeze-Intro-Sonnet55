#!/usr/bin/env python3
"""trace.py prg addr[,addr...] : run, stop at each address once, print raster LIN/CYC, A X Y and some regs"""
import re,sys,time
sys.path.insert(0,'tools')
from vicetool import Vice
prg=sys.argv[1]
def cells():
    out=[];inb=False
    for ln in open('build/intro.lst'):
        if re.search(r'\sblock:\s*$',ln): inb=True
        m=re.match(r'^\.([0-9a-f]{4})\t.*;\s*c0\b',ln)
        if inb and m: out.append(int(m.group(1),16))
    return out
CELLS=cells()
def parse(a):
    return CELLS[int(a[1:])] if a[0]=='c' else int(a,16)
addrs=[parse(a) for a in sys.argv[2].split(',')]
mons=sys.argv[3:]           # extra monitor commands run at each stop
v=Vice(prg); v.wait(2)
for a in addrs:
    v.cmd('del'); v.cmd(f'break {a:x}')
    v.s.sendall(b"x\n"); time.sleep(0.6)
    o=v._read()
    m=re.search(r'\(Stop on\s+exec\s+(\w+)\)\s+(\d+)/\$[0-9a-f]+,\s+(\d+)',o)
    reg=re.search(r'A:(\w\w) X:(\w\w) Y:(\w\w)',o)
    print(f'${a:04x}: line {m.group(2) if m else "?"} cyc {m.group(3) if m else "?"}  regs {reg.groups() if reg else "?"}')
    for c in mons:
        print('   ',v.cmd(c).replace('\n','\n    ').strip())
v.close()
