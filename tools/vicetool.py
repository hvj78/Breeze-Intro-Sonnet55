#!/usr/bin/env python3
"""Small controller for x64sc through its text remote monitor.

    from vicetool import Vice
    v = Vice("build/intro.prg")          # starts VICE, injects and runs the PRG
    v.wait(3)                            # seconds of emulated real time (wall clock)
    v.shot("build/a.png")                # screenshot (384x272 PAL, normal borders)
    print(v.cmd("m 0006 0009"))          # any monitor command (emulation is paused inside)
    v.go()                               # resume (leave the monitor)
    v.close()
"""
import os, socket, subprocess, time

class Vice:
    def __init__(self, prg, port=6510, extra=(), sound=False):
        cmd = ["x64sc", "-VICIIborders", "0", "-remotemonitor",
               "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
               "-autostartprgmode", "1"]
        cmd += ["-sound"] if sound else ["+sound"]
        cmd += list(extra) + ["-autostart", prg]
        self.p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.s = None
        for _ in range(150):
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        if not self.s:
            self.p.kill(); raise RuntimeError("no monitor connection")
        self.s.settimeout(0.6)
        self.t0 = time.time()
        self.paused = False

    def _read(self):
        data = b""
        try:
            while True:
                chunk = self.s.recv(65536)
                if not chunk: break
                data += chunk
                if data.rstrip().endswith(b")"): break
        except socket.timeout:
            pass
        return data.decode(errors="replace")

    def wait(self, sec):
        time.sleep(sec)

    def cmd(self, c):
        self.s.sendall((c + "\n").encode())
        self.paused = True
        time.sleep(0.15)
        return self._read()

    def shot(self, path):
        out = self.cmd(f'screenshot "{os.path.abspath(path)}" 2')
        time.sleep(0.2)
        return out

    def dump(self, a, e, chunk=0x400):
        """read memory a..e (inclusive) through the monitor, returns bytes"""
        import re
        out = bytearray()
        for s0 in range(a, e + 1, chunk):
            e0 = min(e, s0 + chunk - 1)
            txt = self.cmd(f'm {s0:04x} {e0:04x}')
            got = {}
            for m in re.finditer(r'>C:([0-9a-f]{4})((?:\s+[0-9a-f]{2}){1,4}(?:\s+[0-9a-f]{2}){0,12})', txt):
                addr = int(m.group(1), 16)
                for i, h in enumerate(m.group(2).split()):
                    got[addr + i] = int(h, 16)
            out += bytes(got.get(x, 0xEE) for x in range(s0, e0 + 1))
        return bytes(out)

    def go(self):
        self.s.sendall(b"x\n"); self.paused = False; time.sleep(0.1); self._read()

    def close(self):
        try: self.s.sendall(b"quit\n")
        except Exception: pass
        time.sleep(0.4)
        if self.p.poll() is None: self.p.kill()
