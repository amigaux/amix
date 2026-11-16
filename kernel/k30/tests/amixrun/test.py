#!/usr/bin/env python3
# tests/amixrun/test.py AMIXRUN -- amixrun.py against a fake telnet server: over-long, answered, never answered, old marker text.
# MIT licence, see LICENSE in kernel/k30.
import os, re, socket, subprocess, sys, threading, time
def serve(mode):
    l = socket.socket(); l.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); l.bind(('127.0.0.1', 0)); l.listen(1)
    def run():
        c, _ = l.accept(); c.sendall(b'login: '); c.recv(99); c.sendall(b'Password:'); c.recv(99); c.sendall(b'# ')
        d = c.recv(999)
        import re
        m = re.search(rb"D''ONE_(\w+)_", d)
        n = m.group(1) if m else b''
        real = (b'DONE_' + n + b'_0\r\n# ') if m else b'DONE_0\r\n# '
        if mode == 'answer': c.sendall(b'hello\r\n' + real)
        if mode == 'stale': c.sendall(b'DONE_0\r\nDONE_7\r\n')
        if mode == 'late': c.sendall(b'DONE_0\r\nDONE_7\r\n'); time.sleep(0.3); c.sendall(b'the rest\r\n' + real)
        try:
            c.recv(99)
        except OSError:
            pass
        c.close()
    threading.Thread(target=run, daemon=True).start()
    return l.getsockname()[1]
T = sys.argv[1]; bad = 0
def go(name, want, cmd, port):
    global bad
    env = dict(os.environ, AMIX_HOST='127.0.0.1', AMIX_PORT=str(port), AMIX_PASS='x', AMIX_CMD_TIMEOUT='2')
    p = subprocess.run([sys.executable, T, cmd], env=env, capture_output=True, text=True, timeout=40)
    ok = p.returncode == want
    # the marker comes out as DONE_<rc>, the nonce taken out, as callers parse it
    if ok and want == 0 and ('DONE_0' not in p.stdout or re.search(r'DONE_\w+_\d', p.stdout)):
        ok = False
    bad += not ok
    print('%-4s %-36s rc %d (want %d) %s' % ('ok' if ok else 'FAIL', name, p.returncode, want, p.stderr.strip()[:70]))
go('over-long, nothing dialled', 2, 'x' * 233, 1)
go('exactly the limit, answered', 0, 'x' * 232, serve('answer'))
go('old DONE_ text, never finishes', 1, 'cat /old', serve('stale'))
go('old DONE_ text, then the real end', 0, 'cat /old', serve('late'))
go('a short command, answered', 0, 'date', serve('answer'))
go('a command never finishes', 1, 'date', serve('silent'))
# telnet sends a bare CR as CR NUL: the transcript keeps the CR only, also across two reads; a NUL not after a CR is kept
class Chunks:
    def __init__(self, chunks): self.chunks = list(chunks)
    def settimeout(self, t): pass
    def recv(self, n): return self.chunks.pop(0) if self.chunks else b''
    def sendall(self, data): pass
import importlib.util
os.environ.update(AMIX_HOST='127.0.0.1', AMIX_PASS='x')   # amixrun refuses to load without them; nothing is dialled here
spec = importlib.util.spec_from_file_location('amixrun', T); ar = importlib.util.module_from_spec(spec); spec.loader.exec_module(ar)
got = ar.readuntil(Chunks([b'ab\r', b'\x00cd\r\x00\n', b'x\x00y\r\n']), [], 5)
ok = got == b'ab\rcd\r\nx\x00y\r\n'; bad += not ok
print('%-4s %-36s %r' % ('ok' if ok else 'FAIL', 'CR NUL folded, a lone NUL kept', got))
sys.exit(1 if bad else 0)
