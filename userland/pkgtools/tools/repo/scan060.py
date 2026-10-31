#!/usr/bin/env python3
# scan060.py -- find 68060-unimplemented integer instructions in what we ship.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Usage: scan060.py [--include-stock] <elf|pkg|dir> [...]
#        scan060.py --self-test
#
# Exit: 0 every inspected ELF is clean, 2 at least one hit (or nothing was
#       inspected at all), 1 a usage/tool error.
#
# Env:  AMIX_PKGTRANS  the host pkgtrans that unpacks a datastream (as in
#       build/pkg/layout.sh); unset or empty, heirloom/build-host/bin/pkgtrans.
#
# ---------------------------------------------------------------------------
# WHY.  The 68060 does not implement, and traps through vector 61 (offset
# 0xF4, "unimplemented integer instruction"), these 68020/030 forms:
#
#   MULU.L/MULS.L <ea>,Dh:Dl   32x32 -> 64 product   0x4C00-0x4C3F, ext bit 10
#   DIVU.L/DIVS.L <ea>,Dr:Dq   64/32 dividend        0x4C40-0x4C7F, ext bit 10
#   MOVEP, CMP2, CHK2, CAS2    (and a misaligned CAS, which no static scan sees)
#
# Amix has no 060 integer-emulation package, so the kernel SIGKILLs the
# process: "u_trap WARNING: SIGKILL sent to pid N (...) because of vector
# 0xF4".  On 2026-10-05 that killed /usr/apkg/bin/installf on an emulated
# LC060 first boot (amix-installng cd1-emu): the APKGENG-1.12.0 published on
# pkg.amigaux.org is the 2026-07-05 mint, built before gcc-cross-amix 984192a,
# when GNU as 2.8.1 assembled gcc's SGS "tdivs.l" (32-bit remainder divide) as
# the 64-bit-dividend DIVS.L.  NOTES.md 2026-10-05.
#
# The decision is made from the ENCODING, never the mnemonic: binutils spells
# the 64-bit divide "divsl" and the 32-bit remainder divide "divsll", and the
# 2.8.1-era objdump spells both forms with commas, so a mnemonic or colon grep
# is wrong in one direction or the other.  (Same rule as amix-kerntools'
# scan060.py, which this re-implements for whole binaries and datastreams.)
#
# BLINDNESS.  objdump disassembles .text linearly; a jump table or literal in
# .text could decode as one of these words.  Every hit is printed with its
# address and enclosing symbol so it can be checked by hand.  A CAS on a
# misaligned operand traps on the 060 too and cannot be seen statically.
# ---------------------------------------------------------------------------

import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PKGTRANS_DEFAULT = os.path.join(REPO, "heirloom", "build-host", "bin",
                                "pkgtrans")
ELF_MAGIC = b"\x7fELF"
VENDOR_DIRS = ("stock/",)
INCLUDE_STOCK = False

LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{4} )+)\s*(\S+)\s*(.*)$")
SYM = re.compile(r"^([0-9a-f]+) <([^>]+)>:\s*$")
MNEM_OTHER = re.compile(r"^(movep|cmp2|chk2|cas2)")


def pkgtrans_tool():
    """AMIX_PKGTRANS when set, else this tree's host build; exits if absent."""
    env = os.environ.get("AMIX_PKGTRANS", "")
    if env:
        if not (os.path.isfile(env) and os.access(env, os.X_OK)):
            raise SystemExit("scan060: AMIX_PKGTRANS=%s is not an executable"
                             % env)
        return env
    if not os.path.isfile(PKGTRANS_DEFAULT):
        raise SystemExit("scan060: %s missing -- run heirloom/build-host.sh "
                         "or set AMIX_PKGTRANS" % PKGTRANS_DEFAULT)
    return PKGTRANS_DEFAULT


def objdump_tool():
    for t in ("m68k-linux-gnu-objdump", "m68k-elf-objdump",
              "m68k-cbm-sysv4-objdump"):
        p = shutil.which(t)
        if p:
            return p
    print("scan060: no m68k objdump on PATH (m68k-linux-gnu-objdump, or "
          "source gcc-cross-amix/build/env.sh)", file=sys.stderr)
    raise SystemExit(1)


def classify(hexwords, mnem):
    """-> reason string for a 060-unimplemented instruction, or None."""
    if MNEM_OTHER.match(mnem):
        return "%s (not implemented on the 060)" % mnem
    if len(hexwords) < 2:
        return None
    op = int(hexwords[0], 16)
    ext = int(hexwords[1], 16)
    if not (0x4C00 <= op <= 0x4C7F):
        return None
    if not (ext & 0x0400):          # SIZE clear: 32-bit form, fine on the 060
        return None
    return "64-bit product" if op < 0x4C40 else "64-bit dividend"


def scan_listing(text):
    """-> (decoded_lines, [(addr, symbol, mnem, ops, why)])"""
    hits, total, sym = [], 0, "?"
    for raw in text.splitlines():
        s = SYM.match(raw)
        if s:
            sym = s.group(2)
            continue
        m = LINE.match(raw)
        if not m:
            continue
        total += 1
        why = classify(m.group(2).split(), m.group(3))
        if why:
            hits.append((m.group(1), sym, m.group(3), m.group(4).strip(), why))
    return total, hits


def is_m68k(data):
    """ELF32 big-endian, e_machine EM_68K (4)."""
    return (len(data) >= 20 and data[4] == 1 and data[5] == 2
            and struct.unpack(">H", data[18:20])[0] == 4)


def exec_sections(data):
    """ELF32 big-endian -> [(addr, file_offset, size)] of SHF_EXECINSTR."""
    shoff = struct.unpack(">I", data[32:36])[0]
    shentsize, shnum = struct.unpack(">HH", data[46:50])
    out = []
    for i in range(shnum):
        sh = data[shoff + i * shentsize: shoff + (i + 1) * shentsize]
        _n, typ, flags, addr, off, size = struct.unpack(">IIIIII", sh[:24])
        if typ == 1 and flags & 0x4 and size:          # PROGBITS, EXECINSTR
            out.append((addr, off, size))
    return out


# gcc's switch dispatch: "jmp %pc@(T,%dN:w)" (4efb), a word table at T of
# signed offsets from T.  The table is DATA inside .text; decoded linearly it
# reads as movep/andi/bset noise -- every movep hit in the first cut of this
# tool was a table entry (0x010a = a +266 offset).  Stock PLT stubs are
# "jmp %pc@(...)@(0)" (4efb 0171) and are not tables.
JMPTAB = re.compile(r"^\s*([0-9a-f]+):\s+4efb [0-9a-f]{4} \s*jmp\s+"
                    r"%pc@\((?:0x)?([0-9a-f]+)\b[^)]*,%d[0-7]:w\)\s*$")


def table_ranges(listing, data, secs):
    """-> [(start, end)] data ranges: dispatch tail + table, per jmp."""
    def word_at(a):
        for sa, so, sz in secs:
            if sa <= a and a + 2 <= sa + sz:
                return struct.unpack(">h", data[so + a - sa: so + a - sa + 2])[0]
        return None
    out = []
    for raw in listing.splitlines():
        m = JMPTAB.match(raw)
        if not m:
            continue
        jmp, t = int(m.group(1), 16), int(m.group(2), 16)
        if not (jmp < t <= jmp + 64):
            continue
        end, a, n = None, t, 0
        while n < 8192 and (end is None or a < end):
            w = word_at(a)
            if w is None:
                break
            if w > 0 and (end is None or t + w < end):
                end = t + w
            a += 2
            n += 1
        if end is not None and end > t:
            out.append((jmp + 4, end))
    return out


def run_objdump(objdump, path, lo=None, hi=None):
    cmd = [objdump, "-d", "-m", "m68k:68020"]
    if lo is not None:
        cmd += ["--start-address=0x%x" % lo, "--stop-address=0x%x" % hi]
    r = subprocess.run(cmd + [path], capture_output=True, text=True,
                       errors="replace")
    if r.returncode != 0:
        raise SystemExit("scan060: objdump failed on %s: %s"
                         % (path, r.stderr.strip()[:160]))
    return r.stdout


def scan_elf(path, objdump):
    """-> (decoded_lines, hits, n_tables_skipped)

    Whole-file listing first; then, if switch tables were found, re-decode
    only the code BETWEEN them (so the stream re-synchronises after each
    table) and repeat until no new table turns up.
    """
    with open(path, "rb") as fp:
        data = fp.read()
    secs = exec_sections(data)
    listing = run_objdump(objdump, path)
    skip = set(table_ranges(listing, data, secs))
    for _round in range(6):
        if not skip:
            break
        listing = ""
        for sa, _so, sz in secs:
            lo, hi = sa, sa + sz
            for s, e in sorted(r for r in skip if sa <= r[0] < hi):
                if s > lo:
                    listing += run_objdump(objdump, path, lo, s)
                lo = max(lo, e)
            if lo < hi:
                listing += run_objdump(objdump, path, lo, hi)
        new = set(table_ranges(listing, data, secs)) - skip
        if not new:
            break
        skip |= new
    total, hits = scan_listing(listing)
    return total, hits, len(skip)


def datastream_pkginst(path):
    with open(path, "rb") as fp:
        lines = fp.read(512).split(b"\n")
    if len(lines) < 2 or not lines[0].startswith(b"# PaCkAgE DaTaStReAm"):
        raise SystemExit("scan060: %s: not an SVR4 datastream" % path)
    return lines[1].split()[0].decode("ascii")


def walk_elfs(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for f in sorted(filenames):
            full = os.path.join(dirpath, f)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            with open(full, "rb") as fp:
                if is_m68k(fp.read(20)):
                    yield full


def targets_of(path, tmpdirs):
    """-> [(label, elf_path)] for one command-line argument."""
    out = []
    if os.path.isdir(path):
        for e in walk_elfs(path):
            out.append((os.path.relpath(e, path), e))
        for dirpath, dirnames, filenames in os.walk(path):
            dirnames.sort()
            for f in sorted(filenames):
                if not f.endswith(".pkg"):
                    continue
                pk = os.path.join(dirpath, f)
                rel = os.path.relpath(pk, path).replace(os.sep, "/")
                if not INCLUDE_STOCK and rel.startswith(VENDOR_DIRS):
                    continue
                out += [("%s!%s" % (rel, l), e)
                        for l, e in targets_of(pk, tmpdirs)]
        return out
    with open(path, "rb") as fp:
        head = fp.read(32)
    if head.startswith(ELF_MAGIC):
        if not is_m68k(head):
            print("scan060: %s: not an m68k ELF, skipped" % path)
            return []
        return [(os.path.basename(path), path)]
    if head.startswith(b"# PaCkAgE DaTaStReAm"):
        pkgtrans = pkgtrans_tool()
        tmp = tempfile.mkdtemp(prefix="scan060.")
        tmpdirs.append(tmp)
        subprocess.run([pkgtrans, "-o", path, tmp, datastream_pkginst(path)],
                       capture_output=True, text=True, timeout=600)
        if not os.listdir(tmp):
            raise SystemExit("scan060: %s: pkgtrans unpacked nothing" % path)
        return [(os.path.relpath(e, tmp), e) for e in walk_elfs(tmp)]
    return []


def self_test():
    """Prove the detector fires, on bytes objdump really decodes."""
    objdump = objdump_tool()
    cases = [
        ("4c6e1c020010", True,  "divs.l 16(fp),d2:d1 (the installf trap)"),
        ("4c6e18020010", False, "divsl.l 16(fp),d2:d1 (32-bit remainder)"),
        ("4c3c040100000005", True, "mulu.l #5,d1:d0 (64-bit product)"),
        ("4c3c000100000005", False, "mulu.l #5,d0 (32-bit product)"),
        ("4c410000", False, "divu.l d1,d0 (32-bit)"),
        ("01080000", True,  "movep.w 0(a0),d0"),
        ("4e71", False, "nop"),
    ]
    ok = True
    with tempfile.TemporaryDirectory(prefix="scan060-st.") as tmp:
        for hexs, want, what in cases:
            b = os.path.join(tmp, "probe.bin")
            with open(b, "wb") as fp:
                fp.write(bytes.fromhex(hexs))
            r = subprocess.run([objdump, "-D", "-b", "binary", "-m",
                                "m68k:68020", b],
                               capture_output=True, text=True)
            total, hits = scan_listing(r.stdout)
            got = bool(hits)
            res = "ok" if (got == want and total) else "FAIL"
            if res == "FAIL":
                ok = False
            print("  %-4s %-44s -> %s" % (res, what,
                  hits[0][4] if hits else "clean"))
    print("self-test: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 2


def main(argv):
    global INCLUDE_STOCK
    if "--self-test" in argv:
        return self_test()
    INCLUDE_STOCK = "--include-stock" in argv
    paths = [a for a in argv if not a.startswith("-")]
    if not paths:
        print("usage: scan060.py [--include-stock] <elf|pkg|dir> [...]",
              file=sys.stderr)
        return 1
    objdump = objdump_tool()
    rc, n_elf, n_hit = 0, 0, 0
    tmpdirs = []
    try:
        for p in paths:
            label = os.path.basename(p.rstrip("/"))
            elfs = targets_of(p, tmpdirs)
            if not elfs:
                print("scan060: %s: NOTHING INSPECTED -- no ELF found; that "
                      "is not a pass" % label)
                rc = 2
                continue
            for rel, e in elfs:
                total, hits, ntab = scan_elf(e, objdump)
                n_elf += 1
                verdict = "CLEAN" if not hits else "HITS %d" % len(hits)
                print("  %-9s %s!%s (%d insns, %d switch tables skipped)"
                      % (verdict, label, rel, total, ntab))
                for addr, sym, mnem, ops, why in hits:
                    print("      %s <%s> %s %s  -- %s"
                          % (addr, sym, mnem, ops, why))
                if hits:
                    n_hit += 1
                    rc = 2
    finally:
        for t in tmpdirs:
            shutil.rmtree(t, ignore_errors=True)
    print("scan060: %d ELF(s) inspected, %d with 060-unimplemented integer "
          "instructions" % (n_elf, n_hit))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
