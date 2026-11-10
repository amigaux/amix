#!/usr/bin/env python3
# tools/iso-selftest.py -- prove every hard constraint of the install CD actually
# FIRES on a crafted violation.  Driven by `tools/build-iso.sh --self-test`.
#
# WHY.  build-iso.sh's checks all pass on a good disc, which tells you nothing: a
# check that has never been observed to fail is an assumption wearing a check's
# clothing.  Each case below builds a deliberately-broken input, runs the real
# check function from tools/lib/isocheck.py against it, and asserts the check
# rejects it -- and, for the constraints that are only observable after mastering,
# masters a real ISO with xorriso and reads it back.
#
# Every fixture is SYNTHETIC: a few bytes of generated content.  There is no
# proprietary Commodore material here, and none may ever be added -- this test must
# stay runnable with no packages, no media, and no bench.
#
# Exit 0 = every constraint fired as designed.  Nonzero = a constraint is not
# actually enforced.  Fails closed: a case that cannot run is a failure, never a
# skip, and a missing xorriso is a failure rather than a reason to pass.

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from isocheck import (                                       # noqa: E402
    ODFS_NAME_MAX, walk_rel, walk_rel_dirs,
    check_no_spaces, check_name_length, check_no_compression, check_no_collisions,
    check_single_session, check_rockridge, check_no_joliet, check_blank_system_id,
    check_zero_renames,
    CDBOOT_SYSTEM_ID, check_system_id, check_cdboot_tree, check_cdboot_plain_names,
    check_cdboot_disc,
    parse_catalog, check_catalog_resolves, check_no_orphan_packages,
)

results = []


def case(name, fn):
    """Run one case; a case that raises is a FAILURE, not a skip."""
    try:
        ok, detail = fn()
    except Exception as e:                                    # noqa: BLE001
        ok, detail = False, "case raised %s: %s" % (type(e).__name__, e)
    results.append((name, ok, detail))
    print("  %s  %s" % ("OK  " if ok else "FAIL", name))
    if detail:
        print("        %s" % detail)
    return ok


def fired(viols, kind):
    """Assert the expected violation kind is among those reported."""
    kinds = [v.kind for v in viols]
    if not viols:
        return False, "check reported NO violation -- the constraint is not enforced"
    if kind not in kinds:
        return False, "expected a %r violation, got %r" % (kind, kinds)
    return True, "fired: %s" % viols[0].detail.split("\n")[0]


def write(path, data=b"x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def master(root, iso, rock=True):
    """Master a single-session ISO exactly as build-iso.sh does.

    -as mkisofs, NOT the native -outdev/-commit: the native path writes a growable
    two-descriptor-set layout (session at LBA 32, PVD at 48, relocated superblock at
    16). See isocheck.check_single_session.

    rock=False builds the Rock-Ridge-OFF fixture, and it has to leave the mkisofs
    emulation to do it: that emulation turns Rock Ridge ON by default (genuine
    mkisofs does not) and rejects -norock outright, so RR can only be suppressed
    through the native -rockridge off. The fixture therefore carries the native
    growable layout too -- irrelevant here, since these cases assert on names and on
    the RR extension record, not on session count. That build-iso.sh must pass
    -rational-rock explicitly rather than lean on the emulation's default is the
    other half of the same observation."""
    if rock:
        cmd = ["xorriso", "-as", "mkisofs", "-o", iso, "-V", "SELFTEST",
               "-iso-level", "3", "-rational-rock", root]
    else:
        cmd = ["xorriso", "-report_about", "SORRY", "-outdev", iso, "-volid", "SELFTEST",
               "-rockridge", "off", "-joliet", "off", "-map", root, "/", "-commit", "-end"]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode != 0:
        raise RuntimeError("xorriso failed: %s" % p.stdout.decode("utf-8", "replace")[-800:])


def extract(iso, dest):
    p = subprocess.run(["xorriso", "-osirrox", "on", "-indev", iso, "-extract", "/", dest],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode != 0:
        raise RuntimeError("xorriso extract failed: %s"
                           % p.stdout.decode("utf-8", "replace")[-800:])


# =====================================================================  cases ===

def c_spaces(tmp):
    """A pathname with a space must be a HARD error, not a warning."""
    root = os.path.join(tmp, "spaces")
    write(os.path.join(root, "pkgs", "stock", "TrueType Fonts.pkg"))
    return fired(check_no_spaces(walk_rel(root)), "space-in-pathname")


def c_spaces_dir(tmp):
    """...including a space in a DIRECTORY component, not just the leaf."""
    root = os.path.join(tmp, "spacedir")
    write(os.path.join(root, "pkgs", "my stock", "a.pkg"))
    paths = walk_rel(root) + walk_rel_dirs(root)
    return fired(check_no_spaces(paths), "space-in-pathname")


def c_namelen(tmp):
    """A component longer than ODFS_NAME_MAX (512 on Amix) must be rejected.

    Driven from a synthetic path LIST rather than real files on purpose: Linux
    NAME_MAX is 255, so a 513-byte filename cannot exist on the host filesystem and
    the fixture could not be built at all. The constraint we are enforcing belongs
    to the target, not to the machine authoring the disc."""
    over = "pkgs/stock/" + "a" * (ODFS_NAME_MAX + 1) + ".pkg"
    ok, d = fired(check_name_length([over]), "name-too-long")
    if not ok:
        return ok, d
    # Exactly at the limit must be accepted -- an off-by-one here rejects legal discs.
    at_limit = "pkgs/stock/" + "a" * ODFS_NAME_MAX
    if check_name_length([at_limit]):
        return False, "a name of exactly %d bytes was rejected (off-by-one)" % ODFS_NAME_MAX
    # And the AmigaOS-only 128 cap must NOT be what we enforce.
    if check_name_length(["pkgs/stock/" + "b" * 200 + ".pkg"]):
        return False, ("a 200-char name was rejected -- that is the AmigaOS 128 cap, "
                       "not Amix's 512")
    return True, d + "; %d-byte name accepted, 200-char accepted (512, not 128)" % ODFS_NAME_MAX


def c_compression(tmp):
    """No .Z on the disc -- gen-catalog accepts .pkg.Z, so this must be checked."""
    root = os.path.join(tmp, "zed")
    write(os.path.join(root, "pkgs", "stock", "core-2.1.pkg.Z"))
    return fired(check_no_compression(walk_rel(root)), "compressed-payload")


def c_collision(tmp):
    """Two names colliding case-insensitively in one directory -> cdfs ~2 rename."""
    root = os.path.join(tmp, "collide")
    write(os.path.join(root, "pkgs", "stock", "Core-2.1.pkg"))
    write(os.path.join(root, "pkgs", "stock", "core-2.1.pkg"))
    return fired(check_no_collisions(walk_rel(root)), "name-collision")


def c_multisession(tmp):
    """SINGLE SESSION: a second descriptor set must be detected in the image.

    Built for real: master a disc, confirm it is clean, then grow it with a genuine
    second session via xorriso's -dev multi-session path and require the check to
    see it. On Amix this is the worst failure mode available -- cdfs would show only
    the first session and report no error at all."""
    root = os.path.join(tmp, "ms")
    write(os.path.join(root, "a.txt"), b"first session\n")
    iso = os.path.join(tmp, "ms.iso")
    master(root, iso)

    good = check_single_session(open(iso, "rb").read())
    if good:
        return False, "a freshly mastered disc was flagged multisession: %s" % good[0]

    root2 = os.path.join(tmp, "ms2")
    write(os.path.join(root2, "b.txt"), b"second session\n")
    p = subprocess.run(["xorriso", "-report_about", "SORRY",
                        "-dev", iso, "-map", root2, "/", "-commit", "-end"],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode != 0:
        raise RuntimeError("could not append a second session: %s"
                           % p.stdout.decode("utf-8", "replace")[-500:])
    return fired(check_single_session(open(iso, "rb").read()), "multisession")


def c_native_growable(tmp):
    """xorriso's NATIVE -outdev/-commit must be rejected as a two-set layout.

    This is the regression guard for the finding that produced the -as mkisofs
    choice: the native write path silently emits a growable image (session at LBA
    32, PVD at 48, relocated superblock at 16). It looks like an ordinary ISO, it
    mounts fine on Linux, and it is precisely what a reader with no read_toc cannot
    reason about. If a future edit switches the mastering command back, this fires."""
    root = os.path.join(tmp, "native")
    write(os.path.join(root, "a.txt"), b"native write path\n")
    iso = os.path.join(tmp, "native.iso")
    p = subprocess.run(["xorriso", "-report_about", "SORRY", "-outdev", iso,
                        "-volid", "SELFTEST", "-rockridge", "on", "-joliet", "off",
                        "-map", root, "/", "-commit", "-end"],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.returncode != 0:
        raise RuntimeError("xorriso failed: %s" % p.stdout.decode("utf-8", "replace")[-500:])
    return fired(check_single_session(open(iso, "rb").read()), "multisession")


def c_joliet(tmp):
    """Joliet must be off, and its presence must be detected in the image."""
    root = os.path.join(tmp, "jol")
    write(os.path.join(root, "a.txt"), b"joliet\n")
    iso = os.path.join(tmp, "jol.iso")
    subprocess.run(["xorriso", "-as", "mkisofs", "-o", iso, "-V", "SELFTEST",
                    "-rational-rock", "-J", root],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    ok, d = fired(check_no_joliet(open(iso, "rb").read()), "joliet-present")
    if not ok:
        return ok, d
    iso2 = os.path.join(tmp, "nojol.iso")
    master(root, iso2)
    if check_no_joliet(open(iso2, "rb").read()):
        return False, "a disc mastered without -J was reported as carrying Joliet"
    return True, d + "; no-Joliet control passed"


def c_sysid(tmp):
    """A set PVD System ID must be detected (the A4092 ROM boots 'CDTV' at pri 2)."""
    root = os.path.join(tmp, "sysid")
    write(os.path.join(root, "a.txt"), b"sysid\n")
    iso = os.path.join(tmp, "sysid.iso")
    subprocess.run(["xorriso", "-as", "mkisofs", "-o", iso, "-V", "SELFTEST",
                    "-sysid", "CDTV", "-rational-rock", root],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    ok, d = fired(check_blank_system_id(open(iso, "rb").read()), "system-id-set")
    if not ok:
        return ok, d
    iso2 = os.path.join(tmp, "nosysid.iso")
    master(root, iso2)
    if check_blank_system_id(open(iso2, "rb").read()):
        return False, "a disc mastered without -sysid was reported as carrying a System ID"
    return True, d + "; blank-System-ID control passed"


def cdboot_tree(root, loader_mode=0o755):
    """A synthetic mkstore -C tree: both line directories, loader, Startup-Sequence."""
    write(os.path.join(root, "BOOT", "amix-cdboot"), b"\x00\x00\x03\xf3synthetic")
    os.chmod(os.path.join(root, "BOOT", "amix-cdboot"), loader_mode)
    for line in ("K30", "K46"):
        d = os.path.join(root, "BOOT", line)
        write(os.path.join(d, "CONTROL"), b"\0" * 2048)
        for n in ("G1.GMF", "G1K.BIN", "G1R.BIN", "G1M01.BIN"):
            write(os.path.join(d, n), n.encode() + b"\n")
    write(os.path.join(root, "S", "Startup-Sequence"),
          b"; synthetic\nSYS:BOOT/amix-cdboot\n")


def master_cdboot(root, iso, sysid=True):
    cmd = ["xorriso", "-as", "mkisofs", "-o", iso, "-V", "SELFTEST",
           "-iso-level", "3", "-rational-rock"]
    if sysid:
        cmd += ["-sysid", CDBOOT_SYSTEM_ID]
    subprocess.run(cmd + [root], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=True)


def c_cdboot_sysid(tmp):
    """The CD-boot disc must carry System ID 'AMIGA BOOT' (else the ROM gives it -1)."""
    root = os.path.join(tmp, "cbsys")
    cdboot_tree(root)
    iso = os.path.join(tmp, "cbsys-none.iso")
    master_cdboot(root, iso, sysid=False)
    ok, d = fired(check_system_id(open(iso, "rb").read(), CDBOOT_SYSTEM_ID), "system-id-wrong")
    if not ok:
        return ok, d
    iso2 = os.path.join(tmp, "cbsys-set.iso")
    master_cdboot(root, iso2)
    v = check_system_id(open(iso2, "rb").read(), CDBOOT_SYSTEM_ID)
    if v:
        return False, "a disc mastered with -sysid 'AMIGA BOOT' was refused: %s" % v[0]
    return True, d + "; -sysid 'AMIGA BOOT' control passed"


def c_cdboot_tree(tmp):
    """A tree that is not a mkstore -C tree is refused before mastering."""
    good = os.path.join(tmp, "cbtree-good")
    cdboot_tree(good)
    if check_cdboot_tree(good):
        return False, "the synthetic mkstore tree was refused: %s" % check_cdboot_tree(good)[0]
    broken = []
    for kind, mutate in (
            ("cdboot-no-loader", lambda r: os.remove(os.path.join(r, "BOOT", "amix-cdboot"))),
            ("cdboot-name", lambda r: write(os.path.join(r, "BOOT", "K30", "G1-K.BIN"))),
            ("cdboot-control", lambda r: write(os.path.join(r, "BOOT", "K46", "CONTROL"), b"short")),
            ("cdboot-startup", lambda r: write(os.path.join(r, "S", "Startup-Sequence"),
                                               b"LoadWB\nEndCLI\n")),
            ("cdboot-top", lambda r: write(os.path.join(r, "README"))),
    ):
        r = os.path.join(tmp, "cbtree-" + kind)
        cdboot_tree(r)
        mutate(r)
        ok, d = fired(check_cdboot_tree(r), kind)
        if not ok:
            return False, "%s: %s" % (kind, d)
        broken.append(kind)
    return True, "fired: %s; the good tree passed" % ", ".join(broken)


def c_cdboot_exec(tmp):
    """BOOT/amix-cdboot mastered without an execute bit is caught (ODFS FIBF_EXECUTE)."""
    root = os.path.join(tmp, "cbexec")
    cdboot_tree(root, loader_mode=0o644)
    iso = os.path.join(tmp, "cbexec.iso")
    master_cdboot(root, iso)
    disc = os.path.join(tmp, "cbexec-x")
    extract(iso, disc)
    ok, d = fired(check_cdboot_disc(root, disc), "cdboot-not-executable")
    if not ok:
        return ok, d
    root2 = os.path.join(tmp, "cbexec2")
    cdboot_tree(root2)
    iso2 = os.path.join(tmp, "cbexec2.iso")
    master_cdboot(root2, iso2)
    disc2 = os.path.join(tmp, "cbexec2-x")
    extract(iso2, disc2)
    v = check_cdboot_disc(root2, disc2)
    if v:
        return False, "a 0755 loader mastered with -rational-rock was refused: %s" % v[0]
    return True, d + "; 0755 control passed"


def c_cdboot_plain(tmp):
    """A line-directory member without its own plain ISO9660 name is caught."""
    root = os.path.join(tmp, "cbplain")
    cdboot_tree(root)
    os.rename(os.path.join(root, "BOOT", "K30", "G1K.BIN"),
              os.path.join(root, "BOOT", "K30", "g1k.bin"))
    iso = os.path.join(tmp, "cbplain.iso")
    master_cdboot(root, iso)
    ok, d = fired(check_cdboot_plain_names(open(iso, "rb").read(), root), "cdboot-plain-name")
    if not ok:
        return ok, d
    root2 = os.path.join(tmp, "cbplain2")
    cdboot_tree(root2)
    iso2 = os.path.join(tmp, "cbplain2.iso")
    master_cdboot(root2, iso2)
    v = check_cdboot_plain_names(open(iso2, "rb").read(), root2)
    if v:
        return False, "the 8.3 tree lost a plain ISO9660 name: %s" % v[0]
    return True, d + "; 8.3 control passed"


def c_rockridge(tmp):
    """Rock Ridge OFF must be detected, and must destroy the on-disc names.

    This is the check that makes 'zero renames' meaningful: without RR, cdfs falls
    back to the mangled ISO9660 namespace and every catalog lookup misses."""
    root = os.path.join(tmp, "norr")
    write(os.path.join(root, "pkgs", "stock", "core-2.1.pkg"), b"payload\n")
    iso = os.path.join(tmp, "norr.iso")
    master(root, iso, rock=False)
    ok, d = fired(check_rockridge(open(iso, "rb").read()), "no-rock-ridge")
    if not ok:
        return ok, d
    # the positive control: an RR disc must pass
    iso2 = os.path.join(tmp, "rr.iso")
    master(root, iso2)
    if check_rockridge(open(iso2, "rb").read()):
        return False, "a Rock Ridge disc was reported as having no Rock Ridge"
    return True, d + "; RR-on control passed"


def c_renames(tmp):
    """ZERO RENAMES: a disc whose names differ from the staged names must fail.

    Uses the real mastered-image path -- master with RR off so the ISO9660 namespace
    mangles the names, then assert the staged-vs-disc comparison catches it."""
    root = os.path.join(tmp, "ren")
    write(os.path.join(root, "pkgs", "stock", "core-2.1.pkg"), b"payload\n")
    iso = os.path.join(tmp, "ren.iso")
    master(root, iso, rock=False)
    ex = os.path.join(tmp, "ren-x")
    extract(iso, ex)
    ok, d = fired(check_zero_renames(walk_rel(root), walk_rel(ex)), "renamed-on-disc")
    if not ok:
        return ok, d
    # positive control: with RR on, names must survive exactly
    iso2 = os.path.join(tmp, "ren2.iso")
    master(root, iso2)
    ex2 = os.path.join(tmp, "ren2-x")
    extract(iso2, ex2)
    v = check_zero_renames(walk_rel(root), walk_rel(ex2))
    if v:
        return False, "RR disc still reported renames: %s" % v[0]
    return True, d + "; RR-on control preserved names exactly"


def c_catalog_dangling(tmp):
    """A catalog row pointing at a file the disc does not hold must be caught.

    This is what a ~2/~3 rename looks like from the catalog's side."""
    disc = os.path.join(tmp, "cat1")
    write(os.path.join(disc, "pkgs", "stock", "core-2.1.pkg"), b"payload\n")
    cat = ("#apkg-catalog 1\n"
           "core|2.1|core|stock/gone-2.1.pkg|%s|8|none|system|missing\n"
           % hashlib.md5(b"payload\n").hexdigest())
    rows, bad = parse_catalog(cat)
    if bad:
        return False, "fixture catalog did not parse"
    return fired(check_catalog_resolves(rows, disc), "catalog-dangling")


def c_catalog_md5(tmp):
    """A row whose md5/size disagree with the bytes on the disc must be caught."""
    disc = os.path.join(tmp, "cat2")
    write(os.path.join(disc, "pkgs", "stock", "core-2.1.pkg"), b"payload\n")
    cat = ("#apkg-catalog 1\n"
           "core|2.1|core|stock/core-2.1.pkg|%s|8|none|system|wrong md5\n"
           % ("0" * 32))
    rows, _ = parse_catalog(cat)
    return fired(check_catalog_resolves(rows, disc), "catalog-md5-mismatch")


def c_catalog_orphan(tmp):
    """A .pkg on the disc that no catalog row mentions must be caught."""
    disc = os.path.join(tmp, "cat3")
    write(os.path.join(disc, "pkgs", "stock", "core-2.1.pkg"), b"payload\n")
    write(os.path.join(disc, "pkgs", "stock", "stowaway-2.1.pkg"), b"nobody asked\n")
    cat = ("#apkg-catalog 1\n"
           "core|2.1|core|stock/core-2.1.pkg|%s|8|none|system|fine\n"
           % hashlib.md5(b"payload\n").hexdigest())
    rows, _ = parse_catalog(cat)
    return fired(check_no_orphan_packages(rows, walk_rel(disc)), "uncatalogued-package")


def c_catalog_header(tmp):
    """A catalog without the v1 header must not be accepted as one."""
    rows, bad = parse_catalog("name|1|N|f|m|1|none|c|d\n")
    return fired(bad, "bad-catalog")


def c_roundtrip_green(tmp):
    """Positive control: a well-formed disc passes every check.

    Without this, all the above would still 'pass' if the checks simply rejected
    everything."""
    disc = os.path.join(tmp, "green")
    payload = b"synthetic package payload\n"
    write(os.path.join(disc, "pkgs", "stock", "core-2.1.pkg"), payload)
    write(os.path.join(disc, "pkgs", "base", "APKG-0.1.pkg"), payload)
    os.makedirs(os.path.join(disc, "install"), exist_ok=True)
    write(os.path.join(disc, "install", "PLACEHOLDER"), b"later\n")
    md5 = hashlib.md5(payload).hexdigest()
    n = len(payload)
    cat = ("#apkg-catalog 1\n"
           "apkg|0.1|APKG|base/APKG-0.1.pkg|%s|%d|none|application|ours\n"
           "core|2.1|core|stock/core-2.1.pkg|%s|%d|none|system|synthetic\n"
           % (md5, n, md5, n))
    write(os.path.join(disc, "catalog"), cat.encode())

    iso = os.path.join(tmp, "green.iso")
    master(disc, iso)
    ex = os.path.join(tmp, "green-x")
    extract(iso, ex)
    img = open(iso, "rb").read()
    files = walk_rel(ex)
    allp = files + walk_rel_dirs(ex)
    rows, bad = parse_catalog(open(os.path.join(ex, "catalog"), encoding="utf-8").read())
    v = (check_single_session(img) + check_rockridge(img) + check_no_joliet(img)
         + check_blank_system_id(img)
         + check_zero_renames(walk_rel(disc), files)
         + check_no_spaces(allp) + check_name_length(allp) + check_no_compression(files)
         + bad + check_catalog_resolves(rows, ex) + check_no_orphan_packages(rows, files))
    if v:
        return False, "a well-formed disc failed: %s" % "; ".join(str(x) for x in v)
    return True, "%d files mastered, read back, all constraints satisfied" % len(files)


CASES = [
    ("HARD CONSTRAINT: no spaces in a pathname (leaf)",          c_spaces),
    ("HARD CONSTRAINT: no spaces in a pathname (directory)",     c_spaces_dir),
    ("HARD CONSTRAINT: ODFS_NAME_MAX is 512, not the AmigaOS 128", c_namelen),
    ("HARD CONSTRAINT: no .Z compression on the disc",           c_compression),
    ("HARD CONSTRAINT: no case-collisions (cdfs ~2 rename)",     c_collision),
    ("HARD CONSTRAINT: single session (real 2nd session appended)", c_multisession),
    ("HARD CONSTRAINT: xorriso native -outdev is a growable 2-set layout", c_native_growable),
    ("HARD CONSTRAINT: Rock Ridge present (real RR-off master)", c_rockridge),
    ("HARD CONSTRAINT: Joliet off (real -J master detected)",     c_joliet),
    ("HARD CONSTRAINT: PVD System ID blank (real -sysid CDTV master)", c_sysid),
    ("HARD CONSTRAINT: zero renames (staged names == disc names)", c_renames),
    ("CD BOOT: System ID 'AMIGA BOOT' (real masters with and without)", c_cdboot_sysid),
    ("CD BOOT: the tree is a mkstore -C tree (five broken trees)", c_cdboot_tree),
    ("CD BOOT: amix-cdboot executable on the disc (real 0644 master)", c_cdboot_exec),
    ("CD BOOT: line directories keep 8.3 plain ISO9660 names", c_cdboot_plain),
    ("CATALOG: row pointing at a file not on the disc",          c_catalog_dangling),
    ("CATALOG: row whose md5 disagrees with the disc",           c_catalog_md5),
    ("CATALOG: .pkg on the disc with no catalog row",            c_catalog_orphan),
    ("CATALOG: missing '#apkg-catalog 1' header",                c_catalog_header),
    ("POSITIVE CONTROL: a well-formed disc passes everything",   c_roundtrip_green),
]


def main():
    if not shutil.which("xorriso"):
        sys.stderr.write(
            "iso-selftest: FATAL -- xorriso not found.\n"
            "  Several cases master and read back real ISOs; without it they cannot\n"
            "  run, and an unrun constraint check must never be reported as passing.\n")
        return 2

    print("iso-selftest: proving each install-CD hard constraint FIRES")
    print("iso-selftest: fixtures are synthetic -- no proprietary content, no bench")
    print()
    tmp = tempfile.mkdtemp(prefix="iso-selftest.")
    try:
        for name, fn in CASES:
            case(name, lambda fn=fn: fn(tmp))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    bad = [n for n, ok, _ in results if not ok]
    print()
    if bad:
        print("iso-selftest: FAIL -- %d/%d case(s) did not behave as designed:"
              % (len(bad), len(results)))
        for n in bad:
            print("   - %s" % n)
        return 1
    print("iso-selftest: PASS -- %d/%d constraints demonstrated" % (len(results), len(results)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
