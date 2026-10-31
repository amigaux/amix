# smoke.py -- Python 3.11 acceptance, run on the box by smoke.sh.  Prints one
# "RES ok|FAIL <what>" line per check.
import sys
fails = 0
def check(what, cond):
    global fails
    print("RES %s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        fails += 1

check("version %s" % sys.version.split()[0], sys.version_info[:3] == (3, 11, 18))
check("big integers: 2**200 %% 1000003", 2 ** 200 % 1000003 == pow(2, 200, 1000003))
check("float: 0.1 + 0.2 repr", repr(0.1 + 0.2) == "0.30000000000000004")
import json
check("json round trip", json.loads(json.dumps({"a": [1, 2.5, "x"]})) == {"a": [1, 2.5, "x"]})
import zlib
data = bytes(range(256)) * 400
check("zlib round trip of %d bytes" % len(data), zlib.decompress(zlib.compress(data, 9)) == data)
import hashlib
check("sha256 of b'abc'", hashlib.sha256(b"abc").hexdigest() ==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
import datetime
check("datetime arithmetic", datetime.date(2026, 10, 31) - datetime.date(2026, 1, 1) == datetime.timedelta(days=303))
import threading, queue
q = queue.Queue()
def worker(n):
    q.put(sum(range(n)))
ts = [threading.Thread(target=worker, args=(10000 * (i + 1),)) for i in range(4)]
for t in ts:
    t.start()
for t in ts:
    t.join()
got = sorted(q.get() for _ in range(4))
check("four threads through pth", got == sorted(sum(range(10000 * (i + 1))) for i in range(4)))
import os, tempfile
d = tempfile.mkdtemp(dir=".")
with open(os.path.join(d, "f"), "w") as f:
    f.write("hello\n")
check("file I/O and listdir", os.listdir(d) == ["f"] and open(os.path.join(d, "f")).read() == "hello\n")
import sysconfig
check("sysconfig platform %s" % sysconfig.get_platform(), "amigaunix" in sysconfig.get_platform())
print("RES python %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
sys.exit(1 if fails else 0)
