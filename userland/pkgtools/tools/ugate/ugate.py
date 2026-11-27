#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
"""ugate.py -- the user-path release gate: released disks, a candidate repository, the commands a user types.

  ugate.py run   --conf FILE --tree DIR --rows FILE --out DIR [--only ID,ID] [--keep-disks]
  ugate.py check --conf FILE --tree DIR --rows FILE          the plan, nothing run
  ugate.py judge --rows FILE --out DIR [--conf FILE]         judge (again) the rows of an earlier run
  ugate.py --selftest

run: serves DIR (a make dist release/<ver> tree, read-only, at /<ver>/) to the boxes, gives every row a slot and a
copy of its disk that claims the slot's address, boots it in the emulator (the row runner, kerntools' rig-run, two
boots by default: the second is the power cycle a kernel upgrade asks for), runs the row's commands on boot 1 as a
root user types them (box/ugate-box.sh), the row's session check on boot 2 when it names one, then judges every
row and writes OUT/report.md and OUT/report.tsv. Rows run in parallel, one per slot. Exit 0 every row passed, 1 a
row failed (named in the report and on stderr), 2 usage or set-up.

A row passes when: every command exits with the status the row expects (0 unless written "=N command"); the box
script finished; pkgchk -n shows no error after that it did not show before; no bus error on any boot; the session
check passed; the row runner raised no other reason than those in UGATE_IGNORE_CHECKS.

Nothing on the box is prepared by hand: the only change ugate makes to it is /etc/apkg.conf's repo= line, set to
the candidate repository for the commands and put back after them, and the disk copy's own address (one per slot).

The rows file (rows/*.rows):
    # comment
    row <id> <line> <disk> [session=<name>] [boots=<n>]
        apkg update
        =5 apkg install cde          <- a command expected to exit 5
<line> is k30 or k46; <disk> is a name looked up as $UGATE_DISKS/<disk>.hdf (or a path). Command lines are
indented. The conf file (KEY=VALUE lines, ${VAR} expanded; see ugate.conf.example) holds everything about the
emulator host: no address, slot or host path is in this directory.
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
REQUIRED = ("UGATE_RUNNER", "UGATE_SLOT_ENV", "UGATE_DISKADDR", "UGATE_BIND", "UGATE_PORT", "UGATE_SLOTS",
            "UGATE_DISKS", "AMIX_PASS")
DEFAULTS = {
    "UGATE_RUNNER_ARGS": "",
    "UGATE_IMAGE_KEY": "root6",
    "UGATE_IGNORE_CHECKS": "display-rtg",
    "UGATE_ROW_PREFIX": "E9",
    "UGATE_REFUSE_SLOTS": "",
    "UGATE_ROW_TIMEOUT": "14400",
    "UGATE_BOX_WAIT": "7200",
    "UGATE_AMIXRUN": os.path.join(REPO, "kernel", "k30", "tools", "amixrun.py"),
    "UGATE_AMIXSYNC": os.path.join(REPO, "kernel", "k30", "tools", "amixsync.py"),
    "UGATE_SESSION_HOOK": "",
}
ROWID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")


class Row:
    def __init__(self, rid, line, disk, session="none", boots=2, lineno=0):
        self.id, self.line, self.disk, self.session, self.boots = rid, line, disk, session, boots
        self.cmds = []          # (expected rc, command)
        self.lineno = lineno
        self.slot = self.rig = self.copy = None


def die(msg, rc=2):
    print("ugate: " + msg, file=sys.stderr)
    sys.exit(rc)


def read_conf(path):
    conf = dict(DEFAULTS)
    if path:
        env = dict(os.environ)
        with open(path) as f:
            for n, raw in enumerate(f, 1):
                s = raw.strip()
                if not s or s.startswith("#"):
                    continue
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", s)
                if not m:
                    die("%s:%d: not KEY=VALUE" % (path, n))
                k, v = m.group(1), m.group(2)
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                    v = v[1:-1]
                v = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", lambda mm: conf.get(mm.group(1), env.get(mm.group(1), "")), v)
                v = v.replace("\\t", "\t")
                conf[k] = v
    for k in list(conf) + list(REQUIRED):
        if k in os.environ and k.startswith(("UGATE_", "AMIX_")):
            conf[k] = os.environ[k]
    return conf


def parse_rows(path):
    rows, cur = [], None
    with open(path) as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if line[0] in " \t":
                if cur is None:
                    raise ValueError("%s:%d: a command before any row" % (path, n))
                want = 0
                m = re.match(r"^=(\d+)\s+(.*)$", s)
                if m:
                    want, s = int(m.group(1)), m.group(2)
                if "\n" in s or len(s) > 200:
                    raise ValueError("%s:%d: a command is one line of at most 200 bytes" % (path, n))
                cur.cmds.append((want, s))
                continue
            w = s.split()
            if w[0] != "row" or len(w) < 4:
                raise ValueError("%s:%d: expected 'row <id> <line> <disk> [session=..] [boots=..]'" % (path, n))
            if not ROWID.match(w[1]):
                raise ValueError("%s:%d: bad row id %r" % (path, n, w[1]))
            if w[2] not in ("k30", "k46"):
                raise ValueError("%s:%d: line %r is not k30 or k46" % (path, n, w[2]))
            cur = Row(w[1], w[2], w[3], lineno=n)
            for opt in w[4:]:
                k, _, v = opt.partition("=")
                if k == "session" and v:
                    cur.session = v
                elif k == "boots" and v.isdigit() and int(v) >= 1:
                    cur.boots = int(v)
                else:
                    raise ValueError("%s:%d: unknown row option %r" % (path, n, opt))
            if any(r.id == cur.id for r in rows):
                raise ValueError("%s:%d: row id %s used twice" % (path, n, cur.id))
            rows.append(cur)
    for r in rows:
        if not r.cmds:
            raise ValueError("%s:%d: row %s has no commands" % (path, r.lineno, r.id))
        if r.session != "none" and r.boots < 2:
            raise ValueError("%s:%d: row %s names a session: it needs boots=2 or more" % (path, r.lineno, r.id))
    return rows


def disk_path(conf, name):
    return name if "/" in name else os.path.join(conf["UGATE_DISKS"], name + ".hdf")


def slots_of(conf):
    refuse = set(conf["UGATE_REFUSE_SLOTS"].replace(",", " ").split())
    out = []
    for s in conf["UGATE_SLOTS"].replace(",", " ").split():
        if not s.isdigit():
            die("UGATE_SLOTS: %r is not a slot number" % s)
        if s in refuse:
            die("UGATE_SLOTS names slot %s, which UGATE_REFUSE_SLOTS refuses" % s)
        out.append(s)
    if not out:
        die("UGATE_SLOTS is empty")
    return out


def plan(conf, tree, rows):
    errs = []
    for k in REQUIRED:
        if not conf.get(k):
            errs.append("conf: %s is not set" % k)
    for r in rows:
        if not conf.get("UGATE_ROW_" + r.line):
            errs.append("conf: UGATE_ROW_%s (the matrix columns of a %s row) is not set" % (r.line, r.line))
        if conf.get("UGATE_DISKS") and not os.path.isfile(disk_path(conf, r.disk)):
            errs.append("row %s: no disk %s" % (r.id, disk_path(conf, r.disk)))
        if r.session != "none" and not conf.get("UGATE_SESSION_HOOK"):
            errs.append("row %s names session %s and UGATE_SESSION_HOOK is not set" % (r.id, r.session))
    for f in ("catalog", "catalog.md5"):
        if not os.path.isfile(os.path.join(tree, f)):
            errs.append("tree %s: no %s" % (tree, f))
    return errs


def matrix_line(conf, r):
    cols = conf["UGATE_ROW_" + r.line].split("\t")
    flags = conf.get("UGATE_FLAGS_" + r.line, "-")
    ev = "user-path gate row %s (%s, disk %s)" % (r.id, r.line, r.disk)
    return "\t".join([r.rig] + cols + [ev, flags, "%s=%s" % (conf["UGATE_IMAGE_KEY"], r.copy)])


def serve(conf, tree, out):
    name = os.path.basename(os.path.normpath(tree))
    cmd = [sys.executable, "-I", os.path.join(HERE, "ugate-serve.py"), "--bind", conf["UGATE_BIND"],
           "--port", conf["UGATE_PORT"], "--name", name, "--tree", tree, "--log", os.path.join(out, "serve.log")]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    line = p.stdout.readline().strip()
    if not line.startswith("ugate-serve: ready "):
        p.kill()
        die("the server did not start: %s" % line)
    url = line.split()[-1]
    with urllib.request.urlopen(url + "/catalog", timeout=10) as r:
        r.read()
    return p, url


def run_row(conf, out, r, url, log):
    rd = os.path.join(out, "rows", r.id)
    os.makedirs(rd, exist_ok=True)
    with open(os.path.join(rd, "cmds"), "w") as f:
        for want, c in r.cmds:
            f.write("%d %s\n" % (want, c))
    env = dict(os.environ)
    env.update({k: v for k, v in conf.items() if k.startswith(("UGATE_", "AMIX_"))})
    env.update({"UGATE_DIR": HERE, "UGATE_URL": url, "UGATE_ROWDIR": rd, "UGATE_SESSION": r.session,
                "RIG_HOLDER_PID": str(os.getpid())})
    cmd = ["timeout", conf["UGATE_ROW_TIMEOUT"], "bash", conf["UGATE_RUNNER"], "run"] + \
        shlex.split(conf["UGATE_RUNNER_ARGS"]) + \
        ["--matrix", os.path.join(out, "matrix.tsv"), "--rows", r.rig, "--slots", r.slot, "--boots", str(r.boots),
         "--no-writeback", "--out-dir", os.path.join(rd, "run"),
         "--host-extra", "bash " + shlex.quote(os.path.join(HERE, "ugate-hook.sh"))]
    t0 = time.time()
    with open(os.path.join(rd, "runner.log"), "w") as lf:
        rc = subprocess.call(cmd, stdout=lf, stderr=subprocess.STDOUT, env=env,
                             cwd=os.path.dirname(os.path.dirname(os.path.abspath(conf["UGATE_RUNNER"]))))
    log("row %s (slot %s) runner rc %d, %d s" % (r.id, r.slot, rc, time.time() - t0))
    return rc


def cmd_run(a, conf):
    rows = parse_rows(a.rows)
    if a.only:
        want = a.only.split(",")
        rows = [r for r in rows if r.id in want]
        missing = set(want) - {r.id for r in rows}
        if missing:
            die("--only names rows not in %s: %s" % (a.rows, ",".join(sorted(missing))))
    tree = os.path.abspath(a.tree)
    errs = plan(conf, tree, rows)
    if errs:
        die("\n  ".join(["the plan does not hold:"] + errs))
    slots = slots_of(conf)
    out = os.path.abspath(a.out)
    if os.path.exists(out) and os.listdir(out):
        die("%s exists and is not empty" % out)
    os.makedirs(os.path.join(out, "disks"), exist_ok=True)
    lock = threading.Lock()
    logf = open(os.path.join(out, "ugate.log"), "a")

    def log(msg):
        with lock:
            line = time.strftime("%H:%M:%S ") + msg
            print(line, flush=True)
            logf.write(line + "\n")
            logf.flush()
    t0 = time.time()
    log("ugate run: tree %s, rows %s (%d), slots %s" % (tree, a.rows, len(rows), ",".join(slots)))
    for i, r in enumerate(rows, 1):
        r.rig = "%s%02d" % (conf["UGATE_ROW_PREFIX"], i)
    srv, url = serve(conf, tree, out)
    log("serving %s as %s" % (tree, url))
    free = list(slots)
    cv = threading.Condition()
    threads = []

    def worker(r):
        try:
            r.copy = os.path.join(out, "disks", "%s-s%s.hdf" % (r.id, r.slot))
            dl = subprocess.run(["python3", conf["UGATE_DISKADDR"], "--set", r.slot, disk_path(conf, r.disk), r.copy],
                                capture_output=True, text=True)
            with open(os.path.join(out, "disks", r.id + "-diskaddr.txt"), "w") as f:
                f.write(dl.stdout + dl.stderr)
            if dl.returncode != 0:
                log("row %s: the disk copy for slot %s failed (disks/%s-diskaddr.txt)" % (r.id, r.slot, r.id))
                return
            with lock:
                with open(os.path.join(out, "matrix.tsv"), "a") as f:
                    f.write(matrix_line(conf, r) + "\n")
            log("row %s: slot %s, disk %s, %d command(s), session %s" % (r.id, r.slot, r.disk, len(r.cmds), r.session))
            run_row(conf, out, r, url, log)
        finally:
            if r.copy and os.path.exists(r.copy) and not a.keep_disks:
                os.remove(r.copy)
            with cv:
                free.append(r.slot)
                cv.notify_all()

    with open(os.path.join(out, "matrix.tsv"), "w") as f:
        f.write("# user-path gate rows (ugate.py)\n")
    try:
        for r in rows:
            with cv:
                while not free:
                    cv.wait()
                r.slot = free.pop(0)
            t = threading.Thread(target=worker, args=(r,))
            t.start()
            threads.append(t)
            time.sleep(15)          # the runner's start-up, one at a time
        for t in threads:
            t.join()
    finally:
        srv.terminate()
        srv.wait()
    wall = time.time() - t0
    log("all rows done, wall %d s" % wall)
    with open(os.path.join(out, "slots.tsv"), "w") as f:
        for r in rows:
            f.write("%s\t%s\t%s\n" % (r.id, r.slot, r.rig))
    return judge(conf, rows, out, wall, tree)


# ------------------------------------------------------------------ judge ---
def cell_of(out, r):
    base = os.path.join(out, "rows", r.id, "run")
    if r.rig is None:
        cand = [d for d in (os.listdir(base) if os.path.isdir(base) else []) if os.path.isdir(os.path.join(base, d))]
        r.rig = cand[0] if len(cand) == 1 else None
    return os.path.join(base, r.rig) if r.rig else None


def errset(path):
    try:
        return set(re.findall(r"^ERROR: (\S+)", open(path, errors="replace").read(), re.M))
    except OSError:
        return None


def buserrs(cell):
    n, seen = 0, False
    for f in sorted(os.listdir(cell)) if cell and os.path.isdir(cell) else []:
        if f.startswith("03-buserr") and f.endswith(".txt"):
            seen = True
            for m in re.finditer(r"(?:syslog|serial|console OCR) (\d+)", open(os.path.join(cell, f), errors="replace").read()):
                n += int(m.group(1))
    return n if seen else None


def clean_out(text):
    keep = [l for l in text.splitlines() if not re.match(r"^apkg: \.\.\. \d+/\d+ bytes", l) and l.strip()]
    return keep


def judge_row(conf, out, r):
    res = {"id": r.id, "line": r.line, "disk": r.disk, "slot": r.slot or "-", "fails": [], "cmds": [], "kernels": []}
    cell = cell_of(out, r)
    box = os.path.join(cell, "ugate", "box") if cell else None
    if not cell or not os.path.isdir(cell):
        res["fails"].append("the row did not run (no runner cell)")
        return res
    rt = os.path.join(cell, "result.tsv")
    reasons = []
    if os.path.isfile(rt):
        f = open(rt).read().split("\t")
        reasons = [x for x in (f[3].split() if len(f) > 3 else []) if x != "-"]
    else:
        res["fails"].append("the runner wrote no result.tsv")
    ignore = set(conf["UGATE_IGNORE_CHECKS"].replace(",", " ").split())
    res["ignored"] = [x for x in reasons if x.split(":")[-1] in ignore]
    for x in reasons:
        if x.split(":")[-1] in ignore:
            continue
        if x.endswith("host-extra"):
            b = x.split(":")[0] if ":" in x else "b1"
            res["fails"].append("boot 1: the box script did not finish" if b == "b1"
                                else "%s: session %s failed" % (b, r.session))
        else:
            res["fails"].append("runner: " + x)
    for k in range(1, r.boots + 1):
        u = os.path.join(cell, "ugate", "boot%d-uname.txt" % k)
        k = [l.strip() for l in open(u, errors="replace")] if os.path.isfile(u) else []
        k = [l for l in k if l and not l.startswith("#")]
        res["kernels"].append(" / ".join(k) if k else "?")
    results = os.path.join(box, "results")
    got = {}
    if os.path.isfile(results):
        for l in open(results, errors="replace"):
            p = l.rstrip("\n").split("\t", 3)
            if len(p) == 4 and p[0].isdigit():
                got[int(p[0])] = (int(p[1]) if p[1].lstrip("-").isdigit() else p[1], int(p[2]), p[3])
    elif not any("box script" in x for x in res["fails"]):
        res["fails"].append("boot 1: no results from the box")
    for i, (want, c) in enumerate(r.cmds, 1):
        o = os.path.join(box, "out.%d" % i) if box else ""
        text = clean_out(open(o, errors="replace").read()) if o and os.path.isfile(o) else []
        rc = got.get(i, (None,))[0]
        res["cmds"].append({"n": i, "cmd": c, "want": want, "rc": rc, "out": text})
        if rc is None:
            if os.path.isfile(results):
                res["fails"].append("command %d did not run: %s" % (i, c))
        elif rc != want:
            res["fails"].append("command %d exited %s, expected %d: %s%s" % (i, rc, want, c,
                                (" -- " + text[-1]) if text else ""))
    b, af = errset(os.path.join(box, "pkgchk-before.txt")), errset(os.path.join(box, "pkgchk-after.txt"))
    if b is None or af is None:
        res["pkgchk"] = "not run"
        if os.path.isfile(results):
            res["fails"].append("pkgchk did not run")
    else:
        new = sorted(af - b)
        res["pkgchk"] = "%d ERROR before, %d after, %d new%s" % (len(b), len(af), len(new),
                                                                 (": " + " ".join(new[:8])) if new else "")
        if new:
            res["fails"].append("pkgchk -n: %d new error(s): %s" % (len(new), " ".join(new[:8])))
    be = buserrs(cell)
    res["buserr"] = "?" if be is None else str(be)
    if be:
        res["fails"].append("%d bus error(s)" % be)
    res["pass"] = not res["fails"]
    return res


def judge(conf, rows, out, wall=None, tree=None):
    st = os.path.join(out, "slots.tsv")
    if os.path.isfile(st):
        for l in open(st):
            p = l.rstrip("\n").split("\t")
            for r in rows:
                if r.id == p[0]:
                    r.slot, r.rig = p[1], p[2]
    res = [judge_row(conf, out, r) for r in rows]
    md = ["# User-path gate report", ""]
    if tree:
        md.append("- tree: `%s`, catalog md5 %s" % (tree, md5file(os.path.join(tree, "catalog"))))
    if wall is not None:
        md.append("- wall time: %d s (%d min) for %d row(s)" % (wall, round(wall / 60), len(rows)))
    md.append("- result: **%s**" % ("PASS" if all(x["pass"] for x in res) else
                                    "FAIL (" + ", ".join(x["id"] for x in res if not x["pass"]) + ")"))
    md += ["", "| row | line | disk | slot | result | commands (rc) | kernel boot 1 -> last | pkgchk -n | bus errors |",
           "|---|---|---|---|---|---|---|---|---|"]
    for x in res:
        cmds = "; ".join("%s (%s%s)" % (c["cmd"], c["rc"], "" if c["rc"] == c["want"] else " != %d" % c["want"])
                         for c in x["cmds"])
        k = [re.sub(r"^\S+ \S+ ", "", s) for s in x["kernels"]]
        md.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            x["id"], x["line"], x["disk"], x["slot"], "PASS" if x["pass"] else "**FAIL**", cmds,
            (k[0] + " -> " + k[-1]) if k else "?", x.get("pkgchk", "?"), x.get("buserr", "?")))
    for x in res:
        md += ["", "## %s: %s" % (x["id"], "PASS" if x["pass"] else "FAIL")]
        for f in x["fails"]:
            md.append("- FAIL: " + f)
        if x.get("ignored"):
            md.append("- runner reasons ignored (UGATE_IGNORE_CHECKS): " + " ".join(x["ignored"]))
        for c in x["cmds"]:
            md += ["", "`# %s` -> rc %s (expected %d)" % (c["cmd"], c["rc"], c["want"]), "", "```"]
            md += (c["out"][:40] + (["... (%d more lines, rows/%s/run/*/ugate/box/out.%d)" % (len(c["out"]) - 40, x["id"], c["n"])]
                                    if len(c["out"]) > 40 else [])) or ["(no output)"]
            md.append("```")
    with open(os.path.join(out, "report.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    with open(os.path.join(out, "report.tsv"), "w") as f:
        f.write("#row\tline\tdisk\tslot\tresult\tfails\n")
        for x in res:
            f.write("%s\t%s\t%s\t%s\t%s\t%s\n" % (x["id"], x["line"], x["disk"], x["slot"],
                                                  "PASS" if x["pass"] else "FAIL", " | ".join(x["fails"]) or "-"))
    bad = [x for x in res if not x["pass"]]
    for x in bad:
        print("ugate: FAIL row %s: %s" % (x["id"], "; ".join(x["fails"])), file=sys.stderr)
    print("ugate: %s -- %s" % ("PASS" if not bad else "FAIL", os.path.join(out, "report.md")))
    return 1 if bad else 0


def md5file(p):
    import hashlib
    try:
        return hashlib.md5(open(p, "rb").read()).hexdigest()
    except OSError:
        return "?"


# --------------------------------------------------------------- selftest ---
def selftest():
    ok = True
    with tempfile.TemporaryDirectory() as d:
        rf = os.path.join(d, "t.rows")
        open(rf, "w").write("# x\nrow a k30 disk-a session=cde\n\tapkg update\n\t=5 apkg install cde\n"
                            "row b k46 /x/y.hdf boots=1\n    apkg upgrade\n")
        rows = parse_rows(rf)
        ok &= [(r.id, r.line, r.disk, r.session, r.boots) for r in rows] == \
            [("a", "k30", "disk-a", "cde", 2), ("b", "k46", "/x/y.hdf", "none", 1)]
        ok &= rows[0].cmds == [(0, "apkg update"), (5, "apkg install cde")]
        for bad in ("\tapkg update\n", "row a k99 d\n\tx\n", "row a k30 d\n", "row a k30 d session=cde boots=1\n\tx\n",
                    "row a k30 d\n\tx\nrow a k30 d\n\tx\n", "row a k30 d colour=red\n\tx\n"):
            open(rf, "w").write(bad)
            try:
                parse_rows(rf)
                ok = False
                print("selftest: accepted %r" % bad)
            except ValueError:
                pass
        # judge: a passing row and a failing one, from fixture cells
        conf = dict(DEFAULTS)
        out = os.path.join(d, "out")

        def cell(rid, rig, results, before, after, reasons="-", bus=(0, 0), outs=()):
            c = os.path.join(out, "rows", rid, "run", rig)
            os.makedirs(os.path.join(c, "ugate", "box"))
            open(os.path.join(c, "result.tsv"), "w").write("%s\t7\t%s\t%s\t1/1\n" % (rig, "PASS" if reasons == "-" else "FAIL", reasons))
            for i, b in enumerate(bus, 1):
                open(os.path.join(c, "03-buserr%s.txt" % ("" if i == 1 else "-b%d" % i)), "w").write(
                    "bus errors this boot: syslog %d (x), serial 0, console OCR 0\n" % b)
                open(os.path.join(c, "ugate", "boot%d-uname.txt" % i), "w").write("UNIX_System_V uaeamix 4.0 2.1c 0800430 Amiga (Unlimited) 68060-26112%d-68 m68k\n" % i)
            open(os.path.join(c, "ugate", "box", "results"), "w").write(results)
            open(os.path.join(c, "ugate", "box", "pkgchk-before.txt"), "w").write(before)
            open(os.path.join(c, "ugate", "box", "pkgchk-after.txt"), "w").write(after)
            for i, t in enumerate(outs, 1):
                open(os.path.join(c, "ugate", "box", "out.%d" % i), "w").write(t)
        a = Row("a", "k30", "d")
        a.cmds = [(0, "apkg update"), (5, "apkg install cde")]
        cell("a", "E901", "1\t0\t0\tapkg update\n2\t5\t5\tapkg install cde\n", "ERROR: /etc/x\n", "ERROR: /etc/x\n",
             reasons="b2:display-rtg", outs=("apkg: ... 1/2 bytes\ncatalog updated\n", "apkg: missing dependency\n"))
        b = Row("b", "k46", "d", session="cde")
        b.cmds = [(0, "apkg install cde")]
        cell("b", "E902", "1\t0\t0\tapkg install cde\n", "", "ERROR: /opt/x\n", reasons="b2:host-extra b2:display-rtg",
             bus=(0, 3))
        rc = judge(conf, [a, b], out)
        tsv = open(os.path.join(out, "report.tsv")).read()
        ok &= rc == 1 and "\na\tk30\td\t-\tPASS\t-\n" in tsv
        rb = [l for l in tsv.splitlines() if l.startswith("b\t")][0]
        ok &= "FAIL" in rb and "session cde failed" in rb and "new error" in rb and "3 bus error" in rb
        md = open(os.path.join(out, "report.md")).read()
        ok &= "1/2 bytes" not in md and "catalog updated" in md and "FAIL (b)" in md
    print("ugate: selftest", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    p = argparse.ArgumentParser(description="the user-path release gate")
    sub = p.add_subparsers(dest="verb", required=True)
    for v in ("run", "check", "judge"):
        s = sub.add_parser(v)
        s.add_argument("--conf", required=(v != "judge"))
        s.add_argument("--rows", required=True)
        if v != "judge":
            s.add_argument("--tree", required=True)
        if v != "check":
            s.add_argument("--out", required=True)
        if v == "run":
            s.add_argument("--only")
            s.add_argument("--keep-disks", action="store_true")
    a = p.parse_args()
    conf = read_conf(a.conf)
    try:
        if a.verb == "run":
            return cmd_run(a, conf)
        rows = parse_rows(a.rows)
    except ValueError as e:
        die(str(e))
    if a.verb == "check":
        errs = plan(conf, os.path.abspath(a.tree), rows)
        for r in rows:
            print("row %s: %s, disk %s, session %s, %d boot(s)" % (r.id, r.line, disk_path(conf, r.disk), r.session, r.boots))
            for want, c in r.cmds:
                print("    %s%s" % ("" if want == 0 else "=%d " % want, c))
        print("slots: %s" % ",".join(slots_of(conf)) if conf.get("UGATE_SLOTS") else "slots: (not set)")
        for e in errs:
            print("ugate: " + e, file=sys.stderr)
        return 2 if errs else 0
    return judge(conf, rows, os.path.abspath(a.out))


if __name__ == "__main__":
    sys.exit(main())
