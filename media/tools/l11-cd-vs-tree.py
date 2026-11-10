#!/usr/bin/env python3
"""l11-cd-vs-tree.py EXTRACTED-CD REPO-TREE -- every package datastream on the install CD against the repository
tree's: identical, different or missing, by package instance and sha256. Exit 0 every package on the CD is in the tree byte for byte, 1 otherwise,
2 it could not look: no package found on the CD or in the tree.
"""
import hashlib, os, sys
if len(sys.argv) != 3:
    sys.exit(__doc__)
X, T = sys.argv[1], sys.argv[2]
def inst(p):
    with open(p, "rb") as f:
        h = f.read(4096).decode("latin-1").splitlines()
    i = h.index("# PaCkAgE DaTaStReAm") if "# PaCkAgE DaTaStReAm" in h else -1
    return h[i + 1].split()[0] if i >= 0 else "?"
def scan(root):
    out = {}
    for r, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(".pkg"):
                p = os.path.join(r, f)
                out[p] = (hashlib.md5(open(p, "rb").read()).hexdigest(), inst(p), os.path.relpath(p, root))
    return out
cd, tree = scan(X), scan(os.path.join(T, "pkgs"))
if not cd or not tree:
    print("l11-cd-vs-tree: STOP, could not look: %d packages under %s, %d under %s/pkgs" % (len(cd), X, len(tree), T))
    sys.exit(2)
tmd5 = {v[0]: v for v in tree.values()}
tinst = {}
for v in tree.values():
    tinst.setdefault(v[1], []).append(v)
cmd5 = {v[0] for v in cd.values()}
cinst = {v[1] for v in cd.values()}
print("== on the CD (%d), against the tree" % len(cd))
same = diff = miss = 0
for p, (m, i, rel) in sorted(cd.items(), key=lambda kv: kv[1][2]):
    if m in tmd5:
        same += 1; continue
    if i in tinst:
        diff += 1; print("  DIFFERENT BYTES  %-10s CD %s  tree %s" % (i, rel, " ".join(v[2] for v in tinst[i])))
    else:
        miss += 1; print("  MISSING          %-10s CD %s (md5 %s)" % (i, rel, m))
print("  identical in the tree: %d, different bytes: %d, missing: %d" % (same, diff, miss))
print("== in the tree (%d), against the CD" % len(tree))
for p, (m, i, rel) in sorted(tree.items(), key=lambda kv: kv[1][2]):
    if m not in cmd5:
        print("  %-14s %-10s %s" % ("NOT ON THE CD" if i not in cinst else "OTHER VERSION", i, rel))
sys.exit(1 if diff or miss else 0)
