#!/usr/bin/env python3
#
# comaddr.py -- recover the RUNTIME addresses of kernel symbols that exist only in
# the LOADED image (avenrun, lbolt, time, freemem, the FPE/f60/fpc/fpi/fpa counter
# blocks, ...) by replaying elf2brel's COMMON/section placement at a load base.
#
# WHY THIS TOOL EXISTS.  The Amix kernel ships as ET_REL (`/stand/unix`), and many
# of the words worth reading on a live box -- `avenrun`, and every FPE metal-round
# counter -- are ELF SHN_COMMON symbols with no fixed file address.  `nlist(3)`
# SUCCEEDS on them but returns the alignment, not an address; `adb -k /stand/unix`
# reads the FILE's placement, which is right only on a box whose running kernel was
# loaded from /stand/unix.  The trustworthy method on metal is to replay the loader's
# own COMMON allocation (tools/elf2brel.py, ProcessSymtab) to get each symbol's
# offset in the combined image, then add the address the kernel was LOADED at:
#
#       runtime_address = load_base + combined_offset
#
# THE HAZARD THIS TOOL IS HARDENED AGAINST -- the load base is NOT a constant.
# ------------------------------------------------------------------------------
# `load_base` is a property of the ACCELERATOR CARD's fast-RAM region, not of the
# machine.  Amix loads its kernel into the largest contiguous fast-RAM block, and
# WHERE that block starts depends on which CPU card is fitted:
#
#       68060 Mercury  (32 MB card RAM)  -> kernel loads at 0x08000000
#       A3640 / 68040  (RAM below it)    -> kernel loads at 0x07000000
#
# Swap the card and the base MOVES -- by 0x01000000 (16 MiB) in the case above.
# Every runtime address computed from the old base is then wrong by exactly that
# delta, and an `adb` read at the wrong address does NOT fail: it returns a
# plausible-looking number from an unrelated word.  A silently-shifted base is the
# same trap class as the COMMON-symbol trap this tool exists to defeat -- and it was
# caught on real hardware precisely because the counter blocks
# carry MAGIC WORDS that were read back and checked.  This tool makes that check
# mandatory rather than a lucky habit:
#
#   1. The load base is a PARAMETER (--load-base, default 0x08000000), never a
#      hardcoded constant, and overridable (--load-base 0x07000000) or discoverable
#      (--discover 0x08000000,0x07000000).
#   2. A MAGIC-WORD GATE, fail-closed: after computing the runtime address of a magic
#      anchor symbol (fpe_magic / f60_magic / fpc_magic / fpi_magic / fpe_abort_magic),
#      the tool REFUSES to hand out addresses unless a value READ FROM THE BOX at that
#      address (--observed) matches the magic the anchor holds in the ELF image.  A
#      mismatch means the base is wrong -- it says so, loudly, and names the base to
#      try instead.  Assuming the base without a read is possible only by saying so
#      out loud (--assume-base), and even then the output is banner-marked UNVERIFIED.
#
# The magic constant for the gate is READ FROM THE KERNEL ELF (the anchor's
# initialized .data word), so it is ground truth for THIS artifact and needs no
# hand-maintained table; the known-magic table below is only a cross-check and a
# nicety for `--list-magics`.
#
# HOST-STATIC.  This tool never touches the box.  The value read from the box is an
# INPUT (--observed), supplied by whoever ran `adb .../dev/mem` or the counter recipe.
# That keeps it offline-testable and keeps the network concern in the recipe that reads
# the box, which is where it belongs.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import elf2brel as E  # noqa: E402  -- the COMMON-placement engine we replay

WHO = "comaddr"
DEFAULT_BASE = 0x08000000
ALT_BASE = 0x07000000  # the A3640/040 base -- named in every wrong-base message

# Known FPE metal-round magics, in auto-anchor priority order.  The EXPECTED value
# for the gate is read from the ELF, not from here; this table is a cross-check
# (a warning if the ELF disagrees) and the source for --list-magics.
MAGICS = [
    ("fpe_magic",       0x46504521, "FPE!"),
    ("f60_magic",       0x46503630, "FP60"),
    ("fpc_magic",       0x46504321, "FPC!"),
    ("fpi_magic",       0x46504921, "FPI!"),
    ("fpe_abort_magic", 0x46504121, "FPA!"),
]
MAGIC_BY_NAME = {n: (v, t) for (n, v, t) in MAGICS}


def die(msg, code=2):
    sys.stderr.write("%s: %s\n" % (WHO, msg))
    sys.exit(code)


def ascii4(v):
    return "".join(chr((v >> s) & 0xff) if 32 <= ((v >> s) & 0xff) < 127 else "."
                   for s in (24, 16, 8, 0))


class Kernel:
    """An elf2brel COMMON-replay over one kernel, with symbol lookup + ELF magic read."""

    def __init__(self, path):
        try:
            data = open(path, "rb").read()
        except OSError as e:
            die("cannot read kernel %s: %s" % (path, e))
        self.path = path
        self.c = E.Elf2Brel(data, WHO)
        self.c.read_elf()
        self.c.process_symtab()
        # name -> first defined symbol index
        self.by_name = {}
        for k in range(self.c.nsyms):
            nm = self.c._symname(k)
            if nm and nm not in self.by_name:
                self.by_name[nm] = k

    # --- header numbers, for the informational banner ---
    def sizes(self):
        c = self.c
        return (c.textsize, c.rodatasize, c.datasize, c.bsssize)

    def has(self, name):
        return name in self.by_name

    def combined_off(self, name):
        k = self.by_name.get(name)
        if k is None:
            return None, None
        return self.c.sym_value[k], self.c.sym_size[k]

    def runtime(self, base, name):
        off, _ = self.combined_off(name)
        if off is None:
            return None
        return (base + off) & 0xffffffff

    def elf_value(self, name):
        """The symbol's INITIALIZED 32-bit word as it sits in the ELF image (ground
        truth for a magic).  None if the symbol is uninitialized (bss/COMMON/undef)
        or out of range."""
        c = self.c
        k = self.by_name.get(name)
        if k is None:
            return None
        shx = c.sym_shndx_in[k]
        val_in = c.sym_value_in[k]
        if shx == c.i_data:
            base_off = c.S[c.i_data]["offset"]
        elif c.i_rodata and shx == c.i_rodata:
            base_off = c.S[c.i_rodata]["offset"]
        elif shx == c.i_text:
            base_off = c.S[c.i_text]["offset"]
        else:
            return None  # SHN_COMMON / .bss / SHN_UNDEF -- no initialized bytes
        fo = base_off + val_in
        if fo + 4 > len(c.d):
            return None
        return E.u32(c.d, fo)

    def pick_anchor(self, forced=None):
        """Return (anchor_name, expected_magic) or (None, None) if none usable.

        expected_magic is the ELF's own initialized word for the anchor; if the ELF
        lacks it but the name is a known magic, fall back to the table constant."""
        if forced:
            if not self.has(forced):
                die("anchor '%s' is not a symbol in %s" % (forced, self.path))
            exp = self.elf_value(forced)
            if exp is None:
                if forced in MAGIC_BY_NAME:
                    exp = MAGIC_BY_NAME[forced][0]
                else:
                    die("anchor '%s' has no initialized value in the ELF -- pick a "
                        "magic symbol (--list-magics) or use --assume-base" % forced)
            return forced, exp
        for (nm, _v, _t) in MAGICS:
            if self.has(nm):
                exp = self.elf_value(nm)
                if exp is not None:
                    return nm, exp
        return None, None


# ------------------------------------------------------------------ arg parsing --
class Args:
    def __init__(self):
        self.kernel = None
        self.syms = []
        self.load_base = None
        self.discover = None          # list[int] of candidate bases
        self.anchor = None
        self.observed = {}            # base(int|None) -> value(int); None key = single-base read
        self.assume_base = False
        self.list_magics = False
        self.map = False              # --map: every defined symbol at its combined (post-COMMON) offset


def parse_hex(s, what):
    try:
        return int(s, 16)
    except ValueError:
        die("%s: not a hex number: %r" % (what, s))


def is_hexish(s):
    return s.lower().startswith("0x") and all(ch in "0123456789abcdef" for ch in s[2:]) and len(s) > 2


def parse_observed(spec, a):
    # SPEC = HEX | BASE=HEX[,BASE=HEX...]
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            b, v = part.split("=", 1)
            a.observed[parse_hex(b, "--observed base")] = parse_hex(v, "--observed value")
        else:
            a.observed[None] = parse_hex(part, "--observed value")


USAGE = """usage: comaddr.py KERNEL [SYM ...] [options]

Recover runtime addresses of loaded-image kernel symbols by replaying elf2brel's
COMMON placement at a load base, gated on a magic word so a wrong base is caught.

  KERNEL              ET_REL kernel ELF (/stand/unix-class).
  SYM ...             symbols to resolve (default: the auto-picked magic anchor).

load base:
  --load-base HEX     pin the base (default 0x%08X).
  --discover H,H,...  candidate bases; pick the one whose anchor magic reads correct.

magic gate (fail-closed):
  --anchor NAME       magic symbol to gate on (default: auto -- first known magic present).
  --observed SPEC     value(s) READ FROM THE BOX at the anchor's runtime address.
                      SPEC = HEX  (single --load-base)  |  BASE=HEX[,BASE=HEX]  (--discover).
  --assume-base       proceed on an UNVERIFIED base (loud banner). Required to emit
                      addresses with no --observed. The legacy `KERNEL 0xBASE SYM...`
                      positional form implies it.
  --list-magics       print the known-magic table and exit.
  --map               print the whole symbol map AFTER elf2brel's COMMON allocation: one line
                      per defined symbol, `<combined_off> <size> <seg T|R|D|B> <name>`, sorted;
                      runtime = load base + combined_off. Needs no base and reads nothing from
                      a box (an ET_REL `nm` leaves COMMON counters with no address at all).

exit: 0 proceed (verified / discovered / assumed) | 2 usage/IO | 3 REFUSED (gate
failed, discovery no/ambiguous match, or base unverified with no override).
""" % DEFAULT_BASE


def parse_args(argv):
    a = Args()
    positional = []
    i = 0
    while i < len(argv):
        t = argv[i]
        if t in ("-h", "--help"):
            sys.stdout.write(USAGE)
            sys.exit(0)
        elif t == "--list-magics":
            a.list_magics = True
        elif t == "--load-base":
            i += 1
            if i >= len(argv):
                die("--load-base needs a hex argument")
            a.load_base = parse_hex(argv[i], "--load-base")
        elif t.startswith("--load-base="):
            a.load_base = parse_hex(t.split("=", 1)[1], "--load-base")
        elif t == "--discover":
            i += 1
            if i >= len(argv):
                die("--discover needs a comma-separated list of hex bases")
            a.discover = [parse_hex(x, "--discover") for x in argv[i].split(",") if x.strip()]
        elif t.startswith("--discover="):
            a.discover = [parse_hex(x, "--discover") for x in t.split("=", 1)[1].split(",") if x.strip()]
        elif t == "--anchor":
            i += 1
            if i >= len(argv):
                die("--anchor needs a symbol name")
            a.anchor = argv[i]
        elif t.startswith("--anchor="):
            a.anchor = t.split("=", 1)[1]
        elif t == "--observed":
            i += 1
            if i >= len(argv):
                die("--observed needs a value (HEX or BASE=HEX,...)")
            parse_observed(argv[i], a)
        elif t.startswith("--observed="):
            parse_observed(t.split("=", 1)[1], a)
        elif t == "--assume-base":
            a.assume_base = True
        elif t == "--map":
            a.map = True
        elif t.startswith("-") and t != "-":
            die("unknown option %r (see --help)" % t)
        else:
            positional.append(t)
        i += 1

    if a.list_magics:
        return a
    if not positional:
        die("no KERNEL given (see --help)")
    a.kernel = positional[0]
    rest = positional[1:]
    # Legacy positional: `comaddr.py KERNEL 0xBASE SYM...` -- second positional a bare
    # 0x-hex number means the load base (and implies --assume-base for back-compat).
    if a.load_base is None and a.discover is None and rest and is_hexish(rest[0]):
        a.load_base = parse_hex(rest[0], "load base")
        a.assume_base = True
        rest = rest[1:]
    a.syms = rest
    if a.load_base is not None and a.discover is not None:
        die("--load-base and --discover are mutually exclusive")
    if a.load_base is None and a.discover is None:
        a.load_base = DEFAULT_BASE
    return a


# ----------------------------------------------------------------- the actions --
def print_sizes(k, base_label):
    ts, rs, ds, bs = k.sizes()
    print("textsize=0x%x rodatasize=0x%x datasize=0x%x bsssize(after COMMON)=0x%x"
          % (ts, rs, ds, bs))
    print(base_label)
    print()


def print_syms(k, base, syms):
    for nm in syms:
        off, sz = k.combined_off(nm)
        if off is None:
            print("%-22s  *** NOT FOUND in %s ***" % (nm, os.path.basename(k.path)))
            continue
        print("%-22s combined_off=0x%08x  runtime=0x%08X  size=%d"
              % (nm, off, (base + off) & 0xffffffff, sz))


def print_map(k):
    c = k.c
    t, r, d, b = c.textsize, c.rodatasize, c.datasize, c.bsssize
    print("# comaddr.py --map %s -- combined offsets after elf2brel's COMMON allocation;" % os.path.basename(k.path))
    print("# runtime address = load base + combined_off. The base depends on the machine's RAM (measured: 0x08000000")
    print("# on the Z3660 060, 0x07000000 on an A3640/040): VERIFY it before trusting an address -- read a known")
    print("# initialised word (a *_magic, or a D symbol whose value you know) at base + its offset.")
    print("# textsize=0x%x rodatasize=0x%x datasize=0x%x bsssize(after COMMON)=0x%x" % (t, r, d, b))
    rows = []
    for nm, kk in k.by_name.items():
        if c.sym_shndx[kk] == 0:
            continue                      # undefined
        off, sz = c.sym_value[kk], c.sym_size[kk]
        if off >= t + r + d + b:
            continue                      # absolute / not in the image
        seg = "T" if off < t else "R" if off < t + r else "D" if off < t + r + d else "B"
        rows.append((off, nm, sz, seg))
    for off, nm, sz, seg in sorted(rows):
        print("%08x %8d %s %s" % (off, sz, seg, nm))
    return 0


def gate_fail_message(base, anchor, addr, got, expected):
    exp_txt = ascii4(expected)
    lines = [
        "",
        "*** LOAD BASE 0x%08X FAILED magic gate ***" % base,
        "    anchor %s at runtime 0x%08X read back 0x%08X (\"%s\")," % (anchor, addr, got, ascii4(got)),
        "    but the ELF holds 0x%08X (\"%s\") there." % (expected, exp_txt),
        "    The load base is WRONG: it is a property of the accelerator card's fast-RAM,",
        "    not the machine, and it moves on a card swap (68060 0x08000000 <-> A3640/040 0x07000000).",
    ]
    if base != ALT_BASE:
        lines.append("    Try --load-base 0x%08X, or --discover 0x%08X,0x%08X."
                     % (ALT_BASE, DEFAULT_BASE, ALT_BASE))
    else:
        lines.append("    Try --load-base 0x%08X, or --discover 0x%08X,0x%08X."
                     % (DEFAULT_BASE, DEFAULT_BASE, ALT_BASE))
    return "\n".join(lines)


def run(a):
    if a.list_magics:
        print("known FPE metal-round magics (expected value is read from the ELF; this is a cross-check):")
        for (nm, v, t) in MAGICS:
            print("  %-18s 0x%08X  \"%s\"" % (nm, v, t))
        return 0

    k = Kernel(a.kernel)
    if a.map:
        return print_map(k)
    anchor, expected = k.pick_anchor(a.anchor)

    # ------------------------------------------------------------- discover mode --
    if a.discover is not None:
        if anchor is None:
            die("no known magic symbol in %s to discover the base with -- pass --anchor "
                "NAME, or --load-base with --assume-base" % os.path.basename(a.kernel), 3)
        if anchor in MAGIC_BY_NAME and expected != MAGIC_BY_NAME[anchor][0]:
            sys.stderr.write("%s: warning: ELF's %s = 0x%08X disagrees with the known 0x%08X "
                             "(\"%s\") -- trusting the ELF\n"
                             % (WHO, anchor, expected, MAGIC_BY_NAME[anchor][0], MAGIC_BY_NAME[anchor][1]))
        # No reads yet? Tell the operator exactly what to read at each candidate.
        if not a.observed:
            print("DISCOVER: read anchor %s (\"%s\", expect 0x%08X) at each candidate base,"
                  % (anchor, ascii4(expected), expected))
            print("          then re-run with --observed BASE=VALUE[,BASE=VALUE...]:")
            for b in a.discover:
                print("  base 0x%08X  ->  read 0x%08X" % (b, k.runtime(b, anchor)))
            print()
            print("MAGIC GATE: base UNVERIFIED -- no reads supplied (fail-closed)")
            return 3
        matches = []
        print("DISCOVER: anchor %s expects 0x%08X (\"%s\")" % (anchor, expected, ascii4(expected)))
        for b in a.discover:
            addr = k.runtime(b, anchor)
            got = a.observed.get(b)
            if got is None:
                print("  base 0x%08X  addr 0x%08X  (no --observed given)" % (b, addr))
                continue
            ok = (got == expected)
            print("  base 0x%08X  addr 0x%08X  read 0x%08X (\"%s\")  %s"
                  % (b, addr, got, ascii4(got), "MAGIC OK" if ok else "mismatch"))
            if ok:
                matches.append(b)
        print()
        if len(matches) == 1:
            base = matches[0]
            print("MAGIC GATE: LOAD BASE DISCOVERED 0x%08X (%s verified)" % (base, anchor))
            print()
            print_sizes(k, "load base = 0x%08X  (DISCOVERED, magic-verified)" % base)
            print_syms(k, base, a.syms or [anchor])
            return 0
        if not matches:
            sys.stderr.write(
                "%s: *** LOAD BASE NOT FOUND among %s ***\n"
                "    no candidate's anchor %s read back its magic 0x%08X -- none of these is\n"
                "    the running kernel's base (card changed? different kernel? bad reads?).\n"
                % (WHO, ",".join("0x%08X" % b for b in a.discover), anchor, expected))
            print("MAGIC GATE: *** FAILED -- no candidate base matched ***")
            return 3
        sys.stderr.write("%s: *** AMBIGUOUS -- %d candidate bases matched the magic ***\n"
                         % (WHO, len(matches)))
        print("MAGIC GATE: *** FAILED -- ambiguous (%s) ***"
              % ",".join("0x%08X" % b for b in matches))
        return 3

    # ---------------------------------------------------------- single-base mode --
    base = a.load_base
    syms = a.syms or ([anchor] if anchor else [])

    # A gate was requested: an --observed read at the anchor's address.
    observed = a.observed.get(None)
    if observed is None and len(a.observed) == 1:
        observed = next(iter(a.observed.values()))  # tolerate a lone BASE=VAL in single mode

    if observed is not None:
        if anchor is None:
            die("--observed given but %s has no known magic symbol to gate on -- "
                "pass --anchor NAME" % os.path.basename(a.kernel), 3)
        addr = k.runtime(base, anchor)
        if anchor in MAGIC_BY_NAME and expected != MAGIC_BY_NAME[anchor][0]:
            sys.stderr.write("%s: warning: ELF's %s = 0x%08X disagrees with the known 0x%08X "
                             "(\"%s\") -- trusting the ELF\n"
                             % (WHO, anchor, expected, MAGIC_BY_NAME[anchor][0], MAGIC_BY_NAME[anchor][1]))
        if observed != expected:
            sys.stderr.write(gate_fail_message(base, anchor, addr, observed, expected) + "\n")
            print("MAGIC GATE: *** FAILED on load base 0x%08X ***" % base)
            return 3
        print("MAGIC GATE: LOAD BASE VERIFIED 0x%08X (%s = 0x%08X \"%s\" at 0x%08X)"
              % (base, anchor, expected, ascii4(expected), addr))
        print()
        print_sizes(k, "load base = 0x%08X  (VERIFIED, magic-gated)" % base)
        print_syms(k, base, syms)
        return 0

    # No read supplied.  Fail-closed unless the operator says --assume-base out loud.
    if a.assume_base:
        print("MAGIC GATE: *** LOAD BASE 0x%08X UNVERIFIED (--assume-base) ***" % base)
        if anchor is not None:
            print("            verify: read %s at 0x%08X, expect 0x%08X (\"%s\")"
                  % (anchor, k.runtime(base, anchor), expected, ascii4(expected)))
        print()
        print_sizes(k, "load base = 0x%08X  (UNVERIFIED -- assumed)" % base)
        print_syms(k, base, syms)
        return 0

    # Fail-closed: refuse to hand out trusted addresses on an unverified base.
    if anchor is None:
        sys.stderr.write(
            "%s: *** LOAD BASE 0x%08X UNVERIFIED and no magic anchor found ***\n"
            "    %s carries none of the known magics (%s), so the base cannot be checked.\n"
            "    Pass --assume-base to proceed anyway (addresses are trusted only if the\n"
            "    kernel actually loaded at 0x%08X).\n"
            % (WHO, base, os.path.basename(a.kernel),
               " ".join(n for (n, _v, _t) in MAGICS), base))
        print("MAGIC GATE: base UNVERIFIED -- no anchor, no override (fail-closed)")
        return 3
    addr = k.runtime(base, anchor)
    sys.stderr.write(
        "%s: *** LOAD BASE 0x%08X UNVERIFIED -- refusing to emit trusted addresses ***\n"
        "    Read the anchor on the box, e.g.:  printf '0x%x,1/X\\n' | adb /stand/unix /dev/mem\n"
        "    Expect %s = 0x%08X (\"%s\").  Then either:\n"
        "      * re-run with  --observed <value-you-read>   (single-base gate), or\n"
        "      * re-run with  --discover 0x%08X,0x%08X   (auto-pick the base), or\n"
        "      * pass  --assume-base  to proceed unverified (the base moves on a card swap!).\n"
        % (WHO, base, addr, anchor, expected, ascii4(expected),
           DEFAULT_BASE, ALT_BASE))
    print("MAGIC GATE: base 0x%08X UNVERIFIED -- no read, no override (fail-closed)" % base)
    return 3


def main(argv):
    a = parse_args(argv)
    return run(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
