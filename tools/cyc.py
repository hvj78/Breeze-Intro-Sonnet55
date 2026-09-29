#!/usr/bin/env python3
"""Cell length checker for 64tass listings.

Every raster-line "cell" of the intro starts with an instruction annotated `; c0`.
This tool sums the CPU cycles between consecutive `; c0` annotations and reports
the length of each cell.  Expected: 63 for a full line, 20 for a short cell
(the one before a bad line, followed by 43 stolen cycles).

  cyc.py build/intro.lst          summary + list of unexpected cells
  cyc.py build/intro.lst -v       list every cell
Branches count as not taken unless the source line contains ';taken' or the
branch is a `bne` loop closer annotated `taken`.  Indexed reads are assumed not
to cross a page (tables are page aligned on purpose).  The block is only
measured between the `block:` label and the line containing `; end of block`.
"""
import re, sys, collections
from py65.devices.mpu6502 import MPU

CYC = MPU().cycletime
BRANCH = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}
line_re = re.compile(r'^\.([0-9a-fA-F]{4})\t((?:[0-9a-f]{2} ?)+)\t[^\t]*\t(.*)$')
OK = {63, 20}


def main():
    path = sys.argv[1]
    verbose = '-v' in sys.argv
    in_block = False
    cells = []          # (start_addr, cycles)
    cur = None
    for ln in open(path, errors='replace'):
        if re.search(r'\sblock:\s*$', ln):
            in_block = True
        m = line_re.match(ln)
        if not m:
            continue
        addr = int(m.group(1), 16)
        src = m.group(3)
        if not in_block:
            continue
        if '; end of block' in src:
            if cur:
                cells.append(cur)
            break
        op = int(m.group(2).split()[0], 16)
        c = CYC[op]
        if op in BRANCH and ';' in src and 'taken' in src.split(';', 1)[1] and 'not taken' not in src:
            c += 1
        if re.search(r';\s*c0\b', src):
            if cur:
                cells.append(cur)
            cur = [addr, 0]
        if cur:
            cur[1] += c
    hist = collections.Counter(c for _, c in cells)
    print(f'{len(cells)} cells:', dict(sorted(hist.items())))
    bad = [(a, c) for a, c in cells if c not in OK]
    for a, c in cells if verbose else bad:
        print(f'  cell @ ${a:04x}: {c} cycles{"" if c in OK else "   <-- UNEXPECTED"}')
    sys.exit(1 if bad else 0)


main()
