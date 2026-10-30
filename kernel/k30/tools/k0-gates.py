#!/usr/bin/env python3
"""k0-gates.py -- the K0 kernel-family gates, run by the PRODUCER.

    k0-gates.py check  --manifest <family>/MANIFEST.json [--objects-dir DIR]
    k0-gates.py media  --kernel K --media-class {z3660,generic} --manifest M [--manifest M ...]
                       [--release]
    k0-gates.py relsim --loader LOADER <kernel>          (a missing --loader is REFUSED)
    k0-gates.py scan060 <kernel> [--objects-dir DIR --family F]
    k0-gates.py spl    --object O.o --source unit.c [--cflags-env env.sh] [--cpu -m68040]
                       [--include DIR ...] [--define -DX ...] [--macro NAME ...] [--allow NOTE]
    k0-gates.py control
    k0-gates.py --selftest

Every per-family fact is read from contracts/kernel-families.json -- never from a manifest the
producer just wrote, so a family cannot self-declare its way through a gate:

  scan060   every driver object named by the family CLEAN (hard fail), and the whole kernel's
            candidate list, address-normalised, EQUAL to the frozen control's set, pinned by
            sha256 in the contract.  A NEW candidate fails the kernel; a VANISHED one is
            reported with the contract's explanation, or as UNEXPLAINED (the recipe changed).
  wd7       the W-D7 fingerprint (00dd0041 / 00dd0043) per the family's `wd7` polarity:
            "absent" = both counts 0; "required" = each count exactly 1 AND the family's
            `wd7_payload` (a sha256 the injector knows: 6a5e077e the low-nibble gate, 7b9b7301 the first payload) is the
            bytes at the detour target, exits resolved, via the injector's locate_injected().  A
            required family without a `wd7_payload`, or with one the injector does not know, is
            refused; the fingerprint counts alone no longer pass a probe.
  setuid    the port's src/patch_setuid_hook.py KERNEL --check
            must exit 0 -- the stock `setuid(-123456)` test panic is removed (bra.w at the
            derived site).  Exit 1 = the hook is LIVE (any user can panic the box), exit 2 =
            the site is not recognised; both refuse.  Every family, no polarity: a kernel
            that still carries the panic is not shippable.  The script reads only the kernel.
  cdevsw    the family's `cdevsw` map (row -> {field: symbol|null}) decoded from the kernel bytes
            (the .rela.data records at cdevsw + row*52; a null = no relocation and a zero word),
            with cdevcnt == the table's own size.  /dev/monsw is row 52 (d_open monswopen,
            d_str null) and row 50 stays the SAD STREAMS row (d_str sadinfo); a row whose d_str is
            set is a STREAMS device no matter what its d_open says, which is how row 50 fooled the
            first monsw pass.  A family without a `cdevsw` map is not judged.
  metal     a kernel bound for metal must carry W-D7 -- without the
            probe the stock autocon touches the phantom A3000 SCSI at $DD0000, which on the A4000T
            is the onboard 53C710, and the boot hangs.  A family is metal-bound when its media
            class is z3660 and it is not bench-only, or when the contract says `metal_bound`;
            such a family must have `wd7` required (and so a verified payload) unless the contract
            carries a `wd7_exempt` reason (K060, the frozen control, metal-proven before the
            probe existed).  wd7-absent families are rig-only, and the media gate refuses their
            chains from z3660 (metal) media.
  relsim    tools/relsim.py with the family's loader; this tool never runs relsim without one.
  status    the port's tools/status-facts.sh must print the build id and the artifact's sha256
            and no traceback/ERROR (it exits 0 even on a non-kernel, so the OUTPUT is judged).
  root      tools/check-chain-stamp.py on every chain row: coherence, the (card, unit) stamp,
            bo_size == the family constant (an inherited /stand/CONFIG NSWAP is
            refused), cputype, and nothing changed outside the stamped ranges.  PLUS the port's
            src/check_root_family.py (the root-storage FAMILY: scsicard[] rows, loop bound,
            queue functions; --require-queue z3660queue for a z3660scsi family), whose
            `FAMILY root=cardN(<node>)` must name exactly the stamped card and root node.
  swap      the manifest's bo_size_constant equals the contract's.
  control   candidate-3's sha256 and `sum -r` equal the frozen values, at every copy.
  spl       per driver translation unit:
            G1 (cause) -- `gcc $AMIX_KERNEL_CFLAGS -dM -E unit.c` must not define `volatile`
            EMPTY (the -traditional sys/types.h erasure that makes gcc drop the spl()/splx()
            asms); G2 (effect) -- every FUNCTION whose preprocessed body calls _spl[0-7]/splx
            (or one of the unit's own spl macros, scanned in the raw source) must carry at
            least one `,%sr` write in `objdump -d`.  Per function, not by count: tail-merged
            exits give fewer writes than sites.  A unit with `allow` (z3660eth's no-op macros)
            is reported, not failed, until the note's expiry.  Counts go into the gate log.
  media     a kernel may go onto media only if its sha256 is a chain row of a family manifest;
            a bench_only family is refused from EVERY media path; a family that carries
            z3660scsi only on media of class z3660; with --release, only shipped families.

exit 0 = every gate green, 1 = a gate refused, 2 = usage / missing input.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
FAMILIES = os.path.join(REPO, "contracts", "kernel-families.json")


def find_port():
    """The 040/060 port checkout (amix-040-060-port, the fork amix pins in kernel/port/port.pin): $PORT, else
    amix-040-060-port beside this tree (a cut's run root lays it out so), else beside the amix checkout."""
    if os.environ.get("PORT"):
        return os.path.abspath(os.environ["PORT"])
    for base in (os.path.dirname(REPO), os.path.dirname(os.path.dirname(os.path.dirname(REPO)))):
        if os.path.isdir(os.path.join(base, "amix-040-060-port")):
            return os.path.join(base, "amix-040-060-port")
    return os.path.join(os.path.dirname(REPO), "amix-040-060-port")


PORT = find_port()
AMIX = os.path.dirname(PORT)     # the directory the contracts' relative tool paths resolve against
SCAN060 = os.path.join(PORT, "test-tools", "scan060.py")
# the port's switch-table reader (6e8f973): a MOVEP candidate inside a gcc dispatch table is a misdecoded offset
SCAN060_TABLES = os.path.join(PORT, "tools", "scan060-tables.py")
STATUS_FACTS = os.path.join(PORT, "tools", "status-facts.sh")
RELSIM = os.path.join(HERE, "relsim.py")
CRF = os.path.join(HERE, "check-chain-stamp.py")
PORT_CRF = os.path.join(PORT, "src", "check_root_family.py")
SETUID_HOOK = os.path.join(PORT, "src", "patch_setuid_hook.py")
FAMILY_RE = re.compile(r"^\s*FAMILY\s+root=card(\d+)\((\S+?)\)", re.M)
OBJDUMP = "m68k-linux-gnu-objdump"
NM = "m68k-linux-gnu-nm"
WD7_PATTERNS = (("SASR 0xDD0041", bytes.fromhex("00dd0041")),
                ("SCMD 0xDD0043", bytes.fromhex("00dd0043")))
Z3660SCSI_SYMS = (b"z3660queue\0", b"z3660intr\0", b"z3660present\0")
# the toolchain: gcc-cross-amix's build/ directory ($GCA, toolchain/README.md)
GCA = os.path.abspath(os.environ["GCA"]) if os.environ.get("GCA") else os.path.join(AMIX, "gcc-cross-amix", "build")
# test fixtures that are real kernels (opt-in; absent = those selftest cases are skipped)
K0_FIXTURES = os.environ.get("K0_FIXTURES", "")


def fixture(name):
    return os.path.join(K0_FIXTURES, name) if K0_FIXTURES else os.path.join(HERE, "no-such-fixture", name)


def cross_bin():
    """The cross binutils' bin/: $AMIX_CROSS_PREFIX/bin, else the AMIX_CROSS_PREFIX that $GCA/env.sh exports."""
    pre = os.environ.get("AMIX_CROSS_PREFIX", "")
    if not pre:
        try:
            m = re.search(r'AMIX_CROSS_PREFIX="([^"]*)"', open(os.path.join(GCA, "env.sh")).read())
            pre = m.group(1) if m else ""
        except OSError:
            pre = ""
    return os.path.join(pre, "bin") if pre else ""


def cross_path():
    b = cross_bin()
    return b + os.pathsep + os.environ.get("PATH", "") if b else os.environ.get("PATH", "")


class Gate(object):
    def __init__(self):
        self.lines = []
        self.bad = 0

    def ok(self, gate, what):
        self.lines.append("PASS    %-8s %s" % (gate, what))

    def fail(self, gate, what):
        self.lines.append("REFUSED %-8s %s" % (gate, what))
        self.bad += 1

    def note(self, gate, what):
        self.lines.append("NOTE    %-8s %s" % (gate, what))

    def dump(self):
        for ln in self.lines:
            print(ln)


def load_families(path=FAMILIES):
    with open(path) as fh:
        return json.load(fh)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def sum_r(buf):
    s = 0
    for c in buf:
        s = (s >> 1) + ((s & 1) << 15)
        s = (s + c) & 0xFFFF
    return s


def amix_path(p):
    """A contract's tool path: absolute as given; amix-040-060-port/... in PORT; gcc-cross-amix/build/... in GCA;
    anything else beside the port checkout."""
    if os.path.isabs(p):
        return p
    parts = p.split("/")
    if parts[0] == "amix-040-060-port":
        return os.path.join(PORT, *parts[1:])
    if parts[:2] == ["gcc-cross-amix", "build"]:
        return os.path.join(GCA, *parts[2:])
    return os.path.join(AMIX, p)


# ---------------------------------------------------------------- scan060 --

CAND_RE = re.compile(r"^\s+[0-9a-f]+\s{2}(\S.*?)\s*$")


def normalise(scan_text):
    """scan060 candidate lines -> sorted list with the address column dropped and every
    PC-relative target `@(<hex> <SYM>)` reduced to `@(<SYM>)`: a relink moves addresses, not
    instructions.  Header/verdict lines are not candidates."""
    out = []
    for ln in scan_text.splitlines():
        m = CAND_RE.match(ln)
        if not m or ln.lstrip().startswith(("==", "total", "CLEAN")):
            continue
        body = re.sub(r"@\([0-9a-f]+ <", "@(<", m.group(1))
        out.append(re.sub(r"\s+", " ", body))
    return sorted(out)


def set_sha(lines):
    return hashlib.sha256(("\n".join(lines) + "\n").encode()).hexdigest()


def code_bytes(path):
    """Total size of the CODE sections (objdump -h), so an empty listing can be told apart:
    a data-only object (z3660_cache_arm.o) legitimately decodes 0 lines."""
    r = subprocess.run([OBJDUMP, "-h", path], capture_output=True, text=True,
                       env=dict(os.environ, LC_ALL="C"))
    total, lines = 0, r.stdout.splitlines()
    for i, ln in enumerate(lines[:-1]):
        f = ln.split()
        if len(f) >= 7 and f[0].isdigit() and "CODE" in lines[i + 1]:
            total += int(f[2], 16)
    return total if r.returncode == 0 else None


def run_scan060(path, tables=False):
    """objdump -d + scan060.py.  Returns (verdict, text): verdict CLEAN | NO-CODE | CANDIDATES
    | UNREADABLE.  tables=True also runs the port's scan060-tables.py over the same listing and returns
    (verdict, text, (rc, tables_text))."""
    lst = subprocess.run([OBJDUMP, "-d", path], capture_output=True, text=True,
                         env=dict(os.environ, LC_ALL="C"))
    if lst.returncode != 0:
        return ("UNREADABLE", lst.stderr) + (((2, ""),) if tables else ())
    with tempfile.NamedTemporaryFile("w", suffix=".lst", delete=False) as fh:
        fh.write(lst.stdout)
        tmp = fh.name
    try:
        r = subprocess.run([sys.executable, SCAN060, tmp], capture_output=True, text=True)
        t = subprocess.run([sys.executable, SCAN060_TABLES, tmp], capture_output=True, text=True) if tables else None
    finally:
        os.unlink(tmp)
    v = scan_verdict(r.stdout, code_bytes(path))
    return (v, r.stdout, (t.returncode, t.stdout + t.stderr)) if tables else (v, r.stdout)


TABLE_OK_RE = re.compile(r"^\s+([0-9a-f]+) (movep\S*): inside the table at [0-9a-f]+ -- a misdecoded offset, accepted$")


def tables_pin(g, fam):
    """The family's scan060_tables record: the reader's sha256 pinned (a newer reader cannot move the gate).
    Returns True when the allowance may be used."""
    rec = fam.get("scan060_tables")
    if not rec:
        return False
    try:
        sha = hashlib.sha256(open(SCAN060_TABLES, "rb").read()).hexdigest()
    except OSError as e:
        g.fail("scan060", "scan060_tables: the reader is absent (%s)" % e)
        return False
    if sha != rec.get("sha256"):
        g.fail("scan060", "scan060_tables: %s sha256 %s is not the pinned %s"
               % (os.path.relpath(SCAN060_TABLES, AMIX), sha[:16], str(rec.get("sha256"))[:16]))
        return False
    return True


def scan_verdict(text, code=None):
    m = re.search(r"\((\d+) decoded lines\)", text)
    if m and int(m.group(1)) == 0 and code == 0:
        return "NO-CODE"                        # nothing to decode, and nothing was hidden
    if not m or int(m.group(1)) == 0:
        return "UNREADABLE"
    if "CLEAN -- no candidate found" in text:
        return "CLEAN"
    if re.search(r"total candidates: *\d+", text):
        return "CANDIDATES"
    return "UNREADABLE"


def judge_whole_kernel(g, cand, fam, fams, accepted=(), known=()):
    sc = fams["scan060"]
    ctl_file = os.path.join(REPO, sc["control_set_file"])
    with open(ctl_file) as fh:
        ctl = [ln.rstrip("\n") for ln in fh if ln.strip()]
    if set_sha(ctl) != sc["control_set_sha256"]:
        g.fail("scan060", "the pinned control set %s does not hash to the contract's %s"
               % (sc["control_set_file"], sc["control_set_sha256"][:16]))
        return
    from collections import Counter
    have, want = Counter(cand), Counter(ctl)
    new = list((have - want).elements())
    gone = list((want - have).elements())
    # the switch-table allowance: a NEW candidate the pinned scan060-tables.py proved to be a MOVEP inside a
    # gcc dispatch table is a misdecoded offset, not an instruction; anything else stays a failure
    table_new = list((Counter(new) & Counter(accepted)).elements())
    new = list((Counter(new) - Counter(accepted)).elements())
    # the known-data allowance: a NEW candidate at the family's named <anchor> + <offset> is data
    known_new = list((Counter(new) & Counter(known)).elements())
    new = list((Counter(new) - Counter(known)).elements())
    for t in table_new:
        g.note("scan060", "table entry, not an instruction (scan060-tables.py): %s" % t)
    for t in known_new:
        g.note("scan060", "known data, not an instruction (scan060_known_data): %s" % t)
    if new:
        g.fail("scan060", "%d NEW whole-kernel candidate(s) beyond the control's set: %s"
               % (len(new), "; ".join(new[:4])))
    else:
        g.ok("scan060", "whole kernel: %d candidate(s), none beyond the frozen control's %d "
             "(set sha %s)" % (len(cand), len(ctl), sc["control_set_sha256"][:16]))
    why = fam.get("scan060_vanished", {})
    for v in gone:
        g.note("scan060", "VANISHED vs control: %s -- %s"
               % (v, why.get(v, "UNEXPLAINED: a stock instruction disappeared, so the recipe "
                                 "changed; say why in the family's scan060_vanished")))


ADDR_RE = re.compile(r"^\s+([0-9a-f]+)\s{2}\S")


def scan_hits(text):
    """scan060 candidate lines -> [(address, normalised line)]."""
    return [(int(m.group(1), 16), normalise(ln)[0]) for ln in text.splitlines()
            for m in [ADDR_RE.match(ln)] if m and normalise(ln)]


def sym_value(path, name):
    """The value of the one global/local symbol `name` in an ELF (nm), or None when it is not exactly one."""
    r = subprocess.run([NM, path], capture_output=True, text=True, env=dict(os.environ, LC_ALL="C"))
    vals = [int(f[0], 16) for f in (ln.split() for ln in r.stdout.splitlines()) if len(f) == 3 and f[2] == name]
    return vals[0] if len(vals) == 1 else None


def known_data_objects(fam):
    return {k["object"]: k for k in fam.get("scan060_known_data", [])}


def known_data_object(g, p, obj, rec):
    """a driver object whose scan060 candidates are DATA the family names one by one (the 68060 ISP's
    offset-table word): the object's sha256 is pinned and its candidates must be exactly the named
    (offset, line) set -- one more, one fewer or one moved fails."""
    if rec.get("sha256") and sha256_file(p) != rec["sha256"]:
        g.fail("scan060", "driver object %s: sha256 %s is not the pinned %s (the known-data allowance was judged "
               "on those bytes)" % (obj, sha256_file(p)[:16], rec["sha256"][:16]))
        return
    v, text = run_scan060(p)
    want = sorted((int(h["offset"], 16), h["line"]) for h in rec["hits"])
    have = sorted(scan_hits(text))
    (g.ok if v == "CANDIDATES" and have == want else g.fail)(
        "scan060", "driver object %s: %s, %d candidate(s) %s the %d named known-data word(s) (%s)"
        % (obj, v, len(have), "==" if have == want else "!=", len(want), rec.get("why", "")[:80]))


def known_data_kernel(kernel, text, fam):
    """The whole-kernel side: a candidate is known data only at <anchor symbol> + <offset> with the named line."""
    out = []
    hits = scan_hits(text)
    for rec in fam.get("scan060_known_data", []):
        base = sym_value(kernel, rec["anchor"])
        if base is None:
            continue
        for h in rec["hits"]:
            at = base + int(h["offset"], 16)
            out += [ln for a, ln in hits if a == at and ln == h["line"]]
    return out


def gate_scan060(g, kernel, fam, fams, objects_dir=None):
    v_tables = tables_pin(g, fam)
    for obj in fam.get("driver_objects", []):
        if objects_dir is None:
            g.note("scan060", "driver objects not checked (no --objects-dir)")
            break
        p = os.path.join(objects_dir, obj)
        if not os.path.isfile(p):
            g.fail("scan060", "driver object %s missing in %s" % (obj, objects_dir))
            continue
        if obj in known_data_objects(fam):
            known_data_object(g, p, obj, known_data_objects(fam)[obj])
            continue
        if v_tables and obj in fam["scan060_tables"].get("objects", []):
            v, _, (trc, ttext) = run_scan060(p, tables=True)
            if v == "CANDIDATES" and trc == 0:
                g.ok("scan060", "driver object %s: every candidate is a MOVEP inside a gcc switch table "
                     "(scan060-tables.py: %s)" % (obj, ttext.strip().splitlines()[-1].strip()))
                continue
        else:
            v, _ = run_scan060(p)
        (g.ok if v in ("CLEAN", "NO-CODE") else g.fail)("scan060", "driver object %s: %s"
                                                          % (obj, v))
    gate_scan060_kernel(g, kernel, fam, fams, v_tables)


def gate_scan060_kernel(g, kernel, fam, fams, v_tables):
    """The whole-kernel half of scan060 (every chain), with the family's switch-table allowance."""
    if v_tables:
        v, text, (_trc, ttext) = run_scan060(kernel, tables=True)
        ok_at = {int(m.group(1), 16) for m in (TABLE_OK_RE.match(ln) for ln in ttext.splitlines()) if m}
        accepted = normalise("\n".join(ln for ln in text.splitlines()
                                       if re.match(r"^\s+([0-9a-f]+)\s{2}", ln)
                                       and int(ln.split()[0], 16) in ok_at))
    else:
        v, text = run_scan060(kernel)
        accepted = []
    if v == "UNREADABLE":
        g.fail("scan060", "%s: scan060 produced no verdict" % kernel)
        return
    judge_whole_kernel(g, normalise(text), fam, fams, accepted, known_data_kernel(kernel, text, fam))


# -------------------------------------------------------------------- wd7 --

INJECTOR = os.path.join(HERE, "kernel-support-probe-inject.py")


def injector():
    """tools/kernel-support-probe-inject.py as a module (the payload registry + locate_injected)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("kernel_support_probe_inject", INJECTOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gate_wd7(g, data, fam, label):
    pol = fam.get("wd7")
    counts = [data.count(p) for _, p in WD7_PATTERNS]
    desc = ", ".join("%s x%d" % (n, c) for (n, _), c in zip(WD7_PATTERNS, counts))
    if pol == "absent":
        (g.ok if counts == [0, 0] else g.fail)("wd7", "%s: polarity absent, %s" % (label, desc))
    elif pol == "required":
        if counts != [1, 1]:
            g.fail("wd7", "%s: polarity required, %s" % (label, desc))
            return
        want = fam.get("wd7_payload")
        if not want:
            g.fail("wd7", "%s: polarity required but the family declares no wd7_payload" % label)
            return
        try:
            inj = injector()
        except Exception as e:                       # noqa: BLE001 -- the gate must not pass by accident
            g.fail("wd7", "%s: cannot load the injector (%s)" % (label, e))
            return
        payload = inj.PAYLOADS.get(want)
        if payload is None:
            g.fail("wd7", "%s: wd7_payload %s is not a payload the injector knows (%s)"
                   % (label, want[:16], ", ".join(k[:8] for k in inj.PAYLOADS)))
            return
        try:
            facts = inj.locate_injected(data, probe=payload)
        except inj.Refused as e:
            g.fail("wd7", "%s: payload %s not verified -- %s" % (label, want[:8], "; ".join(e.args[0])))
            return
        g.ok("wd7", "%s: polarity required, %s; payload %s verified at .text+0x%x (detour at autocon+0x%x)"
             % (label, desc, want[:8], facts["probe_at"], facts["guess"] - facts["autocon"]))
    else:
        g.fail("wd7", "family has no valid wd7 polarity (%r) -- absent|required" % (pol,))


# ----------------------------------------------------------------- setuid --

SDDEVSIZE_INJECT = os.path.join(HERE, "kernel-sddevsize-inject.py")


def gate_sddevsize(g, kernel, fam, label):
    """a 040/060 family that declares `sddevsize: fixed` must carry the partition-size fix (sddevsize's never-opened
    default 0x3FFFFF, tools/kernel-sddevsize-inject.py verify); a family that declares nothing is noted as stock."""
    want = fam.get("sddevsize")
    if want is None:
        g.note("sddevsize", "%s: family declares no sddevsize -- the stock 1234567-block default (the stock cap)" % label)
        return
    if want != "fixed":
        g.fail("sddevsize", "%s: family sddevsize %r is not `fixed`" % (label, want))
        return
    r = subprocess.run([sys.executable, SDDEVSIZE_INJECT, "verify", kernel], capture_output=True, text=True)
    (g.ok if r.returncode == 0 else g.fail)("sddevsize", "%s: %s" % (label, (r.stdout + r.stderr).strip().splitlines()[-1][:160]))


def gate_rth1(g, kernel, fam, label):
    """a family declaring `rth1: required` carries the RTH1 kernel half -- main's one `jsr
    vfs_mountroot` retargeted to rth1_mountroot (which calls vfs_mountroot), rth1_used/rth1_why unset, sdcardbase
    linked -- as judged by the port's own checker at the sha the family pins (a newer checker cannot move the
    gate), and the `/dev/dsk/c` literal the root stampers and check_root_family anchor on is still unique.
    A family that declares nothing must not carry the hook."""
    want = fam.get("rth1")
    with open(kernel, "rb") as fh:
        data = fh.read()
    if want is None:
        if b"rth1_mountroot" in data:
            g.fail("rth1", "%s: carries rth1_mountroot but the family declares no rth1" % label)
        else:
            g.note("rth1", "%s: family declares no rth1 (root as compiled)" % label)
        return
    if want != "required":
        g.fail("rth1", "%s: family rth1 %r is not `required`" % (label, want))
        return
    hook = fam.get("rth1_hook") or {}
    tool = amix_path(hook.get("tool", ""))
    if not hook.get("tool") or not os.path.isfile(tool):
        g.fail("rth1", "%s: the family's rth1_hook.tool is missing (%r)" % (label, hook.get("tool")))
        return
    if sha256_file(tool) != hook.get("sha256"):
        g.fail("rth1", "%s: %s sha256 %s is not the pinned %s" % (label, hook["tool"], sha256_file(tool)[:16],
                                                                   str(hook.get("sha256"))[:16]))
        return
    r = subprocess.run([sys.executable, tool, "--check", kernel], capture_output=True, text=True)
    last = ((r.stdout + r.stderr).strip().splitlines() or ["(no output)"])[-1].strip()
    (g.ok if r.returncode == 0 else g.fail)("rth1", "%s: %s" % (label, last[:170]))
    n = data.count(b"/dev/dsk/c")
    (g.ok if n == 1 else g.fail)("rth1", "%s: the /dev/dsk/c anchor occurs %d time(s) (must be 1)" % (label, n))


def gate_ttcompat(g, kernel, fam, label):
    """a family declaring `ttcompat_fix: required` carries the port's opt-in ttcompat
    init fix -- the stock ttcompatopen leaves t_state/t_iocid/t_ioccmd uninitialised -- as judged by the port's
    own patch_ttcompat_init.py --check (0 = fixed, 1 = stock) at the sha the family pins. A family that declares
    nothing must carry the STOCK bytes (the r6-as-decided set must not pick the fix up silently)."""
    want = fam.get("ttcompat_fix")
    tool = fam.get("ttcompat_tool") or {}
    path = amix_path(tool.get("tool", "amix-040-060-port/src/patch_ttcompat_init.py"))
    if want not in (None, "required"):
        g.fail("ttcompat", "%s: family ttcompat_fix %r is not `required`" % (label, want))
        return
    if not os.path.isfile(path):
        (g.fail if want else g.note)("ttcompat", "%s: the port's patch_ttcompat_init.py is absent (%s)" % (label, path))
        return
    if want and sha256_file(path) != tool.get("sha256"):
        g.fail("ttcompat", "%s: %s sha256 %s is not the pinned %s" % (label, tool.get("tool"), sha256_file(path)[:16],
                                                                      str(tool.get("sha256"))[:16]))
        return
    r = subprocess.run([sys.executable, path, "--check", kernel], capture_output=True, text=True)
    last = ((r.stdout + r.stderr).strip().splitlines() or ["(no output)"])[-1].strip()[:150]
    if want:
        (g.ok if r.returncode == 0 else g.fail)("ttcompat", "%s: %s" % (label, last))
    elif r.returncode == 1:
        g.note("ttcompat", "%s: stock ttcompatopen (family declares no fix): %s" % (label, last))
    elif r.returncode == 0:
        g.fail("ttcompat", "%s: carries the ttcompat fix but the family declares none" % label)
    else:
        g.note("ttcompat", "%s: checker rc %d: %s" % (label, r.returncode, last))


PORT_CHECKS = {
    # gate: (family key, family tool key, the port's checker, what it proves)
    "pgrsv": ("pgrsv", "pgrsv_tool", "amix-040-060-port/src/patch_pgrsv_sites.py",
              "the page-out reserve (DRIVER-LINE-8): the page_get callers -> pgrsv_get"),
    "isp060": ("isp060", "isp060_tool", "amix-040-060-port/src/patch_isp060_hook.py",
               "the 68060 ISP (DRIVER-LINE-9) behind isp61's declines"),
    "tcp_hiwat": ("tcp_hiwat", "tcp_hiwat_tool", "amix-040-060-port/src/patch_tcp_hiwat.py",
                  "the TCP lower-read hiwat 16384 (DRIVER-LINE-10)"),
}
# tcp_hiwat is judged on EVERY chain, a family's `gates` list notwithstanding -- the checker
# reads the 030 and the 060 line alike, and an undeclared family must still prove it carries the stock word.
EVERY_CHAIN = {"tcp_hiwat"}


def gate_port_check(g, kernel, fam, label, gate):
    """a family declaring `<gate>: required` carries the port pass, as judged by the port's
    own --check (0 = present, else absent/refused) at the sha the family pins. A family that declares nothing
    must NOT carry it (an accepted family cannot pick a pass up silently)."""
    key, tkey, default, what = PORT_CHECKS[gate]
    want = fam.get(key)
    tool = fam.get(tkey) or {}
    path = amix_path(tool.get("tool", default))
    if want not in (None, "required"):
        g.fail(gate, "%s: family %s %r is not `required`" % (label, key, want))
        return
    if not os.path.isfile(path):
        (g.fail if want else g.note)(gate, "%s: the port's %s is absent (%s)" % (label, os.path.basename(default), path))
        return
    if want and sha256_file(path) != tool.get("sha256"):
        g.fail(gate, "%s: %s sha256 %s is not the pinned %s" % (label, tool.get("tool"), sha256_file(path)[:16],
                                                                str(tool.get("sha256"))[:16]))
        return
    r = subprocess.run([sys.executable, path, "--check", kernel], capture_output=True, text=True)
    last = ((r.stdout + r.stderr).strip().splitlines() or ["(no output)"])[-1].strip()[:170]
    if want:
        (g.ok if r.returncode == 0 else g.fail)(gate, "%s: %s" % (label, last))
    elif r.returncode == 0:
        g.fail(gate, "%s: carries %s but the family declares none" % (label, what))
    else:
        g.note(gate, "%s: absent, as the family declares (%s)" % (label, last[:100]))


def gate_setuid(g, kernel, label, script=SETUID_HOOK):
    """the port's checker, --check only (it reads the kernel and writes nothing)."""
    if not os.path.isfile(script):
        g.fail("setuid", "%s: REFUSED -- the port's src/patch_setuid_hook.py is absent at %s"
               % (label, script))
        return
    r = subprocess.run([sys.executable, script, kernel, "--check"], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().splitlines()
    last = out[-1].strip() if out else "(no output)"
    if r.returncode == 0:
        g.ok("setuid", "%s: %s" % (label, last))
    elif r.returncode == 1:
        g.fail("setuid", "%s: setuid hook LIVE -- %s" % (label, last))
    elif r.returncode == 2:
        g.fail("setuid", "%s: site not recognised -- %s" % (label, last))
    else:
        g.fail("setuid", "%s: patch_setuid_hook.py --check rc %d -- %s" % (label, r.returncode, last))


# ----------------------------------------------------------------- cdevsw --

CDEVSW_FIELDS = ["d_open", "d_close", "d_read", "d_write", "d_ioctl", "d_mmap", "d_segmap",
                 "d_poll", "d_xpoll", "d_xhalt", "d_ttys", "d_str", "d_flag"]
CDEVSW_ENTSIZE = 52


def decode_cdevsw(data):
    """Rows of cdevsw[] in an ET_REL kernel: {row: {field: symbol-or-None}}, cdevcnt, table rows."""
    u16 = lambda o: struct.unpack(">H", data[o:o + 2])[0]
    u32 = lambda o: struct.unpack(">I", data[o:o + 4])[0]
    if data[:4] != b"\x7fELF":
        raise ValueError("not ELF")
    so, se, sn, ss = u32(32), u16(46), u16(48), u16(50)
    sh = [dict(name=u32(so + i * se), offset=u32(so + i * se + 16), size=u32(so + i * se + 20),
               link=u32(so + i * se + 24), entsize=u32(so + i * se + 36)) for i in range(sn)]
    sb = sh[ss]["offset"]
    names = [data[sb + h["name"]:data.index(b"\0", sb + h["name"])].decode() for h in sh]
    sec = dict(zip(names, sh))
    for need in (".symtab", ".data", ".rela.data"):
        if need not in sec:
            raise ValueError("no %s section" % need)
    st = sec[".symtab"]; stro = sh[st["link"]]["offset"]
    syms = []
    for i in range(st["size"] // st["entsize"]):
        o = st["offset"] + i * st["entsize"]; n = u32(o)
        syms.append((data[stro + n:data.index(b"\0", stro + n)].decode(), u32(o + 4), u16(o + 14)))
    byname = dict((n, (v, sh_)) for n, v, sh_ in syms)
    if "cdevsw" not in byname or "cdevcnt" not in byname:
        raise ValueError("no cdevsw/cdevcnt symbol")
    cd, cdsec = byname["cdevsw"]; cnt, cntsec = byname["cdevcnt"]
    if names[cdsec] != ".data" or names[cntsec] != ".data":
        raise ValueError("cdevsw/cdevcnt not in .data")
    dofs = sec[".data"]["offset"]
    rela = sec[".rela.data"]; rel = {}
    for i in range(rela["size"] // rela["entsize"]):
        o = rela["offset"] + i * rela["entsize"]
        rel[u32(o)] = syms[u32(o + 4) >> 8][0]
    ncnt = u32(dofs + cnt)
    rows = {}
    for r in range(ncnt):
        base = cd + r * CDEVSW_ENTSIZE
        rows[r] = {}
        for i, f in enumerate(CDEVSW_FIELDS):
            off = base + i * 4
            if off in rel:
                rows[r][f] = rel[off]
            else:
                w = u32(dofs + off)
                rows[r][f] = None if w == 0 else "0x%x" % w
    return rows, ncnt, (cnt - cd) // CDEVSW_ENTSIZE


def gate_cdevsw(g, kernel, fam, label):
    want = fam.get("cdevsw")
    if not want:
        return
    with open(kernel, "rb") as fh:
        data = fh.read()
    try:
        rows, ncnt, table_rows = decode_cdevsw(data)
    except (ValueError, IndexError, struct.error, UnicodeDecodeError) as e:
        g.fail("cdevsw", "%s: cannot decode cdevsw[] (%s)" % (label, e))
        return
    if ncnt != table_rows:
        g.fail("cdevsw", "%s: cdevcnt %d != the table's %d rows (cdevsw..cdevcnt / %d)"
               % (label, ncnt, table_rows, CDEVSW_ENTSIZE))
    for row, fields in sorted(want.items(), key=lambda kv: int(kv[0])):
        r = int(row)
        if r >= ncnt:
            g.fail("cdevsw", "%s: row %d beyond cdevcnt %d" % (label, r, ncnt))
            continue
        bad = []
        for f, sym in fields.items():
            if f not in CDEVSW_FIELDS:
                bad.append("%s: not a cdevsw field" % f)
                continue
            got = rows[r].get(f)
            if got != sym:
                bad.append("%s=%s (contract %s)" % (f, got, sym))
        desc = " ".join("%s=%s" % (f, rows[r].get(f)) for f in fields)
        if bad:
            g.fail("cdevsw", "%s: row %d: %s" % (label, r, "; ".join(bad)))
        else:
            g.ok("cdevsw", "%s: row %d %s" % (label, r, desc))


# ----------------------------------------------------------------- relsim --

def gate_relsim(g, kernel, loader, label):
    if loader == "stock":                  # the 030 line boots through the stock unix_boot chain: rel.c as relsim models it
        r = subprocess.run([sys.executable, RELSIM, kernel], capture_output=True, text=True)
        comp = re.findall(r"COMPLAINTS \(would fire D245\): (\d+)", r.stdout)
        if r.returncode == 0 and comp and comp[-1] == "0":
            g.ok("relsim", "%s: stock loader (rel.c), 0 complaints" % label)
        else:
            g.fail("relsim", "%s: stock loader rc %d, complaints %s" % (label, r.returncode, comp[-1] if comp else "?"))
        return
    if not loader:
        g.fail("relsim", "%s: no --loader -- REFUSED.  The stock default models the wrong "
               "loader for the 040/060 line (330 fpe PC-relative complaints on candidate-3 "
               "itself); name the loader the family boots through" % label)
        return
    r = subprocess.run([sys.executable, RELSIM, "--loader", loader, kernel],
                       capture_output=True, text=True)
    comp = re.findall(r"COMPLAINTS \(would fire D245\): (\d+)", r.stdout)
    if r.returncode == 0 and comp and comp[-1] == "0":
        g.ok("relsim", "%s: --loader %s, 0 complaints" % (label, loader))
    else:
        g.fail("relsim", "%s: --loader %s rc %d, complaints %s"
               % (label, loader, r.returncode, comp[-1] if comp else "?"))


# ----------------------------------------------------------------- status --

def gate_status(g, kernel, label):
    env = dict(os.environ, PATH=cross_path())
    r = subprocess.run(["sh", STATUS_FACTS, kernel], capture_output=True, text=True, env=env)
    out = r.stdout + r.stderr
    sha = sha256_file(kernel)
    problems = []
    if r.returncode != 0:
        problems.append("rc %d" % r.returncode)
    if "Traceback" in out or re.search(r"^ERROR", out, re.M):
        problems.append("traceback/ERROR in the output")
    if not re.search(r"^build id\s+680[46]0-\d{6}-\d+", out, re.M):
        problems.append("no build id line")
    if not re.search(r"^sha256\s+%s" % sha, out, re.M):
        problems.append("sha256 line missing or not this artifact's")
    if problems:
        g.fail("status", "%s: %s" % (label, "; ".join(problems)))
    else:
        bid = re.search(r"^build id\s+(\S+)", out, re.M).group(1)
        g.ok("status", "%s: build id %s, sha256 matches" % (label, bid))


# -------------------------------------------------------------- root/swap --

def gate_root(g, chain, row, fam, base, label):
    if row.get("floppy"):
        # contract rootdev.floppy: the chain carries FD0P + /dev/fakeswap, no card/unit
        r = subprocess.run([sys.executable, CRF, chain, "--floppy", "--cputype", str(fam["cputype"]),
                            "--bo-size", str(fam["bo_size"])] + (["--base", base] if base else []),
                           capture_output=True, text=True)
        if r.returncode == 0:
            g.ok("root", "%s: check-chain-stamp --floppy PASS (FD0P + /dev/fakeswap, bo_size %d)" % (label, fam["bo_size"]))
        else:
            g.fail("root", "%s: %s" % (label, " | ".join(
                ln.strip() for ln in r.stdout.splitlines() if ln.strip().startswith("-"))))
        return
    r = subprocess.run([sys.executable, CRF, chain, "--card", str(row["card"]),
                        "--unit", str(row["unit"]), "--cputype", str(fam["cputype"]),
                        "--bo-size", str(fam["bo_size"])] + (["--base", base] if base else []),
                       capture_output=True, text=True)
    if r.returncode == 0:
        g.ok("root", "%s: check-chain-stamp PASS (card %d unit %d, bo_size %d)"
             % (label, row["card"], row["unit"], fam["bo_size"]))
    else:
        g.fail("root", "%s: %s" % (label, " | ".join(
            ln.strip() for ln in r.stdout.splitlines() if ln.strip().startswith("-"))))


def judge_family(g, out, rc, row, label):
    """The port's FAMILY line must name the stamped card and root node; a coherent family that
    roots somewhere else is the Round-6 failure (root through the wrong controller)."""
    if row.get("floppy"):
        # the port's check_root_family names a contract floppy root `root=floppy(FD0P)` (port 7005281)
        if rc != 0 or "[ok]   root-storage family coherent" not in out:
            g.fail("family", "%s: port check_root_family rc %d, family not coherent" % (label, rc))
        elif not re.search(r"^\s*FAMILY\s+root=floppy\(FD0P\)", out, re.M):
            g.fail("family", "%s: port check_root_family does not name the floppy root (FAMILY root=floppy(FD0P))" % label)
        else:
            g.ok("family", "%s: port check_root_family coherent, FAMILY root=floppy(FD0P) == the floppy stamp" % label)
        return
    m = FAMILY_RE.search(out)
    want_node = "/dev/dsk/c%xd0s1" % (8 * row["card"] + row["unit"])  # C4-1 section 2.2
    if rc != 0 or "[ok]   root-storage family coherent" not in out:
        g.fail("family", "%s: port check_root_family rc %d, family not coherent" % (label, rc))
    elif not m:
        g.fail("family", "%s: port check_root_family printed no FAMILY line" % label)
    elif int(m.group(1)) != row["card"] or m.group(2) != want_node:
        g.fail("family", "%s: FAMILY root=card%s(%s) disagrees with the stamp card %d (%s)"
               % (label, m.group(1), m.group(2), row["card"], want_node))
    else:
        g.ok("family", "%s: port check_root_family coherent, FAMILY root=card%s(%s) == stamp"
             % (label, m.group(1), m.group(2)))


def gate_family(g, chain, row, fam, label):
    args = [sys.executable, PORT_CRF, chain]
    if "z3660scsi" in fam.get("drivers", []):
        args += ["--require-queue", "z3660queue"]
    if "a4091" in fam.get("drivers", []):
        args += ["--require-queue", "a4091queue"]      # the A4091 family's rows must be there
    r = subprocess.run(args, capture_output=True, text=True)
    judge_family(g, r.stdout + r.stderr, r.returncode, row, label)


def gate_swap(g, man, fam):
    got = man.get("bo_size_constant")
    if got == fam["bo_size"]:
        g.ok("swap", "manifest bo_size_constant %d == the family constant (D13)" % got)
    else:
        g.fail("swap", "manifest bo_size_constant %r != the family constant %d -- a swap length "
               "from an inherited /stand/CONFIG NSWAP is refused (D13)" % (got, fam["bo_size"]))


# ----------------------------------------------------------------- policy --

def gate_policy(g, man, fam):
    """The manifest carries the family's policy (wd7 polarity, media class, bench_only ...) as
    emitted; it must still equal the contract, which is what every gate actually reads."""
    if man.get("family_policy") != fam:
        g.fail("policy", "the manifest's family_policy differs from contracts/kernel-families.json "
               "(or is missing) -- the manifest was emitted under another policy; re-emit")
    else:
        g.ok("policy", "manifest family_policy == the contract (wd7 %s, media %s, bench_only %s)"
             % (fam.get("wd7"), fam.get("media_class"), fam.get("bench_only")))


def metal_bound(fam):
    return bool(fam.get("metal_bound")) or (fam.get("media_class") == "z3660" and not fam.get("bench_only"))


def gate_metal(g, fam, label):
    """a metal-bound family carries W-D7 (wd7 required) or is explicitly exempt."""
    if not metal_bound(fam):
        g.ok("metal", "%s: not metal-bound (rig-only%s)" % (label, ", wd7 %s" % fam.get("wd7")))
        return
    if fam.get("wd7") == "required":
        g.ok("metal", "%s: metal-bound, wd7 required (payload %s)" % (label, str(fam.get("wd7_payload"))[:8]))
    elif fam.get("wd7_exempt"):
        g.note("metal", "%s: metal-bound WITHOUT W-D7, exempt: %s" % (label, fam["wd7_exempt"]))
        g.ok("metal", "%s: exemption recorded in the contract" % label)
    else:
        g.fail("metal", "%s: metal-bound (media %s, bench_only %s, metal_bound %s) but wd7 %r -- a kernel "
               "without W-D7 touches the phantom A3000 SCSI at $DD0000 = the A4000T's onboard 53C710; "
               "inject the probe or mark the family rig-only"
               % (label, fam.get("media_class"), fam.get("bench_only"), fam.get("metal_bound"), fam.get("wd7")))


# ---------------------------------------------------------------- control --

def gate_control(g, fams):
    c = fams["control"]
    for p in c["paths"]:
        ap = amix_path(p)
        if not os.path.isfile(ap):
            g.fail("control", "%s: missing" % p)
            continue
        with open(ap, "rb") as fh:
            data = fh.read()
        sha, s = hashlib.sha256(data).hexdigest(), sum_r(data)
        if sha == c["sha256"] and s == c["sum_r"]:
            g.ok("control", "%s unchanged: sha256 %s sum -r %05d" % (p, sha[:16], s))
        else:
            g.fail("control", "%s CHANGED: sha256 %s sum -r %05d (frozen %s / %05d)"
                   % (p, sha[:16], s, c["sha256"][:16], c["sum_r"]))


# ------------------------------------------------------------------ media --

def gate_media(g, kernel, media_class, manifests, fams, release=False):
    sha = sha256_file(kernel)
    with open(kernel, "rb") as fh:
        data = fh.read()
    hit = None
    for mp in manifests:
        with open(mp) as fh:
            man = json.load(fh)
        for row in man.get("chains", []):
            if row.get("sha256") == sha:
                hit = (man["family"], row, mp)
    if hit is None:
        g.fail("media", "%s (sha %s) is not a chain row of any given family manifest -- only "
               "manifest-listed chains go onto media" % (kernel, sha[:16]))
        return
    famname, row, mp = hit
    fam = fams["families"].get(famname)
    if fam is None:
        g.fail("media", "family %s is not in contracts/kernel-families.json" % famname)
        return
    label = "%s (%s c%d u%d)" % (os.path.basename(kernel), famname, row["card"], row["unit"])
    if fam.get("bench_only"):
        g.fail("media", "%s: family %s is BENCH-ONLY -- refused from every media path"
               % (label, famname))
        return
    # floppy chains (contract rootdev.floppy) go onto floppy media only, and floppy media take nothing else
    if (fam.get("media_class") == "floppy") != (media_class == "floppy"):
        g.fail("media", "%s: family media_class %r onto %r media -- a floppy-rooted kernel goes onto floppy media "
               "only, and floppy media take only floppy-rooted kernels" % (label, fam.get("media_class"), media_class))
        return
    carries = all(s in data for s in Z3660SCSI_SYMS)
    if ("z3660scsi" in fam.get("drivers", [])) != carries:
        g.fail("media", "%s: the contract says drivers %s but the bytes %s z3660scsi"
               % (label, fam.get("drivers"), "carry" if carries else "lack"))
        return
    if carries and media_class not in ("z3660", "floppy"):
        g.fail("media", "%s carries z3660scsi: only onto Z3660 media, not %s (ZS-02 not landed)"
               % (label, media_class))
        return
    if release and not fam.get("shipped"):
        g.fail("media", "%s: family %s is never shipped -- refused from release media"
               % (label, famname))
        return
    if media_class == "z3660" and fam.get("wd7") != "required" and not fam.get("wd7_exempt"):
        g.fail("media", "%s: family %s carries no W-D7 (wd7 %r) -- rig-only, refused from z3660 (metal) media"
               % (label, famname, fam.get("wd7")))
        return
    g.ok("media", "%s onto %s media%s" % (label, media_class, " (release)" if release else ""))


# -------------------------------------------------------------------- spl --
# under -traditional the stock sys/types.h does `#define volatile` (empty), so the
# spl()/splx() inline asms lose `volatile` and gcc deletes every one whose output is unused.
# G1 catches the cause in the preprocessor; G2 catches the effect in the object, per function.

CROSS_GCC = "m68k-cbm-sysv4-gcc"
CFLAGS_ENV = os.path.join(GCA, "env.sh")
SPL_CALL_RE = re.compile(r"\b_?spl(?:[0-7]|x|tty|hi|lo|clock|imp|net|bio|str)\s*\(")
SR_WRITE_RE = re.compile(r",%sr\b")
FUNC_LABEL_RE = re.compile(r"^[0-9a-f]+ <([^>+]+)>:")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def kernel_cflags(env_path=CFLAGS_ENV, cpu=None):
    """AMIX_KERNEL_CFLAGS from the toolchain's env.sh, the way the relink scripts read it
    (with -m68020 swapped for the requested CPU dialect)."""
    with open(env_path) as fh:
        m = re.search(r'AMIX_KERNEL_CFLAGS="([^"]*)"', fh.read())
    if not m:
        raise RuntimeError("no AMIX_KERNEL_CFLAGS in %s" % env_path)
    flags = m.group(1).split()
    if cpu:
        flags = [cpu if f.startswith("-m680") else f for f in flags]
    return flags


def strip_c(text):
    """Comments and string/char literals blanked (lengths kept), so braces and parens inside
    them do not count."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(" " * (j - i)); i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(c + " " * (j - i - 2) + c if j - i >= 2 else c); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


C_TYPE_WORDS = {"int", "char", "short", "long", "unsigned", "signed", "void", "float", "double", "struct", "union",
                "enum", "register", "static", "extern", "volatile", "const", "uint", "ulong", "ushort", "uchar", "bool"}


def split_functions(text):
    """[(name, body)] for every top-level function definition in C text (K&R or ANSI heads).
    A `{` at depth 0 opens a function when an identifier followed by `(` was seen since the
    last top-level statement end; struct/enum/initializer blocks have no such head and are
    skipped.  K&R parameter declarations between `)` and `{` end with `;` and must not reset
    the head, so a top-level `;` resets only when the pending head carries an `=`."""
    t = strip_c(text)
    funcs, depth, i, n = [], 0, 0, len(t)
    head_start, name, body_start = 0, None, None
    while i < n:
        c = t[i]
        if depth == 0:
            if c == "(":
                m = list(IDENT_RE.finditer(t, head_start, i))
                # a type keyword before `(` is a K&R parameter declaration such as `int (*strat)( );`
                # (stock sdpart.c), never a function name
                if m and t[m[-1].end():i].strip() == "" and m[-1].group(0) not in C_TYPE_WORDS:
                    name = m[-1].group(0)
            elif c == ";":
                if name is None or "=" in t[head_start:i]:
                    name, head_start = None, i + 1
            elif c == "{":
                depth = 1; body_start = i + 1
            elif c == "}":
                name, head_start = None, i + 1
        else:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    if name:
                        funcs.append((name, t[body_start:i]))
                    name, head_start = None, i + 1
        i += 1
    return funcs


def spl_sites(body, macros=()):
    """Number of spl call sites in a function body: the kernel names, plus the unit's own
    macro names (raw-source scan; a no-op macro vanishes from the preprocessed text)."""
    n = len(SPL_CALL_RE.findall(body))
    for mname in macros:
        if SPL_CALL_RE.match(mname + "("):
            continue                            # a kernel name (e.g. splx): counted above already
        n += len(re.findall(r"\b%s\s*\(" % re.escape(mname), body))
    return n


def sr_writes_by_function(listing):
    """{function: count of `,%sr` writes} from an `objdump -d` listing."""
    out, cur = {}, None
    for ln in listing.splitlines():
        m = FUNC_LABEL_RE.match(ln)
        if m:
            cur = m.group(1); out.setdefault(cur, 0)
        elif cur and SR_WRITE_RE.search(ln):
            out[cur] += 1
    return out


def g1_erases_volatile(dm_text):
    """True when the macro dump defines `volatile` as nothing."""
    return any(re.match(r"^#define volatile\s*$", ln) for ln in dm_text.splitlines())


def spl_unit(g, obj, source, cflags, includes=(), defines=(), macros=(), allow=None,
             cwd=None, label=None):
    """G1 + G2 for one translation unit.  `cflags` is the list from kernel_cflags()."""
    label = label or os.path.basename(obj)
    # the cross toolchain lives beside the one status-facts uses; prepend it as gate_status does
    os.environ["PATH"] = cross_path()
    if shutil.which(CROSS_GCC) is None:
        g.fail("spl", "%s: %s not on PATH -- G1/G2 cannot run (a gate that cannot run "
               "does not pass)" % (label, CROSS_GCC))
        return
    if shutil.which(OBJDUMP) is None:
        g.fail("spl", "%s: %s not on PATH -- G2 cannot run" % (label, OBJDUMP))
        return
    inc = ["-I%s" % d for d in includes]
    base = [CROSS_GCC] + cflags + list(defines) + inc
    # G1
    r = subprocess.run(base + ["-dM", "-E", source], capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        g.fail("spl", "%s: G1 preprocess failed: %s" % (label, r.stderr.strip()[:160]))
        return
    vol = [ln for ln in r.stdout.splitlines() if ln.startswith("#define volatile")]
    if g1_erases_volatile(r.stdout):
        g.fail("spl", "%s: G1 -traditional erases volatile (`#define volatile` is EMPTY): the "
               "spl()/splx() asms lose volatile and gcc drops them" % label)
    else:
        g.ok("spl", "%s: G1 volatile kept (%s)" % (label, "; ".join(vol) or "no #define volatile"))
    # G2
    r = subprocess.run(base + ["-E", "-P", source], capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        g.fail("spl", "%s: G2 preprocess failed: %s" % (label, r.stderr.strip()[:160]))
        return
    pre = {n: spl_sites(b) for n, b in split_functions(r.stdout)}
    raw = {}
    if macros:
        with open(os.path.join(cwd or ".", source) if not os.path.isabs(source) else source) as fh:
            raw = {n: spl_sites(b, macros) for n, b in split_functions(fh.read())}
    sites = {}
    for n in set(pre) | set(raw):
        k = pre.get(n, 0) + raw.get(n, 0)
        if k:
            sites[n] = k
    d = subprocess.run([OBJDUMP, "-d", obj], capture_output=True, text=True,
                       env=dict(os.environ, LC_ALL="C"))
    if d.returncode != 0:
        g.fail("spl", "%s: objdump failed" % label)
        return
    writes = sr_writes_by_function(d.stdout)
    total_sites = sum(sites.values())
    total_writes = sum(writes.values())
    bad, missing = [], []
    for n in sorted(sites):
        if n not in writes:
            missing.append(n)
        elif writes[n] == 0:
            bad.append(n)
    detail = " ".join("%s:%d/%d" % (n, sites[n], writes.get(n, -1)) for n in sorted(sites))
    g.note("spl", "%s: G2 counts (function:sites/sr-writes) %s | unit %d site(s) in %d "
           "function(s), %d sr write(s) in the object" % (label, detail or "none",
                                                          total_sites, len(sites), total_writes))
    if missing:
        g.fail("spl", "%s: G2 function(s) with spl sites but no symbol in the object: %s"
               % (label, ", ".join(missing)))
    if bad:
        if allow:
            g.note("spl", "%s: G2 ALLOWLISTED -- %d function(s) call spl with no %%sr write "
                   "(%s); allowance: %s" % (label, len(bad), ", ".join(bad), allow))
        else:
            g.fail("spl", "%s: G2 %d function(s) call spl but write %%sr never: %s (the "
                   "masks were dropped)" % (label, len(bad), ", ".join(bad)))
    elif not missing:
        g.ok("spl", "%s: G2 every spl-calling function writes %%sr (%d function(s))"
             % (label, len(sites)))


def gate_spl(g, fam, objects_dir):
    spl = fam.get("spl")
    if not spl:
        g.note("spl", "family has no `spl` record: G1/G2 not run (add one)")
        return
    if objects_dir is None:
        g.fail("spl", "no --objects-dir: G1/G2 need the objects and their sources")
        return
    env = amix_path(spl.get("cflags_env", CFLAGS_ENV))
    for obj, u in spl["units"].items():
        cwd = os.path.join(objects_dir, u.get("cwd", "."))
        try:
            cflags = kernel_cflags(env, u.get("cpu"))
        except (OSError, RuntimeError) as e:
            g.fail("spl", "%s: %s" % (obj, e))
            return
        spl_unit(g, os.path.join(objects_dir, obj), u["source"], cflags,
                 includes=u.get("includes", ()), defines=u.get("defines", ()),
                 macros=u.get("macros", ()), allow=u.get("allow"), cwd=cwd, label=obj)



# ------------------------------------------------------- probe_vposr (030) --

HW_RANGES = ((0xDFF000, 0xDFFFFF, "custom chip (VPOSR etc.)"), (0xDD0000, 0xDDFFFF, "Gayle/DMAC A4000 space"),
             (0xDA0000, 0xDAFFFF, "Gayle A1200/A600 space"), (0xDE0000, 0xDEFFFF, "Gayle id space"))


def _hw_range(v):
    for lo, hi, name in HW_RANGES:
        if lo <= v <= hi:
            return name
    return None


def gate_probe_vposr(g, objects_dir, fam, label):
    """The family's probe (ide_detect) touches the hardware on a NON-AGA chipset exactly once: one word read of
    VPOSR (0xDFF004) before the chipset branch, and the not-AGA path to `rts` touches no hardware at all.
    Static, on the driver object's disassembly (objdump -d); the Gayle base lives in the board table and is
    reached only after the AGA test. The a4000-ide contract's `probe_vposr` record names object + function."""
    spec = fam.get("probe_vposr")
    if not spec:
        g.note("probe_vposr", "%s: family has no `probe_vposr` record: not run" % label)
        return
    if objects_dir is None:
        g.fail("probe_vposr", "no --objects-dir: the gate needs the driver object")
        return
    obj = os.path.join(objects_dir, spec["object"])
    fn = spec.get("function", "ide_detect")
    vposr = int(spec.get("vposr", "0xDFF004"), 16)
    env = dict(os.environ, PATH=cross_path())
    r = subprocess.run(["m68k-linux-gnu-objdump", "-d", obj], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        g.fail("probe_vposr", "%s: objdump rc %d" % (label, r.returncode))
        return
    # split into functions
    funcs, cur = {}, None
    for ln in r.stdout.splitlines():
        m = re.match(r"^([0-9a-f]+) <([^>]+)>:$", ln)
        if m:
            cur = m.group(2); funcs[cur] = []; continue
        m = re.match(r"^\s*([0-9a-f]+):\s+(?:[0-9a-f]{4} )+\s*(\S+)\s*(.*)$", ln)
        if m and cur:
            funcs[cur].append((int(m.group(1), 16), m.group(2), m.group(3).strip()))
    if fn not in funcs:
        g.fail("probe_vposr", "%s: no function %s in %s" % (label, fn, spec["object"]))
        return
    # every immediate in a hardware range, anywhere in the object
    hits = []
    for name, ins in funcs.items():
        for addr, op, args in ins:
            for imm in re.findall(r"#(-?\d+)", args):
                v = int(imm) & 0xffffffff
                if _hw_range(v):
                    hits.append((name, addr, op, v))
    vposr_hits = [h for h in hits if h[3] == vposr]
    other = [h for h in hits if h[3] != vposr]
    if len(vposr_hits) != 1 or vposr_hits[0][0] != fn:
        g.fail("probe_vposr", "%s: VPOSR 0x%X literal appears %d time(s) (%s), want exactly once in %s"
               % (label, vposr, len(vposr_hits), ", ".join("%s+%x" % (h[0], h[1]) for h in vposr_hits), fn))
        return
    in_fn = [h for h in other if h[0] == fn]
    if in_fn:
        g.fail("probe_vposr", "%s: other hardware-range literals in %s: %s"
               % (label, fn, ", ".join("%s+%x #0x%X (%s)" % (h[0], h[1], h[3], _hw_range(h[3])) for h in in_fn)))
        return
    if other:
        # helpers the auto-detect path never calls (ide_gayle_id reads the Gayle id register only for a forced
        # A1200/A600 board, README); they are named so a reviewer sees every hardware literal the object holds
        g.note("probe_vposr", "%s: hardware literals outside %s (forced-board helpers): %s"
               % (label, fn, ", ".join("%s+%x #0x%X (%s)" % (h[0], h[1], h[3], _hw_range(h[3])) for h in other)))
    ins = funcs[fn]
    idx = [i for i, (a, op, args) in enumerate(ins) if a == vposr_hits[0][1]][0]
    # the literal goes into an address register, the NEXT instruction is one word read through it
    m = re.search(r",%(a\d)$", ins[idx][2])
    nxt = ins[idx + 1] if idx + 1 < len(ins) else (0, "", "")
    if not (ins[idx][1].startswith("move") and m and nxt[1] == "movew" and nxt[2].startswith("%%%s@," % m.group(1))):
        g.fail("probe_vposr", "%s: the VPOSR access is not a single word read (%s %s / %s %s)"
               % (label, ins[idx][1], ins[idx][2], nxt[1], nxt[2]))
        return
    # the first conditional branch after the read: its target is the not-AGA path (the driver tests the
    # Alice id's low nibble >= 2 and branches away when it is not); walk that path to rts
    branch = None
    for a, op, args in ins[idx + 2:]:
        if re.match(r"^b(cc|cs|eq|ne|ge|gt|hi|le|ls|lt|mi|pl|vc|vs)w?$", op):
            branch = (a, op, args); break
        if op.startswith("jsr") or "@" in args:
            g.fail("probe_vposr", "%s: memory access or call between the VPOSR read and the chipset branch: %s %s" % (label, op, args))
            return
    if not branch:
        g.fail("probe_vposr", "%s: no conditional branch after the VPOSR read" % label)
        return
    target = int(branch[2].split()[0], 16)
    seen, cursor, bad = set(), target, []
    while cursor not in seen:
        seen.add(cursor)
        row = [x for x in ins if x[0] == cursor]
        if not row:
            bad.append("path leaves %s at %x" % (fn, cursor)); break
        a, op, args = row[0]
        if op == "rts":
            break
        if op.startswith("jsr") or op.startswith("bsr"):
            if "<" in args and not re.search(r"<(ide_read|ide_write|ide_gayle|ide_detect|ide_readback)", args):
                pass                            # a relocated call to a kernel routine (printf), not hardware
            else:
                bad.append("%x: %s %s" % (a, op, args))
        elif re.search(r"%a\d@", args) and not re.search(r"%sp@|%fp@", args):
            bad.append("%x: %s %s (memory through an address register)" % (a, op, args))
        if op in ("braw", "bra", "bral", "jmp"):
            cursor = int(args.split()[0], 16)
        else:
            nxt = [x for x in ins if x[0] > a]
            if not nxt:
                break
            cursor = nxt[0][0]
    if bad:
        g.fail("probe_vposr", "%s: the not-AGA path touches hardware: %s" % (label, "; ".join(bad)))
        return
    g.ok("probe_vposr", "%s: %s reads VPOSR 0x%X once (word) at +%x, branch %s at +%x, the not-AGA path to rts touches no hardware, no other hardware literal in %s"
         % (label, fn, vposr, vposr_hits[0][1], branch[1], branch[0], fn))


def gate_rootdev(g, kernel, fam, label):
    """The baked-in root device of a 030-line kernel (config object, not a stamp): tools/rootdev-assert.py."""
    cfg = fam.get("rootdev_config")
    if not cfg:
        g.note("rootdev", "%s: family has no `rootdev_config`: not run" % label)
        return
    r = subprocess.run([sys.executable, os.path.join(HERE, "rootdev-assert.py"), kernel, "--config", cfg],
                       capture_output=True, text=True)
    if r.returncode == 0:
        g.ok("rootdev", "%s: %s" % (label, (r.stdout.strip().splitlines() or ["rootdev-assert OK"])[-1][:120]))
    else:
        g.fail("rootdev", "%s: rootdev-assert --config %s rc %d: %s" % (label, cfg, r.returncode, (r.stdout + r.stderr).strip()[-200:]))


# ------------------------------------------------------------------ check --

def cmd_check(a, fams):
    with open(a.manifest) as fh:
        man = json.load(fh)
    fam = fams["families"].get(man.get("family"))
    g = Gate()
    if fam is None:
        print("REFUSED family %r is not in %s" % (man.get("family"), FAMILIES))
        return 1
    mdir = os.path.dirname(os.path.abspath(a.manifest))
    # a family may name the gates that apply to it (`gates`): the 030 line (K030-IDE) has no stamps, no
    # boot2, no 060 arms, so it runs policy/metal/control/wd7/relsim/rootdev/spl/probe_vposr only
    allow = fam.get("gates")
    def on(name):
        return allow is None or name in allow
    gate_policy(g, man, fam)
    gate_metal(g, fam, man["family"])
    base = man.get("base", {}).get("file")
    if base and sha256_file(base) != man["base"]["sha256"]:
        g.fail("root", "the family base %s no longer has the manifest's sha256" % base)
    if man.get("cputype") != fam["cputype"]:
        g.fail("root", "manifest cputype %r != contract %d" % (man.get("cputype"), fam["cputype"]))
    if on("swap"):
        gate_swap(g, man, fam)
    gate_control(g, fams)
    first = True
    for row in man["chains"]:
        chain = os.path.join(mdir, row["file"])
        if sha256_file(chain) != row["sha256"]:
            g.fail("root", "%s: bytes differ from the manifest row" % row["file"])
            continue
        if row.get("floppy"):
            if fam.get("media_class") != "floppy":
                g.fail("root", "%s: a floppy chain in a family whose media_class is %r, not 'floppy'"
                       % (row["file"], fam.get("media_class")))
        elif fam.get("media_class") == "floppy":
            g.fail("root", "%s: a card/unit chain in a floppy family" % row["file"])
        elif row["card"] not in fam["cards"]:
            g.fail("root", "%s: card %d not in the family's cards %s"
                   % (row["file"], row["card"], fam["cards"]))
        with open(chain, "rb") as fh:
            data = fh.read()
        etrel = os.path.join(mdir, row["etrel"]) if row.get("etrel") else chain   # the 030 chain is brel; relsim/rootdev judge the ET_REL beside it
        if row.get("etrel") and sha256_file(etrel) != row.get("etrel_sha256"):
            g.fail("root", "%s: the ET_REL beside the chain no longer has the manifest's sha256" % row["file"])
        if fam.get("cputype") in (40, 60):
            gate_sddevsize(g, chain, fam, row["file"])
        if on("wd7"):
            gate_wd7(g, data, fam, row["file"])
        else:
            g.note("wd7", "%s: not in the family's gates (the 030 line has no W-D7 probe; the stock a3091 driver's register literals are expected)" % row["file"])
        if on("rth1"):
            gate_rth1(g, etrel, fam, row["file"])
        if on("ttcompat"):
            gate_ttcompat(g, etrel, fam, row["file"])
        for pc in PORT_CHECKS:
            if on(pc) or pc in EVERY_CHAIN:
                gate_port_check(g, etrel, fam, row["file"], pc)
        if on("setuid"):
            gate_setuid(g, chain, row["file"])
        if on("cdevsw"):
            gate_cdevsw(g, chain, fam, row["file"])
        if on("relsim"):
            gate_relsim(g, etrel, fam.get("relsim_loader"), row["file"])
        if on("status"):
            gate_status(g, chain, row["file"])
        if on("root"):
            gate_root(g, chain, row, fam, base, row["file"])
        if on("family"):
            gate_family(g, chain, row, fam, row["file"])
        if on("rootdev"):
            gate_rootdev(g, etrel, fam, row["file"])
        if first:
            if on("scan060"):
                gate_scan060(g, chain, fam, fams, a.objects_dir)
            if on("spl"):
                gate_spl(g, fam, a.objects_dir)
            if on("probe_vposr"):
                gate_probe_vposr(g, a.objects_dir, fam, row["file"])
            first = False
        elif on("scan060"):
            sub = Gate()
            gate_scan060_kernel(sub, chain, fam, fams, tables_pin(sub, fam))
            g.lines += [ln.replace("whole kernel", row["file"] + " whole kernel") for ln in sub.lines]
            g.bad += sub.bad
    g.dump()
    print("K0-GATES %s family %s: %d chain(s), %s"
          % (os.path.basename(a.manifest), man["family"], len(man["chains"]),
             "ALL GREEN" if not g.bad else "%d REFUSAL(S)" % g.bad))
    return 0 if not g.bad else 1


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(prog="k0-gates.py", description=__doc__.split("\n")[0])
    ap.add_argument("--families", default=FAMILIES)
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("check")
    p.add_argument("--manifest", required=True)
    p.add_argument("--objects-dir")
    p = sub.add_parser("media")
    p.add_argument("--kernel", required=True)
    p.add_argument("--media-class", required=True, choices=("z3660", "generic"))
    p.add_argument("--manifest", action="append", required=True)
    p.add_argument("--release", action="store_true")
    p = sub.add_parser("relsim")
    p.add_argument("--loader")
    p.add_argument("kernel")
    p = sub.add_parser("scan060")
    p.add_argument("kernel")
    p.add_argument("--family", required=True)
    p.add_argument("--objects-dir")
    p = sub.add_parser("spl")
    p.add_argument("--object", required=True)
    p.add_argument("--source", required=True)
    p.add_argument("--cflags-env", default=CFLAGS_ENV)
    p.add_argument("--cpu", default=None, help="e.g. -m68040 (replaces -m68020 in the flags)")
    p.add_argument("--include", action="append", default=[])
    p.add_argument("--define", action="append", default=[])
    p.add_argument("--macro", action="append", default=[], help="the unit's own spl macro names")
    p.add_argument("--allow", default=None, help="allowlist note (reported, not failed)")
    p.add_argument("--cwd", default=None)
    sub.add_parser("control")
    a = ap.parse_args(argv)
    if not a.cmd:
        ap.print_usage(sys.stderr)
        return 2
    fams = load_families(a.families)
    g = Gate()
    if a.cmd == "check":
        return cmd_check(a, fams)
    if a.cmd == "media":
        gate_media(g, a.kernel, a.media_class, a.manifest, fams, a.release)
    elif a.cmd == "relsim":
        gate_relsim(g, a.kernel, a.loader, os.path.basename(a.kernel))
    elif a.cmd == "scan060":
        gate_scan060(g, a.kernel, fams["families"][a.family], fams, a.objects_dir)
    elif a.cmd == "control":
        gate_control(g, fams)
    elif a.cmd == "spl":
        spl_unit(g, a.object, a.source, kernel_cflags(a.cflags_env, a.cpu), includes=a.include,
                 defines=a.define, macros=a.macro, allow=a.allow, cwd=a.cwd)
    g.dump()
    return 0 if not g.bad else 1


# --------------------------------------------------------------- selftest --
# Each gate: one failing fixture and one passing fixture, both exercised.  Hermetic where the
# gate's judgement is pure (wd7, the scan060 set logic and verdict parsing, swap, media, the
# relsim --loader refusal, control); the gates that shell out to a real instrument (relsim's
# verdict, status-facts, check-chain-stamp, the port's check_root_family) are exercised on synthetic inputs they must refuse,
# and on the real family chains by `check`.

def selftest():
    fails = []
    tmpd = tempfile.mkdtemp(prefix="k0gates-")

    def expect(label, want_bad, fn):
        g = Gate()
        fn(g)
        ok = (g.bad > 0) == want_bad
        print("  %-70s %s" % (label, "ok" if ok else "FAIL"))
        if not ok:
            fails.append(label)
            for ln in g.lines:
                print("      " + ln)
        return g

    ctl = ["movepl %a4@(460),%d0 060: movepl not implemented",
           "cmp2l %pc@(<BOUNDS1>),%d0 060: cmp2l not implemented"]
    ctl_file = os.path.join(tmpd, "ctl.txt")
    with open(ctl_file, "w") as fh:
        fh.write("\n".join(sorted(ctl)) + "\n")
    fams = {"control": {"sha256": "", "sum_r": 0, "paths": []},
            "scan060": {"control_set_file": ctl_file, "control_set_sha256": set_sha(sorted(ctl))},
            "families": {
                "Z": {"cputype": 60, "bo_size": 61440, "cards": [1], "wd7": "absent",
                      "drivers": ["z3660scsi"], "bench_only": False, "shipped": True},
                "ZA": {"cputype": 60, "bo_size": 61440, "cards": [0], "wd7": "required",
                       "drivers": [], "bench_only": False, "shipped": True},
                "B": {"cputype": 60, "bo_size": 61440, "cards": [0], "wd7": "absent",
                      "drivers": ["z3660scsi"], "bench_only": True, "shipped": False},
                "N": {"cputype": 60, "bo_size": 61440, "cards": [1], "wd7": "absent",
                      "drivers": ["z3660scsi"], "bench_only": False, "shipped": False}}}
    Z, ZA = fams["families"]["Z"], fams["families"]["ZA"]

    print("k0-gates selftest")
    print("scan060")
    kernel_scan = ("== k.lst  (123 decoded lines)\n"
                   "   9668  movepl   %a4@(460),%d0                    060: movepl not implemented\n"
                   "   e4294  cmp2l    %pc@(e4294 <BOUNDS1>),%d0        060: cmp2l not implemented\n"
                   "   total candidates: 2 -- each needs its surrounding bytes read\n")
    expect("PASS: the control's candidates at moved addresses", False,
           lambda g: judge_whole_kernel(g, normalise(kernel_scan), Z, fams))
    expect("REFUSED: one NEW candidate beyond the control's set", True,
           lambda g: judge_whole_kernel(g, normalise(kernel_scan + "   aa1e  cas2w    %d0,%d4 "
                                                     "   060: cas2w not implemented\n"), Z, fams))
    g = expect("PASS (reported): a VANISHED candidate is a note, not a refusal", False,
               lambda g: judge_whole_kernel(g, normalise(kernel_scan.splitlines()[0] + "\n"
                                                         + kernel_scan.splitlines()[1] + "\n"),
                                            Z, fams))
    if not any("VANISHED" in ln and "UNEXPLAINED" in ln for ln in g.lines):
        print("  %-70s FAIL" % "  ... the vanished candidate is named UNEXPLAINED")
        fails.append("vanished named")
    mv = "   fd656  movepw   %d0,%a2@(1152)                   060: movepw not implemented\n"
    expect("PASS: a NEW MOVEP the switch-table reader accepted is a table entry, not a refusal", False,
           lambda g: judge_whole_kernel(g, normalise(kernel_scan + mv), Z, fams, normalise(mv)))
    expect("REFUSED: the table allowance covers only what the reader accepted (a CAS2 stays new)", True,
           lambda g: judge_whole_kernel(g, normalise(kernel_scan + mv + "   aa1e  cas2w    %d0,%d4 "
                                                     "   060: cas2w not implemented\n"), Z, fams, normalise(mv)))
    expect("REFUSED: a scan060_tables record whose pinned reader sha does not match", True,
           lambda g: tables_pin(g, dict(Z, scan060_tables={"sha256": "0" * 64, "objects": []})))
    expect("PASS: no scan060_tables record = no allowance, nothing refused", False,
           lambda g: tables_pin(g, Z) and None)
    bad_pin = dict(fams, scan060=dict(fams["scan060"], control_set_sha256="0" * 64))
    expect("REFUSED: the pinned control set does not match its sha (no drift)", True,
           lambda g: judge_whole_kernel(g, normalise(kernel_scan), Z, bad_pin))
    ok_v = scan_verdict("== x (812 decoded lines)\n   CLEAN -- no candidate found.  Data ...\n")
    bad_v = scan_verdict("== x (812 decoded lines)\n   total candidates: 3\n")
    old_v = scan_verdict("== x (812 decoded lines)\n   total hits: 0\n")
    empty = "== x (0 decoded lines)\n   CLEAN -- no candidate found.\n"
    nocode_v, hidden_v = scan_verdict(empty, 0), scan_verdict(empty, 3350)
    for label, got, want in (("driver-object verdict CLEAN parses as CLEAN", ok_v, "CLEAN"),
                             ("driver-object 'total candidates: 3' is CANDIDATES (a fail)",
                              bad_v, "CANDIDATES"),
                             ("the OLD 'total hits' line is UNREADABLE, never a pass",
                              old_v, "UNREADABLE"),
                             ("0 decoded lines from a data-only object (0 code bytes) is NO-CODE",
                              nocode_v, "NO-CODE"),
                             ("0 decoded lines from an object WITH code is UNREADABLE",
                              hidden_v, "UNREADABLE")):
        print("  %-70s %s" % (label, "ok" if got == want else "FAIL (%s)" % got))
        if got != want:
            fails.append(label)

    print("wd7")
    stock = b"\x00" * 64 + b"\x00\xdd\x00\x00" + b"\x00" * 64
    probe = stock + b"\x00\xdd\x00\x41" + b"\x22\x7c\x00\xdd\x00\x43"
    expect("PASS: polarity absent, no fingerprint", False, lambda g: gate_wd7(g, stock, Z, "k"))
    expect("REFUSED: polarity absent, fingerprint present", True,
           lambda g: gate_wd7(g, probe, Z, "k"))
    expect("REFUSED: polarity required, each port once, but no wd7_payload declared (counts alone no longer pass)",
           True, lambda g: gate_wd7(g, probe, ZA, "k"))
    expect("REFUSED: polarity required, fingerprint absent", True,
           lambda g: gate_wd7(g, stock, ZA, "k"))
    expect("REFUSED: a family with no polarity", True,
           lambda g: gate_wd7(g, stock, dict(Z, wd7=None), "k"))
    inj = injector()
    synth = inj.synthetic_stock_kernel()
    new_k, _ = inj.inject(synth)
    old_k, _ = inj.inject(synth, probe=inj.PAYLOADS[inj.PROBE_SHA256_KT09])
    ZP = dict(ZA, wd7_payload=inj.PROBE_SHA256)
    ZO = dict(ZA, wd7_payload=inj.PROBE_SHA256_KT09)
    expect("PASS: required + the low-nibble payload pinned, on a kernel injected with it", False,
           lambda g: gate_wd7(g, new_k, ZP, "k"))
    expect("PASS: required + the first payload pinned, on a kernel injected with it", False,
           lambda g: gate_wd7(g, old_k, ZO, "k"))
    expect("REFUSED: the low-nibble payload pinned but the kernel carries the first payload's bytes (counts 1/1 alone no longer pass)", True,
           lambda g: gate_wd7(g, old_k, ZP, "k"))
    expect("REFUSED: the first payload pinned but the kernel carries the low-nibble bytes", True,
           lambda g: gate_wd7(g, new_k, ZO, "k"))
    expect("REFUSED: required without a wd7_payload", True, lambda g: gate_wd7(g, new_k, ZA, "k"))
    expect("REFUSED: a wd7_payload the injector does not know", True,
           lambda g: gate_wd7(g, new_k, dict(ZA, wd7_payload="00" * 32), "k"))
    expect("REFUSED: required + payload on a kernel with the fingerprint but no detour", True,
           lambda g: gate_wd7(g, probe, ZP, "k"))

    print("setuid")
    junk = os.path.join(tmpd, "junk")
    with open(junk, "wb") as fh:
        fh.write(b"not an elf" * 100)

    def fake_checker(name, rc, line):
        p = os.path.join(tmpd, "setuid-" + name + ".py")
        with open(p, "w") as fh:
            fh.write("import sys\nassert sys.argv[2:] == ['--check'], sys.argv\n"
                     "open(sys.argv[1], 'rb').read()\nprint(%r)\nsys.exit(%d)\n" % (line, rc))
        return p
    expect("PASS: checker exits 0 (panic removed)", False,
           lambda g: gate_setuid(g, junk, "k", fake_checker("ok", 0, "      [OK]   setuid: removed")))
    expect("REFUSED: checker exits 1 (the hook is LIVE)", True,
           lambda g: gate_setuid(g, junk, "k", fake_checker("live", 1, "      [--]   setuid: LIVE")))
    expect("REFUSED: checker exits 2 (site not recognised)", True,
           lambda g: gate_setuid(g, junk, "k", fake_checker("unk", 2, "[FAIL] no setuid in .text")))
    expect("REFUSED: checker exits 3 (anything else)", True,
           lambda g: gate_setuid(g, junk, "k", fake_checker("odd", 3, "?")))
    expect("REFUSED: the port's checker is absent", True,
           lambda g: gate_setuid(g, junk, "k", os.path.join(tmpd, "no-such-checker.py")))
    expect("REFUSED: the real checker on a non-kernel", True,
           lambda g: gate_setuid(g, junk, "junk"))
    g = expect("PASS/REFUSED lines name the gate and the row", True,
               lambda g: gate_setuid(g, junk, "rowname", fake_checker("live2", 1, "LIVE")))
    if not any("rowname" in ln and "LIVE" in ln for ln in g.lines):
        fails.append("setuid line names the row and the reason")
    fixed, live = fixture("setuid-fixed"), fixture("setuid-live")
    if os.path.isfile(fixed) and os.path.isfile(live):
        expect("PASS: the setuid-fixed kernel (real checker, real kernel)", False,
               lambda g: gate_setuid(g, fixed, "fixed"))
        expect("REFUSED: the setuid-control kernel (hook live)", True,
               lambda g: gate_setuid(g, live, "control"))
    else:
        print("  %-70s %s" % ("(no setuid-fixed/setuid-live under $K0_FIXTURES -- real-kernel cases skipped)", "skip"))

    print("rth1")
    RTOOL = "amix-040-060-port/src/patch_rth1_hook.py"
    rtool_sha = sha256_file(amix_path(RTOOL)) if os.path.isfile(amix_path(RTOOL)) else "absent"
    FR = {"rth1": "required", "rth1_hook": {"tool": RTOOL, "sha256": rtool_sha}}
    plain = os.path.join(tmpd, "plain.bin")
    with open(plain, "wb") as fh:
        fh.write(b"\0" * 64 + b"/dev/dsk/c6d0s2\0")
    hooked = os.path.join(tmpd, "hooked.bin")
    with open(hooked, "wb") as fh:
        fh.write(b"\0" * 64 + b"rth1_mountroot\0/dev/dsk/c6d0s2\0")
    expect("PASS: a family without rth1, a kernel without the hook (noted)", False,
           lambda g: gate_rth1(g, plain, {}, "k"))
    expect("REFUSED: a family without rth1, but the kernel carries rth1_mountroot", True,
           lambda g: gate_rth1(g, hooked, {}, "k"))
    expect("REFUSED: rth1 declared but not `required`", True,
           lambda g: gate_rth1(g, plain, {"rth1": "yes"}, "k"))
    expect("REFUSED: required without an rth1_hook tool", True,
           lambda g: gate_rth1(g, plain, {"rth1": "required"}, "k"))
    expect("REFUSED: the pinned checker sha does not match the tool", True,
           lambda g: gate_rth1(g, plain, {"rth1": "required", "rth1_hook": {"tool": RTOOL, "sha256": "0" * 64}}, "k"))
    if rtool_sha != "absent":
        expect("REFUSED: the real checker on a non-kernel", True, lambda g: gate_rth1(g, plain, FR, "k"))
        r5 = fixture("r5-chain")
        r6 = fixture("r6-base")
        if os.path.isfile(r5):
            expect("REFUSED: the r5 KD060-Z chain (no RTH1 hook) against a family that requires it", True,
                   lambda g: gate_rth1(g, r5, FR, "r5"))
        if os.path.isfile(r6):
            expect("PASS: the r6 KD060-Z base (hook present, anchor unique)", False,
                   lambda g: gate_rth1(g, r6, FR, "r6"))
    else:
        print("  %-70s %s" % ("(the port's patch_rth1_hook.py is absent -- real-checker cases skipped)", "skip"))

    print("ttcompat")
    TTOOL = "amix-040-060-port/src/patch_ttcompat_init.py"
    if os.path.isfile(amix_path(TTOOL)):
        FT = {"ttcompat_fix": "required", "ttcompat_tool": {"tool": TTOOL, "sha256": sha256_file(amix_path(TTOOL))}}
        expect("REFUSED: ttcompat_fix declared but not `required`", True,
               lambda g: gate_ttcompat(g, plain, {"ttcompat_fix": "yes"}, "k"))
        expect("REFUSED: the pinned ttcompat checker sha does not match", True,
               lambda g: gate_ttcompat(g, plain, {"ttcompat_fix": "required",
                                                  "ttcompat_tool": {"tool": TTOOL, "sha256": "0" * 64}}, "k"))
        expect("REFUSED: required, on a non-kernel", True, lambda g: gate_ttcompat(g, plain, FT, "k"))
        stock = fixture("r6-base")
        fixed = fixture("r6t-base")
        if os.path.isfile(stock) and os.path.isfile(fixed):
            expect("PASS: required, on the r6t KD060-Z base (fixed)", False, lambda g: gate_ttcompat(g, fixed, FT, "r6t"))
            expect("REFUSED: required, on the r6 KD060-Z base (stock)", True, lambda g: gate_ttcompat(g, stock, FT, "r6"))
            expect("PASS: undeclared, on the r6 base (stock, noted)", False, lambda g: gate_ttcompat(g, stock, {}, "r6"))
            expect("REFUSED: undeclared, but the kernel carries the fix", True, lambda g: gate_ttcompat(g, fixed, {}, "r6t"))
    else:
        print("  %-70s %s" % ("(the port's patch_ttcompat_init.py is absent -- ttcompat cases skipped)", "skip"))

    print("pgrsv / isp060 / tcp_hiwat")
    with_both = fixture("r6b-base")                    # r6 second cut: pgrsv and isp060 in
    without = fixture("r6t-base")                      # r6 first cut: neither
    pairs = {"tcp_hiwat": (fixture("tcp-hiwat-chain"), fixture("tcp-hiwat-released"), "hiwat", "r6-2")}
    for pc in PORT_CHECKS:
        fixed, stock, fl, sl = pairs.get(pc, (with_both, without, "r6b", "r6"))
        key, tkey, tpath, _ = PORT_CHECKS[pc]
        if not os.path.isfile(amix_path(tpath)):
            print("  %-70s %s" % ("(the port's %s is absent -- %s cases skipped)" % (os.path.basename(tpath), pc), "skip"))
            continue
        FP = {key: "required", tkey: {"tool": tpath, "sha256": sha256_file(amix_path(tpath))}}
        expect("REFUSED: %s declared but not `required`" % pc, True,
               lambda g: gate_port_check(g, plain, {key: "yes"}, "k", pc))
        expect("REFUSED: the pinned %s checker sha does not match" % pc, True,
               lambda g: gate_port_check(g, plain, {key: "required", tkey: {"tool": tpath, "sha256": "0" * 64}}, "k", pc))
        expect("REFUSED: %s required, on a non-kernel" % pc, True, lambda g: gate_port_check(g, plain, FP, "k", pc))
        if os.path.isfile(fixed) and os.path.isfile(stock):
            expect("PASS: %s required, on the %s KD060-Z kernel" % (pc, fl), False,
                   lambda g: gate_port_check(g, fixed, FP, fl, pc))
            expect("REFUSED: %s required, on the %s KD060-Z kernel" % (pc, sl), True,
                   lambda g: gate_port_check(g, stock, FP, sl, pc))
            expect("PASS: %s undeclared, on the %s kernel (absent, noted)" % (pc, sl), False,
                   lambda g: gate_port_check(g, stock, {}, sl, pc))
            expect("REFUSED: %s undeclared, but the kernel carries it" % pc, True,
                   lambda g: gate_port_check(g, fixed, {}, fl, pc))
        else:
            print("  %-70s %s" % ("(the %s fixture kernels are absent -- real-kernel cases skipped)" % pc, "skip"))

    print("scan060 known data (the 68060 ISP's offset-table word)")
    pkg = fixture("isp060_pkg.o")
    if os.path.isfile(pkg) and os.path.isfile(with_both) and os.path.isfile(SCAN060):
        real = json.load(open(fixture("kernel-families-r6.json")))
        HIT = {"offset": "0x5e4", "line": "movepw %a2@(296),%d0 060: movepw not implemented"}
        KD = {"object": "isp060_pkg.o", "anchor": "isp060_top", "sha256": sha256_file(pkg), "hits": [HIT], "why": "t"}
        expect("PASS: the package's candidates are exactly the named word", False,
               lambda g: known_data_object(g, pkg, "isp060_pkg.o", KD))
        expect("REFUSED: the named word moved by 2 bytes", True,
               lambda g: known_data_object(g, pkg, "isp060_pkg.o", dict(KD, hits=[dict(HIT, offset="0x5e6")])))
        expect("REFUSED: no word named (the package's candidate is unexplained)", True,
               lambda g: known_data_object(g, pkg, "isp060_pkg.o", dict(KD, hits=[])))
        expect("REFUSED: the package bytes are not the pinned ones", True,
               lambda g: known_data_object(g, pkg, "isp060_pkg.o", dict(KD, sha256="0" * 64)))
        _v, ktext = run_scan060(with_both)
        cand = normalise(ktext)
        for label, rec, bad in (("PASS: the whole kernel's one new candidate sits at isp060_top + 0x5e4", [KD], False),
                                ("REFUSED: no known-data record (the hit is NEW)", [], True),
                                ("REFUSED: the record's offset is 2 bytes off", [dict(KD, hits=[dict(HIT, offset="0x5e6")])], True),
                                ("REFUSED: the record's anchor symbol is not in the kernel", [dict(KD, anchor="no_such_sym")], True)):
            fam_kd = {"scan060_known_data": rec}
            expect(label, bad, lambda g: judge_whole_kernel(g, cand, fam_kd, real, (),
                                                            known_data_kernel(with_both, ktext, fam_kd)))
    else:
        print("  %-70s %s" % ("(the r6 second-cut tree or kernel is absent -- known-data cases skipped)", "skip"))

    print("cdevsw")

    def mk_cdevsw_elf(rows, ncnt=None, cnt_rows=None):
        """A minimal big-endian ET_REL: .data = cdevsw[cnt_rows] + cdevcnt, .symtab/.strtab,
        .rela.data (rows = {row: {field: symbol}}), .shstrtab."""
        cnt_rows = cnt_rows if cnt_rows is not None else (max(rows) + 1 if rows else 1)
        ncnt = cnt_rows if ncnt is None else ncnt
        symnames = ["", "cdevsw", "cdevcnt"] + sorted(set(v for r in rows.values() for v in r.values() if v))
        strtab = b""; stroff = {}
        for n in symnames:
            stroff[n] = len(strtab); strtab += n.encode() + b"\0"
        data = bytearray(cnt_rows * CDEVSW_ENTSIZE + 4)
        struct.pack_into(">I", data, cnt_rows * CDEVSW_ENTSIZE, ncnt)
        symtab = b""; symidx = {}
        for i, n in enumerate(symnames):
            symidx[n] = i
            if n == "cdevsw":
                symtab += struct.pack(">IIIBBH", stroff[n], 0, 0, 0x11, 0, 1)
            elif n == "cdevcnt":
                symtab += struct.pack(">IIIBBH", stroff[n], cnt_rows * CDEVSW_ENTSIZE, 4, 0x11, 0, 1)
            else:
                symtab += struct.pack(">IIIBBH", stroff[n], 0, 0, 0x10 if n else 0, 0, 0)
        rela = b""
        for r, fs in rows.items():
            for f, sym in fs.items():
                rela += struct.pack(">IIi", r * CDEVSW_ENTSIZE + CDEVSW_FIELDS.index(f) * 4, (symidx[sym] << 8) | 1, 0)
        shstr = b"\0.data\0.symtab\0.strtab\0.rela.data\0.shstrtab\0"
        nm = {".data": 1, ".symtab": 7, ".strtab": 15, ".rela.data": 23, ".shstrtab": 34}
        secs = [(".data", 1, bytes(data), 0, 0, 0), (".symtab", 2, symtab, 3, 0, 16),
                (".strtab", 3, strtab, 0, 0, 0), (".rela.data", 4, rela, 2, 1, 12), (".shstrtab", 3, shstr, 0, 0, 0)]
        body = b""; hdrs = [b"\0" * 40]; off = 52
        for name, typ, blob, link, info, ent in secs:
            hdrs.append(struct.pack(">IIIIIIIIII", nm[name], typ, 0, 0, off, len(blob), link, info, 4, ent))
            body += blob; off += len(blob)
        ehdr = (b"\x7fELF\x01\x02\x01" + b"\0" * 9 +
                struct.pack(">HHIIIIIHHHHHH", 1, 4, 1, 0, 0, 52 + len(body), 0, 52, 0, 0, 40, len(hdrs), 5))
        p = os.path.join(tmpd, "cdevsw-%d.elf" % len(os.listdir(tmpd)))
        with open(p, "wb") as fh:
            fh.write(ehdr + body + b"".join(hdrs))
        return p
    nodev10 = dict((f, "nodev") for f in CDEVSW_FIELDS[:10])
    good = mk_cdevsw_elf({50: dict(nodev10, d_str="sadinfo", d_flag="nullflag"),
                          52: dict(nodev10, d_open="monswopen", d_close="monswclose", d_ioctl="monswioctl",
                                   d_flag="nullflag")}, cnt_rows=70)
    FAMC = {"cdevsw": {"52": {"d_open": "monswopen", "d_ioctl": "monswioctl", "d_str": None},
                       "50": {"d_str": "sadinfo"}}}
    expect("PASS: row 52 monsw with d_str null, row 50 d_str sadinfo, cdevcnt == rows", False,
           lambda g: gate_cdevsw(g, good, FAMC, "k"))
    bad50 = mk_cdevsw_elf({50: dict(nodev10, d_open="monswopen", d_ioctl="monswioctl", d_str="sadinfo")}, cnt_rows=70)
    expect("REFUSED: monsw wired into row 50, a STREAMS row (d_str not null)", True,
           lambda g: gate_cdevsw(g, bad50, {"cdevsw": {"50": {"d_open": "monswopen", "d_str": None}}}, "k"))
    expect("REFUSED: row 52 not wired (d_open None)", True, lambda g: gate_cdevsw(g, bad50, FAMC, "k"))
    expect("REFUSED: cdevcnt disagrees with the table", True,
           lambda g: gate_cdevsw(g, mk_cdevsw_elf({52: dict(nodev10, d_open="monswopen")}, ncnt=60, cnt_rows=70),
                                 {"cdevsw": {"52": {"d_open": "monswopen"}}}, "k"))
    expect("REFUSED: a contract row beyond cdevcnt", True,
           lambda g: gate_cdevsw(g, good, {"cdevsw": {"75": {"d_open": "monswopen"}}}, "k"))
    expect("REFUSED: a field name that is not a cdevsw field", True,
           lambda g: gate_cdevsw(g, good, {"cdevsw": {"52": {"d_bogus": "x"}}}, "k"))
    expect("REFUSED: not a kernel", True, lambda g: gate_cdevsw(g, ctl_file, FAMC, "k"))
    g = expect("PASS: a family without a cdevsw map is not judged", False,
               lambda g: gate_cdevsw(g, ctl_file, {}, "k"))
    if g.lines:
        fails.append("cdevsw judged a family without a map")
    real = fixture("monsw-row50-chain")
    if os.path.isfile(real):
        expect("REFUSED: a kernel with monsw on row 50 (over d_str sadinfo) against the row-52 map", True,
               lambda g: gate_cdevsw(g, real, FAMC, "kt12d"))
        expect("PASS: that kernel against its own map (row 50 d_open monswopen, d_str sadinfo)", False,
               lambda g: gate_cdevsw(g, real, {"cdevsw": {"50": {"d_open": "monswopen", "d_str": "sadinfo"}}}, "kt12d"))
    else:
        print("  %-70s %s" % ("(no monsw-row50-chain under $K0_FIXTURES -- real-kernel cdevsw cases skipped)", "skip"))

    print("relsim")
    expect("REFUSED: no --loader", True, lambda g: gate_relsim(g, junk, None, "junk"))
    expect("REFUSED: --loader given, but the input is not a kernel relsim can clear", True,
           lambda g: gate_relsim(g, junk, "boot2-040", "junk"))
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "--families", FAMILIES,
                        "relsim", junk], capture_output=True, text=True)
    print("  %-70s %s" % ("CLI: `relsim <k>` without --loader exits 1 with REFUSED",
                          "ok" if r.returncode == 1 and "REFUSED" in r.stdout else "FAIL"))
    if not (r.returncode == 1 and "REFUSED" in r.stdout):
        fails.append("relsim CLI refusal")

    print("status")
    expect("REFUSED: status-facts on a non-kernel (it exits 0 -- the output is judged)", True,
           lambda g: gate_status(g, junk, "junk"))

    print("root / swap")
    fam_ok = ("   [ok]   root-storage family coherent\n"
              "   FAMILY    root=card1(/dev/dsk/ced0s1) queues=a3091queue+z3660queue\n")
    expect("PASS: port FAMILY root=card1(ced0s1) on a card-1 unit-6 row", False,
           lambda g: judge_family(g, fam_ok, 0, {"card": 1, "unit": 6}, "k"))
    expect("REFUSED: port FAMILY names card 1 but the row is stamped card 0 unit 6", True,
           lambda g: judge_family(g, fam_ok, 0, {"card": 0, "unit": 6}, "k"))
    expect("REFUSED: port check_root_family not coherent (rc 1)", True,
           lambda g: judge_family(g, "   [FAIL] bo_name digit\n", 1, {"card": 1, "unit": 6}, "k"))
    expect("REFUSED: port check_root_family on a non-kernel", True,
           lambda g: gate_family(g, junk, {"card": 1, "unit": 6}, Z, "junk"))
    expect("REFUSED: check-chain-stamp on a non-kernel", True,
           lambda g: gate_root(g, junk, {"card": 1, "unit": 6}, Z, None, "junk"))
    expect("PASS: manifest bo_size_constant == the family constant", False,
           lambda g: gate_swap(g, {"bo_size_constant": 61440}, Z))
    expect("REFUSED: bo_size_constant from an inherited NSWAP (20479)", True,
           lambda g: gate_swap(g, {"bo_size_constant": 20479}, Z))

    print("policy")
    expect("PASS: the manifest's family_policy equals the contract", False,
           lambda g: gate_policy(g, {"family_policy": dict(Z)}, Z))
    expect("REFUSED: a manifest emitted under polarity 'required' for an 'absent' family", True,
           lambda g: gate_policy(g, {"family_policy": dict(Z, wd7="required")}, Z))
    expect("REFUSED: a manifest with no family_policy", True, lambda g: gate_policy(g, {}, Z))

    print("control")
    cfile = os.path.join(tmpd, "control")
    with open(cfile, "wb") as fh:
        fh.write(b"frozen bytes")
    cf = dict(fams, control={"sha256": hashlib.sha256(b"frozen bytes").hexdigest(),
                             "sum_r": sum_r(b"frozen bytes"), "paths": [cfile]})
    expect("PASS: the control reads its frozen sha256 and sum -r", False,
           lambda g: gate_control(g, cf))
    with open(cfile, "wb") as fh:
        fh.write(b"frozen byteS")
    expect("REFUSED: one byte of the control moved", True, lambda g: gate_control(g, cf))

    print("spl")
    print("  %-70s %s" % ("G1: an EMPTY `#define volatile` is the erasure",
                          "ok" if g1_erases_volatile("#define inline __inline__\n#define volatile \n#define const \n") else "FAIL"))
    print("  %-70s %s" % ("G1: `#define volatile __volatile__` is not",
                          "ok" if not g1_erases_volatile("#define volatile __volatile__\n") else "FAIL"))
    if g1_erases_volatile("#define volatile __volatile__\n") or not g1_erases_volatile("#define volatile \n"):
        fails.append("g1 parse")
    kr = ("struct sdcom { int a; };\nint tab[] = { 1, 2 };\nextern int f();\n"
          "static void\nz3660_complete( cp)\nstruct sdcom *cp;\n{ int s; s = _spl4(); if (cp) { splx(s); return; } splx(s); }\n"
          "int plain(void) { return 0; }\nvoid eth_rx() { s = splz3660eth(); splx(s); }\n")
    fx = split_functions(kr)
    names = [n for n, _ in fx]
    ok_split = names == ["z3660_complete", "plain", "eth_rx"]
    print("  %-70s %s" % ("split_functions: K&R head, struct and initializer blocks skipped",
                          "ok" if ok_split else "FAIL %r" % names))
    if not ok_split:
        fails.append("split_functions")
    sites = {n: spl_sites(b) for n, b in fx}
    ok_sites = sites == {"z3660_complete": 3, "plain": 0, "eth_rx": 1}
    print("  %-70s %s" % ("spl_sites: 3 kernel sites in z3660_complete, splx only in eth_rx",
                          "ok" if ok_sites else "FAIL %r" % sites))
    if not ok_sites:
        fails.append("spl_sites")
    msites = {n: spl_sites(b, ["splz3660eth"]) for n, b in fx}
    print("  %-70s %s" % ("spl_sites with a driver macro: eth_rx counts 2",
                          "ok" if msites["eth_rx"] == 2 else "FAIL"))
    if msites["eth_rx"] != 2:
        fails.append("spl macro sites")
    lst = ("00000000 <guard_hdr>:\n   4:\t40c0\tmovew %sr,%d0\n   6:\t46fc 2400\tmovew #9216,%sr\n"
           "0000000a <leave_hdr>:\n   c:\t4e75\trts\n00000012 <leave_gnu>:\n  1a:\t46c0\tmovew %d0,%sr\n")
    w = sr_writes_by_function(lst)
    ok_w = w == {"guard_hdr": 1, "leave_hdr": 0, "leave_gnu": 1}
    print("  %-70s %s" % ("sr_writes_by_function: reads of %sr are not writes",
                          "ok" if ok_w else "FAIL %r" % w))
    if not ok_w:
        fails.append("sr writes")
    fixd = os.path.join(REPO, "contracts", "spl-gate-fixtures")
    if shutil.which(OBJDUMP):
        ksrc = open(os.path.join(fixd, "kern.c")).read()
        ksites = {n: spl_sites(b) for n, b in split_functions(ksrc)}
        for fname, want_bad in (("kern-trad.o", True), ("kern-dv.o", False)):
            d = subprocess.run([OBJDUMP, "-d", os.path.join(fixd, fname)], capture_output=True,
                               text=True, env=dict(os.environ, LC_ALL="C")).stdout
            w = sr_writes_by_function(d)
            bad = [n for n, k in ksites.items() if k and w.get(n, 0) == 0]
            got_bad = bool(bad)
            print("  %-70s %s" % ("G2 on the repro %s: %s" % (fname, "REFUSED (masks dropped)" if want_bad
                                                                  else "PASS (masks present)"),
                                  "ok" if got_bad == want_bad else "FAIL %r %r" % (ksites, w)))
            if got_bad != want_bad:
                fails.append("G2 fixture " + fname)
    else:
        print("  (%s not on PATH: the repro-object G2 cases skipped)" % OBJDUMP)
    expect("REFUSED: a family without an spl record still says so (note only, no fail)", False,
           lambda g: gate_spl(g, {}, tmpd))
    expect("REFUSED: an spl record without --objects-dir", True,
           lambda g: gate_spl(g, {"spl": {"units": {}}}, None))

    knr = "int\nf( dev, strat)\nint (*strat)( );\n{\n\tint x = spl5( );\n\tsplx( x);\n}\n"
    expect("PASS: a K&R `int (*strat)( );` parameter does not rename the function", False,
           lambda g: (g.ok("spl", "split") if [n for n, _ in split_functions(knr)] == ["f"]
                      else g.fail("spl", "split named %r" % [n for n, _ in split_functions(knr)])))

    print("media")
    kz = os.path.join(tmpd, "kz")
    with open(kz, "wb") as fh:
        fh.write(b"\0".join(Z3660SCSI_SYMS) + b"payload")
    kg = os.path.join(tmpd, "kg")
    with open(kg, "wb") as fh:
        fh.write(b"no scsi driver here")

    def man(name, fam, k):
        p = os.path.join(tmpd, "M-" + name)
        with open(p, "w") as fh:
            json.dump({"family": fam, "chains": [{"file": os.path.basename(k), "card": 1,
                                                  "unit": 6, "sha256": sha256_file(k)}]}, fh)
        return p
    mz, mb, mn = man("z", "Z", kz), man("b", "B", kz), man("n", "N", kz)
    mza = man("za", "ZA", kg)
    # onto z3660 (metal) media a family must carry W-D7 or be exempt; these fixtures are
    # wd7-absent, so the media PASS cases model the exempt (frozen-control) shape.
    famsx = dict(fams, families=dict(fams["families"],
                                     Z=dict(Z, wd7_exempt="fixture: the frozen control's shape"),
                                     N=dict(fams["families"]["N"], wd7_exempt="fixture: the frozen control's shape")))
    expect("PASS: a z3660scsi family chain onto Z3660 media (family W-D7-exempt)", False,
           lambda g: gate_media(g, kz, "z3660", [mz], famsx))
    expect("REFUSED: the same chain onto generic media (z3660scsi only on Z3660 media)", True,
           lambda g: gate_media(g, kz, "generic", [mz], fams))
    expect("PASS: a family without z3660scsi onto generic media", False,
           lambda g: gate_media(g, kg, "generic", [mza], fams))
    expect("REFUSED: a BENCH-ONLY family chain, even onto Z3660 media", True,
           lambda g: gate_media(g, kz, "z3660", [mb], fams))
    expect("REFUSED: a kernel that is no manifest's chain row", True,
           lambda g: gate_media(g, kg, "z3660", [mz], fams))
    expect("PASS: a never-shipped family onto non-release Z3660 media (family W-D7-exempt)", False,
           lambda g: gate_media(g, kz, "z3660", [mn], famsx))
    expect("REFUSED: a never-shipped family onto --release media", True,
           lambda g: gate_media(g, kz, "z3660", [mn], famsx, release=True))
    expect("REFUSED: bytes lack z3660scsi but the contract says the family carries it", True,
           lambda g: gate_media(g, kg, "z3660", [man("zg", "Z", kg)], fams))

    # floppy-rooted families (contract rootdev.floppy) only onto floppy media, and floppy media take nothing else
    famsf = dict(famsx, families=dict(famsx["families"], F=dict(famsx["families"]["Z"], media_class="floppy",
                                                                     bench_only=False, wd7="required")))
    mf = man("f", "F", kz)
    expect("REFUSED: a floppy family's chain onto Z3660 (disk) media", True,
           lambda g: gate_media(g, kz, "z3660", [mf], famsf))
    expect("REFUSED: a disk family's chain onto floppy media", True,
           lambda g: gate_media(g, kz, "floppy", [mz], famsx))
    expect("PASS: a floppy family's chain (z3660scsi carrier) onto floppy media", False,
           lambda g: gate_media(g, kz, "floppy", [mf], famsf))

    print("metal")
    ZM = dict(Z, bench_only=False, media_class="z3660")  # media z3660, not bench-only: metal-bound
    expect("REFUSED: metal-bound family (z3660 media, not bench-only) with wd7 absent", True,
           lambda g: gate_metal(g, ZM, "k"))
    expect("PASS: metal-bound family with wd7 required", False,
           lambda g: gate_metal(g, dict(ZM, wd7="required", wd7_payload="6a5e077e"), "k"))
    expect("PASS: metal-bound family, wd7 absent but exempt with a reason (the frozen control)", False,
           lambda g: gate_metal(g, dict(ZM, wd7_exempt="frozen control, metal-proven"), "k"))
    expect("REFUSED: bench-only family the contract marks metal_bound, wd7 absent", True,
           lambda g: gate_metal(g, dict(Z, bench_only=True, metal_bound=True), "k"))
    expect("PASS: bench-only family not marked metal_bound, wd7 absent (rig-only)", False,
           lambda g: gate_metal(g, dict(Z, bench_only=True), "k"))
    expect("PASS: generic-media family, wd7 absent (rig-only)", False,
           lambda g: gate_metal(g, dict(Z, media_class="generic", bench_only=False), "k"))
    famsm = dict(fams, families=dict(fams["families"], ZM=ZM, ZX=dict(ZM, wd7_exempt="frozen control")))
    expect("REFUSED (media): a wd7-absent family's chain onto z3660 (metal) media", True,
           lambda g: gate_media(g, kz, "z3660", [man("zm", "ZM", kz)], famsm))
    expect("PASS (media): the same chain when the family is wd7-exempt", False,
           lambda g: gate_media(g, kz, "z3660", [man("zx", "ZX", kz)], famsm))

    print()
    if fails:
        print("k0-gates: SELFTEST FAIL -- %s" % ", ".join(fails))
        return 1
    print("k0-gates: SELFTEST PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
