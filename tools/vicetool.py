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

    def go(self):
        self.s.sendall(b"x\n"); self.paused = False; time.sleep(0.1); self._read()

    def close(self):
        try: self.s.sendall(b"quit\n")
        except Exception: pass
        time.sleep(0.4)
        if self.p.poll() is None: self.p.kill()
