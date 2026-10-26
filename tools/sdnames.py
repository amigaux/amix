#!/usr/bin/env python3
"""sdnames.py -- a 1.1 profile's controller numbers under a four-card install kernel.

    tools/sdnames.py PROFILE --sdcards N        the override lines for the staged copy
    tools/sdnames.py --sidecar FILE             the sd cards a kernel sidecar declares
    tools/sdnames.py --datastream PKG --line L  ... the one inside a kernel package (stand/L/kabi)
    tools/sdnames.py --manifest FILE            ... a kerntools chain's MANIFEST.json
    tools/sdnames.py --self-test

amix-dlm contract C4-1. A two-card kernel numbers the sd cards by base address (the 1.0
order); a four-card kernel (sidecar `sdcards=4`, absent = 2; a chain's MANIFEST.json the
same key) by rank class -- z3660 < zorro < mobo < ide -- then base. A profile keeps its
two-card values: TARGET_SCSI_ID (card*8 + unit, hex), CD_SPEC (card,unit) and ROOTDEV
(sd block major 18 << 18 | minor). Its physical facts say what the rig carries:
  SD_BOARDS  the disk controllers, in base order: a3000 a4000t gayle z3660scsi a2090
             a2091 a4091 a4092
  TARGET_HBA the target's controller, CD_HBA the install CD's (SOURCE_KIND=cdfs).
With N=4 the cards are derived again and every value that moves is printed as KEY=VALUE
under a comment, for build-install-iso.sh to append to the staged profile (the last
assignment wins when the profile is sourced). With N=2 nothing is printed. The units do
not move, only the cards.
"""
import json
import re
import sys

CLASS = {"z3660scsi": 1, "a4091": 2, "a4092": 2, "a2091": 2, "a2090": 2,
         "a3000": 3, "a4000t": 3, "gayle": 4}
SD_BMAJ = 18


def die(msg):
    sys.stderr.write("sdnames: %s\n" % msg)
    sys.exit(2)


def read_profile(path):
    kv = {}
    for line in open(path, encoding="latin-1"):
        m = re.match(r'^([A-Z][A-Z0-9_]*)=(.*)$', line.rstrip("\n"))
        if m:
            kv[m.group(1)] = m.group(2).strip().strip('"')
    return kv


def sidecar_cards(text):
    n = 2
    for line in text.splitlines():
        if line.startswith("sdcards="):
            n = int(line.split("=", 1)[1])
    if n not in (2, 4):
        die("sdcards=%d is not 2 or 4" % n)
    return n


def datastream_sidecar(path, line):
    """The text of stand/<line>/kabi inside a kernel package datastream (newc cpio)."""
    d = open(path, "rb").read()
    want = ("stand/%s/kabi" % line).encode()
    i = d.find(b"070701")
    while i >= 0:
        h = d[i:i + 110]
        try:
            size, nsz = int(h[54:62], 16), int(h[94:102], 16)
        except ValueError:
            i = d.find(b"070701", i + 6)
            continue
        name = d[i + 110:i + 110 + nsz - 1]
        off = (i + 110 + nsz + 3) & ~3
        if name.endswith(want):
            return d[off:off + size].decode("latin-1")
        i = d.find(b"070701", off + size)
    die("%s carries no %s" % (path, want.decode()))


def order(boards, cards):
    """The sd card order: the boards as listed (base order) for 2, by class then base for 4."""
    for b in boards:
        if b not in CLASS:
            die("SD_BOARDS names an unknown controller %r" % b)
    if len(boards) > 4:
        die("SD_BOARDS names %d controllers; the sd layer keeps four" % len(boards))
    if cards == 2:
        return list(boards)
    return sorted(boards, key=lambda b: (CLASS[b], boards.index(b)))


def derive(kv, cards):
    """[(key, value)] for every value that moves under `cards`; [] for 2."""
    if cards == 2:
        return []
    boards = kv.get("SD_BOARDS", "").split()
    if not boards:
        die("a four-card install kernel, and the profile names no SD_BOARDS")
    two, four = order(boards, 2), order(boards, 4)
    hba = kv.get("TARGET_HBA", "")
    if hba not in boards:
        die("TARGET_HBA=%s is not in SD_BOARDS (%s)" % (hba, " ".join(boards)))
    tid = int(kv["TARGET_SCSI_ID"], 16)
    if tid // 8 != two.index(hba):
        die("TARGET_SCSI_ID=%s is not card %d of SD_BOARDS' base order" % (kv["TARGET_SCSI_ID"], two.index(hba)))
    unit = tid % 8
    out = []
    nid = four.index(hba) * 8 + unit
    if nid != tid:
        out.append(("TARGET_SCSI_ID", "%x" % nid))
    if kv.get("SOURCE_KIND") == "cdfs" and kv.get("CD_SPEC"):
        chba = kv.get("CD_HBA", "")
        if chba not in boards:
            die("CD_HBA=%s is not in SD_BOARDS (%s)" % (chba, " ".join(boards)))
        cc, cu = (int(x) for x in kv["CD_SPEC"].split(","))
        if cc != two.index(chba):
            die("CD_SPEC=%s is not card %d of SD_BOARDS' base order" % (kv["CD_SPEC"], two.index(chba)))
        ncd = "%d,%d" % (four.index(chba), cu)
        if ncd != kv["CD_SPEC"]:
            out.append(("CD_SPEC", ncd))
    if kv.get("ROOTDEV"):
        sl = int(kv.get("TARGET_ROOT_SLICE") or 1)
        minor = lambda n: sl * 16 + n % 16 + (128 if n >= 16 else 0)
        if int(kv["ROOTDEV"], 16) != (SD_BMAJ << 18 | minor(tid)):
            die("ROOTDEV=%s is not slice %d of TARGET_SCSI_ID=%s" % (kv["ROOTDEV"], sl, kv["TARGET_SCSI_ID"]))
        nrd = "0x%08x" % (SD_BMAJ << 18 | minor(nid))
        if nrd != kv["ROOTDEV"].lower():
            out.append(("ROOTDEV", nrd))
    return out


def self_test():
    fails = 0

    def t(what, got, want):
        nonlocal fails
        print("  %s  %s" % ("OK  " if got == want else "FAIL", what if got == want else "%s: %r, want %r" % (what, got, want)))
        fails += got != want
    k30 = {"SD_BOARDS": "a3000 a4091", "TARGET_HBA": "a3000", "CD_HBA": "a4091", "SOURCE_KIND": "cdfs",
           "TARGET_SCSI_ID": "6", "CD_SPEC": "1,3", "ROOTDEV": "0x00480016", "TARGET_ROOT_SLICE": "1"}
    t("two-card kernel: nothing moves", derive(k30, 2), [])
    t("four-card kernel, WD + A4091: the WD is card 1 (ced0), the A4091 card 0 (CD 0,3), rootdev minor 0x1e",
      derive(k30, 4), [("TARGET_SCSI_ID", "e"), ("CD_SPEC", "0,3"), ("ROOTDEV", "0x0048001e")])
    k46 = {"SD_BOARDS": "z3660scsi", "TARGET_HBA": "z3660scsi", "CD_HBA": "z3660scsi", "SOURCE_KIND": "cdfs",
           "TARGET_SCSI_ID": "6", "CD_SPEC": "0,2", "ROOTDEV": "0x00480016", "TARGET_ROOT_SLICE": "1"}
    t("four-card kernel, the Z3660 alone: nothing moves", derive(k46, 4), [])
    two = {"SD_BOARDS": "z3660scsi a4091", "TARGET_HBA": "a4091", "CD_HBA": "z3660scsi", "SOURCE_KIND": "cdfs",
           "TARGET_SCSI_ID": "9", "CD_SPEC": "0,2"}
    t("four-card kernel, Z3660 + A4091 (a set of record): the 1.0 names hold", derive(two, 4), [])
    four = {"SD_BOARDS": "a3000 gayle z3660scsi a4091", "TARGET_HBA": "gayle", "TARGET_SCSI_ID": "e"}
    t("four-card kernel, four controllers: gayle (class 4) is card 3 -> c1e", derive(four, 4), [("TARGET_SCSI_ID", "1e")])
    t("sidecar: sdcards=4", sidecar_cards("kabi=k30.1.0\nsdcards=4\n"), 4)
    t("sidecar: absent = 2", sidecar_cards("kabi=k30.1.0\n"), 2)
    t("manifest: sdcards=4", json.loads('{"sdcards": 4}').get("sdcards", 2), 4)
    print("sdnames self-test: %s" % ("PASS" if not fails else "FAILED -- %d" % fails))
    return 1 if fails else 0


def main(argv):
    if argv[:1] == ["--self-test"]:
        return self_test()
    if argv[:1] == ["--sidecar"]:
        print(sidecar_cards(open(argv[1], encoding="latin-1").read()))
        return 0
    if argv[:1] == ["--datastream"] and argv[2:3] == ["--line"]:
        print(sidecar_cards(datastream_sidecar(argv[1], argv[3])))
        return 0
    if argv[:1] == ["--manifest"]:
        n = json.load(open(argv[1])).get("sdcards", 2)
        if n not in (2, 4):
            die("%s: sdcards=%r is not 2 or 4" % (argv[1], n))
        print(n)
        return 0
    if len(argv) == 3 and argv[1] == "--sdcards":
        cards = int(argv[2])
        if cards not in (2, 4):
            die("--sdcards %d is not 2 or 4" % cards)
        moves = derive(read_profile(argv[0]), cards)
        if moves:
            print("# C4-1 (build-install-iso.sh, tools/sdnames.py): the install kernel is four-card;")
            print("# its class order (z3660 < zorro < mobo < ide, then base) moves these names")
            for k, v in moves:
                print("%s=%s" % (k, v))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
