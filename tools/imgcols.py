#!/usr/bin/env python3
"""Print run-length colour transitions along a pixel column: imgcols.py img.png x [x2 ...]"""
import sys
from PIL import Image
PAL = {(0,0,0):'0 black',(255,255,255):'1 white',(136,0,0):'2 red',(170,255,238):'3 cyan',(204,68,204):'4 purple',
 (0,204,85):'5 green',(0,0,170):'6 blue',(238,238,119):'7 yellow',(221,136,85):'8 orange',(102,68,0):'9 brown',
 (255,119,119):'a lred',(51,51,51):'b dgrey',(119,119,119):'c grey',(170,255,102):'d lgreen',(0,136,255):'e lblue',(187,187,187):'f lgrey'}
def name(c):
    if c in PAL: return PAL[c]
    best=min(PAL,key=lambda p:sum((a-b)**2 for a,b in zip(p,c)))
    return PAL[best][0]+'~'
im=Image.open(sys.argv[1]).convert('RGB')
print(im.size)
for x in map(int,sys.argv[2:]):
    print('column',x)
    prev=None;start=0
    for y in range(im.height+1):
        c=name(im.getpixel((x,y))) if y<im.height else None
        if c!=prev:
            if prev is not None: print(f'  y{start:3d}-{y-1:3d} {prev}')
            prev=c;start=y
