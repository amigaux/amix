#!/usr/bin/env python3
#
# gen-install-order.py -- turn deps.conf + a selected package set into the flat
# install-order file the installer driver iterates.
#
# THE DRIVER DOES NOT RESOLVE DEPS. On the miniroot there is no apkg and no
# dependency solver; the driver just reads a text file, one package name per
# line, and runs `pkgadd -R` down the list. All the ordering intelligence lives
# HERE, host-side, at ISO-assembly time -- exactly like the catalog. This keeps
# the on-box driver tiny and keeps a single authored dependency graph
# (../amix-packagemanager/build/repo-staging/deps.conf) as the one source of
# truth for install order.
#
# RULES (fail-closed):
#   * `core` is ALWAYS first. It is the base OS and it establishes the target's
#     name service; Gate 13 (core-first-gate) refuses any other package into a
#     bare root. Refuse to emit an order whose selection lacks `core`.
#   * dependencies before dependents (topological sort of deps.conf, restricted
#     to the selected set -- deps outside the selection are dropped with a note,
#     they are simply not on this disc).
#   * deterministic: ties break by the order names were given, so the same
#     selection always yields the same file (a re-master is reproducible).
#   * a dependency CYCLE is a hard error (deps.conf is a DAG by construction).
#
# The package client rides the base set (W6.4b): APKGENG (the heirloom engine)
# and APKG (the remote client) are installed by the SAME pkgadd -R loop so an
# installed box has a working package manager out of the box. deps.conf's
# `apkg: apkgeng` edge orders APKGENG before APKG. The driver still never
# INVOKES apkg during the install -- it only transplants the package.
#
# CASE: package NAMES are emitted verbatim (case preserved). The graph is matched
# case-insensitively so the lowercase deps.conf edges apply to the uppercase base
# packages, but the emitted order keeps APKG/APKGENG uppercase and core/bsd/cdfs
# lowercase -- the case each package's SVR4 instance name and .pkg file actually use.
#
# SET NAME (W3b, optional): a medium now carries several order files -- the
# mastered default as /install/order plus one /install/order.<set> per named set
# it can satisfy in full -- so an order file that cannot say which set it IS is a
# file you have to guess about from its own filename. `--set NAME` records the
# name in the header, where every consumer already skips it: the driver and the
# interview both drop '#' lines, so this is documentation for humans and for
# `grep`, never input. It changes no emitted package line.
#
#   gen-install-order.py --deps <deps.conf> core bsd net text sysadm cdfs APKGENG APKG
#   gen-install-order.py --deps <deps.conf> --out order.txt core bsd net text sysadm
#   gen-install-order.py --deps <deps.conf> --set standard --out order.standard ...
#
# Stdlib-only python3. No proprietary bytes.

import argparse
import sys


def parse_deps(path):
    """{name: [dep, ...]} from deps.conf ('name: a,b,c' lines)."""
    deps = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                name, rhs = line.split(":", 1)
                name = name.strip().lower()
                ds = [d.strip().lower() for d in rhs.split(",") if d.strip()]
                deps[name] = ds
    except OSError as e:
        sys.exit("gen-install-order: STOP: cannot read deps.conf: %s" % e)
    return deps


def order(selected, deps):
    # Match the dependency graph case-INSENSITIVELY (deps.conf is authored in
    # lowercase, and gen-catalog.py lowercases catalog names), but PRESERVE the
    # caller's original spelling in the emitted order. The driver passes each
    # order line verbatim to `pkgadd -d <file> <NAME>`, and the SVR4 package
    # instance name is case-SENSITIVE -- our own base/ packages are uppercase
    # (APKG, APKGENG) while the stock + cdfs packages are lowercase. The driver's
    # `pkgs/{stock,base}/<NAME>-*.pkg` resolution glob is likewise case-sensitive
    # on the Rock-Ridge disc, so a lowercased "apkg" would match neither the file
    # nor the instance name. So: canonicalise to lowercase for the DAG, emit the
    # original spelling.
    sel = []            # canonical (lowercase) names -- dedup, first-seen order
    orig = {}           # canonical -> original spelling (first occurrence wins)
    seen = set()
    for n in selected:
        c = n.lower()
        if c not in seen:
            sel.append(c)
            orig[c] = n
            seen.add(c)
    selset = set(sel)

    if "core" not in selset:
        sys.exit("gen-install-order: STOP: selection has no 'core'. core is the "
                 "base OS and MUST be installed first (Gate 13); an order without "
                 "it would refuse at the first non-core pkgadd.")

    # edges restricted to the selection; note (not fail) deps outside it.
    dropped = []
    adj = {}          # name -> deps within the selection
    for n in sel:
        want = deps.get(n, [])
        inside = []
        for d in want:
            if d in selset:
                inside.append(d)
            else:
                dropped.append((n, d))
        adj[n] = inside

    # Kahn's algorithm, deterministic by input order. core is pinned first by
    # giving it an artificial precedence: it never has in-selection deps (it is
    # never a dependency and lists none), and we emit it before anything else.
    indeg = dict((n, 0) for n in sel)
    for n in sel:
        for d in adj[n]:
            indeg[n] += 1            # n depends on d => edge d->n => in-degree(n)++

    out = []
    # ready = no unsatisfied deps; process in input order, core forced ahead.
    def ready_list():
        r = [n for n in sel if indeg[n] == 0 and n not in out_set]
        # core first among the ready set
        r.sort(key=lambda n: (n != "core", sel.index(n)))
        return r

    out_set = set()
    remaining = set(sel)
    while remaining:
        r = ready_list()
        if not r:
            cyc = sorted(remaining)
            sys.exit("gen-install-order: STOP: dependency cycle among %s -- "
                     "deps.conf must be a DAG." % ", ".join(cyc))
        pick = r[0]
        out.append(pick)
        out_set.add(pick)
        remaining.discard(pick)
        for n in sel:
            if pick in adj.get(n, []) and n in remaining:
                indeg[n] -= 1

    if out[0] != "core":
        sys.exit("gen-install-order: STOP: internal -- core did not sort first "
                 "(got %r); refusing to emit a non-core-first order." % out[0])
    # emit the caller's original spelling (case-sensitive pkgadd instance names)
    return [orig[c] for c in out], dropped


def main():
    ap = argparse.ArgumentParser(description="Emit the installer's flat install-order file.")
    ap.add_argument("--deps", required=True, help="path to deps.conf")
    ap.add_argument("--out", help="write here (default: stdout)")
    ap.add_argument("--set", dest="setname",
                    help="record this set NAME in the header (documentation only)")
    ap.add_argument("names", nargs="+", help="selected package names (the disc's set)")
    args = ap.parse_args()

    deps = parse_deps(args.deps)
    seq, dropped = order(args.names, deps)

    header = [
        "# amix-installng install order (generated from deps.conf)",
        "# one package per line, install top-to-bottom; core first (Gate 13).",
        "# The driver reads this verbatim and runs `pkgadd -R` down the list;",
        "# it does NOT resolve dependencies.",
    ]
    if args.setname:
        header.append("# set: %s (%d package(s))" % (args.setname, len(seq)))
    if dropped:
        header.append("# deps outside this disc's selection (dropped, not on disc):")
        for n, d in dropped:
            header.append("#   %s needs %s" % (n, d))
    body = "\n".join(header + seq) + "\n"

    if args.out:
        with open(args.out, "w") as fh:
            fh.write(body)
        sys.stderr.write("gen-install-order: wrote %s (%d packages: %s)\n"
                         % (args.out, len(seq), " ".join(seq)))
    else:
        sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
