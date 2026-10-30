#!/usr/bin/env python3
# s5-collision-scan.py -- find the objects a package set cannot lay down on a
# 14-character (System V s5) filesystem.  Host-side tool (Linux, python3
# stdlib only).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# WHY THIS EXISTS.  Amix's root filesystem is s5, which truncates every
# directory-entry name to 14 bytes on create AND on lookup.  Two paths in the
# same directory whose first 14 basename characters agree are therefore ONE
# dirent on the box: the second install overwrites the first, pkgadd's
# size/cksum verification fails against the first one's pkgmap line, and the
# package reports "partially failed".  That is what happened to `gnusrc2` on
# the amix-installng W6 cd-full run.
#
# The measurement and the decision it feeds are in
# ../../docs/s5-14char-collisions.md.  W6's own scan was prose only and had a
# DEFECT this tool exists to not repeat: it keyed collision groups on the
# truncated BASENAME ALONE, so two directories that each hold the same
# aliasing pair collapsed into one row -- it reported 3 groups where there are
# 5, and the fix is per-path.  A collision is a property of a DIRECTORY, so the
# key here is (dirname, basename[:14]).
#
# WHAT IT READS.  Published SVR4 datastream packages (*.pkg / *.pkg.Z): only
# their pkgmaps, so a scan is host-side, needs no box, and costs no bench
# cycle.  The datastream/cpio reader is imported from gen-catalog.py rather
# than copied, deliberately -- the count identity below only holds while both
# tools see exactly the same objects.
#
# THE COUNT IDENTITY (docs section 3.1).  The number of distinct pkgmap paths
# across a set, `i` lines excluded, EQUALS the object count of the contents DB
# that set installs -- verified with zero residual against all four attested
# reference sets (minimal 4859, standard 11012, developer 11497, x11 11546).
# So `--set <name>` predicts the object count of a proposed set before anyone
# boots a box; only the md5 digest still requires the guest.
#
# UNIVERSES.  Two, and the difference is a counting convention, not physics:
#   object universe      every distinct path, all ftypes, `i` excluded.  This
#                        is the contents-DB object count.
#   truncation universe  the same, minus b/c/p (device nodes and pipes).  s5
#                        does store those as dirents, so they CAN collide;
#                        they are excluded here only because W6's counts
#                        excluded them and the pinned constants below are
#                        stated over that universe.  The scan reports the
#                        collision count over both and says so when they
#                        differ -- if they ever do, believe the object
#                        universe.
#
# UFS-ONLY PACKAGES.  A package whose pkginfo carries APKG_FSTYPE (e.g.
# APKG_FSTYPE=ufs; gen-catalog.py's UFS-ONLY BLOCK, docs/design.md section
# 2b) never installs on s5: apkg refuses it there.  The s5 rule does not
# apply to it (P-35 Option C, 2026-10-30).  Its objects still count in
# every universe above -- the count identity is about objects, not
# filesystems -- but the scan names the marked packages, and a collision
# group made only of their objects is reported as exempt and does not
# fail --fail-on-collision.
#
# usage:
#   s5-collision-scan.py <staging-dir>              scan every package found
#   s5-collision-scan.py -s full <staging-dir>      scan one install set
#   s5-collision-scan.py --check -s full <dir>      assert the pinned constants
#   s5-collision-scan.py a.pkg b.pkg ...            scan named packages
#
# exit 0 = scanned (collisions are REPORTED, not an error, unless
#          --fail-on-collision), 1 = --check mismatch or --fail-on-collision
#          with collisions present, 2 = usage / unreadable input.

import argparse
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

S5_NAME_MAX = 14

# ftypes that are not ordinary tree objects for the W6 counting convention
DEVICE_FTYPES = frozenset("bcp")

# pkgmap(4) ftypes whose path field is "<path>=<source>" (pkgmap(4): the
# link target follows an '='; only the left side lands in the tree).
LINK_FTYPES = frozenset("sl")

# -------------------------------------------------------------------------
# Regression constants -- the `full` set (30 published packages) as measured
# for docs/s5-14char-collisions.md section 3.  `--check` asserts them.  They
# are pinned so that a re-mint, an added package or a changed exclusion list
# cannot move the collision picture silently.
#
# NOTE on `basename_key_groups`: that is NOT a measurement of anything real.
# It is the W6 defect reproduced on purpose -- group the TRUNCATED (>14)
# basenames on basename[:14] with the directory thrown away, and count a group
# only when it holds more than one distinct basename.  It reproduces W6's
# three rows exactly, which is what makes "3 vs 5" a regression-checkable
# statement instead of an anecdote.
#
# NOTE on `over_14` = 147: W6 reported 152 over the identical 27,876-path
# universe and no counting variant reproduces 152 (docs section 7).  147 is
# what the published packages contain; over-long names that do not collide are
# harmless anyway, by the same lookup-truncation round trip that makes the
# surviving name readable.
# -------------------------------------------------------------------------
PINNED = {
    "full": {
        "packages": 30,
        "object_universe": 28709,
        "truncation_universe": 27876,
        "over_14": 147,
        "at_least_14": 572,
        "collision_groups": 5,
        "basename_key_groups": 3,
    },
}


class ScanError(Exception):
    """Input cannot be scanned."""


def load_gen_catalog():
    """Import gen-catalog.py (hyphen in the name, hence importlib).

    Shared on purpose: parse_datastream()/decompress_z() are the reader the
    catalog itself is built with, so a package this tool can count is exactly
    a package the catalog can publish, and the section-3.1 count identity
    stays checkable.
    """
    path = os.path.join(HERE, "gen-catalog.py")
    spec = importlib.util.spec_from_file_location("gen_catalog", path)
    if spec is None or spec.loader is None:
        raise ScanError("cannot load %s" % path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_pkgmap(text, source):
    """Yield (ftype, path) for every pkgmap(4) entry that lands in the tree.

    pkgmap(4) lines are positional, with an OPTIONAL leading part number:

        [<part>] <ftype> <class> <path> [...]        f v e d x c b p s l
        [<part>] i <path> <size> <cksum> <modtime>   control files

    `i` entries are skipped: they are the pkginfo and the install scripts,
    they land under /var/sadm/pkg/<PKG>/install, and they are not part of the
    installed object universe (which is precisely why the section-3.1 count
    identity holds with them excluded).  ':' lines are the part/size header.
    """
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(":"):
            continue
        tok = line.split()
        if tok[0].isdigit():
            tok = tok[1:]
        if not tok:
            continue
        ftype = tok[0]
        if ftype == "i":
            continue
        if len(ftype) != 1 or len(tok) < 3:
            sys.stderr.write("s5-collision-scan: %s:%d: unparsable pkgmap "
                             "line, skipped: %r\n" % (source, lineno, raw))
            continue
        path = tok[2]
        if ftype in LINK_FTYPES:
            path = path.split("=", 1)[0]
        yield ftype, path


def read_catalog(path):
    """Read an apkg catalog; return {name: filename} (field 1 -> field 4)."""
    names = {}
    with open(path, encoding="latin-1") as fp:
        for line in fp:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.rstrip("\n").split("|")
            if len(fields) < 4:
                raise ScanError("%s: not a catalog line: %r" % (path, line))
            names[fields[0]] = fields[3]
    if not names:
        raise ScanError("%s: no catalog entries" % path)
    return names


def collect(pkgfiles, gen):
    """Scan the packages; return (objects, owners, marked).

    objects[path] = set of ftypes declaring it
    owners[path]  = set of package instances declaring it
    marked[pkginst] = the APKG_FSTYPE value of a UFS-only package
    """
    objects = {}
    owners = {}
    marked = {}
    for pkgfile in pkgfiles:
        try:
            with open(pkgfile, "rb") as fp:
                raw = fp.read()
            buf = gen.decompress_z(pkgfile) if pkgfile.endswith(".Z") else raw
            pkginst, params, pkgmap = gen.parse_datastream(buf)
            mark = gen.fstype_mark(params)
        except (OSError, gen.Malformed) as exc:
            raise ScanError("%s: %s" % (pkgfile, exc))
        if mark is not None:
            marked[pkginst] = mark
        if pkgmap is None:
            raise ScanError("%s: no pkgmap in the datastream" % pkgfile)
        for ftype, path in parse_pkgmap(pkgmap, os.path.basename(pkgfile)):
            objects.setdefault(path, set()).add(ftype)
            owners.setdefault(path, set()).add(pkginst)
    return objects, owners, marked


def group_by_directory(paths):
    """Group paths by (dirname, basename[:14]) -- the s5 dirent identity.

    THE keying rule.  A truncated name only collides with names in its OWN
    directory; keying on the basename alone is the W6 defect (it both merges
    genuinely separate collisions and invents cross-directory ones).
    """
    groups = {}
    for path in paths:
        dirname, basename = os.path.split(path)
        groups.setdefault((dirname, basename[:S5_NAME_MAX]), set()).add(path)
    return dict((k, v) for k, v in groups.items() if len(v) > 1)


def group_by_basename(paths):
    """The W6 defect, reproduced for regression: directory discarded.

    Restricted to names that are actually truncated (> 14), and counting a
    group only when it holds more than one distinct basename -- that is the
    variant that reproduces W6's three rows.  Reference only; never a fix
    input.
    """
    groups = {}
    for path in paths:
        basename = os.path.basename(path)
        if len(basename) > S5_NAME_MAX:
            groups.setdefault(basename[:S5_NAME_MAX], set()).add(path)
    return dict((k, v) for k, v in groups.items()
                if len(set(os.path.basename(p) for p in v)) > 1)


def scan(pkgfiles, gen):
    """Do the whole measurement; return a dict of results."""
    objects, owners, marked = collect(pkgfiles, gen)
    truncation = [p for p, ftypes in objects.items()
                  if not (ftypes & DEVICE_FTYPES)]

    groups = group_by_directory(truncation)
    groups_all = group_by_directory(list(objects))
    # a group whose every object belongs to UFS-only packages only
    exempt = [k for k, paths in groups.items()
              if all(owners[p] <= set(marked) for p in paths)]

    return {
        "packages": len(pkgfiles),
        "objects": objects,
        "owners": owners,
        "object_universe": len(objects),
        "truncation_universe": len(truncation),
        "over_14": len([p for p in truncation
                        if len(os.path.basename(p)) > S5_NAME_MAX]),
        "at_least_14": len([p for p in truncation
                            if len(os.path.basename(p)) >= S5_NAME_MAX]),
        "groups": groups,
        "collision_groups": len(groups),
        "collision_groups_all_ftypes": len(groups_all),
        "basename_key_groups": len(group_by_basename(truncation)),
        "marked": marked,
        "exempt_groups": len(exempt),
    }


def report(res, quiet):
    out = sys.stdout.write
    out("packages scanned                    %8d\n" % res["packages"])
    out("object universe (contents-DB objs)  %8d\n" % res["object_universe"])
    out("truncation universe (no b/c/p)      %8d\n"
        % res["truncation_universe"])
    out("basenames > %d characters            %8d\n"
        % (S5_NAME_MAX, res["over_14"]))
    out("basenames >= %d characters           %8d\n"
        % (S5_NAME_MAX, res["at_least_14"]))
    out("collision groups (dir, base[:%d])    %8d\n"
        % (S5_NAME_MAX, res["collision_groups"]))
    out("collision groups, basename-only key %8d\n"
        % res["basename_key_groups"])
    out("  (that last line is the W6 defect reproduced for reference:\n"
        "   the directory discarded.  It is never the number to fix by.)\n")

    if res["marked"]:
        out("UFS-only packages (APKG_FSTYPE)     %8d   %s\n"
            % (len(res["marked"]), " ".join(
                "%s=%s" % (k, res["marked"][k]) for k in sorted(res["marked"]))))
        out("collision groups of those only      %8d   (exempt: never on s5)\n"
            % res["exempt_groups"])

    if res["collision_groups_all_ftypes"] != res["collision_groups"]:
        out("\nNOTE: over the FULL object universe (device nodes and pipes\n"
            "      included, which s5 also stores as dirents) there are %d\n"
            "      collision groups, not %d.  Believe this number.\n"
            % (res["collision_groups_all_ftypes"], res["collision_groups"]))

    if quiet or not res["groups"]:
        return
    out("\ncollision groups (each is ONE dirent on s5):\n")
    for n, key in enumerate(sorted(res["groups"]), 1):
        dirname, truncated = key
        out("\n  %d. %s/  ->  %s\n" % (n, dirname, truncated))
        for path in sorted(res["groups"][key]):
            out("       %-56s %s  %s\n"
                % (os.path.basename(path),
                   "".join(sorted(res["objects"][path])),
                   ",".join(sorted(res["owners"][path]))))


def check_pinned(res, setname):
    """Compare against PINNED[setname]; return the list of mismatches."""
    pins = PINNED.get(setname)
    if pins is None:
        raise ScanError("no pinned constants for set %r (have: %s)"
                        % (setname, ", ".join(sorted(PINNED))))
    bad = []
    for field in sorted(pins):
        want = pins[field]
        got = res[field]
        if got != want:
            bad.append("%s: %d, pinned %d" % (field, got, want))
    return bad


def find_packages(paths, setname, sets_conf, catalog):
    """Resolve the command line into a list of package files."""
    pkgfiles = []
    staging = None
    for path in paths:
        if os.path.isdir(path):
            if staging is not None:
                raise ScanError("give at most one staging directory")
            staging = path
            for root, _dirs, files in os.walk(path):
                for name in sorted(files):
                    if name.endswith(".pkg") or name.endswith(".pkg.Z"):
                        pkgfiles.append(os.path.join(root, name))
        elif os.path.isfile(path):
            pkgfiles.append(path)
        else:
            raise ScanError("no such file or directory: %s" % path)

    if setname is None:
        return sorted(pkgfiles)

    # A set names catalog entries, and only the catalog maps a name to a file.
    sys.path.insert(0, HERE)
    import sets as setsmod          # noqa: E402  (path set above)

    if catalog is None:
        if staging is None:
            raise ScanError("--set needs a staging directory (or --catalog)")
        catalog = os.path.join(staging, "catalog")
    try:
        names = read_catalog(catalog)
        sets = setsmod.read_layered() if sets_conf is None \
            else setsmod.read_sets(sets_conf)
        members = setsmod.resolve(sets, setname)
    except (OSError, setsmod.SetsError) as exc:
        raise ScanError(str(exc))

    byname = {}
    for pkgfile in pkgfiles:
        byname[os.path.basename(pkgfile)] = pkgfile

    selected = []
    for member in members:
        if member not in names:
            raise ScanError("set %r names %r, which is not in %s"
                            % (setname, member, catalog))
        filename = os.path.basename(names[member])
        if filename not in byname:
            raise ScanError("catalog entry %r names %r, which was not found"
                            % (member, names[member]))
        selected.append(byname[filename])
    return sorted(selected)


def main(argv):
    ap = argparse.ArgumentParser(
        description="find the objects a package set cannot lay down on a "
                    "14-character (s5) filesystem")
    ap.add_argument("paths", nargs="+", metavar="PATH",
                    help="a staging directory and/or individual *.pkg files")
    ap.add_argument("-s", "--set", dest="setname",
                    help="restrict to the members of a sets.conf install set")
    ap.add_argument("--sets-conf", default=None,
                    help="sets.conf to read alone (default: the one beside "
                         "this script with amix's userland/packages/conf "
                         "layer, as sets.py reads them)")
    ap.add_argument("--catalog",
                    help="catalog to resolve set members through "
                         "(default: <staging>/catalog)")
    ap.add_argument("--check", action="store_true",
                    help="assert the pinned regression constants for --set")
    ap.add_argument("--fail-on-collision", action="store_true",
                    help="exit 1 if any collision group exists (groups made "
                         "only of UFS-only packages' objects excepted)")
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="counts only; do not list the colliding groups")
    args = ap.parse_args(argv)

    try:
        gen = load_gen_catalog()
        pkgfiles = find_packages(args.paths, args.setname, args.sets_conf,
                                 args.catalog)
        if not pkgfiles:
            raise ScanError("no *.pkg / *.pkg.Z found")
        res = scan(pkgfiles, gen)
    except ScanError as exc:
        sys.stderr.write("s5-collision-scan: %s\n" % exc)
        return 2

    report(res, args.quiet)

    rc = 0
    if args.check:
        if args.setname is None:
            sys.stderr.write("s5-collision-scan: --check needs --set\n")
            return 2
        try:
            bad = check_pinned(res, args.setname)
        except ScanError as exc:
            sys.stderr.write("s5-collision-scan: %s\n" % exc)
            return 2
        if bad:
            sys.stderr.write("s5-collision-scan: pinned-constant mismatch "
                             "for set %r:\n" % args.setname)
            for line in bad:
                sys.stderr.write("    %s\n" % line)
            rc = 1
        else:
            sys.stdout.write("\npinned constants for set %r: all %d match\n"
                             % (args.setname, len(PINNED[args.setname])))

    failing = res["collision_groups"] - res["exempt_groups"]
    if args.fail_on_collision and failing:
        sys.stderr.write("s5-collision-scan: %d collision group(s) present\n"
                         % failing)
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
