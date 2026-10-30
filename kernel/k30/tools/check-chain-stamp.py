#!/usr/bin/env python3
"""check-chain-stamp.py -- gate ONE emitted per-id chain of a prebuilt kernel family.

    check-chain-stamp.py <chain> --card {0|1} --unit N --cputype {40|60} --bo-size BLOCKS
                         [--base <family-base>] [--root-slice 1] [--swap-slice 2]
    check-chain-stamp.py --selftest

A family (prebuilt families, per-id chains) is ONE gated link, stamped per
destination: rootdev + swapfile.bo_name by tools/kernel-rootdev-stamp.py, cputype by
tools/kernel-cputype-stamp.py.  This asserts that a chain is exactly that and nothing else:

  1. the by_symbol coherence gate holds (kernel-rootdev-stamp.py SymbolKernel: ET_REL,
     anchor unique, no relocation over the written ranges, rootfstype empty, the bo_name /
     rootdev controller digits agree);
  2. rootdev == makedevice(sd, C4-1's minor: (card>>1)<<7 | root_slice<<4 | (card&1)<<3 | unit) and bo_name is the HEX node
     for (card, unit, swap_slice) -- card 1 unit 6 is ced0s2, never c14d0s2;
  3. bo_size == --bo-size, the FAMILY CONSTANT (K060/KD: 61,440 blocks).  A kernel
     whose swap length came from an inherited /stand/CONFIG NSWAP carries some other value
     and is refused -- bo_size is a build-time constant, never stamped, never inherited;
  4. cputype reads --cputype and pcr_boot still holds its unwritten sentinel;
  5. with --base: same size as the family base, and every differing byte lies in the three
     stamped ranges (rootdev 4 B, bo_name 128 B, cputype 4 B).  A chain that differs from
     its base anywhere else is not a member of the family.

relsim is NOT run here -- run tools/relsim.py --loader boot2-040 beside it (the families
boot through boot2-040; the stock-loader verdict is expected to complain on the fpe line).

NOT the same gate as amix-040-060-port/src/check_root_family.py, which decodes the root-storage
FAMILY (the scsicard[] table sd's init() walks, its loop bound and queue functions). That one
asks "which controllers can this kernel register, and which one roots"; this one asks "is this
chain exactly the family base with the (card, unit) stamp and the family constants". k0-gates
runs both on every chain.

exit 0 = pass, 1 = refusal, 2 = usage / unreadable.
"""
import argparse
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
WHOAMI = "check-chain-stamp"


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fname))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


R = _load("kernel_rootdev_stamp", "kernel-rootdev-stamp.py")
C = _load("kernel_cputype_stamp", "kernel-cputype-stamp.py")


class Refused(Exception):
    pass


def check(path, card, unit, cputype, bo_size, base=None, root_slice=None, swap_slice=None,
          contract=R.CONTRACT, floppy=False):
    """Return a list of fact lines; raise Refused(list-of-problems) on any failure."""
    spec = R.Spec(R.load_contract(contract), contract)
    root_slice = spec.def_root_slice if root_slice is None else root_slice
    swap_slice = spec.def_swap_slice if swap_slice is None else swap_slice
    with open(path, "rb") as fh:
        data = fh.read()
    bad = [] if floppy else spec.check_id(unit, root_slice, swap_slice, card)
    if floppy and spec.floppy_rootdev is None:
        bad = ["the contract has no rootdev.floppy section"]
    if bad:
        raise Refused(bad)
    try:
        img = R.SymbolKernel(path, spec, data=data)     # exits 1 via R.refuse() on failure
    except SystemExit as e:
        raise Refused(["the by_symbol coherence gate refused %s (rc %s)" % (path, e.code)])
    problems = []
    if floppy:   # contract rootdev.floppy: FD0P + /dev/fakeswap
        want_dev, want_swap = spec.floppy_rootdev, spec.floppy_bo_name.decode("latin1")
        if not img.floppy:
            problems.append("not a floppy kernel: rootdev 0x%08x (%s)" % (img.rootdev, img.root_device))
    else:
        want_dev = spec.compose_dev(unit, root_slice, card)
        want_swap = spec.device_name(unit, swap_slice, card)
    if img.rootdev != want_dev:
        problems.append("rootdev 0x%08x (%s), expected 0x%08x (%s)"
                        % (img.rootdev, img.root_device, want_dev,
                           "fd0 (FD0P)" if floppy else spec.device_name(unit, root_slice, card)))
    if img.swap_device != want_swap:
        problems.append("swapfile.bo_name %r, expected %r" % (img.swap_device, want_swap))
    if img.bo_size != bo_size:
        problems.append("bo_size %d blocks, expected the family constant %d -- a swap length "
                        "inherited from /stand/CONFIG NSWAP is refused"
                        % (img.bo_size, bo_size))
    try:
        site = C.locate(data, path)
    except SystemExit as e:
        raise Refused(problems + ["the cputype site cannot be located (rc %s)" % e.code])
    if site["cputype"] != cputype:
        problems.append("cputype reads %d, expected %d" % (site["cputype"], cputype))
    if site["sentinel"] != C.SENTINEL_UNWRITTEN:
        problems.append("pcr_boot reads 0x%08x, not the unwritten sentinel" % site["sentinel"])
    diffs = None
    if base is not None:
        with open(base, "rb") as fh:
            bdata = fh.read()
        if len(bdata) != len(data):
            problems.append("size %d differs from the family base's %d" % (len(data), len(bdata)))
        else:
            ranges = ((img.off_rootdev, img.off_rootdev + spec.rootdev_size),
                      (img.off_name, img.off_name + spec.bo["bo_name"][1]),
                      (site["off"], site["off"] + 4))
            diffs = [i for i in range(len(data)) if data[i] != bdata[i]]
            stray = [i for i in diffs if not any(lo <= i < hi for lo, hi in ranges)]
            if stray:
                problems.append("%d byte(s) differ from the family base OUTSIDE the stamped "
                                "ranges: %s" % (len(stray), ", ".join("0x%x" % s for s in stray[:8])))
    if problems:
        raise Refused(problems)
    s, blocks = R.sum_r(data)
    facts = ["%s  rootdev 0x%08x (%s)  swap %s  bo_size %d  cputype %d"
             % ("FLOPPY" if floppy else "card %d unit %d" % (card, unit), img.rootdev, img.root_device,
                img.swap_device, img.bo_size, site["cputype"]),
             "sum -r %05d %d  svr4-sum 0x%04x" % (s, blocks, R.svr4_sum(data))]
    if diffs is not None:
        facts.append("%d byte(s) differ from the base, all inside the stamped ranges" % len(diffs))
    return facts


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(prog="check-chain-stamp.py",
                                 description="gate one per-id chain of a kernel family")
    ap.add_argument("chain")
    ap.add_argument("--card", type=int, default=None)
    ap.add_argument("--unit", type=int, default=None)
    ap.add_argument("--floppy", action="store_true",
                    help="the chain is the contract's rootdev.floppy pair (FD0P + /dev/fakeswap): no card/unit")
    ap.add_argument("--cputype", type=int, choices=(40, 60), required=True)
    ap.add_argument("--bo-size", type=int, required=True, help="the family swap constant, blocks")
    ap.add_argument("--base", help="the family base (card-0 link) the chain was stamped from")
    ap.add_argument("--root-slice", type=int, default=None)
    ap.add_argument("--swap-slice", type=int, default=None)
    a = ap.parse_args(argv)
    if not a.floppy and (a.card is None or a.unit is None):
        ap.error("--card and --unit are required (or --floppy)")
    for p in [a.chain] + ([a.base] if a.base else []):
        if not os.path.isfile(p):
            sys.stderr.write("%s: %s: no such file\n" % (WHOAMI, p))
            return 2
    try:
        facts = check(a.chain, a.card, a.unit, a.cputype, a.bo_size, a.base,
                      a.root_slice, a.swap_slice, floppy=a.floppy)
    except Refused as e:
        print("%s: REFUSED %s" % (WHOAMI, a.chain))
        for p in e.args[0]:
            print("  - " + p)
        return 1
    print("%s: PASS %s" % (WHOAMI, a.chain))
    for f in facts:
        print("  " + f)
    return 0


# ------------------------------------------------------------------ selftest --
# Hermetic: kernel-rootdev-stamp.py's synthetic ET_REL (cputype=N grafts the 040-line
# cputype/pcr_boot pair in).  Proves one PASS per card and every refusal kind.

def selftest():
    fails = []
    import contextlib
    import io

    def case(label, want_refused, blob, **kw):
        with tempfile.TemporaryDirectory(prefix="crf-") as td:
            p = os.path.join(td, "k")
            with open(p, "wb") as fh:
                fh.write(blob)
            bp = None
            if "base_blob" in kw:
                bp = os.path.join(td, "base")
                with open(bp, "wb") as fh:
                    fh.write(kw.pop("base_blob"))
            try:
                with contextlib.redirect_stderr(io.StringIO()), \
                        contextlib.redirect_stdout(io.StringIO()):
                    check(p, base=bp, **kw)
                got = False
            except Refused as e:
                got = e.args[0]
        ok = (got is not False) == want_refused
        why = "" if ok else ("passed" if got is False else "; ".join(got))
        print("  %-68s %s%s" % (label, "ok" if ok else "FAIL", "" if ok else "  (" + why + ")"))
        if not ok:
            fails.append(label)
        return got

    def names(got, word, label):
        if got and not any(word in g for g in got):
            print("  %-68s FAIL" % ("  ... " + label))
            fails.append(label)

    std = dict(card=0, unit=6, cputype=60, bo_size=61440)
    base = R._mkelf(cputype=40)                                   # the family base (card 0, 40)
    c0u6 = R._mkelf(cputype=60)
    c1u6 = R._mkelf(cputype=60, rootdev=0x0048001e, swap_name=b"/dev/dsk/ced0s2")
    c1u0 = R._mkelf(cputype=60, rootdev=0x00480018, swap_name=b"/dev/dsk/c8d0s2")
    print("check-chain-stamp selftest")
    case("PASS: card 0 unit 6, cputype 60, vs the base", False, c0u6, base_blob=base, **std)
    case("PASS: card 1 unit 6 (ced0s1/ced0s2) vs the base", False, c1u6, base_blob=base,
         **dict(std, card=1))
    case("PASS: card 1 unit 0 (c8d0s1/c8d0s2)", False, c1u0, **dict(std, card=1, unit=0))
    # the contract's rootdev.floppy pair (FD0P + /dev/fakeswap) -- only with floppy=True, and vice versa
    fd = R._mkelf(cputype=60, rootdev=0x00400008, swap_name=b"/dev/fakeswap")
    case("PASS: floppy=True, FD0P + /dev/fakeswap vs the base", False, fd, base_blob=base,
         **dict(std, card=None, unit=None, floppy=True))
    case("REFUSED: floppy=True on an sd chain", True, c0u6, **dict(std, card=None, unit=None, floppy=True))
    case("REFUSED: a floppy chain checked as card 0 unit 6", True, fd, **std)
    names(case("wrong unit is refused", True, c0u6, **dict(std, unit=3)), "rootdev",
          "rootdev named")
    names(case("bo_size != the family constant is refused (inherited NSWAP)", True,
               R._mkelf(cputype=60, bo_size=20479), **std), "NSWAP", "NSWAP named")
    got = case("card-1 expected, card-0 image -> rootdev + bo_name refused", True, c0u6,
               **dict(std, card=1))
    names(got, "rootdev", "rootdev named (card)")
    names(got, "bo_name", "bo_name named (card)")
    case("card 2 is refused before any read", True, c0u6, **dict(std, card=2))
    names(case("cputype 40 when 60 is expected is refused", True, base, **std), "cputype",
          "cputype named")
    names(case("no cputype symbol at all is refused (fail closed)", True, R._mkelf(), **std),
          "cputype", "cputype site named")
    stray = bytearray(c0u6)
    stray[60] ^= 0xFF
    names(case("a byte outside the stamped ranges vs --base is refused", True, bytes(stray),
               base_blob=base, **std), "OUTSIDE", "stray byte named")
    print()
    if fails:
        print("%s: SELFTEST FAIL -- %s" % (WHOAMI, ", ".join(fails)))
        return 1
    print("%s: SELFTEST PASS" % WHOAMI)
    return 0


if __name__ == "__main__":
    sys.exit(main())
