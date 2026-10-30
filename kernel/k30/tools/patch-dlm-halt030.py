#!/usr/bin/env python3
# patch-dlm-halt030.py -- the k30 module kernel's halt-pass hook (S4-21; kernel/dlm core patch 0030, spec 30 sec 2
# patch 11): mdboot calls dlm_halt() immediately before its haltsys and before its rtnfirm.
#
#   patch-dlm-halt030.py ETREL            retarget; idempotent ([skip] when already done)
#   patch-dlm-halt030.py --check ETREL    verify a finished kernel carries the hook; writes nothing
#
# THE EDIT.  Two relocation words, no instruction byte.  On the k30 base, uadmin's A_SHUTDOWN and A_REBOOT reach
# mdboot (os/exp, a pre-linked stock blob without source), which calls haltsys(0) for fcn 0 and rtnfirm()
# otherwise; each is `jsr <abs>.l` whose operand an R_68K_32 fills.  The relocation's symbol index is changed from
# haltsys to dlm_halt_haltsys and from rtnfirm to dlm_halt_rtnfirm (tools/dlm-halt030.s: `jsr dlm_halt` then `jmp`
# to the stock routine, the caller's frame and argument untouched).  haltsys and rtnfirm themselves are NOT
# changed: xpanic and xcmn_err reach rtnfirm, and the keyboard-reset path (screen.c) reaches haltsys, and those
# must not run module code.
#
# Asserted before anything is written: the ET_REL defines mdboot, dlm_halt and both shims; inside mdboot exactly
# one R_68K_32 names haltsys (or, already patched, dlm_halt_haltsys) and exactly one names rtnfirm (or
# dlm_halt_rtnfirm), each with addend 0 on the operand of a `jsr <abs>.l` (4eb9).

import struct, sys

PAIRS = (("haltsys", "dlm_halt_haltsys"), ("rtnfirm", "dlm_halt_rtnfirm"))
CALLER, CORE = "mdboot", "dlm_halt"
R_68K_32 = 1


def die(msg):
    sys.stderr.write("patch-dlm-halt030: %s\n" % msg)
    sys.exit(1)


class Elf:
    def __init__(self, path):
        self.path = path
        self.b = bytearray(open(path, "rb").read())
        b = self.b
        if b[:4] != b"\x7fELF" or b[4] != 1 or b[5] != 2:
            die("%s: not a 32-bit big-endian ELF" % path)
        if struct.unpack(">H", b[16:18])[0] != 1:
            die("%s: not an ET_REL" % path)
        shoff, = struct.unpack(">I", b[32:36])
        shentsize, shnum, shstrndx = struct.unpack(">HHH", b[46:52])
        self.sh = []
        for i in range(shnum):
            o = shoff + i * shentsize
            name, typ, _, _, off, size, link, info, _, entsize = struct.unpack(">IIIIIIIIII", b[o:o + 40])
            self.sh.append(dict(name=name, type=typ, off=off, size=size, link=link, info=info, entsize=entsize))
        so = self.sh[shstrndx]["off"]
        for s in self.sh:
            s["n"] = self.cstr(so + s["name"])
        st = [i for i, s in enumerate(self.sh) if s["type"] == 2]
        if len(st) != 1:
            die("%s: %d symbol tables" % (path, len(st)))
        self.symsec = self.sh[st[0]]
        self.stroff = self.sh[self.symsec["link"]]["off"]
        self.syms = []
        for i in range(self.symsec["size"] // 16):
            o = self.symsec["off"] + i * 16
            name, value, size, info, other, shndx = struct.unpack(">IIIBBH", b[o:o + 16])
            self.syms.append(dict(name=self.cstr(self.stroff + name), value=value, size=size, info=info, shndx=shndx))

    def cstr(self, o):
        e = self.b.index(b"\0", o)
        return self.b[o:e].decode("latin-1")

    def defined(self, name):
        hits = [i for i, s in enumerate(self.syms) if s["name"] == name and s["shndx"] not in (0, 0xFFF1, 0xFFF2)]
        return hits

    def index_of(self, name):
        """the one global (or the one) symbol index of a defined name"""
        hits = self.defined(name)
        g = [i for i in hits if self.syms[i]["info"] >> 4 != 0]
        if len(g) == 1:
            return g[0]
        if len(hits) == 1:
            return hits[0]
        die("%s: %d definitions of %s" % (self.path, len(hits), name))

    def extent(self, name):
        """[lo, hi) of a .text function: up to the next symbol in its section with a higher value"""
        i = self.index_of(name)
        s = self.syms[i]
        lo, sec = s["value"], s["shndx"]
        hi = min([t["value"] for t in self.syms if t["shndx"] == sec and t["value"] > lo]
                 + [self.sh[sec]["size"]])
        return sec, lo, hi

    def relocs_in(self, sec, lo, hi):
        """(file offset of the entry, r_offset, sym index, type, addend) for the RELA of `sec` in [lo, hi)"""
        out = []
        for s in self.sh:
            if s["type"] != 4 or s["info"] != sec:
                continue
            for k in range(s["size"] // 12):
                o = s["off"] + k * 12
                r_off, r_info, r_add = struct.unpack(">IIi", self.b[o:o + 12])
                if lo <= r_off < hi:
                    out.append((o, r_off, r_info >> 8, r_info & 0xFF, r_add))
        return out


def sites(e):
    """{stock name: (entry offset, current target name)} for mdboot's two calls; dies on anything unexpected"""
    for n in (CALLER, CORE) + tuple(h for _, h in PAIRS):
        if not e.defined(n):
            die("%s: %s is not defined (a module kernel with core patch 0030 and tools/dlm-halt030.s linked?)"
                % (e.path, n))
    sec, lo, hi = e.extent(CALLER)
    text = e.sh[sec]
    found = {}
    for stock, hook in PAIRS:
        hits = []
        for o, r_off, si, typ, add in e.relocs_in(sec, lo, hi):
            n = e.syms[si]["name"]
            if n not in (stock, hook):
                continue
            if typ != R_68K_32 or add != 0:
                die("%s: mdboot's relocation for %s at +0x%x is type %d addend %d, not R_68K_32 + 0"
                    % (e.path, n, r_off, typ, add))
            op = text["off"] + r_off - 2
            if bytes(e.b[op:op + 2]) != b"\x4e\xb9":
                die("%s: mdboot's relocation for %s at +0x%x is not on a `jsr <abs>.l` operand" % (e.path, n, r_off))
            hits.append((o, n))
        if len(hits) != 1:
            die("%s: mdboot has %d calls of %s/%s, want exactly 1" % (e.path, len(hits), stock, hook))
        found[stock] = hits[0]
    return found


def cmd_patch(path):
    e = Elf(path)
    found = sites(e)
    changed = 0
    for stock, hook in PAIRS:
        o, cur = found[stock]
        if cur == hook:
            print("  [skip] mdboot's %s call already goes through %s" % (stock, hook))
            continue
        r_info = e.index_of(hook) << 8 | R_68K_32
        e.b[o + 4:o + 8] = struct.pack(">I", r_info)
        changed += 1
        print("  [ok]   mdboot's jsr %s -> %s (dlm_halt first)" % (stock, hook))
    if changed:
        open(path, "wb").write(e.b)
    return cmd_check(path)


def cmd_check(path):
    e = Elf(path)
    found = sites(e)
    bad = [stock for stock, hook in PAIRS if found[stock][1] != hook]
    if bad:
        die("%s: mdboot still calls %s directly" % (path, ", ".join(bad)))
    print("  [ok]   halt hook present: mdboot calls dlm_halt before haltsys and before rtnfirm; "
          "haltsys/rtnfirm themselves untouched")
    return 0


def main(argv):
    if len(argv) == 2 and argv[0] == "--check":
        return cmd_check(argv[1])
    if len(argv) == 1 and not argv[0].startswith("-"):
        return cmd_patch(argv[0])
    sys.stderr.write(__doc__ if __doc__ else "usage: patch-dlm-halt030.py [--check] ETREL\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
