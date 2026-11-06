#!/usr/bin/env python3
"""udpsend.py HOST PORT SIZE RATE SECS -- send SIZE-byte UDP datagrams at RATE per second for SECS; prints what was sent.
From the host, an 8 KiB datagram reaches the guest as a burst of fragments on its network card, no larger than the host's
path MTU allows."""
import socket
import sys
import time

host, port, size, rate, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
d = bytes(size)
sent = err = 0
t0 = time.time()
while True:
    now = time.time() - t0
    if now >= secs:
        break
    due = int(now * rate)
    while sent + err <= due:
        try:
            s.sendto(d, (host, port))
            sent += 1
        except OSError:
            err += 1
    time.sleep(0.002)
print('udpsend: %d datagrams of %d bytes, %d send errors, %.1f s' % (sent, size, err, time.time() - t0))
