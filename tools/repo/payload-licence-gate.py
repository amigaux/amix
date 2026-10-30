#!/usr/bin/env python3
# payload-licence-gate.py -- refuse a package that carries FOREIGN object code.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Usage: payload-licence-gate.py <pkg-or-dir> [...]
#        payload-licence-gate.py --self-test
#
# Exit: 0 all clean (possibly with UNKNOWNs -- see below), 2 a REFUSE,
#       1 a usage/parse error.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS.  On 2026-09-16 `amixbench-1.2.pkg` was staged for the public
# repository carrying a `whet` binary that statically embedded the stock SVR4
# /usr/ccs/lib/libm.a -- Commodore/AT&T object code, which we may not
# redistribute.  It was caught by a human reading the recipe.  Every automated
# gate passed it, including the one whose name sounds like it should have
# caught it:
#
#   gen-catalog.py --scan-private keys on the KSUM_R / BOOT2_SHA pkginfo
#   markers that OUR OWN kernel mints carry.  Its contract is "our private
#   kernel packages never reach a redistributable catalog".  A third-party .a
#   linked into someone's payload binary carries no marker, so 1.2 passed it
#   clean.
#
# "Our kernel packages never leave" and "no foreign object code goes out" are
# DIFFERENT properties.  Only the first was checked.  This tool checks the
# second, and the two are deliberately kept in separate files so neither can
# quietly absorb and weaken the other.
#
# ---------------------------------------------------------------------------
# WHAT IT LOOKS FOR, and what that is worth.
#
# 1. libm STT_FILE names.  A static link from an archive leaves the member's
#    source-file symbol behind: `whet` carries atan.c exp.c log.c matherr.c
#    reduce.c sin.c sqrt.c beside its own whetstone.c.  This is the signature
#    that actually caught the real defect, so it is the primary test.
#
# 2. DT_NEEDED beyond the allowed set -- reported as a NOTE, never a refusal.
#    This was a REFUSE in the first draft and that was WRONG: the very first
#    run over the already-published packages refused APKG 0.2 for NEEDED
#    libnsl.so.  A DT_NEEDED is dynamic linkage against a library that lives
#    on the box; it redistributes none of the vendor's code, which is the
#    opposite of statically embedding libm.a.  apkg legitimately needs libnsl
#    for its sockets.  Conflating the two would have blocked the next APKG
#    publish with a bogus licensing accusation -- so the NEEDED list is
#    informational (it is still worth seeing an unexpected one), and only
#    embedded object code can refuse.
#
# ---------------------------------------------------------------------------
# ★ THE BLINDNESS, STATED WHERE IT IS CLAIMED.
#
# Test 1 reads a SYMBOL TABLE.  A stripped binary has none, so this tool
# cannot see embedded objects in one.  That is not a corner case: of the
# twelve packages we had published when this was written, four (gzip, less,
# AMIXDEMO, DEMOLIB) carry no source-file symbols at all.
#
# So a stripped ELF is reported UNKNOWN, never "clean".  A clean bill from
# this tool means "no foreign object code that a symbol table would reveal",
# and for a stripped binary that is no statement at all.  The tool prints the
# distinction rather than letting a reader infer a guarantee it cannot give;
# `--strict` turns UNKNOWN into a refusal for a caller that wants the strong
# reading.  The honest fix for an UNKNOWN is upstream: ship unstripped (which
# is what our own mints already do), or attest the link line in the recipe.
#
# ---------------------------------------------------------------------------
# ★ SCOPE: this gate polices OUR builds, not the vendor's.
#
# `pkgs/stock/` is the 27 repackaged Amix 2.1 factory packages -- Commodore's
# own binaries.  Of course they contain SVR4 libm objects: 39 of them do, and
# the X11 ones carry the whole archive.  That is not "we linked someone else's
# object code into our build"; it IS the vendor's code, and whether it may be
# served at all is a SEPARATE, explicit licensing decision the maintainer has taken
# (demo-only from 2026-09-14; since the 2026-09-23 licensing outcome -- Amiga
# Corporation approved distributing the Commodore binaries -- they are listed
# in the public catalog) -- not a question this gate is entitled to re-answer.  Scanning it would refuse every publish forever and
# teach everyone to pass a --force that must not exist.
#
# So `stock/` is skipped BY PROVENANCE PATH, loudly (the skip is printed, never
# silent), and `--include-stock` scans it anyway for anyone auditing it
# deliberately.  Everything else -- base/, extra/, test/ and any new group --
# is in scope, because those are the ones we build and therefore the ones we
# can accidentally contaminate.
#
# That the detector lights up on genuine SVR4 X11 binaries it was never tuned
# against is, incidentally, the strongest evidence we have that it works.
#
# ---------------------------------------------------------------------------
# A broken version of this tool -- wrong path, unreadable package, a regex
# that matches nothing -- would print exactly the same "all clean" as a
# healthy one over a clean input.  So --self-test runs it against the known
# CONTAMINATED signature and fails if it does NOT fire.

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PKGTRANS = os.path.join(REPO, "heirloom", "build-host", "bin", "pkgtrans")

# Source-file names of the SVR4 libm.a members.  Derived from the real
# positive (amixbench-1.2's `whet`, which carried the first seven) plus the
# rest of the archive's public entry points.
LIBM_OBJECTS = {
    "atan.c", "exp.c", "log.c", "matherr.c", "reduce.c", "sin.c", "sqrt.c",
    "asin.c", "acos.c", "atan2.c", "cosh.c", "sinh.c", "tanh.c", "tan.c",
    "pow.c", "fmod.c", "log10.c", "floor.c", "ceil.c", "gamma.c", "j0.c",
    "j1.c", "jn.c", "hypot.c", "cbrt.c", "erf.c", "expm1.c", "log1p.c",
}

# Names that are DISTINCTIVE to the SVR4 libm.a and are not plausible source
# filenames in someone else's project.  `matherr` is SVR4's math error hook and
# `reduce` its argument-reduction helper; neither shows up by accident.
# Refusing on a bare `log.c` or `exp.c` would be a false positive waiting to
# happen -- plenty of honest programs have one -- so a refusal needs either a
# distinctive marker or enough libm names co-occurring to rule out coincidence.
LIBM_DISTINCTIVE = {"matherr.c", "reduce.c"}
LIBM_COOCCURRENCE = 3

# Kickstart ROM images.  The Amix permission (Amiga Corporation, 2026-09-23)
# covers Amix; it does not cover the Kickstart ROM, and a Kickstart image never
# goes out.  Read from the content, not the filename: a ROM starts with the
# magic word $1111 (256K) or $1114 (512K and up) followed by JMP abs.l ($4EF9);
# a 16-bit byte-swapped dump (EPROM burner order) starts with the same bytes
# swapped; a Cloanto-encrypted image starts with "AMIROMTYPE1".  Measured
# 2026-10-30 on a set of 105 Kickstart 1.3-3.2.2 / CDTV / A3000 boot-ROM
# images: 89 caught, and the 16 missed are all split halves (hi/lo, even/odd
# chip images); 0 hits on 29 expansion-board ROMs.  An AROS ROM matches
# too; refusing it is the safe side.  NOT seen: split halves, a ROM inside an
# archive or disk image, a compressed ROM.
KICKSTART_HEADERS = (b"\x11\x11\x4e\xf9", b"\x11\x14\x4e\xf9",
                     b"\x11\x11\xf9\x4e", b"\x14\x11\xf9\x4e")
KICKSTART_ENCRYPTED = b"AMIROMTYPE1"

ALLOWED_NEEDED = {"/usr/lib/libc.so.1", "libc.so.1"}

# Provenance directories holding VENDOR content -- out of scope (see SCOPE).
VENDOR_DIRS = ("stock/",)

SRCNAME_RE = re.compile(rb"^[A-Za-z0-9_][A-Za-z0-9_+-]*\.[cs]$")
ELF_MAGIC = b"\x7fELF"

INCLUDE_STOCK = False

CLEAN, UNKNOWN, REFUSE = "clean", "UNKNOWN", "REFUSE"
NOTE = "note"


def strings_of(data):
    """ASCII runs of length >= 4, like strings(1) -- no external tool."""
    out, cur = [], bytearray()
    for b in data:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 4:
                out.append(bytes(cur))
            cur = bytearray()
    if len(cur) >= 4:
        out.append(bytes(cur))
    return out


def kickstart_rom(data):
    """A reason string if `data` is a Kickstart ROM image, else None."""
    if data.startswith(KICKSTART_ENCRYPTED):
        return "encrypted Kickstart ROM image (AMIROMTYPE1)"
    if data[:4] in KICKSTART_HEADERS:
        return "Kickstart ROM image (reset header %s)" % data[:4].hex()
    return None


def readelf_needed(path):
    """DT_NEEDED entries, or None if readelf cannot read the file."""
    try:
        r = subprocess.run(["readelf", "-d", path], capture_output=True,
                           text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return re.findall(r"\(NEEDED\).*?\[(.*?)\]", r.stdout)


def has_symtab(path):
    try:
        r = subprocess.run(["readelf", "-S", path], capture_output=True,
                           text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return ".symtab" in r.stdout


def inspect_elf(path, data):
    """-> (verdict, [reasons], [notes])"""
    notes = []
    needed = readelf_needed(path)
    if needed is not None:
        extra = [n for n in needed if n not in ALLOWED_NEEDED]
        if extra:
            # Informational ONLY -- see the header. Dynamic linkage ships no
            # vendor object code.
            notes.append("links box libraries beyond libc: " + " ".join(extra))

    names = {s.decode("ascii") for s in strings_of(data) if SRCNAME_RE.match(s)}
    hits = sorted(names & LIBM_OBJECTS)
    distinctive = sorted(set(hits) & LIBM_DISTINCTIVE)
    if distinctive or len(hits) >= LIBM_COOCCURRENCE:
        why = "embeds libm objects: " + " ".join(hits)
        if distinctive:
            why += "  (distinctive SVR4 libm marker: %s)" % " ".join(distinctive)
        else:
            why += "  (%d libm names co-occur; >=%d rules out coincidence)" % (
                len(hits), LIBM_COOCCURRENCE)
        return REFUSE, [why], notes
    if hits:
        # One or two generic names: could be this project's own source file.
        # Not a refusal, but a human should look.
        return UNKNOWN, ["carries libm-ish source name(s) %s -- too few and too "
                         "generic to call, check the link line by hand"
                         % " ".join(hits)], notes

    sym = has_symtab(path)
    if sym is False:
        return UNKNOWN, ["stripped (no .symtab): the object-code test cannot "
                         "see inside this binary"], notes
    if sym is None:
        return UNKNOWN, ["readelf could not read it: not inspected"], notes
    if not names:
        return UNKNOWN, ["unstripped but carries no source-file symbols: "
                         "nothing for the object-code test to read"], notes
    return CLEAN, [], notes


def scan_tree(root):
    """-> (verdict, findings, notes, n_elfs_inspected)"""
    findings, allnotes, worst, n_elf, n_file = [], [], CLEAN, 0, 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for f in sorted(filenames):
            full = os.path.join(dirpath, f)
            try:
                with open(full, "rb") as fp:
                    data = fp.read()
            except OSError:
                continue
            n_file += 1
            rel = os.path.relpath(full, root)
            rom = kickstart_rom(data)
            if rom:
                findings.append((rel, REFUSE, [rom + " -- not covered by "
                                               "the Amix permission; never "
                                               "shipped"]))
                worst = REFUSE
                continue
            if not data.startswith(ELF_MAGIC):
                continue
            n_elf += 1
            v, why, notes = inspect_elf(full, data)
            for n in notes:
                allnotes.append((rel, n))
            if v != CLEAN:
                findings.append((rel, v, why))
                if v == REFUSE:
                    worst = REFUSE
                elif worst == CLEAN:
                    worst = UNKNOWN
    return worst, findings, allnotes, (n_elf, n_file)


def datastream_pkginst(path):
    """The PKG instance from the datastream header's second line.

    pkgtrans needs it named explicitly; without it it just lists what is
    available and unpacks nothing.
    """
    with open(path, "rb") as fp:
        head = fp.read(512)
    lines = head.split(b"\n")
    if len(lines) < 2 or not lines[0].startswith(b"# PaCkAgE DaTaStReAm"):
        raise SystemExit("payload-licence-gate: %s: not an SVR4 datastream"
                         % path)
    return lines[1].split()[0].decode("ascii")


def scan_package(path):
    if os.path.isdir(path):
        # ★ A staging root holds .pkg DATASTREAMS, not ELFs.  The first draft
        # just walked for ELF magic, found none, and reported OK -- a vacuous
        # pass, and it did it for the CONTAMINATED staging too.  So descend
        # into every package as well as scanning any loose ELFs.
        pkgs = []
        for dirpath, dirnames, filenames in os.walk(path):
            dirnames.sort()
            for f in sorted(filenames):
                if f.endswith(".pkg") or f.endswith(".pkg.Z"):
                    pkgs.append(os.path.join(dirpath, f))
        worst, findings, notes, n = scan_tree(path)
        n_elf, n_file = n
        skipped = []
        if not INCLUDE_STOCK:
            keep = []
            for pk in pkgs:
                rel = os.path.relpath(pk, path).replace(os.sep, "/")
                (skipped if rel.startswith(VENDOR_DIRS) else keep).append(rel)
            pkgs = [os.path.join(path, r) for r in keep]
        if skipped:
            print("  scope   skipping %d vendor package(s) under %s -- factory "
                  "Amix content, governed by its own licensing decision, not "
                  "by this gate (--include-stock to scan anyway)"
                  % (len(skipped), " ".join(VENDOR_DIRS)))
        for pk in pkgs:
            pv, pf, pn, pnn = scan_package(pk)
            rel = os.path.relpath(pk, path)
            findings += [("%s!%s" % (rel, r), v, w) for r, v, w in pf]
            notes += [("%s!%s" % (rel, r), t) for r, t in pn]
            n_elf += pnn[0]
            n_file += pnn[1]
            if pv == REFUSE:
                worst = REFUSE
            elif pv == UNKNOWN and worst == CLEAN:
                worst = UNKNOWN
        return worst, findings, notes, (n_elf, n_file)
    with tempfile.TemporaryDirectory(prefix="paylic.") as tmp:
        if not os.path.isfile(PKGTRANS):
            print("payload-licence-gate: %s missing -- build the host engine "
                  "(heirloom/build-host.sh)" % PKGTRANS, file=sys.stderr)
            raise SystemExit(1)
        r = subprocess.run([PKGTRANS, "-o", path, tmp,
                            datastream_pkginst(path)],
                           capture_output=True, text=True, timeout=600)
        if not os.listdir(tmp):
            print("payload-licence-gate: %s: pkgtrans unpacked nothing (%s)"
                  % (path, (r.stderr or "").strip()[:120]), file=sys.stderr)
            raise SystemExit(1)
        return scan_tree(tmp)


def self_test():
    """Fire the detector at the known CONTAMINATED signature.

    A detector that matches nothing prints the same 'clean' as a healthy one,
    so prove it fires before trusting a pass.
    """
    ok = True
    fake = b"\x7fELF" + b"\x00" * 64 + b"\x00".join(
        [b"whetstone.c", b"sqrt.c", b"matherr.c", b"exp.c"]) + b"\x00"
    names = {s.decode() for s in strings_of(fake) if SRCNAME_RE.match(s)}
    hits = names & LIBM_OBJECTS
    print("  known-positive signature -> %s" % (sorted(hits) or "NOTHING"))
    if hits != {"sqrt.c", "matherr.c", "exp.c"}:
        print("  FAIL: the libm signature did not fire"); ok = False
    clean = {s.decode() for s in strings_of(b"\x7fELF\x00dhry.c\x00")
             if SRCNAME_RE.match(s)}
    print("  known-negative signature -> %s" % (sorted(clean & LIBM_OBJECTS)
                                                or "nothing (correct)"))
    if clean & LIBM_OBJECTS:
        print("  FAIL: fired on a clean binary"); ok = False
    rom = b"\x11\x14\x4e\xf9\x00\xf8\x00\xd2" + b"\x00" * (512 * 1024 - 8)
    print("  known-positive Kickstart header -> %s"
          % (kickstart_rom(rom) or "NOTHING"))
    if not kickstart_rom(rom) or not kickstart_rom(b"AMIROMTYPE1\x1b"):
        print("  FAIL: the Kickstart ROM test did not fire"); ok = False
    if kickstart_rom(fake):
        print("  FAIL: the Kickstart ROM test fired on an ELF"); ok = False
    print("self-test: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 2


def main(argv):
    global INCLUDE_STOCK
    if "--self-test" in argv:
        return self_test()
    INCLUDE_STOCK = "--include-stock" in argv
    strict = "--strict" in argv
    targets = [a for a in argv if not a.startswith("-")]
    if not targets:
        print(__doc__ or "usage: payload-licence-gate.py <pkg-or-dir> [...]",
              file=sys.stderr)
        print("usage: payload-licence-gate.py [--strict] <pkg-or-dir> [...]",
              file=sys.stderr)
        return 1

    rc, n_unknown, n_refuse = 0, 0, 0
    for t in targets:
        verdict, findings, notes, (n_elf, n_file) = scan_package(t)
        label = os.path.basename(t.rstrip("/"))
        for rel, n in notes:
            print("  %-7s %s: %s" % ("note", rel, n))
        for rel, v, why in findings:
            for w in why:
                print("  %-7s %s: %s" % (v, rel, w))
            if v == REFUSE:
                n_refuse += 1
            else:
                n_unknown += 1
        if verdict == REFUSE:
            print("payload-licence-gate: REFUSE %s -- it carries foreign "
                  "object code; the public repo ships only our own builds"
                  % label)
            rc = 2
        elif verdict == UNKNOWN:
            print("payload-licence-gate: %s: no foreign object code FOUND, "
                  "but some binaries could not be inspected (above). This is "
                  "not a clean bill." % label)
            if strict and rc == 0:
                rc = 2
        elif n_file == 0:
            # Inspecting nothing and calling it clean is how a broken gate
            # looks exactly like a healthy one.  No files AT ALL means the
            # path is wrong or the package would not unpack -- refuse.
            print("payload-licence-gate: %s: NOTHING INSPECTED -- not one file "
                  "was read. That is not a pass; check the path." % label)
            if rc == 0:
                rc = 2
        elif n_elf == 0:
            # Files, but no ELFs: a legitimate binary-free package (docs,
            # scripts, source).  Nothing for this gate to police, and saying
            # so is honest -- unlike the case above, we did read the payload.
            print("payload-licence-gate: OK %s (%d file(s), no ELF binaries "
                  "-- nothing for this gate to police)" % (label, n_file))
        else:
            print("payload-licence-gate: OK %s (%d ELF(s) inspected; no "
                  "embedded foreign object code)" % (label, n_elf))
    if n_unknown and not n_refuse:
        print("payload-licence-gate: %d uninspectable binary/binaries. A "
              "stripped ELF hides the symbol table this test reads, so "
              "UNKNOWN means UNTESTED, not clean." % n_unknown)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
