#!/usr/bin/env python3
"""kernel-sddevsize-inject.py -- the on-box partition-size fix for a 040/060-line AMIX kernel, by symbol.

Stock amiga/alien/sdpart.c:

    uint sddevsize( dev) { return partab[MINOR( dev)].len ? partab[MINOR( dev)].len : 1234567; }

1234567 blocks (602.8 MiB) is what the kernel answers for a partition length it does not know, and dd.c clamps every
raw transfer to it -- so on-box mkfs fails ENXIO on any slice ending past that block.
The 030 line fixes the source (src/kernel-patches/sdpart.c.patch: the default becomes 0x3FFFFF, the largest whose
*BSIZE still fits a signed 32-bit offset). The 040/060 line links the STOCK sdpart.o, so this tool writes the same
constant into the linked function: exactly ONE word, the immediate of the function's single `move.l #1234567,%d0`
(opcode 0x203C).

    kernel-sddevsize-inject.py show   <kernel>             where the site is and what it holds
    kernel-sddevsize-inject.py inject <kernel> -o <out>    write 0x3FFFFF (refuses unless the stock 1234567 is there)
    kernel-sddevsize-inject.py verify <kernel>             require the injected value
    kernel-sddevsize-inject.py --selftest                  hermetic (assembles a tiny ET_REL with the cross binutils)

Refuses (exit 1): not an ET_REL m68k ELF; `sddevsize` not exactly one global FUNC in .text; the function holds no or
more than one `203C 0012D687` / `203C 003FFFFF`; a relocation overlaps the 4 immediate bytes; anything outside those
4 bytes differs after the write. Apply it to the family's unstamped base BEFORE the per-unit chains are cut.
"""
import os, shutil, struct, subprocess, sys, tempfile

WHO = "kernel-sddevsize-inject"
STOCK, FIXED = 1234567, 0x3FFFFF
OPC = b"\x20\x3c"


class Refused(Exception):
    pass


def u16(b, o): return struct.unpack_from(">H", b, o)[0]
def u32(b, o): return struct.unpack_from(">I", b, o)[0]


def sections(d):
    if d[:4] != b"\x7fELF" or d[4] != 1 or d[5] != 2:
        raise Refused("not a 32-bit big-endian ELF")
    if u16(d, 16) != 1 or u16(d, 18) != 4:
        raise Refused("not an ET_REL m68k object (e_type %d, e_machine %d)" % (u16(d, 16), u16(d, 18)))
    shoff, shentsize, shnum, shstrndx = u32(d, 32), u16(d, 46), u16(d, 48), u16(d, 50)
    secs = []
    for k in range(shnum):
        o = shoff + k * shentsize
        secs.append(dict(name=u32(d, o), type=u32(d, o + 4), offset=u32(d, o + 16), size=u32(d, o + 20),
                         link=u32(d, o + 24), info=u32(d, o + 28), entsize=u32(d, o + 36)))
    stro = secs[shstrndx]["offset"]
    for s in secs:
        e = d.index(b"\0", stro + s["name"]); s["name"] = d[stro + s["name"]:e].decode("latin1")
    return secs


def locate(d):
    secs = sections(d)
    text = [k for k, s in enumerate(secs) if s["name"] == ".text"]
    symtab = [s for s in secs if s["type"] == 2]
    if len(text) != 1 or len(symtab) != 1:
        raise Refused("expected exactly one .text and one .symtab")
    ti, st = text[0], symtab[0]
    strs = secs[st["link"]]["offset"]
    hits = []
    for k in range(st["size"] // 16):
        o = st["offset"] + k * 16
        nm = d[strs + u32(d, o):d.index(b"\0", strs + u32(d, o))]
        if nm == b"sddevsize":
            hits.append((u32(d, o + 4), u32(d, o + 8), d[o + 12], u16(d, o + 14)))
    defs = [h for h in hits if h[3] == ti and (h[2] >> 4) == 1 and (h[2] & 0xF) in (0, 2)]
    if len(defs) != 1:
        raise Refused("`sddevsize` is not exactly one global symbol in .text (%d candidates of %d)" % (len(defs), len(hits)))
    val, size, _info, _sh = defs[0]
    fstart = secs[ti]["offset"] + val
    fend = fstart + (size if size else 0x60)          # NOTYPE size-0 symbols: the stock body is 0x30 bytes
    body = d[fstart:fend]
    sites = []
    for want in (STOCK, FIXED):
        pat = OPC + struct.pack(">I", want)
        i = body.find(pat)
        while i >= 0:
            sites.append((fstart + i + 2, want))
            i = body.find(pat, i + 1)
    if len(sites) != 1:
        raise Refused("sddevsize holds %d `move.l #1234567|#0x3FFFFF,%%d0` sites, not exactly 1" % len(sites))
    imm_off, value = sites[0]
    text_rel = imm_off - secs[ti]["offset"]
    for s in secs:
        if s["type"] == 4 and s["info"] == ti:            # SHT_RELA against .text
            for k in range(s["size"] // 12):
                r = u32(d, s["offset"] + k * 12)
                if r < text_rel + 4 and r + 4 > text_rel:
                    raise Refused("a relocation at .text+0x%x overlaps the immediate" % r)
    return dict(func=val, imm_off=imm_off, text_off=text_rel, value=value)


def cmd(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    if len(argv) < 2 or argv[0] not in ("show", "inject", "verify"):
        sys.stderr.write(__doc__); return 2
    op, path = argv[0], argv[1]
    d = open(path, "rb").read()
    try:
        s = locate(d)
        if op == "show":
            print("%s: sddevsize .text+0x%x, immediate at file 0x%x = %d (0x%x) -- %s"
                  % (WHO, s["func"], s["imm_off"], s["value"], s["value"], "STOCK" if s["value"] == STOCK else "INJECTED"))
            return 0
        if op == "verify":
            if s["value"] != FIXED:
                raise Refused("sddevsize answers %d, not the injected 0x%x" % (s["value"], FIXED))
            print("%s: PASS  %s sddevsize default 0x%x (file 0x%x)" % (WHO, path, FIXED, s["imm_off"]))
            return 0
        if "-o" not in argv:
            raise Refused("inject needs -o <out>")
        out = argv[argv.index("-o") + 1]
        if s["value"] != STOCK:
            raise Refused("the site holds 0x%x, not the stock 1234567 -- inject from the base, never twice" % s["value"])
        nd = bytearray(d); nd[s["imm_off"]:s["imm_off"] + 4] = struct.pack(">I", FIXED)
        diff = [i for i in range(len(d)) if d[i] != nd[i]]
        if any(not (s["imm_off"] <= i < s["imm_off"] + 4) for i in diff):
            raise Refused("bytes outside the immediate would change")
        open(out, "wb").write(nd)
        back = locate(open(out, "rb").read())
        if back["value"] != FIXED:
            raise Refused("read-back: the site holds 0x%x" % back["value"])
        print("%s: injected %s -> %s: sddevsize .text+0x%x immediate 1234567 -> 0x%x (%d byte(s) changed)"
              % (WHO, path, out, s["func"], FIXED, len(diff)))
        return 0
    except Refused as e:
        print("%s: REFUSED -- %s: %s" % (WHO, path, e)); return 1


def selftest():
    asm = ("\t.text\n\t.globl sddevsize\n\t.type sddevsize,@function\nsddevsize:\n\tlinkw %fp,#0\n"
           "\tmovel %fp@(8),%d0\n\tbeqw 1f\n\tmovel #1234567,%d0\n1:\tunlk %fp\n\trts\n\t.size sddevsize,.-sddevsize\n"
           "\t.globl other\nother:\tmovel #1234567,%d1\n\trts\n")
    fails, n = [], 0
    if not shutil.which("m68k-linux-gnu-as"):
        print("%s selftest: SKIP -- no m68k-linux-gnu-as on PATH to assemble the fixture" % WHO); return 0
    with tempfile.TemporaryDirectory(prefix="sddevsize-") as td:
        s, o = os.path.join(td, "k.s"), os.path.join(td, "k.o")
        open(s, "w").write(asm)
        r = subprocess.run(["m68k-linux-gnu-as", "-m68040", s, "-o", o], capture_output=True, text=True)
        if r.returncode != 0:
            print("%s selftest: cannot assemble the fixture: %s" % (WHO, r.stderr.strip())); return 1
        two = os.path.join(td, "two.o")
        open(os.path.join(td, "t.s"), "w").write(asm.replace("1:\tunlk", "\tmovel #1234567,%d0\n1:\tunlk"))
        subprocess.run(["m68k-linux-gnu-as", "-m68040", os.path.join(td, "t.s"), "-o", two], check=True)

        def case(label, want, args):
            nonlocal n
            n += 1
            import io, contextlib
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = cmd(args)
            ok = rc == want
            print("  %-64s %s" % (label, "ok" if ok else "FAIL (rc %d) %s" % (rc, buf.getvalue().strip()[:120])))
            if not ok:
                fails.append(label)
        out = os.path.join(td, "out.o")
        case("show reads the stock site", 0, ["show", o])
        case("inject writes 0x3FFFFF", 0, ["inject", o, "-o", out])
        case("verify accepts the injected kernel", 0, ["verify", out])
        case("REFUSED: verify on the stock kernel", 1, ["verify", o])
        case("REFUSED: inject twice", 1, ["inject", out, "-o", os.path.join(td, "x.o")])
        case("REFUSED: two sites in sddevsize", 1, ["inject", two, "-o", os.path.join(td, "y.o")])
        a, b = open(o, "rb").read(), open(out, "rb").read()
        n += 1
        diff = [i for i in range(len(a)) if a[i] != b[i]]
        ok = len(diff) <= 4 and b.count(struct.pack(">I", STOCK)) == 1      # `other`'s immediate untouched
        print("  %-64s %s" % ("only the 4 immediate bytes changed; other functions untouched", "ok" if ok else "FAIL %s" % diff))
        if not ok:
            fails.append("diff")
    print("%s: SELFTEST %s -- %d/%d" % (WHO, "PASS" if not fails else "FAIL", n - len(fails), n))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(cmd(sys.argv[1:]))
