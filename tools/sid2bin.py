#!/usr/bin/env python3
"""Strip the PSID header: sid2bin.py in.sid out.bin  -> raw code (without the 2 byte load address)
and print the addresses the intro needs (load / init / play)."""
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:4] in (b'PSID', b'RSID'), 'not a SID file'
ver, off, load, init, play, songs, start, speed = struct.unpack('>HHHHHHHI', d[4:22])
name, author, released = (d[i:i + 32].split(b'\0')[0].decode('latin1') for i in (0x16, 0x36, 0x56))
body = d[off:]
if load == 0:                       # load address is the first two data bytes
    load = body[0] | body[1] << 8
    body = body[2:]
open(sys.argv[2], 'wb').write(body)
print(f'{name!r} by {author!r} ({released}): load ${load:04x}-${load + len(body) - 1:04x} init ${init or load:04x} play ${play:04x} songs {songs}')
