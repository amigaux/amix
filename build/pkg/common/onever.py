#!/usr/bin/env python3
"""onever.py -- one version, one set of bytes (the check behind onever.sh).

    python3 -I onever.py <datastream> <pkginst> <version> [<root>...]

Looks <pkginst> <version> up in every <root>/catalog: an ordinary row
(name|version|pkginst|file|md5|size|...) or a kernel-space row (#kpkg <name>
<version> ... size= sha256= file= pkginst=).  Where a root lists it, the
datastream must be that row's bytes (size and md5 or sha256).

Exit 0: no root lists it (a new version), or every root that lists it has
these very bytes (a byte-identical rebuild).  Exit 1: some root lists it with
other bytes -- refused.  Exit 2: usage or an unreadable file.
"""
import hashlib
import os
import sys


def rows(catalog, pkginst, version):
    """(kind, size, hash) for each row of <catalog> naming pkginst+version"""
    out = []
    with open(catalog, encoding="latin-1") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("#kpkg "):
                t = line.split()
                kv = dict(x.split("=", 1) for x in t[3:] if "=" in x)
                if len(t) > 2 and t[2] == version and kv.get("pkginst") == pkginst:
                    out.append(("sha256", kv.get("size"), kv.get("sha256"), kv.get("file")))
            elif line and not line.startswith("#"):
                c = line.split("|")
                if len(c) >= 6 and c[1] == version and c[2] == pkginst:
                    out.append(("md5", c[5], c[4], c[3]))
    return out


def main(argv):
    if len(argv) < 3:
        print("usage: onever.py <datastream> <pkginst> <version> [<root>...]", file=sys.stderr)
        return 2
    ds, pkginst, version, roots = argv[0], argv[1], argv[2], argv[3:]
    try:
        data = open(ds, "rb").read()
    except OSError as e:
        print("onever: %s" % e, file=sys.stderr)
        return 2
    have = {"md5": hashlib.md5(data).hexdigest(), "sha256": hashlib.sha256(data).hexdigest()}
    size = str(len(data))
    same, other = [], []
    for root in roots:
        cat = os.path.join(root, "catalog")
        if not os.path.isfile(cat):
            continue
        with open(cat, "rb") as f:
            cmd5 = hashlib.md5(f.read()).hexdigest()[:8]
        for kind, rsize, rhash, rfile in rows(cat, pkginst, version):
            where = "%s (catalog %s, %s)" % (root, cmd5, rfile)
            if rsize == size and rhash == have[kind]:
                same.append(where)
            else:
                other.append("%s: %s bytes, %s %s" % (where, rsize, kind, (rhash or "?")[:16]))
    if other:
        print("one-version: %s %s is already listed with other bytes:" % (pkginst, version))
        for w in other:
            print("    " + w)
        print("  this roll: %s bytes, md5 %s, sha256 %s" % (size, have["md5"][:16], have["sha256"][:16]))
        print("  one version, one set of bytes: a changed package takes a new version")
        return 1
    if same:
        print("one-version: %s %s is byte-identical to the listed datastream in %d root(s) "
              "(%s): allowed, an identical rebuild" % (pkginst, version, len(same), "; ".join(same)))
    else:
        print("one-version: %s %s is listed in no root: a new version" % (pkginst, version))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
