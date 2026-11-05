#!/usr/bin/env python3
"""install-reads-check.py STAGE: every file the 1.1 installer on STAGE reads from its medium must be there.

Reads bin/install.sh, bin/setup.sh and l11/l11.sh from the stage, leaves out what only a 1.0 disk runs (the file's own
INSTALL_LAYOUT branches), and looks for each literal $INST/path. Exit 0 all there, 1 some absent, 2 could not look.
--selftest proves it fails when it should.
"""
import os, re, shutil, sys, tempfile

SOURCES = ("bin/install.sh", "bin/setup.sh", "l11/l11.sh")
REF = re.compile(r'\$\{?INST\}?"?/([A-Za-z0-9_./-]+)(\$|\{)?')
# Reads the installer guards itself, with why each may be absent
GUARDED = {
    "firstboot/root.shadow": "only a bench medium seeds a hash; install.sh tests for it",
    "profiles/raw.profile": "only a raw source slice has it; setup.sh tests for it",
}
X11KIT = "x11kit"   # read only when a profile says X11KIT=rtg


def layout_mask(lines):
    """Lines only a 1.0 disk runs. A nested fi at column 0 ends a branch early: that checks more, never less."""
    skip = [False] * len(lines)
    for k, l in enumerate(lines):
        if l.startswith(('if [ "$INSTALL_LAYOUT" = 1.0 ]', 'if [ "$INSTALL_LAYOUT" != 1.1 ]')):
            for e in range(k + 1, len(lines)):
                if re.match(r"(fi|else)\b", lines[e]):
                    skip[k:e + 1] = [True] * (e + 1 - k)
                    break
        elif l.startswith('if [ "$INSTALL_LAYOUT" = 1.1 ]'):
            for e in range(k + 1, len(lines)):
                if re.match(r"fi\b", lines[e]):
                    break
                if re.match(r"else\b", lines[e]):
                    for f in range(e, len(lines)):
                        if re.match(r"fi\b", lines[f]):
                            skip[e:f + 1] = [True] * (f + 1 - e)
                            break
                    break
    return skip


def reads(stage):
    """{path: (is a prefix, first place it is read)}. Raises OSError if a source is missing."""
    out = {}
    for src in SOURCES:
        lines = open(os.path.join(stage, src), encoding="latin-1").read().split("\n")
        skip = layout_mask(lines) if src == "bin/install.sh" else [False] * len(lines)
        for k, l in enumerate(lines):
            if skip[k] or l.lstrip().startswith("#"):
                continue
            for m in REF.finditer(l):
                prefix = bool(m.group(2))
                p = m.group(1)
                if not prefix:
                    p = p.rstrip("/.")
                if p:
                    out.setdefault(p, (prefix, "%s:%d" % (src, k + 1)))
    return out


def rtg_profile(stage):
    d = os.path.join(stage, "profiles")
    for n in os.listdir(d) if os.path.isdir(d) else ():
        if n.endswith(".profile") and re.search(r'^X11KIT="?rtg"?\s*$', open(os.path.join(d, n), encoding="latin-1").read(), re.M):
            return True
    return False


def present(stage, path, prefix):
    if not prefix:
        return os.path.lexists(os.path.join(stage, path))
    d, base = os.path.split(path)
    full = os.path.join(stage, d)
    return os.path.isdir(full) and any(n.startswith(base) for n in os.listdir(full))


def check(stage):
    """(paths read, [absent]). Raises OSError if it cannot look."""
    r = reads(stage)
    rtg = rtg_profile(stage)
    absent = []
    for p, (prefix, where) in sorted(r.items()):
        if present(stage, p, prefix) or p in GUARDED:
            continue
        if p.split("/")[0] == X11KIT and not rtg:
            continue
        absent.append("%s (read at %s)" % (p, where))
    return len(r), absent


def selftest():
    bad = 0
    def want(name, got, exp):
        nonlocal bad
        print("  %-4s %s" % ("ok" if got == exp else "FAIL", name))
        bad += got != exp
    d = tempfile.mkdtemp()
    try:
        for n in ("bin", "l11", "profiles", "syslog"):
            os.mkdir(os.path.join(d, n))
        def write(p, s):
            with open(os.path.join(d, p), "w") as f:
                f.write(s)
        write("bin/setup.sh", 'x=$INST/profiles/raw.profile\n')
        write("l11/l11.sh", '# $INST/only/a/comment\n')
        write("bin/install.sh", 'if [ "$INSTALL_LAYOUT" = 1.1 ]; then\n\tcp "$INST/syslog/syslogd" t\nelse\ncp "$INST/syslog/old.conf" t\nfi\n'
              'if [ "$INSTALL_LAYOUT" != 1.1 ]; then\ncp "$INST/stand/makeiblk" t\nfi\ncp "$INST/x11kit/Xzz9000" t\n')
        n, a = check(d)
        want("the 1.1 branch's file absent: found", [x.split()[0] for x in a], ["syslog/syslogd"])
        want("1.0 branches, comments and guarded reads aren't asked for", n, 3)
        write("syslog/syslogd", "x")
        want("the file there: nothing absent", check(d)[1], [])
        write("profiles/a.profile", 'X11KIT=rtg\n')
        want("a profile with X11KIT=rtg: its kit is asked for", [x.split()[0] for x in check(d)[1]], ["x11kit/Xzz9000"])
        os.remove(os.path.join(d, "profiles/a.profile"))
        write("bin/setup.sh", 'y=$INST/l11/base/o$SET\n')
        want("a path with a variable end: nothing starts with it", [x.split()[0] for x in check(d)[1]], ["l11/base/o"])
        os.mkdir(os.path.join(d, "l11/base")); write("l11/base/o.standard", "x")
        want("a path with a variable end: one starts with it", check(d)[1], [])
        os.remove(os.path.join(d, "bin/setup.sh"))
        try:
            check(d)
            want("a missing installer script can't be looked at", False, True)
        except OSError:
            want("a missing installer script can't be looked at", True, True)
    finally:
        shutil.rmtree(d)
    print("install-reads-check --selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        n, absent = check(sys.argv[1])
    except OSError as e:
        print("install-reads-check: STOP, could not look: %s" % e, file=sys.stderr)
        return 2
    for a in absent:
        print("install-reads-check: ABSENT %s" % a, file=sys.stderr)
    print("install-reads-check: %d paths read, %d absent" % (n, len(absent)))
    return 1 if absent else 0


if __name__ == "__main__":
    sys.exit(main())
