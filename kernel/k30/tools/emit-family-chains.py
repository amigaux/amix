#!/usr/bin/env python3
"""emit-family-chains.py -- cut the per-id chains of one prebuilt kernel family.

    emit-family-chains.py --family K060 --base <card-0 link> --out <dir>
                          --cputype 60 --bo-size 61440
                          [--cards 0] [--units 0-6]
                          [--control <frozen kernel> --control-sha256 H --control-sum-r N
                           --control-card 1 --control-unit 6 | --no-oracle]

A family is ONE gated link, cut from its card-0 base per destination.  For
every (card, unit) this runs the SHIPPED tools, never a re-implementation:

    kernel-rootdev-stamp.py stamp <base> --card C --id U --expect-current-id 6 -o <tmp>
    kernel-cputype-stamp.py stamp <tmp> --cputype 60 -o <chain>
    check-chain-stamp.py <chain> --card C --unit U --cputype 60 --bo-size B --base <base>
    relsim.py --loader boot2-040 <chain>

and writes <out>/<family>-cC-uU, <out>/MANIFEST.json and <out>/SHA256SUMS.

Defaults are card 0 (with the W-D7 probe in, the Z3660 is card 0); the K060 rollback
family (candidate-3, no probe) is the explicit case: --cards 0,1 --control-card 1.

--control FREEZES a reference kernel (candidate-3 is the rollback/diff reference, never
rebuilt).  Its sha256 and `sum -r` are asserted BEFORE anything is
written and AGAIN after the last chain, and the chain for (--control-card, --control-unit)
must be byte-identical to it -- the regression oracle that proves the per-unit route
reproduces the chain that produced the control.  A mismatch anywhere is exit 1 and the
manifest records FAIL.  --no-oracle keeps the before/after freeze check but skips the cmp:
for a family that is NOT the control's rebuild (e.g. KD060-Z0, a different base), the control
is only asserted untouched.

exit 0 = every chain green + oracle identical, 1 = any gate failed, 2 = usage.
"""
import argparse, shutil
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RSTAMP = os.path.join(HERE, "kernel-rootdev-stamp.py")
CSTAMP = os.path.join(HERE, "kernel-cputype-stamp.py")
CRF = os.path.join(HERE, "check-chain-stamp.py")
RELSIM = os.path.join(HERE, "relsim.py")


def _load_stamper():
    ks = importlib.util.spec_from_file_location("krs", RSTAMP)
    mod = importlib.util.module_from_spec(ks)
    ks.loader.exec_module(mod)
    return mod


K = _load_stamper()
sum_r = K.sum_r                                  # the one `sum -r` every kerntools gate uses


def ident(path):
    with open(path, "rb") as fh:
        b = fh.read()
    s, blocks = sum_r(b)
    return dict(size=len(b), sum_r=s, sum_r_blocks=blocks,
                sha256=hashlib.sha256(b).hexdigest(), md5=hashlib.md5(b).hexdigest())


def run(argv):
    r = subprocess.run([sys.executable] + argv, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def parse_list(text, lo, hi):
    out = []
    for part in text.split(","):
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    if not out or any(not lo <= v <= hi for v in out):
        sys.exit("emit-family-chains: %r outside %d-%d" % (text, lo, hi))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--family", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cputype", type=int, choices=(30, 40, 60), required=True)
    ap.add_argument("--etrel", help="030 line: the ET_REL kernel beside the brel base (relsim/rootdev judge it); the base is copied unstamped")
    ap.add_argument("--bo-size", type=int, required=True)
    ap.add_argument("--cards", default="0",
                    help="card list; default 0. Card 1 only for the pre-probe K060 rollback family")
    ap.add_argument("--units", default="0-6")
    ap.add_argument("--sdcards", type=int, choices=(2, 4),
                    help="the kernel's sd card count, MANIFEST.json `sdcards` (C2-3 v7, C4-1); with --etrel it is read "
                         "from the linked sd (build-cross-kernel.sh --sd-cards 4's rank column) and must agree; default 2")
    ap.add_argument("--families", default=os.path.join(os.path.dirname(HERE), "contracts", "kernel-families.json"),
                    help="the family contract the manifest's policy is read from (default: this repo's)")
    ap.add_argument("--floppy-root", action="store_true",
                    help="030 line, fd0unix config: root is the floppy (FD0P), swap the stock /dev/fakeswap; "
                         "labels the chain so instead of c<unit>d0s1 (the unit then only names the file). "
                         "040/060 line: ONE chain <family>-fd0 stamped `kernel-rootdev-stamp.py stamp --floppy` "
                         "(contract rootdev.floppy) from the sd-6 base; --cards/--units are ignored")
    ap.add_argument("--control")
    ap.add_argument("--control-sha256")
    ap.add_argument("--control-sum-r", type=int)
    ap.add_argument("--control-card", type=int, default=0,
                    help="the control's card; candidate-3 is card 1: pass --control-card 1 for K060")
    ap.add_argument("--control-unit", type=int, default=6)
    ap.add_argument("--no-oracle", action="store_true",
                    help="assert the control unchanged, but do not cmp a chain against it")
    a = ap.parse_args()
    cards = parse_list(a.cards, 0, 1)
    units = parse_list(a.units, 0, 7)
    if a.control and (a.control_sha256 is None or a.control_sum_r is None):
        ap.error("--control needs --control-sha256 and --control-sum-r (the frozen identity)")
    os.makedirs(a.out, exist_ok=True)
    fails = []
    sp = K.Spec(K.load_contract(), K.CONTRACT)

    def control_check(when):
        if not a.control:
            return None
        c = ident(a.control)
        ok = c["sha256"] == a.control_sha256 and c["sum_r"] == a.control_sum_r
        print("control %-6s sha256 %s  sum -r %05d %d  %s"
              % (when, c["sha256"][:16], c["sum_r"], c["sum_r_blocks"], "OK" if ok else "CHANGED"))
        if not ok:
            fails.append("control %s: identity differs from the frozen values" % when)
        return dict(c, ok=ok)

    before = control_check("before")
    if a.control and not before["ok"]:
        print("REFUSED: the frozen control is not the frozen bytes -- nothing emitted")
        return 1
    base = ident(a.base)
    print("base   %s  sha256 %s  sum -r %05d" % (a.base, base["sha256"][:16], base["sum_r"]))

    rows = []
    if a.floppy_root and a.cputype != 30:
        # the 040/060 install floppy (contract rootdev.floppy): one chain, stamped from the sd-6 base
        name = "%s-fd0" % a.family
        chain = os.path.join(a.out, name); tmp = chain + ".rootdev.tmp"
        for p in (chain, tmp):
            if os.path.exists(p):
                os.unlink(p)
        row = dict(file=name, card=None, unit=None, floppy=True)
        rc, out = run([RSTAMP, "stamp", a.base, "--floppy", "-o", tmp])
        if rc == 0:
            rc, out = run([CSTAMP, "stamp", tmp, "--cputype", str(a.cputype), "-o", chain])
        if os.path.exists(tmp):
            os.unlink(tmp)
        if rc != 0:
            row["stamp"] = "FAIL"; fails.append("%s: floppy stamp rc %d" % (name, rc)); print(out)
        else:
            crc, cout = run([CRF, chain, "--floppy", "--cputype", str(a.cputype), "--bo-size", str(a.bo_size),
                             "--base", a.base])
            rrc, rout = run([RELSIM, "--loader", "boot2-040", chain])
            comp = [ln for ln in rout.splitlines() if "COMPLAINTS" in ln]
            data = open(chain, "rb").read()
            s, blocks = sum_r(data)
            row.update(stamp="floppy", rootdev="0x%08x" % sp.floppy_rootdev, root_device="fd0 (FD0P)",
                       swap_device=sp.floppy_bo_name.decode("latin1"), bo_size=a.bo_size, cputype=a.cputype,
                       size=len(data), sum_r=s, sum_r_blocks=blocks, svr4_sum="0x%04x" % K.svr4_sum(data),
                       md5=hashlib.md5(data).hexdigest(), sha256=hashlib.sha256(data).hexdigest(),
                       check_chain_stamp="PASS" if crc == 0 else "FAIL",
                       relsim_boot2_040="CLEAN" if rrc == 0 else "FAIL (rc %d)" % rrc)
            if crc != 0:
                fails.append("%s: check-chain-stamp rc %d" % (name, crc)); print(cout)
            if rrc != 0:
                fails.append("%s: relsim rc %d" % (name, rrc))
            print("%-12s %-18s swap %-18s sum -r %05d  crf %s  relsim %s"
                  % (name, row["root_device"], row["swap_device"], s, row["check_chain_stamp"],
                     (comp[-1].strip() if comp else "?")))
        rows.append(row)
        cards = []
    for card in cards:
        for unit in units:
            name = "%s-c%d-u%d" % (a.family, card, unit)
            chain = os.path.join(a.out, name)
            tmp = chain + ".rootdev.tmp"
            for p in (chain, tmp):
                if os.path.exists(p):
                    os.unlink(p)
            row = dict(file=name, card=card, unit=unit)
            if a.cputype == 30:
                # the 030 line: the kernel's root device is baked by its config object (c6s1unix), there is no
                # rootdev/cputype stamp and no boot2 -- the chain IS the base (unix.brel), recorded with its ET_REL
                shutil.copyfile(a.base, chain)
                with open(chain, "rb") as fh:
                    data = fh.read()
                s, blocks = sum_r(data)
                row.update(stamp="prebuilt", bo_size=a.bo_size, cputype=30, size=len(data), sum_r=s,
                           sum_r_blocks=blocks, svr4_sum="0x%04x" % K.svr4_sum(data),
                           md5=hashlib.md5(data).hexdigest(), sha256=hashlib.sha256(data).hexdigest(),
                           root_device="fd0 (FD0P)" if a.floppy_root else "c%xd0s1" % (8 * card + unit),
                           swap_device="/dev/fakeswap" if a.floppy_root else "c%xd0s2" % (8 * card + unit),
                           check_chain_stamp="n/a (prebuilt 030)")
                if a.etrel:
                    er = os.path.join(a.out, name + ".etrel"); shutil.copyfile(a.etrel, er)
                    row["etrel"] = name + ".etrel"; row["etrel_sha256"] = hashlib.sha256(open(er, "rb").read()).hexdigest()
                    # the symbol map beside the chain: later cells read driver
                    # counters (ide_intr_count, spurious, timeouts, ...) from /dev/kmem by these addresses + the load base
                    nm = os.path.join(a.out, name + ".nm")
                    import subprocess
                    nr = subprocess.run(["m68k-linux-gnu-nm", "-n", er], capture_output=True, text=True)
                    if nr.returncode == 0 and nr.stdout:
                        with open(nm, "w") as fh:
                            fh.write(nr.stdout)
                        row["nm"] = name + ".nm"
                    else:
                        fails.append("%s: nm of the ET_REL failed (rc %d)" % (name, nr.returncode))
                    rrc, rout = run([RELSIM, er])
                else:
                    rrc, rout = 1, ""
                comp = [ln for ln in rout.splitlines() if "COMPLAINTS" in ln]
                row["relsim_stock"] = "CLEAN" if rrc == 0 else "FAIL (rc %d)" % rrc
                if rrc != 0:
                    fails.append("%s: relsim (stock loader) rc %d" % (name, rrc))
                print("%-12s %-10s prebuilt  sum -r %05d  relsim %s" % (name, row["root_device"], s, (comp[-1].strip() if comp else "?")))
                rows.append(row)
                continue
            rc, out = run([RSTAMP, "stamp", a.base, "--card", str(card), "--id", str(unit),
                           "--expect-current-id", "6", "-o", tmp])
            if rc == 0:
                rc, out = run([CSTAMP, "stamp", tmp, "--cputype", str(a.cputype), "-o", chain])
            if os.path.exists(tmp):
                os.unlink(tmp)
            if rc != 0:
                row["stamp"] = "FAIL"
                fails.append("%s: stamp rc %d" % (name, rc))
                print(out)
                rows.append(row)
                continue
            crc, cout = run([CRF, chain, "--card", str(card), "--unit", str(unit),
                             "--cputype", str(a.cputype), "--bo-size", str(a.bo_size),
                             "--base", a.base])
            rrc, rout = run([RELSIM, "--loader", "boot2-040", chain])
            comp = [ln for ln in rout.splitlines() if "COMPLAINTS" in ln]
            with open(chain, "rb") as fh:
                data = fh.read()
            s, blocks = sum_r(data)
            row.update(stamp="ok",
                       rootdev="0x%08x" % sp.compose_dev(unit, sp.def_root_slice, card),
                       root_device=sp.device_name(unit, sp.def_root_slice, card),
                       swap_device=sp.device_name(unit, sp.def_swap_slice, card),
                       bo_size=a.bo_size, cputype=a.cputype, size=len(data),
                       sum_r=s, sum_r_blocks=blocks, svr4_sum="0x%04x" % K.svr4_sum(data),
                       md5=hashlib.md5(data).hexdigest(),
                       sha256=hashlib.sha256(data).hexdigest(),
                       check_chain_stamp="PASS" if crc == 0 else "FAIL",
                       relsim_boot2_040="CLEAN" if rrc == 0 else "FAIL (rc %d)" % rrc)
            if crc != 0:
                fails.append("%s: check-chain-stamp rc %d" % (name, crc))
                print(cout)
            if rrc != 0:
                fails.append("%s: relsim rc %d" % (name, rrc))
            print("%-12s %-18s swap %-18s sum -r %05d  crf %s  relsim %s"
                  % (name, row["root_device"], row["swap_device"], s,
                     row["check_chain_stamp"], (comp[-1].strip() if comp else "?")))
            rows.append(row)

    oracle = None
    if a.control and not a.no_oracle:
        name = "%s-c%d-u%d" % (a.family, a.control_card, a.control_unit)
        p = os.path.join(a.out, name)
        same = os.path.exists(p) and open(p, "rb").read() == open(a.control, "rb").read()
        oracle = dict(chain=name, control=os.path.abspath(a.control),
                      byte_identical=same)
        print("ORACLE %s vs control: %s" % (name, "BYTE-IDENTICAL" if same else "DIFFERS"))
        if not same:
            fails.append("oracle: %s differs from the control" % name)
    # the symbol map AFTER elf2brel's COMMON allocation, beside every chain (an ET_REL `nm` gives COMMON
    # counters -- ide_intr_*, a3q_*, kstat blocks -- no address at all): tools/comaddr.py --map of the ET_REL
    import subprocess
    for r in rows:
        src = os.path.join(a.out, r["etrel"]) if r.get("etrel") else os.path.join(a.out, r["file"])
        if not os.path.exists(src) or "sha256" not in r:
            continue
        mr = subprocess.run([sys.executable, os.path.join(HERE, "comaddr.py"), src, "--map"], capture_output=True, text=True)
        if mr.returncode == 0 and mr.stdout:
            with open(os.path.join(a.out, r["file"] + ".map"), "w") as fh:
                fh.write(mr.stdout)
            r["map"] = r["file"] + ".map"
        else:
            fails.append("%s: comaddr --map failed (rc %d)" % (r["file"], mr.returncode))
    after = control_check("after")

    with open(a.families) as fh:
        policy = json.load(fh)["families"].get(a.family)
    if policy is None:
        fails.append("family %s is not in %s" % (a.family, a.families))
    sdcards = a.sdcards or 2
    if a.etrel:
        ks = importlib.util.spec_from_file_location("kabi_sidecar030", os.path.join(HERE, "kabi-sidecar030.py"))
        km = importlib.util.module_from_spec(ks)
        ks.loader.exec_module(km)
        got = km.sd_cards(a.etrel)
        if a.sdcards and a.sdcards != got:
            fails.append("--sdcards %d but the linked sd (%s) has %d cards" % (a.sdcards, a.etrel, got))
        sdcards = got
    man = dict(manifest="amix-kernel-family", schema_version=1, family=a.family,
               family_policy=policy, sdcards=sdcards,
               generated_by="amix kernel/k30 tools/emit-family-chains.py",
               base=dict(file=os.path.abspath(a.base), **base),
               cputype=a.cputype, bo_size_constant=a.bo_size,
               relsim_loader="boot2-040",
               control=None if not a.control else dict(
                   file=os.path.abspath(a.control), frozen_sha256=a.control_sha256,
                   frozen_sum_r=a.control_sum_r, card=a.control_card, unit=a.control_unit,
                   before=before, after=after, oracle=oracle),
               chains=rows, verdict="PASS" if not fails else "FAIL", failures=fails)
    with open(os.path.join(a.out, "MANIFEST.json"), "w") as fh:
        json.dump(man, fh, indent=2)
        fh.write("\n")
    with open(os.path.join(a.out, "SHA256SUMS"), "w") as fh:
        for r in rows:
            if "sha256" in r:
                fh.write("%s  %s\n" % (r["sha256"], r["file"]))
    print("FAMILY %s: %d chain(s)  verdict %s%s"
          % (a.family, len(rows), man["verdict"], "" if not fails else " -- " + "; ".join(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
