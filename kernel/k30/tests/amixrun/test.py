#!/usr/bin/env python3
# tests/amixrun/test.py AMIXRUN -- amixrun.py against a fake telnet server: over-long, answered, never answered, old marker text.
# MIT licence, see LICENSE in kernel/k30.
import os, socket, subprocess, sys, threading, time
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
    ok = p.returncode == want; bad += not ok
    print('%-4s %-36s rc %d (want %d) %s' % ('ok' if ok else 'FAIL', name, p.returncode, want, p.stderr.strip()[:70]))
go('over-long, nothing dialled', 2, 'x' * 233, 1)
go('exactly the limit, answered', 0, 'x' * 232, serve('answer'))
go('old DONE_ text, never finishes', 1, 'cat /old', serve('stale'))
go('old DONE_ text, then the real end', 0, 'cat /old', serve('late'))
go('a short command, answered', 0, 'date', serve('answer'))
go('a command never finishes', 1, 'date', serve('silent'))
sys.exit(1 if bad else 0)
