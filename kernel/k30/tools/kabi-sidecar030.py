#!/usr/bin/env python3
"""kabi-sidecar030.py -- write the kabi sidecar of a finished 030 kernel (kernel/dlm C2-3 §2, version 4).

    kabi-sidecar030.py ETREL BREL --family NAME [--pin PIN] [-o OUT | --stand DIR]
    kabi-sidecar030.py --check ETREL BREL SIDECAR
    kabi-sidecar030.py ETREL BREL --family generic --module FILL [--abi ABI --mkabi MKABI DDILIST OFFS] [-o OUT | --stand DIR]
    kabi-sidecar030.py --check ETREL BREL SIDECAR --module FILL [--abi ABI --mkabi MKABI DDILIST OFFS]

The 030 kit ships the brel (elf2brel's output); the ET_REL it was made from is the only place the symbols are.
One key=value per line, in C2-3's order: kabi, family, line, pin, build, size, sha256, bss, loader-min, root,
rootfs. Every value except family and pin is read from the two files, so the sidecar and /dev/kinfo cannot
disagree:
  kabi     kinfo030's kinfo_kabi ("static"; the image must carry kinfo, registered in cdevsw[53])
  build    kinfo030's kinfo_buildid, the id the build stamped (68030-yymmdd-nn; /dev/kinfo shows the same)
  size, sha256   of the brel, the form shipped
  bss      the ET_REL's end minus its text, rodata and data, as elf2brel lays them out (COMMON included);
           the ET_REL must convert to exactly BREL's bytes
  root     the rows of sd.c's scsicard[] (product number, queue function, name; walked while the function
           record is a relocation to a *queue function): mobo:a3000-wd for 0x0202F003, mobo:gayle for the
           Gayle IDE row 0xFFFF1DE0, else zorro:<mmmm>:<pp> from the product number <mmmm><00pp>
  rootfs   ufs (ufs_mountroot), s5 (s5mountroot)
  pin      gcc-2.7.2.3-<commit> of gcc-cross-amix; by default its HEAD, refused unless the installed
           m68k-cbm-sysv4-gcc is that commit's wrapper
--module FILL (the module kernel, stage 3; FILL = kernel/dlm tools/mkident.py --fill's output): kabi is the kinfo tag
(k30.1.0), loader-min=2, the ident=, arena= and ksym= lines from FILL -- each offset checked against elf2brel's
layout of dlm_ident, dlm_arena and dlm_ksym -- and, through stage 3, root=/rootfs= as on the static kernel (C3-3
§3: kbootset's gate 3 needs them). --abi ABI (the build's step-9 `mkabi.py
--check` output, abi=<64 hex>) adds abi= (C3-3 §4); with --mkabi this tool re-runs `MKABI --text` on ETREL with DDILIST and
OFFS (the step-2 dlm_offs.h) and the two must agree. --sym SYM (C2-3 version 6) adds sym=unix.sym <size> <sha256> for
the brel's symbols file beside unix; its `end` must be the image size plus bss=.
No timestamps: the same files give the same bytes. -o OUT writes the sidecar there (default: BREL's directory/
kabi); --stand DIR lays out the package's files instead: DIR/stand/k30/unix (a copy of BREL) and DIR/stand/k30/kabi.
"""
import argparse, hashlib, importlib.util, os, re, shutil, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOADER_MIN = 1
MOBO_ROWS = {0x0202F003: "mobo:a3000-wd", 0xFFFF1DE0: "mobo:gayle"}
ROOTFS = (("ufs", "ufs_mountroot"), ("s5", "s5mountroot"))
BUILD_RE = re.compile(r"^68030-[0-9]{6}-[0-9]{2}$")


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


kc = load("kinfo_cdevsw", "kinfo-cdevsw.py")
e2b = load("elf2brel", "elf2brel.py")


def die(msg):
    raise SystemExit("kabi-sidecar030: " + msg)


def u32(b, o): return struct.unpack(">I", b[o:o + 4])[0]


def data_sym(k, name, n, local=False):
    """n bytes at a .data symbol; a local one (sd.c's static scsicard) must be the only one of its name"""
    hits = []
    for i in range(k.sec[".symtab"]["size"] // k.se):
        o = k.so + i * k.se
        if k.symname(i) == name and struct.unpack(">H", k.b[o + 14:o + 16])[0] != 0:
            hits.append(u32(k.b, o + 4))
    if len(hits) != 1:
        die("%s: %d definitions of %s" % (k.path, len(hits), name))
    return hits[0], bytes(k.b[k.data + hits[0]:k.data + hits[0] + n])


def sym_size(k, name):
    """st_size of the one defined symbol `name`"""
    sizes = []
    for i in range(k.sec[".symtab"]["size"] // k.se):
        o = k.so + i * k.se
        if k.symname(i) == name and struct.unpack(">H", k.b[o + 14:o + 16])[0] != 0:
            sizes.append(u32(k.b, o + 8))
    if len(sizes) != 1:
        die("%s: %d definitions of %s" % (k.path, len(sizes), name))
    return sizes[0]


def cstr(b):
    return b.split(b"\0")[0].decode("latin-1")


def scsicard_table(k):
    """(table offset, relocations, is_queue, row stride) of sd.c's scsicard[]: a row is {pn, f, name} (12 bytes), or
    with --sd-cards 4 {pn, f, name, rank} (16 bytes, C4-1); the second row's queue function says which (in a 12-byte
    table tab+20 is a name, not a function)"""
    tab, _ = data_sym(k, "scsicard", 0, local=True)
    at = k.relocs(tab, tab + 16 * 64)

    def is_queue(f):
        return f in at and k.symname(u32(k.b, at[f] + 4) >> 8).endswith("queue")
    return tab, at, is_queue, 16 if is_queue(tab + 20) else 12


def sd_cards(etrel):
    """4 when the linked sd is build-cross-kernel.sh --sd-cards 4's (the rank column), else 2"""
    return 4 if scsicard_table(kc.Kernel(etrel))[3] == 16 else 2


def root_keys(k):
    tab, at, is_queue, stride = scsicard_table(k)
    keys, rows = [], 0
    while True:
        f = tab + rows * stride + 4
        if not is_queue(f):
            break
        pn = u32(k.b, k.data + tab + rows * stride)
        if pn in MOBO_ROWS:
            key = MOBO_ROWS[pn]
        elif pn >> 16 and pn & 0xFFFF <= 0xFF:
            key = "zorro:%04x:%02x" % (pn >> 16, pn & 0xFF)
        else:
            die("scsicard[%d] product number 0x%08x is neither an AutoConfig id nor a known motherboard row" % (rows, pn))
        if key not in keys:
            keys.append(key)
        rows += 1
    if not rows:
        die("%s: sd.c's scsicard[] has no rows" % k.path)
    return keys


def default_pin():
    if not os.environ.get("GCA"):
        die("set GCA to gcc-cross-amix's build/ directory (toolchain/README.md), or give --pin")
    gca = os.path.dirname(os.path.abspath(os.environ["GCA"]))
    try:
        head = subprocess.run(["git", "-C", gca, "rev-parse", "--short=7", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
        wrapper = open(os.path.join(gca, "amix-gcc-wrapper.sh")).read().replace("@TARGET@", "m68k-cbm-sysv4")
    except (OSError, subprocess.CalledProcessError):
        die("cannot read gcc-cross-amix at %s; give --pin" % gca)
    cc = shutil.which("m68k-cbm-sysv4-gcc") or "m68k-cbm-sysv4-gcc"
    if not os.path.exists(cc) or open(cc).read() != wrapper:
        die("the installed m68k-cbm-sysv4-gcc (%s) is not gcc-cross-amix %s's wrapper; give --pin" % (cc, head))
    return "gcc-2.7.2.3-" + head


def module_keys(k, conv, fill):
    """ident=, arena=, ksym= from mkident --fill's output, each offset checked against elf2brel's layout"""
    kv = {}
    for ln in open(fill).read().splitlines():
        if "=" in ln:
            a, v = ln.split("=", 1)
            kv[a.strip()] = v.strip()
    base = conv.textsize + conv.rodatasize
    for key, name in (("ident", "dlm_ident"), ("arena", "dlm_arena"), ("ksym", "dlm_ksym")):
        if key not in kv:
            die("%s has no %s= line" % (fill, key))
        want = base + data_sym(k, name, 0)[0]
        got = int(kv[key].split()[0], 16)
        if key == "arena" and len(kv[key].split()) > 1 and sym_size(k, name) == int(kv[key].split()[1], 16) + 16:
            # C3-3 v5 (kernel/dlm a829c44): dlm_arena is capacity + 16 and arena= is its first 16-aligned image offset
            # (the loader binds .data straight after .text and .rodata, so only the image offset can be aligned)
            want = (want + 15) & ~15
            if got % 16:
                die("arena=%s is not a multiple of 16 (C3-3 v5)" % kv[key])
        if got != want:
            die("%s=%s but elf2brel places %s at 0x%08x" % (key, kv[key], name, want))
    return [("ident", kv["ident"]), ("arena", kv["arena"]), ("ksym", kv["ksym"])]


def abi_key(etrel, abi, mkabi):
    """abi= from the build's mkabi --check output, recomputed by mkabi --text and compared when mkabi is given"""
    m = re.search(r"^abi=([0-9a-f]{64})$", open(abi).read(), re.M)
    if not m:
        die("%s has no abi=<64 hex> line" % abi)
    if mkabi:
        import tempfile
        tool, ddi, offs = mkabi
        with tempfile.NamedTemporaryFile(suffix=".txt") as tf:
            p = subprocess.run([sys.executable, tool, "--text", tf.name, etrel, ddi, offs], capture_output=True, text=True)
        n = re.search(r"abi=([0-9a-f]{64})", p.stdout)
        if p.returncode != 0 or not n:
            die("mkabi --text failed: %s" % (p.stdout + p.stderr).strip()[:200])
        if n.group(1) != m.group(1):
            die("abi=%s from the build, but mkabi --text on %s gives %s" % (m.group(1), etrel, n.group(1)))
    return [("abi", m.group(1))]


def sym_key(sym, conv):
    """sym=<name> <size> <sha256> (C2-3 v6), the file's end checked against the image size plus bss="""
    b = open(sym, "rb").read()
    spec = importlib.util.spec_from_file_location("mksym030", os.path.join(HERE, "mksym030.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    end = m.read(sym).get("end", (None,))[0]
    want = conv.textsize + conv.rodatasize + conv.datasize + conv.bsssize
    if end != want:
        die("%s: end is %s, not the image size plus bss= (%d)" % (sym, end, want))
    return [("sym", "%s %d %s" % (os.path.basename(sym), len(b), hashlib.sha256(b).hexdigest()))]


def sidecar(etrel, brel, family, pin, fill=None, abi=None, mkabi=None, sym=None, sdcards=2):
    k = kc.Kernel(etrel)
    if "kinfoopen" not in k.index or "kinfo_kabi" not in k.index:
        die("%s does not carry kinfo (build-cross-kernel.sh --kinfo)" % etrel)
    if kc.patch(etrel, 53, check=True, out=lambda s: None) != 0:
        die("%s: kinfo is not registered in cdevsw[53]" % etrel)
    kabi = cstr(data_sym(k, "kinfo_kabi", 24)[1])
    build = cstr(data_sym(k, "kinfo_buildid", 32)[1])
    if fill and kabi not in ("k30.1.0", "k30.1.1", "k30.1.2", "k30.1.3"):
        die("a module kernel's kinfo tag is %r, not k30.1.0, k30.1.1, k30.1.2 or k30.1.3 (kernel/dlm)" % kabi)
    if not BUILD_RE.match(build):
        die("kinfo_buildid %r is not a stamped 68030-yymmdd-nn" % build)
    raw = open(brel, "rb").read()
    conv = e2b.Elf2Brel(open(etrel, "rb").read(), whoami="kabi-sidecar030")
    if conv.convert() != raw:
        die("%s is not elf2brel's output for %s" % (brel, etrel))
    fs = [n for n, s in ROOTFS if s in k.index]
    if not fs and not fill:
        die("no root filesystem in %s" % etrel)
    if fill:
        # a module kernel carved of ufs and s5 (--carve-fs) has no *mountroot and omits rootfs= (C3-3 v6)
        return "".join("%s=%s\n" % kv for kv in [
            ("kabi", kabi), ("family", family), ("line", "k30"), ("pin", pin), ("build", build),
            ("size", str(len(raw))), ("sha256", hashlib.sha256(raw).hexdigest()), ("bss", str(conv.bsssize)),
            ("loader-min", "2"), ("root", ",".join(root_keys(k)))] + ([("rootfs", ",".join(fs))] if fs else [])
            + sdcards_key(sdcards) + module_keys(k, conv, fill) + (abi_key(etrel, abi, mkabi) if abi else []) + (sym_key(sym, conv) if sym else [])
            + rth1_key(k))
    lines = [
        ("kabi", kabi),
        ("family", family),
        ("line", "k30"),
        ("pin", pin),
        ("build", build),
        ("size", str(len(raw))),
        ("sha256", hashlib.sha256(raw).hexdigest()),
        ("bss", str(conv.bsssize)),
        ("loader-min", str(LOADER_MIN)),
        ("root", ",".join(root_keys(k))),
        ("rootfs", ",".join(fs)),
    ] + sdcards_key(sdcards) + rth1_key(k)
    return "".join("%s=%s\n" % kv for kv in lines)


def rth1_key(k):
    """rth1=2 (kernel/dlm C2-3 v9) when the RTH1 half matches a motherboard record by its id (C4-1 v6 section 5.2): the
    port's rth1.c from 88dcfc0 on, recognised by rth1_moboid beside rth1_apply, both functions in the image"""
    def func(n):
        i = k.index.get(n)
        return i is not None and (k.b[k.so + i * k.se + 12] & 0xF) == 2   # STT_FUNC
    return [("rth1", "2")] if func("rth1_moboid") and func("rth1_apply") else []


def sdcards_key(n):
    """sdcards=4 on a --sd-cards 4 kernel (kernel/dlm C4-1: minor bit 7 is card high bit, not LUN 1); absent = 2"""
    if n not in (2, 4):
        die("--sdcards %r: want 2 or 4" % n)
    return [("sdcards", "4")] if n == 4 else []


def selftest():
    import types
    n = f = 0

    def ok(name, c):
        nonlocal n, f
        n += 1
        f += 0 if c else 1
        print('  %s %s' % ('ok  ' if c else 'FAIL', name))

    def kern(**syms):   # name -> st_info, a symbol table of 16-byte entries (entry 0 the null symbol)
        b = bytearray(16 * (len(syms) + 1))
        idx = {}
        for i, (nm, info) in enumerate(syms.items(), 1):
            b[16 * i + 12] = info
            idx[nm] = i
        return types.SimpleNamespace(index=idx, b=bytes(b), so=0, se=16)
    print('kabi-sidecar030 selftest')
    ok('rth1=2: rth1_moboid (a static function) beside rth1_apply', rth1_key(kern(rth1_moboid=0x02, rth1_apply=0x12)) == [('rth1', '2')])
    ok('no rth1= for the old rth1.c (rth1_apply alone)', rth1_key(kern(rth1_apply=0x12)) == [])
    ok('no rth1= when rth1_moboid is not a function', rth1_key(kern(rth1_moboid=0x01, rth1_apply=0x12)) == [])
    ok('no rth1= without rth1_apply', rth1_key(kern(rth1_moboid=0x02)) == [])
    print('kabi-sidecar030: %d checks, %d failed' % (n, f))
    print('kabi-sidecar030: SELFTEST PASS' if f == 0 else 'kabi-sidecar030: SELFTEST FAIL')
    return 0 if f == 0 else 1


def main(argv=None):
    if (argv if argv is not None else sys.argv[1:])[:1] == ['--selftest']:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("etrel")
    ap.add_argument("brel")
    ap.add_argument("sidecar", nargs="?", help="with --check: the sidecar to compare")
    ap.add_argument("--family")
    ap.add_argument("--pin")
    ap.add_argument("-o", dest="out")
    ap.add_argument("--stand")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--module", metavar="FILL")
    ap.add_argument("--abi", metavar="ABI")
    ap.add_argument("--mkabi", nargs=3, metavar=("MKABI", "DDILIST", "OFFS"))
    ap.add_argument("--sym", metavar="SYM")
    ap.add_argument("--sdcards", type=int, default=2, help="4 on a build-cross-kernel.sh --sd-cards 4 kernel")
    a = ap.parse_args(argv)
    if a.check:
        if not a.sidecar:
            ap.error("--check ETREL BREL SIDECAR")
        have = open(a.sidecar).read()
        kv = dict(ln.split("=", 1) for ln in have.splitlines() if "=" in ln)
        want = sidecar(a.etrel, a.brel, kv.get("family", ""), kv.get("pin", ""), a.module, a.abi, a.mkabi, a.sym, a.sdcards)
        if have != want:
            print("kabi-sidecar030: %s differs from what this tool writes:\n%s" % (a.sidecar, want), end="")
            return 1
        print("kabi-sidecar030: %s OK" % a.sidecar)
        return 0
    if not a.family:
        ap.error("--family NAME")
    text = sidecar(a.etrel, a.brel, a.family, a.pin or default_pin(), a.module, a.abi, a.mkabi, a.sym, a.sdcards)
    if a.stand:
        d = os.path.join(a.stand, "stand", "k30")
        os.makedirs(d, exist_ok=True)
        shutil.copyfile(a.brel, os.path.join(d, "unix"))
        out = os.path.join(d, "kabi")
    else:
        out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.brel)), "kabi")
    with open(out, "w") as f:
        f.write(text)
    print(text, end="")
    print("kabi-sidecar030: wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
