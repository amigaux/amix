#!/usr/bin/env python3
"""ZS-05 gate on the built objects (NOTES.md "ZS-05").

Disassembles each object with the cross objdump and checks every IPL-7
block the Z3660ETH_WRA/WRV/RDA macros emit:
  movew %sr,%dN ; oriw #1792,%sr ; <accesses> ; movew %dN,%sr
where <accesses> is exactly one of
  RDA  read A, read A
  WRA  read A, write W     with W & ~A == 0 (no bit rises from the arm)
  WRV  read A, write A, nop, read A
The offsets come from the lea/addaw that set each address register just
before the block.  Then every function must hold exactly the blocks listed
below for its form (module or static), with the arm and access offsets
given -- so a register access dropped from a block, or a new one added
without an arm, fails here.
Usage: check-zs05.py module|static OBJECT   (OBJDUMP overrides the tool)
"""
import os, re, subprocess, sys

CONFIG, ETH_TX, ETH_RX, MAC_HI, MAC_LO, RX_ADDR, INT_STATUS = \
    0x104, 0x190, 0x194, 0x198, 0x19C, 0x1A4, 0x1A8
CFG = ("WRA", RX_ADDR, CONFIG)
STROBE = ("WRA", MAC_LO, ETH_RX)
SHARED = {
    "z3660eth_map": [("RDA", MAC_HI, MAC_HI), ("RDA", MAC_LO, MAC_LO)],
    "z3660eth_initialize": [CFG],
    "z3660ethclose": [CFG],
    "z3660ethxmit": [("WRV", ETH_TX, ETH_TX)],
}
WANT = {
    "module": dict(SHARED, **{
        "z3660eth_drain": [("RDA", RX_ADDR, RX_ADDR), STROBE, STROBE, STROBE],
        "z3660eth_int6": [("RDA", INT_STATUS, INT_STATUS), CFG],
        "z3660eth_rx_work": [CFG], "z3660eth_intr_start": [CFG],
        "z3660eth_load": [CFG], "z3660eth_unload": [CFG],
        "z3660eth_halt": [CFG]}),
    "static": dict(SHARED, **{
        "z3660eth_drain": [("RDA", RX_ADDR, RX_ADDR), STROBE, STROBE],
        "z3660ethintr": [("RDA", INT_STATUS, INT_STATUS), CFG]}),
}

def fail(msg):
    print("check-zs05: FAIL " + msg)
    sys.exit(1)

def main():
    form, obj = sys.argv[1], sys.argv[2]
    tool = os.environ.get("OBJDUMP", "m68k-cbm-sysv4-objdump")
    dis = subprocess.run([tool, "-d", obj], check=True, capture_output=True,
                         text=True).stdout
    funcs, fn = {}, None
    for line in dis.splitlines():
        m = re.match(r"^[0-9a-f]+ <([^>+]+)>:$", line)
        if m:
            fn = m.group(1)
            funcs[fn] = []
            continue
        m = re.match(r"^\s*([0-9a-f]+):\t[0-9a-f ]+\t(.*)$", line)
        if m and fn:
            funcs[fn].append((int(m.group(1), 16), m.group(2).strip()))
    got = {}
    for fn, ins in funcs.items():
        for i, (a, t) in enumerate(ins):
            if t != "oriw #1792,%sr":
                continue
            m = re.match(r"movew %sr,(%d\d)$", ins[i - 1][1])
            if not m:
                fail("%s 0x%x: oriw without a saved SR" % (fn, a))
            d = m.group(1)
            body = []
            for a2, t2 in ins[i + 1:i + 7]:
                if t2 == "movew %s,%%sr" % d:
                    break
                body.append(t2)
            else:
                fail("%s 0x%x: no SR restore" % (fn, a))
            acc = []
            for t2 in body:
                r = re.match(r"movel (%a\d)@,%d\d$", t2)
                w = re.match(r"movel %d\d,(%a\d)@$", t2)
                if r:
                    acc.append(("R", r.group(1)))
                elif w:
                    acc.append(("W", w.group(1)))
                elif t2 == "nop":
                    acc.append(("N", None))
                else:
                    fail("%s 0x%x: unexpected %r in the block" % (fn, a, t2))

            def off(reg):
                for _, t3 in reversed(ins[:i - 1]):
                    m3 = re.match(r"lea %a\d@\((\d+)\)," + reg + "$", t3)
                    if m3:
                        return int(m3.group(1))
                    m3 = re.match(r"addaw #(\d+)," + reg + "$", t3)
                    if m3:
                        return int(m3.group(1))
                    if t3.endswith("," + reg):
                        return None
                return None

            shape = "".join(k for k, _ in acc)
            offs = [off(r) for k, r in acc if r]
            if None in offs:
                fail("%s 0x%x: an access register has no offset" % (fn, a))
            if shape == "RR" and offs[0] == offs[1]:
                blk = ("RDA", offs[0], offs[1])
            elif shape == "RW":
                if offs[1] & ~offs[0]:
                    fail("%s 0x%x: W $%X armed by $%X: bits rise" % (fn, a, offs[1], offs[0]))
                blk = ("WRA", offs[0], offs[1])
            elif shape == "RWNR" and offs[0] == offs[1] == offs[2]:
                blk = ("WRV", offs[0], offs[1])
            else:
                fail("%s 0x%x: block shape %s offsets %s" % (fn, a, shape, offs))
            got.setdefault(fn, []).append(blk)
    want = WANT[form]
    if got != want:
        for fn in sorted(set(got) | set(want)):
            if got.get(fn) != want.get(fn):
                print("check-zs05: %s: got %s want %s" % (fn, got.get(fn), want.get(fn)))
        fail("%s: the blocks are not the ZS-05 set" % obj)
    n = sum(len(v) for v in got.values())
    print("check-zs05: ok (%s, %s: %d armed blocks in %d functions)"
          % (form, obj, n, len(got)))

main()
