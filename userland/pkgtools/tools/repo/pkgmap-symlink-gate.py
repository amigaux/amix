#!/usr/bin/env python3
"""pkgmap-symlink-gate.py - fail-closed gate on the link entries of a pkgmap.

Copyright (c) 2026 Jussi Alanärä.  MIT license.

Usage:  pkgmap-symlink-gate.py <pkgmap> [<pkgmap> ...]
        pkgmap-symlink-gate.py --pkg <datastream.pkg> [...]

Exit 0 = every link entry is well formed; exit 1 = at least one is not
(with the offending line printed).  build-packages.sh runs this on the
pkgmap pkgmk produces, for every package it mints.

WHY THIS EXISTS
---------------
APKG 0.2 declared its PATH shim as

    s none /usr/bin/apkg=../apkg/bin/apkg

which is the form the SVR4 spec blesses and which our own heirloom
pkgadd handles correctly (verified host-side: it creates
`/usr/bin/apkg -> ../apkg/bin/apkg`, resolving to /usr/apkg/bin/apkg).

On the metal it still broke.  /usr/apkg/bin is deliberately NOT on the
default PATH, so the pkgadd an operator actually types is the STOCK 1991
/usr/sbin/pkgadd -- and that one prefixed the basedir onto the link
SOURCE as well as onto the destination, producing

    /usr/bin/apkg -> /../apkg/bin/apkg        (i.e. /apkg/bin/apkg)

so `apkg` was "not found" immediately after a successful install
(metal, A4000D/68LC060, 2026-09-16).  A relative target is
therefore not portable across the two engines that will both be used on
these boxes; an absolute one is, and it is what stock core's own pkgmap
uses (`s none /usr/bin/uname=/sbin/uname`).

THE RULES ENFORCED
------------------
For every `s` (symlink) and `l` (hard link) entry:

  1. The entry must have a `path=target` source at all.
  2. The target must be ABSOLUTE.  This is the rule the pre-fix APKG 0.2
     pkgmap fails, and the reason the gate exists.
  3. The target, normalised, must not escape the root (no leading `..`).
  4. The target must resolve to a path THIS package declares -- a link
     that points at something the package does not ship is either a typo
     or an undeclared dependency on another package's layout.

Rule 4 is checked against the package's own pkgmap only, so it is
deliberately strict: if a package ever needs to link into another
package's tree, that is a decision to make explicitly, not by accident.
"""

import os
import posixpath
import subprocess
import sys
import tempfile

LINK_FTYPES = ("s", "l")
# ftypes that put a real object at ept.path
PATH_FTYPES = ("f", "d", "e", "v", "x", "c", "b", "p", "s", "l")


def parse_pkgmap(path):
    """-> (entries, declared_paths).

    entries: list of (lineno, ftype, path, target_or_None, rawline)
    declared_paths: set of every path the package places on the system
    """
    entries = []
    declared = set()
    with open(path, "r", encoding="utf-8", errors="replace") as fp:
        for lineno, raw in enumerate(fp, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#") or line.startswith(":"):
                continue
            fields = line.split()
            if len(fields) < 3:
                continue
            # "<volno> <ftype> <class> <path>[=<target>] ..."
            ftype = fields[1]
            if ftype == "i":
                continue
            if len(fields) < 4:
                continue
            spec = fields[3]
            if "=" in spec:
                objpath, target = spec.split("=", 1)
            else:
                objpath, target = spec, None
            if ftype in PATH_FTYPES:
                declared.add(posixpath.normpath(objpath))
            entries.append((lineno, ftype, objpath, target, line))
    return entries, declared


def check_pkgmap(path):
    entries, declared = parse_pkgmap(path)
    problems = []
    nlinks = 0

    for lineno, ftype, objpath, target, line in entries:
        if ftype not in LINK_FTYPES:
            continue
        nlinks += 1
        what = "symlink" if ftype == "s" else "hard link"

        if target is None or target == "":
            problems.append(
                "%s:%d: %s %s has no target (expected 'path=target')"
                % (path, lineno, what, objpath))
            continue

        if not target.startswith("/"):
            resolved = posixpath.normpath(
                posixpath.join(posixpath.dirname(objpath), target))
            problems.append(
                "%s:%d: %s %s -> %s is RELATIVE; use the absolute %s.\n"
                "        The stock Amix pkgadd prefixes the basedir onto a "
                "relative link source too,\n"
                "        so this one lands as /%s -- proven on metal "
                "2026-09-16."
                % (path, lineno, what, objpath, target, resolved, target))
            continue

        resolved = posixpath.normpath(target)
        if resolved.startswith("/.."):
            problems.append(
                "%s:%d: %s target %r escapes the root (resolves to %r)"
                % (path, lineno, what, target, resolved))
            continue

        if resolved not in declared:
            problems.append(
                "%s:%d: %s %s -> %s: target is not a path this package "
                "declares" % (path, lineno, what, objpath, resolved))

    return nlinks, problems


def pkgmap_from_datastream(pkgfile, workdir):
    """Extract <PKG>/pkgmap out of a .pkg datastream; returns its path."""
    body = os.path.join(workdir, "body.cpio")
    with open(pkgfile, "rb") as src, open(body, "wb") as dst:
        src.seek(512)
        dst.write(src.read())
    subprocess.run(["cpio", "-idm", "--quiet", "--no-absolute-filenames"],
                   cwd=workdir, stdin=open(body, "rb"),
                   stderr=subprocess.DEVNULL, check=False)
    for root, _dirs, files in os.walk(workdir):
        if "pkgmap" in files:
            return os.path.join(root, "pkgmap")
    raise SystemExit("FATAL: no pkgmap inside %s" % pkgfile)


def main(argv):
    args = argv[1:]
    from_pkg = False
    if args and args[0] == "--pkg":
        from_pkg = True
        args = args[1:]
    if not args:
        sys.stderr.write(__doc__.split("\n\n", 1)[0] + "\n")
        sys.stderr.write("usage: pkgmap-symlink-gate.py [--pkg] <file>...\n")
        return 2

    failed = False
    for arg in args:
        if from_pkg:
            with tempfile.TemporaryDirectory() as tmp:
                pkgmap = pkgmap_from_datastream(arg, tmp)
                nlinks, problems = check_pkgmap(pkgmap)
                label = arg
        else:
            nlinks, problems = check_pkgmap(arg)
            label = arg
        if problems:
            failed = True
            for p in problems:
                sys.stderr.write("LINK GATE FAIL: %s\n" % p)
        else:
            print("link gate OK: %s (%d link entr%s checked)"
                  % (label, nlinks, "y" if nlinks == 1 else "ies"))
    if failed:
        sys.stderr.write("FATAL: pkgmap link gate failed\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
