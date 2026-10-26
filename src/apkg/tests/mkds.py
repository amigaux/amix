#!/usr/bin/env python3
# mkds.py - write a test datastream: a real SVR4 header, a real newc cpio
# first archive (<PKG>/pkginfo + <PKG>/pkgmap), then the plain-text install
# directives the pkgadd shims of run-tests.sh / kbootset-consumer.sh act on.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# usage: mkds.py <out> <PKGINST> <VERSION>    directives on stdin:
#   DIR <path>                 pkgmap "1 d none <path> 0755 root sys"
#   FILE <path> <word>         pkgmap "1 f none <path> ..." (shim writes <word>)
#   SHARED <path> <word>       as FILE; the shim also names OTHERPKG first
#   COPY <path> <hostfile>     as FILE; the shim copies <hostfile>
#   CDEV <path> <maj> <min>    pkgmap "1 c none <path> <maj> <min> 0644 root
#                              root" (the shim makes the node, or a stand-in)
#   PKGMAP <pkgmap line>       an extra pkgmap line, verbatim (no directive)
# A second archive carries the payload as pkgtrans lays it out (pkginfo,
# pkgmap, then root/<path> for every DIR/FILE/SHARED/COPY), so
# gen-catalog.py can read a kernel package's sidecar out of it.  The
# directives stay in the file after the archives (the shims read them with
# sed); apkg and gen-catalog read the header and the cpio archives.
import sys

def newc(name, data):
    name_b = name.encode() + b"\0"
    hdr = "070701" + "%08X" * 13 % (0, 0o100644, 0, 0, 1, 0, len(data),
                                     0, 0, 0, 0, len(name_b), 0)
    out = hdr.encode() + name_b
    out += b"\0" * ((4 - len(out) % 4) % 4)
    out += data
    out += b"\0" * ((4 - len(out) % 4) % 4)
    return out

out, pkg, ver = sys.argv[1:4]
directives = sys.stdin.read().splitlines()
pkginfo = ("PKG=%s\nNAME=test %s\nVERSION=%s\nARCH=m68k\nCATEGORY=system\n"
           "CLASSES=none\n" % (pkg, pkg, ver)).encode()
pm = [": 1 20"]
for d in directives:
    t = d.split(None, 2)
    if not t:
        continue
    if t[0] == "DIR":
        pm.append("1 d none %s 0755 root sys" % t[1])
    elif t[0] in ("FILE", "SHARED", "COPY"):
        pm.append("1 f none %s 0644 root sys 1 1 1" % t[1])
    elif t[0] == "CDEV":
        pm.append("1 c none %s %s 0644 root root" % (t[1], t[2]))
    elif t[0] == "PKGMAP":
        pm.append(d.split(None, 1)[1])
pm.append("1 i pkginfo %d 1 1" % len(pkginfo))
pkgmap = ("\n".join(pm) + "\n").encode()
hdr = b"# PaCkAgE DaTaStReAm\n%s 1 20\n# end of header\n" % pkg.encode()
hdr += b"\0" * ((512 - len(hdr) % 512) % 512)
arc = newc(pkg + "/pkginfo", pkginfo) + newc(pkg + "/pkgmap", pkgmap) \
    + newc("TRAILER!!!", b"")
arc += b"\0" * ((512 - len(arc) % 512) % 512)
pay = newc("pkginfo", pkginfo) + newc("pkgmap", pkgmap) + newc("root", b"")
for d in directives:
    t = d.split(None, 2)
    if not t or t[0] in ("PKGMAP", "CDEV"):
        continue
    if t[0] == "DIR":
        pay += newc("root" + t[1], b"")
    elif t[0] == "COPY":
        pay += newc("root" + t[1], open(t[2], "rb").read())
    elif t[0] in ("FILE", "SHARED"):
        pay += newc("root" + t[1], (t[2] + "\n").encode())
pay += newc("TRAILER!!!", b"")
pay += b"\0" * ((512 - len(pay) % 512) % 512)
arc += pay
body = ("VERSION %s\n" % ver + "\n".join(directives) + "\n").encode()
with open(out, "wb") as fp:
    fp.write(hdr + arc + b"\n" + body)
