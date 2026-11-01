# starve.py -- does a CPU-bound thread let the others run?  ON THE BOX.
#
#     python3 tests/starve.py
#
# A worker spins in pure Python until the main thread, after time.sleep(0.2),
# sets a flag.  Under cooperative Pth threads the main thread runs again only
# if the worker gives the interpreter up.  SIGALRM after 10 s keeps its default
# action, which ends the process: a hang shows as a kill, not a stuck test (a
# Python-level handler would itself need the main thread to run).
# MIT, see LICENSE.amix in the package.

import signal
import threading
import time

signal.alarm(10)
flag = False
loops = 0


def worker():
    global loops
    while not flag:
        loops += 1


t0 = time.time()
t = threading.Thread(target=worker)
t.start()
time.sleep(0.2)
flag = True
t.join()
signal.alarm(0)
print("RES ok   starve: the main thread ran again after %.2f s (%d worker loops)"
      % (time.time() - t0, loops))
