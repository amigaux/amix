#!/usr/bin/env python3
"""check.py -- judge what box.sh found.

    python3 check.py <pulled dir> <archives dir>

<pulled dir> holds box.log, the t-*.tf/.tvf listings and the c-*.tar
archives box.sh wrote; <archives dir> is make-archives.sh's output (expect).
Prints RES ok/FAIL lines (and NOTE lines for what stock tar did, which is
recorded, not judged) and exits 1 on any FAIL.  MIT, this repository.
"""
import os
import re
import sys
import tarfile

P, A = sys.argv[1], sys.argv[2]
log = open(os.path.join(P, "box.log"), errors="replace").read().splitlines()
expect = {}
for line in open(os.path.join(A, "expect")):
    f, s = line.split()
    expect[f] = s
fails = 0


def res(ok, what):
    global fails
    print(("RES ok   " if ok else "RES FAIL ") + what)
    if not ok:
        fails += 1


def ids(prefix, name):
    for line in log:
        if line.startswith("== " + prefix + " "):
            for ent in line.split()[2:]:
                parts = ent.split(":")
                if parts[0] == name:
                    return parts[1:]
    return None


bin_uid, bin_gid = ids("passwd", "bin")
root_uid, root_gid = ids("passwd", "root")
bin_grp = ids("group", "bin")[0]
sys_grp = ids("group", "sys")[0]
res(ids("passwd", "jdoe") is None and ids("group", "users") is None,
    "the box has no user jdoe and no group users")
OWN = {
    "v7": ("0", sys_grp),
    "ustar-named": (bin_uid, bin_grp), "gnu-named": (bin_uid, bin_grp),
    "pax": (bin_uid, bin_grp),
    "ustar-absent": ("1234", "5678"), "gnu-absent": ("1234", "5678"),
    "ustar-empty": ("1234", "5678"), "gnu-empty": ("1234", "5678"),
}
MODES = {"./hello": "-rw-r--r--", "./d/b511": "-rw-------"}
LONG = [f for f in expect if len(f) > 100]

X, S, O, L = {}, {}, {}, {}
for line in log:
    w = line.split()
    if not w:
        continue
    if w[0] == "X" and len(w) >= 3:
        X[(w[1], w[2])] = line
    elif w[0] == "S":
        S.setdefault((w[1], w[2]), []).append(w[3:])
    elif w[0] == "O":
        O[(w[1], w[2], w[3])] = w[4:]
    elif w[0] == "L":
        L[(w[1], w[2])] = line


def field(line, key):
    m = re.search(r"\b" + key + r"= *(\S*)", line or "")
    return m.group(1) if m else None


def judge_extract(label, arch, own=None, strict=True):
    """strict: judge; else only describe (stock tar)."""
    x = X.get((label, arch))
    if x is None:
        res(False, "%s %s: no extraction line" % (label, arch))
        return
    rc, core = field(x, "rc"), field(x, "core")
    bad = []
    for f, *rest in S.get((label, arch), []):
        if rest == ["missing"]:
            if not (arch == "v7" and f in LONG) and not arch.startswith("from") or \
                    (arch.startswith("from") and f not in LONG):
                bad.append(f + " missing")
            continue
        s, mode, uid, gid = rest
        if int(s) != int(expect[f]):
            bad.append("%s sum %s != %s" % (f, s, expect[f]))
        if own and (uid, gid) != own:
            bad.append("%s owner %s/%s != %s/%s" % (f, uid, gid, own[0], own[1]))
        if f in MODES and mode != MODES[f]:
            bad.append("%s mode %s" % (f, mode))
    if own:
        for d in (".", "d", "d/sub", "empty"):
            o = O.get((label, arch, d))
            if o and tuple(o[1:3]) != own:
                bad.append("dir %s owner %s/%s" % (d, o[1], o[2]))
        o = O.get((label, arch, "d/sub"))
        if o and o[0] != "drwxr-x---":
            bad.append("d/sub mode %s" % o[0])
    lk = L.get((label, arch), "")
    if field(lk, "symlink") != "hello":
        bad.append("symlink: %s" % field(lk, "symlink"))
    if "links=2 2" not in lk:
        bad.append("hard link: %s" % lk)
    desc = "%s %s: rc=%s core=%s files=%s" % (label, arch, rc, core, field(x, "files"))
    if strict:
        res(rc == "0" and core == "no" and not bad,
            desc + ("" if not bad else "; " + "; ".join(bad[:4])))
    else:
        print("NOTE " + desc + ("" if not bad else "; " + "; ".join(bad[:3])) +
              " | " + x.split("last=", 1)[-1][:90])


print("== stock /usr/sbin/tar (recorded)")
for a in OWN:
    judge_extract("stock", a, OWN[a], strict=False)
print("== heirloom /usr/sbin/tar")
for a in OWN:
    judge_extract("heir", a, OWN[a])
x = X.get(("heir-o", "gnu-absent"), "")
res(field(x, "rc") == "0" and x.endswith("own=%s %s" % (root_uid, root_gid)),
    "xof as root: owner is root (%s)" % x.split("own=")[-1])
x = X.get(("heir-u", "gnu-absent"), "")
res(field(x, "rc") == "0" and x.endswith("own=%s %s" % (bin_uid, bin_gid)),
    "xf as user bin: owner is bin (%s)" % x.split("own=")[-1])
judge_extract("heir", "fromstock", None)
judge_extract("stock", "fromheir", None)

# listings: heir's tf names every member (as Python's tarfile reads the
# archive); stock's is recorded where it differs; tvf samples
def tfnames(text):
    out = []
    for x in text.splitlines():
        x = re.sub(r" (linked to|symbolic link to) .*$", "", x)
        out.append(x.rstrip("/") or ".")
    return out


for a in OWN:
    try:
        st = open(os.path.join(P, "t-stock-%s.tf" % a), errors="replace").read()
        he = open(os.path.join(P, "t-heir-%s.tf" % a), errors="replace").read()
    except OSError as e:
        res(False, "tf %s: %s" % (a, e))
        continue
    with tarfile.open(os.path.join(A, a + ".tar")) as t:
        want = [m.name.rstrip("/") for m in t.getmembers()]
    res(tfnames(he) == want, "tf %s: heir names all %d members" % (a, len(want)))
    if st != he:
        d = [x for x in st.splitlines() if x not in he.splitlines()]
        print("NOTE tf %s: stock differs: %r" % (a, d[:2]))
for a in ("v7", "ustar-named", "gnu-empty"):
    try:
        st = open(os.path.join(P, "t-stock-%s.tvf" % a), errors="replace").read().splitlines()
        he = open(os.path.join(P, "t-heir-%s.tvf" % a), errors="replace").read().splitlines()
    except OSError:
        continue
    print("NOTE tvf %s: stock %r" % (a, st[1] if len(st) > 1 else st))
    print("NOTE tvf %s: heir  %r" % (a, he[1] if len(he) > 1 else he))

# what each tar writes: every header field, and the size against the data
HF = [("name", 0, 100), ("mode", 100, 8), ("uid", 108, 8), ("gid", 116, 8),
      ("size", 124, 12), ("mtime", 136, 12), ("chksum", 148, 8), ("type", 156, 1),
      ("linkname", 157, 100), ("magic", 257, 6), ("version", 263, 2),
      ("uname", 265, 32), ("gname", 297, 32), ("devmajor", 329, 8),
      ("devminor", 337, 8), ("prefix", 345, 155)]


def headers(path):
    out = []
    data = open(path, "rb").read()
    off = 0
    while off + 512 <= len(data):
        h = data[off:off + 512]
        if h == b"\0" * 512:
            break
        rec = {k: h[o:o + n] for k, o, n in HF}
        try:
            sz = int(rec["size"].strip(b"\0 ") or b"0", 8)
        except ValueError:
            # not octal: the size field is garbage, or this is not a header
            out.append({"_bad": off, "name": rec["name"], "size": rec["size"]})
            break
        rec["_off"] = off
        out.append(rec)
        typ = rec["type"]
        off += 512 + (0 if typ in (b"1", b"2", b"5") else (sz + 511) // 512 * 512)
    return out


def tarmembers(path):
    try:
        with tarfile.open(path) as t:
            ms = t.getmembers()
            d = {m.name.lstrip("./"): m.size for m in ms if m.isfile()}
            # a hard link member counts with its target's size
            for m in ms:
                if m.islnk():
                    d[m.name.lstrip("./")] = d.get(m.linkname.lstrip("./"))
            return d
    except Exception as e:
        return str(e)


sizes = {f.lstrip("./"): os.path.getsize(os.path.join(A, "src", f)) for f in expect}
for w in ("stock", "heir", "no03"):
    p = os.path.join(P, "cv-%s.tar" % w)
    if not os.path.exists(p):
        continue
    hs = headers(p)
    bad = [h for h in hs if "_bad" in h]
    got = {h["name"].rstrip(b"\0").decode(errors="replace").lstrip("./"):
           int(h["size"].strip(b"\0 ") or b"0", 8) for h in hs if "_bad" not in h}
    if bad:
        got[bad[0]["name"].rstrip(b"\0").decode(errors="replace").lstrip("./")] = \
            "unreadable %r" % bad[0]["size"]
    ok = all(got.get(f) == sizes[f] for f in ("hello", "d/m6"))
    line = "%s writes hello %s, d/m6 %s bytes (really %d, %d)" % (
        w, got.get("hello"), got.get("d/m6"), sizes["hello"], sizes["d/m6"])
    if w == "no03":
        print("NOTE without patch 03: " + line)
    else:
        res(ok, line)
cs, ch = os.path.join(P, "c-stock.tar"), os.path.join(P, "c-heir.tar")
if os.path.exists(cs) and os.path.exists(ch):
    ms, mh = tarmembers(cs), tarmembers(ch)
    wrong = mh if not isinstance(mh, dict) else \
        [f for f in expect if mh.get(f.lstrip("./")) != sizes[f.lstrip("./")]]
    res(not wrong, "heir's tar c is read back by Python's tarfile with every size right"
        + ("" if not wrong else ": %r" % (wrong[:3],)))
    hs, hh = headers(cs), headers(ch)
    print("NOTE tar c: stock %d headers, %d bytes; heir %d headers, %d bytes" % (
        len(hs), os.path.getsize(cs), len(hh), os.path.getsize(ch)))
    byname = {h["name"]: h for h in hs}
    diffs = {}
    for h in hh:
        s = byname.get(h["name"])
        if s is None:
            diffs.setdefault("only in heir", []).append(h["name"].rstrip(b"\0"))
            continue
        for k, _, _ in HF:
            if s[k] != h[k]:
                diffs.setdefault(k, []).append((h["name"].rstrip(b"\0")[:40], s[k].rstrip(b"\0"),
                                               h[k].rstrip(b"\0")))
    for h in hs:
        if h["name"] not in {x["name"] for x in hh}:
            diffs.setdefault("only in stock", []).append(h["name"].rstrip(b"\0"))
    for k, v in diffs.items():
        print("DIFF tar c %s (%d): %r" % (k, len(v), v[:2]))

for key in ("RES pkgadd", "RES pkgchk"):
    l = [x for x in log if x.startswith(key)]
    res(bool(l) and l[0].endswith("rc=0"), l[0] if l else key + ": missing")
# removal: apkg must refuse (essential); then the plain pkgrm removes it.
# An apkg that removes it anyway is recorded, and its removal is judged.
ar = [x for x in log if x.startswith("D apkg remove")]
pr = [x for x in log if x.startswith("RES pkgrm")]
if ar and field(ar[0], "rc") == "5":
    res(True, "apkg refuses to remove heirtar: " + ar[0].split("rc=5", 1)[1].strip()[:70])
    res(bool(pr) and pr[0].endswith("rc=0"), pr[0] if pr else "RES pkgrm: missing")
elif ar and field(ar[0], "rc") == "0":
    print("NOTE apkg on this box removed heirtar (no essential refusal); pkgrm then: %s"
          % (pr[0] if pr else "missing"))
    try:
        al = open(os.path.join(P, "apkg-rm.log"), errors="replace").read()
    except OSError:
        al = ""
    res("Removal of <heirtar> was successful." in al and
        "pkgrm: ERROR: no package associated with <heirtar>" in log,
        "apkg's removal succeeded, and pkgrm finds no heirtar after it")
else:
    res(bool(pr) and pr[0].endswith("rc=0"), pr[0] if pr else "RES pkgrm: missing")
sums = [x for x in log if x.startswith("SUM /usr/sbin/tar")]
if len(sums) == 3:
    res(sums[1] != sums[0], "pkgadd replaced /usr/sbin/tar (%s -> %s)" % (sums[0][18:], sums[1][18:]))
    res(sums[2] == sums[1] != sums[0], "after pkgrm /usr/sbin/tar is still Heirloom's (%s)" % sums[2][18:])
# pkgchk -l after pkgadd: /usr/sbin/tar referenced by core and heirtar
ph2 = log[log.index("== 2 pkgadd"):] if "== 2 pkgadd" in log else []
refs = []
for i, x in enumerate(ph2):
    if x.startswith("Pathname: /usr/sbin/tar"):
        j = next((k for k in range(i, len(ph2)) if ph2[k].startswith("Referenced by")), None)
        if j is not None:
            refs = ph2[j + 1].split()
        break
if not any(x.startswith("Pathname:") for x in ph2):
    print("NOTE pkgchk -l -p printed nothing on this box")
else:
    res("heirtar" in refs and "core" in refs,
        "pkgchk -l: /usr/sbin/tar is referenced by %s" % " ".join(refs))
g = [x for x in log if x.startswith("G ")]
if any(x.startswith("== 5 grep") for x in log):
    print("NOTE grep: %d lines name tar in scripts" % len(g))
    for x in g:
        print("  " + x[2:][:160])
sys.exit(1 if fails else 0)
