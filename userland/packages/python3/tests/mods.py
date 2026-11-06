# mods.py -- the modules a script expects: subprocess, csv, decimal, locks, XML.  ON THE BOX.
#
#     python3 tests/mods.py
#
# SIGALRM's default action ends it if something hangs.
# MIT, see LICENSE.amix in the package.

import array
import asyncio
import bisect
import cmath
import contextvars
import csv
import decimal
import fcntl
import fractions
import grp
import heapq
import io
import os
import pickle
import plistlib
import queue
import shutil
import signal
import statistics
import subprocess
import sys
import syslog
import tempfile
import termios
import threading
import time
import xml.dom.minidom
import xml.etree.ElementTree

signal.alarm(300)
fails = 0


def check(what, good, detail=""):
    global fails
    print("RES %s %s %s" % ("ok  " if good else "FAIL", what, detail), flush=True)
    if not good:
        fails += 1


# subprocess: a real program, pipes both ways, a status, the shell, a timeout
r = subprocess.run(["uname", "-s"], capture_output=True, text=True)
check("subprocess uname", r.returncode == 0 and r.stdout.strip() != "", repr(r.stdout.strip()))
r = subprocess.run(["tr", "amix", "AMIX"], input=b"amix\n" * 4000, capture_output=True)
check("subprocess through a pipe both ways", r.stdout == b"AMIX\n" * 4000, "%d bytes" % len(r.stdout))
r = subprocess.run("exit 3", shell=True)
check("subprocess status through the shell", r.returncode == 3)
t = time.time()
try:
    subprocess.run(["sleep", "30"], timeout=1)
    check("subprocess timeout", False)
except subprocess.TimeoutExpired:
    check("subprocess timeout", time.time() - t < 15, "%.1f s" % (time.time() - t))
try:
    subprocess.run(["/no/such/program"])
    check("subprocess of no program", False)
except FileNotFoundError:
    check("subprocess of no program", True)

# a thread keeps running while the main thread waits for a child
n = [0]
go = [True]


def tick():
    while go[0]:
        n[0] += 1
        time.sleep(0.05)


th = threading.Thread(target=tick)
th.start()
subprocess.run(["sleep", "2"])
go[0] = False
th.join()
check("a thread runs while a child is waited for", n[0] >= 5, "%d ticks" % n[0])

# csv
b = io.StringIO()
rows = [["a", "b,c", 'd"e'], ["1", "2", "3"]]
csv.writer(b).writerows(rows)
check("csv round trip", list(csv.reader(io.StringIO(b.getvalue()))) == rows)

# decimal, fractions, statistics, cmath, contextvars
decimal.getcontext().prec = 40
d = decimal.Decimal(1) / decimal.Decimal(7)
check("decimal", str(d) == "0.1428571428571428571428571428571428571429", str(d))
check("fractions", fractions.Fraction(1, 3) + fractions.Fraction(1, 6) == fractions.Fraction(1, 2))
check("statistics", statistics.mean([1, 2, 3, 4]) == 2.5 and round(statistics.stdev([1, 2, 3, 4]), 6) == 1.290994)
check("cmath", abs(cmath.exp(1j * cmath.pi) + 1) < 1e-12)
v = contextvars.ContextVar("v", default=1)
check("contextvars", contextvars.copy_context().run(lambda: (v.set(2), v.get())[1]) == 2 and v.get() == 1)

# file locks: another process is refused, then gets it
tmp = tempfile.mkdtemp(prefix="mods")
p = os.path.join(tmp, "lock")
code = "import fcntl,sys\nf=open(sys.argv[1],'r+')\ntry:\n fcntl.%s\n print('got')\nexcept OSError as e:\n print('refused',e.errno)\n"
f = open(p, "w+")
fcntl.lockf(f, fcntl.LOCK_EX)
r = subprocess.run([sys.executable, "-c", code % "lockf(f,fcntl.LOCK_EX|fcntl.LOCK_NB)", p], capture_output=True, text=True)
check("lockf refuses another process", r.stdout.startswith("refused"), r.stdout.strip() + r.stderr[-80:])
fcntl.lockf(f, fcntl.LOCK_UN)
r = subprocess.run([sys.executable, "-c", code % "lockf(f,fcntl.LOCK_EX|fcntl.LOCK_NB)", p], capture_output=True, text=True)
check("lockf, once released", r.stdout.startswith("got"), r.stdout.strip() + r.stderr[-80:])
fcntl.flock(f, fcntl.LOCK_EX)
r = subprocess.run([sys.executable, "-c", code % "flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)", p], capture_output=True, text=True)
check("flock refuses another process", r.stdout.startswith("refused"), r.stdout.strip() + r.stderr[-80:])
fcntl.flock(f, fcntl.LOCK_UN)
f.close()
shutil.rmtree(tmp)

# XML through pyexpat
x = xml.dom.minidom.parseString("<a><b c='1'>t\u00e4</b></a>")
check("minidom", x.getElementsByTagName("b")[0].getAttribute("c") == "1")
e = xml.etree.ElementTree.fromstring("<a><b>t\u00e4</b></a>")
check("ElementTree", e.find("b").text == "t\u00e4")
check("plistlib", plistlib.loads(plistlib.dumps({"k": [1, 2]})) == {"k": [1, 2]})
try:
    xml.dom.minidom.parseString("<a><b></a>")
    check("expat refuses bad XML", False)
except Exception as err:
    check("expat refuses bad XML", True, type(err).__name__)

# the C versions are the ones in use, and they work
check("pickle is _pickle", pickle.Pickler.__module__ == "_pickle" and pickle.loads(pickle.dumps({"a": (1, 2.5)})) == {"a": (1, 2.5)})
h = [5, 1, 3]
heapq.heapify(h)
check("heapq", heapq.heappop(h) == 1 and heapq.heappush.__module__ == "_heapq")
check("bisect", bisect.bisect([1, 3, 5], 4) == 2 and bisect.bisect.__module__ == "_bisect")
q = queue.SimpleQueue()
q.put(1)
check("queue", q.get() == 1 and q.__class__.__module__ == "_queue")
check("array", array.array("i", [1, 2, 3]).tolist() == [1, 2, 3] and array.array("d", [0.5]).tobytes() != b"")
check("grp", grp.getgrgid(0).gr_gid == 0, grp.getgrgid(0).gr_name)
try:
    termios.tcgetattr(os.open("/dev/null", os.O_RDONLY))
    check("termios", False, "/dev/null is a terminal")
except termios.error as err:
    check("termios", True, str(err.args[0]))
syslog.openlog("mods.py")
syslog.syslog(syslog.LOG_INFO, "test line from python3 mods.py")
syslog.closelog()
check("syslog", True)


# asyncio: a sleep, TCP on loopback, a child
async def amain():
    await asyncio.sleep(0.01)

    async def serve(rd, wr):
        wr.write(await rd.read(16))
        await wr.drain()
        wr.close()

    s = await asyncio.start_server(serve, "127.0.0.1", 0)
    port = s.sockets[0].getsockname()[1]
    rd, wr = await asyncio.open_connection("127.0.0.1", port)
    wr.write(b"amix")
    await wr.drain()
    got = await rd.read(16)
    wr.close()
    s.close()
    await s.wait_closed()
    c = await asyncio.create_subprocess_exec("uname", "-s", stdout=asyncio.subprocess.PIPE)
    out, _ = await c.communicate()
    return got, c.returncode, out


got, rc, out = asyncio.run(amain())
check("asyncio TCP", got == b"amix")
check("asyncio child", rc == 0 and out.strip() != b"", repr(out.strip()))

if fails:
    print("RES FAIL mods: %d" % fails)
    raise SystemExit(1)
print("RES ok   mods")
