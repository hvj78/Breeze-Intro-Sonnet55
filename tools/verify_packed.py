#!/usr/bin/env python3
"""Run build/breeze.prg (packed) in VICE, dump RAM and compare the regions that the intro never
modifies at run time (code, charsets, constant tables) with the unpacked build/intro.prg."""
import sys, time, os
sys.path.insert(0, 'tools')
from vicetool import Vice
orig = open('build/intro.prg', 'rb').read()[2:]        # loaded at $0801
regions = [('block code + wave tables', 0x8000, 0xB900), ('sine tables', 0xB900, 0xCA00),
           ('charsets', 0x4000, 0x5000), ('logo screens', 0x5000, 0x6C00), ('sprite data', 0x7400, 0x7600),
           ('update code', 0x2300, 0x3155), ('boot code', 0x0810, 0x0985)]
v = Vice('build/breeze.prg'); time.sleep(9)
v.cmd('del')
ram = v.dump(0x0801, 0xC9FF); v.close()
ok = True
for n, a, e in regions:
    same = ram[a - 0x801:e - 0x801] == orig[a - 0x801:e - 0x801]
    ok &= same
    print(f'{n:26s} ${a:04x}-${e - 1:04x}  {"identical" if same else "DIFFERENT"}')
sys.exit(0 if ok else 1)
