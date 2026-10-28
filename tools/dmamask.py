#!/usr/bin/env python3
"""dmamask.py -- each disk controller's RDB DosEnvec Mask, from the one table (tools/lib/dmamask.py).

  tools/dmamask.py mask --hba NAME                       the Mask, 0x%08X (an unknown name: the
  tools/dmamask.py mask --profile P --role target|src    conservative 0x07FFFFFE and a warning)
  tools/dmamask.py hba --profile P --role target|src     the controller a profile's disk hangs off
  tools/dmamask.py check IMAGE (--hba NAME | --profile P --role R | --mask M)
                       read back every PART's Mask/BufMemType/checksum against the table; exit 1
                       on any mismatch. Prints the PART fields.
  tools/dmamask.py medium [--out FILE]                   the on-box table (/install/dmamask)
  tools/dmamask.py --self-test

P is a profile name (profiles/P.profile) or a path. Why the Mask matters: the loaders take their
DMA buffers by the boot partition's DosEnvec, as FFS does (amix-dlm spec 10 sections 3.1/3.2).
"""
import argparse
import glob
import os
import re
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, "lib"))
import dmamask as dm  # noqa: E402
import rdb  # noqa: E402


def profile_path(p):
    if os.path.isfile(p):
        return p
    q = os.path.join(REPO, "profiles", p + ".profile")
    if os.path.isfile(q):
        return q
    sys.exit("dmamask: no profile %r" % p)


def resolve(a, what):
    """(mask, hba label) from --mask, --hba or --profile/--role; warns on stderr when unknown."""
    if getattr(a, "mask", None):
        return int(a.mask, 0), "explicit"
    if a.hba is not None:
        hba = a.hba
    elif a.profile:
        if not a.role:
            sys.exit("dmamask: --profile needs --role target|src")
        hba = dm.profile_hba(dm.read_profile(profile_path(a.profile)), a.role)
    else:
        sys.exit("dmamask: name the controller (--hba, or --profile with --role)")
    mask, known = dm.mask_for(hba)
    if not known:
        sys.stderr.write(dm.unknown_warning(hba, what) + "\n")
    return mask, hba or "(none)"


def cmd_mask(a):
    mask, _ = resolve(a, a.what)
    print("0x%08X" % mask)
    return 0


def cmd_hba(a):
    print(dm.profile_hba(dm.read_profile(profile_path(a.profile)), a.role))
    return 0


def cmd_check(a):
    want, hba = resolve(a, "image")
    img = open(a.image, "rb").read()
    problems, fields = dm.check_image(img, want)
    print("dmamask check: %s -- controller %s, Mask 0x%08X, BufMemType 0" % (a.image, hba, want))
    print(dm.format_fields(fields))
    for p in problems:
        print("  FAIL %s" % p)
    print("dmamask check: %s" % ("PASS" if not problems else "FAIL (%d)" % len(problems)))
    return 0 if not problems else 1


def cmd_medium(a):
    text = dm.medium_rows()
    if a.out:
        with open(a.out, "w") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)
    return 0


# --- self-test -----------------------------------------------------------------
def self_test():
    fails = []

    def t(cond, what):
        print("  %s  %s" % ("OK  " if cond else "FAIL", what))
        if not cond:
            fails.append(what)

    print("dmamask self-test (synthetic, no media)")
    # the table: the rule's values, and every controller sdnames knows is named in it
    want = {"a4091": 0x07FFFFFE, "a4092": 0x07FFFFFE, "a3000": 0x07FFFFFE, "a2091": 0x00FFFFFE,
            "a2090": 0x00FFFFFE, "a4000t": 0xFFFFFFFC, "gayle": 0xFFFFFFFC, "z3660scsi": 0xFFFFFFFC}
    t(all(dm.mask_for(k) == (v, True) for k, v in want.items()) and len(dm.TABLE) == len(want),
      "the table holds the rule's eight controllers and values")
    t(dm.mask_for("a4kt710") == (0xFFFFFFFC, True), "a4kt710 is the A4000T onboard 710")
    t(dm.mask_for("") == (0x07FFFFFE, False) and dm.mask_for("ncr9999") == (0x07FFFFFE, False),
      "an unknown or empty controller: 0x07FFFFFE, not known (the caller warns)")
    sys.path.insert(0, HERE)
    import importlib
    sdn = importlib.import_module("sdnames")
    t(set(sdn.CLASS) <= {n for n, *_ in dm.TABLE}, "every SD_BOARDS controller (sdnames.CLASS) has a Mask")
    t(all(m & 1 == 0 for _, m, *_ in dm.TABLE), "every Mask is word-aligned (bit 0 clear)")
    # profile resolution
    ph = dm.profile_hba
    t(ph({"TARGET_HBA": "a4091"}, "target") == "a4091", "target: TARGET_HBA")
    t(ph({"SRC_HBA": "z3660scsi", "TARGET_HBA": "a4091", "SRC_SCSI_ID": "6", "TARGET_SCSI_ID": "9"}, "src")
      == "z3660scsi", "src: SRC_HBA wins")
    t(ph({"TARGET_HBA": "z3660scsi", "SRC_SCSI_ID": "e", "TARGET_SCSI_ID": "8"}, "src") == "z3660scsi",
      "src: on the target's card -> TARGET_HBA")
    t(ph({"TARGET_HBA": "a4091", "SRC_SCSI_ID": "6", "TARGET_SCSI_ID": "9",
          "SD_BOARDS": "z3660scsi a4091"}, "src") == "z3660scsi", "src: another card -> SD_BOARDS")
    t(ph({"TARGET_HBA": "a4091", "SRC_SCSI_ID": "6", "TARGET_SCSI_ID": "9"}, "src") == "",
      "src: another card and no SD_BOARDS -> unknown")
    # every tracked profile resolves a target controller in the table
    bad = []
    for p in sorted(glob.glob(os.path.join(REPO, "profiles", "*.profile"))):
        kv = dm.read_profile(p)
        if kv.get("TARGET_HBA") and not dm.mask_for(kv["TARGET_HBA"])[1]:
            bad.append(os.path.basename(p))
    t(not bad, "every profile's TARGET_HBA is in the table%s" % (" (not: %s)" % bad if bad else ""))
    # check_image on synthetic RDBs
    good = dm.synth_rdb(0x07FFFFFE)
    pr, fl = dm.check_image(bytes(good), 0x07FFFFFE)
    t(not pr and len(fl) == 3, "check: a conforming 3-slice RDB passes")
    pr, _ = dm.check_image(bytes(good), 0xFFFFFFFC)
    t(len(pr) == 3, "check: the wrong Mask fires on every slice")
    pr, _ = dm.check_image(bytes(dm.synth_rdb(0x07FFFFFE, bufmemtype=4)), 0x07FFFFFE)
    t(len(pr) == 3 and "BufMemType" in pr[0], "check: a non-zero BufMemType fires")
    broken = bytearray(good)
    struct.pack_into('>I', broken, 2 * 512 + 128 + 4 * dm.DE_MASK, 0xFFFFFFFC)   # no re-close
    pr, _ = dm.check_image(bytes(broken), 0x07FFFFFE)
    t(len(pr) == 2 and sum("checksum" in x for x in pr) == 1, "check: a PART whose checksum does not close fires")
    pr, _ = dm.check_image(bytes(512 * 64), 0x07FFFFFE)
    t(len(pr) == 1 and "unreadable" in pr[0], "check: no RDB fires")
    patched = dm.set_mask(dm.synth_rdb(0xFFFFFFFC), 0x00FFFFFE)
    t(not dm.check_image(bytes(patched), 0x00FFFFFE)[0], "set_mask re-closes every checksum")
    # the medium table: one row per name, the unknown row last, the bytes are the Mask
    rows = [l.split() for l in dm.medium_rows().splitlines()]
    okrows = all(len(r) == 6 and struct.pack('>I', int(r[5], 16)) == bytes(int(x) for x in r[1:5]) for r in rows)
    t(okrows and rows[-1][0] == "*" and {r[0] for r in rows[:-1]} == {n for n, *_ in dm.TABLE} | set(dm.ALIASES),
      "medium table: every controller, the aliases and '*', bytes == Mask")
    # the one-table rule: no RDB writer carries a literal Mask
    lit = []
    for f in sorted(glob.glob(os.path.join(HERE, "*.sh"))):
        for i, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
            if re.search(r'\bmask=0x[0-9a-fA-F]', line) and not line.lstrip().startswith("#"):
                lit.append("%s:%d" % (os.path.basename(f), i))
    t(not lit, "no tools/*.sh writes a literal mask=0x... (one table)%s" % (" -- %s" % lit if lit else ""))
    # the CLI end to end on a synthetic image
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "x.hdf")
        open(p, "wb").write(bytes(good))
        r = subprocess.run([sys.executable, __file__, "check", p, "--hba", "a4092"], capture_output=True, text=True)
        r2 = subprocess.run([sys.executable, __file__, "check", p, "--hba", "z3660scsi"], capture_output=True,
                            text=True)
        r3 = subprocess.run([sys.executable, __file__, "mask", "--hba", "frob"], capture_output=True, text=True)
        t(r.returncode == 0 and r2.returncode == 1 and r3.stdout.strip() == "0x07FFFFFE" and "WARNING" in r3.stderr,
          "CLI: check passes/fails by the table; an unknown controller warns")
    print("dmamask self-test: %s" % ("PASS" if not fails else "FAIL (%d)" % len(fails)))
    return 0 if not fails else 1


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    for name in ("mask", "check"):
        s = sp.add_parser(name)
        if name == "check":
            s.add_argument("image")
            s.add_argument("--mask")
        s.add_argument("--hba")
        s.add_argument("--profile")
        s.add_argument("--role", choices=("target", "src"))
        s.add_argument("--what", default="disk", help="label for the warning")
    s = sp.add_parser("hba")
    s.add_argument("--profile", required=True)
    s.add_argument("--role", choices=("target", "src"), required=True)
    s = sp.add_parser("medium")
    s.add_argument("--out")
    a = ap.parse_args()
    return {"mask": cmd_mask, "hba": cmd_hba, "check": cmd_check, "medium": cmd_medium}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
