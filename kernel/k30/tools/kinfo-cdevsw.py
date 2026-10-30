#!/usr/bin/env python3
"""kinfo-cdevsw.py -- register /dev/kinfo (src/kinfo030.c) in cdevsw[53] of a linked 030 ET_REL kernel (C2-1 §1).

    kinfo-cdevsw.py KERNEL [MAJOR]           (MAJOR defaults to 53)
    kinfo-cdevsw.py --check KERNEL [MAJOR]   exit 0 registered, 1 free, 2 anything else
    kinfo-cdevsw.py --selftest

The port's src/patch_kinfo_cdevsw.py (amix-040-060-port e65247a) for the classic 030 kit, whose stock
master.d/kernel.c keeps `nullflag` static: a row's d_flag is a relocation to .data plus an addend, not to a
named symbol. So a free row here is: its ten function records R_68K_32 relocations to `nodev`; d_ttys (+0x28)
and d_str (+0x2c) NULL words with no relocation; d_flag the same relocation (symbol and addend) as the table's
last row, itself a filler row. Anything else is somebody else's driver and the answer is to stop. kinfo has
open, close, read and write (write answers EPERM); the other six stay `nodev`. The four retargets are one
write; idempotent; fails closed on any mismatch. Run after the final `ld -r`, before elf2brel.
"""
import struct, sys

R_68K_32 = 1
ENTSIZE = 52                     # sizeof(struct cdevsw), usr/include/sys/conf.h: 13 words
NFREE = 10                       # records that must read `nodev` in a free row
FIELDS = {0: "kinfoopen", 1: "kinfoclose", 2: "kinforead", 3: "kinfowrite"}   # d_open..d_write


def u16(b, o): return struct.unpack(">H", b[o:o + 2])[0]
def u32(b, o): return struct.unpack(">I", b[o:o + 4])[0]


class Kernel:
    def __init__(self, path):
        self.path = path
        b = self.b = bytearray(open(path, "rb").read())
        e_shoff, e_shentsize, e_shnum, e_shstrndx = u32(b, 32), u16(b, 46), u16(b, 48), u16(b, 50)
        sh = []
        for i in range(e_shnum):
            o = e_shoff + i * e_shentsize
            sh.append(dict(name=u32(b, o), offset=u32(b, o + 16), size=u32(b, o + 20),
                           link=u32(b, o + 24), entsize=u32(b, o + 36)))
        shstr = sh[e_shstrndx]["offset"]
        self.sec = {self.cstr(shstr + s["name"]): s for s in sh}
        st = self.sec[".symtab"]
        self.so, self.se, self.stroff = st["offset"], st["entsize"], sh[st["link"]]["offset"]
        self.index = {}
        for i in range(st["size"] // self.se):
            o = self.so + i * self.se
            if u16(b, o + 14) != 0:                # defined symbols only
                self.index.setdefault(self.symname(i), i)
        self.data = self.sec[".data"]["offset"]
        r = self.sec[".rela.data"]
        self.ro, self.re = r["offset"], r["entsize"]
        self.rn = r["size"] // self.re

    def cstr(self, o):
        return self.b[o:self.b.index(b"\0", o)].decode("latin-1")

    def symname(self, i):
        return self.cstr(self.stroff + u32(self.b, self.so + i * self.se))

    def sym(self, name):
        if name not in self.index:
            raise SystemExit("ABORT: symbol %s not defined in %s (was kinfo030.o linked in?)" % (name, self.path))
        return self.index[name]

    def value(self, name):
        return u32(self.b, self.so + self.sym(name) * self.se + 4)

    def relocs(self, lo, hi):
        """{.data offset: .rela.data record offset} for the records inside [lo, hi)"""
        at = {}
        for i in range(self.rn):
            o = self.ro + i * self.re
            if lo <= u32(self.b, o) < hi:
                at[u32(self.b, o)] = o
        return at


def row(k, major):
    """(record offsets by field, the row's .data offset); fails closed on a missing or odd record"""
    slot = k.value("cdevsw") + major * ENTSIZE
    at = k.relocs(slot, slot + ENTSIZE)
    for f in list(range(NFREE)) + [12]:
        off = slot + f * 4
        if off not in at:
            raise SystemExit("ABORT: no .rela.data record at cdevsw[%d] field %d (.data+0x%x)" % (major, f, off))
        if u32(k.b, at[off] + 4) & 0xff != R_68K_32:
            raise SystemExit("ABORT: cdevsw[%d] field %d: reloc type %d, not R_68K_32"
                             % (major, f, u32(k.b, at[off] + 4) & 0xff))
    return at, slot


def target(k, at, slot, f):
    o = at[slot + f * 4]
    return k.symname(u32(k.b, o + 4) >> 8), u32(k.b, o + 8)


def patch(path, major=53, check=False, out=print):
    k = Kernel(path)
    cdevcnt = u32(k.b, k.data + k.value("cdevcnt"))
    span = k.value("cdevcnt") - k.value("cdevsw")
    if span != cdevcnt * ENTSIZE:
        raise SystemExit("ABORT: cdevcnt %d but the table spans %d bytes" % (cdevcnt, span))
    if not 0 < major < cdevcnt - 1:
        raise SystemExit("ABORT: major %d outside cdevsw[1..%d)" % (major, cdevcnt - 1))
    out("  cdevcnt %d (the table's own size); row %d below it" % (cdevcnt, major))
    at, slot = row(k, major)
    lat, lslot = row(k, cdevcnt - 1)
    if any(target(k, lat, lslot, f) != ("nodev", 0) for f in range(NFREE)):
        raise SystemExit("ABORT: the reference row cdevsw[%d] is not a filler row" % (cdevcnt - 1))
    nullflag = target(k, lat, lslot, 12)
    bad = []
    for f, what in ((10, "d_ttys"), (11, "d_str")):
        off = slot + f * 4
        if off in at:
            bad.append("%s -> %s" % (what, target(k, at, slot, f)[0]))
        elif u32(k.b, k.data + off) != 0:
            bad.append("%s = 0x%x" % (what, u32(k.b, k.data + off)))
    if target(k, at, slot, 12) != nullflag:
        bad.append("d_flag -> %s+0x%x, not the filler's %s+0x%x" % (target(k, at, slot, 12) + nullflag))
    names = [target(k, at, slot, f) for f in range(NFREE)]
    ours = all(names[f] == (n, 0) for f, n in FIELDS.items())
    rest = [names[f] for f in range(NFREE) if f not in FIELDS or not ours]
    if bad or any(t != ("nodev", 0) for t in rest):
        raise SystemExit("ABORT: cdevsw[%d] is neither free nor kinfo's: %s %s"
                         % (major, ["%s+0x%x" % t for t in names], bad))
    if ours:
        out("[fixed] kinfo registered in cdevsw[%d] of %s" % (major, path) if check
            else "kinfo already registered (cdevsw[%d]) in %s" % (major, path))
        return 0
    out("  cdevsw[%d] free: ten nodev, d_ttys/d_str NULL, d_flag the filler's %s+0x%x" % ((major,) + nullflag))
    if check:
        out("[stock] cdevsw[%d] of %s is free: kinfo not registered" % (major, path))
        return 1
    for f, n in sorted(FIELDS.items()):
        o = at[slot + f * 4]
        struct.pack_into(">II", k.b, o + 4, (k.sym(n) << 8) | R_68K_32, 0)
        out("  [ok]   cdevsw[%d] field %d @.data+0x%x  nodev -> %s (.text+0x%x)" % (major, f, slot + f * 4, n, k.value(n)))
    open(path, "wb").write(k.b)
    out("kinfo registered (cdevsw[%d], major %d) -> %s" % (major, major, path))
    return 0


def selftest():
    """a synthetic ET_REL: .data with a 4-row table and cdevcnt, .rela.data, .symtab, .strtab"""
    import os, tempfile
    print("kinfo-cdevsw selftest")
    n = f = 0

    def check(name, c):
        nonlocal n, f
        n += 1
        f += 0 if c else 1
        print("  %s %s" % ("ok  " if c else "FAIL", name))

    def build(rows, path, cnt=None):
        names = ["", "nodev", "cdevsw", "cdevcnt", ".data", "kinfoopen", "kinfoclose", "kinforead", "kinfowrite", "zzopen"]
        strtab = b"\0"
        off = {}
        for s in names[1:]:
            off[s] = len(strtab); strtab += s.encode() + b"\0"
        # symbols: 0 null, 1 nodev(.text 1), 2 cdevsw(.data 2), 3 cdevcnt, 4 .data section, 5.. kinfo*, zzopen
        syms = [(0, 0, 0)] + [(off["nodev"], 0x100, 1), (off["cdevsw"], 0, 2), (off["cdevcnt"], len(rows) * 52, 2),
                              (0, 0, 2)] + [(off[s], 0x200 + 4 * i, 1) for i, s in enumerate(names[5:])]
        data = bytearray(len(rows) * 52 + 4 + 8)
        struct.pack_into(">I", data, len(rows) * 52, cnt if cnt is not None else len(rows))
        rela = b""
        for r, kind in enumerate(rows):
            base = r * 52
            for fl in range(10):
                tgt = 9 if (kind == "zz" and fl == 0) else 1
                rela += struct.pack(">IIi", base + fl * 4, (tgt << 8) | 1, 0)
            if kind == "str":
                rela += struct.pack(">IIi", base + 44, (4 << 8) | 1, len(rows) * 52 + 4)
            rela += struct.pack(">IIi", base + 48, (4 << 8) | 1, len(rows) * 52 + 8 if kind != "flag" else 0)
        symtab = b"".join(struct.pack(">IIIBBH", nm, v, 0, 0, 0, sh) for nm, v, sh in syms)
        shstr = b"\0.text\0.data\0.rela.data\0.symtab\0.strtab\0.shstrtab\0"
        text = bytes(0x300)
        blobs = [text, bytes(data), rela, symtab, strtab, shstr]
        o = 52
        offs = []
        for x in blobs:
            offs.append(o); o += len(x)
        shoff = o
        hdr = bytearray(52)
        hdr[0:4] = b"\x7fELF"
        struct.pack_into(">IHHH", hdr, 32, shoff, 0, 0, 0)
        struct.pack_into(">HHHH", hdr, 44, 0, 40, 7, 6)
        # sections: 0 null, 1 .text, 2 .data, 3 .rela.data, 4 .symtab (link 5), 5 .strtab, 6 .shstrtab
        nm = {".text": 1, ".data": 7, ".rela.data": 13, ".symtab": 24, ".strtab": 32, ".shstrtab": 40}
        sh = bytes(40)
        for i, (s, link, ent) in enumerate(((".text", 0, 0), (".data", 0, 0), (".rela.data", 4, 12),
                                             (".symtab", 5, 16), (".strtab", 0, 0), (".shstrtab", 0, 0))):
            sh += struct.pack(">IIIIIIIIII", nm[s], 1, 0, 0, offs[i], len(blobs[i]), link, 0, 0, ent)
        open(path, "wb").write(bytes(hdr) + b"".join(blobs) + sh)

    d = tempfile.mkdtemp()
    p = os.path.join(d, "unix")
    quiet = lambda s: None
    build(["fill", "fill", "fill", "fill"], p)
    check("a free row: --check says free (1)", patch(p, 2, check=True, out=quiet) == 1)
    before = open(p, "rb").read()
    check("patch registers it (0)", patch(p, 2, out=quiet) == 0)
    after = open(p, "rb").read()
    check("only the four records' info/addend words change", sum(x != y for x, y in zip(before, after)) <= 16
          and len(before) == len(after))
    check("--check after the patch: registered (0)", patch(p, 2, check=True, out=quiet) == 0)
    check("a second patch is a no-op", patch(p, 2, out=quiet) == 0 and open(p, "rb").read() == after)
    for kind, why in (("zz", "a driver's open in the row"), ("str", "a d_str in the row"), ("flag", "another d_flag")):
        build(["fill", "fill", kind, "fill"], p)
        try:
            patch(p, 2, out=quiet); ok = False
        except SystemExit as x:
            ok = "ABORT" in str(x.code)
        check("refused: %s" % why, ok and patch.__name__)
    build(["fill", "fill", "fill", "fill"], p, cnt=5)
    try:
        patch(p, 2, out=quiet); ok = False
    except SystemExit as x:
        ok = "cdevcnt" in str(x.code)
    check("refused: cdevcnt disagrees with the table's span", ok)
    print("kinfo-cdevsw: %d checks, %d failed" % (n, f))
    print("kinfo-cdevsw: SELFTEST PASS" if f == 0 else "kinfo-cdevsw: SELFTEST FAIL")
    return 0 if f == 0 else 1


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    check = argv[:1] == ["--check"]
    if check:
        argv = argv[1:]
    if not 1 <= len(argv) <= 2:
        raise SystemExit("usage: kinfo-cdevsw.py [--check] KERNEL [MAJOR] | --selftest")
    try:
        return patch(argv[0], int(argv[1]) if len(argv) > 1 else 53, check)
    except SystemExit as x:
        if check and isinstance(x.code, str):
            print(x.code)
            return 2
        raise


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
