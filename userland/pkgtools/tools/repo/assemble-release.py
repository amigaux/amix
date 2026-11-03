#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# assemble-release.py -- write one release's apkg repository tree.
#
#   assemble-release.py --userland DIR --kspace DIR [--apkg DIR] [--stock DIR]
#                       [--previous DIR] --release 1.1 --out OUT
#                       [--release-check PATH] [--rom-register FILE]
#                       [--private-patterns FILE] [--scan060 PATH]
#                       [--scan060-g14 PATH] [--apkg-bin PATH]
#
# OUT gets the layout publish.sh pushes and a box reads as ONE repository:
#
#   OUT/catalog, OUT/catalog.md5
#   OUT/pkgs/<filename>          <filename> is the row's 4th field (#kpkg: file=)
#
# Inputs.
#   --userland, --kspace   gen-catalog outputs (catalog, catalog.md5, pkgs/):
#                          make dist's out/userland and out/kspace.  Their rows
#                          are taken verbatim; their files stay where the rows
#                          put them (flat in pkgs/).
#   --apkg DIR             APKG-*.pkg and APKGENG-*.pkg, exactly one of each,
#                          into pkgs/base/ (optional: absent when make dist's
#                          userland catalog already carries them).
#   --stock DIR            Commodore's datastreams, exactly those
#                          stock-<release>.lock names (size, md5, sha256),
#                          into pkgs/stock/.  amix holds none of them.
#   --previous DIR         the published tree, read-only (absent: a first
#                          release).
#   The --apkg and --stock rows are gen-catalog's, with this directory's
#   deps/names/cats/descs.conf, as every pkgtools row is made.
#
# Every live ordinary row gets its #isize line (`#ext isize 1`), the
# installed size gen-catalog --isize computes from the datastream's pkgmap,
# as the install CD's catalog has it: the installer's free-space check sizes
# the network install from it.  An input's own #isize line must agree.
#
# Every published version stays.  The catalog's live part has ONE row per
# name, the newest (every apkg ever shipped takes the first row of a name, so
# several live rows would be read wrongly by the clients on the boxes).  Older
# published rows are kept verbatim in a block every apkg skips, and their
# files stay in pkgs/ byte for byte:
#
#   #ext older 1
#   #old <row>                   an ordinary row, or
#   #old #kpkg <name> ...        a kernel-space line
#   #end older
#
# Refused (exit 1, nothing written):
#   - an input catalog whose catalog.md5 differs, a row whose file is missing
#     or whose size or md5 (#kpkg: sha256) differs, a malformed line, an #ext
#     block other than kpkg, fstype and isize (and older, in --previous), a
#     #fstype or #isize line naming a package its catalog does not carry;
#   - two inputs carrying one name, pkginst or filename, whatever the
#     versions: no newest-wins between inputs;
#   - against --previous: a published name and version whose bytes differ,
#     a version older than the published live one, a row that changes kind;
#   - a dependency that names no live row;
#   - a 68060-unimplemented instruction in an ELF of a live ordinary row,
#     by build/pkg's D4 rule: scan060.py for period ELFs; for GCC 14 ELFs
#     scan060-g14.py, with every scan060.py hit explained by it (stock/ is
#     vendor code, and kernel-space files have kernel space's own gates);
#   - tools/release-check refusing the tree;
#   - apkg itself not reading the tree as one repository (`update`, `list`).
# The tree is written to OUT.tmp and renamed into place only after every
# check; an existing OUT must be what this run writes, byte for byte.
#
# Exit: 0 written, 1 refused, 2 usage or tool error, 3 an input or a check
# tool is not there yet ([MISSING] line).  The output depends on the inputs
# alone: no time stamps, rows sorted, files copied byte for byte (mode 0644).

import argparse
import functools
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PKGTOOLS = os.path.dirname(os.path.dirname(HERE))
TOP = os.path.dirname(os.path.dirname(PKGTOOLS))
MAGIC = "#apkg-catalog 1"
CONFS = ("deps.conf", "names.conf", "cats.conf", "descs.conf")
LINE_MAX = 2047         # apkg's bound on every catalog line, comments too


class Refused(Exception):
    pass


class Missing(Exception):
    pass


class ToolError(Exception):
    pass


# ---------------------------------------------------------------- versions

def _segs(v):
    return re.split(r"[.-]", v) if v else []


def vercmp(a, b):
    """apkg_vercmp (src/apkg/vercmp.c): segments split on '.' and '-',
    numeric against numeric by value, otherwise by strcmp; a missing segment
    is "0"."""
    sa, sb = _segs(a or ""), _segs(b or "")
    n = max(len(sa), len(sb))
    for i in range(n):
        x = sa[i] if i < len(sa) else "0"
        y = sb[i] if i < len(sb) else "0"
        if x.isdigit() and y.isdigit():
            if int(x) != int(y):
                return -1 if int(x) < int(y) else 1
        elif x != y:
            return -1 if x < y else 1
    return 0


# ---------------------------------------------------------------- entries

def file_hashes(path):
    md5, sha = hashlib.md5(), hashlib.sha256()
    with open(path, "rb") as fp:
        while True:
            b = fp.read(1 << 20)
            if not b:
                break
            md5.update(b)
            sha.update(b)
    return md5.hexdigest(), sha.hexdigest()


class Entry:
    """One catalog line: an ordinary row or a #kpkg line."""

    def __init__(self, kind, line, src, pkgsdir):
        self.kind = kind            # "row" or "kpkg"
        self.line = line
        self.src = src              # the input it came from, for messages
        self.pkgsdir = pkgsdir
        self.ann = {}               # per-name block lines: {"fstype": line, ...}
        if kind == "row":
            f = line.split("|")
            if len(f) != 9:
                raise Refused("%s: not a catalog row (%d fields): %s"
                              % (src, len(f), line[:80]))
            (self.name, self.version, self.pkginst, self.filename,
             self.md5, size, deps, _cat, _desc) = f
            self.sha256 = None
            self.deps = [] if deps in ("", "none") else deps.split(",")
        else:
            t = line.split()
            if len(t) < 3:
                raise Refused("%s: not a #kpkg line: %s" % (src, line[:80]))
            self.name, self.version = t[1], t[2]
            kv = dict(x.split("=", 1) for x in t[3:] if "=" in x)
            for k in ("file", "size", "sha256"):
                if k not in kv:
                    raise Refused("%s: #kpkg %s has no %s=" % (src, self.name, k))
            self.filename, size, self.sha256 = kv["file"], kv["size"], kv["sha256"]
            self.pkginst = kv.get("pkginst", self.name)
            self.md5 = None
            self.deps = []
        if not size.isdigit():
            raise Refused("%s: %s: size %r" % (src, self.name, size))
        self.size = int(size)
        if (self.filename.startswith("/") or ".." in self.filename.split("/")
                or self.filename == ""):
            raise Refused("%s: %s: unsafe filename %r" % (src, self.name, self.filename))
        if len(self.line) + 5 > LINE_MAX:
            raise Refused("%s: %s: line too long for apkg" % (src, self.name))

    def path(self):
        return os.path.join(self.pkgsdir, self.filename)

    def verify(self):
        p = self.path()
        if not os.path.isfile(p):
            raise Refused("%s: %s %s: file %s is missing"
                          % (self.src, self.name, self.version, self.filename))
        if os.path.getsize(p) != self.size:
            raise Refused("%s: %s %s: %s is %d B, the row says %d"
                          % (self.src, self.name, self.version, self.filename,
                             os.path.getsize(p), self.size))
        md5, sha = file_hashes(p)
        if self.kind == "row" and md5 != self.md5:
            raise Refused("%s: %s %s: md5 of %s is %s, the row says %s"
                          % (self.src, self.name, self.version, self.filename,
                             md5, self.md5))
        if self.kind == "kpkg" and sha != self.sha256:
            raise Refused("%s: %s %s: sha256 of %s is %s, the line says %s"
                          % (self.src, self.name, self.version, self.filename,
                             sha, self.sha256))
        self.file_md5, self.file_sha = md5, sha

    def who(self):
        return "%s %s (%s)" % (self.name, self.version, self.src)


def read_catalog(tree, src, previous=False):
    """-> (live entries, older entries) of a gen-catalog output dir."""
    cat = os.path.join(tree, "catalog")
    md5f = os.path.join(tree, "catalog.md5")
    pkgs = os.path.join(tree, "pkgs")
    for p in (cat, md5f):
        if not os.path.isfile(p):
            raise Missing("%s: no %s" % (src, p))
    with open(cat, "rb") as fp:
        body = fp.read()
    with open(md5f) as fp:
        want = fp.read().split()
    got = hashlib.md5(body).hexdigest()
    if not want or want[0] != got:
        raise Refused("%s: catalog md5 %s, catalog.md5 says %s"
                      % (src, got, want[0] if want else "nothing"))
    lines = body.decode("utf-8").split("\n")
    if lines[-1] == "":
        lines.pop()
    if not lines or lines[0] != MAGIC:
        raise Refused("%s: catalog does not start with %r" % (src, MAGIC))
    live, older = [], []
    anns = []                   # (kind, name, line, where) of the live part
    block = None
    for n, line in enumerate(lines[1:], 2):
        where = "%s: catalog line %d" % (src, n)
        if line == "":
            continue
        if block in ANN:
            # gen-catalog closes these blocks with nothing: the next #ext
            # header or the end of the catalog ends them
            if line.startswith(ANN[block]):
                anns.append((block, ann_name(line, where), line, where))
                continue
            if line == "#end " + block:
                block = None
                continue
            block = None
        if block == "kpkg":
            if line == "#end kpkg":
                block = None
            elif line.startswith("#kpkg "):
                live.append(Entry("kpkg", line, src, pkgs))
            else:
                raise Refused("%s: unexpected line in the kpkg block: %s"
                              % (where, line[:60]))
            continue
        if block == "older":
            if line == "#end older":
                block = None
            elif line.startswith("#old #kpkg "):
                older.append(Entry("kpkg", line[5:], src, pkgs))
            elif any(line.startswith("#old " + pre) for pre in ANN.values()):
                kind = [k for k, pre in ANN.items() if line.startswith("#old " + pre)][0]
                nm = ann_name(line[5:], where)
                if not older or older[-1].name != nm or kind in older[-1].ann:
                    raise Refused("%s: %s does not follow its own older row"
                                  % (where, line[:60]))
                older[-1].ann[kind] = line[5:]
            elif line.startswith("#old ") and not line.startswith("#old #"):
                older.append(Entry("row", line[5:], src, pkgs))
            else:
                raise Refused("%s: unexpected line in the older block: %s"
                              % (where, line[:60]))
            continue
        if line == "#ext kpkg 1":
            block = "kpkg"
        elif line == "#ext older 1" and previous:
            block = "older"
        elif line[5:-2] in ANN and line == "#ext %s 1" % line[5:-2]:
            block = line[5:-2]
        elif line.startswith("#"):
            raise Refused("%s: a line this tool does not know: %s"
                          % (where, line[:60]))
        else:
            live.append(Entry("row", line, src, pkgs))
    if block is not None and block not in ANN:
        raise Refused("%s: the %s block is not closed" % (src, block))
    byname = {e.name: e for e in live}
    for kind, nm, line, where in anns:
        e = byname.get(nm)
        if e is None:
            raise Refused("%s: #%s names %s, which is not in this catalog"
                          % (where, kind, nm))
        if kind in e.ann:
            raise Refused("%s: a second #%s line for %s" % (where, kind, nm))
        e.ann[kind] = line
    return live, older


# the per-name blocks gen-catalog writes after the entries, in its order:
# {kind: line prefix}.  Comment lines to every apkg; carried with the row of
# the name they describe.
ANN = {"isize": "#isize ", "fstype": "#fstype "}


def ann_name(line, where):
    t = line.split()
    if len(t) != 3:
        raise Refused("%s: malformed line: %s" % (where, line[:60]))
    return t[1]


def gen_rows(files, src, scratch):
    """Rows for loose datastreams, by gen-catalog with this directory's
    confs.  files: [(subdir, path)].  -> [Entry] reading from scratch."""
    stage = os.path.join(scratch, "pkgs")
    os.makedirs(stage)
    for c in CONFS:
        shutil.copyfile(os.path.join(HERE, c), os.path.join(stage, c))
    for sub, p in files:
        d = os.path.join(stage, sub)
        os.makedirs(d, exist_ok=True)
        os.symlink(os.path.abspath(p), os.path.join(d, os.path.basename(p)))
    r = subprocess.run([sys.executable, "-I", "-B", os.path.join(HERE, "gen-catalog.py"),
                        "--packages-conf", "none", "-o", scratch, stage],
                       capture_output=True, text=True)
    if r.returncode != 0 or "0 skipped" not in r.stdout:
        raise ToolError("%s: gen-catalog failed:\n%s%s" % (src, r.stdout, r.stderr))
    live, older = read_catalog(scratch, src)
    return live


# ---------------------------------------------------------------- inputs

def apkg_files(d):
    if not os.path.isdir(d):
        raise Missing("--apkg: no directory %s" % d)
    out = []
    for pfx in ("APKG-", "APKGENG-"):
        m = sorted(f for f in os.listdir(d)
                   if f.startswith(pfx) and f.endswith(".pkg")
                   and re.match(r"^%s[0-9]" % pfx, f))
        if len(m) != 1:
            raise Refused("--apkg %s: %d %s*.pkg file(s), want exactly one: %s"
                          % (d, len(m), pfx, " ".join(m) or "none"))
        p = os.path.join(d, m[0])
        md5, sha = file_hashes(p)
        for ext, want in ((".md5", md5), (".sha256", sha)):
            side = p + ext
            if os.path.isfile(side):
                with open(side) as fp:
                    v = fp.read().split()
                if not v or v[0] != want:
                    raise Refused("--apkg: %s%s says %s, the file is %s"
                                  % (m[0], ext, v[0] if v else "nothing", want))
        out.append(("base", p))
    return out


def stock_files(d, lock):
    if not os.path.isfile(lock):
        raise Missing("no stock lock %s" % lock)
    want = []
    with open(lock) as fp:
        for line in fp:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            f = line.split()
            if len(f) != 4 or not f[1].isdigit():
                raise ToolError("%s: malformed line: %s" % (lock, line))
            want.append(f)
    if d is None:
        raise Missing("--stock: %s names %d stock package(s); give their "
                      "directory" % (os.path.basename(lock), len(want)))
    if not os.path.isdir(d):
        raise Missing("--stock: no directory %s" % d)
    out = []
    for name, size, md5, sha in want:
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            raise Missing("--stock: %s is not in %s" % (name, d))
        gm, gs = file_hashes(p)
        if os.path.getsize(p) != int(size) or gm != md5 or gs != sha:
            raise Refused("--stock: %s differs from %s (size %d md5 %s)"
                          % (name, os.path.basename(lock), os.path.getsize(p), gm))
        out.append(("stock", p))
    return out


# ---------------------------------------------------------------- merge

def merge(inputs, prev_live, prev_older):
    """-> (live, older, notes).  inputs: [Entry] from this build."""
    notes = []
    by = {}
    for key in ("name", "pkginst", "filename"):
        seen = {}
        for e in inputs:
            k = getattr(e, key)
            if k in seen:
                o = seen[k]
                raise Refused("%s %s is in two inputs: %s and %s"
                              % (key, k, o.who(), e.who()))
            seen[k] = e
        by[key] = seen
    live = {e.name: e for e in prev_live}
    older = list(prev_older)
    published = {}
    for e in prev_live + prev_older:
        published[(e.name, e.version)] = e
    pub_files = {e.filename: e for e in prev_live + prev_older}
    for e in inputs:
        p = published.get((e.name, e.version))
        if p is not None:
            if p.kind != e.kind:
                raise Refused("%s: published as a %s line, now a %s line"
                              % (e.who(), p.kind, e.kind))
            if (p.filename, p.size, p.file_md5) != (e.filename, e.size, e.file_md5):
                raise Refused("%s: version %s is published with other bytes "
                              "(%s, md5 %s); a published version never changes"
                              % (e.who(), e.version, p.filename, p.file_md5))
            if p.line != e.line or p.ann != e.ann:
                notes.append("%s: the row text differs from the published "
                             "one; the published row is kept" % e.who())
            continue
        f = pub_files.get(e.filename)
        if f is not None:
            raise Refused("%s: filename %s is published for %s %s"
                          % (e.who(), e.filename, f.name, f.version))
        cur = live.get(e.name)
        if cur is not None:
            if cur.kind != e.kind:
                raise Refused("%s: %s is published as a %s line, now a %s line"
                              % (e.who(), e.name, cur.kind, e.kind))
            if vercmp(e.version, cur.version) <= 0:
                raise Refused("%s: older than the published %s %s"
                              % (e.who(), cur.name, cur.version))
            older.append(cur)
            notes.append("%s replaces %s %s; that one moves to the older block"
                         % (e.who(), cur.name, cur.version))
        live[e.name] = e
    inst = {}
    for e in live.values():
        if e.pkginst in inst:
            raise Refused("pkginst %s is live twice: %s and %s"
                          % (e.pkginst, inst[e.pkginst].who(), e.who()))
        inst[e.pkginst] = e
    names = set(live)
    for e in sorted(live.values(), key=lambda x: x.name):
        for d in e.deps:
            if d not in names:
                raise Refused("%s depends on %s, which no live row names"
                              % (e.who(), d))
    return live, older, notes


_GENCAT = None


def gencat():
    """gen-catalog.py as a module: the release's #isize values come from its
    own parse_datastream() and installed_size(), the --isize code the
    install CD's catalog is written with."""
    global _GENCAT
    if _GENCAT is None:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "gen_catalog", os.path.join(HERE, "gen-catalog.py"))
        _GENCAT = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_GENCAT)
    return _GENCAT


def size_rows(live):
    """An #isize line for every live ordinary row (gen-catalog sizes
    ordinary entries only; a #kpkg entry gets none), from the datastream's
    pkgmap.  A row an input already sized must agree."""
    g = gencat()
    for e in sorted(live.values(), key=lambda x: x.name):
        if e.kind != "row":
            continue
        p = e.path()
        try:
            if p.endswith(".Z"):
                raw = g.decompress_z(p)
            else:
                with open(p, "rb") as fp:
                    raw = fp.read()
            n = g.installed_size(g.parse_datastream(raw)[2])
        except g.Malformed as x:
            raise Refused("%s: %s" % (e.who(), x))
        if n is None:
            raise Refused("%s: no installed size: %s has no pkgmap that can be "
                          "summed" % (e.who(), e.filename))
        line = "#isize %s %d" % (e.name, n)
        if "isize" in e.ann and e.ann["isize"] != line:
            raise Refused("%s: its catalog says %r, the datastream sums to %d"
                          % (e.who(), e.ann["isize"], n))
        e.ann["isize"] = line


def render(live, older):
    rows = sorted((e for e in live.values() if e.kind == "row"), key=lambda e: e.name)
    kp = sorted((e for e in live.values() if e.kind == "kpkg"), key=lambda e: e.name)
    out = [MAGIC] + [e.line for e in rows]
    for kind in ANN:
        lines = [e.ann[kind] for e in rows + kp if kind in e.ann]
        if lines:
            out += ["#ext %s 1" % kind] + lines
    if kp:
        out += ["#ext kpkg 1"] + [e.line for e in kp] + ["#end kpkg"]
    if older:
        old = sorted(older, key=lambda e: (e.name, _vkey(e.version), e.version))
        out += ["#ext older 1"]
        for e in old:
            out.append("#old " + e.line)
            out += ["#old " + e.ann[k] for k in ANN if k in e.ann]
        out += ["#end older"]
    return ("\n".join(out) + "\n").encode("utf-8")


def _vkey(v):
    return functools.cmp_to_key(vercmp)(v)


# ---------------------------------------------------------------- checks

def run_check(argv, what, refuse_rc):
    r = subprocess.run(argv, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode in refuse_rc:
        raise Refused("%s refused the tree (exit %d)" % (what, r.returncode))
    if r.returncode != 0:
        raise ToolError("%s failed (exit %d)" % (what, r.returncode))


def m68k_elf(path):
    try:
        with open(path, "rb") as fp:
            h = fp.read(20)
    except OSError:
        return False
    return len(h) == 20 and h[:4] == b"\x7fELF" and h[5] == 2 and h[18:20] == b"\x00\x04"


def built_by_gcc14(path):
    """GCC 14's ident in the ELF's .comment: that toolchain's switch tables
    are sized by scan060-g14.py, not scan060.py (build/pkg's D4 gate)."""
    with open(path, "rb") as fp:
        d = fp.read()
    try:
        shoff = struct.unpack(">I", d[32:36])[0]
        ent, num, stx = struct.unpack(">HHH", d[46:52])
        sh = [struct.unpack(">IIIIII", d[shoff + i * ent:shoff + i * ent + 24])
              for i in range(num)]
        so = sh[stx][4]
        for nm, _t, _f, _a, off, size in sh:
            if d[so + nm:d.index(b"\0", so + nm)] == b".comment":
                return b"GCC: (GNU) 14." in d[off:off + size]
    except (struct.error, IndexError, ValueError):
        pass
    return False


def objdump_tool():
    t = os.environ.get("OBJDUMP")
    if t:
        return t
    for t in ("m68k-linux-gnu-objdump", "m68k-elf-objdump", "m68k-cbm-sysv4-objdump"):
        if shutil.which(t):
            return shutil.which(t)
    raise Missing("no m68k objdump on PATH (or OBJDUMP=)")


def scan_userland(files, a, work):
    """The 68060 scan over the ELFs of the live userland rows, by the rule
    build/pkg's D4 gate applies at roll time: a period ELF's verdict is
    scan060.py's; a GCC 14 ELF's is scan060-g14.py's, and every hit
    scan060.py reports on it must be one scan060-g14.py explains (inside a
    sized switch table, or at an odd address: scan060.py sizes tables by gcc
    2.7's layout and reads GCC 14's as code).  A package without an ELF has
    nothing to scan.  -> (period ELFs, gcc14 ELFs) counted."""
    pkgtrans = os.environ.get("AMIX_PKGTRANS") or os.path.join(
        PKGTOOLS, "heirloom", "build-host", "bin", "pkgtrans")
    if not os.access(pkgtrans, os.X_OK):
        raise Missing("pkgtrans for the scan: %s (AMIX_PKGTRANS=)" % pkgtrans)
    objdump = objdump_tool()
    period, g14 = [], []
    for i, f in enumerate(files):
        with open(f, "rb") as fp:
            head = fp.read(512).split(b"\n")
        if len(head) < 2 or not head[0].startswith(b"# PaCkAgE DaTaStReAm"):
            raise Refused("%s: not an SVR4 datastream" % os.path.basename(f))
        inst = head[1].split()[0].decode("ascii")
        d = os.path.join(work, "u%d" % i)
        os.makedirs(d)
        r = subprocess.run([pkgtrans, "-o", f, d, inst], capture_output=True, text=True)
        if r.returncode != 0:
            raise ToolError("pkgtrans %s: %s" % (os.path.basename(f), r.stderr.strip()[:200]))
        for root, dirs, names in os.walk(d):
            dirs.sort()
            for n in sorted(names):
                p = os.path.join(root, n)
                if os.path.isfile(p) and not os.path.islink(p) and m68k_elf(p):
                    (g14 if built_by_gcc14(p) else period).append(p)
    if period:
        run_check([sys.executable, "-I", a.scan060] + period, "scan060", (2,))
    if g14:
        run_check([sys.executable, "-I", a.scan060_g14, "--objdump", objdump] + g14,
                  "scan060-g14", (1, 3))
        for p in g14:
            hits = p + ".scan060"
            with open(hits, "w") as fp:
                r = subprocess.run([sys.executable, "-I", a.scan060, p], stdout=fp,
                                   stderr=subprocess.STDOUT, text=True)
            if r.returncode == 0:
                continue
            if r.returncode != 2:
                raise ToolError("scan060 failed on %s (exit %d)" % (p, r.returncode))
            run_check([sys.executable, "-I", a.scan060_g14, "--objdump", objdump,
                       "--explain", hits, p], "scan060-g14 --explain", (1, 3))
    return len(period), len(g14)


def apkg_reads(apkg_bin, tree, n_rows, n_k):
    """apkg's own parse: `update` and `list` against file://tree."""
    with tempfile.TemporaryDirectory() as d:
        conf = os.path.join(d, "apkg.conf")
        with open(conf, "w") as fp:
            fp.write("repo=file://%s\ncachedir=%s/var/apkg/cache\nadmin=%s/admin\n"
                     % (os.path.abspath(tree), d, d))
        env = dict(os.environ, APKG_ROOT=d)
        r = subprocess.run([apkg_bin, "-c", conf, "update"], capture_output=True,
                           text=True, env=env)
        want = "catalog updated: %d packages" % n_rows
        if n_k:
            want += ", %d kernel-space" % n_k
        if r.returncode != 0 or want not in r.stdout:
            raise Refused("apkg update on the tree: exit %d, wanted %r:\n%s%s"
                          % (r.returncode, want, r.stdout, r.stderr))
        r = subprocess.run([apkg_bin, "-c", conf, "list"], capture_output=True,
                           text=True, env=env)
        if r.returncode != 0:
            raise Refused("apkg list on the tree: exit %d:\n%s"
                          % (r.returncode, r.stderr))
        print("apkg reads the tree: %s" % want)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="write one release's apkg repository tree")
    ap.add_argument("--userland", required=True)
    ap.add_argument("--kspace", required=True)
    ap.add_argument("--apkg")
    ap.add_argument("--stock")
    ap.add_argument("--previous")
    ap.add_argument("--release", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--stock-lock")
    ap.add_argument("--release-check", default=os.path.join(TOP, "tools", "release-check"))
    ap.add_argument("--rom-register", default=os.environ.get("ROM_MANIFEST"))
    ap.add_argument("--private-patterns", default=os.environ.get("PRIVACY_PATTERNS"))
    ap.add_argument("--scan060", default=os.path.join(HERE, "scan060.py"))
    ap.add_argument("--scan060-g14", default=os.path.join(
        TOP, "build", "pkg", "common", "gcc14", "scan060-g14.py"))
    ap.add_argument("--apkg-bin", default=os.path.join(PKGTOOLS, "src", "apkg", "apkg"))
    a = ap.parse_args()
    if not re.match(r"^[0-9]+\.[0-9]+$", a.release):
        ap.error("--release %r is not <major>.<minor>" % a.release)
    lock = a.stock_lock or os.path.join(HERE, "stock-%s.lock" % a.release)
    out = os.path.abspath(a.out.rstrip("/"))
    tmp = out + ".tmp"
    try:
        # the check tools first: a missing one is MISSING, not a skipped check
        for what, p in (("release-check", a.release_check), ("scan060", a.scan060),
                        ("scan060-g14", a.scan060_g14), ("apkg (host build)", a.apkg_bin)):
            if not os.access(p, os.X_OK) and not (what.startswith("scan060") and os.path.isfile(p)):
                raise Missing("%s: %s" % (what, p))
        for what, p in (("rom register", a.rom_register),
                        ("private patterns", a.private_patterns)):
            if not p or not os.path.isfile(p):
                raise Missing("%s for release-check: %s" % (what, p or "not given"))

        inputs = []
        for src, d in (("userland", a.userland), ("kspace", a.kspace)):
            if not os.path.isdir(d):
                raise Missing("--%s: no directory %s" % (src, d))
            live, _ = read_catalog(d, src)
            inputs += live
        loose = []
        if a.apkg:
            loose += apkg_files(a.apkg)
        if os.path.isfile(lock) or a.stock:
            loose += stock_files(a.stock, lock)
        scratch = tempfile.mkdtemp(prefix="assemble-release.")
        try:
            if loose:
                inputs += gen_rows(loose, "apkg/stock", scratch)
            for e in inputs:
                e.verify()
            prev_live, prev_older = [], []
            if a.previous:
                if not os.path.isdir(a.previous):
                    raise Missing("--previous: no directory %s" % a.previous)
                prev_live, prev_older = read_catalog(a.previous, "previous", True)
                for e in prev_live + prev_older:
                    e.verify()
            live, older, notes = merge(inputs, prev_live, prev_older)
            size_rows(live)
            body = render(live, older)

            if os.path.lexists(tmp):
                shutil.rmtree(tmp)
            os.makedirs(os.path.join(tmp, "pkgs"))
            for e in sorted(list(live.values()) + older, key=lambda e: e.filename):
                dst = os.path.join(tmp, "pkgs", e.filename)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(e.path(), dst)
                os.chmod(dst, 0o644)
            with open(os.path.join(tmp, "catalog"), "wb") as fp:
                fp.write(body)
            with open(os.path.join(tmp, "catalog.md5"), "w") as fp:
                fp.write("%s  catalog\n" % hashlib.md5(body).hexdigest())
            for f in ("catalog", "catalog.md5"):
                os.chmod(os.path.join(tmp, f), 0o644)
            for root, dirs, files in os.walk(tmp):
                for x in dirs:
                    os.chmod(os.path.join(root, x), 0o755)
            os.chmod(tmp, 0o755)
        finally:
            shutil.rmtree(scratch, ignore_errors=True)

        n_rows = sum(1 for e in live.values() if e.kind == "row")
        n_k = len(live) - n_rows
        # scan060 over the live userland rows: stock/ is Commodore's vendor
        # code (scan060 skips it too), and the #kpkg files have kernel
        # space's own gates (a k30 object is never run on an 060).  Older
        # rows were checked when they were published.
        scan = sorted(os.path.join(tmp, "pkgs", e.filename) for e in live.values()
                      if e.kind == "row" and not e.filename.startswith("stock/"))
        if scan:
            sw = tempfile.mkdtemp(prefix="assemble-release-scan.")
            try:
                np, ng = scan_userland(scan, a, sw)
            finally:
                shutil.rmtree(sw, ignore_errors=True)
            print("68060 scan: %d package(s), %d period ELF(s), %d GCC 14 ELF(s): clean"
                  % (len(scan), np, ng))
        run_check([a.release_check, "--rom-register", a.rom_register,
                   "--private-patterns", a.private_patterns, tmp],
                  "release-check", (1,))
        apkg_reads(a.apkg_bin, tmp, n_rows, n_k)

        if os.path.lexists(out):
            same = subprocess.run(["diff", "-r", "-q", out, tmp],
                                  capture_output=True).returncode == 0
            if not same:
                raise Refused("%s exists and is not what this run writes; "
                              "remove it or name another --out" % out)
            shutil.rmtree(tmp)
        else:
            os.rename(tmp, out)
        for n in notes:
            print("note: %s" % n)
        print("release %s: %d live (%d kernel-space), %d older, catalog md5 %s"
              % (a.release, len(live), n_k, len(older), hashlib.md5(body).hexdigest()))
        return 0
    except Missing as e:
        print("[MISSING] assemble-release: %s" % e, file=sys.stderr)
        rc = 3
    except Refused as e:
        print("assemble-release: refused: %s" % e, file=sys.stderr)
        rc = 1
    except (ToolError, OSError) as e:
        print("assemble-release: %s" % e, file=sys.stderr)
        rc = 2
    if os.path.lexists(tmp):
        shutil.rmtree(tmp, ignore_errors=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
