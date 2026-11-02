#!/usr/bin/env python3
# notices.py XC -- the COPYRIGHT file of the x11r63 package, from the built tree XC.
#
# The notices the package's programs and libraries carry: every copyright and
# permission comment in a C source that was compiled (a .c beside a .o under XC),
# grouped by permission text with their copyright lines, and the COPYRIGHT and
# NOTICE properties of the bitmap fonts the package ships.  Deterministic: the
# order is that of the sorted source paths.  Python 3 standard library only.
#
# MIT licence, see LICENSE in userland/packages.

import collections
import os
import re
import sys

FONT_DIRS = ("misc", "75dpi", "100dpi")    # fonts/bdf/<dir>, as the package ships

HEAD = """X11R6.3 for Amix (the x11r63 package): copyright notices

The package is X11R6.3 from the X Consortium, with an Amiga X server and
changes for Amix.  Its parts and their terms:

- the package's own changes and files (the recipe, patches 01 onwards):
  MIT, see LICENSE in this directory;
- the Amiga X server of patch 00 (hw/amix with its rtg/zz9000 driver, and
  the mfbimage.c change), as published by Ignacio Soriano under MIT: its
  rtg/ layer and ZZ9000 driver are based on Antti Sokero's xrtg-amix (MIT),
  and it carries Z3660 changes from amix-z3660rtg (MIT); LICENSE.ddx has
  those notices and says which part each covers.  Its hw/amix input code
  derives from the 1987 Sun X server through Commodore's Amix server and
  carries their notices, listed below;
- X11R6.3 itself: the notices below, from every source file compiled into
  the package's programs and libraries.  The installed headers carry their
  own notices.  The X Consortium's is the first.

Each notice below is the copyright lines of its holders followed by the
permission text they share.
"""


def comment_notices(path):
    """The comments of a source file that hold a copyright and a grant."""
    try:
        text = open(path, encoding="latin-1").read()
    except OSError:
        return
    for m in re.finditer(r"/\*(.*?)\*/", text, re.S):
        body = m.group(1)
        if not re.search(r"copyright", body, re.I):
            continue
        if not re.search(r"permission|redistribut|licen[cs]e|granted", body, re.I):
            continue
        yield clean(body)


def clean(body):
    """Comment decoration off: leading and trailing stars, bars, rules."""
    out = []
    for line in body.split("\n"):
        line = re.sub(r"^[\s*#|]+", "", line)
        line = re.sub(r"[\s*#|]+$", "", line)
        line = re.sub(r"\s\*\s", " ", line)
        if re.fullmatch(r"[-=*_~+ ]*", line):
            line = ""
        out.append(line)
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip("\n")


def is_copyright(line):
    return bool(re.match(r"(Portions )?(Copyright|COPYRIGHT|\([cC]\))", line) or
                re.match(r"All Rights Reserved", line, re.I))


def key(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def sources(xc):
    found = []
    for root, dirs, files in os.walk(xc):
        if root == xc and "config" in dirs:
            dirs.remove("config")       # imake and the other host tools
        dirs.sort()
        for f in sorted(files):
            if f.endswith(".o"):
                c = os.path.join(root, f[:-2] + ".c")
                if os.path.exists(c):
                    found.append(c)
    return sorted(set(os.path.realpath(c) for c in found))


def font_notices(xc):
    seen = collections.OrderedDict()
    for d in FONT_DIRS:
        bdf = os.path.join(xc, "fonts", "bdf", d)
        if not os.path.isdir(bdf):
            continue
        for f in sorted(os.listdir(bdf)):
            if not f.endswith(".bdf"):
                continue
            props = []
            for line in open(os.path.join(bdf, f), encoding="latin-1"):
                if line.startswith(("COPYRIGHT ", "NOTICE ")):
                    props.append(line.split(" ", 1)[1].strip().strip('"'))
                elif line.startswith("ENDPROPERTIES"):
                    break
            if props:
                text = "\n".join(props)
                seen.setdefault(key(text), [text, 0])[1] += 1
    return list(seen.values())


def main():
    xc = sys.argv[1]
    groups = collections.OrderedDict()
    whole = set()
    for path in sources(xc):
        for notice in comment_notices(path):
            k = key(notice)
            if k in whole:
                continue
            whole.add(k)
            lines = notice.split("\n")
            holders = [l for l in lines if is_copyright(l)]
            grant = "\n".join(l for l in lines if not is_copyright(l)).strip("\n")
            g = groups.setdefault(key(grant), [grant, []])
            for h in holders:
                if h not in g[1]:
                    g[1].append(h)

    # the X Consortium's grant first, then in order of first appearance
    order = sorted(groups.values(),
                   key=lambda g: 0 if any("X Consortium" in h for h in g[1]) else 1)
    out = [HEAD]
    out.append("=" * 72 + "\nX11R6.3 SOURCES\n")
    for grant, holders in order:
        out.append("-" * 72)
        out.extend(holders)
        if holders and grant:
            out.append("")
        if grant:
            out.append(grant)
        out.append("")
    out.append("=" * 72 + "\nBITMAP FONTS (misc, 75dpi, 100dpi)\n")
    out.append("Each font carries these as its COPYRIGHT and NOTICE properties.\n")
    for text, n in font_notices(xc):
        out.append("-" * 72)
        out.append("%s\n(%d font%s)" % (text, n, "" if n == 1 else "s"))
        out.append("")
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()
