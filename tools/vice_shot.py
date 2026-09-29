#!/usr/bin/env python3
"""Launch x64sc with the text remote monitor, wait, take screenshots, quit.
usage: vice_shot.py prg out_prefix [delay_s ...]
"""
import socket, subprocess, sys, time, os, signal

def main():
    prg, prefix = sys.argv[1], sys.argv[2]
    delays = [float(x) for x in sys.argv[3:]] or [3.0]
    port = 6510
    cmd = ["x64sc", "+sound", "-VICIIborders", "0", "-remotemonitor",
           "-remotemonitoraddress", f"ip4://127.0.0.1:{port}", "-autostartprgmode", "1", "-autostart", prg]
    p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    s = None
    for _ in range(100):
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=1); break
        except OSError:
            time.sleep(0.2)
    if not s:
        p.kill(); sys.exit("no monitor connection")
    s.settimeout(2)
    def send(c):
        s.sendall((c + "\n").encode()); time.sleep(0.3)
        try: return s.recv(65536).decode(errors="replace")
        except socket.timeout: return ""
    t0 = time.time()
    for i, d in enumerate(delays):
        time.sleep(max(0, d - (time.time() - t0)))
        out = f"{prefix}_{i}.png"
        print(send(f'screenshot "{os.path.abspath(out)}" 2'))
    send("quit")
    time.sleep(0.5)
    if p.poll() is None: p.kill()
main()
