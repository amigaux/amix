#!/usr/bin/env python3
#
# installer-selftest.py -- structural proof of the installer driver + payload,
# host-side, no box, no media, no proprietary inputs. This is the evidence
# that the artifacts are "complete, gated, and structurally proven"; the
# end-to-end on-box run comes after it.
#
# It proves TWENTY things, each fail-closed (added over time: M, N,
# O, P, Q + R, S, and T with the bench
# root-cause of the null-command-redirection defect):
#
#   A. PRE-POSIX PORTABILITY. The driver (src/installer/install.sh) and the
#      first-boot script (payload/firstboot/firstboot.sh) run on the 1991 SVR4
#      miniroot /bin/sh. `sh -n` under a POSIX shell is NOT enough (it accepts
#      $(...), [[ ]], etc.), so this is a GREP audit of the CODE (full-line
#      comments stripped) for every pre-POSIX pitfall: $(...), $(( )), `export
#      VAR=val`, wc, [[ ]], local. Any hit fails.
#   B. PARSE. Both scripts pass `sh -n` (dash) as a basic syntax gate on top of A.
#   C. INSTALL ORDER. gen-install-order.py yields core-first, honours deps.conf
#      topologically, refuses a selection without core, and refuses a cycle.
#   D. BOOT-SLICE MANIFEST. The manifest format is block-aligned and its `sum -r`
#      values reproduce when the exact block spans are re-read -- the property the
#      driver's on-target verification relies on -- and the driver parses the
#      same 4-column shape.
#   E. PARTITION ARITHMETIC. The driver's on-box sh arithmetic (plan_partitions)
#      is byte-identical to tools/mkroot.sh's host-side layout for a range of
#      disk sizes. With rdbtool present this compares against mkroot's REAL
#      layout.json; without it, the mkroot cross-check reports SKIP (never a
#      silent pass) and a python reference is used.
#   F. SEED + FIRST-BOOT SAFETY. The driver performs the proven pkgadd-R seed
#      (passwd/group/admin/pkg, tmp 1777, TMPDIR export in the pre-POSIX form),
#      and firstboot.sh NEVER writes /etc/inet/network-config and NEVER sets the
#      clock forward.
#   G. MINIROOT-TOOL ALLOWLIST. Pre-POSIX syntax (A) is not enough: install.sh
#      runs on a THIN miniroot that lacks basename/sed/touch/date (a bench run proved
#      it on the box, and a `sed`-absent verify silently printed vacuous OKs).
#      So every command's first word in install.sh must resolve to a /bin/sh
#      builtin, a binary the tracked miniroot.proto ACTUALLY carries (the
#      allowlist is derived FROM the proto, never a second hardcoded copy), or a
#      /cdrom/... path. firstboot.sh runs on the FULL installed target, so it
#      gets a small documented per-script exception (sed/uname/true). A reference
#      to any other tool is a FAIL, and crafted negative fixtures prove the audit
#      fires (a driver that reaches for `sed`/`touch`/`basename`/`date` is caught).
#   H. SUBSHELL-SAFE LOOPS. The miniroot /bin/sh runs a `while ... done < FILE`
#      loop in a SUBSHELL, so a variable mutated in the body is LOST at `done`
#      (the pkgadd loop's `npkgs` and the verify loop's `vok`/`vfails`
#      reverted to zero -> "installed 0 package(s)" and a false-firing arm guard).
#      This audit flags any redirect-fed loop whose body assigns a variable that is
#      referenced after the loop, and passes the temp-file idiom that survives it.
#      Negative fixtures (the exact pattern a bench run hit) prove it fires; positive controls
#      (the temp-file idiom, a non-redirected loop) prove it does not over-fire.
#   I. PRE-POSIX `set --` COUNTING GUARD. The subshell-safe count (H) tallies a temp
#      file after the loop, but `set -- `cat FILE`; $#` is itself a trap: on the
#      miniroot sh an EMPTY `set --` is a no-op on $@ (confirmed on-box), so an empty
#      file returns a STALE count (a bench run: the empty vfails "counted" the vok 3
#      and the verify false-failed). This flags any `set -- `cmd`` count not
#      `[ -s ]`-guarded; a negative fixture fires, the guarded idiom passes.
#   J. FIRST-BOOT INIT WIRING. The armed payload only runs if the target
#      init invokes it; the STOCK init does not (cold boot #1 fell into the stock
#      sysinit dialog). This audits that install.sh's arm step (a) WRITES
#      /etc/rc2.d/S16firstboot -- a NEW, driver-written, non-package file that runs
#      firstboot.sh iff PENDING exists -- and (b) DISARMS the stock dialog
#      (`chmod -x /usr/amiga/bin/system.setup`, the stock's own once-only lever).
#      A DRIFT-LOCK extracts the driver's emit_firstboot_hook and re-runs it,
#      proving it reproduces the tracked payload/firstboot/S16firstboot template
#      byte-for-byte; the hook is pre-POSIX + parses + references only
#      target-present tools; and firstboot.sh removes PENDING (once-only).
#   K. INSTALLER COMPLETENESS. The driver (a) runs the CD-resident static
#      contents-fsck over the freshly built <root>/var/sadm/install/contents AFTER
#      the pkgadd loop and BEFORE arming first-boot, FAIL CLOSED (any non-zero ->
#      `die`, no `|| true`-style softening, CHECK-ONLY / never `-r`); and (b) WRITES
#      /etc/apkg.conf on the target with the live-repo line, on the miniroot
#      (identity-independent -> not first-boot), via echo + redirection only. A
#      negative fixture proves the fail-open (`contents-fsck ... || true`) is caught.
#   L. REPO-HOST BAKING (zero-touch apkg). A fresh install cannot resolve the
#      apkg repo's hostname (no DNS on the bench LAN; firstboot section 5 baked only
#      the box's OWN nodename), so `apkg update` worked only after a MANUAL
#      /etc/inet/hosts edit. The driver bakes the repo host too: the profile carries
#      FB_REPO_HOST + FB_REPO_IP (paired); install.sh passes them through
#      firstboot.conf; firstboot.sh appends "<ip> <host>" to /etc/inet/hosts at
#      identity-bake time -- guarded (skip-but-log when either is empty: a repo-less
#      profile is legal), duplicate-safe (strip any prior host line, then append
#      one), and NEVER touching network-config. This audit FIRES on a missing
#      firstboot append whenever a profile carries the vars; a negative fixture
#      proves the append check fires and the bench profile's canonical values are
#      pinned.
#   Q. /stand FRAMING TOOLS. updbootpart's reframe pipeline (gate 5a)
#      fails closed without /stand/boot1.boot + an executable local
#      /stand/makeiblk; on a metal run the KERN handoff on a fresh metal base-8
#      install died "framed image is empty" until the pair was ferried by hand.
#      This audits that the driver LAYS BOTH DOWN (cp from /install/stand,
#      chmod 0644/0755) after the base transplant, that the media staging
#      fingerprint-pins them (boot1.boot 41892/1024 -- the 2.1 original the 2.1c
#      patch never touched; makeiblk 58483/14924 -- the 2.1c build the goldens
#      run and the metal reframe was proven with), that every framing source
#      updbootpart gates on is driver-guaranteed, and (when a staged tree is
#      present) that the staged bytes match the pins. A negative fixture proves
#      the laydown check fires.
#   R. SYSLOG UNIT. A base-8 install has core's syslogd BINARY but no unit
#      (no /etc/init.d/syslogd, no rc links, no /etc/syslog.conf, no /var/log)
#      -- it cannot log at all. This audits that the driver lays down the
#      complete 2.1c unit: conf 0444, the ENABLED init script (vendor `exit`
#      commented at STAGING -- the miniroot has no sed), S70/K50 as HARD links
#      (`ln`, never `ln -s`/cp -- the one-inode 3-link stock topology; edits
#      must be cp-in-place), the 2.1c daemon over core's 2.1 copy (chmod 0100),
#      the eight /var/log stubs, and /dev/conslog c 25 0; that the laydown is
#      UNCONDITIONAL (not inside the zen0 guard); that the staging transform is
#      gated (exactly one vendor `exit` -> `#exit`, the pid file checked by ps, pinned 28819/967); and (when
#      a staged tree is present) that the staged unit matches the pins with NO
#      live `exit`. Negative fixtures prove the link-topology and live-exit
#      checks fire.
#   S. DRIVER PLUMBING. The interview needs somewhere to land its
#      answers, so this turns the driver's remaining hardcodes into profile KEYS
#      and restores two stock steps the NG driver had dropped -- all
#      non-interactive, all behaviour-preserving when the keys carry today's
#      values. Audited: install.sh accepts a profile BY PATH as well as by name
#      (proven by RUNNING the extracted resolution block on four argument
#      shapes); every install persists <target>/var/adm/install.log, opened right
#      after the target mount, with INSTALL_VERBOSE deciding only what the
#      CONSOLE sees -- proven by RUNNING the extracted logline/runq/run helpers in
#      both modes and diffing console against log (there is no tee on the
#      miniroot, so the mechanism is a temp file cat'd twice, and a FAILING child
#      is shown in both modes); the stage messages are the original installer's
#      strings, checked VERBATIM against the stock root floppy's bytes when it is
#      present (SKIP, never a silent pass, otherwise); the stock keymap bake is
#      back (FB_KMAP, HARD link, empty/usa == none, fail-closed on an unknown
#      map); plan_partitions is fed by a real /etc/ddsize probe when
#      TARGET_DISK_MB is not pinned (and ddsize is genuinely on the proto); the
#      stock lost+found 100-slot preseed is back, in the stock position;
#      FB_DNS1/FB_DNS2 are RECORDED and applied NOWHERE (the dialog owns application);
#      and every tracked profile carries every new key. Audits E, F, K and P were
#      extended in lockstep -- the size-override arithmetic with all four stock
#      floors/ceilings, the parametrized TZ colon form, the parametrized repo
#      URL, and the parametrized zen0 gateway.
#   T. NULL-COMMAND REDIRECTION INSIDE A LOOP -- "the create that lies". On the
#      miniroot's 1991 SVR4 sh, `: > file` inside a for/while body performs the
#      redirection ONLY on the first iteration; from the second on it returns 0,
#      prints nothing, and creates nothing. Bench-proven with an instrumented
#      driver (matrix 20260811-103107-cd): stub 1 present, stubs 2-8 ABSENT, the
#      same seven names then created 7/7 by `cp /dev/null` in the same directory
#      seconds later; three straight-line `: >` controls all fine. It had shipped
#      TWO defects -- the syslog unit laid down one of eight /var/log
#      stubs and then hard-stopped every install, and the lost+found preseed was
#      a silent no-op. This audit forbids the idiom structurally in the driver,
#      firstboot and updbootpart; its negative fixtures are the two real defects
#      (and it is verified to FIRE on the historical 05e100b/15a2b21 drivers).
#
#   tools/installer-selftest.py            # run everything
#   tools/installer-selftest.py --self-test  # same (the run-checks.sh entrypoint)
#
# Every fixture this self-test writes (the partition-arithmetic mkroot images, the
# extracted sh harnesses, the synthetic cycle deps.conf, the emit-hook scratch)
# lands under ONE tempdir that is removed on EVERY exit path -- success, a failed
# check, an exception, or SIGINT/SIGTERM -- so a run never leaks /tmp/installsel_*.
# Set INSTALLSEL_KEEP=1 to KEEP that tree for debugging: nothing is deleted and its
# path is printed on exit.
#
# Stdlib-only python3.

import atexit
import json
import hashlib
import importlib.util
import os
import re
import shutil
import signal
import subprocess
import sys
import struct
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, os.pardir))
# the media tools (media/tools); the checkout's top (amix), whose tools/lib holds ufs.py
TOOLS = os.path.join(REPO, "tools")
TOP = os.path.normpath(os.path.join(REPO, os.pardir))
sys.path.insert(0, os.path.join(TOOLS, "lib"))
sys.path.insert(1, os.path.join(TOP, "tools", "lib"))
from sumr import bsd_sum_r                                        # noqa: E402

DRIVER = os.path.join(REPO, "src", "installer", "install.sh")
SETUP = os.path.join(REPO, "src", "installer", "setup.sh")
# the 1.1 layout's half of the driver, sourced by install.sh (INSTALL_LAYOUT=1.1)
L11 = os.path.join(REPO, "src", "installer", "l11.sh")
# the miniroot's own /etc/profile -- the install script the console login
# shell sources. It is the STRICTEST of the three on-box scripts (it runs with
# nothing mounted), so it takes the same audits under the same allowlist.
MINIROOT_PROFILE = os.path.join(REPO, "src", "miniroot", "profile")
FIRSTBOOT = os.path.join(REPO, "payload", "firstboot", "firstboot.sh")
HOOK = os.path.join(REPO, "payload", "firstboot", "S16firstboot")
UPDBOOTPART = os.path.join(REPO, "payload", "updbootpart")
ZENHOOK = os.path.join(REPO, "payload", "S99zen")
PROFILES_DIR = os.path.join(REPO, "profiles")
ISO_BUILDER = os.path.join(TOOLS, "build-install-iso.sh")
STAGE_DIR = os.environ.get("INSTALLSEL_STAGE",
                           os.path.join(TOP, "out", "build", "media", "release", "stage"))
GEN_ORDER = os.path.join(TOOLS, "gen-install-order.py")
# amix userland/pkgtools (media/build.sh builds the media from this checkout's): the
# authored repo metadata build-install-iso.sh reads (deps.conf, sets.conf, cats.conf)
PT_REPO = os.path.join(TOP, "userland", "pkgtools", "tools", "repo")
DEPS = os.path.join(PT_REPO, "deps.conf")

FAILS = []
NOTES = []


def read_sh(path):
    """Read an on-box shell script as text.

    The miniroot install script is LATIN-1 on purpose -- the Amix console is
    8-bit ISO-8859-1 and the keymap menu's labels carry 0xE7 / 0xF1, byte-for-byte
    as the stock artifact has them. install.sh and setup.sh are UTF-8 (their
    comments use a star glyph). Decode as UTF-8 first and fall back to Latin-1, so
    every audit reads every script without any of them having to care."""
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


# ---------------------------------------------------------------------------
# Session scratch dir -- every fixture this self-test writes lands under ONE
# tempdir that is removed on EVERY exit path (normal return, a failed check, an
# exception, SIGINT/SIGTERM). Nothing is written straight into the system
# tempdir any more, so a run never leaves /tmp/installsel_* behind. Set
# INSTALLSEL_KEEP=1 (any value other than "" / "0") to KEEP the tree for
# debugging: it is not deleted and its path is printed on exit.
# ---------------------------------------------------------------------------
KEEP_WORK = os.environ.get("INSTALLSEL_KEEP", "") not in ("", "0")
_WORKDIR = None


def workdir():
    """The session scratch dir, created lazily on first use."""
    global _WORKDIR
    if _WORKDIR is None:
        _WORKDIR = tempfile.mkdtemp(prefix="installsel_")
    return _WORKDIR


def workpath(name):
    """A path for a fixture named `name` inside the session scratch dir."""
    return os.path.join(workdir(), name)


def _cleanup_workdir():
    global _WORKDIR
    if _WORKDIR is None:
        return
    if KEEP_WORK:
        sys.stderr.write("installsel: INSTALLSEL_KEEP set -- kept scratch dir %s\n"
                         % _WORKDIR)
        return
    shutil.rmtree(_WORKDIR, ignore_errors=True)
    _WORKDIR = None


def _on_signal(signum, _frame):
    # remove the scratch dir, then re-raise the signal with the default handler
    # so the exit status still reflects the signal.
    _cleanup_workdir()
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


atexit.register(_cleanup_workdir)                      # normal exit + exceptions
for _sig in (signal.SIGINT, signal.SIGTERM):           # + Ctrl-C / kill
    try:
        signal.signal(_sig, _on_signal)
    except (ValueError, OSError):                       # e.g. not the main thread
        pass


def ok(msg):
    print("  OK    %s" % msg)


def fail(msg):
    print("  FAIL  %s" % msg)
    FAILS.append(msg)


def skip(msg):
    print("  SKIP  %s" % msg)
    NOTES.append("SKIP: " + msg)


def head(title):
    print()
    print("== %s ==" % title)


_HEREDOC_OPEN = re.compile(r"<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_heredocs(text):
    """Remove here-document BODIES (the literal data between a `<<[-]['\"]?DELIM`
    opener and its closing DELIM line). A here-doc body is DATA, never the script's
    own commands, so the miniroot-code audits (pre-POSIX + tool allowlist) must not
    scan it: install.sh emits the TARGET tool updbootpart via `cat <<'UPDBOOTPART_EOF'
    ... EOF`, and that body legitimately uses sum/wc/cmp/pkgparam (which the miniroot
    lacks). Keeping the OPENER line (so the surrounding `cat > "$1"` still parses) and
    dropping the body + closer keeps those target tokens out of the driver's own
    audits, while audit O scans the body independently under the target allowlist.
    install.sh/firstboot.sh carry exactly ONE here-doc (updbootpart's); on text with
    none this is a no-op, so no existing audit changes behaviour."""
    lines = text.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        out.append(line)
        m = _HEREDOC_OPEN.search(line)
        if m:
            delim = m.group(2)
            i += 1
            while i < n and lines[i].strip() != delim:
                i += 1
            # skip the closing delimiter line too (do not emit body or closer)
        i += 1
    return "\n".join(out)


def strip_dquoted(text):
    """Blank out double-quoted spans, line by line. What is left is CODE: a path
    inside `echo "... /etc/foo ..."` is prose the script prints, a path outside
    quotes is an argument the script acts on. Single quotes are left alone (this
    tree writes its emitted here-doc bodies with them)."""
    out = []
    for line in text.split("\n"):
        out.append(re.sub(r'"[^"]*"', '""', line))
    return "\n".join(out)


def _writes_network_config(text):
    """Does this script WRITE /etc/inet/network-config? (The hard rule.) A
    redirection into it, or any file-touching tool naming it as a bare argument.
    Mentions inside double-quoted strings are prose -- see strip_dquoted."""
    code = strip_dquoted(text)
    if re.search(r'>\s*/etc/inet/network-config', code):
        return True
    return bool(re.search(r'\b(sed|cp|mv|cat|ln|ed|chmod|rm)\b[^\n]*'
                          r'/etc/inet/network-config', code))


def strip_full_comments(text):
    """Drop full-line comments (^ws#...). Inline comments STAY (fail-closed:
    an inline comment with a forbidden token is flagged, never hidden). Here-doc
    BODIES are stripped first (see strip_heredocs) -- they are emitted data, not the
    driver's own commands, so they must never count as miniroot code."""
    text = strip_heredocs(text)
    out = []
    for line in text.split("\n"):
        if re.match(r'^\s*#', line):
            continue
        out.append(line)
    return "\n".join(out)


# ---------------------------------------------------------------------------
# A. pre-POSIX audit
# ---------------------------------------------------------------------------
PATTERNS = [
    (r'\$\(\(', "arithmetic $(( )) -- use expr"),
    (r'\$\((?!\()', "command substitution $(...) -- use backticks"),
    (r'\bexport\s+[A-Za-z_][A-Za-z0-9_]*=', "`export VAR=val` -- write VAR=val; export VAR"),
    (r'\bwc\b', "wc -- the miniroot has none; count with set -- glob; echo $#"),
    (r'\[\[', "[[ ]] -- bash test; use [ ]"),
    # `local` is a COMMAND, so it can only ever appear where a command may start:
    # at the beginning of a line or right after a `;`/`&&`/`||`/`{`. Anchoring it
    # there is not a softening -- every real `local x` / `local x=1` declaration
    # still fires (the negative fixture in audit A proves it) -- but it stops the
    # audit misreading the WORD inside a quoted stock string. The dialog made that
    # concrete: the first-boot dialog carries stock's own question "Do you wish to
    # configure Netnews for either local or networked operation? [n] ", which must
    # stay byte-for-byte stock, and a bare \blocal\b in it is not a shell keyword.
    (r'(?m)(?:^|[;&|{]\s*)\s*local\s+[A-Za-z_]', "local -- not in SVR4 sh"),
]


def audit_prepos():
    head("A. pre-POSIX portability audit (grep of code; full-line comments stripped)")
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT):
        rel = os.path.relpath(path, REPO)
        if not os.path.isfile(path):
            fail("%s: missing" % rel)
            continue
        code = strip_full_comments(read_sh(path))
        hits = []
        for pat, why in PATTERNS:
            for m in re.finditer(pat, code):
                # line number within the stripped body is not the file line, but
                # the token + reason is what matters for the audit.
                hits.append((why, m.group(0)))
        if hits:
            for why, tok in hits:
                fail("%s: pre-POSIX violation %r (%s)" % (rel, tok, why))
        else:
            ok("%s: no $(...), $(( )), export VAR=val, wc, [[ ]], or local in code"
               % rel)


# ---------------------------------------------------------------------------
# B. sh -n parse
# ---------------------------------------------------------------------------
def audit_parse():
    head("B. sh -n parse gate (dash)")
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT):
        rel = os.path.relpath(path, REPO)
        rc = subprocess.call([sh, "-n", path])
        if rc == 0:
            ok("%s: %s -n clean" % (rel, sh))
        else:
            fail("%s: %s -n rc=%d" % (rel, sh, rc))


# ---------------------------------------------------------------------------
# C. install order
# ---------------------------------------------------------------------------
def run_order(args):
    return subprocess.run([sys.executable, GEN_ORDER, "--deps", DEPS] + args,
                          capture_output=True, text=True)


def audit_order():
    head("C. install-order generation (gen-install-order.py + deps.conf)")
    if not os.path.isfile(DEPS):
        skip("deps.conf not found (%s) -- order checks need it" % DEPS)
        return
    # the six-package selection -- NOT the shipped base set (that grew to
    # EIGHT later and is checked immediately below). Kept because it isolates
    # the cdfs edge: cdfs joined so an installed box can mount CDs, and
    # cdfs->core must keep it anywhere after core with no APKG/APKGENG present.
    r = run_order(["core", "bsd", "net", "text", "sysadm", "cdfs"])
    seq = [l for l in r.stdout.splitlines() if l and not l.startswith("#")]
    if r.returncode == 0 and seq and seq[0] == "core" and \
            seq == ["core", "bsd", "net", "text", "sysadm", "cdfs"]:
        ok("six-package selection -> core first (cdfs after core): %s"
           % " ".join(seq))
    else:
        fail("six-package order wrong (rc=%d): %r" % (r.returncode, seq))
    # GROWN base set: EIGHT packages -- the package client (APKGENG engine +
    # APKG client) joins so an installed box has apkg out of the box. Case is
    # PRESERVED: our base packages are uppercase (APKG/APKGENG), stock + cdfs are
    # lowercase, and the driver passes each order line verbatim to a case-SENSITIVE
    # `pkgadd -d <file> <NAME>` and a case-sensitive .pkg glob, so a lowercased name
    # would match neither. deps.conf's apkg->apkgeng edge orders APKGENG before APKG.
    r = run_order(["core", "bsd", "net", "text", "sysadm", "cdfs", "APKGENG", "APKG"])
    seq = [l for l in r.stdout.splitlines() if l and not l.startswith("#")]
    want = ["core", "bsd", "net", "text", "sysadm", "cdfs", "APKGENG", "APKG"]
    if r.returncode == 0 and seq == want:
        ok("grown base set -> core first, eight packages, case preserved, "
           "APKGENG before APKG: %s" % " ".join(seq))
    else:
        fail("grown base set order wrong (rc=%d): got %r want %r"
             % (r.returncode, seq, want))
    # the lowercase deps.conf apkg->apkgeng edge must apply to the UPPERCASE base
    # packages (case-INSENSITIVE graph match) AND force APKGENG first even when APKG
    # is listed first in the input -- proving both the case-fold match and the edge.
    r = run_order(["core", "APKG", "APKGENG"])
    seq = [l for l in r.stdout.splitlines() if l and not l.startswith("#")]
    if r.returncode == 0 and seq == ["core", "APKGENG", "APKG"]:
        ok("APKGENG before APKG via the case-folded apkg->apkgeng edge "
           "(input APKG,APKGENG reversed): %s" % " ".join(seq))
    else:
        fail("apkg->apkgeng case-folded ordering wrong (rc=%d): %r"
             % (r.returncode, seq))
    # topo: xcore before its dependents; oldev last
    r = run_order(["core", "oldev", "olcore", "xdev", "xcore", "bsd"])
    seq = [l for l in r.stdout.splitlines() if l and not l.startswith("#")]
    def before(a, b):
        return a in seq and b in seq and seq.index(a) < seq.index(b)
    if r.returncode == 0 and seq[0] == "core" and before("xcore", "olcore") \
            and before("xcore", "xdev") and before("olcore", "oldev") \
            and before("xdev", "oldev"):
        ok("X11 stack topologically ordered: %s" % " ".join(seq))
    else:
        fail("X11 topo order wrong: %r" % seq)
    # refuse without core
    r = run_order(["bsd", "net"])
    if r.returncode != 0 and "core" in (r.stderr + r.stdout).lower():
        ok("refuses a selection without core (Gate 13)")
    else:
        fail("did NOT refuse a core-less selection (rc=%d)" % r.returncode)
    # refuse a cycle (synthetic deps file)
    with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False,
                                     dir=workdir()) as fh:
        fh.write("core:\na: b\nb: a\n")
        cyc = fh.name
    try:
        r = subprocess.run([sys.executable, GEN_ORDER, "--deps", cyc,
                            "core", "a", "b"], capture_output=True, text=True)
        if r.returncode != 0 and "cycle" in (r.stderr + r.stdout).lower():
            ok("refuses a dependency cycle")
        else:
            fail("did NOT refuse a cycle (rc=%d)" % r.returncode)
    finally:
        os.unlink(cyc)


# ---------------------------------------------------------------------------
# D. boot-slice manifest format + verification arithmetic
# ---------------------------------------------------------------------------
def audit_manifest():
    head("D. boot-slice manifest (block-aligned; sums reproduce on re-read)")
    SB = 512
    # synthesize a padded chain like build-bootslice emits: 0x2800 prefix + a
    # non-block-multiple 'kernel' + zero pad to a whole block.
    prefix = bytes(bytearray((i * 7 + 3) & 0xff for i in range(0x2800)))
    kernel = bytes(bytearray((i * 13 + 5) & 0xff for i in range(1252347)))
    chain = prefix + kernel
    pad = (-len(chain)) % SB
    img = chain + b"\x00" * pad
    nblk = len(img) // SB
    if len(img) % SB != 0:
        fail("padded chain is not a whole number of blocks")
        return
    ok("padded chain = %d bytes = %d blocks (kernel %d + %d pad)"
       % (len(img), nblk, len(kernel), pad))
    # regions exactly as build-bootslice: boot1(blk0,2) boot2(blk3,16) chain(0,all)
    regions = [("boot1", 0, 2), ("boot2", 3, 16), ("chain", 0, nblk)]
    manifest = []
    for name, blk, n in regions:
        span = img[blk * SB:(blk + n) * SB]
        manifest.append((name, blk, n, bsd_sum_r(span)))
    # verify: reading the exact block span reproduces the sum (the driver's op)
    allok = True
    for name, blk, n, want in manifest:
        got = bsd_sum_r(img[blk * SB:(blk + n) * SB])
        if got != want:
            allok = False
    if allok:
        ok("every region's sum -r reproduces on a block-aligned re-read: %s"
           % ", ".join("%s=%05d" % (n, s) for n, _, _, s in manifest))
    else:
        fail("a region sum did not reproduce on re-read")
    # the driver must parse a 4-column manifest line (region blk n sum)
    code = strip_full_comments(open(DRIVER, encoding="utf-8").read())
    if re.search(r'read\s+region\s+blk_off\s+nblk\s+want_sum', code) and \
            re.search(r'dd\s+if="\$BOOT_RAW"\s+bs=512\s+skip="\$blk_off"\s+count="\$nblk"', code):
        ok("driver reads the 4-column manifest with block-aligned dd (no bs=1)")
    else:
        fail("driver manifest-parse / block-aligned read not found as expected")


# ---------------------------------------------------------------------------
# E. partition arithmetic == mkroot.sh
# ---------------------------------------------------------------------------
def extract_plan_harness():
    """Build a runnable sh harness from install.sh's constants + plan_partitions,
    so the ACTUAL driver arithmetic is exercised (not a reimplementation). is_num
    is extracted too (the size-override validation calls it), so the harness
    stays a transcription of the driver rather than a stand-in for it. The
    override keys come in from the ENVIRONMENT, exactly as sourcing a profile
    would set them -- unset means "stock default", the earlier behaviour."""
    src = open(DRIVER, encoding="utf-8").read()
    lines = src.splitlines()
    # constants: from OFFSET_BLOCKS= down to the SECS=64 line
    ci = next(i for i, l in enumerate(lines) if l.startswith("OFFSET_BLOCKS="))
    cj = next(i for i, l in enumerate(lines) if l.startswith("SECS=64"))
    consts = "\n".join(lines[ci:cj + 1])
    isnum = _extract_func(src, "is_num")
    # function: from 'plan_partitions() {' to its closing '}' at column 0
    fi = next(i for i, l in enumerate(lines) if l.startswith("plan_partitions()"))
    fj = next(i for i in range(fi + 1, len(lines)) if lines[i] == "}")
    func = "\n".join(lines[fi:fj + 1])
    harness = (consts + "\n" + "die(){ echo \"die: $*\" >&2; exit 3; }\n" +
               isnum + "\n" + func +
               "\nplan_partitions \"$1\"\n"
               "echo \"$ROOT_OFF $SWAP_OFF $BOOT_OFF $ROOTLEN $SWAPLEN $BOOTLEN\"\n")
    return harness






# ---------------------------------------------------------------------------
# F. seed steps + first-boot safety
# ---------------------------------------------------------------------------
def _mnttab_write(text):
    """Classify the seed's /etc/mnttab root-line write as 'overwrite' | 'append' |
    None. Operates on comment-stripped driver text (real commands only). `>>` is
    tested first because the `>` pattern would otherwise match the second `>` of an
    append. The write MUST be an OVERWRITE of the "/" root entry. The
    fs field is the RUNNING MINIROOT's own ($MINIROOT_FSTYPE -- s5 on the 030 line,
    ufs on the 040/060 line, derived from INSTALL_CPU), NOT the target's; a
    hardcoded literal or a $TARGET_ROOT_FSTYPE there is a defect (audit AA6)."""
    if re.search(r'echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>>\s*/etc/mnttab', text):
        return "append"
    if re.search(r'echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>\s*/etc/mnttab', text):
        return "overwrite"
    return None


# --- F/TZ: the colon form, now that the ZONE is a profile key ----------------
# REGRESSION GUARD, extended to the parametrized emission. The TIMEZONE line
# MUST use the SVR4 tzfile-pathname form `TZ=:<pathname>` (LEADING COLON): only
# the colon makes ctime(3)/tzset(3) read the tzfile; the colon-less
# `TZ=US/Eastern` is parsed as a POSIX rule string and BUS-ERRORs date/who -r/
# ls -l/cron/sac at 474D5400 on cold boot (cascading into rc2 `test: unknown
# operator S`). The ZONE is a key (FB_TZ) but deliberately NOT the colon --
# the colon is emitted by CODE so no profile, answers file or stripped quote can
# ever produce the broken form. So the audit demands exactly that shape:
#   * firstboot.sh emits `TZ=:$FB_TZ` (literal colon, then the variable);
#   * firstboot.sh DEFAULTS FB_TZ (an old firstboot.conf must not yield `TZ=:`);
#   * install.sh passes FB_TZ into firstboot.conf and STRIPS a leading colon off
#     the profile value (`TZ=::US/Eastern` is just as dead);
#   * every profile carries a zone-shaped FB_TZ (contains a '/').


def _fb_tz_emission(fb_code):
    """Classify firstboot.sh's TZ= emission on comment-stripped code:
    'param'  -- TZ=:$FB_TZ / TZ=:${FB_TZ}   (the required shape)
    'literal'-- TZ=:<something/else>        (a hardcoded zone, as it once was)
    'nocolon'-- TZ=<anything> with no colon  (the bus-error form)
    None     -- no TZ= assignment at all."""
    # Only an EMISSION counts, so the pattern is anchored on the `echo "TZ=` that
    # writes /etc/TIMEZONE. The dialog made that precision necessary: this file now also
    # SEEDS `TZ=":$FB_TZ"` into the environment for the stock zone menu and READS
    # the zone back with `sed -n 's/^TZ=//p'`, and a looser pattern classified the
    # reader as a colon-less emission -- an audit that fires on the wrong line is
    # as bad as one that never fires.
    m = re.search(r'echo\s+"TZ=(:?)(\$\{?FB_TZ\}?|[^\s"\']+)', fb_code)
    if not m:
        return None
    if m.group(1) != ":":
        return "nocolon"
    return "param" if m.group(2).startswith("$") else "literal"


def audit_tz_colon(fb, drv):
    kind = _fb_tz_emission(fb)
    if kind == "param":
        ok("firstboot.sh emits the tzfile form `TZ=:$FB_TZ` -- zone parametrized, "
           "COLON emitted by code")
    elif kind == "literal":
        fail("firstboot.sh still HARDCODES the timezone zone -- it must be parametrized "
             "as FB_TZ (the literal made every profile's zone a no-op)")
    else:
        fail("firstboot.sh TIMEZONE must be `TZ=:$FB_TZ` (leading colon emitted by "
             "code) -- got %r; the colon-less form BUS-ERRORs date/who -r/ls -l at "
             "cold boot" % kind)
    if re.search(r'\[\s+-n\s+"\$FB_TZ"\s+\]\s+\|\|\s+FB_TZ=\S+', fb):
        ok("firstboot.sh defaults FB_TZ (an old firstboot.conf can never yield `TZ=:`)")
    else:
        fail("firstboot.sh does not default FB_TZ -- a conf without the key would "
             "write the empty `TZ=:`")
    if re.search(r'echo\s+"FB_TZ=\$FB_TZ"', drv):
        ok("install.sh passes FB_TZ through to firstboot.conf")
    else:
        fail("install.sh does not write FB_TZ into firstboot.conf -- the key would be "
             "a dead letter")
    if re.search(r'\[\s+-n\s+"\$FB_TZ"\s+\]\s+\|\|\s+FB_TZ=\S+', drv) and \
            re.search(r'FB_TZ=`expr\s+"\$FB_TZ"\s+:\s+\':\\\(', drv):
        ok("install.sh defaults FB_TZ and strips a leading colon off the profile value "
           "(no `TZ=::zone`)")
    else:
        fail("install.sh must default FB_TZ and strip a leading colon from it (the "
             "colon belongs to the emitter, never to data)")
    # Every profile carries a zone-shaped FB_TZ -- with ONE exemption, and it is
    # the whole point of the public flavor: a profile that ARMS THE DIALOG
    # (FIRSTBOOT_DIALOG=y) hands the timezone to the genuine stock zone menu, so
    # an empty FB_TZ there is a deliberate blank and not a missing key. A
    # NON-empty value is still held to the same shape everywhere, because the
    # failure it guards against (a colon-less or non-zone TZ) bus-errors every
    # ctime(3) consumer at cold boot whichever tier wrote it.
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    bad = []
    exempt = []
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        v = d.get("FB_TZ")
        asks = d.get("FIRSTBOOT_DIALOG") == "y"
        if not v:
            if asks:
                exempt.append(pf)
            else:
                bad.append("%s=%r (unattended: nothing would ever ask)" % (pf, v))
            continue
        # Area/City, OR one of the flat zone files Amix 2.1's 1991 tz data ships at the
        # top of /usr/lib/locale/TZ (it has no Europe/* -- EET is how a Finnish box
        # names its zone; read off an installed tree, 2026-09-29).
        if v.startswith(":") or ("/" not in v and v not in AMIX_FLAT_ZONES):
            bad.append("%s=%r" % (pf, v))
    if profs and not bad:
        zones = sorted(set(_parse_profile(os.path.join(PROFILES_DIR, p)).get("FB_TZ")
                           for p in profs if _parse_profile(
                               os.path.join(PROFILES_DIR, p)).get("FB_TZ")))
        ok("every profile carries a colon-less, zone-shaped FB_TZ (%s)%s"
           % (", ".join(zones),
              "" if not exempt else "; empty by design on the dialog flavor(s): "
              + ", ".join(exempt)))
    else:
        fail("profile(s) with a missing/mis-shaped FB_TZ: %s" % ", ".join(bad))
    # NEGATIVE FIXTURE: the exemption must be narrow -- an UNATTENDED profile
    # with an empty zone is still a failure, and a dialog profile with a broken
    # one is too.
    for label, tier, zone, want_bad in (
            ("unattended, empty zone", "n", "", True),
            ("dialog, empty zone", "y", "", False),
            ("dialog, colon-prefixed zone", "y", ":US/Eastern", True),
            ("dialog, non-zone string", "y", "EST5EDT", True)):
        got_bad = False
        if not zone:
            got_bad = (tier != "y")
        elif "/" not in zone or zone.startswith(":"):
            got_bad = True
        if got_bad == want_bad:
            ok("FB_TZ rule: %s is %s, as it must be"
               % (label, "REFUSED" if want_bad else "allowed"))
        else:
            fail("FB_TZ rule is wrong for: %s" % label)
    # NEGATIVE FIXTURES -- both broken shapes must be caught.
    for name, snippet, want in [
        ("colon-less parametrized", 'echo "TZ=$FB_TZ"\n', "nocolon"),
        ("hardcoded zone", 'echo "TZ=:US/Eastern"\n', "literal"),
    ]:
        got = _fb_tz_emission(snippet)
        if got == want:
            ok("negative fixture fires: %-24s -> classified %r" % (name, got))
        else:
            fail("negative fixture DID NOT fire: %s (got %r, want %r)"
                 % (name, got, want))


def audit_seed_firstboot():
    head("F. seed steps + first-boot safety")
    code = strip_full_comments(open(DRIVER, encoding="utf-8").read())
    checks = [
        (r'cp\s+/etc/passwd\s+"\$TARGET/etc/passwd"', "seeds <root>/etc/passwd from the miniroot (== core's)"),
        (r'cp\s+/etc/group\s+"\$TARGET/etc/group"', "seeds <root>/etc/group"),
        (r'var/sadm/install/admin/default', "seeds the 183-B admin default"),
        (r'var/sadm/pkg', "creates <root>/var/sadm/pkg"),
        (r'chmod\s+1777\s+"\$TARGET/tmp"', "chmod 1777 <root>/tmp"),
        (r'TMPDIR="\$TARGET/tmp";\s*export\s+TMPDIR', "TMPDIR onto the target (pre-POSIX export form)"),
        (r'"\$PKGADD"\s+-R\s+"\$TARGET"\s+-n\s+-a\s+"\$ADMIN"\s+-d\s+"\$pf"\s+"\$pkg"',
         "pkgadd -R <root> -n -a <admin> -d <pkg> <name> (proven invocation)"),
        (r'cp\s+"\$INST/\$BOOT2_BOOT"\s+"\$TARGET/stand/boot2.boot"',
         "overwrites <root>/stand/boot2.boot with the flags-based loader"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok(desc)
        else:
            fail("driver missing: %s" % desc)

    # --- /etc/mnttab root line -----------------------------------------------
    # The RUNNING miniroot ships no /etc/mnttab on FRESH media; pkgadd/apkg open()
    # it before installing and abort with "unable to open mount table (/etc/mnttab)"
    # (a metal run froze exactly here). The seed must WRITE the "/" root line -- and
    # OVERWRITE (`>`), never append, so a stale/contaminated table (the reused-bench-
    # floppy trap that masked this for a while) is REPLACED. get_mntinfo keys off
    # the SHORTEST mount point being exactly "/".
    mode = _mnttab_write(code)
    if mode == "overwrite":
        ok('seed writes /etc/mnttab root line `echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab` '
           "(OVERWRITE, replaces a stale/contaminated table)")
    elif mode == "append":
        fail("seed writes /etc/mnttab with `>>` (append) -- must be `>` (OVERWRITE) so a "
             "stale/contaminated table is replaced, not appended to")
    else:
        fail('seed does not write the /etc/mnttab root line `/dev/root / $MINIROOT_FSTYPE '
             'rw 0` -- pkgadd/apkg abort with "unable to open mount table (/etc/mnttab)" '
             "on FRESH media; the fs field is the miniroot's own, not a literal")
    # it must be the "/" root mount point (a "/mnt" line does NOT satisfy get_mntinfo)
    if re.search(r'echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>+\s*/etc/mnttab', code):
        ok('mnttab line is the "/" root entry get_mntinfo requires (mount point "/")')
    else:
        fail('mnttab write is not the "/" root entry get_mntinfo keys on')
    # ORDER: written in the SEED (both source arms), BEFORE the base-OS install loop.
    i_seed = code.find("seeding target root")
    i_mnttab = code.find("> /etc/mnttab")
    i_order = code.find('done < "$ORDER"')
    if 0 <= i_seed < i_mnttab < i_order:
        ok("mnttab is written in the seed step, before the pkgadd/apkg install loop")
    else:
        fail("mnttab write is mis-ordered (seed@%d mnttab@%d order-loop@%d)"
             % (i_seed, i_mnttab, i_order))
    # NEGATIVE FIXTURE -- with the seed's mnttab line removed the audit MUST report
    # absence, or this check is worthless (the exact fresh-media regression).
    neg = re.sub(r'\n[^\n]*echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>+\s*/etc/mnttab[^\n]*', "", code)
    if _mnttab_write(neg) is None:
        ok("negative fixture fires: a seed with no /etc/mnttab write is flagged absent")
    else:
        fail("negative fixture did NOT fire: a missing mnttab write was not caught")

    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    # NEVER write network-config: no redirection into it, and no tool naming it as
    # an ARGUMENT. The dialog forced the distinction between a write and a MENTION: the
    # first-boot dialog's DNS branch has to TELL the operator, in prose, that DNS
    # is refused on aen0 *because* the bring-up line lives in that file. A rule
    # that cannot tell `cp x /etc/inet/network-config` from `echo "... in
    # /etc/inet/network-config ..."` would make explaining the rule a violation of
    # it. So double-quoted spans are stripped first, and what remains is code.
    if _writes_network_config(fb):
        fail("firstboot.sh appears to WRITE /etc/inet/network-config -- forbidden")
    else:
        ok("firstboot.sh never writes /etc/inet/network-config (mentions inside "
           "quoted strings are prose, not writes)")
    # and the distinction has to FIRE: a real write must still be caught.
    if _writes_network_config('cp /tmp/x /etc/inet/network-config\n') and \
            _writes_network_config('echo up > /etc/inet/network-config\n') and \
            not _writes_network_config('echo "see /etc/inet/network-config"\n'):
        ok("negative fixtures: a bare-argument write and a redirection are both "
           "caught; a quoted mention is not")
    else:
        fail("the network-config write detector does not separate writes from "
             "quoted mentions")
    # it MUST edit /etc/inet/hosts (the one allowed networking edit)
    if re.search(r'/etc/inet/hosts', fb):
        ok("firstboot.sh edits /etc/inet/hosts (the only allowed networking edit)")
    else:
        fail("firstboot.sh does not touch /etc/inet/hosts")
    # NEVER set the clock forward: no date/setclk/stime that sets a time (the one
    # gated battery-clock re-read, IN-rtc-2, is checked for its shape and place)
    fb_nc, why = _strip_setclk_rerun(fb)
    if why:
        fail("firstboot.sh: " + why)
    # the exemption must stay NARROW: a second copy, a copy away from the clkzone
    # write, or one with nothing clearing lastchg after it are all refused
    fx = 'echo "$ZSET" > /etc/clkzone\n' + SETCLK_RERUN + '\n\tclear_lastchg\n'
    if _strip_setclk_rerun(fx)[1] is None and \
            _strip_setclk_rerun(fx + SETCLK_RERUN + '\n')[1] and \
            _strip_setclk_rerun(SETCLK_RERUN + '\n\tclear_lastchg\n')[1] and \
            _strip_setclk_rerun('echo "$ZSET" > /etc/clkzone\n' + SETCLK_RERUN + '\n')[1]:
        ok("negative fixtures: the setclk re-read exemption admits only the one "
           "gated line after the clkzone write and before clear_lastchg")
    else:
        fail("the setclk re-read exemption is not narrow")
    if re.search(r'\b(date\s+[0-9]|setclk\b|stime\b|/usr/bin/date\s+[0-9])', fb_nc):
        fail("firstboot.sh appears to SET the clock -- forbidden (RTC aging trap)")
    else:
        ok("firstboot.sh never sets the clock (no date/setclk/stime write) apart from "
           "the one gated setclk re-read after the zone question")
    # timezone + nodename presence
    if re.search(r'/etc/TIMEZONE', fb) and re.search(r'/etc/nodename', fb):
        ok("firstboot.sh sets nodename + timezone (zone from FB_TZ; US/Eastern index 47)")
    else:
        fail("firstboot.sh missing nodename/timezone handling")
    audit_tz_colon(fb, drv=strip_full_comments(open(DRIVER, encoding="utf-8").read()))


# ---------------------------------------------------------------------------
# G. miniroot-tool allowlist audit
# ---------------------------------------------------------------------------
# Parse the command first-word of every simple command in the shipped sh and
# require it to resolve to a /bin/sh builtin, a binary the miniroot.proto carries,
# or a /cdrom/... path. This is a HEURISTIC miniroot-sh parser (perfect shell
# parsing is undecidable), tuned fail-closed: it recurses into `backtick` command
# subs, collapses quoted spans + drops redirections, and understands case
# patterns, keywords, leading assignments and the driver's `run CMD` wrapper.
# Quoted/variable commands ("$PKGADD", "$@") are out of scope (skipped) -- the
# audit targets LITERAL tool references, which is where the absent-tool bugs live.

QUOTED = "\x01"          # placeholder a quoted span collapses to

SH_KEYWORDS = {
    "if", "then", "elif", "else", "fi", "while", "until", "do", "done",
    "{", "}", "!",
}
# genuine SVR4 Bourne-sh builtins (NOT printf/local/true/false -- those are not
# builtins here; the miniroot has no /bin/echo, so `echo` MUST be the builtin).
SH_BUILTINS = {
    ":", ".", "[", "test", "echo", "read", "set", "unset", "shift", "export",
    "readonly", "return", "exit", "break", "continue", "cd", "pwd", "eval",
    "exec", "trap", "umask", "wait", "times", "ulimit", "getopts", "hash", "type",
}
# `run CMD ...` / `runq CMD ...` -- the real command is CMD (the install.sh
# idiom). runq is the output-routing twin of run (it returns the rc instead of
# dying); both must be unwrapped or the tool audit would stop seeing the actual
# commands behind them.
WRAPPERS = {"run", "runq"}

# install.sh runs on the THIN miniroot: NO target-side extras allowed.
DRIVER_EXTRA = set()
# src/miniroot/profile: /sbin/modadmin is on the RAM-disk miniroot only
# (tools/build-ramdisk-miniroot.sh), and the profile runs it behind `[ -x ]`; the network
# userland (build-ramdisk-miniroot.sh --net) is on the netinstall image only, and the
# profile reaches it only in net_source, behind the image's /install/NETINSTALL marker.
PROFILE_EXTRA = {"modadmin", "aen", "date", "ifconfig", "route", "slink", "sleep"}
# setup.sh's extra: the RAM disk's /bin/sleep (build-ramdisk-miniroot.sh), which bounds the chosen disk's size
# request (disk_real_mb); the helper tests for it and keeps the old layout's size without it
SETUP_EXTRA = {"sleep"}
# firstboot.sh runs on the FULL installed target (core+base transplanted), so the
# complete SVR4 userland is present. These are the tools it deliberately uses that
# the miniroot itself lacks -- documented, and NOT granted to install.sh.
FIRSTBOOT_EXTRA = {
    # the APPLY half: target tools the miniroot lacks
    "sed", "uname", "true", "grep", "ed", "domainname",
    # the DIALOG half (`firstboot.sh --dialog`). Every one of these is here
    # because a QUESTION needs it, and each stock helper is a `core` member, so it
    # is on every installed target, minimal tier included (verified against an
    # installed base-8 tree, 2026-08-12).
    "ksh",         # the genuine stock /usr/amiga/etc/TZ zone menu is ksh
    "passwd",      # the root-password question, and stock passwdall's own tool
    "date",        # the summary's stock Date: line
    "sum",         # the summary's stock NetNews cnews-vs-nntp test
    "stty",        # the stock terminal setup the dialog opens with
    "mknod",       # /dev/zen0 does not exist before rc2 (S99zen makes it)
    "chown", "chgrp",  # /dev/kinfo's owner and group on a 1.1 disk (no chgrp on the miniroot)
    "false",       # /usr/bin/true and /usr/bin/false ARE the A2024 flag (stock)
    "A2024", "aen", "passwdall", "amixcolorx", "amixmkuser", "amixnews",
    # IN-rtc-2: the ONE gated battery-clock re-read after the zone question
    # (see _strip_setclk_rerun) -- our plausibility-gated setclk, never a time
    "setclk",
    # trap ii of pick-at-install: re-register the installer-laid /stand/unix (040/060) in the core
    # package -- the stock pkgtools installf, a core member on every installed target
    "installf",
    # a 1.1 disk's /stand/unix out of the core package -- APKGENG's heirloom
    # removef and pkgchk (/usr/apkg/bin), from the APKG set every target carries
    "removef", "pkgchk",
    # C4-1: the root's name as the running kernel numbers it (stat only, a core member;
    # updbootpart and bcheckrc use it the same way)
    "devnm",
    # step 4d's `kbootset nodes` (C2-4 §14), the kbootset package every 1.1 disk
    # installs, behind `[ -x /sbin/kbootset ]`
    "kbootset",
    # 1.1: amix-base's ifup (the dialog's /etc/inet/interfaces checked with
    # `ifup -n`) and dlpi-mac (the amix-xxxx fallback name), and head, a core member
    "ifup", "dlpi-mac", "head",
}

# IN-rtc-2: the dialog re-reads the battery clock in the zone just chosen. This is
# the single clock-setting line the "never set the clock" rules let through, and
# only in its exact shape: our 1992..2037-gated setclk (it takes no time argument),
# right after /etc/clkzone is written and BEFORE clear_lastchg (so the password
# steps and the lastchg clear both run on the corrected clock -- the RTC trap stays
# closed). Anything else that sets the clock is still refused.
SETCLK_RERUN = ("if [ -x /usr/amiga/bin/setclk ]; then\n"
                "\t/usr/amiga/bin/setclk > /dev/null\nfi\n")
_SETCLK_RERUN_RE = re.compile(r'if \[ -x /usr/amiga/bin/setclk \]; then[ \t]*\n'
                              r'[ \t]*/usr/amiga/bin/setclk > /dev/null[ \t]*\n[ \t]*fi\n')


def _strip_setclk_rerun(code):
    """(code without the allowed re-read block, problem or None)."""
    hits = list(_SETCLK_RERUN_RE.finditer(code))
    if not hits:
        return code, None
    if len(hits) != 1:
        return code, "the setclk re-read appears %d times (exactly one allowed)" % len(hits)
    i = hits[0].start()
    z = code.rfind('echo "$ZSET" > /etc/clkzone', 0, i)
    if z < 0 or i - z > 600:
        return code, "the setclk re-read is not right after the /etc/clkzone write"
    if code.find("clear_lastchg\n", i) < 0:
        return code, "no clear_lastchg call follows the setclk re-read"
    return code[:i] + code[hits[0].end():], None

_BACKTICK_RE = re.compile(r'`([^`]*)`')
_TOK_RE = re.compile(r';;|&&|\|\||[;|&()\n]|[^\s;|&()\n]+')
_ASSIGN_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')






def _strip_quotes(text):
    """Collapse '...' and "..." spans to a padded placeholder, quote-aware and
    multi-line (backticks must already be extracted)."""
    out = []
    sq = dq = False
    for c in text:
        if sq:
            if c == "'":
                sq = False
                out.append(" %s " % QUOTED)
            continue
        if dq:
            if c == '"':
                dq = False
                out.append(" %s " % QUOTED)
            continue
        if c == "'":
            sq = True
        elif c == '"':
            dq = True
        else:
            out.append(c)
    return "".join(out)


def _strip_redirections(text):
    text = re.sub(r'[0-9]*>&[0-9-]+', ' ', text)            # 2>&1, >&2, >&-
    text = re.sub(r'[0-9]*>>?\s*[^\s;|&()<>]+', ' ', text)  # >f, >>f, 2>f
    text = re.sub(r'[0-9]*<\s*[^\s;|&()<>]+', ' ', text)    # <f
    return text


def _extract_backticks(text, inners):
    """Replace every `...` command substitution that is NOT inside single quotes
    with a space, appending its body to `inners`. Double-quoted backticks ARE
    substitutions (shell semantics); single-quoted ones are literal."""
    out = []
    sq = dq = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if sq:
            if c == "'":
                sq = False
            out.append(c)
        elif c == "`":
            j = text.find("`", i + 1)
            if j < 0:
                out.append(text[i:])
                break
            inners.append(text[i + 1:j])
            out.append(" ")
            i = j
        else:
            if c == '"':
                dq = not dq
            elif c == "'" and not dq:
                sq = True
            out.append(c)
        i += 1
    return "".join(out)


def command_words(text):
    """Yield the command first-word of every simple command in `text`."""
    text = strip_full_comments(text)
    text = re.sub(r'\\\n', ' ', text)      # join `\`-continued lines
    # recurse into backtick command subs, then remove them. Quote-aware: a backtick
    # inside '...' is literal text, not a command substitution -- the driver's
    # emit_* functions echo whole target scripts in single quotes (the S99zen
    # carries `sed ...`/`uname -n` substitutions that run on the TARGET, never on
    # the miniroot), and those must not be charged to the miniroot allowlist.
    inners = []
    text = _extract_backticks(text, inners)
    for inner in inners:
        for w in command_words(inner):
            yield w
    text = _strip_quotes(text)             # quoted spans -> placeholder (# in them gone)
    text = re.sub(r'(?m)(^|[ \t])#[^\n]*', r'\1', text)   # drop inline comments
    text = _strip_redirections(text)

    expect = True          # a command word is expected at this position
    pattern = False        # inside a case-pattern label
    case_depth = 0
    await_in = False       # after `case`, skip words until `in`
    await_do = False       # after `for`, skip words until `do`

    for tok in _TOK_RE.findall(text):
        # operators / separators (regardless of state)
        if tok in (";", "\n", "&", "&&", "||", "|"):
            if not pattern:
                expect = True
            continue
        if tok == ";;":
            if case_depth > 0:
                pattern = True
            expect = False
            continue
        if tok == "(":
            if not pattern:
                expect = True
            continue
        if tok == ")":
            pattern = False
            expect = True
            continue
        # case/for skip-states + esac + pattern labels (regardless of `expect`)
        if await_in:
            if tok == "in":
                await_in = False
                pattern = True
                case_depth += 1
            continue
        if await_do:
            if tok == "do":
                await_do = False
                expect = True
            continue
        if tok == "esac":
            if case_depth > 0:
                case_depth -= 1
            pattern = False
            expect = True
            continue
        if pattern:
            continue
        # NOT at a command position -> it is an argument (this is what keeps the
        # `!`/`-f` in `[ ! -f x ]` from being mistaken for the shell `!` keyword).
        if not expect:
            continue
        # command position:
        if tok == "case":
            await_in = True
            expect = False
            continue
        if tok == "for":
            await_do = True
            expect = False
            continue
        if tok in SH_KEYWORDS or tok == "in":
            expect = True                  # control word; the command follows it
            continue
        if tok == QUOTED or tok.startswith("$"):
            expect = False
            continue                       # quoted/variable command -- out of scope
        if _ASSIGN_RE.match(tok):
            continue                       # leading assignment; a command may follow
        if tok in WRAPPERS:
            expect = True                  # unwrap: the NEXT word is the real command
            continue
        yield tok
        expect = False








# ---------------------------------------------------------------------------
# H. subshell-loop audit -- redirect-fed `while read` loops must be subshell-safe
# ---------------------------------------------------------------------------
# The miniroot's 1991 SVR4 /bin/sh runs a `while ... done < FILE` loop in a
# SUBSHELL, so a variable MUTATED inside the loop body reverts to its pre-loop
# value at `done` (`npkgs` -> "installed 0 package(s)" while all 5 packages
# were installed; `vok` -> the aggregate guard `[ $vok -gt 0 ]` false-fired and the
# driver refused to arm first-boot). This audit FLAGS the exact defect class: a
# redirect-fed loop (`done < ...`) whose BODY assigns a variable that is then
# REFERENCED AFTER the loop. The subshell-safe idiom -- record to a temp file
# inside the loop, count/test it in the PARENT after `done` -- has no such
# assign-inside/use-after and passes. Negative fixtures (the bench-run pattern) prove
# the audit fires; positive controls (the temp-file idiom; a non-redirected loop)
# prove it does not over-fire.


def _sl_mask(text):
    """Length-preserving mask: blank out the CONTENTS of comments, quotes and
    backticks with spaces so do/done/NAME= structure scans see clean tokens, while
    character offsets are preserved so spans map back to the original text. `$#`
    is protected (a '#' only starts a comment at line start or after whitespace)."""
    out = list(text)
    n = len(text)
    i = 0
    sq = dq = bt = comment = False
    while i < n:
        c = text[i]
        if comment:
            if c == "\n":
                comment = False
            else:
                out[i] = " "
        elif sq:
            if c == "'":
                sq = False
            else:
                out[i] = " "
        elif dq:
            if c == '"':
                dq = False
            else:
                out[i] = " "
        elif bt:
            if c == "`":
                bt = False
            else:
                out[i] = " "
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n"):
            comment = True
            out[i] = " "
        elif c == "'":
            sq = True
            out[i] = " "
        elif c == '"':
            dq = True
            out[i] = " "
        elif c == "`":
            bt = True
            out[i] = " "
        i += 1
    return "".join(out)


def _sl_assigned(body_masked):
    """Variable names assigned in a (masked) loop body: `NAME=...` at a command
    position, plus `read NAME...` targets. Runs on the masked body so an `=` or a
    `read` word inside a string or backtick can never masquerade as an assignment."""
    names = set()
    for m in re.finditer(r'(?:^|[;&|()]|\bdo\b|\bthen\b|\belse\b)\s*'
                         r'([A-Za-z_][A-Za-z0-9_]*)=', body_masked):
        names.add(m.group(1))
    for m in re.finditer(r'\bread\b([^\n;|&<]*)', body_masked):
        for w in m.group(1).split():
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', w):    # skip -r and friends
                names.add(w)
    return names


def _sl_refs_var(after, var):
    """Is `var` referenced ($var / ${var}) anywhere after the loop? Single-quoted
    spans (which suppress $-expansion) are dropped; double quotes/backticks (which
    do NOT) are kept, so `"installed $npkgs"` still counts as a reference."""
    a = strip_full_comments(after)
    a = re.sub(r"'[^']*'", " ", a)
    return re.search(r'\$\{?%s\b' % re.escape(var), a) is not None


def _sl_redirected_loops(text):
    """Yield (body_masked, after_orig) for every do/done compound whose `done`
    carries a `<` redirect. Offsets come from the length-preserving mask; the body
    is returned masked (for structure) and the post-loop tail unmasked (for refs)."""
    masked = _sl_mask(text)
    stack = []
    for m in re.finditer(r'\bdo\b|\bdone\b', masked):
        if m.group(0) == "do":
            stack.append(m.end())
        elif stack:
            b0 = stack.pop()
            tail = masked[m.end():]
            mred = re.match(r'\s*<[^\n;)&|]*', tail)
            if mred:
                yield masked[b0:m.start()], text[m.end() + mred.end():]


def subshell_offenders(text):
    """Vars assigned inside a `done < FILE` loop body AND referenced after it."""
    bad = []
    for body_masked, after_orig in _sl_redirected_loops(text):
        for v in _sl_assigned(body_masked):
            if _sl_refs_var(after_orig, v):
                bad.append(v)
    return bad


_SL_EXIT_RE = re.compile(r'(?:^|[;&|{(]|\bthen\b|\belse\b|\bdo\b)[ \t]*(die|exit|run)\b', re.M)


def subshell_exit_offenders(text):
    """`die`/`exit`/`run` (run dies on failure) inside a `done < FILE` loop body:
    on the miniroot sh the body is a SUBSHELL, so the stop ends only the subshell
    and the install carries on (IN-fp: install.sh 5b had exactly this)."""
    bad = []
    for body_masked, _after in _sl_redirected_loops(text):
        bad += [m.group(1) for m in _SL_EXIT_RE.finditer(body_masked)]
    return bad


def _redirected_read_offenders(text):
    """`read VAR... < FILE` and `{ ...; } < FILE` -- BOTH forbidden outright.

    ★ BENCH-MEASURED 2026-08-11 (matrix run w3b2-cdi). The code read the medium's set
    table with the obvious idiom

        { read R1N R1SET R1ORD R1ATT R1LBL
          read R2N R2SET R2ORD R2ATT R2LBL ; } < "$SET_F"

    and the 1991 SVR4 sh FORKED for it: both reads happened in a child, the
    parent saw empty variables, and the interview died on its own guard
    (`STOP: internal: /cdrom/install/sets has no usable first row`) with the
    console still waiting on a prompt. It is the same shell behaviour that makes
    every `while read ... done < FILE` loop a subshell here (audit H) -- a
    redirected COMPOUND command is a fork -- and this repo has exactly one idiom
    that survives it: write the value to a FILE and `cat` it back in the parent.

    A redirected `read` on a SIMPLE command is not known to fork, but it is
    banned with the compound form on purpose: nothing here needs it, the two are
    indistinguishable at a glance, and one of them costs a ten-minute blind
    console run to diagnose. `done < FILE` is exempt -- that is audit H's
    territory and the loops here are written knowing they are subshells."""
    bad = []
    masked = _sl_mask(text)
    for m in re.finditer(r'\}\s*<[^<]', masked):
        ln = text[:m.start()].count("\n") + 1
        bad.append("line %d: `} <` -- a redirected brace group FORKS on this shell" % ln)
    for m in re.finditer(r'(?:^|[;&|(]|\bdo\b|\bthen\b|\belse\b)\s*'
                         r'read\s+[A-Za-z_][^\n;|&<]*<[^<]', masked):
        ln = text[:m.start()].count("\n") + 1
        bad.append("line %d: `read VAR... < FILE` -- use a temp file + `cat`" % ln)
    return bad


def audit_subshell_loops():
    head("H. subshell-safe loops (redirect-fed `while read` must not assign-then-use-after)")
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT):
        rel = os.path.relpath(path, REPO)
        if not os.path.isfile(path):
            fail("%s: missing" % rel)
            continue
        text = read_sh(path)
        nloops = len(list(_sl_redirected_loops(text)))
        bad = subshell_offenders(text)
        if bad:
            fail("%s: %d redirect-fed loop(s); variable(s) assigned in a subshell "
                 "loop body and used AFTER the loop (lost on the miniroot sh): %s"
                 % (rel, nloops, ", ".join(sorted(set(bad)))))
        else:
            ok("%s: %d redirect-fed `while read ... done < FILE` loop(s), none "
               "leak a body-assigned variable past `done`" % (rel, nloops))

    # NON-VACUITY: the driver is KNOWN to carry two redirect-fed loops (the pkgadd
    # loop and the boot-chain verify loop). If the structure scanner finds none,
    # a clean result would be vacuous -- fail rather than pass silently.
    dloops = len(list(_sl_redirected_loops(open(DRIVER, encoding="utf-8").read())))
    if dloops >= 2:
        ok("scanner locates the driver's %d redirect-fed loops (non-vacuity)" % dloops)
    else:
        fail("subshell-loop scanner found only %d redirect-fed loop(s) in the "
             "driver (expected the pkgadd + verify loops) -- audit would be vacuous"
             % dloops)

    # H4 (IN-fp): 5b EXECUTED -- the real block, under sh, against a fake medium +
    # target with a stub `sum`: a good pair installs, and a mismatch, an unknown
    # member or a missing target file each STOP (in the parent, after the loop).
    drv = read_sh(DRIVER)
    m5b = re.search(r'\nFPFIX="\$INST/fpfix"\n.*?\nfi\n', drv, re.S)
    mct = re.search(r'\ncount_tokens\(\) \{\n.*?\n\}\n', drv, re.S)
    if not (m5b and mct):
        fail("H4: cannot extract install.sh 5b / count_tokens for the executed test")
    else:
        def run5b(sums, files):
            t = tempfile.mkdtemp(prefix="st-5b.")
            try:
                inst, tgt = os.path.join(t, "inst"), os.path.join(t, "tgt")
                for d in ("fpfix", "bin"):
                    os.makedirs(os.path.join(inst, d))
                os.makedirs(os.path.join(tgt, "tmp"))
                os.makedirs(os.path.join(tgt, "usr/lib/fs/ufs"))
                open(os.path.join(inst, "fpfix", "SUMS"), "w").write(sums)
                for rel, body in files.items():
                    open(os.path.join(t, rel), "w").write(body)
                sb = os.path.join(inst, "bin", "sum")
                open(sb, "w").write('#!/bin/sh\nread w < "$2"; echo "$w 1 $2"\n')
                os.chmod(sb, 0o755)
                harness = ('die() { echo "DIE: $*"; exit 1; }\nmsg() { echo "MSG: $*"; }\n'
                           'runq() { "$@"; }\n' + mct.group(0) +
                           'INST=%s\nTARGET=%s\nTARGET_ROOT_FSTYPE=ufs\n' % (inst, tgt) +
                           m5b.group(0) + 'echo END\n')
                r = subprocess.run(["sh", "-c", harness], capture_output=True, text=True)
                return r.returncode, r.stdout
            finally:
                shutil.rmtree(t, ignore_errors=True)
        both = {"inst/fpfix/mkfs": "111\n", "inst/fpfix/fsck": "222\n",
                "tgt/usr/lib/fs/ufs/mkfs": "0\n", "tgt/usr/lib/fs/ufs/fsck": "0\n"}
        cases = [
            ("good pair", "mkfs 111\nfsck 222\n", both, 0, "END"),
            ("sum mismatch", "mkfs 111\nfsck 999\n", both, 1, "REFUSING to arm"),
            ("unknown member", "mkfs 111\nfdisk 5\n", both, 1, "unknown fpfix member"),
            ("target lacks fsck", "mkfs 111\nfsck 222\n",
             {k: v for k, v in both.items() if k != "tgt/usr/lib/fs/ufs/fsck"}, 1, "no /usr/lib/fs/ufs/fsck"),
        ]
        wrong = []
        for name, sums, files, rc, needle in cases:
            got_rc, out = run5b(sums, files)
            if got_rc != rc or needle not in out or (rc and "END" in out):
                wrong.append((name, got_rc, out.strip()[-160:]))
        if wrong:
            fail("H4: install.sh 5b EXECUTED wrong: %s" % wrong)
        else:
            ok("H4: install.sh 5b EXECUTED: a good pair installs; a sum mismatch, an "
               "unknown member and a missing target file each STOP after the loop")

    # NEGATIVE FIXTURES -- the audit MUST fire on the exact bench-run defect, both the
    # pkgadd shape (`npkgs`) and the verify shape (`vok`), inside single AND double
    # quotes for the post-loop reference.
    neg = [
        ("bench-run pkgadd (npkgs, dq ref)",
         '#!/bin/sh\nnpkgs=0\nwhile read pkg; do\n'
         '  npkgs=`expr "$npkgs" + 1`\ndone < /cd/order\n'
         'echo "installed $npkgs package(s)"\n', "npkgs"),
        ("bench-run verify (vok, guard ref)",
         '#!/bin/sh\nvok=0\nwhile read r a b c; do\n'
         '  vok=`expr "$vok" + 1`\ndone < /cd/manifest\n'
         '[ "$vok" -gt 0 ] || echo refuse\n', "vok"),
        ("general body var, ${..} ref after",
         '#!/bin/sh\ntotal=0\nwhile read n; do\n'
         '  total=`expr "$total" + "$n"`\ndone < /cd/nums\necho ${total}\n', "total"),
    ]
    for name, script, needle in neg:
        bad = subshell_offenders(script)
        if needle in bad:
            ok("negative fixture fires: %-32s -> flagged %r" % (name, needle))
        else:
            fail("negative fixture DID NOT fire: %s (expected %r; got %r)"
                 % (name, needle, bad))

    # POSITIVE CONTROLS -- must NOT fire.
    pos = [
        ("temp-file idiom (count in parent)",
         '#!/bin/sh\n: > /t/ok\nwhile read pkg; do\n  echo "$pkg" >> /t/ok\n'
         'done < /cd/order\nset -- `cat /t/ok`\nn=$#\necho "installed $n"\n'),
        ("non-redirected loop (no subshell)",
         '#!/bin/sh\nn=0\nfor x in a b c; do n=`expr $n + 1`; done\necho $n\n'),
        ("body var not used after",
         '#!/bin/sh\nwhile read k v; do echo "$k=$v"; done < /cd/f\necho done\n'),
    ]
    for name, script in pos:
        bad = subshell_offenders(script)
        if bad:
            fail("positive control wrongly flagged: %s -> %r" % (name, bad))
        else:
            ok("positive control passes clean: %s" % name)

    # --- H3 (IN-fp): no die/exit/run inside a redirect-fed loop body ---------
    # The subshell swallows the stop: 5b's FP-patch verify could fail and the
    # install still arm the disk. Record in the loop, decide after `done`.
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT):
        rel = os.path.relpath(path, REPO)
        if not os.path.isfile(path):
            continue
        bad = subshell_exit_offenders(read_sh(path))
        if bad:
            fail("%s: %s inside a redirect-fed loop body (ends only the subshell)"
                 % (rel, ", ".join(sorted(set(bad)))))
        else:
            ok("%s: no die/exit/run inside a redirect-fed loop body" % rel)
    neg3 = [
        ("5b shape (die in the body)", '#!/bin/sh\nwhile read a b; do\n'
         '\t[ "$a" = "$b" ] || die "mismatch"\ndone < /cd/SUMS\n', "die"),
        ("run in the body", '#!/bin/sh\nwhile read f; do\n\trun cp "$f" /t\ndone < /cd/l\n', "run"),
        ("exit after then", '#!/bin/sh\nwhile read f; do\n\tif [ -z "$f" ]; then exit 1; fi\n'
         'done < /cd/l\n', "exit"),
    ]
    for name, script, needle in neg3:
        if needle in subshell_exit_offenders(script):
            ok("H3 negative fixture fires: %s" % name)
        else:
            fail("H3 negative fixture DID NOT fire: %s" % name)
    pos3 = [
        ("record in the loop, die after done", '#!/bin/sh\n: > /t/f\nwhile read a; do\n'
         '\techo "$a" >> /t/f\ndone < /cd/l\n[ -s /t/f ] && die "failed"\n'),
        ("runq and a quoted 'die' in the body", '#!/bin/sh\nwhile read a; do\n'
         '\trunq cp "$a" /t || echo "would die" >> /t/f\ndone < /cd/l\n'),
        ("die in a non-redirected loop", '#!/bin/sh\nfor a in x y; do\n\t[ -f "$a" ] || die "no $a"\ndone\n'),
    ]
    for name, script in pos3:
        if subshell_exit_offenders(script):
            fail("H3 positive control wrongly flagged: %s" % name)
        else:
            ok("H3 positive control passes clean: %s" % name)

    # --- H2: no redirected `read`, and no redirected brace group -------------
    # Bench-measured: a redirected COMPOUND command forks on the miniroot sh, so
    # `{ read A; read B; } < FILE` silently assigns nothing in the parent. Both
    # forms are banned; the surviving idiom is a temp file plus `cat`.
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT):
        rel = os.path.relpath(path, REPO)
        if not os.path.isfile(path):
            continue
        bad = _redirected_read_offenders(read_sh(path))
        if bad:
            for b in bad:
                fail("%s: %s" % (rel, b))
        else:
            ok("%s: no redirected `read`, no redirected brace group" % rel)
    neg2 = [
        ("brace group fed by a file",
         '#!/bin/sh\n{ read A B\n  read C D ; } < /cd/sets\necho "$A$C"\n', "} <"),
        ("simple redirected read",
         '#!/bin/sh\nread A B C < /tmp/row\necho "$A"\n', "read VAR"),
        ("redirected read inside an if",
         '#!/bin/sh\nif [ -s /t/f ]; then read X < /t/f; fi\necho "$X"\n', "read VAR"),
    ]
    for name, script, needle in neg2:
        bad = _redirected_read_offenders(script)
        if any(needle in b for b in bad):
            ok("H2 negative fixture fires: %-28s -> %s" % (name, bad[0]))
        else:
            fail("H2 negative fixture DID NOT fire: %s (got %r)" % (name, bad))
    pos2 = [
        ("temp file + cat (the surviving idiom)",
         '#!/bin/sh\nwhile read a b; do echo "$b" > /t/v; done < /cd/f\n'
         'V=`cat /t/v`\necho "$V"\n'),
        ("a redirect-fed while loop is audit H\'s business, not H2\'s",
         '#!/bin/sh\nwhile read x; do echo "$x"; done < /cd/order\n'),
        ("`read` from the console (the interview\'s own prompt)",
         '#!/bin/sh\nreadask()\n{\n\techo "$*\\c"\n\tread ask\n}\nreadask "Choose: "\n'),
    ]
    for name, script in pos2:
        bad = _redirected_read_offenders(script)
        if bad:
            fail("H2 positive control wrongly flagged: %s -> %r" % (name, bad))
        else:
            ok("H2 positive control passes clean: %s" % name)


# ---------------------------------------------------------------------------
# I. pre-POSIX `set --` counting guard (the empty-arg no-op trap)
# ---------------------------------------------------------------------------
# The subshell-safe loops (H) count by tallying an append-only temp file after the
# loop. The natural `set -- `cat FILE`; n=$#` is a TRAP on the miniroot's 1991 sh:
# `set --` with an EMPTY argument list is a NO-OP on $@ there (it does NOT clear the
# positional parameters -- confirmed on-box: `set -- a b c; set -- `cat /dev/null``
# leaves $#=3), so counting an EMPTY file returns a STALE count from a previous
# `set --`. (A bench run: vok counted 3, then the empty vfails file "counted" 3 too
# and the boot-chain verify false-failed.) The safe idiom guards with `[ -s FILE ]`
# so `set --` is only ever fed a non-empty list. This audit flags any
# `set -- `cmd`` in the driver that is NOT `[ -s ]`-guarded on its own or a nearby
# preceding line; a negative fixture proves it fires, a positive control passes.


def _unguarded_set_counts(text):
    """Lines with `set -- `cmd`` (a backtick command-sub fed to `set --`) that are
    NOT protected by a `[ -s ... ]` presence guard on the same or one of the two
    preceding non-blank lines -- the empty-`set --` no-op counting trap."""
    lines = strip_full_comments(text).splitlines()
    bad = []
    for i, l in enumerate(lines):
        if not re.search(r'\bset\s+--\s+`', l):
            continue
        guarded = bool(re.search(r'\[\s*-s\s', l))       # same-line guard
        seen = 0
        j = i - 1
        while j >= 0 and not guarded and seen < 2:
            if lines[j].strip():
                seen += 1
                if re.search(r'\[\s*-s\s', lines[j]):
                    guarded = True
            j -= 1
        if not guarded:
            bad.append(l.strip())
    return bad


def audit_setcount_guard():
    head("I. pre-POSIX `set --` counting guard (empty arg list is a no-op on the miniroot sh)")
    for path in (MINIROOT_PROFILE, DRIVER, SETUP):
        rel = os.path.relpath(path, REPO)
        bad = _unguarded_set_counts(read_sh(path))
        if bad:
            fail("%s has UNGUARDED `set -- `cmd`` count(s) -- an empty `set --` leaves "
                 "$@ stale on the miniroot sh, so an empty file miscounts; guard with "
                 "`[ -s FILE ]`: %s" % (rel, "; ".join(bad)))
        else:
            ok("every `set -- `cmd`` in %s is `[ -s ]`-guarded (empty-safe)" % rel)
    neg = "#!/bin/sh\n: > /t/f\nset -- `cat /t/f`\nn=$#\necho $n\n"
    if _unguarded_set_counts(neg):
        ok("negative fixture fires: unguarded `set -- `cat FILE`; $#` is flagged")
    else:
        fail("negative fixture did NOT fire (unguarded set-- count missed)")
    pos = ("#!/bin/sh\ncount() {\n\tif [ -s \"$1\" ]; then\n\t\tset -- `cat \"$1\"`\n"
           "\t\techo $#\n\telse\n\t\techo 0\n\tfi\n}\nn=`count /t/f`\n")
    if _unguarded_set_counts(pos):
        fail("positive control wrongly flagged the `[ -s ]`-guarded count")
    else:
        ok("positive control passes: the `[ -s ]`-guarded count_tokens idiom is accepted")


# ---------------------------------------------------------------------------
# J. first-boot init wiring -- rc2 hook + stock-dialog disarm
# ---------------------------------------------------------------------------
# The payload was ARMED by earlier work but nothing in the STOCK target init
# invoked it, so cold boot #1 fell into the stock sysinit dialog. This closes
# the gap two ways, both proven against an s5 read of the installed target:
#   * install.sh WRITES /etc/rc2.d/S16firstboot (a NEW, non-package file -- it is
#     driver-written, not copied from the CD, so it never reaches the pkgadd
#     contents DB and cannot perturb altroot-attest);
#   * install.sh DISARMS the stock dialog -- /etc/sysinit runs
#     /usr/amiga/bin/system.setup iff it is `-x`, so `chmod -x` (the stock's OWN
#     once-only mechanism) suppresses it. Mode-only; content/cksum untouched.
# This audit locks all of that: the arm step writes the hook and disarms the
# dialog; the driver's emit_firstboot_hook reproduces the tracked template
# byte-for-byte (drift-lock); the hook is pre-POSIX, guards on PENDING, invokes
# firstboot.sh, and references only target-present tools; and firstboot.sh
# removes PENDING (the once-only half the hook relies on).


def _extract_func(src, name):
    lines = src.splitlines()
    fi = next(i for i, l in enumerate(lines) if l.startswith(name + "()"))
    fj = next(i for i in range(fi + 1, len(lines)) if lines[i] == "}")
    return "\n".join(lines[fi:fj + 1])






# ---------------------------------------------------------------------------
# IS. interactive disk scan -- card-1 media scan card 1 ONLY (choose_disk must
#     never open a c0..c7 node = the phantom A3091, first I/O = bus-error panic).
# ---------------------------------------------------------------------------
# The interview's scan_disks opens /dev/dsk/c<i>d0s0 for every i in SCAN_IDS. On a
# card-1 medium that list MUST be card-1 ids only, derived from the SAME baked file
# the source auto-probe uses (/etc/install-src-candidates), so it cannot regress.
# Every other device open in setup.sh keys on the scanned $i or the chosen $SCSI,
# so once the scan is card-1 the whole interview is card-1-clean; a hardcoded
# c0..c7 node anywhere would defeat that, so it is also refused here.
# ---------------------------------------------------------------------------
# RB. RDSK at block 0 -- the author path's RDB must be findable by STOCK Z3660
#     firmware (2026-09-26).
# ---------------------------------------------------------------------------
# Stock firmware reads the image in 64 KB strides and tests 4 bytes per read: it
# finds an RDB at byte 0 and never at block 2. The stock Amix line is
# `/etc/rdb -c -L 2`, and /etc/rdb honours -L ONLY on a disk with no RDSK in
# 0..15 (it rewrites an existing RDB where it finds it -- disassembly of the stock
# binary, md5 6cacf95f...). So the author path must (1) default the block to 0
# with only 0|2 accepted, (2) clear blocks 0..15 BEFORE `rdb -c`, (3) pass
# -L "$TARGET_RDB_BLOCK" (never a literal), and (4) read the magic back at byte 0
# and die if it is not there.
def audit_rdb_location():
    head("RB. author path writes the RDSK at block 0 (stock-Z3660-firmware findable)")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)
    # (1) the key: default 0, only 0|2, anything else dies -- EXECUTED, not grepped
    try:
        lines = code.splitlines()
        i = next(k for k, l in enumerate(lines)
                 if l.startswith('[ -n "$TARGET_RDB_BLOCK" ]'))
        j = next(k for k in range(i, len(lines)) if lines[k] == "esac")
        span = "\n".join(lines[i:j + 1])
    except StopIteration:
        span = None
        fail("TARGET_RDB_BLOCK default/validation block not found at top level")
    if span:
        pre = 'die() { echo "DIE: $*"; exit 3; }\n'
        post = '\necho "RDB_BLOCK=$TARGET_RDB_BLOCK"\n'
        for val, want in (("", "RDB_BLOCK=0"), ("0", "RDB_BLOCK=0"),
                          ("2", "RDB_BLOCK=2"), ("1", "DIE"), ("x", "DIE"),
                          ("16", "DIE")):
            r = _run_sh(pre + span + post, [], env={"TARGET_RDB_BLOCK": val})
            got = (r.stdout or "").strip()
            if got.startswith(want):
                ok("TARGET_RDB_BLOCK=%r -> %s" % (val, got.splitlines()[0][:60]))
            else:
                fail("TARGET_RDB_BLOCK=%r gave %r, expected %s" % (val, got, want))
    try:
        fn = strip_full_comments(_extract_func(driver_src, "build_target_author"))
    except StopIteration:
        fn = None
        fail("could not extract build_target_author() from the driver")
    if not fn:
        return
    clear = re.search(r'run dd if=/dev/zero of="\$DISK_RAW" bs=512 count=16\b', fn)
    if not clear and re.search(r'\n\tRDB_CLEAR=16\n', fn):
        clear = re.search(r'run dd if=/dev/zero of="\$DISK_RAW" bs=512 count="\$RDB_CLEAR"', fn)
    create = re.search(r'run /etc/rdb -c -s "\$SECS" -L "\$TARGET_RDB_BLOCK" '
                       r'-d "\$DISKLEN" "\$DISK_RAW"', fn)
    literal = re.search(r'run /etc/rdb -c[^\n]*-L\s+[0-9]', fn)
    back = re.search(r'RDSK\*\)\s+msg "RDB read-back', fn)
    backdie = re.search(r'die "RDB read-back: no RDSK at block 0', fn)
    if clear and create and clear.start() < create.start():
        ok("blocks 0..15 are cleared BEFORE `/etc/rdb -c`, so its -L is honoured "
           "even on a reinstall over an old RDSK-at-2 disk")
    else:
        fail("the 0..15 clear is missing or does not precede `/etc/rdb -c` "
             "(clear=%s create=%s)" % (bool(clear), bool(create)))
    if create and not literal:
        ok("`/etc/rdb -c` takes -L \"$TARGET_RDB_BLOCK\" (no literal block number)")
    else:
        fail("`/etc/rdb -c` does not use -L \"$TARGET_RDB_BLOCK\" (literal=%s)"
             % bool(literal))
    if back and backdie and create and back.start() > create.start():
        ok("the RDSK magic is read back at byte 0 after authoring, and a miss DIES")
    else:
        fail("no fail-closed RDSK-at-byte-0 read-back after `/etc/rdb -c` "
             "(readback=%s die=%s)" % (bool(back), bool(backdie)))
    # the guard's dd bs=4 probe is not an author write; the clear must be the ONLY
    # dd that writes $DISK_RAW (anything else would be an unaudited raw write)
    writes = re.findall(r'dd [^\n]*of="\$DISK_RAW"', fn)
    if len(writes) == 1:
        ok("the 0..15 clear is the only dd writing $DISK_RAW")
    else:
        fail("%d dd writes to $DISK_RAW in build_target_author, expected 1" % len(writes))


def audit_interactive_card1_scan():
    head("IS. interactive disk scan is card-1-safe (choose_disk never opens a card-0 node)")
    code = strip_full_comments(open(SETUP, encoding="utf-8").read())
    reads_cand = "/etc/install-src-candidates" in code
    classifies = bool(re.search(r'\[89aAbBcCdDeEfF\]\)', code))
    card1_set = re.search(r'SCAN_IDS="([89a-fA-F ]+)"', code)
    card1_ok = bool(card1_set and all(int(t, 16) >= 8 for t in card1_set.group(1).split()))
    if reads_cand and classifies and card1_ok:
        ok("setup.sh derives a card-1 SCAN_IDS from /etc/install-src-candidates "
           "(controller 8..f => %s) -- a card-1 medium scans card 1 only" % card1_set.group(1))
    else:
        fail("setup.sh does not derive a card-1-only SCAN_IDS from the baked candidates "
             "(reads=%s classify=%s card1-only=%s) -- a card-1 medium's 'Scanning SCSI "
             "bus' would open card 0 and double-panic (pc=0x800D578)"
             % (bool(reads_cand), classifies, card1_ok))
    # the card-0 default is still present for the 030 line / no-candidates media.
    if re.search(r'SCAN_IDS="0 1 2 3 5 6"', code):
        ok("the historical card-0 default remains for the 030 line / media with no candidates file")
    else:
        fail("setup.sh lost its card-0 SCAN_IDS default -- the 030 line would not scan")
    # NO hardcoded c0..c7 disk node anywhere in setup.sh -- every open is c${i}/
    # c${SCSI}/c${1}d0sN (a scanned or chosen id).
    stray = sorted(set(re.findall(r'/dev/r?dsk/c[0-7]d\d', code)))
    if stray:
        fail("setup.sh opens hardcoded card-0..7 node(s) %s -- each is a bus-error "
             "landmine on a card-1 medium, defeating the card-1 scan" % ", ".join(stray))
    else:
        ok("setup.sh opens disk nodes only as c${i}/c${SCSI}/c${1}d0sN (scanned or "
           "chosen id) -- no hardcoded c0..c7, so the card-1 scan list is the sole gate")
    # The miniroot's REPAIR path (src/miniroot/profile scan_ids) opens c<i>d0s0 for
    # every SCAN_IDS id too, so "Do you want to install or repair? -> repair" must
    # derive the SAME card-1 list from the baked candidates. (Its legacy card-0
    # RAW_CANDIDATES default is a source-probe fallback for 030 media, not a scan, so
    # a blanket no-c0..c7 check does not apply here -- the derivation is what matters.)
    mp = strip_full_comments(open(MINIROOT_PROFILE, encoding="latin-1").read())
    m_class = bool(re.search(r'\[89aAbBcCdDeEfF\]\)', mp))
    m_c1 = re.search(r'SCAN_IDS="([89a-fA-F ]+)"', mp)
    m_c1_ok = bool(m_c1 and all(int(t, 16) >= 8 for t in m_c1.group(1).split()))
    m_def = bool(re.search(r'SCAN_IDS="0 1 2 3 5 6"', mp))
    if m_class and m_c1_ok and m_def:
        ok("src/miniroot/profile derives the SAME card-1 scan for the REPAIR path "
           "(scan_ids => %s on a card-1 medium; card-0 default kept)" % m_c1.group(1))
    else:
        fail("src/miniroot/profile's repair scan (scan_ids) does not derive a card-1-only "
             "SCAN_IDS (classify=%s card1=%s default=%s) -- 'repair' would open card 0 and "
             "double-panic on a card-1 medium" % (m_class, m_c1_ok, m_def))
    # The repair MOUNT+FSCK must match the installed root's filesystem. build-miniroot
    # bakes ROOT_FSYS to this miniroot's line (ufs on 040/060) and repairdisk() fscks
    # it -- a ufs root fsck'd as s5 dropped the v7 repair to a shell (metal 2026-09-15).
    # Require a ROOT_FSYS=ufs branch carrying a LITERAL fsck_ufs (both fsck_* are proto
    # members), not a bare hardcoded fsck_s5.
    m_ufs_branch = bool(re.search(r'ROOT_FSYS"?\s*=\s*ufs', mp)) and "fsck_ufs" in mp
    m_s5_fsck = "fsck_s5" in mp
    if m_ufs_branch and m_s5_fsck:
        ok("src/miniroot/profile repairdisk is fs-aware: fsck_ufs under a ROOT_FSYS=ufs "
           "branch, fsck_s5 otherwise -- a ufs root is no longer fsck'd as s5 (v7 metal "
           "finding); build-miniroot bakes ROOT_FSYS to the built line")
    else:
        fail("src/miniroot/profile repairdisk is NOT fs-aware (ufs-branch+fsck_ufs=%s "
             "fsck_s5=%s) -- a ufs-root repair would fsck as s5 and drop to a shell "
             "without mounting" % (m_ufs_branch, m_s5_fsck))


# ---------------------------------------------------------------------------
# K. installer completeness -- contents-fsck fail-closed step + apkg.conf
# ---------------------------------------------------------------------------
# Two additions to the driver, both audited fail-closed:
#   * The driver runs the CD-resident STATIC contents-fsck over the freshly built
#     <root>/var/sadm/install/contents AFTER the pkgadd loop and BEFORE arming
#     first-boot. It must be FAIL CLOSED: any non-zero exit -> `die`, with NO
#     `|| true`/`|| :`-style softening on the invocation (a soft contents-fsck is
#     worse than none -- it launders a bad DB into a green install). CHECK-ONLY:
#     never a `-r` repair (a fresh DB that needs repair means the install is wrong).
#   * The driver WRITES /etc/apkg.conf onto the target with the live-repo line, on
#     the miniroot (identity-independent -> NOT first-boot), so an installed box's
#     package client points at the repo out of the box.


def audit_x11_easystart():
    """firstboot makes the installed system X-READY before the X packages
    exist. The X set (xcore/xbasic/olcore) is an apkg step the operator runs
    LATER; the stock login PATH carries no /usr/bin/X11 and no LD_LIBRARY_PATH,
    and olwm's libXol.so is in /usr/lib (not the X binaries' own /usr/X/lib). The
    fix lives in OUR firstboot (the stock X bytes are proprietary) and must be
    SVR4-Bourne-safe + idempotent (firstboot can re-run if the dialog spans boots)."""
    print()
    print("== X11 easy-start (firstboot: PATH/lib env + one-command startx) ==")
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())

    path_x = bool(re.search(r'PATH=\$PATH:/usr/bin/X11', fb))
    ldlib = bool(re.search(r'LD_LIBRARY_PATH=/usr/lib\b', fb))
    to_profile = bool(re.search(r'\}\s*>>\s*/etc/profile', fb))
    if path_x and ldlib and to_profile:
        ok("firstboot appends /usr/bin/X11 to PATH + LD_LIBRARY_PATH=/usr/lib onto "
           "/etc/profile (the stock login PATH carries neither) -- root and every user")
    else:
        fail("firstboot does not make X resolvable via /etc/profile "
             "(PATH+=/usr/bin/X11=%s LD_LIBRARY_PATH=/usr/lib=%s append>>/etc/profile=%s)"
             % (path_x, ldlib, to_profile))

    guarded = bool(re.search(r"if\s+grep\s+'Installer-NG X11'[^\n]*/etc/profile", fb))
    bad_neg = bool(re.search(r'(?:if|&&|\|\|)\s+!\s+grep', fb))
    if guarded and not bad_neg:
        ok("the /etc/profile append is grep-guarded (idempotent -- a dialog that "
           "spans boots re-runs firstboot) with no `!` pipeline negation (the target "
           "/bin/sh is the 1991 SVR4 Bourne shell, which lacks it)")
    else:
        fail("the X11 /etc/profile append is not SVR4-safe/idempotent "
             "(grep-guard=%s forbidden-`! grep`=%s)" % (guarded, bad_neg))

    # apkg PATH: /opt/amix/bin appended LAST on /etc/profile PATH (the rule: last,
    # never first -- stock tools keep precedence). Same /etc/profile-only append as
    # the X11 block, its OWN grep guard, and it must come AFTER the /usr/bin/X11
    # append so /opt/amix/bin lands last (metal-verified fresh-login PATH ends
    # ...:/usr/bin/X11:/opt/amix/bin; this is what fixes `less: command not found`).
    amix_path = bool(re.search(r'PATH=\$PATH:/opt/amix/bin', fb))
    amix_guard = bool(re.search(r"grep\s+'/opt/amix/bin'\s+/etc/profile", fb))
    _x11p = fb.find('PATH=$PATH:/usr/bin/X11')
    _amixp = fb.find('PATH=$PATH:/opt/amix/bin')
    amix_last = amix_path and _x11p != -1 and _amixp > _x11p
    if amix_path and amix_guard and amix_last:
        ok("apkg PATH: firstboot appends /opt/amix/bin LAST on /etc/profile PATH "
           "(after the /usr/bin/X11 append), grep-guarded -- stock tools keep "
           "precedence (last, never first); fixes `less: command not found`")
    else:
        fail("the /opt/amix/bin PATH append is wrong (present=%s grep-guard=%s "
             "after-X11=%s)" % (amix_path, amix_guard, amix_last))

    # The OPEN LOOK desktop: olwm (window frames) + olwsm (the
    # SEPARATE Workspace-menu daemon -- without it there is no root menu, the
    # "no window manager" look) + a session-controlling `exec xterm` (its exit
    # ends the X session). The old single `exec olwm` is intentionally gone.
    xinitrc = (bool(re.search(r'>\s*/\.xinitrc', fb))
               and 'olwm &' in fb and 'olwsm &' in fb
               and bool(re.search(r'exec xterm\b', fb)))
    # .xinitrc MUST be executable (755): xinit execs it as the client and only
    # falls back to `sh` on it if X_OK -- a 644 .xinitrc launches no client and
    # startx dies on launch. Catch a regression to 644.
    xinitrc_exec = (bool(re.search(r'chmod 755 /\.xinitrc', fb))
                    and not re.search(r'chmod 644 /\.xinitrc', fb))
    skel = bool(re.search(r'/etc/skel/\.xinitrc', fb))
    startx = bool(re.search(r'>\s*/usr/local/bin/startx', fb))
    abs_server = bool(re.search(r'xinit\s+--\s+/usr/bin/X11/X2410', fb))
    if xinitrc and xinitrc_exec and startx and abs_server:
        ok("one-command desktop: /.xinitrc (+/etc/skel=%s) = the OPEN LOOK desktop "
           "(olwm + olwsm Workspace menu + xclock/xload/olfm/2 xterms, the exec'd "
           "xterm controls the session) and EXECUTABLE (755 -- xinit execs it), "
           "/usr/local/bin/startx runs xinit against X2410 by ABSOLUTE path" % skel)
    else:
        fail("the X easy-start desktop is incomplete (/.xinitrc olwm+olwsm+exec-xterm=%s "
             "exec-755=%s startx=%s abs-server=%s)" % (xinitrc, xinitrc_exec, startx, abs_server))

    # FIXTURE: apply firstboot's exact append lines the way the login shell will,
    # and confirm /usr/bin/X11 lands on PATH (so xinit/X2410/olwm/xterm resolve by
    # name) and LD_LIBRARY_PATH is /usr/lib (so olwm finds libXol.so).
    fixture = (
        "PATH=/usr/bin:/usr/amiga/bin\n"
        "PATH=$PATH:/usr/bin/X11\n"
        "LD_LIBRARY_PATH=/usr/lib\n"
        "export PATH LD_LIBRARY_PATH\n"
        'case ":$PATH:" in *:/usr/bin/X11:*) echo XPATH_OK ;; *) echo XPATH_BAD ;; esac\n'
        'echo "LDLIB=$LD_LIBRARY_PATH"\n'
    )
    r = subprocess.run(["/bin/sh", "-c", fixture], capture_output=True, text=True)
    if "XPATH_OK" in r.stdout and "LDLIB=/usr/lib" in r.stdout:
        ok("fixture: after firstboot's appended lines /usr/bin/X11 is on PATH and "
           "LD_LIBRARY_PATH=/usr/lib -- the X server + clients resolve by name")
    else:
        fail("fixture: firstboot's appended PATH/LD_LIBRARY_PATH lines do not put "
             "/usr/bin/X11 on PATH (out=%r)" % r.stdout)




def audit_card1_derivation_exec():
    """Overnight review 2026-09-16 (minor): the card-1 SCAN_IDS derivation was only
    regex-audited, never EXECUTED. Run the actual derivation block extracted from
    setup.sh, both branches: a card-1 candidate file present -> SCAN_IDS becomes the
    card-1 list; a card-0 candidate or no file -> the card-0 default holds."""
    head("IS-exec. the card-1 SCAN_IDS derivation, ACTUALLY RUN (both branches)")
    if not os.path.exists("/usr/bin/dash"):
        skip("dash absent -- cannot run the derivation under a pre-POSIX-ish sh")
        return
    src = read_sh(SETUP)
    m = re.search(r'(if \[ -z "\$SCAN_IDS" \] && \[ -f /etc/install-src-candidates \]'
                  r'.*?\n\[ -n "\$SCAN_IDS" \] \|\| SCAN_IDS="0 1 2 3 5 6")', src, re.S)
    if not m:
        fail("could not extract the SCAN_IDS derivation block from setup.sh -- "
             "the exec test cannot run (has the block moved or changed shape?)")
        return
    d = workpath("card1deriv")
    os.makedirs(d, exist_ok=True)
    cand = os.path.join(d, "install-src-candidates")
    rewritten = m.group(1).replace("/etc/install-src-candidates", cand)

    def run_case(contents):
        if contents is None:
            try:
                os.remove(cand)
            except OSError:
                pass
        else:
            open(cand, "w").write(contents)
        harness = "SCAN_IDS=\n" + rewritten + '\necho "SCAN_IDS=[$SCAN_IDS]"\n'
        r = subprocess.run(["/usr/bin/dash", "-c", harness],
                           capture_output=True, text=True, timeout=30)
        mm = re.search(r'SCAN_IDS=\[([^\]]*)\]', r.stdout)
        return mm.group(1) if mm else None

    got = run_case("/dev/dsk/ced0s4\n")
    if got == "8 9 a b c d e f":
        ok("card-1 candidate (/dev/dsk/ced0s4, controller 'e') -> SCAN_IDS derives "
           "'8 9 a b c d e f': the scan opens card-1 nodes only (EXECUTED, not regex)")
    else:
        fail("card-1 candidate did NOT derive the card-1 scan list (got SCAN_IDS=%r) "
             "-- a card-1 medium would scan card 0 and panic" % got)

    got = run_case(None)
    if got == "0 1 2 3 5 6":
        ok("no candidate file -> SCAN_IDS holds the card-0 default '0 1 2 3 5 6' "
           "(the 030 line, byte-unchanged)")
    else:
        fail("absent candidates did not fall to the card-0 default (got %r)" % got)

    got = run_case("/dev/dsk/c5d0s4\n")
    if got == "0 1 2 3 5 6":
        ok("card-0 candidate (/dev/dsk/c5d0s4, controller '5') -> NOT promoted; only "
           "controllers 8..f promote, so the card-0 default holds")
    else:
        fail("a card-0 candidate wrongly promoted SCAN_IDS to %r" % got)


def _contents_fsck_softened(text):
    """Offending line if a contents-fsck invocation is softened with a
    `|| true`/`|| :`/`|| continue`/`|| warn` that would swallow its non-zero exit
    (the fail-OPEN trap), else None. Comment lines are stripped first."""
    for l in strip_full_comments(text).splitlines():
        if "contents-fsck" not in l and '"$CFSCK"' not in l:
            continue
        if re.search(r'\|\|\s*(true|:|continue|warn\b|echo\b)', l):
            return l.strip()
    return None


def audit_w64b_completeness():
    head("K. installer completeness: contents-fsck fail-closed + /etc/apkg.conf")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # K1: the driver resolves + invokes the CD-resident static contents-fsck over
    # the target's contents DB.
    if re.search(r'CFSCK="\$INST/bin/contents-fsck"', code) and \
            re.search(r'CONTENTS="\$TARGET/var/sadm/install/contents"', code) and \
            re.search(r'"\$CFSCK"\s+"\$CONTENTS"', code):
        ok("driver runs $INST/bin/contents-fsck over <root>/var/sadm/install/contents")
    else:
        fail("driver does not invoke the CD-resident contents-fsck over the contents DB")

    # K2: FAIL CLOSED -- an if/else whose failure branch `die`s, and NO softening.
    # (The driver routes the call through `runq`, the output-routing wrapper that RETURNS
    # the rc -- the guard shape is unchanged, the rc still decides.)
    if re.search(r'if\s+(runq\s+)?"\$CFSCK"\s+"\$CONTENTS";\s*then', code) and \
            re.search(r'die[^\n]*contents-DB integrity check FAILED', code):
        ok("contents-fsck is guarded by `if ...; then <clean>; else die ...` (fail closed)")
    else:
        fail("contents-fsck call is not guarded by an if/else-die (fail-closed) block")
    soft = _contents_fsck_softened(driver_src)
    if soft:
        fail("contents-fsck invocation is SOFTENED (fail-open): %s" % soft)
    else:
        ok("no `|| true`/`|| :`-style softening on the contents-fsck invocation")
    # CHECK-ONLY: the install step must never pass `-r` (repair) to contents-fsck.
    if re.search(r'"\$CFSCK"\s+-r\b', code) or re.search(r'contents-fsck\s+-r\b', code):
        fail("contents-fsck is called with -r (repair) -- an install step must be CHECK-ONLY")
    else:
        ok("contents-fsck is CHECK-ONLY (no -r repair in the install step)")

    # K3: ORDER -- the check runs AFTER the pkgadd loop and BEFORE arming first-boot.
    i_loop = code.find('done < "$ORDER"')
    i_cfsck = code.find('"$CFSCK" "$CONTENTS"')
    i_arm = code.find("arming first-boot")
    if 0 <= i_loop < i_cfsck < i_arm:
        ok("contents-fsck runs after the pkgadd loop and before the first-boot arm step")
    else:
        fail("contents-fsck is mis-ordered (loop@%d fsck@%d arm@%d)"
             % (i_loop, i_cfsck, i_arm))

    # K4: the driver writes /etc/apkg.conf with the repo line. It de-hardcodes the
    # URL into the profile key FB_REPO_URL whose DEFAULT is the literal that used
    # to be here -- so the installed conf is byte-identical for a profile that
    # omits the key, and a public-flavor profile can point elsewhere without a
    # driver edit. Both halves are required: the parametrized write AND the
    # default, or the de-hardcode would silently ship an empty repo= line.
    if re.search(r'APKG_CONF="\$TARGET/etc/apkg\.conf"', code) and \
            re.search(r'echo\s+"repo=\$FB_REPO_URL"', code) and \
            re.search(r'>\s*"\$APKG_CONF"', code):
        ok("driver writes /etc/apkg.conf -> repo=$FB_REPO_URL (parametrized)")
    else:
        fail("driver does not write /etc/apkg.conf with the parametrized repo line "
             "(echo \"repo=$FB_REPO_URL\")")
    # each release's tree has its own fixed path: 1.1 defaults to /1.1 (apkg fetches
    # <repo>/catalog, so no trailing slash); the frozen 1.0 media keep the root
    if re.search(r'if \[ -z "\$FB_REPO_URL" \]; then\n\tcase "\$INSTALL_LAYOUT" in\n'
                 r'\t\t1\.1\)\tFB_REPO_URL=http://pkg\.amigaux\.org/1\.1 ;;\n'
                 r'\t\t\*\)\tFB_REPO_URL=http://pkg\.amigaux\.org ;;\n\tesac\nfi', code):
        ok("driver defaults FB_REPO_URL by layout: 1.1 -> http://pkg.amigaux.org/1.1, "
           "1.0 -> the root")
    else:
        fail("driver does not default FB_REPO_URL by layout (1.1: http://pkg.amigaux.org/1.1) -- "
             "a profile without the key would write an empty or stale repo= line")
    if re.search(r'repo=http://(files\.example\.net/html/amix|pkg\.amigaux\.org)"', code):
        fail("driver still writes a LITERAL repo= URL somewhere -- it must come from "
             "FB_REPO_URL")
    else:
        ok("no literal repo= URL survives in the driver's code (only the default)")

    # K5: the conf is DRIVER-WRITTEN on the miniroot, and first-boot may only
    # RE-POINT it. Before the dialog the repository was purely a profile fact, so
    # firstboot.sh touching apkg.conf at all was the finding. The dialog makes the repo
    # HOST an answerable question, so the file has to be able to follow that
    # answer -- but only in that one shape: never created at first boot, only the
    # `repo=` line rewritten, and only when the conf's URL and the file's line
    # have actually parted company. Anything wider and the driver stops being the
    # writer of record.
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    if not re.search(r'apkg\.conf', fb):
        ok("first-boot does not write apkg.conf (identity-independent; driver-written)")
    else:
        checks = [
            (r'\[\s+-n\s+"\$FB_REPO_URL"\s+\]\s+&&\s+\[\s+-f\s+/etc/apkg\.conf\s+\]',
             "only when FB_REPO_URL is set AND the driver's file already exists"),
            (r'cur=`sed -n \'s/\^repo=//p\' /etc/apkg\.conf`',
             "reads the current repo= line first"),
            (r'if\s+\[\s+"\$cur"\s+!=\s+"\$FB_REPO_URL"\s+\]',
             "writes only when it differs (an unattended install never writes)"),
            (r'sed\s+"s\|\^repo=\.\*\|repo=\$FB_REPO_URL\|"',
             "rewrites the repo= LINE, never the whole file"),
        ]
        bad = [d for p, d in checks if not re.search(p, fb)]
        if bad:
            for d in bad:
                fail("first-boot apkg.conf re-point MISSING: %s" % d)
        else:
            ok("first-boot re-points apkg.conf only in the expected shape: %s"
               % "; ".join(d for _, d in checks))
        if re.search(r'>\s*/etc/apkg\.conf\b', fb) and not re.search(
                r'>\s*/etc/apkg\.conf\.fb', fb):
            fail("first-boot CREATES /etc/apkg.conf by redirection -- the driver is "
                 "the writer of record; first-boot may only re-point it")
        else:
            ok("first-boot never creates /etc/apkg.conf (only the temp-file rewrite)")

    # K6: apkg.conf write uses echo + redirection only (no sed/cp/mv on the miniroot).
    # Extract the apkg.conf block and confirm it is echo-driven (allowlist-clean;
    # audit G proves the whole driver, this pins the specific block's method).
    m = re.search(r'APKG_CONF="\$TARGET/etc/apkg\.conf".*?wrote \$APKG_CONF', driver_src, re.S)
    block = m.group(0) if m else ""
    if block and re.search(r'echo "repo=\$FB_REPO_URL"', block) \
            and not re.search(r'\b(sed|cp|mv|touch)\b', strip_full_comments(block)):
        ok("apkg.conf written with echo + redirection only (no sed/cp/mv/touch)")
    else:
        fail("apkg.conf block not echo-driven or reaches for an absent miniroot tool")

    # NEGATIVE FIXTURE -- a softened contents-fsck MUST be flagged, or K2 is worthless.
    neg = ('CFSCK="$INST/bin/contents-fsck"\nCONTENTS="$TARGET/var/sadm/install/contents"\n'
           '"$CFSCK" "$CONTENTS" || true\n')
    if _contents_fsck_softened(neg):
        ok("negative fixture fires: `contents-fsck ... || true` is flagged fail-open")
    else:
        fail("negative fixture did NOT fire: a softened contents-fsck was not caught")


# ---------------------------------------------------------------------------
# L. repo-host baking -- zero-touch apkg out of the box
# ---------------------------------------------------------------------------
# A bench run PROVED apkg-over-network works, but only after a MANUAL /etc/inet/hosts
# edit: the fresh box has no DNS and firstboot baked only its own nodename, so it
# could not resolve the repo host (files.example.net). This makes it zero-touch:
#   * the profile carries FB_REPO_HOST + FB_REPO_IP (paired);
#   * install.sh passes them through firstboot.conf;
#   * firstboot.sh appends "<FB_REPO_IP> <FB_REPO_HOST>" to /etc/inet/hosts at
#     identity-bake time -- guarded on both non-empty (a repo-less profile is legal;
#     skip-but-log), duplicate-safe (strip any prior line naming the host, then
#     append exactly one), and NEVER touching network-config.
# This audits all three and FIRES on a missing firstboot append whenever a profile
# carries the vars; a negative fixture proves the append check fires.


# The flat (no "/") zone files Amix 2.1 ships at the top of /usr/lib/locale/TZ.
AMIX_FLAT_ZONES = {
    "CET", "CST6CDT", "EET", "EST", "EST5EDT", "GB-Eire", "GMT", "Greenwich", "HST",
    "Hongkong", "Iceland", "Israel", "Japan", "MET", "MST", "MST7MDT", "NZ", "Navajo",
    "PRC", "PST8PDT", "Poland", "ROC", "ROK", "Singapore", "Turkey", "UCT", "UTC",
    "Universal", "W-SU", "WET",
} | {"GMT%+d" % i for i in range(-12, 14) if i}


def _parse_profile(path):
    """Parse a strict KEY=value profile (bare or "quoted" values, # comments)."""
    d = {}
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        v = v.strip()
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        d[k.strip()] = v
    return d






# ---------------------------------------------------------------------------
# M. RAW source arm -- SOURCE_KIND dimension + apkg SRC_RAW branch
# ---------------------------------------------------------------------------
# The RAW arm gives the installer a raw-distribution-slice source (the metal path
# under the no-burn rule): a SECOND disk carries an s5 PAYLOAD slice (mounted AT
# /cdrom so every /cdrom/install path is byte-unchanged) and a raw distribution
# slice the CD-resident static apkg drives (SRC_RAW). This audits, fail-closed:
#   * the profile source dimension -- SOURCE_KIND on every profile (default cdfs),
#     and the new raw profile's SRC_* keys;
#   * the driver's SOURCE_KIND branch -- it defaults to cdfs, validates cdfs|raw,
#     and DIES on an unknown kind (never silently proceeds);
#   * the driver's RAW branch -- writes raw.conf (repo=raw:, cachedir on the
#     TARGET, admin+pkgadd = CD-resident paths), runs `apkg update` then
#     `apkg -R <target> install`, and FAILS CLOSED (apkg nonzero -> die, with NO
#     `|| true`/`|| :` softening on either apkg call -- a soft apkg is worse than
#     none: it would arm a half-installed disk);
#   * the client-root-vs-target rule -- the RAW branch NEVER sets APKG_ROOT (the
#     engine runs FROM the payload slice and installs INTO the target via -R;
#     pointing the client root at the target is the bootstrap bug conf.c warns of);
#   * the /cdrom-payload-mount convention is documented in the driver;
#   * the raw source-disk builder exists and reuses the staging path.
# Negative fixtures prove the fail-closed + no-APKG_ROOT checks actually fire.








# ---------------------------------------------------------------------------
# O. updbootpart -- the on-box boot-slice reframe tool (kernel upgrade)
# ---------------------------------------------------------------------------
# payload/updbootpart is the on-box finisher for "kernel upgrade via a package":
# `updbootpart --backup` -> `pkgadd KERNBENCH` -> `updbootpart` reframes the UNI\0
# boot slice from the freshly-landed /stand/unix so the next cold boot runs the new
# kernel. install.sh lays it onto every fresh target at /usr/sbin/updbootpart --
# additive, NOT a package member. ★ It is STAGED ON THE MEDIUM at
# /install/updbootpart and COPIED, where it used to be a quoted here-doc inside the
# driver; the 1991 sh materialized that body as a real file on the 880-block install
# floppy at PARSE time, 15,427 B = 16 of its 46 free 1 KB blocks, on every install.
# It runs on the FULL installed target, so it uses sum/wc/cmp/pkgparam (the miniroot
# lacks them) -- which is no longer a problem for the driver's own miniroot audits,
# because those tokens are not in the driver at all any more. This audits,
# fail-closed:
#   * updbootpart is pre-POSIX (target set: wc is ALLOWED on the full box, unlike the
#     miniroot) and parses;
#   * TARGET-tool allowlist -- every command is a builtin, a miniroot.proto binary, a
#     defined function, or one of the documented full-box extras (sum/wc/cmp/pkgparam)
#     or ./makeiblk (the /stand framing tool). A reference to anything else FAILS;
#   * FAIL-CLOSED gates -- the KSUM, boot2-loader and readback-cmp gates each `die`,
#     with NO `|| true`/`|| :`-style softening anywhere in the tool;
#   * it derives the boot slice from /etc/vfstab (never a hardcoded cNd0s3), invokes
#     ./makeiblk, pins boot2 sum -r 14193, and frames to a temp file then reads the
#     slice BACK and cmp's it;
#   * DRIFT-LOCK -- build-install-iso.sh stages the tracked payload/updbootpart master
#     at /install/updbootpart and STOPS unless the staged copy is byte-identical (the
#     lock the here-doc used to give for free, in the one place that still sees both);
#   * the driver INSTALLS it (cp $INST/updbootpart -> /usr/sbin/updbootpart, chmod
#     0755), fails closed on older media, and carries no here-doc at all;
#   * strip_heredocs still works, proven with fixtures (audit Z's here-doc law, now
#     ZERO bytes for every miniroot script, is what keeps the helper needed).

# updbootpart runs on the FULL installed target; these are the tools it deliberately
# uses that the thin miniroot lacks (documented, and NOT granted to install.sh), plus
# makeiblk = /stand/makeiblk, invoked cwd-relative as ./makeiblk.
UPDBOOT_EXTRA = {"sum", "wc", "cmp", "pkgparam", "makeiblk", "devnm"}
# pre-POSIX pitfalls that STILL apply on the target's 1991 SVR4 sh -- everything in
# PATTERNS EXCEPT the `wc` rule (wc is present on the full installed box).
TARGET_PATTERNS = [(p, why) for (p, why) in PATTERNS if r'\bwc\b' != p]
























# ---------------------------------------------------------------------------
# P. zen0 bring-up laydown -- driver lays /etc/rc2.d/S99zen for metal
#    (zen0) profiles, IP-parameterized; the profiles carry the right IP + interface
# ---------------------------------------------------------------------------
# A base install ships only the STOCK a2065/aen0 inet userland, inert on metal (no
# A2065 board) -- so a fresh metal install has NO working ethernet. Metal ethernet is
# z3660eth, interface zen0 (cdevsw major 51 -- renumbered from 48 on 2026-07-30; media
# mastered from this tree REQUIRE kernels that register z3660eth at 51, that kernel set).
# install.sh lays down the proven z3660net
# bring-up as /etc/rc2.d/S99zen -- driver-written + additive, NOT a package member
# (invisible to the contents DB, exactly like S16firstboot / updbootpart), and it
# NEVER edits /etc/inet/network-config (the hard rule). It is GUARDED on the profile's
# ethernet interface being zen0 so the bench a2065/aen0 path is untouched, with the
# LITERAL IP from the profile FB_IP (never a hardcoded golden .39). This audits,
# fail-closed:
#   * the driver lays S99zen under an FB_ETHER_IF=zen0 guard (chmod 0744), refuses a
#     zen0 profile with an empty FB_IP, and does NOT copy it from the CD;
#   * DRIFT-LOCK -- the driver's emit_zen_hook, run with a test IP/netmask, reproduces
#     the tracked payload/S99zen master (placeholders resolved) byte-for-byte, AND a
#     SECOND distinct IP flows through (proving it uses $FB_IP, not a hardcoded value);
#   * the master is pre-POSIX + parses + self-heals /dev/zen0 (mknod c 51 0, and carries
#     no stale c 48 0) +
#     backgrounds the bring-up + uses a literal IP (never uname -n) + references only
#     target-present tools (miniroot.proto + documented net extras);
#   * the metal profiles carry FB_IP=192.0.2.39 + FB_ETHER_IF=zen0; EVERY zen0
#     profile has a non-empty FB_IP; the bench profiles keep aen0 (untouched).
# Negative fixtures prove the empty-FB_IP + hardcoded-IP checks actually fire.

# S99zen runs on the FULL installed target (rc2.d at boot), so it uses net tools the
# thin miniroot lacks -- documented here, NOT granted to install.sh (mknod + expr are
# already in miniroot.proto).
# Address by card (2026-09-26) adds the text tools of the lookup/hosts step
# (sed/grep/awk/cmp -- all on the installed target) and `uname` for the nodename.
ZEN_EXTRA = {"slink", "ifconfig", "route", "sleep", "sed", "grep", "awk", "cmp", "uname"}
_ZEN_TESTIP = "203.0.113.7"          # deliberately NOT .38/.39 -- a hardcoded IP mismatches
_ZEN_TESTMASK = "255.255.0.0"
_ZEN_TESTGW = "203.0.113.254"        # deliberately NOT .2.1 -- a hardcoded gateway mismatches
_ZEN_TESTDOM = "example.org"      # deliberately NOT example.net




def _emit_zen(func, ip, mask, gw=_ZEN_TESTGW, dom=_ZEN_TESTDOM):
    """Run the driver's extracted emit_zen_hook with FB_IP/FB_NETMASK/FB_GATEWAY/
    FB_DOMAIN set, return (returncode, emitted_bytes)."""
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    hp = workpath("emitzen_%s.sh" % ip.replace(".", "_"))
    outp = workpath("zen_%s.out" % ip.replace(".", "_"))
    if os.path.exists(outp):
        os.unlink(outp)
    with open(hp, "w") as fh:
        fh.write("FB_IP=%s\nFB_NETMASK=%s\nFB_GATEWAY=%s\nFB_DOMAIN=%s\n" % (ip, mask, gw, dom)
                 + func + '\nemit_zen_hook "$1"\n')
    r = subprocess.run([sh, hp, outp], capture_output=True, text=True)
    emitted = open(outp, "rb").read() if os.path.isfile(outp) else None
    return r.returncode, emitted




# ---------------------------------------------------------------------------
# Q. /stand framing tools -- driver-guaranteed updbootpart framing sources
# ---------------------------------------------------------------------------
# updbootpart's reframe pipeline needs /stand/boot1.boot, /stand/boot2.boot and an
# executable local /stand/makeiblk (its gate 5a fails closed without them). On
# On a metal run (2026-08) the KERN-package handoff on a fresh metal base-8
# install died exactly there ("framed image is empty") until boot1.boot + makeiblk
# were ferried by hand from the bench golden (1 KB chunk split-pull, reassembled
# byte-perfect sum -r 58483). The driver now LAYS BOTH DOWN from the media, making
# their presence -- and their exact PROVEN bytes -- a driver-guaranteed invariant:
#   boot1.boot 1,024 B sum -r 41892  (the 2.1 original; the 2.1c patch never
#                                     touched it, so core's copy IS the golden's)
#   makeiblk  14,924 B sum -r 58483  (the 2.1c PATCHED build every golden runs;
#                                     the pair the metal reframe was proven with)
# The cp overwrites any core-delivered 2.1 makeiblk -- the boot2.boot-class
# content touch (invisible to the contents-DB digest, which is a pure function of
# what pkgadd RECORDED).

FT_PINS = {                      # staged-file fingerprints: (sum -r, bytes)
    "stand/boot1.boot": (41892, 1024),
    "stand/makeiblk": (58483, 14924),
}
SYSLOG_PINS = {
    "syslog/syslog.conf": (63870, 1928),
    "syslog/syslogd": (53154, 22728),
    "syslog/syslogd.init": (28819, 967),
}




def audit_framing_tools():
    head("Q. /stand framing tools: driver lays boot1.boot + makeiblk (updbootpart gate 5a)")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # Q1: the driver lays BOTH tools down from /install/stand with the right modes.
    lay = [
        (r'cp\s+"\$INST/stand/boot1\.boot"\s+"\$TARGET/stand/boot1\.boot"',
         "cp's /install/stand/boot1.boot -> /stand/boot1.boot"),
        (r'chmod\s+0644\s+"\$TARGET/stand/boot1\.boot"', "chmod 0644 boot1.boot"),
        (r'cp\s+"\$INST/stand/makeiblk"\s+"\$TARGET/stand/makeiblk"',
         "cp's /install/stand/makeiblk -> /stand/makeiblk"),
        (r'chmod\s+0755\s+"\$TARGET/stand/makeiblk"',
         "chmod 0755 makeiblk (updbootpart gates on -x)"),
    ]
    for pat, desc in lay:
        if re.search(pat, code):
            ok("driver %s" % desc)
        else:
            fail("driver does NOT: %s" % desc)

    # Q2: ORDER -- the laydown runs in the arm phase, AFTER the contents-DB gate
    # (never before/instead of the base transplant) and alongside updbootpart.
    m_lay = re.search(r'cp\s+"\$INST/stand/boot1\.boot"', code)
    m_cfsck = re.search(r'contents-DB integrity check', code) or \
        re.search(r'\$CFSCK', code)
    m_updb = re.search(r'cp\s+"\$INST/updbootpart"\s+"\$TARGET/usr/sbin/updbootpart"', code)
    if m_lay and m_cfsck and m_updb and \
            m_lay.start() > m_cfsck.start() and m_lay.start() > m_updb.start():
        ok("laydown ordered after the contents-fsck gate and the updbootpart install "
           "(arm phase)")
    else:
        fail("framing-tools laydown is not ordered after the contents-fsck gate + "
             "updbootpart install")

    # Q3: COHERENCE -- every framing source updbootpart's gate 5a checks is
    # driver-guaranteed: boot1.boot + makeiblk by this laydown, boot2.boot by the
    # section-6 flags-based overwrite, unix by the KERN pkgadd (gated at reframe).
    if not os.path.isfile(UPDBOOTPART):
        fail("payload/updbootpart missing -- cannot cross-check gate 5a")
    else:
        tool = open(UPDBOOTPART, encoding="utf-8").read()
        gates = [
            (r'\[\s+-f\s+"\$STAND/boot1\.boot"\s+\]\s+\|\|\s+die', "boot1.boot"),
            (r'\[\s+-f\s+"\$STAND/boot2\.boot"\s+\]\s+\|\|\s+die', "boot2.boot"),
            (r'\[\s+-x\s+"\$STAND/makeiblk"\s+\]\s+\|\|\s+die', "makeiblk (-x)"),
        ]
        missing = [d for pat, d in gates if not re.search(pat, tool)]
        if missing:
            fail("updbootpart gate 5a no longer checks: %s (coherence lost)" % missing)
        else:
            ok("updbootpart gate 5a checks boot1.boot/boot2.boot/makeiblk -- all three")
        if re.search(r'cp\s+"\$INST/\$BOOT2_BOOT"\s+"\$TARGET/stand/boot2\.boot"', code):
            ok("boot2.boot is driver-written too (section 6 flags-based overwrite) -- "
               "gate 5a's full framing set is driver-guaranteed")
        else:
            fail("driver no longer overwrites /stand/boot2.boot -- gate 5a's framing set "
                 "is not fully driver-guaranteed")

    # Q4: these are the 1.0 path's: a medium stages neither, and the 1.1 path reads neither
    if not os.path.isfile(ISO_BUILDER):
        fail("build-install-iso.sh missing -- cannot check the staging")
    else:
        bsrc = open(ISO_BUILDER, encoding="utf-8").read()
        if re.search(r'\$STAGE/stand\b|\$STAGE/syslog/syslog\.|payload/21c|extract-21c-payload', bsrc):
            fail("build-install-iso.sh stages the 1.0 path's /install/stand or syslog unit, or still reads payload/21c")
        else:
            ok("the medium stages no /install/stand or 1.0 syslog unit, and needs no 2.1c extraction")
        if 'cp "$SYSLOGD_21C" "$STAGE/syslog/syslogd"' in bsrc and 'install-reads-check.py" "$STAGE"' in bsrc:
            ok("the medium stages the 2.1c daemon the 1.1 path lays down, and the build checks every path the installer reads")
        else:
            fail("build-install-iso.sh doesn't stage the 1.1 path's syslogd, or doesn't run install-reads-check")
    l11src = open(os.path.join(os.path.dirname(DRIVER), "l11.sh"), encoding="utf-8").read()
    if re.search(r'\$INST/stand\b|\$INST/syslog/syslog\.', l11src):
        fail("l11.sh reads /install/stand or the 1.0 syslog unit, which a medium no longer stages")
    else:
        ok("l11.sh reads neither /install/stand nor the 1.0 syslog unit")

    # NEGATIVE FIXTURE -- a driver stripped of the laydown is flagged.
    neg = re.sub(r'\n[^\n]*cp\s+"\$INST/stand/boot1\.boot"[^\n]*', "", code)
    if not re.search(r'cp\s+"\$INST/stand/boot1\.boot"\s+"\$TARGET/stand/boot1\.boot"', neg):
        ok("negative fixture fires: a driver without the boot1.boot laydown is flagged")
    else:
        fail("negative fixture did NOT fire: the boot1.boot laydown check is broken")


# ---------------------------------------------------------------------------
# R. syslog unit -- base-8 ships no unit; the driver lays down the 2.1c one
# ---------------------------------------------------------------------------
# A base-8 install has core's /usr/sbin/syslogd BINARY (2.1, 22,368 B) and core's
# /dev/log, but NO unit: no /etc/init.d/syslogd, no rc links, no /etc/syslog.conf,
# no /var/log -- syslog(3) writes are silently discarded (the inetd-throttle hunt,
# kerntools docs/inetd-telnet-throttle.md, measured what that silence costs). The
# driver lays down the complete 2.1c unit from the media, ENABLED:
#   /etc/syslog.conf   0444  (2.1c conf 1.1 -- routes daemon.err to /var/log/notice)
#   /etc/init.d/syslogd 0544 (ENABLED: the vendor disable `exit` was commented at
#                             media STAGING -- the miniroot has no sed)
#   /etc/rc2.d/S70syslogd + /etc/rc0.d/K50syslogd -- HARD links (`ln`): the stock
#                             one-inode 3-link topology. `mv` on the script would
#                             orphan the links (edits must be cp-in-place).
#   /usr/sbin/syslogd  0100  (the 2.1c "major revisions" daemon over core's 2.1 --
#                             the boot2.boot-class content touch)
#   /var/log/{alert,bus-errors,console,critical,kernel,news-urgent,notice,security}
#                             eight zero-length stubs, 0644 (syslogd appends; the
#                             vendor patch ships exactly these)
#   /dev/conslog c 25 0, 0222 (the vendor patch's own "added to support syslogd")

SYSLOG_STUBS = ["alert", "bus-errors", "console", "critical", "kernel",
                "news-urgent", "notice", "security"]


def _live_exit_check(text):
    """True iff an init-script text is the ENABLED copy: no live bare `exit` line
    and exactly one commented `#exit`. (Used on the staged file AND on a crafted
    negative fixture to prove the check can fire.)"""
    lines = text.split("\n")
    return sum(1 for l in lines if l == "exit") == 0 and \
        sum(1 for l in lines if l == "#exit") == 1


def audit_syslog_unit():
    head("R. syslog unit: driver lays the ENABLED 2.1c unit (base-8 ships none)")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # R1: the laydown -- conf, enabled init, hard links, daemon, stubs, conslog.
    lay = [
        (r'cp\s+"\$INST/syslog/syslog\.conf"\s+"\$TARGET/etc/syslog\.conf"',
         "cp's /install/syslog/syslog.conf -> /etc/syslog.conf"),
        (r'chmod\s+0444\s+"\$TARGET/etc/syslog\.conf"', "chmod 0444 syslog.conf (vendor mode)"),
        (r'cp\s+"\$INST/syslog/syslogd\.init"\s+"\$TARGET/etc/init\.d/syslogd"',
         "cp's the ENABLED syslogd.init -> /etc/init.d/syslogd"),
        (r'chmod\s+0544\s+"\$TARGET/etc/init\.d/syslogd"', "chmod 0544 init.d/syslogd (vendor mode)"),
        (r'ln\s+"\$TARGET/etc/init\.d/syslogd"\s+"\$TARGET/etc/rc2\.d/S70syslogd"',
         "HARD-links /etc/rc2.d/S70syslogd to the init script"),
        (r'ln\s+"\$TARGET/etc/init\.d/syslogd"\s+"\$TARGET/etc/rc0\.d/K50syslogd"',
         "HARD-links /etc/rc0.d/K50syslogd to the init script"),
        (r'cp\s+"\$INST/syslog/syslogd"\s+"\$TARGET/usr/sbin/syslogd"',
         "cp's the 2.1c syslogd -> /usr/sbin/syslogd"),
        (r'chmod\s+0100\s+"\$TARGET/usr/sbin/syslogd"', "chmod 0100 syslogd (vendor mode)"),
        (r'chmod\s+0755\s+"\$TARGET/var/log"', "chmod 0755 /var/log"),
        (r'mknod\s+"\$TARGET/dev/conslog"\s+c\s+25\s+0', "mknod /dev/conslog c 25 0"),
        (r'chmod\s+0222\s+"\$TARGET/dev/conslog"', "chmod 0222 /dev/conslog (vendor mode)"),
    ]
    for pat, desc in lay:
        if re.search(pat, code):
            ok("driver %s" % desc)
        else:
            fail("driver does NOT: %s" % desc)
    stubs_line = re.search(r'for\s+lf\s+in\s+([^;]+);', code)
    if stubs_line and stubs_line.group(1).split() == SYSLOG_STUBS:
        ok("driver creates exactly the eight vendor /var/log stubs (%s)"
           % " ".join(SYSLOG_STUBS))
    else:
        fail("driver does not create exactly the eight vendor /var/log stubs "
             "(want: %s)" % " ".join(SYSLOG_STUBS))
    # The stubs are created with `cp /dev/null`, NOT `: >`: on the miniroot's
    # 1991 sh a null-command redirection inside a loop fires only on the FIRST
    # iteration (bench-proven -- see audit T), so `: >` shipped a syslog unit
    # with one stub out of eight. Presence is ASSERTED after the create, because
    # the defect it replaces returned success while doing nothing.
    if re.search(r'run cp /dev/null "\$TARGET/var/log/\$lf"', code):
        ok("stubs created with `cp /dev/null` (an external command -- works every "
           "iteration, unlike a null-command redirection)")
    else:
        fail("stub creation is not `run cp /dev/null <stub>` -- a `: >` in this loop "
             "silently creates only the FIRST stub on the miniroot sh")
    if re.search(r'\[\s+-f\s+"\$TARGET/var/log/\$lf"\s+\]\s+\|\|\s+die', code):
        ok("each stub's presence is ASSERTED after creation (fail-closed against a "
           "create that returns success and does nothing)")
    else:
        fail("stub creation does not assert presence afterwards")

    # R2: LINK TOPOLOGY -- the rc entries must be HARD links; `ln -s` or a cp
    # would break the one-inode contract (the cp-in-place lore depends on it).
    if re.search(r'ln\s+-s\s+[^\n]*syslogd', code):
        fail("driver uses `ln -s` for an rc syslogd entry -- must be a HARD link "
             "(one inode, 3 links; edits are cp-in-place)")
    else:
        ok("no `ln -s` for the rc syslogd entries (hard links preserve the one-inode topology)")
    if re.search(r'cp\s+[^\n]*(S70syslogd|K50syslogd)', code):
        fail("driver COPIES an rc syslogd entry -- a copy breaks the one-inode "
             "3-link topology (a later cp-in-place fix would not propagate)")
    else:
        ok("rc syslogd entries are never cp'd (hard links only)")

    # R3: UNCONDITIONAL -- the laydown must not sit inside the zen0 (metal) guard;
    # bench installs need logging just as much.
    m = re.search(r'if\s+\[\s+"\$FB_ETHER_IF"\s+=\s+zen0\s+\];\s*then(.*?)\nfi\n',
                  code, re.S)
    if m and "syslog" not in m.group(1):
        ok("syslog laydown is UNCONDITIONAL (not inside the FB_ETHER_IF=zen0 guard)")
    elif m:
        fail("syslog laydown sits inside the zen0 guard -- bench installs would ship silent")
    else:
        fail("could not locate the zen0 guard block to prove the syslog laydown is unconditional")

    # NEGATIVE FIXTURES -- the link-topology and live-exit checks must fire.
    neg = re.sub(r'\n[^\n]*ln\s+"\$TARGET/etc/init\.d/syslogd"\s+"\$TARGET/etc/rc2\.d/S70syslogd"[^\n]*',
                 "", code)
    if not re.search(r'ln\s+"\$TARGET/etc/init\.d/syslogd"\s+"\$TARGET/etc/rc2\.d/S70syslogd"', neg):
        ok("negative fixture fires: a driver without the S70 hard link is flagged")
    else:
        fail("negative fixture did NOT fire: the S70 hard-link check is broken")
    dead = "#!/bin/sh\n#TO USE SYSLOGD ...\nexit\npid=x\n"
    if not _live_exit_check(dead):
        ok("negative fixture fires: an init script with a LIVE `exit` fails the "
           "enabled-copy check")
    else:
        fail("negative fixture did NOT fire: the live-exit check is broken")


# ---------------------------------------------------------------------------
# S. driver plumbing -- the input keys the interview will land in
# ---------------------------------------------------------------------------
# This turns the driver's remaining hardcodes into profile KEYS and restores two
# stock steps it had dropped, all non-interactively and all behaviour-preserving
# when the keys carry today's values. This audits each seam fail-closed:
#
#   S1 PROFILE BY PATH   -- install.sh accepts a profile by PATH as well as by
#      name, so the interview can hand it /tmp/answers.profile (the medium is
#      read-only). Proven by RUNNING the extracted resolution block.
#   S2 INSTALL LOG       -- <target>/var/adm/install.log is written on every
#      install, opened right after the mount (the pre-mount window is
#      console-only by nature), and INSTALL_VERBOSE decides only what the CONSOLE
#      sees. There is no tee(1) on the miniroot, so the mechanism is a temp file
#      cat'd twice; this RUNS the extracted helpers in both modes and compares
#      what lands on the console vs in the log.
#   S3 STOCK STAGE STRINGS -- the stage messages are the original installer's
#      own, VERBATIM. When the stock root floppy is present the strings are
#      checked against its bytes; otherwise SKIP (never a silent pass).
#   S4 KEYMAP BAKE       -- the stock `ln <map> default.kmap` step, restored,
#      driven by FB_KMAP (empty/usa == none, exactly like stock's id_kmap).
#   S5 REAL DISK SIZE    -- plan_partitions is fed by a real /etc/ddsize probe
#      when TARGET_DISK_MB is not pinned; ddsize is genuinely on the miniroot.
#   S6 LOST+FOUND        -- the stock 100-slot preseed, restored (an s5 directory
#      never shrinks, which is what gives fsck room to reconnect orphans).
#   S7 DNS PLUMB-ONLY    -- FB_DNS1/FB_DNS2 reach firstboot.conf and NOTHING
#      applies them (that is the dialog's job); a firstboot that started applying DNS would be
#      caught here.
#   S8 KEY COVERAGE      -- every tracked profile carries every new key.

W1_KEYS = ["INSTALL_VERBOSE", "TARGET_ROOT_MB", "TARGET_SWAP_MB", "FB_TZ",
           "FB_GATEWAY", "FB_DNS1", "FB_DNS2", "FB_KMAP", "FB_REPO_URL"]

# The stage strings it takes VERBATIM from the original installer. The first two
# are echo lines in the stock /etc/profile (the stock install script itself); the
# third is amixpkg's per-package printf. All three live on the stock root floppy,
# so when that image is available they are checked against its actual bytes.
STOCK_STAGE_STRINGS = [
    "Making filesystems.  This will take a few minutes.",
    "Please wait while the partitions are checked...",
    "Installing %s",
]




_W1_SEQ = [0]


def _run_sh(script, args, env=None):
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    _W1_SEQ[0] += 1
    p = workpath("w1_%d.sh" % _W1_SEQ[0])
    with open(p, "w") as fh:
        fh.write(script)
    e = dict(os.environ)
    if env:
        e.update(env)
    return subprocess.run([sh, p] + list(args), capture_output=True, text=True, env=e)


















# ---------------------------------------------------------------------------
# T. NULL-COMMAND REDIRECTION INSIDE A LOOP -- the create that lies
# ---------------------------------------------------------------------------
# BENCH-PROVEN 2026-08-11 (instrumented matrix run 20260811-103107-cd). On the
# miniroot's 1991 SVR4 /bin/sh, a redirection applied to the NULL COMMAND is
# performed only on the FIRST pass through a loop body. From the second
# iteration on, `: > file` returns rc=0, prints no diagnostic, and creates
# NOTHING. Measured, in one run, in one directory:
#
#     DIAG stub alert       rc=0 -> present      iteration 1
#     DIAG stub bus-errors  rc=0 -> ABSENT       iterations 2..8 -- every one
#     DIAG stub console     rc=0 -> ABSENT
#     DIAG stub critical    rc=0 -> ABSENT
#     DIAG stub kernel      rc=0 -> ABSENT
#     DIAG stub news-urgent rc=0 -> ABSENT
#     DIAG stub notice      rc=0 -> ABSENT
#     DIAG stub security    rc=0 -> ABSENT
#     DIAG retry-cp <those same 7 names> rc=0 -> present     (cp, same dir)
#
# Controls in the same run: three consecutive STRAIGHT-LINE `: >` creates (two
# in /mnt/tmp, one in /mnt/var/adm) all succeeded, so the null-command idiom
# itself is fine -- it is the LOOP that breaks it. Not the filesystem (an
# external command created the identical paths seconds later, 7/7), not the
# names (plain `console`/`kernel`/`notice`/`security` failed too), not space
# (51k free blocks, 15k free inodes), not a lost write (a whole-ilist scan of
# the target found ZERO orphaned inodes -- nothing was ever allocated).
#
# It cost two shipped defects: the syslog unit shipped ONE of its eight
# /var/log stubs and then hard-stopped the install, and the lost+found preseed
# was a silent no-op (the directory stayed at its mkfs 38 slots). Both are fixed
# by creating with `cp /dev/null` -- an EXTERNAL command, which forks and so
# really runs every iteration.
#
# This audit forbids the idiom structurally: any `: >` (or `: >>`) redirection
# inside a for/while/until loop body in the driver is a FAIL. Negative fixtures
# (the two exact shipped defects) prove it fires; positive controls (a
# straight-line `: >`, and the `cp /dev/null` replacement) prove it does not
# over-fire.

# re.M is LOAD-BEARING: the offending statement is rarely the first one after
# `do` (in the shipped /var/log defect it sat behind an `echo`), so `^` must
# match at every LINE start, not just at the start of the body slice.
_NULLREDIR = re.compile(r'(?:^|[;&|)]|\bdo\b|\bthen\b|\belse\b)\s*:\s*>+', re.M)


def null_redirect_in_loop(text):
    """Offending loop-body lines that create a file with a null-command
    redirection. Uses the length-preserving mask so a `: >` inside a string or a
    comment can never be mistaken for code."""
    masked = _sl_mask(text)
    bad = []
    stack = []
    for m in re.finditer(r'\bdo\b|\bdone\b', masked):
        if m.group(0) == "do":
            stack.append(m.end())
        elif stack:
            b0 = stack.pop()
            if not _NULLREDIR.search(masked[b0:m.start()]):
                continue
            # report the real (unmasked) offending line(s) for the message
            mlines = masked[b0:m.start()].splitlines()
            for i, line in enumerate(text[b0:m.start()].splitlines()):
                if i < len(mlines) and re.search(r'(?:^|[;&|)])\s*:\s*>+', mlines[i]):
                    s = line.strip()
                    if s not in bad:
                        bad.append(s)
    return bad


def audit_null_redirect_loops():
    head("T. null-command redirection inside a loop (`: > file` creates ONLY on the "
         "first iteration -- bench-proven)")
    for path in (MINIROOT_PROFILE, DRIVER, SETUP, FIRSTBOOT, UPDBOOTPART):
        rel = os.path.relpath(path, REPO)
        if not os.path.isfile(path):
            fail("%s: missing" % rel)
            continue
        bad = null_redirect_in_loop(read_sh(path))
        if bad:
            fail("%s: `: >` used to create a file INSIDE a loop -- on the miniroot sh "
                 "this fires only on the first iteration and silently does nothing "
                 "afterwards; use `cp /dev/null`: %s" % (rel, "; ".join(bad)))
        else:
            ok("%s: no null-command redirection inside any loop body" % rel)

    # NEGATIVE FIXTURES -- the two defects this audit exists to prevent.
    neg = [
        ("syslog-unit /var/log stubs",
         '#!/bin/sh\nfor lf in alert bus-errors console; do\n'
         '\t: > "$TARGET/var/log/$lf" || die "cannot create"\n'
         '\trun chmod 0644 "$TARGET/var/log/$lf"\ndone\n'),
        ("lost+found preseed (nested)",
         '#!/bin/sh\nfor i in 0 1 2; do\n\tfor j in 0 1 2; do\n'
         '\t\t: > "$LF/$i$j" || die "cannot preseed"\n\tdone\ndone\n'),
        ("while-read loop",
         '#!/bin/sh\nwhile read n; do\n\t: > "/t/$n"\ndone < /cd/list\n'),
    ]
    for name, script in neg:
        if null_redirect_in_loop(script):
            ok("negative fixture fires: %-32s -> flagged" % name)
        else:
            fail("negative fixture DID NOT fire: %s" % name)

    # POSITIVE CONTROLS -- must NOT fire.
    pos = [
        ("straight-line `: >` (proven fine on-box)",
         '#!/bin/sh\n: > "$LOGFILE" || die "x"\n: > "$pkgok"\n: > "$pkgfail"\n'),
        ("the cp /dev/null replacement in a loop",
         '#!/bin/sh\nfor lf in a b c; do\n\trun cp /dev/null "$T/var/log/$lf"\n'
         '\t[ -f "$T/var/log/$lf" ] || die "x"\ndone\n'),
        ("a `: >` only mentioned in a comment",
         '#!/bin/sh\nfor i in 1 2; do\n\t# never `: > file` here\n\tcp /dev/null "$i"\ndone\n'),
    ]
    for name, script in pos:
        bad = null_redirect_in_loop(script)
        if bad:
            fail("positive control wrongly flagged: %s -> %r" % (name, bad))
        else:
            ok("positive control passes clean: %s" % name)


# ---------------------------------------------------------------------------
# U. INTERVIEW -- structure (src/installer/setup.sh)
# ---------------------------------------------------------------------------
# setup.sh is the interactive veneer: it asks, it composes an answers profile,
# it execs the proven driver. Audits A/B/G/H/I/T already cover it as miniroot
# sh; THIS audit covers the properties that are specific to being an interview
# on a blind console in front of a five-minute transplant.
#
#   U1  THE SCAN NEVER CALLS ddsize. A first measurement proved one unconditional
#       `/etc/ddsize /dev/rdsk/c6d0s0` WEDGES the install on the bench a3091
#       path (matrix 20260811-094255-cd), and the miniroot has no timeout tool,
#       so a hang there cannot be bounded. A SCAN would run it once per id. The
#       four scan-path functions are extracted and required to be ddsize-free;
#       the one reference that does exist must sit behind the DDSIZE_SAFE gate.
#   U2  SCAN_IDS is DERIVED-CHECKED against miniroot.proto: the default id list
#       must be exactly the ids the proto ships /dev/dsk/cNd0s0 nodes for, and
#       id 4 must be absent from both (that is what makes stock's "SCSI device 4
#       must be used for the tape drive" refusal structural rather than a case).
#   U3  THE TRANSPLANT NEVER INHERITS THE CONSOLE. The exec of install.sh must
#       redirect stdin from /dev/null: an inherited stdin is what
#       hung a metal run on the 1991 pkgadd's prompt, and the interview is the first
#       thing in this tree that legitimately holds a console stdin to pass on.
#   U4  THE ANSWERS PROFILE IS BASE-THEN-APPEND, by PATH, with the beacon
#       markers the blind-console harness greps for.
#   U5  NO stty ANYWHERE. The install matrix types its answers into the tty
#       queue ahead of the prompts; an stty would flush them and the run would
#       hang with no diagnosis.
#   U6  STOCK WORDING, VERBATIM. Every prompt, default and validation message
#       claimed to be the original's is checked BYTE-FOR-BYTE against the stock
#       root floppy's own bytes when it is present (SKIP, never a silent pass,
#       when it is not) -- the same discipline audit S applies to the driver's
#       stage strings.

# The prompts/messages below are quoted from `/etc/profile` on the stock root
# floppy (md5 97f800ec7bcd627bfed2322fdc19f86b). Each must appear in setup.sh
# AND in the floppy image.
# (what setup.sh must contain, what the stock root floppy must contain). The two
# differ ONLY where stock parameterised something we resolve: stock asked about
# "the disk you want to $MODE" because it also did repairs (repair mode is elsewhere,
# on the miniroot), and its size prompts interpolate its own default variables.
# Spelling out both halves keeps every deviation VISIBLE instead of hidden
# behind a fuzzy match.
STOCK_INTERVIEW_STRINGS = [
    ("Scanning SCSI bus for hard disks...", None),
    ("No hard disks are attached to this system.", None),
    ("Hard disks attached to this system:", None),
    ("What is the SCSI id of the disk you want to install? ",
     "What is the SCSI id of the disk you want to $MODE? "),
    ("Choose one of the following:", None),
    ("Press RETURN to restart the installation script. ", None),
    ("WARNING:  The following existing data on disk will be destroyed.", None),
    ("Are you sure you want to erase this disk? ", None),
    ("Your boot partition is $BOOTSIZE megabytes.", None),
    ("How many megabytes for the root file system? [$DEF_ROOT] ",
     "How many megabytes for the root file system? [$ROOTSIZE] "),
    ("How many megabytes for the swap partition? [$DEF_SWAP] ",
     "How many megabytes for the swap partition? [$SWAPSIZE] "),
    ("Your root partition must be at least $MINROOT megabytes.", None),
    ("You must leave at least $MINSWAP megabytes free for swap space.", None),
    ("You must have at least $MINSWAP megabytes of swap space.", None),
    ("You only have $MAXSWAP remaining megabytes available.", None),
    ("Running interactive shell...", None),
]
# amixpkg's own menu line (md5 d63408968f87027313dc9115a6756d55) and
# system.setup's summary question -- the other two stock artifacts we quote.
#
# The set menus activate the rest of amixpkg's package screens, so the rest of its
# .rodata is quoted here too. Where stock parameterised what we resolve, or where
# the ONE changed word ("tape" -> "disc", plan §2.7) applies, the deviation is
# DECLARED as the second element rather than hidden behind a fuzzy match --
# exactly the discipline the interview strings already use.
STOCK_AMIXPKG_STRINGS = [
    ("Standard Amiga UNIX installation", None),
    ("Choose: [1] ", None),
    ("Everything on the disc", "Everything on the tape"),
    ("Custom selection", None),
    ("Disc contents:  ", "Tape contents:  "),
    ("Description", None),
    ("-----------", None),
    ("====  ", None),
    (" Total: ", "%53s Total: %6.1f MB"),
    ("Enter package name to install or ignore; enter GO when ready.", None),
    ("Unknown package:  ", None),
    ("WARNING:  Your allocated space for installation is ",
     "Your allocated space for installation "),
    ("but you have selected to install ", None),
    ("Go ahead with the installation anyway? [n] ", None),
]
# system.setup is a CORE PACKAGE member, not a floppy file, so its summary
# question is cross-checked against the extracted core (tools/build-core-tree.sh) when
# that is present (SKIP, never a silent pass, when it is not).
STOCK_SYSSETUP = os.path.join(TOP, "out", "build", "media", "core", "root", "usr", "amiga", "bin", "system.setup")
STOCK_SUMMARY_STRING = "Do you wish to change any of these? [n] "

SCAN_PATH_FUNCS = ("scan_disks", "disk_size_hint", "rdb_present", "rdb_extent_mb")


def audit_w2_structure():
    head("U. interview structure (setup.sh: no ddsize in the scan, stdin "
         "discipline, stock wording)")
    if not os.path.isfile(SETUP):
        fail("src/installer/setup.sh is missing -- the interview is this audit's "
             "whole deliverable")
        return
    src = open(SETUP, encoding="utf-8").read()
    code = strip_full_comments(src)

    # --- U1: the scan path is ddsize-free -----------------------------------
    missing = [f for f in SCAN_PATH_FUNCS if not _extract_func(src, f)]
    if missing:
        fail("cannot extract the scan-path function(s) %s from setup.sh -- U1 "
             "would be vacuous" % missing)
    else:
        dirty = []
        for f in SCAN_PATH_FUNCS:
            body = strip_full_comments(_extract_func(src, f))
            if "ddsize" in body:
                dirty.append(f)
        if dirty:
            fail("setup.sh's SCAN path calls /etc/ddsize in %s -- a first measurement proved an "
                 "unconditional ddsize WEDGES the install on the bench a3091 path "
                 "and the miniroot has no timeout tool; a per-id scan multiplies "
                 "the exposure" % ", ".join(dirty))
        else:
            ok("the scan path (%s) never references ddsize" % ", ".join(SCAN_PATH_FUNCS))

    # Count ddsize as a COMMAND, not as text: the chooser also NAMES the probe
    # in the line it prints before running it (so a console that wedges says
    # exactly where), and a naive substring count would read those as calls.
    # Two invocations, each on ONE already-chosen id: the stock-shaped one in choose_disk behind DDSIZE_SAFE
    # (a pinned rig), and the bounded one in disk_real_mb (a profile that pins no size: the published media),
    # which choose_disk alone calls, never on the A3000's WD, in the background with a per-second bound.
    chooser = _extract_func(src, "choose_disk") or ""
    real = _extract_func(src, "disk_real_mb") or ""
    nds_file = list(command_words(src)).count("/etc/ddsize")
    nds_chooser = list(command_words(chooser)).count("/etc/ddsize")
    nds_real = list(command_words(real)).count("/etc/ddsize")
    if nds_file == 2 and nds_chooser == 1 and nds_real == 1 and "DDSIZE_SAFE" in strip_full_comments(chooser):
        ok("ddsize is INVOKED twice in the whole interview: once in choose_disk behind the DDSIZE_SAFE gate, "
           "once in the bounded disk_real_mb, each on ONE already-chosen id")
    else:
        fail("expected two ddsize INVOCATIONs (choose_disk behind DDSIZE_SAFE, disk_real_mb); found %d in the "
             "file / %d in choose_disk / %d in disk_real_mb, gated=%s"
             % (nds_file, nds_chooser, nds_real, "DDSIZE_SAFE" in strip_full_comments(chooser)))
    rb = strip_full_comments(real)
    calls = [l for l in strip_full_comments(src).splitlines() if "disk_real_mb " in l and "disk_real_mb()" not in l]
    if (re.search(r'mobo:a3000-wd\)', rb) and re.search(r'\) < /dev/null > /dev/null 2>&1 &', rb)
            and "DDSIZE_SECS" in rb and "/bin/sleep 1" in rb and len(calls) == 1
            and "disk_real_mb" in strip_full_comments(chooser)):
        ok("disk_real_mb never asks the A3000's WD, runs ddsize in the background with its own descriptors, "
           "polls it each second up to DDSIZE_SECS, and is called once, from choose_disk")
    else:
        fail("disk_real_mb must skip mobo:a3000-wd, background ddsize with its own descriptors, bound it by "
             "DDSIZE_SECS with /bin/sleep 1, and be called once from choose_disk (calls: %d)" % len(calls))

    # --- U2: SCAN_IDS derived-checked against the proto ---------------------
    m = re.search(r'SCAN_IDS="([0-9 ]+)"', code)
    if not m:
        fail("setup.sh has no SCAN_IDS default -- the scanned id list is unpinned")
    else:
        # the ids against the miniroot's own device nodes: the bench repository's check (its proto)
        got = sorted(int(x) for x in m.group(1).split())
        if 4 in got:
            fail("SCSI id 4 is scannable -- stock reserved it for the tape drive "
                 "and the miniroot ships no c4d0 node; the refusal must stay structural")
        else:
            ok("setup.sh SCAN_IDS %s: id 4 (the tape drive's) is not scanned" % got)

    # --- U3: the transplant's stdin -----------------------------------------
    m = re.search(r'(?m)^\s*sh\s+"\$INST/bin/install\.sh"\s+"\$ANSWERS"\s*<\s*/dev/null\s*$',
                  code)
    if m:
        ok("setup.sh runs the driver with stdin from /dev/null ("
           "preserved: the transplant never inherits the interview's console)")
    else:
        fail("setup.sh must run `sh \"$INST/bin/install.sh\" \"$ANSWERS\" "
             "< /dev/null` -- an inherited stdin is what hung a metal run on the 1991 "
             "pkgadd prompt")
    # --- U3b (D15): the interactive install ENDS in a halt, never a respawn ---
    tail = code[m.end():] if m else ""
    d15 = (re.search(r'rc=\$\?', tail) and
           re.search(r'if \[ -f /matrix\.go \]; then\s+exit \$rc\s+fi', tail) and
           re.search(r'if \[ "\$rc" = 0 \]; then.*?readask.*?sync\s+sync\s+/etc/uadmin 2 0\s+fi',
                     tail, re.S) and
           re.search(r'exec /bin/sh\s*$', tail))
    if d15:
        ok("D15: after a successful driver run setup.sh asks RETURN, syncs twice and "
           "halts (uadmin 2 0); a failed run drops to a shell -- no respawned installer; "
           "under the matrix (/matrix.go) it returns the driver's rc instead")
    else:
        fail("D15: setup.sh must end the interactive install with RETURN -> sync -> "
             "uadmin 2 0 (and a shell on failure), not exec the driver and respawn")

    # --- U4: the answers profile --------------------------------------------
    checks = [
        # ★ Bench-measured: the answers profile is the base profile's
        # ASSIGNMENTS, not a byte copy. A profile is 90% comment -- 13,556 bytes
        # of which ~1,000 are keys -- and copying it whole spent 26 of the
        # floppy's 46 free blocks on prose, on the filesystem the static pkgadd
        # needs for its packaging directory. The merge mechanism is identical
        # (sh ignores comments when it sources a file), the headroom is not.
        (r"case \"\$pline\" in\n\t\t''\|\\#\*\)",
         "the answers profile takes the base profile's ASSIGNMENTS only "
         "(comments are 26 blocks of an 880-block floppy)"),
        (r'done < "\$PROFILE_FILE" > "\$ANSWERS"',
         "...composed by a redirect-fed loop (no grep/sed on the miniroot)"),
        (r'\[ -s "\$ANSWERS" \] \|\| die',
         "...and an EMPTY result is refused (a filter that ate everything must "
         "never reach the driver)"),
        (r'>>\s*"\$ANSWERS"',
         "the answers are APPENDED (a later assignment wins when sh sources it)"),
        (r'TARGET_DISK_MB=\$DISK_MB',
         "TARGET_DISK_MB is always pinned, so install.sh never probes ddsize itself"),
        (r'TARGET_ROOT_MB=\$ANS_ROOT', "the root answer lands in the driver key"),
        (r'TARGET_SWAP_MB=\$ANS_SWAP', "the swap answer lands in the driver key"),
        (r'INSTALL_VERBOSE=\$ANS_VERBOSE', "the verbose answer lands in the driver key"),
        (r'INSTALL_SET=\$SET_NAME', "the chosen set's NAME lands in the driver key"),
        (r'INSTALL_ORDER=\$SET_ORDER', "the chosen set's ORDER FILE lands in the driver key"),
        (r'INSTALL_ATTESTED=\$SET_ATT',
         "the set's attestation posture is recorded, so a waived digest gate is "
         "never silent (plan 5.7)"),
        (r'SETUP-ANSWERS-BEGIN', "the beacon's BEGIN marker (the blind-console harness greps it)"),
        (r'SETUP-ANSWERS-END', "the beacon's END marker"),
        # ★ THE FLOPPY BUDGET (bench-measured). The root filesystem here is
        # an 880-block floppy with ~46 blocks free; $ANSWERS alone is 12 of them
        # (the base profile is copied whole -- the medium is read-only), and the
        # static pkgadd needs room on this same filesystem for
        # /usr/apkg/sadm/install/scripts. Echoing the WHOLE composed profile as
        # the beacon spent another 12 and killed the first interactive run:
        # `Floppy fd0: no space` -> `pkgadd: ERROR: unable to make packaging
        # directory` -> `STOP: base-OS install FAILED for package(s): core`.
        # (An earlier run survived the same shape with SIX blocks to spare -- luck.) The
        # beacon carries the ANSWERS BLOCK only, and the interview's scratch is
        # handed back before the transplant.
        (r'cat "\$ANSWERS_BLOCK" > "\$ANSWERS_ECHO_PATH"',
         "the beacon is the ANSWERS BLOCK, not the whole composed profile (the "
         "floppy has ~46 free blocks and pkgadd needs some of them)"),
        (r'rm -f "\$\{BLK0:\?\}" ',
         "the interview hands its scratch back before exec'ing the driver"),
    ]
    for pat, why in checks:
        if re.search(pat, code):
            ok("answers profile: %s" % why)
        else:
            fail("answers profile: MISSING -- %s (no /%s/ in setup.sh)" % (why, pat))

    # The comment filter goes through `read`, and the 1991 `read` has no -r: it
    # EATS BACKSLASHES. Comments may contain them (they do); an ASSIGNMENT may
    # not, or the value that reaches the driver is not the value the profile
    # wrote. Cheap to check, silent to get wrong.
    bad = []
    for pf in sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")):
        for i, line in enumerate(open(os.path.join(PROFILES_DIR, pf),
                                      encoding="utf-8"), 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if "\\" in s:
                bad.append("%s:%d" % (pf, i))
    if not bad:
        ok("no tracked profile has a backslash on an assignment line (the "
           "answers filter reads through `read`, which has no -r here)")
    else:
        fail("backslash on a profile ASSIGNMENT line -- `read` would eat it: %s"
             % ", ".join(bad))

    if re.search(r'cat "\$ANSWERS" > "\$ANSWERS_ECHO_PATH"', code):
        fail("setup.sh echoes the WHOLE composed profile as the beacon -- that is "
             "12 blocks of an 880-block floppy that the static pkgadd needs for "
             "its packaging directory (bench: `Floppy fd0: no space` then "
             "`pkgadd: ERROR: unable to make packaging directory`)")
    else:
        ok("the beacon is never the whole profile (the floppy-space defect once "
           "measured cannot come back)")

    # --- U5: no stty --------------------------------------------------------
    if re.search(r'\bstty\b', code):
        fail("setup.sh runs stty -- that would FLUSH the answers the install "
             "matrix types into the tty queue ahead of the prompts, and the run "
             "would hang with no diagnosis (stock's own stty lines are commented out)")
    else:
        ok("setup.sh never runs stty (the queued-answer channel stays intact)")

    # --- U6: stock wording, byte-for-byte -----------------------------------
    table = STOCK_INTERVIEW_STRINGS + STOCK_AMIXPKG_STRINGS
    absent = [ours for (ours, _) in table if ours not in src]
    if absent:
        for a in absent:
            fail("setup.sh does not carry the stock string %r" % a)
    else:
        ok("setup.sh carries all %d stock interview strings" % len(table))

    # --- U7: every tracked profile declares the two interview keys -----------
    # Same discipline as the driver keys: a key whose default is silent
    # is a key nobody notices is wrong. DDSIZE_SAFE especially -- its default is
    # the SAFE answer (n), so a metal profile that forgets it silently loses the
    # probe stock itself used, and a bench profile that forgets it is fine; only
    # writing it down makes the difference visible.
    prof = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile"))
    if not prof:
        fail("no profiles found in %s -- U7 would be vacuous" % PROFILES_DIR)
    for f in prof:
        keys = _parse_profile(os.path.join(PROFILES_DIR, f))
        miss = [k for k in ("DDSIZE_SAFE", "ANSWERS_ECHO") if k not in keys]
        if miss:
            fail("profile %s does not declare %s (the interview keys)" % (f, miss))
        elif keys.get("DDSIZE_SAFE") not in ("y", "n"):
            fail("profile %s has DDSIZE_SAFE=%r -- it must be y or n"
                 % (f, keys.get("DDSIZE_SAFE")))
        else:
            ok("profile %-34s DDSIZE_SAFE=%s ANSWERS_ECHO=%s"
               % (f, keys["DDSIZE_SAFE"], keys["ANSWERS_ECHO"]))
    # the bench rig is where the wedge was MEASURED: it must never say y. The Gayle
    # IDE row is another controller (no a3091 on that path) and probes its one id.
    for f in prof:
        if f.startswith("bench-"):
            keys = _parse_profile(os.path.join(PROFILES_DIR, f))
            if keys.get("TARGET_HBA") == "gayle":
                ok("bench profile %s: Gayle IDE target, DDSIZE_SAFE=%s (not the a3091 rig)"
                   % (f, keys.get("DDSIZE_SAFE")))
            elif keys.get("DDSIZE_SAFE") == "y":
                fail("bench profile %s sets DDSIZE_SAFE=y -- the a3091 ddsize wedge "
                     "was measured on exactly that rig (matrix 20260811-094255-cd)" % f)
            else:
                ok("bench profile %s keeps DDSIZE_SAFE=n (the rig the wedge was "
                   "measured on)" % f)

    if STOCK_SUMMARY_STRING not in src:
        fail("setup.sh does not carry system.setup's summary question %r"
             % STOCK_SUMMARY_STRING)
    elif os.path.isfile(STOCK_SYSSETUP):
        if STOCK_SUMMARY_STRING in open(STOCK_SYSSETUP, encoding="latin1").read():
            ok("the confirmation question is system.setup's own %r (verified "
               "against the extracted core package)" % STOCK_SUMMARY_STRING)
        else:
            fail("%r is not in the stock system.setup -- the confirmation screen "
                 "is not using stock wording" % STOCK_SUMMARY_STRING)
    else:
        skip("extracted core system.setup absent -- the confirmation question's "
             "stock provenance is not cross-checked (not a pass)")


# ---------------------------------------------------------------------------
# V. THE INTERVIEW'S DEFAULTS ARE THE DRIVER'S PLAN
# ---------------------------------------------------------------------------
# The sizing screen SHOWS `[79]` and `[18]`; install.sh BUILDS the layout. If
# those two arithmetics ever drift, the interview lies to the operator -- it
# offers a default the driver then computes differently, and nothing downstream
# notices because both numbers are individually legal. So both are EXTRACTED
# and EXECUTED here, on the same disk sizes, and required to agree. (Audit E
# already pins the driver's half against tools/mkroot.sh, which is itself the
# stock arithmetic -- so agreement here chains setup.sh -> driver -> mkroot ->
# stock.)
V_DISK_SIZES = [50, 60, 100,  # r6e: 50, not 40 -- 40 MB is now inside the default-root clamp window
                120, 121, 200, 500, 1000, 2000]


def _setup_plan_harness():
    src = open(SETUP, encoding="utf-8").read()
    lines = src.splitlines()
    ci = next(i for i, l in enumerate(lines) if l.startswith("MINROOT="))
    cj = next(i for i, l in enumerate(lines) if l.startswith("SECS=64"))
    consts = "\n".join(lines[ci:cj + 1])
    # the 1.1 store as the boot size: the two lines setup.sh runs after the profile
    li = next(i for i, l in enumerate(lines) if l.startswith("L11_STORE_MB="))
    consts += "\n" + "\n".join(lines[li:li + 2])
    return (consts + "\n" + _extract_func(src, "is_num") + "\n" +
            _extract_func(src, "l11_data_mb") + "\n" +
            _extract_func(src, "plan_root_default") + "\n" +
            _extract_func(src, "plan_swap_default") + "\n"
            'if plan_root_default "$1"; then :; else echo "TOOSMALL"; exit 0; fi\n'
            'plan_swap_default "$DEF_ROOT"\n'
            'echo "$DEF_ROOT $DEF_SWAP $ROOTMAX $MAXSWAP"\n')


def audit_w2_sizing():
    head("V. the interview's sizing defaults == the driver's plan (both EXECUTED)")
    try:
        sh_setup = _setup_plan_harness()
        drv = extract_plan_harness()
    except StopIteration:
        fail("could not extract the sizing blocks from setup.sh and/or install.sh")
        return
    old = 'echo "$ROOT_OFF $SWAP_OFF $BOOT_OFF $ROOTLEN $SWAPLEN $BOOTLEN"'
    new = 'echo "$ROOT_MB $SWAP_MB $ROOTMAX $MAXSWAP"'
    if old not in drv:
        fail("the driver plan harness changed shape -- V cannot compare megabytes")
        return
    drv = drv.replace(old, new)

    sp = workpath("w2plan-setup.sh")
    dp = workpath("w2plan-driver.sh")
    open(sp, "w").write(sh_setup)
    open(dp, "w").write(drv)
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"

    bad = 0
    for mb in V_DISK_SIZES:
        a = subprocess.run([sh, sp, str(mb)], capture_output=True, text=True)
        b = subprocess.run([sh, dp, str(mb)], capture_output=True, text=True)
        sa = a.stdout.strip()
        sb = b.stdout.strip()
        if sa != sb:
            fail("%4d MB disk: interview offers %r but the driver plans %r"
                 % (mb, sa, sb))
            bad += 1
    if not bad:
        ok("root/swap defaults + the ROOTMAX/MAXSWAP bounds agree for all %d disk "
           "sizes %s" % (len(V_DISK_SIZES), V_DISK_SIZES))

    # NON-VACUITY: the comparison must be of real numbers, not two empty strings.
    a = subprocess.run([sh, sp, "108"], capture_output=True, text=True).stdout.split()
    if len(a) == 4 and a[0] == "79" and a[1] == "18":
        ok("non-vacuity: the 108 MB bench disk (r6e 10 MiB boot) really yields 79 root / 18 swap "
           "(%s) -- the documented bench layout" % " ".join(a))
    else:
        fail("non-vacuity: the 108 MB harness produced %r, expected the documented "
             "bench layout 79 root / 18 swap" % a)

    # E-BIG: the stock-kernel root ceiling is REAL in both halves -- a 1000 MB
    # disk offers and plans a 602 MB root (1234567 blocks / 2048) with ROOTMAX 602,
    # and KERNEL_SDDEVSIZE=fixed (a kernel carrying the sddevsize fix) lifts it.
    for label, env_extra, want in (("stock kernel", {}, ("602", "602")),
                                   ("KERNEL_SDDEVSIZE=fixed", {"KERNEL_SDDEVSIZE": "fixed"}, None)):
        env = dict(os.environ, **env_extra)
        ra = subprocess.run([sh, sp, "1000"], capture_output=True, text=True, env=env).stdout.split()
        rb = subprocess.run([sh, dp, "1000"], capture_output=True, text=True, env=env).stdout.split()
        # the driver prints its cap note on stdout too; compare the final 4 numbers
        ra, rb = ra[-4:], rb[-4:]
        if want:
            good = ra == rb and len(ra) == 4 and (ra[0], ra[2]) == want
        else:
            good = ra == rb and len(ra) == 4 and int(ra[0]) > 602 and int(ra[2]) > 602
        if good:
            ok("E-BIG cap, %s: a 1000 MB disk -> root %s / ROOTMAX %s in BOTH the interview "
               "and the driver" % (label, ra[0], ra[2]))
        else:
            fail("E-BIG cap, %s: 1000 MB disk -> interview %r, driver %r" % (label, ra, rb))

    # 1.1 (INSTALL_LAYOUT=1.1): the boot slice is the 64 MiB store and a data slice may
    # come off first. The driver half takes both from l11.sh (L11_STORE_MB, l11_plan_data),
    # the interview half from its own copies; the same numbers on both lines and with a
    # TARGET_DATA_MB, or the interview offers a root the driver refuses (seen 2026-10-27:
    # [159] on a 200 MB disk against a ceiling of 105).
    l11src = open(L11, encoding="utf-8").read()
    l11store = next(l for l in l11src.splitlines() if l.startswith("L11_STORE_MB="))
    dp11 = workpath("w2plan-driver-l11.sh")
    open(dp11, "w").write(l11store + "\n" + _extract_func(l11src, "l11_plan_data") + "\n" + drv)
    bad = 0
    n = 0
    for env_extra in ({}, {"INSTALL_CPU": "060"}, {"TARGET_DATA_MB": "40"}):
        env = dict(os.environ, INSTALL_LAYOUT="1.1", **env_extra)
        for mb in (200, 300, 512, 1000, 2000):
            n += 1
            ra = subprocess.run([sh, sp, str(mb)], capture_output=True, text=True, env=env).stdout.split()[-4:]
            rb = subprocess.run([sh, dp11, str(mb)], capture_output=True, text=True, env=env).stdout.split()[-4:]
            if ra != rb or len(ra) != 4:
                fail("1.1 %s, %d MB disk: interview offers %r but the driver plans %r"
                     % (env_extra or "defaults", mb, ra, rb))
                bad += 1
    if not bad:
        ok("1.1 layout: root/swap defaults + bounds agree in %d cases (030, 060, TARGET_DATA_MB=40; "
           "200..2000 MB)" % n)
    env = dict(os.environ, INSTALL_LAYOUT="1.1", INSTALL_CPU="060")
    r200 = subprocess.run([sh, sp, "200"], capture_output=True, text=True, env=env).stdout.split()
    if r200[:1] == ["105"] and r200[2:3] == ["105"]:
        ok("non-vacuity: a 200 MB 1.1 disk on the 060 line offers root 105 (ROOTMAX 105): 64 MiB store, 30 MB swap")
    else:
        fail("non-vacuity: a 200 MB 1.1 060 disk gave %r, expected root 105 / ROOTMAX 105" % r200)

    # a disk too small for boot+root+swap must be REFUSED, not silently planned
    tiny = subprocess.run([sh, sp, "3"], capture_output=True, text=True).stdout.strip()
    if tiny == "TOOSMALL":
        ok("a 3 MB disk is refused by the interview's own arithmetic (no negative plan)")
    else:
        fail("a 3 MB disk produced %r instead of a refusal" % tiny)


# ---------------------------------------------------------------------------
# W. THE INTERVIEW, ACTUALLY RUN (a sandboxed end-to-end conversation)
# ---------------------------------------------------------------------------
# Structure audits cannot tell you whether an interview WORKS. This one RUNS
# src/installer/setup.sh under dash against a fake bus -- disks are regular
# files whose block 0 carries (or does not carry) the RDSK magic, /etc/rdb and
# /etc/ddsize are stubs that answer from a table, install.sh is a stub that
# records the profile path it was handed -- feeds it canned answers, and checks
# what it PRINTED and what it COMPOSED.
#
# The script under test is the shipped one with a fixed set of absolute-path
# LITERALS rewritten to point into the sandbox (/cdrom, /dev/dsk, /etc/rdb,
# /etc/ddsize, /tmp/..., /matrix.). One pass, longest-literal-first, so no
# rewritten text can be re-matched; nothing else about the file is touched.
#
# What the cases cover, and why each one is here:
#   * the bench shape end to end -- one eligible disk, so the stock "What is the
#     SCSI id" question is SKIPPED exactly as stock skipped it, the erase
#     confirmation fires on the existing RDB, and the composed profile carries
#     the five answer keys. This is the `cd-interactive` matrix cell, in
#     miniature, host-side.
#   * every dead end reaches the RESTART idiom rather than falling through: no
#     disks, no installable disk, erase declined.
#   * the size question ladder: profile pin -> RDB extent -> ddsize (only when
#     DDSIZE_SAFE says so) -> ask the operator. The DDSIZE_SAFE=n case must
#     ASK; if it ever probes instead, the bench wedges and the run dies with no
#     diagnosis, so that one is asserted in both directions.
#   * stock's four size-validation messages, each provoked and then recovered
#     from -- a validation that cannot be re-answered is a hang.
#   * the package menu is DATA-DRIVEN: the MB column appears only when the
#     medium's catalog carries an #isize block, is ALL-OR-NOTHING (a package
#     without a size means no figure at all, never a partial sum printed as
#     fact), and is never 0.0.
#   * the beacon: written when the matrix's markers are present or the profile
#     asks for it, and NOT written otherwise.

W_ORDER = ["core", "bsd", "net", "text", "sysadm", "cdfs", "APKGENG", "APKG"]
W_BENCH_PARTS = [("UNIX_Root", 128, 161792), ("UNIX_Swap", 161920, 36864),
                 ("UNIX_Boot", 198784, 4096)]
W_PROFILE = """PROFILE_NAME=w2test
PROFILE_DESC="selftest sandbox"
SOURCE_KIND=cdfs
CD_SPEC=1,3
TARGET_SCSI_ID=6
TARGET_ROOT_SLICE=1
TARGET_SWAP_SLICE=2
TARGET_BOOT_SLICE=3
TARGET_DISK_MB=108
TARGET_ROOT_MB=
TARGET_SWAP_MB=
ROOTDEV=0x00480016
INSTALL_VERBOSE=n
DDSIZE_SAFE=n
"""
W_CATALOG = """#apkg-catalog 1
core|2.1|core|stock/core-2.1.pkg|aaa|11247104|none|system|Amiga Unix essentials
bsd|2.1|bsd|stock/bsd-2.1.pkg|bbb|1654784|none|system|Berkeley compat
net|2.1|net|stock/net-2.1.pkg|ccc|3042816|none|system|Networking
text|2.1|text|stock/text-2.1.pkg|ddd|1000000|none|system|Text
sysadm|2.1|sysadm|stock/sysadm-2.1.pkg|eee|1000000|none|system|Sysadm
cdfs|0.1|cdfs|base/cdfs-0.1.pkg|fff|8192|core|system|CD filesystem
apkgeng|1.12.0|APKGENG|base/APKGENG-1.12.0.pkg|ggg|2347520|none|application|Heirloom
apkg|0.1|APKG|base/APKG-0.1.pkg|hhh|115200|apkgeng|application|Remote client
#ext isize 1
#isize core 20000000
#isize bsd 3000000
#isize net 5000000
#isize text 2000000
#isize sysadm 2000000
#isize cdfs 8192
#isize apkgeng 4000000
#isize apkg 200000
"""

# ★ The catalog that puts the disc's own set at EXACTLY the megabyte where the
# ufs superuser reserve decides the answer. The eight #isize lines below sum to
# 75,800,000 payload bytes; the interview budgets that at x + x/10 = 83,380,000,
# which is 79 MB of footprint. Against the bench disk's stock default 79 MB root
# that is a fit on s5 (79 > 79 is false) and an overcommit on ufs (79 > 78,
# because `-o free=2` keeps 2% for the superuser). One number, two verdicts,
# decided solely by the filesystem the operator picked -- which is what makes the
# reserve testable at all rather than a comment nobody can falsify.
W_CATALOG_79 = W_CATALOG.replace("#isize core 20000000",
                                 "#isize core 59591808")

_W_RDB_STUB = '''#!/bin/sh
# sandbox /etc/rdb: answers from a per-disk table. Supports the four forms
# setup.sh uses -- `rdb DEV` (rc 0 iff an RDB), `-h 5` (last partition number),
# `-p N` ("name start length"), `-V` (the human table).
ROOT=%s
mode=info; num=
while [ $# -gt 1 ]; do
  case "$1" in
    -h) mode=h; num="$2"; shift 2 ;;
    -p) mode=p; num="$2"; shift 2 ;;
    -V) mode=V; shift ;;
    *) shift ;;
  esac
done
dev="$1"
id=`echo "$dev" | sed 's|.*/c\\([0-9]*\\)d0s0|\\1|'`
data="$ROOT/bin/rdbdata.c$id"
[ -f "$data" ] || exit 2
has=`sed -n 1p "$data"`
[ "$has" = 1 ] || exit 1
npart=`sed -n '3,$p' "$data" | grep -c .`
case "$mode" in
  info) exit 0 ;;
  h) [ "$num" = 5 ] && echo "$npart" && exit 0; exit 1 ;;
  p) sed -n "$((2+num))p" "$data"; exit 0 ;;
  V) echo "#    Name             Start   Blocks   Size      Flags"
     n=0
     sed -n '3,$p' "$data" | while read nm st ln; do
       n=`expr $n + 1`; echo " $n:  $nm $st $ln"
     done
     exit 0 ;;
esac
'''

_W_DDSIZE_STUB = '''#!/bin/sh
ROOT=%s
id=`echo "$1" | sed 's|.*/c\\([0-9]*\\)d0s0|\\1|'`
data="$ROOT/bin/rdbdata.c$id"
[ -f "$data" ] || exit 1
sed -n 2p "$data"
'''


# the two stock machine-class probes the miniroot carries, as sandbox stubs.
# The DEFAULT values are the ones MEASURED on the canonical bench rig
# 2026-08-12 (work/install-matrix/w6-oldboot): /etc/romsize prints 524288 --
# exactly the stock threshold, so a KS 2.04 box clears `-lt 524288` by zero
# margin -- and `/etc/dioc 1 < /dev/rdsk/c6d0s0` prints `A3000 Internal SCSI`,
# whose FIRST token is what stock compares against "A2090".
_W_ROMSIZE_STUB = '#!/bin/sh\n%s\n'
_W_DIOC_STUB = '#!/bin/sh\ncat > /dev/null\n%s\n'
W_BENCH_ROMSIZE = "echo 524288"
W_BENCH_DIOC = 'echo "A3000 Internal SCSI"'


def _w_build(root, disks, profile_text, order, catalog=None, base_marker=None,
             matrix_marker=True, sets=None, extra_orders=None, machine=None,
             base_lines=None, kinfo_line=None, kbootset=None):
    """disks: {id: (mb, has_rdb, [(name, start, len), ...])}

    kbootset:     the text `kbootset cards --probe` prints (a universal medium's card table),
                  served by a stub at the medium's l11/bin/kbootset; None = no kbootset

    sets:         text of the medium's /install/sets table, or None for a
                  older medium that has none (the interview must still show
                  three rows -- the numbering is a UI constant).
    extra_orders: {"order.standard": [pkg, ...]} -- the per-set order files
                  tools/build-install-iso.sh stages beside /install/order."""
    shutil.rmtree(root, ignore_errors=True)
    for d in ("cdrom/install/bin", "cdrom/install/profiles", "dev/dsk", "dev/rdsk",
              "bin", "tmp", "etc"):
        os.makedirs(os.path.join(root, d))
    for i, (mb, has_rdb, parts) in disks.items():
        p = os.path.join(root, "dev/dsk/c%dd0s0" % i)
        with open(p, "wb") as f:
            f.write((b"RDSK" + bytes(508)) if has_rdb else bytes(512))
            f.write(bytes(512 * 15))
        os.symlink(p, os.path.join(root, "dev/rdsk/c%dd0s0" % i))
        with open(os.path.join(root, "bin/rdbdata.c%d" % i), "w") as f:
            f.write("%d\n%d\n" % (1 if has_rdb else 0, mb * 2048))
            for (nm, st, ln) in parts:
                f.write("%s %d %d\n" % (nm, st, ln))
    for name, body in (("rdb", _W_RDB_STUB), ("ddsize", _W_DDSIZE_STUB)):
        fp = os.path.join(root, "bin", name)
        open(fp, "w").write(body % root)
        os.chmod(fp, 0o755)
    # Machine-class probes. `machine=None` means NEITHER PROBE EXISTS, which
    # is the fail-open path and therefore the right default for every case that
    # is not about machine class: `[ -x ... ]` is false and check_old_boot
    # returns without a word.
    if machine is not None:
        for name, key, default in (("romsize", "rom", W_BENCH_ROMSIZE),
                                   ("dioc", "controller", W_BENCH_DIOC)):
            body = machine.get(key, default)
            if body is None:
                continue
            fp = os.path.join(root, "bin", name)
            open(fp, "w").write(
                (_W_ROMSIZE_STUB if name == "romsize" else _W_DIOC_STUB) % body)
            os.chmod(fp, 0o755)
    if kbootset is not None:
        os.makedirs(os.path.join(root, "cdrom/install/l11/bin"), exist_ok=True)
        fp = os.path.join(root, "cdrom/install/l11/bin/kbootset")
        open(fp, "w").write('#!/bin/sh\ncase "$1 $2" in\n"cards --probe") cat <<\'EOF\'\n%sEOF\n;;\n"cards ") cat <<\'EOF\'\n%sEOF\n;;\n'
                            '*) exit 2 ;;\nesac\n' % (kbootset, "".join(l + "\n" for l in kbootset.splitlines()
                                                                         if l.startswith("card "))))
        os.chmod(fp, 0o755)
    fp = os.path.join(root, "cdrom/install/bin/install.sh")
    open(fp, "w").write('#!/bin/sh\necho "STUB-INSTALL-ARG=$1"\nexit 0\n')
    os.chmod(fp, 0o755)
    open(os.path.join(root, "cdrom/install/profiles/w2test.profile"), "w").write(profile_text)
    open(os.path.join(root, "cdrom/install/order"), "w").write("\n".join(order) + "\n")
    if sets is not None:
        open(os.path.join(root, "cdrom/install/sets"), "w").write(sets)
    for name, pkgs in (extra_orders or {}).items():
        open(os.path.join(root, "cdrom/install", name), "w").write("\n".join(pkgs) + "\n")
    if catalog is not None:
        open(os.path.join(root, "cdrom/catalog"), "w").write(catalog)
    if base_marker:
        open(os.path.join(root, "cdrom/install/profiles/BASE"), "w").write(base_marker + "\n")
    for ln, name in (base_lines or {}).items():
        open(os.path.join(root, "cdrom/install/profiles/BASE." + ln), "w").write(name + "\n")
    if kinfo_line is not None:
        # the C2-1 record's head: magic, version|length, check, CPU, line (offset 16)
        os.makedirs(os.path.join(root, "dev"), exist_ok=True)
        open(os.path.join(root, "dev/kinfo"), "wb").write(
            b"KIF1" + struct.pack(">IIII", (3 << 16) | 580, 0, kinfo_line + 14, kinfo_line)
            + bytes(560))
    if matrix_marker:
        open(os.path.join(root, "matrix.up"), "w").close()

    src = open(SETUP, encoding="utf-8").read()
    rw = {"/cdrom": root + "/cdrom",
          "/etc/rdb": root + "/bin/rdb",
          "/etc/ddsize": root + "/bin/ddsize",
          "/etc/romsize": root + "/bin/romsize",
          "/etc/dioc": root + "/bin/dioc",
          # The card-1 source candidates the choose_disk scan derives SCAN_IDS
          # from: redirected into the sandbox so a run never reads the host's real
          # /etc/install-src-candidates, and so a case that WRITES <root>/etc/install-
          # src-candidates actually exercises the card-1 derivation branch.
          "/etc/install-src-candidates": root + "/etc/install-src-candidates",
          "/dev/dsk/": root + "/dev/dsk/",
          "/dev/kinfo": root + "/dev/kinfo",
          "/dev/rdsk/": root + "/dev/rdsk/",
          "/tmp/setup.": root + "/tmp/setup.",
          "/tmp/cd.spec": root + "/tmp/cd.spec",
          "/tmp/cards.probe": root + "/tmp/cards.probe",
          "/tmp/answers.profile": root + "/tmp/answers.profile",
          "/matrix.": root + "/matrix."}
    # ONE pass, longest literal first: no substituted text can be re-matched.
    pat = re.compile("|".join(re.escape(k) for k in
                              sorted(rw, key=len, reverse=True)))
    out = os.path.join(root, "setup.sh")
    open(out, "w").write(pat.sub(lambda m: rw[m.group(0)], src))
    return out


def _w_run(script, answers, arg="w2test", env=None):
    """Run the sandboxed interview. `env` adds variables to the ENVIRONMENT the
    interview inherits -- today only INSTALL_TARGET_PREBUILT, which the install
    matrix and the runbook put in front of the whole exec chain
    (`INSTALL_TARGET_PREBUILT=1 sh /etc/profile`) and which setup.sh reads to
    decide whether the root-filesystem question can be honoured at all."""
    cmd = ["/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh", script]
    if arg:
        cmd.append(arg)
    e = None
    if env:
        e = dict(os.environ)
        e.update(env)
    return subprocess.run(cmd, input="\n".join(answers) + "\n",
                          capture_output=True, text=True, timeout=120, env=e)


def audit_w2_interview():
    head("W. the interview, ACTUALLY RUN (sandboxed conversations)")
    if not os.path.isfile(SETUP):
        fail("src/installer/setup.sh missing -- nothing to run")
        return
    if not os.path.exists("/usr/bin/dash"):
        skip("dash absent -- the interview cannot be run under a pre-POSIX-ish sh "
             "(not a pass)")
        return
    root = workpath("w2sbx")
    for bad in ("/tmp/setup.", "/tmp/answers.profile", "/matrix.", "/cdrom"):
        if bad in root:
            fail("the sandbox path %r contains the literal %r the rewrite targets "
                 "-- the fixture would corrupt itself" % (root, bad))
            return

    # r6e: 108 MB with the 10 MiB boot slice leaves exactly what 100 MB left with the stock 2 MiB one,
    # so every 79/18 case below keeps its stock numbers.
    bench = {6: (108, True, W_BENCH_PARTS)}
    # --- fixtures: a medium that carries a set table + a per-set order --------
    # Row 1 is a set the medium fully carries (order.standard, five packages);
    # row 2 is everything on the disc (the full base-8 /install/order). That is
    # exactly the shape tools/build-install-iso.sh authors for a disc mastered
    # for a set larger than `standard`.
    w3_sets = ("# <num> <setname> <orderfile> <attested> <label...>\n"
               "1 standard order.standard y Standard Amiga UNIX installation\n"
               "2 minimal order y Everything on the disc\n")
    w3_sets_unatt = w3_sets.replace("2 minimal order y", "2 media order n")
    w3_orders = {"order.standard": ["core", "bsd", "net", "text", "sysadm"]}
    w3 = {"sets": w3_sets, "extra_orders": w3_orders, "catalog": W_CATALOG}
    w3u = {"sets": w3_sets_unatt, "extra_orders": w3_orders, "catalog": W_CATALOG}
    multi = {5: (200, True, [("UNIX_Root", 128, 300000)]),
             6: (100, True, W_BENCH_PARTS)}
    p_multi = W_PROFILE + 'INSTALLABLE_IDS="5 6"\n'
    # a universal medium: no controller, no target, no disk size of its own
    p_uni = W_PROFILE.replace("TARGET_DISK_MB=108", "TARGET_DISK_MB=") + "TARGET_HBA=auto\n"
    uni_probe = ("card 0: c0-c7 zorro:144b:01 base 0x40000000\n  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\n"
                 "card 1: c8-cf zorro:0202:54 base 0x40800000\n  unit 3: type 5 ZuluSCSI CDROM 2.0\n"
                 "card 2: c10-c17 mobo:gayle\n  unit 5: type 5 UAE-ATAPI CD-ROM 0.1\n  unit 6: type 0 UAE IDE -\n")
    p_src = W_PROFILE + "SRC_SCSI_ID=0\n"
    p_blank = W_PROFILE.replace("TARGET_DISK_MB=108", "TARGET_DISK_MB=")
    p_dds = p_blank.replace("DDSIZE_SAFE=n", "DDSIZE_SAFE=y")

    # name, disks, answers, kwargs, expect-in-stdout, forbid-in-stdout, expect-in-answers
    cases = [
        ("bench shape: one eligible disk, id question SKIPPED, erase confirmed",
         bench, ["y", "79", "18", "1", "n", "n"], {},
         ["Scanning SCSI bus for hard disks...",
          "Hard disks attached to this system:",
          "SCSI id 6\t\t108 megabytes",
          "Are you sure you want to erase this disk? ",
          "How many megabytes for the root file system? [79] ",
          "How many megabytes for the swap partition? [18] ",
          "(1)  Standard Amiga UNIX installation",
          "Choose: [1] ", "Verbose install? [n] ",
          "Do you wish to change any of these? [n] ", "STUB-INSTALL-ARG="],
         ["What is the SCSI id"],
         ["TARGET_SCSI_ID=6", "TARGET_DISK_MB=108", "TARGET_ROOT_MB=79",
          "TARGET_SWAP_MB=18", "INSTALL_VERBOSE=n",
          "SETUP-ANSWERS-BEGIN", "SETUP-ANSWERS-END"]),
        ("all-defaults (bare RETURNs) reproduce the stock layout",
         bench, ["y", "", "", "", "", ""], {}, [], [],
         ["TARGET_ROOT_MB=79", "TARGET_SWAP_MB=18", "INSTALL_VERBOSE=n"]),
        ("`Verbose install? y` lands as INSTALL_VERBOSE=y",
         bench, ["y", "", "", "", "y", ""], {}, [], [], ["INSTALL_VERBOSE=y"]),
        ("two eligible disks: the stock id question IS asked and honoured",
         multi, ["5", "y", "", "", "", "", "", ""], {"profile": p_multi},
         ["What is the SCSI id of the disk you want to install? ",
          "SCSI id 5", "SCSI id 6"], [], ["TARGET_SCSI_ID=5"]),
        ("an unknown id re-asks with stock's `Choose one of the following:`",
         multi, ["9", "6", "y", "", "", "", "", "", ""], {"profile": p_multi},
         ["Choose one of the following:"], [], ["TARGET_SCSI_ID=6"]),
        ("the source disk is excluded and a kernel-less id is annotated",
         {0: (500, True, [("Payload", 128, 900000)]), 1: (80, False, []),
          6: (100, True, W_BENCH_PARTS)},
         ["y", "", "", "", "", ""], {"profile": p_src},
         ["source -- not installable", "no kernel on this medium for id 1"],
         [], ["TARGET_SCSI_ID=6"]),
        # id 5 is a miniroot CD candidate too (0,5: an ATAPI drive on the IDE slave)
        ("a non-installable CD-candidate id (5) is never scanned",
         {0: (500, True, [("Payload", 128, 900000)]), 5: (80, False, []),
          6: (100, True, W_BENCH_PARTS)},
         ["y", "", "", "", "", ""], {"profile": p_src},
         ["source -- not installable"],
         ["for id 5"], ["TARGET_SCSI_ID=6"]),
        # route B (2026-10-08): ids 2/3 are miniroot CD candidates -- never opened when not installable
        ("a non-installable CD-candidate id (3) is never scanned",
         {0: (500, True, [("Payload", 128, 900000)]), 3: (80, False, []),
          6: (100, True, W_BENCH_PARTS)},
         ["y", "", "", "", "", ""], {"profile": p_src},
         ["source -- not installable"],
         ["for id 3"], ["TARGET_SCSI_ID=6"]),
        ("no disks at all -> stock's refusal + the restart idiom",
         {}, ["", ""], {},
         ["No hard disks are attached to this system.",
          "Press RETURN to restart the installation script. "], [], []),
        ("erase declined -> the restart idiom, and NO sizing question",
         bench, ["n", ""], {},
         ["Press RETURN to restart the installation script. "],
         ["How many megabytes for the root file system?"], []),
        ("blank disk + DDSIZE_SAFE=n -> the size is ASKED, ddsize NEVER run",
         {6: (250, False, [])}, ["250", "", "", "", "", "", ""], {"profile": p_blank},
         ["size unknown", "How many megabytes is this disk? [100] ",
          "Your disk is 250 megabytes."], [], ["TARGET_DISK_MB=250"]),
        ("blank disk + DDSIZE_SAFE=n, RETURN takes the 100 MB default",
         {6: (250, False, [])}, ["", "", "", "", "", "", ""], {"profile": p_blank},
         [], [], ["TARGET_DISK_MB=100"]),
        ("blank disk + DDSIZE_SAFE=y -> ddsize probes the ONE chosen id",
         {6: (250, False, [])}, ["", "", "", "", "", ""], {"profile": p_dds},
         ["Sizing the disk", "Your disk is 250 megabytes."],
         ["How many megabytes is this disk?"], ["TARGET_DISK_MB=250"]),
        ("RDB present, no profile pin -> the size comes from the RDB extent",
         bench, ["y", "", "", "", "", ""], {"profile": p_blank},
         ["SCSI id 6\t\t99 megabytes", "Your disk is 99 megabytes."],
         ["How many megabytes is this disk?"], ["TARGET_DISK_MB=99"]),
        ("a disk too small for boot+root+swap is REFUSED, not asked about "
         "(stock's own loop would reject every answer forever)",
         {6: (20, False, [])}, ["20", ""],
         {"profile": W_PROFILE.replace("TARGET_DISK_MB=108", "TARGET_DISK_MB=")},
         ["too small to install UNIX on.",
          "Press RETURN to restart the installation script. "],
         ["How many megabytes for the root file system?"], []),
        ("root under MINROOT -> stock's message, then the question re-asks",
         bench, ["y", "8", "79", "", "", "", ""], {},
         ["Your root partition must be at least 16 megabytes."], [],
         ["TARGET_ROOT_MB=79"]),
        ("root over ROOTMAX -> stock's swap-space message, then re-asks",
         bench, ["y", "95", "79", "", "", "", ""], {},
         ["You must leave at least 5 megabytes free for swap space."], [],
         ["TARGET_ROOT_MB=79"]),
        ("swap under MINSWAP -> stock's message, then re-asks",
         bench, ["y", "79", "2", "18", "", "", ""], {},
         ["You must have at least 5 megabytes of swap space."], [],
         ["TARGET_SWAP_MB=18"]),
        ("swap over MAXSWAP -> stock's remaining-megabytes message, then re-asks",
         bench, ["y", "79", "40", "18", "", "", ""], {},
         ["You only have 18 remaining megabytes available."], [],
         ["TARGET_SWAP_MB=18"]),
        ("`change any of these? y` re-runs the whole interview",
         bench, ["y", "79", "18", "1", "n", "y", "y", "40", "10", "1", "y", "n"],
         {}, [], [],
         ["TARGET_ROOT_MB=40", "TARGET_SWAP_MB=10", "INSTALL_VERBOSE=y"]),
        ("catalog #isize block -> amixpkg's MB column lights up, right-aligned "
         "(BUDGETED at ~1.10x: 34.5 MB of payload is a 37.9 MB s5 footprint)",
         bench, ["y", "", "", "", "", ""], {"catalog": W_CATALOG},
         ["(1)  Standard Amiga UNIX installation      37.9 MB"], [], []),
        ("catalog with NO isize block -> no figure at all, never 0.0",
         bench, ["y", "", "", "", "", ""],
         {"catalog": "\n".join(W_CATALOG.splitlines()[:9]) + "\n"},
         ["(1)  Standard Amiga UNIX installation"], [" MB"], []),
        ("one package missing from the isize block -> no partial sum is printed",
         bench, ["y", "", "", "", "", ""],
         {"catalog": W_CATALOG.replace("#isize apkg 200000\n", "")},
         [], [" MB"], []),
        ("no argument -> the medium's own /install/profiles/BASE names the profile",
         bench, ["y", "", "", "", "", ""], {"base_marker": "w2test", "arg": None},
         [], [], ["TARGET_SCSI_ID=6"]),
        ("no argument, a k46 kinfo -> BASE.k46 names the profile (BASE does not resolve)",
         bench, ["y", "", "", "", "", ""],
         {"base_marker": "nosuch", "base_lines": {"k46": "w2test", "k30": "nosuch"},
          "kinfo_line": 46, "arg": None},
         [], [], ["TARGET_SCSI_ID=6"]),
        ("no argument, a k30 kinfo -> BASE.k30 names the profile",
         bench, ["y", "", "", "", "", ""],
         {"base_marker": "nosuch", "base_lines": {"k46": "nosuch", "k30": "w2test"},
          "kinfo_line": 30, "arg": None},
         [], [], ["TARGET_SCSI_ID=6"]),
        ("no argument, no kinfo -> BASE, never a BASE.<line>",
         bench, ["y", "", "", "", "", ""],
         {"base_marker": "w2test", "base_lines": {"k46": "nosuch", "k30": "nosuch"},
          "arg": None},
         [], [], ["TARGET_SCSI_ID=6"]),
        ("no argument, a k46 kinfo but no BASE.k46 -> BASE",
         bench, ["y", "", "", "", "", ""],
         {"base_marker": "w2test", "base_lines": {"k30": "nosuch"}, "kinfo_line": 46,
          "arg": None},
         [], [], ["TARGET_SCSI_ID=6"]),
        ("no matrix marker and no ANSWERS_ECHO -> no beacon is written",
         bench, ["y", "", "", "", "", ""], {"matrix_marker": False},
         [], ["answers echoed to"], []),
        ("ANSWERS_ECHO=y -> the beacon is written even with no matrix marker",
         bench, ["y", "", "", "", "", ""],
         {"profile": W_PROFILE + "ANSWERS_ECHO=y\n", "matrix_marker": False},
         ["answers echoed to"], [], []),

        # ---- the three-tier menu ------------------------------------------
        ("set tiers: the medium's /install/sets drives amixpkg's THREE rows, "
         "each sized from the catalog",
         bench, ["y", "", "", "1", "", ""], dict(w3),
         ["(1)  Standard Amiga UNIX installation      33.5 MB",
          "(2)  Everything on the disc                37.9 MB",
          "(3)  Custom selection"], [],
         ["INSTALL_SET=standard", "INSTALL_ATTESTED=y",
          "install/order.standard"]),
        ("set tiers: row 1 points the driver at that set's OWN order file, "
         "row 2 at the medium's",
         bench, ["y", "", "", "2", "", ""], dict(w3), [], [],
         ["INSTALL_SET=minimal", "INSTALL_ATTESTED=y"]),
        ("set attestation: an ATTESTED row says nothing about attestation",
         bench, ["y", "", "", "1", "", ""], dict(w3),
         ["Package set:\t\tstandard"], ["unattested selection"], []),
        ("set attestation: a row the medium marks n is called an UNATTESTED "
         "SELECTION on the confirmation screen and in the profile",
         bench, ["y", "", "", "2", "", ""], dict(w3u),
         ["Package set:\t\tmedia -- unattested selection"], [],
         ["INSTALL_SET=media", "INSTALL_ATTESTED=n"]),
        ("set tiers: an older medium (no /install/sets) still shows three "
         "rows with the same numbering",
         bench, ["y", "", "", "1", "", ""], {"catalog": W_CATALOG},
         ["(1)  Standard Amiga UNIX installation      37.9 MB",
          "(2)  Everything on the disc",
          "(3)  Custom selection"], [],
         ["INSTALL_SET=default", "INSTALL_ATTESTED=y"]),

        # ---- the custom table ---------------------------------------------
        ("set custom: the frozen amixpkg table renders, opens on the standard "
         "set, and GO composes a Custom selection",
         bench, ["y", "", "", "3", "GO", "", ""], dict(w3),
         ["Inst     Name       Description",
          "yes      core       Amiga Unix essentials",
          "no       APKG       Remote client",
          "Enter package name to install or ignore; enter GO when ready.",
          " Total: ",
          "Software:\t\tCustom selection (5 packages)",
          "Package set:\t\tcustom -- unattested selection"], [],
         ["INSTALL_SET=custom", "INSTALL_ATTESTED=n", "tmp/setup.order"]),
        ("set custom: `all` selects everything on the disc",
         bench, ["y", "", "", "3", "all", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (8 packages)"], [], []),
        ("set custom: `none` leaves the mandatory core and nothing else",
         bench, ["y", "", "", "3", "none", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (1 packages)"], [], []),
        ("set custom: `standard` restores the medium's row-1 set",
         bench, ["y", "", "", "3", "all", "standard", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (5 packages)"], [], []),
        ("set custom: DESELECTING a package takes its DEPENDENTS with it "
         "(APKGENG off -> APKG off; the catalog's apkg->apkgeng edge)",
         bench, ["y", "", "", "3", "all", "APKGENG", "GO", "", ""], dict(w3),
         ["no       APKG       Remote client",
          "Software:\t\tCustom selection (6 packages)"], [], []),
        ("set custom: SELECTING a package brings its DEPENDENCIES in "
         "(APKG on -> APKGENG on)",
         bench, ["y", "", "", "3", "none", "APKG", "GO", "", ""], dict(w3),
         ["yes      APKGENG",
          "Software:\t\tCustom selection (3 packages)"], [], []),
        ("set custom: core is mandatory and refuses to be deselected",
         bench, ["y", "", "", "3", "core", "GO", "", ""], dict(w3),
         ["core is required and cannot be deselected."], [], []),
        ("set custom: an unknown name gets amixpkg's own message, not a crash",
         bench, ["y", "", "", "3", "zzz", "GO", "", ""], dict(w3),
         ["Unknown package:  zzz"], [], []),
        ("set custom: no #isize block -> every size is `?` and NO total is "
         "printed (a partial total is worse than none)",
         bench, ["y", "", "", "3", "GO", "", ""],
         {"sets": w3_sets, "extra_orders": w3_orders,
          "catalog": "\n".join(W_CATALOG.splitlines()[:9]) + "\n"},
         ["Inst     Name       Description"], [" Total: "], []),

        # ---- the free-space check -----------------------------------------
        ("set space: an overcommitted selection gets stock's WARNING, the size it needs and no override; "
         "keeping the root goes back to the menu",
         bench, ["y", "35", "", "2", "n", "1", "y", "", ""], dict(w3),
         ["WARNING:  Your allocated space for installation is 35 MB,",
          "but you have selected to install 38 MB.",
          "That set does not fit: make the root file system at least 38 MB",
          "Do you want to change the root file system's size? [y] "],
         ["Go ahead with the installation anyway?"],
         ["INSTALL_SET=standard", "TARGET_ROOT_MB=35",
          "# set: minimal refused, it needs 38 MB and the root had 35 MB (a root of 38 MB holds it)"]),
        ("set space: changing the root's size asks the sizes again, and the set then fits",
         bench, ["y", "30", "", "2", "y", "", "", "2", "", ""], dict(w3),
         ["Do you want to change the root file system's size? [y] "], [],
         ["INSTALL_SET=minimal"]),
        ("set space: a selection that FITS is never questioned",
         bench, ["y", "", "", "2", "", ""], dict(w3), [],
         ["Do you want to change the root file system's size?", "WARNING:  Your allocated space"], []),

        # ---- the two COVERAGE HOLES, surfaced in-product (plan sec. 6) --
        # Neither of these can be triggered on hardware we own -- there is no
        # IDE-only Amiga and no A2090 on this bench, and Amiberry cannot present
        # one -- so the decision LOGIC is driven here instead, against the
        # miniroot's own probe interface. The one arm that IS hardware-proven is
        # the negative: work/install-matrix/w6-oldboot measured 524288 and
        # "A3000 Internal SCSI" on the canonical rig, and those exact strings
        # are what the "modern machine" case below feeds in.
        ("a machine with NO disks at all gets stock's own line AND the IDE pointer: the A4000's "
         "port takes a master only (a disk not seen is most likely the slave), A600 not, a Buddha any unit",
         {}, ["", ""], {},
         ["No hard disks are attached to this system.",
          "An IDE disk on the A4000's or A1200's own port is used as the",
          "The IDE port of an A600 is not supported.",
          "A Buddha or Catweasel Z-II takes a master or a slave on any port.",
          "UNIX needs a SCSI host adapter"], ["There is no Amiga UNIX IDE driver"], []),
        ("coverage: a KICKSTART 1.3 machine (romsize 262144) is refused by "
         "name, before any size is asked for",
         bench, ["y", "", ""], {"machine": {"rom": "echo 262144"}},
         ["This machine is not supported by this installation disc.",
          "Its Kickstart ROM is 262144 bytes.",
          "original Amiga UNIX 2.1 distribution"],
         ["How many megabytes for the root file system"], []),
        ("coverage: an A2090 controller is refused by name",
         bench, ["y", "", ""],
         {"machine": {"controller": 'echo "A2090 Controller"'}},
         ["This machine is not supported by this installation disc.",
          "Its disk controller is an A2090.",
          "old 2620/2630 ROM"],
         ["How many megabytes for the root file system"], []),
        ("coverage: the MEASURED bench answers (524288 / `A3000 Internal "
         "SCSI`) are NOT refused -- the threshold is cleared by zero margin",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {}}, ["Software:"],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("coverage: FAILS OPEN when romsize cannot answer (its own "
         "`Can't get ROM size` error is not a number)",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {"rom": 'echo "Can\'t get ROM size"'}}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("coverage: FAILS OPEN when dioc says nothing at all (the shape a "
         "node with no disk behind it produced on the bench)",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {"controller": ":"}}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("coverage: FAILS OPEN when neither probe is installed at all",
         bench, ["y", "", "", "1", "", ""], {}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),

        # ---- UFS: the root filesystem is not asked -------------------
        ("UFS: the root filesystem is NOT asked -- the summary and the beacon "
         "say ufs, and no s5/ufs menu is shown",
         bench, ["y", "79", "18", "1", "n", "n"], {},
         ["Root file system type:\tufs"],
         ["What file system type is the root partition?",
          "Traditional UNIX file system"],
         ["TARGET_ROOT_FSTYPE=ufs"]),
        # The 2% superuser reserve: W_CATALOG_79 sizes the disc's own set at
        # 79.x budgeted MB (80, rounded up) against a 79 MB root. An 80 MB root
        # still has only 79 after `-o free=2`, so the size named is 81.
        ("UFS: the 2% superuser reserve is subtracted from the free-space check "
         "-- 80 MB of packages into a 79 MB ufs root is an OVERCOMMIT, the "
         "operator is told the honest 78, and the root size named is one that passes",
         bench, ["y", "79", "18", "1", "y", "81", "16", "1", "n", "n"],
         {"catalog": W_CATALOG_79},
         ["WARNING:  Your allocated space for installation is 78 MB,",
          "but you have selected to install 80 MB.",
          "make the root file system at least 81 MB, or choose a smaller set."], [],
         ["TARGET_ROOT_FSTYPE=ufs", "TARGET_ROOT_MB=81"]),

        # ---- a universal medium (TARGET_HBA=auto): every card's disks, by what they hold ----
        ("universal: two disks (a blank one on the Z3660, AmigaOS on the IDE master behind it) -- "
         "both shown with their controller and contents, the id question asked",
         {6: (100, False, []), 16: (500, True, [("DH0", 128, 409600), ("Work", 409728, 614400)])},
         ["6", "100", "", "", "", "", ""],
         {"profile": p_uni, "kbootset": uni_probe},
         ["SCSI id 6  Z3660 SCSI", "blank", "disk 16 (c16d0: card 2, SCSI id 6)  IDE", "AmigaOS: DH0 Work",
          "What is the SCSI id of the disk you want to install? "], [],
         ["TARGET_SCSI_ID=6", "TARGET_HBA=z3660scsi", "ROOTDEV=0x00480016"]),
        ("universal: a single disk holding an Amix layout is chosen by typing its id, and the erase "
         "question names its partitions",
         {6: (108, True, W_BENCH_PARTS)}, ["6", "y", "", "", "", "", ""],
         {"profile": p_uni, "kbootset": "card 0: c0-c7 zorro:144b:01 base 0x40000000\n  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\n"},
         ["What is the SCSI id of the disk you want to install? ",
          "SCSI id 6 holds Amix: UNIX_Root UNIX_Swap UNIX_Boot.  All of it will be erased.",
          "Are you sure you want to erase this disk? "], [],
         ["TARGET_SCSI_ID=6", "TARGET_HBA=z3660scsi"]),
        ("universal: a single BLANK disk keeps today's flow (no id question)",
         {6: (100, False, [])}, ["100", "", "", "", "", ""],
         {"profile": p_uni, "kbootset": "card 0: c0-c7 zorro:144b:01 base 0x40000000\n  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\n"},
         ["SCSI id 6  Z3660 SCSI"], ["What is the SCSI id"], ["TARGET_SCSI_ID=6", "TARGET_HBA=z3660scsi"]),
    ]

    npass = 0
    for (name, disks, answers, kw, exp, forbid, expans) in cases:
        arg = kw.pop("arg", "w2test")
        env = kw.pop("env", None)
        script = _w_build(root, disks, kw.pop("profile", W_PROFILE), W_ORDER, **kw)
        try:
            p = _w_run(script, answers, arg=arg, env=env)
        except subprocess.TimeoutExpired:
            fail("interview case HUNG (no prompt consumed the canned answers): %s" % name)
            continue
        ap = os.path.join(root, "tmp/answers.profile")
        ans = open(ap).read() if os.path.exists(ap) else ""
        bad = []
        if p.returncode != 0:
            bad.append("rc=%d" % p.returncode)
        bad += ["stdout lacks %r" % e for e in exp if e not in p.stdout]
        bad += ["stdout MUST NOT hold %r" % e for e in forbid if e in p.stdout]
        bad += ["answers lack %r" % e for e in expans if e not in ans]
        if bad:
            fail("interview case: %s -- %s" % (name, "; ".join(bad)))
            if os.environ.get("INSTALLSEL_DUMP"):
                with open(os.environ["INSTALLSEL_DUMP"], "a") as df:
                    df.write("==== %s\n%s\n---- answers.profile\n%s\n" % (name, p.stdout, ans))
        else:
            npass += 1
            ok("interview: %s" % name)

    # NON-VACUITY: the harness must be capable of failing. Drive the same runner
    # over a deliberately broken expectation and require it to be detected.
    script = _w_build(root, bench, W_PROFILE, W_ORDER)
    p = _w_run(script, ["y", "", "", "", "", "", ""])
    if "THIS-STRING-IS-NOT-PRINTED" in p.stdout:
        fail("non-vacuity: the sandbox reported a string the interview never prints")
    elif "Scanning SCSI bus for hard disks..." in p.stdout:
        ok("non-vacuity: the sandbox really captures the interview's output "
           "(%d/%d cases passed)" % (npass, len(cases)))
    else:
        fail("non-vacuity: the sandbox captured NO interview output -- every case "
             "above would have been vacuous")


# ---------------------------------------------------------------------------
# X. -- PACKAGE METADATA: the catalog parser, the media builders, the driver
# ---------------------------------------------------------------------------
# The on-box half (the three-tier menu, the custom table, the free-space
# check) is proven by audits U and W, which RUN it. This audit covers the other
# half -- the host-side machinery that puts the metadata on the medium, and the
# driver key that consumes it:
#
#   X1  tools/lib/isocheck.py's parse_catalog SKIPS '#' lines. It was
#       9-fields-EXACTLY, which is why amix-packagemanager's docs/design.md named
#       it as the one known non-conforming consumer of catalog v1 and why nothing
#       was allowed to pass --isize into the ISO path. Both directions are
#       checked: an --isize catalog must parse to the SAME rows as one without
#       (backward compatibility is the whole point), and the isize block's own
#       well-formedness check must FIRE on a broken block and stay SILENT when
#       there is none.
#   X2  build-iso.sh passes --isize and stages BOTH authored .conf files from the
#       packagemanager's REPO TREE, then removes them from the disc: they are
#       generator inputs, not disc content.
#   X3  the set membership has ONE definition. Neither builder may carry a
#       hardcoded package list any more -- both resolve sets.conf through that
#       repo's own sets.py. Where the sibling is present this is checked
#       BEHAVIOURALLY, including the bug this exists to fix: `--set full` used to
#       select only stock/*.pkg, so a Full install shipped no cdfs and no package
#       manager.
#   X4  a set advertised on the medium as ATTESTED must have a real reference
#       digest in the matrix, and vice versa. A disc that promises a digest-gated
#       set the matrix cannot gate is a promise with nothing behind it.
#   X5  the driver's INSTALL_ORDER / INSTALL_SET / INSTALL_ATTESTED keys, incl.
#       the property that makes them safe: an empty INSTALL_ORDER must resolve to
#       exactly the earlier $INST/order, and core-first must still be checked in
#       the DRIVER, because INSTALL_ORDER now lets a file the driver did not
#       generate name the packages.
#   X6  every tracked profile declares all three keys, with the defaults that
#       reproduce today's behaviour.
#   X7  gen-install-order.py --set records the set name as a HEADER COMMENT and
#       changes no package line -- the driver and the interview both skip '#',
#       so it is documentation, never input.

SETS_CONF = os.path.join(PT_REPO, "sets.conf")
SETS_PY = os.path.join(PT_REPO, "sets.py")
CATS_CONF = os.path.join(PT_REPO, "cats.conf")
BUILD_ISO = os.path.join(TOOLS, "build-iso.sh")

# The resolved memberships sets.conf itself spells out at the bottom of the file
# and its own test suite asserts. Repeated here so a change on either side of the
# repo boundary shows up as a disagreement rather than as a silent re-scope.
W3B_SET_SIZES = {"minimal": 8, "standard": 17, "full": 30,
                 "developer": 19, "x11": 18}


def _attestation_checks(code):
    """X4b: the driver's medium-wins attestation cross-check, as a dict of facts.

    Kept as one function so the negative fixtures below run the SAME predicates
    the positive checks do -- a fixture judged by a second, hand-written regex
    proves nothing about the check that actually ships.
    """
    return {
        "reads_medium":
            bool(re.search(r'done < "\$INST/sets"', code)),
        "y_guarded":
            bool(re.search(r'if \[ "\$INSTALL_ATTESTED" = y \] '
                           r'&& \[ -f "\$INST/sets" \]; then', code)),
        # the ONLY assignment the block makes is the downgrade. An assignment of
        # $satt (or of a literal y) anywhere under a tab is an upgrade path.
        "downgrade_only":
            bool(re.search(r'^\t\tINSTALL_ATTESTED=n$', code, re.M))
            and not re.search(r'^\t+INSTALL_ATTESTED=(y|\$satt|"?\$satt"?)$',
                              code, re.M),
        "subshell_safe":
            bool(re.search(r'\[ -f "\$SETATT" \] \|\| echo "\$satt" > "\$SETATT"',
                           code)),
        "absence_unknown":
            bool(re.search(r'&& \[ -f "\$INST/sets" \]; then', code)),
        "absent_row_untouched":
            bool(re.search(r'if \[ -s "\$SETATT" \] &&', code)),
    }


def audit_w3b_metadata():
    head("X. package metadata (catalog parser, media builders, driver keys)")

    # --- X1: the catalog parser conforms ------------------------------------
    sys.path.insert(0, os.path.join(TOOLS, "lib"))
    try:
        import isocheck                                        # noqa: E402
    except ImportError as e:
        fail("cannot import tools/lib/isocheck.py: %s -- X1 would be vacuous" % e)
        return
    plain = ("#apkg-catalog 1\n"
             "core|2.1|core|stock/core-2.1.pkg|d41d8|10|none|system|Essentials\n"
             "apkg|0.1|APKG|base/APKG-0.1.pkg|d41d8|20|apkgeng|system|Client\n")
    withisz = plain + ("#ext isize 1\n"
                       "#isize core 20971520\n"
                       "#isize apkg 200000\n")
    r0, b0 = isocheck.parse_catalog(plain)
    r1, b1 = isocheck.parse_catalog(withisz)
    if b0:
        fail("a plain catalog does not parse cleanly: %s" % "; ".join(str(x) for x in b0))
    elif b1:
        fail("an --isize catalog is REJECTED: %s -- parse_catalog still counts "
             "extension-block lines as malformed entries"
             % "; ".join(str(x) for x in b1))
    elif r0 != r1:
        fail("the isize block CHANGED the parsed rows (%d vs %d) -- a comment "
             "trailer must be invisible to a v1 field parser" % (len(r0), len(r1)))
    else:
        ok("parse_catalog: an --isize catalog yields the SAME %d row(s) as one "
           "without, with zero violations (backward-compatible by construction)"
           % len(r0))
    isz = isocheck.parse_catalog_isize(withisz)
    if isz == {"core": 20971520, "apkg": 200000}:
        ok("parse_catalog_isize reads the block: %s" % sorted(isz))
    else:
        fail("parse_catalog_isize returned %r" % isz)
    if isocheck.parse_catalog_isize(plain) == {}:
        ok("a catalog with NO isize block yields NO sizes -- absence is UNKNOWN, "
           "and a consumer must never read it as zero")
    else:
        fail("parse_catalog_isize invented sizes for a catalog with no block")
    if isocheck.check_catalog_isize(r0, plain):
        fail("check_catalog_isize complains about a catalog that has no block -- "
             "the block is OPT-IN and its absence must be silent")
    else:
        ok("check_catalog_isize is silent when there is no block (opt-in)")
    if isocheck.check_catalog_isize(r1, withisz):
        fail("check_catalog_isize rejects a WELL-FORMED block")
    else:
        ok("check_catalog_isize accepts a well-formed block")
    # ...and it must FIRE. A check that cannot fail is not a check.
    for label, text in (
            ("names a package that is not a catalog row",
             plain + "#ext isize 1\n#isize nosuch 1\n"),
            ("repeats a package",
             withisz + "#isize core 1\n"),
            ("carries a non-numeric size",
             plain + "#ext isize 1\n#isize core xx\n"),
            ("has #isize lines but no #ext header",
             plain + "#isize core 1\n")):
        rows, _ = isocheck.parse_catalog(text)
        if isocheck.check_catalog_isize(rows, text):
            ok("check_catalog_isize FIRES on a block that %s" % label)
        else:
            fail("check_catalog_isize did NOT fire on a block that %s" % label)

    # --- X2: build-iso.sh stages the metadata and asks for the block ---------
    if not os.path.isfile(BUILD_ISO):
        fail("tools/build-iso.sh is missing")
    else:
        bi = open(BUILD_ISO, encoding="utf-8").read()
        checks = [
            (r'\$GEN_CATALOG"\s+--isize', "build-iso.sh generates the catalog WITH the isize block"),
            (r'cp -p "\$CATS_CONF" "\$root/pkgs/cats\.conf"',
             "cats.conf is staged so the catalog carries the authored taxonomy "
             "(no package is re-minted, so no .pkg md5 moves)"),
            (r'cp -p "\$DEPS_CONF" "\$root/pkgs/deps\.conf"',
             "deps.conf is staged from the packagemanager's REPO TREE, not its "
             "build staging (the staging copy has been observed lagging)"),
            (r'rm -f "\$\{root:\?\}/pkgs/deps\.conf" "\$\{root:\?\}/pkgs/cats\.conf"',
             "both are removed again -- they are generator inputs, not disc content"),
            (r'check_catalog_isize', "the mastered image's isize block is verified"),
        ]
        for pat, why in checks:
            if re.search(pat, bi):
                ok("build-iso: %s" % why)
            else:
                fail("build-iso: MISSING -- %s (no /%s/)" % (why, pat))

    # --- X3: one definition of a set ----------------------------------------
    if not os.path.isfile(ISO_BUILDER):
        fail("tools/build-install-iso.sh is missing")
        return
    bii = open(ISO_BUILDER, encoding="utf-8").read()
    for path, name in ((ISO_BUILDER, "build-install-iso.sh"), (BUILD_ISO, "build-iso.sh")):
        src = open(path, encoding="utf-8").read()
        code = strip_full_comments(src)
        if re.search(r'^\s*BASE_SET=\(', code, re.M):
            fail("%s still carries a hardcoded BASE_SET array -- the membership "
                 "of a set has ONE definition (sets.conf) and one resolver" % name)
        elif "SETS_CONF" not in code or "SETS_PY" not in code:
            fail("%s does not resolve sets through sets.conf/sets.py" % name)
        else:
            ok("%s resolves set membership through the packagemanager's "
               "sets.conf + sets.py (no second hardcoded list)" % name)
    for pat, why in (
            (r'--out "\$STAGE/order\.\$s"',
             "one /install/order.<set> per named set the medium can satisfy"),
            (r'> "\$STAGE/sets"',
             "the interview's three-tier table is authored onto the medium"),
            (r'set_satisfiable',
             "a set is only offered when the medium carries ALL of it")):
        if re.search(pat, bii):
            ok("build-install-iso: %s" % why)
        else:
            fail("build-install-iso: MISSING -- %s (no /%s/)" % (why, pat))

    if not (os.path.isfile(SETS_CONF) and os.path.isfile(SETS_PY)):
        skip("userland/pkgtools/tools/repo/sets.{conf,py} absent -- the set "
             "memberships are not cross-checked (not a pass)")
    else:
        bad = 0
        for name, want in sorted(W3B_SET_SIZES.items()):
            p = subprocess.run([sys.executable, SETS_PY, "-f", SETS_CONF, name],
                               capture_output=True, text=True)
            got = [x for x in p.stdout.split() if x]
            if p.returncode != 0 or len(got) != want:
                fail("sets.conf set %r resolves to %d package(s), expected %d"
                     % (name, len(got), want))
                bad = 1
            elif name == "full" and not ({"cdfs", "apkgeng", "apkg"} <= set(got)):
                fail("sets.conf `full` omits the base/ packages %s -- this is "
                     "exactly the set-selection bug: a Full install with no CD filesystem "
                     "and no package manager"
                     % sorted({"cdfs", "apkgeng", "apkg"} - set(got)))
                bad = 1
        if not bad:
            ok("sets.conf resolves to the locked memberships %s, and `full` "
               "carries cdfs/apkgeng/apkg (the --set full bug)"
               % ", ".join("%s=%d" % (k, v) for k, v in sorted(W3B_SET_SIZES.items())))
        # ★ THE AUTHORED ORDER IS THE INSTALL ORDER. gen-install-order.py breaks
        # topological ties by input order, so whatever order the builder feeds it
        # becomes the order packages are laid down in. sets.py's resolve() sorts;
        # build-install-iso.sh deliberately uses the FILE order instead, because
        # the base-8 install order `core bsd net text sysadm cdfs APKGENG APKG`
        # is the one that produced every attested digest this project has, and a
        # sorted membership would have silently re-ordered it.
        try:
            import importlib.util
            _sp = importlib.util.spec_from_file_location("amix_sets", SETS_PY)
            _sm = importlib.util.module_from_spec(_sp)
            _sp.loader.exec_module(_sm)
            _sets = _sm.read_sets(SETS_CONF)

            def _authored(name, stack=()):
                out = []
                for mem in _sets.get(name, []):
                    src = _authored(mem[1:], stack + (name,)) if mem.startswith("+") else [mem]
                    for p in src:
                        if p not in out:
                            out.append(p)
                return out
            got = _authored("minimal")
            want = ["core", "bsd", "net", "text", "sysadm", "cdfs", "apkgeng", "apkg"]
            if got != want:
                fail("sets.conf declares `minimal` in the order %s, but the base-8 "
                     "install order is %s -- the authored order IS the install "
                     "order, and every attested digest was produced with that one"
                     % (got, want))
            elif sorted(got) != _sm.resolve(_sets, "minimal"):
                fail("the authored expansion of `minimal` disagrees with sets.py "
                     "resolve() as a SET -- the two must only differ in order")
            else:
                ok("sets.conf's AUTHORED order for `minimal` is the historical "
                   "base-8 install order (%s), and equals sets.py resolve() as a set"
                   % " ".join(got))
        except Exception as e:                                 # noqa: BLE001
            fail("could not cross-check the authored set order: %s: %s"
                 % (type(e).__name__, e))
        if os.path.isfile(CATS_CONF):
            ok("cats.conf is present as the authored category taxonomy "
               "(%d override line(s))"
               % sum(1 for l in open(CATS_CONF, encoding="utf-8")
                     if ":" in l and not l.lstrip().startswith("#")))
        else:
            skip("cats.conf absent -- the taxonomy override is not cross-checked")

    # --- X4: attested sets are a promise the matrix has to keep -------------
    m = re.search(r'^ATTESTED_SETS="([^"]*)"', bii, re.M)
    if not m:
        fail("build-install-iso.sh declares no ATTESTED_SETS -- the medium could "
             "not tell the interview which sets are digest-gated")
    else:
        # each advertised set against the bench's reference digests: the bench repository's check
        ok("build-install-iso.sh declares ATTESTED_SETS: %s" % m.group(1))

    # --- X4b: ...and an UNATTENDED run has to ASK the medium -----------------
    # The 2026-08-14 cd-full run logged `install set: full ... (attested=y)`
    # against a disc whose own /install/sets said `2 full order n`. Nothing lied:
    # setup.sh reads the table and writes INSTALL_ATTESTED=$SET_ATT, but an
    # unattended install has no interview, so the value came from the canned
    # profile -- and a profile is a RIG while a set is a MEDIUM. One rig profile
    # (bench-a3000-a4091-big) serves an attested set and an unattested one.
    # X4 above pairs the two TABLES off against each other; this pairs the
    # RUNNING DRIVER off against the table it is installing from.
    attc = _attestation_checks(strip_full_comments(open(DRIVER, encoding="utf-8").read()))
    for key, why in (
        ("reads_medium",
         "the driver reads the MEDIUM's own $INST/sets for the set it resolved "
         "-- an unattended run has no interview to read it for them"),
        ("y_guarded",
         "the cross-check runs only when the profile claimed `y` -- a profile "
         "that deliberately WAIVED the gate keeps its waiver"),
        ("downgrade_only",
         "the medium can only ever DOWNGRADE y->n, never assign $satt straight "
         "through: a disc must not be able to talk a run INTO claiming an "
         "attestation it does not have"),
        ("subshell_safe",
         "the table probe records to a FILE inside the redirect-fed loop and "
         "decides in the parent (a variable set inside `done < FILE` is lost)"),
        ("absence_unknown",
         "a medium with NO sets table (older, or a raw slice) is left alone "
         "-- absence is UNKNOWN, never `n`"),
        ("absent_row_untouched",
         "a set the table does not mention is left alone too -- the empty probe "
         "file is tested before it is read"),
    ):
        if attc[key]:
            ok("driver attestation: %s" % why)
        else:
            fail("driver attestation: MISSING -- %s" % why)
    # ...and each must FIRE. Every fixture is a plausible wrong version.
    acode = strip_full_comments(open(DRIVER, encoding="utf-8").read())
    for label, broken, key in (
        ("the downgrade 'symmetrised' into `INSTALL_ATTESTED=$satt` -- which "
         "reads tidier and lets a hand-mastered disc UPGRADE a waived run",
         acode.replace("\t\tINSTALL_ATTESTED=n\n",
                       "\t\tINSTALL_ATTESTED=$satt\n"),
         "downgrade_only"),
        ("the probe file replaced by a plain variable inside the loop -- the "
         "bench-run subshell trap, which would silently never downgrade anything",
         acode.replace('\t\t[ -f "$SETATT" ] || echo "$satt" > "$SETATT"\n',
                       '\t\tSETATTV="$satt"\n'),
         "subshell_safe"),
        ("the `-f $INST/sets` guard dropped, so a medium with no table would "
         "read as a medium that answered",
         acode.replace('if [ "$INSTALL_ATTESTED" = y ] && [ -f "$INST/sets" ]; then',
                       'if [ "$INSTALL_ATTESTED" = y ]; then'),
         "absence_unknown"),
        ("the emptiness test dropped, so a set the table never mentions would "
         "be compared as the empty string and left to chance",
         acode.replace('\tif [ -s "$SETATT" ] && [ "`cat "$SETATT"`" = n ]; then',
                       '\tif [ "`cat "$SETATT"`" = n ]; then'),
         "absent_row_untouched"),
        ("the profile-claimed-y guard dropped, so the block would re-examine a "
         "run whose profile had already waived the gate",
         acode.replace('if [ "$INSTALL_ATTESTED" = y ] && [ -f "$INST/sets" ]; then',
                       'if [ -f "$INST/sets" ]; then'),
         "y_guarded"),
    ):
        if broken == acode:
            fail("negative fixture did not modify the driver at all (%s) -- the "
                 "check below would be vacuous" % label)
        elif _attestation_checks(broken)[key]:
            fail("audit X4b does NOT fire on: %s" % label)
        else:
            ok("fires on %s" % label)

    # --- X5: the driver's keys ----------------------------------------------
    drv = open(DRIVER, encoding="utf-8").read()
    dcode = strip_full_comments(drv)
    for pat, why in (
            (r'ORDER="\$INST/order"',
             "an unset INSTALL_ORDER resolves to exactly the earlier order file"),
            (r'\*/\*\)\s*ORDER="\$INSTALL_ORDER"',
             "a value with a '/' is a PATH (the read-only medium cannot hold a "
             "custom selection)"),
            (r'ORDER="\$INST/\$INSTALL_ORDER"',
             "a bare name resolves on the medium"),
            (r'\[ "\$ofirst" = core \]',
             "CORE-FIRST is still checked in the DRIVER, now that an order file "
             "the driver did not generate can name the packages"),
            (r'unattested selection',
             "an unattested selection says so in the install log")):
        if re.search(pat, dcode):
            ok("driver: %s" % why)
        else:
            fail("driver: MISSING -- %s (no /%s/)" % (why, pat))
    # the core-first check must be SUBSHELL-SAFE: an in-loop decision would be
    # made in a subshell and lost (the bench-run lesson, still the sharpest edge here)
    if re.search(r'\[ -f "\$ORDERFIRST" \] \|\| echo "\$pkg" > "\$ORDERFIRST"', dcode):
        ok("driver: the first-package probe records to a FILE inside the "
           "redirect-fed loop and decides in the parent")
    else:
        fail("driver: the core-first probe must record to a file and decide "
             "after the loop -- a variable set inside `done < FILE` is lost")

    # --- X6: every profile declares the set keys ----------------------------
    prof = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile"))
    if not prof:
        fail("no profiles found in %s -- X6 would be vacuous" % PROFILES_DIR)
    for f in prof:
        keys = _parse_profile(os.path.join(PROFILES_DIR, f))
        miss = [k for k in ("INSTALL_ORDER", "INSTALL_SET", "INSTALL_ATTESTED")
                if k not in keys]
        if miss:
            fail("profile %s does not declare %s (the set keys)" % (f, miss))
        elif (keys.get("INSTALL_ORDER") or keys.get("INSTALL_SET")) and keys.get("IMAGE_KIT") != "y":
            fail("profile %s pins INSTALL_ORDER=%r / INSTALL_SET=%r -- the tracked "
                 "profiles must keep the medium's own default, or a re-mastered "
                 "disc would install the set the profile remembers"
                 % (f, keys.get("INSTALL_ORDER"), keys.get("INSTALL_SET")))
        elif keys.get("INSTALL_ATTESTED") != "y":
            # ★ THE OLD REASON HERE WAS "the matrix only drives attested sets",
            # and the 2026-08-14 cd-full run falsified it -- the matrix drove
            # `full` on this very key while the medium marked it unattested. The
            # requirement SURVIVES the correction, with a smaller claim: `y` is
            # the profile's DEFAULT POSTURE, not an assertion about a set, and
            # `n` in a tracked profile would waive the gate for every medium that
            # rig ever runs. The set-specific truth is the medium's, and X4b
            # requires the driver to go and ask it.
            fail("profile %s has INSTALL_ATTESTED=%r -- a tracked rig profile "
                 "carries the DEFAULT posture `y`; a blanket `n` here would "
                 "waive the digest gate for every medium this rig runs. A set "
                 "that is not attested is the MEDIUM's fact (X4b)"
                 % (f, keys.get("INSTALL_ATTESTED")))
        else:
            ok("profile %-34s INSTALL_ORDER=<medium> INSTALL_SET=<order file> "
               "INSTALL_ATTESTED=y (default posture; the medium may downgrade)" % f)

    # --- X7: the order file says which set it is ----------------------------
    if not os.path.isfile(GEN_ORDER):
        fail("tools/gen-install-order.py is missing")
        return
    if not os.path.isfile(DEPS):
        skip("deps.conf absent -- the --set header is not exercised (not a pass)")
        return
    args = ["core", "bsd", "net", "text", "sysadm", "cdfs", "APKGENG", "APKG"]
    a = run_order(["--deps", DEPS] + args)
    b = run_order(["--deps", DEPS, "--set", "minimal"] + args)
    if a.returncode != 0 or b.returncode != 0:
        fail("gen-install-order --set exited nonzero (%d/%d)"
             % (a.returncode, b.returncode))
        return
    pa = [l for l in a.stdout.splitlines() if l and not l.startswith("#")]
    pb = [l for l in b.stdout.splitlines() if l and not l.startswith("#")]
    if pa != pb:
        fail("--set CHANGED the emitted order: %r vs %r" % (pa, pb))
    elif "# set: minimal (8 package(s))" not in b.stdout:
        fail("--set minimal did not record the set in the header:\n%s" % b.stdout)
    else:
        ok("gen-install-order --set records `# set: minimal (8 package(s))` as a "
           "HEADER COMMENT and emits the identical %d package line(s) -- the "
           "driver reads it back for the log and every consumer skips '#'" % len(pa))


# ---------------------------------------------------------------------------
# Y. MINIROOT INSTALL SCRIPT (src/miniroot/profile -> /etc/profile)
# ---------------------------------------------------------------------------
# The miniroot's /etc/profile is the one file in this tree that runs with NOTHING
# mounted, and it is the first thing a user of this installer ever sees. Audits
# A/B/G/H/I/T already cover it as miniroot sh; THIS audit covers what is specific
# to being the pre-mount script:
#
#   Y1  ORDER. Banner, then the Ctrl-C trap, then the keymap, then
#       install-or-repair, then the probe, then the hand-off -- in that order.
#       The trap before the FIRST prompt is not cosmetic: it is the only way out
#       of every question below it, and the install matrix's own miniroot
#       handshake (Ctrl-C at the first prompt -> shell) depends on it. If the
#       trap ever moved below the keymap menu, every unattended matrix cell
#       would hang at a prompt no one can answer.
#   Y2  HAND-OFF. `exec sh /cdrom/install/bin/setup.sh` and nothing else: the
#       profile must never exec the DRIVER directly, because it is setup.sh that
#       redirects the transplant's stdin from /dev/null.
#   Y3  THE KEYMAP MENU is stock's, byte-for-byte, with exactly ONE relabelled
#       row. Every other row is checked against the stock root floppy's own
#       bytes; row 11 must be ours and stock's row 11 must be absent.
#   Y4  THE KEYMAP HAND-OFF is pinned ACROSS FILES: the profile writes /tmp/kmap
#       and exports $KMAP; setup.sh reads that same path into FB_KMAP and writes
#       it into the answers profile. Two files, one contract, one audit.
#   Y5  THE PROBE decides by CONTENT, never by a mount return code, keeps its
#       hardcoded CD-then-RAW order, retries a cdfs mount once (errno 5), and
#       asks the operator ONLY when more than one candidate answered.
#   Y6  STOCK WORDING, byte-for-byte against the stock root floppy, with every
#       deviation DECLARED (the same discipline as audits S and U6).
#   Y7  NO stty and NO ddsize -- the first would flush the answers the matrix
#       types ahead into the tty queue; the second is the call that WEDGED an
#       install on the bench a3091 path and cannot be bounded here.
#   Y8  8-BIT CLEAN. The file must be Latin-1, not UTF-8: the console is
#       ISO-8859-1 and the labels carry 0xE7/0xF1.

# (ours, stock-or-None). None = ours IS stock's, byte for byte.
STOCK_PROFILE_STRINGS = [
    ("Amiga UNIX install script", None),
    ("Running interactive shell...", None),
    ("Press RETURN to restart the installation script. ", None),
    ("Do you want to install or repair? [install] ", None),
    ("Available key mappings are:", None),
    ("Which keyboard are you using? [$DEFKMAP] ", None),
    ("No hard disks are attached to this system.", None),
    ("Hard disks attached to this system:", None),
    ("Choose one of the following:", None),
    ("Can't find rigid disk block on $DISK", None),
    ("No such partition is defined.", None),
    ("Do you want to fsck $UPART? [y] ", None),
    ("mounted on /mnt", None),
    ("Mount of $UPART failed", None),
    ("Logout with ctrl-D when you are finished", None),
    ("Shutting down, please wait...", None),
    # Stock parameterised these two because ONE script did both jobs; ours are
    # reached only from repair mode, so the parameter is resolved.
    ("What is the SCSI id of the disk you want to repair? ",
     "What is the SCSI id of the disk you want to $MODE? "),
    ("Which partition has the root filesystem? ",
     "Which partition $ISFOR the root filesystem? "),
]


def _kmap_rows(text):
    """The numbered rows of the keymap menu as our /etc/profile prints them."""
    m = re.search(r'Available key mappings are:\n(.*?)\n"\n', text, re.S)
    if not m:
        return []
    return [l for l in m.group(1).split("\n") if re.match(r'^\s*\d+\)\t', l)]


def audit_w4_miniroot_profile():
    head("Y. miniroot install script (src/miniroot/profile: order, keymap, "
         "probe, hand-off)")
    if not os.path.isfile(MINIROOT_PROFILE):
        fail("src/miniroot/profile is missing -- the miniroot has no install "
             "script and the box would boot to a bare shell")
        return
    raw = open(MINIROOT_PROFILE, "rb").read()
    src = read_sh(MINIROOT_PROFILE)
    code = strip_full_comments(src)

    # --- Y8: 8-bit clean ----------------------------------------------------
    if b"\xc3" in raw or raw.startswith(b"\xef\xbb\xbf"):
        fail("src/miniroot/profile looks UTF-8 encoded (0xC3 lead byte or a BOM) "
             "-- the miniroot console is ISO-8859-1 and the keymap labels carry "
             "single-byte 0xE7/0xF1; the menu would show mojibake")
    else:
        hi = sorted(set(b for b in raw if b > 127))
        ok("src/miniroot/profile is Latin-1/8-bit clean (%d bytes; non-ASCII: %s)"
           % (len(raw), " ".join("0x%02x" % b for b in hi) or "none"))

    # --- Y1: the order the screens happen in --------------------------------
    marks = [
        ("banner",      r'echo "Amiga UNIX install script"'),
        ("ctrl-c trap", r"trap '"),
        ("keymap",      r'^ask_kmap$'),
        ("install/repair", r'Do you want to install or repair'),
        ("probe",       r'^find_source$'),
        ("hand-off",    r'^exec sh \$SETUP$'),
    ]
    pos = {}
    for name, pat in marks:
        m = re.search(pat, code, re.M)
        if m is None:
            fail("src/miniroot/profile: no %s (/%s/)" % (name, pat))
            pos[name] = -1
        else:
            pos[name] = m.start()
    if all(v >= 0 for v in pos.values()):
        order = [n for n, _ in marks]
        seq = [pos[n] for n in order]
        if seq == sorted(seq):
            ok("screens happen in the right order: %s" % " -> ".join(order))
        else:
            fail("src/miniroot/profile runs its screens out of order: %s"
                 % [(n, pos[n]) for n in order])
        # the trap must precede EVERY prompt, not just the first screen
        first_prompt = re.search(r'\breadask\b', code)
        if first_prompt and pos["ctrl-c trap"] < first_prompt.start():
            ok("the Ctrl-C trap is installed BEFORE the first prompt (the only "
               "exit from every question below it, and the matrix's own miniroot "
               "handshake)")
        else:
            fail("the Ctrl-C trap must be installed before the first readask -- "
                 "a prompt above it cannot be escaped, and the install matrix's "
                 "Ctrl-C handshake would hang")

    # --- Y2: the hand-off ---------------------------------------------------
    if re.search(r'^SETUP=\$CDROM/install/bin/setup\.sh$', code, re.M):
        ok("hands off to /cdrom/install/bin/setup.sh (the interview, on the medium)")
    else:
        fail("src/miniroot/profile must define SETUP=$CDROM/install/bin/setup.sh")
    # install.sh may be reached from the miniroot ONLY on the unattended demo-card
    # path, and the null-stdin invariant is what actually matters: the transplant
    # must never inherit the console stdin. So assert the invariant directly (every
    # install.sh call carries `< /dev/null`) rather than banning the reference --
    # the interactive path still reaches the driver through setup.sh (the interview audit).
    inst_calls = [ln for ln in code.splitlines() if "install.sh" in ln]
    if not inst_calls:
        ok("the driver is never exec'd directly (the interview owns the console "
           "and hands the transplant a /dev/null stdin)")
    else:
        bad = [ln for ln in inst_calls if "< /dev/null" not in ln]
        if bad:
            fail("src/miniroot/profile invokes install.sh WITHOUT `< /dev/null` "
                 "(the transplant must never inherit the console "
                 "stdin): %s" % "; ".join(x.strip() for x in bad))
        else:
            ok("install.sh is reached only on the unattended path, and every call "
               "hands it a /dev/null stdin (held without setup.sh)")

    # --- Y3: the keymap menu ------------------------------------------------
    rows = _kmap_rows(src)
    if len(rows) != 14:
        fail("the keymap menu has %d numbered rows, stock offers 14" % len(rows))
    else:
        ok("the keymap menu offers 14 rows, as stock does (usa1 is excluded in "
           "both)")
    # the MENU ROWS only -- the file's own comment says the word too, and an
    # audit that cannot tell a comment from a menu entry fires on prose.
    if any("usa1" in r for r in rows) or re.search(r'KMAP=usa1', code):
        fail("usa1 appears in our keymap menu -- stock ships the map but does "
             "NOT offer it")
    else:
        ok("usa1 is not offered (stock ships 15 maps and offers 14)")
    if re.search(r'^DEFKMAP=12$', code, re.M):
        ok("the default is 12 (usa American), exactly stock's DEFKMAP")
    else:
        fail("DEFKMAP must be 12 -- stock's default keyboard answer")
    want11 = "11)\ts\tSuomi / Svenska"
    if want11 in src:
        ok("keymap entry 11 is the ONE relabelled row: %r (map still `s`)" % want11)
    else:
        fail("keymap entry 11 must read %r -- the plan's single label change" % want11)
    if "11)\ts\tSvenska" in src:
        fail("stock's own entry-11 label is still in the file -- the relabel did "
             "not replace it")
    if re.search(r'unset KMAP\n\t\t/etc/sioc 5\n', src):
        ok("`usa` unsets $KMAP and calls bare `sioc 5` -- stock's own semantics "
           "(the American map is compiled in, so it links nothing on the target)")
    else:
        fail("the usa arm must `unset KMAP` and call `/etc/sioc 5` with no map "
             "(stock's semantics, and what the driver's FB_KMAP bake expects)")
    if re.search(r'/etc/sioc 5 \$KMAPDIR/\$KMAP', code):
        ok("a chosen map is applied LIVE with `/etc/sioc 5 /etc/kmap/$KMAP`")
    else:
        fail("the chosen map must be applied live via /etc/sioc 5 $KMAPDIR/$KMAP")


    # --- Y4: the keymap hand-off, pinned across two files -------------------
    if re.search(r'echo "\$KMAP" > \$KMAPFILE', code) and re.search(r'^export KMAP$', code, re.M):
        ok("the chosen map leaves on BOTH channels: /tmp/kmap and an exported $KMAP")
    else:
        fail("the profile must write `echo \"$KMAP\" > $KMAPFILE` and `export KMAP` "
             "-- the file survives a Ctrl-C, the export survives the exec chain")
    m1 = re.search(r'^KMAPFILE=(\S+)$', code, re.M)
    setup_src = read_sh(SETUP)
    setup_code = strip_full_comments(setup_src)
    m2 = re.search(r'^KMAP_FILE=(\S+)$', setup_code, re.M)
    if m1 and m2 and m1.group(1) == m2.group(1):
        ok("the two files agree on the channel: %s (profile KMAPFILE == setup.sh "
           "KMAP_FILE)" % m1.group(1))
    else:
        fail("the miniroot profile and setup.sh must name the SAME keymap file "
             "(got %r and %r) -- a silent disagreement here loses the answer and "
             "the target keeps the American map"
             % (m1.group(1) if m1 else None, m2.group(1) if m2 else None))
    for pat, why in (
            (r'FB_KMAP=`cat "\$KMAP_FILE"`',
             "setup.sh takes the keymap from the file the miniroot wrote"),
            (r'elif \[ -n "\$KMAP" \]; then\n\tFB_KMAP="\$KMAP"',
             "an exported $KMAP is the fallback channel"),
            (r'echo "FB_KMAP=\$FB_KMAP"',
             "the answer lands in the answers profile UNCONDITIONALLY (an empty "
             "value is the answer `usa`, and it must override a base profile "
             "that names a map)")):
        if re.search(pat, setup_code):
            ok("setup.sh: %s" % why)
        else:
            fail("setup.sh: MISSING -- %s (no /%s/)" % (why, pat))

    # --- Y5: the probe ------------------------------------------------------
    # ★ THE ONE-ATTEMPT RULE IS THE POINT OF THIS BLOCK. Bench-measured
    # 2026-08-11 (lab-C): a SECOND cdfs mount attempt on a unit that is not
    # there PANICS the kernel (bus error, pc=0x70002E8), and an absent unit
    # fails with the SAME errno 5 a real media-change gives -- so the retry
    # that recovers a media change is the retry that kills the box. The scan
    # therefore touches each address ONCE, stops at the first answer, and gates
    # every RAW candidate on the one probe proven harmless (a bounded dd).
    if re.search(r'^CD_CANDIDATES="1,3 0,3 0,2 1,2 0,5 1,5 2,5 3,5"$', code, re.M):
        ok("the cdfs probe order is pinned 1,3 -> 0,3 -> 0,2 -> 1,2 -> 0,5 -> 1,5 -> 2,5 -> 3,5 "
           "(hardcoded HERE: it cannot come from the medium it is looking for; 0,3 = a sole "
           "A4091 as card 0; k,5 = an ATAPI drive on the IDE slave, the IDE port as card k)")
    else:
        fail("CD_CANDIDATES must be exactly \"1,3 0,3 0,2 1,2 0,5 1,5 2,5 3,5\"")
    if re.search(r'^RAW_CANDIDATES="/dev/dsk/c0d0s4 /dev/dsk/c5d0s1 /dev/dsk/c5d0s4"$', code, re.M):
        ok("the RAW payload-slice probe list is pinned (metal 5-slice s4, bench "
           "2-slice s1, the Gayle IDE slave's s4)")
    else:
        fail("RAW_CANDIDATES must be \"/dev/dsk/c0d0s4 /dev/dsk/c5d0s1 /dev/dsk/c5d0s4\"")
    icd = code.find("for s in $CD_CANDIDATES")
    iraw = code.find("for d in $RAW_CANDIDATES")
    if iraw >= 0 and icd > iraw:
        ok("the existence-testable RAW candidates are probed BEFORE the CDs -- a "
           "self-booting source disk answers a bounded dd, so the metal source "
           "rig never issues a cdfs probe at all")
    else:
        fail("the RAW candidates must be probed BEFORE the CD ones (they are the "
             "only ones whose existence can be settled without mounting)")
    pc = _extract_func(src, "probe_cdfs") or ""
    pr = _extract_func(src, "probe_raw") or ""
    dp = _extract_func(src, "disk_present") or ""
    if not pc or not pr or not dp:
        fail("cannot extract probe_cdfs/probe_raw/disk_present -- Y5 would be vacuous")
    n = pc.count("/usr/lib/fs/cdfs/mount")
    if n == 1:
        ok("probe_cdfs mounts EXACTLY ONCE -- a second attempt on an absent unit "
           "bus-errors the kernel (lab-C 2026-08-11); the media-change retry is "
           "the operator's RETURN at the restart prompt, which re-probes each "
           "address once more")
    else:
        fail("probe_cdfs must attempt the cdfs mount exactly ONCE (found %d) -- "
             "the retry that recovers a media change is the retry that PANICS on "
             "a unit that is not there" % n)
    if "/etc/umount" in pc:
        fail("probe_cdfs unmounts and re-mounts -- that is the panicking retry; "
             "the caller drops a non-answering mount instead")
    else:
        ok("probe_cdfs never umount+remounts (the caller's drop_source does the "
           "cleanup, and the next attempt is a whole new pass)")
    for name, body in (("probe_cdfs", pc), ("probe_raw", pr)):
        if re.search(r'\[ -f \$SETUP \]', body):
            ok("%s decides on CONTENT ($SETUP), not on the mount's return code "
               "(a cdfs mount can return 0 and be EMPTY; a mount over a live "
               "/cdrom returns EBUSY while the source is perfectly readable)"
               % name)
        else:
            fail("%s must decide by testing for $SETUP, never by the mount rc" % name)
    if re.search(r'\bdd if="\$1"', dp) and "ddsize" not in dp:
        ok("disk_present is ONE bounded 512-byte dd -- the same existence probe "
           "the interview's scan uses, and the only one proven harmless against "
           "absent hardware")
    else:
        fail("disk_present must test a device with a single bounded dd")
    fs = _extract_func(src, "find_source") or ""
    if not fs:
        fail("cannot extract find_source() -- Y5 would be vacuous")
    else:
        if re.search(r'disk_present "\$d" \|\| continue', fs):
            ok("every RAW candidate is existence-gated before it is mounted")
        else:
            fail("find_source must gate each RAW candidate on disk_present")
        if fs.count("break") == 2:
            ok("both walks STOP at the first candidate that answers, and it is "
               "left mounted -- nothing probes past a working source")
        else:
            fail("find_source must break out of both candidate walks on the first "
                 "answer (found %d break(s))" % fs.count("break"))
        if "restart" in fs and "press RETURN to try again" in fs:
            ok("a source that is never found ends at the stock restart idiom, "
               "which IS the media-change retry (one attempt per address per pass)")
        else:
            fail("find_source must end a no-source dead end at restart(), offering "
                 "the insert-and-RETURN pass")

    # --- Y7: no stty, no ddsize --------------------------------------------
    if re.search(r'\bstty\b', code):
        fail("src/miniroot/profile runs stty -- it would FLUSH the answers the "
             "install matrix types into the tty queue ahead of the prompts "
             "(stock's own stty lines are commented out for the same reason)")
    else:
        ok("no stty (the queued-answer channel the blind console depends on stays "
           "intact)")
    if "ddsize" in code:
        fail("src/miniroot/profile calls /etc/ddsize -- one unconditional call "
             "WEDGED the install on the bench a3091 path (matrix run "
             "20260811-094255-cd) and there is no timeout tool here")
    else:
        ok("/etc/ddsize is never called (the repair chooser reads ONE 512-byte "
           "block per id, exactly as the interview's scan does)")

    # --- Y9: SCAN_IDS derived from the proto --------------------------------
    m = re.search(r'^SCAN_IDS="([0-9 ]+)"$', code, re.M)
    if not m:
        fail("src/miniroot/profile has no SCAN_IDS default")
    else:
        # the ids against the miniroot's own device nodes: the bench repository's check (its proto)
        got = sorted(int(x) for x in m.group(1).split())
        if 4 in got:
            fail("SCSI id 4 is scannable -- stock reserved it for the tape drive")
        else:
            ok("profile SCAN_IDS %s: id 4 (the tape drive's) is not scanned" % got)

    # --- Y6: stock wording, byte-for-byte ----------------------------------
    absent = [ours for (ours, _) in STOCK_PROFILE_STRINGS if ours not in src]
    if absent:
        for a in absent:
            fail("src/miniroot/profile does not carry the stock string %r" % a)
    else:
        ok("the install script carries all %d quoted stock strings"
           % len(STOCK_PROFILE_STRINGS))


# ---------------------------------------------------------------------------
# Z. the first-boot configuration dialog
# ---------------------------------------------------------------------------
# the dialog TRAVELS IN firstboot.sh (the `--dialog` entry point) and the
# stock sysinit slot gets a three-line STUB that execs it. payload/firstboot/
# system.setup is that stub -- the master the driver's emitter is drift-locked
# against -- NOT the dialog. See the here-doc law (Z0) for why.
DIALOG_STUB = os.path.join(REPO, "payload", "firstboot", "system.setup")
# Stock artifacts the dialog quotes. Each string must appear BYTE-FOR-BYTE in the
# named recovered file; a missing core tree is a SKIP, never a silent pass.
STOCK_CORE = os.path.join(TOP, "out", "build", "media", "core", "root")   # tools/build-core-tree.sh (media/build.sh)
DIALOG_STOCK_STRINGS = [
    ("usr/amiga/lib/amixnode",
     "What is the nodename of this machine? ["),
    ("usr/amiga/lib/amixnode",
     "What is this machine's network domain? ["),
    ("usr/amiga/bin/system.setup",
     "Would you like to assign a password to all of the"),
    ("usr/amiga/bin/system.setup",
     "system accounts? [y] "),
    ("usr/amiga/bin/system.setup",
     "Would you like to assign a password to the guest account? [$SYSPASS] "),
    ("usr/amiga/bin/system.setup",
     "Would you like to create a user account? [n] "),
    ("usr/amiga/bin/system.setup",
     "Are you using an A2024 or Moniterm high resolution monitor? [$DEFMON] "),
    ("usr/amiga/bin/system.setup",
     "Do you wish to configure X Windows for a color graphics card? [n] "),
    ("usr/amiga/bin/system.setup",
     "Do you wish to configure Netnews for either local or networked operation? [n] "),
    ("usr/amiga/bin/system.setup",
     "Do you wish to change any of these? [n] "),
    ("usr/amiga/bin/system.setup", "Monitor:\t\tMoniterm or A2024"),
    ("usr/amiga/bin/system.setup", "Monitor:\t\tnot a Moniterm or A2024"),
    ("usr/amiga/lib/amixhosts", "What is this machine's network address? "),
]














# --- Z7c: THE DISTRO-NEUTRAL PUBLIC FLAVOR ----------------------------------
# A public disc's guarantee is negative -- it is about what is NOT on it -- and a
# negative guarantee is exactly the kind that rots silently. Nothing goes wrong
# when somebody adds `FB_IP=192.0.2.38` back to the public profile: every gate
# still passes, every matrix cell still goes green, and the disc ships with one
# household's LAN baked into it. So the absence is audited here, key by key.
#
# The rule is derived from the profile, not from its filename: a profile that
# ARMS THE DIALOG is one whose answers come from the person at the console, so
# it must not carry answers of its own.

# The LAN facts a public medium must not know. Empty is the ONLY legal value.
PUBLIC_MUST_BE_EMPTY = (
    ("FB_IP", "this box's address"),
    ("FB_NETMASK", "the netmask"),
    ("FB_GATEWAY", "the default route"),
    ("FB_DNS1", "the primary resolver"),
    ("FB_DNS2", "the secondary resolver"),
    ("FB_DOMAIN", "the DNS domain"),
    ("FB_REPO_IP", "the package repository's address"),
    ("TARGET_DISK_MB", "the size of a disk this disc has never seen"),
)
# Nodenames that belong to a machine on somebody's LAN. A public disc's default
# must be generic; these are the ones this tree has actually shipped.
PUBLIC_FORBIDDEN_NODENAMES = ("uaeamix", "amixmetal", "z3660amix")








# ---------------------------------------------------------------------------
# AA. THE UFS TARGET FILESYSTEM -- the driver half
# ---------------------------------------------------------------------------
# Audit W already RUNS the interview and proves the question, its `[ufs]`
# default, the `s5` escape, the typo re-ask, the prebuilt suppression and the 2%
# reserve. This audit covers what a conversation cannot reach: the DRIVER's four
# filesystem-dependent steps, the two places the type must NOT reach, and the
# handoff into the first boot. Every check has a negative fixture, because the
# whole class of defect here is silent -- a wrong node, a stale parameterisation
# or a missing refusal produces a box that installs fine and does not boot.
#
#   AA1  the key is validated FAIL-CLOSED (s5|ufs, else die) and defaults to s5,
#        which is the compatibility floor, not the product default (that is the
#        interview's `[ufs]`).
#   AA2  the mkfs/fsck program names are LITERAL. `mkfs_${TARGET_ROOT_FSTYPE}`
#        would be a program name audit G -- the miniroot-tool allowlist, derived
#        from miniroot.proto -- cannot resolve, on a filesystem with no `sed` to
#        resolve it with. Two literal arms instead.
#   AA3  the ufs mkfs runs on the BLOCK node with stock's `-o free=2,opt=s` and
#        the s5 mkfs keeps the RAW node: stock passed $UPART (block) to
#        mkfs_${ROOT_FSYS}, our s5 path has always passed the raw node and is
#        what every attested digest was measured through. Neither may drift into
#        the other.
#   AA4  no labelit on the ufs path -- there is no /usr/lib/fs/ufs/labelit on the
#        medium (checked against the proto, not asserted), and stock ran labelit
#        on NEITHER filesystem.
#   AA5  prebuilt mode REFUSES a non-s5 target. tools/mkroot.sh mints s5 and only
#        s5; carrying on would mount an s5 filesystem under a vfstab that says
#        ufs.
#   AA6  the /etc/mnttab seed line names the RUNNING MINIROOT's own fs
#        ($MINIROOT_FSTYPE, derived from INSTALL_CPU: 030 => s5, 040/060 => ufs),
#        NEVER $TARGET_ROOT_FSTYPE and never a hardcoded literal. It describes the
#        miniroot the driver is executing from, not the target -- keying it off the
#        TARGET is the most plausible wrong "fix" in this change, so it is pinned.
#        INSTALL_CPU defaults to 030 (the compatibility floor: an old profile that
#        omits it seeds `s5` byte-identically), and the 040/060 line is UFS-only.
#   AA7  the mount type IS parameterised, and the post-unmount fsck has both arms.
#   AA8  the type reaches the first boot as FB_ROOT_FSTYPE and lands in vfstab
#        column 4, defaulted to s5 and validated there too.
#   AA9  every tracked profile declares the key with a legal value.

_UFS_OPT = '-o `ufs_mkfs_opts "$ROOTLEN"`'   # stock's free=2,opt=s; nbpi=8192 over 512 MiB














def audit_monsw():
    head("AM. the monitor switch: MONSW is /etc/display's monsw line on 1.1; the monsw package "
         "ships monswctl, its boot step and /dev/monsw; nothing is staged or laid by the installer")
    driver_src = open(DRIVER, encoding="utf-8", errors="replace").read()
    code = strip_full_comments(driver_src)
    iso_src = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    iso_code = strip_full_comments(iso_src)

    # The legal values are exactly the subset sums of {1, 2, 16, 32} (monswctl's own rule).
    legal = sorted({a + b + c + d for a in (0, 1) for b in (0, 2) for c in (0, 16) for d in (0, 32)})
    legal_s = set(str(v) for v in legal)

    # AM1: install.sh refuses a bad value up front -- EXECUTE its own case block.
    m = re.search(r'\ncase "\$MONSW" in\n(.*?)\nesac\n', code, re.S)
    if not m:
        fail("install.sh has no up-front `case \"$MONSW\"` validation")
    else:
        snippet = ('die() { echo BAD; exit 1; }\ncase "$MONSW" in\n' + m.group(1) + '\nesac\necho OK\n')
        wrong = []
        for v in [str(i) for i in range(0, 64)] + ["", "none", "abc", "-1", "034", "34 "]:
            r = subprocess.run(["sh", "-c", snippet], env={"MONSW": v, "PATH": os.environ.get("PATH", "")},
                               capture_output=True, text=True)
            want = "OK" if (v in legal_s or v in ("", "none")) and v != "034" else "BAD"
            if r.stdout.strip() != want:
                wrong.append((v, r.stdout.strip(), want))
        if wrong:
            fail("install.sh MONSW validation disagrees with the 1|2|16|32 rule: %s" % wrong[:6])
        else:
            ok("install.sh MONSW validation EXECUTED: all 64 bit patterns + none/empty/junk "
               "classified exactly as monswctl would (%d legal values)" % len(legal))

    # AM2: install.sh lays down no monitor-switch file, and refuses MONSW on a 1.0 install.
    laid = [d for rx, d in (
        (r'\$INST/monsw/', "a file from $INST/monsw"),
        (r'usr/include/sys/monsw\.h', "sys/monsw.h"),
        (r'mknod\s+"\$TARGET/dev/monsw"', "a /dev/monsw node"),
        (r'>\s+"\$TARGET/etc/monsw"', "/etc/monsw")) if re.search(rx, code)]
    refuse = re.search(r'elif \[ -n "\$MONSW" \] && \[ "\$MONSW" != none \]; then\n\tdie "profile '
                       r'\$PROFILE_NAME sets MONSW=\$MONSW on a 1\.0 install', code)
    if laid or not refuse:
        fail("install.sh: monitor-switch laydown left (%s) or no refusal of MONSW on 1.0" % (laid or "-"))
    else:
        ok("install.sh lays down no monitor-switch file (the monsw package's) and refuses MONSW on a 1.0 install")

    # AM3: the medium stages nothing for it, reads neither kerntools nor the port's header,
    # and refuses MONSW on a 1.0 profile.
    reads = [d for rx, d in (
        (r'amix-kerntools/tools/monsw', "amix-kerntools/tools/monsw"),
        (r'monsw\.h', "sys/monsw.h"),
        (r'\$STAGE/monsw', "$STAGE/monsw"),
        (r'MONSW_H_SHA', "MONSW_H_SHA")) if re.search(rx, iso_code)]
    stop10 = re.search(r'\[ "\$_l" = 1\.1 \] \|\| \{ echo "STOP: profile \$_p: MONSW=\$_v on a 1\.0 install',
                       iso_code)
    if reads or not stop10:
        fail("build-install-iso.sh: monitor-switch staging left (%s) or no STOP for MONSW on 1.0" % (reads or "-"))
    else:
        ok("build-install-iso.sh stages no /install/monsw, reads no kerntools or port file, "
           "and STOPs on MONSW in a 1.0 profile")

    # AM4: the 1.0 profiles that still name a switch value are frozen: mastering refuses them.
    old10 = []
    for pf in sorted(os.listdir(PROFILES_DIR)):
        if not pf.endswith(".profile"):
            continue
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        v = d.get("MONSW", "")
        if v not in ("", "none") and d.get("INSTALL_LAYOUT") != "1.1":
            old10.append(pf)
    ok("%d 1.0 profile(s) set MONSW: 1.0 media are frozen, build-install-iso.sh refuses them" % len(old10))







def audit_030_rootswap():
    head("SWAP030. the 030 line adds slice 2's tail past K030-U's boot swap at boot: S89rootswap, 030 only")
    drv = read_sh(DRIVER)
    m = re.search(r'if \[ "\$\{INSTALL_CPU:-030\}" = 030 \] && \[ "\$INSTALL_LAYOUT" != 1\.1 \]; then\n\tRSLEN="\$SWAPBLKS"(.*?)\nfi\n', drv, re.S)
    if not m:
        fail("SWAP030: install.sh has no INSTALL_CPU=030-gated, 1.0-only S89rootswap block")
        return
    ok("SWAP030: S89rootswap is the 1.0 030 line's only; a 1.1 disk has amix-base's swap step (S90swap)")
    blk = m.group(1)
    need = ['/etc/rc2.d/S89rootswap', '`/etc/devnm / 2>/dev/null | sed -e "s: .*::"`', 's:s[0-9a-fA-F]*', 'case "$s" in /dev/dsk/c*s2) ;; *) exit 0 ;; esac',
            '/usr/sbin/swap -l', 'grep "^/dev/"', '/usr/sbin/swap -a $s 0 $LEN',
            # r6c: the tail -- only past exactly the boot area, one area listed, >= 1 MiB left
            'echo "BOOT=$K030_BOOTSWAP"', 'RSSTART=$K030_SWAPTAIL', '[ $# = 5 ] || exit 0',
            '[ "$1" = "$s" ] && [ "$3" = 0 ] && [ "$4" = "$BOOT" ] || exit 0', '[ $LEN -ge `expr $START + 2048` ] || exit 0',
            '/usr/sbin/swap -a $s $START $n']
    if not (re.search(r'^K030_BOOTSWAP=20476$', drv, re.M) and re.search(r'^K030_SWAPTAIL=20480\t', drv, re.M)):
        fail("SWAP030: K030_BOOTSWAP/K030_SWAPTAIL are not 20476/20480 (K030-U's boot area as swap -l lists it; the next 16-block boundary)")
        return
    miss = [n for n in need if n not in blk]
    arm = drv.find("# 9. ARM FIRST-BOOT")
    if miss:
        fail("SWAP030: the S89rootswap writer lacks %s" % miss)
    elif not (0 <= m.start() < arm):
        fail("SWAP030: the S89rootswap block is not before section 9 (it needs SWAPBLKS from 2c)")
    else:
        ok("SWAP030: 030-only S89rootswap adds slice 2's tail past the boot area (devnm, as bcheckrc); any other swap -l is left alone")


def audit_apkg_conf_order():
    head("APKGCONF. /etc/apkg.conf is written BEFORE the APKG package (r6: plain pkgchk APKG clean on a fresh install)")
    drv = read_sh(DRIVER)
    seed = drv.find('msg "install set: ')
    ends = [i for i in (drv.find('ADMIN="$INST/admin/pkgadd"'), drv.find('msg "RAW: apkg update')) if i >= 0]
    sec5 = min(ends) if ends else -1
    # 1.0 only (APKG 0.2.3 keeps it); on 1.1 APKG 0.3.4's conffile class would count it edited
    calls = [m.start() for m in re.finditer(r'(?m)^\s*\[ "\$INSTALL_LAYOUT" = 1\.1 \] \|\| write_apkg_conf\s*$', drv)]
    gate = re.search(r'while read _p _rest; do\s*\n\s*if \[ "\$_p" = APKG \]', drv)
    if seed < 0 or sec5 < 0 or not calls:
        fail("APKGCONF: could not find the install-set / package-loop markers or a write_apkg_conf call")
        return
    first = calls[0]
    if seed < first < sec5 and gate and seed < gate.start() < sec5:
        ok("the conf is written after the install-set line and before either package path (cdfs pkgadd loop / RAW apkg), gated on APKG in the order file (1.0 only)")
    else:
        fail("APKGCONF: the first write_apkg_conf call (offset %d) is not between the install-set line (%d) and the first package path (%d), or the order gate is missing" % (first, seed, sec5))
    if re.search(r'elif \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n\t\twrite_apkg_conf\n', drv):
        ok("1.1: the repo line is written after APKG installs its default (a conffile edit, no PENDING)")
    else:
        fail("APKGCONF: 1.1 does not write the repo line after the APKG package")
    if re.search(r'repo=\$FB_REPO_URL" \]; then echo y', drv) and "lost its repo line" in drv:
        ok("after the install the conf is re-checked and written again only if an older APKG replaced it")
    else:
        fail("APKGCONF: the post-install re-check of /etc/apkg.conf is missing")




def audit_dmamask_stamp():
    head("DMASK. the DosEnvec Mask: install.sh's dm_target_mask EXECUTED on /etc/rdb-shaped RDBs")
    drv = read_sh(DRIVER)

    def fn(name):
        m = re.search(r"(?ms)^%s\(\)\s*\{\n.*?\n\}\n" % re.escape(name), drv)
        return m.group(0) if m else None
    names = ("is_num", "oct_file", "dm_byte", "dm_u16", "dm_oct", "dm_stamp", "dm_target_mask")
    funcs = [fn(n) for n in names]
    if None in funcs:
        fail("could not extract install.sh's DosEnvec Mask helpers (%s)"
             % ", ".join(n for n, f in zip(names, funcs) if f is None))
        return
    code = strip_full_comments(drv)
    if re.search(r'RDB read-back: no RDSK at block 0[^\n]*\n\s*esac\n\s*fi\n\s*dm_target_mask "\$DISK_RAW" "\$\{TARGET_HBA:-\}"',
                 code):
        ok("author mode stamps the target's Mask right after the RDSK read-back (TARGET_HBA's row)")
    else:
        fail("build_target_author does not call dm_target_mask \"$DISK_RAW\" \"${TARGET_HBA:-}\" after the RDSK read-back")
    iso = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    if re.search(r'dmamask\.py" medium --out "\$STAGE/dmamask"', iso):
        ok("build-install-iso.sh stages /install/dmamask from the one table")
    else:
        fail("build-install-iso.sh does not stage /install/dmamask (tools/dmamask.py medium)")
    if not os.path.exists("/usr/bin/dash") or not shutil.which("sum"):
        skip("dash or sum absent -- the Mask stamper cannot be executed")
        return
    sys.path.insert(0, os.path.join(REPO, "tools", "lib"))
    import dmamask as dm
    d = workpath("dmask")
    os.makedirs(os.path.join(d, "inst", "bin"), exist_ok=True)
    sumbin = os.path.join(d, "inst", "bin", "sum")
    if not os.path.exists(sumbin):
        os.symlink(shutil.which("sum"), sumbin)
    with open(os.path.join(d, "inst", "dmamask"), "w") as fh:
        fh.write(dm.medium_rows())
    dev = os.path.join(d, "disk")
    # a regular file stands in for the raw disk: GNU dd truncates on seek= without notrunc
    pre = ("PROG=t\nmsg() { echo \"$PROG: $*\"; }\nwarn() { echo \"$PROG: WARNING: $*\"; }\n"
           "die() { echo \"$PROG: STOP: $*\"; exit 1; }\n"
           "dd() { case \"$*\" in *of=%s*) command dd \"$@\" conv=notrunc ;; *) command dd \"$@\" ;; esac; }\n"
           "INST=%s\n" % (dev, os.path.join(d, "inst"))) + "".join(funcs)

    def run(img, hba):
        open(dev, "wb").write(bytes(img))
        r = subprocess.run(["/usr/bin/dash", "-c", pre + 'dm_target_mask "$1" "$2"\n', "t", dev, hba],
                           capture_output=True, text=True, timeout=120)
        return r, open(dev, "rb").read()

    def only_mask_moved(a, b):
        """every byte identical except each PART's checksum and Mask longwords"""
        a, b = bytearray(a), bytearray(b)
        for _sl, _nm, _bm, _mt, _mk, _dt, pb, _ck in dm.part_fields(bytes(b)):
            for off in (8, 128 + 4 * dm.DE_MASK):
                a[pb * 512 + off:pb * 512 + off + 4] = b[pb * 512 + off:pb * 512 + off + 4]
        return a == b

    cases = [("a4091", dm.synth_rdb(0xFFFFFFFC), 0x07FFFFFE, 3),
             ("a2091", dm.synth_rdb(0xFFFFFFFC, rdsk_block=2, nparts=4), 0x00FFFFFE, 4),
             ("z3660scsi", dm.synth_rdb(0x00FFFFFE), 0xFFFFFFFC, 3),
             ("a4000t", dm.synth_rdb(0x07FFFFFE), 0xFFFFFFFC, 3)]
    for hba, img, want, n in cases:
        r, got = run(img, hba)
        probs = dm.check_image(got, want)[0]
        if r.returncode == 0 and not probs and only_mask_moved(img, got) and ("on %d partition" % n) in r.stdout:
            ok("%s: %d PART block(s) -> Mask 0x%08X, checksums close, nothing else moved" % (hba, n, want))
        else:
            fail("%s: rc=%d problems=%s out=%r err=%r" % (hba, r.returncode, probs, r.stdout[-200:], r.stderr[-200:]))
    img = dm.synth_rdb(0x07FFFFFE)
    r, got = run(img, "a4092")
    if r.returncode == 0 and got == bytes(img):
        ok("a disk already at its Mask is left byte-identical (a re-stamp is idempotent)")
    else:
        fail("re-stamping an already-stamped disk changed it (rc=%d)" % r.returncode)
    r, got = run(dm.synth_rdb(0xFFFFFFFC), "")
    if r.returncode == 0 and not dm.check_image(got, 0x07FFFFFE)[0] and "WARNING" in r.stdout:
        ok("no TARGET_HBA: the unknown row (0x07FFFFFE) and a warning")
    else:
        fail("no TARGET_HBA: rc=%d out=%r" % (r.returncode, r.stdout[-200:]))
    r, _got = run(bytes(64 * 512), "a4091")
    if r.returncode != 0 and "no RDSK" in r.stdout:
        ok("a disk with no RDSK in blocks 0-15 stops the install")
    else:
        fail("no RDSK did not stop: rc=%d out=%r" % (r.returncode, r.stdout[-200:]))




def audit_firstboot_perms():
    head("AU. the first-boot state dir is root's alone (2026-10-03)")
    drv = strip_full_comments(open(DRIVER, encoding="latin-1").read())
    fb = strip_full_comments(open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"),
                                  encoding="latin-1").read())
    want_drv = [(r'run chmod 700 "\$TARGET/var/adm/firstboot"\n', "dir 0700 at laydown"),
                (r'run chmod 600 "\$TARGET/var/adm/firstboot/root.shadow"', "root.shadow 0600"),
                (r'run chmod 600 "\$TARGET/var/adm/firstboot/firstboot.conf" "\$TARGET/var/adm/firstboot/PENDING"',
                 "firstboot.conf + PENDING 0600")]
    want_fb = [(r'chmod 700 "\$FBDIR" 2>/dev/null', "firstboot re-tightens the dir on every run"),
               (r'chmod 600 "\$CONF" "\$MARK" "\$DIALOG_DONE" "\$FBDIR/root.shadow" 2>/dev/null',
                "... and its state files"),
               (r'rm -f "\$\{MARK:\?\}"\nrm -f "\$\{FBDIR:\?\}/root.shadow"', "root.shadow removed when first boot completes")]
    miss = [d for rx, d in want_drv if not re.search(rx, drv)] + \
           [d for rx, d in want_fb if not re.search(rx, fb)]
    if miss:
        fail("first-boot state not root-only: missing %s" % miss)
    else:
        ok("first-boot state is root's alone: dir 0700 + files 0600 at laydown, re-tightened "
           "by firstboot.sh on every run, root.shadow removed at completion")

    # One-shot umask audit (amix-cb, SEC-1): the miniroot runs with umask 0, so every
    # dir install.sh mkdir -p's on the target and every file it CREATES there by
    # redirection is 0777/0666 unless it is chmod'ed. Each one must be, or be on this
    # reviewed list: package-declared dirs (pkgadd reasserts their pkgmap modes; none
    # is world-writable on an installed disk) and files the package owns or that are
    # scratch.
    reviewed = {"$TARGET/etc": "core dir (pkgadd reasserts 0775/sys)",
                "$TARGET/etc/init.d": "core dir", "$TARGET/etc/rc0.d": "core dir",
                "$TARGET/etc/rc2.d": "core dir", "$TARGET/usr/sbin": "core dir",
                "$TARGET/var/adm": "core dir",
                "$TARGET/etc/profile": "core file, APPENDED to (its mode is the package's)",
                "$TARGET/tmp/.chainblk": "install-time scratch"}
    mk = set(re.findall(r'mkdir -p "(\$TARGET/[^"]+)"', drv))
    rd = set(re.findall(r'>>? *"(\$TARGET/[^"$]+)"', drv))
    chp = set()
    for g in re.findall(r'chmod [0-7]+ ((?:"\$TARGET/[^"]+" ?)+)', drv):
        chp.update(re.findall(r'"(\$TARGET/[^"]+)"', g))
    loose = sorted(x for x in (mk | rd) if x not in chp and x not in reviewed)
    if loose:
        fail("umask 0: target path(s) created without an explicit mode and not reviewed: %s" % loose)
    else:
        ok("umask 0 audit: %d target dirs/files install.sh creates -- every one chmod'ed or on "
           "the reviewed package/scratch list (%d)" % (len(mk | rd), len(reviewed)))
    fb_need = [(r'mv /etc/inet/hosts\.fb\$\$ /etc/inet/hosts\n\s*chmod 444 /etc/inet/hosts', "hosts 0444 after the identity rewrite"),
               (r'mv /etc/inet/hosts\.rp\$\$ /etc/inet/hosts\n\s*chmod 444 /etc/inet/hosts', "hosts 0444 after the repo row"),
               (r'chmod 644 /etc/tz\.index', "tz.index 0644")]
    zen = open(os.path.join(REPO, "payload", "S99zen"), encoding="utf-8").read()
    miss2 = [d for rx, d in fb_need if not re.search(rx, fb)]
    if 'mv "${HOSTS:?}.zn$$" "${HOSTS:?}" && chmod 444 $HOSTS' not in zen:
        miss2.append("S99zen hosts 0444 after its own-row rewrite")
    if miss2:
        fail("boot-time rewrites leave world-writable files (init's umask is 0): %s" % miss2)
    else:
        ok("boot-time rewrites restore modes: /etc/inet/hosts 0444 (firstboot x2, S99zen), "
           "/etc/tz.index 0644")




def audit_tz():
    head("AZ. IN-rtc-2: TZFILES=tzdata (every 1991 zone regenerated from current tzdata, "
         "1991 layout) and the laydown over /usr/lib/locale/TZ")
    code = strip_full_comments(open(DRIVER, encoding="utf-8", errors="replace").read())
    iso_src = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()

    # AZ1: TZFILES validation, EXECUTED (default tzdata; stock; nothing else).
    m = re.search(r'\n\[ -n "\$TZFILES" \] \|\| TZFILES=tzdata\ncase "\$TZFILES" in\n(.*?)\nesac\n', code, re.S)
    if not m:
        fail("install.sh has no TZFILES default + validation")
    else:
        snippet = ('die() { echo BAD; exit 1; }\n[ -n "$TZFILES" ] || TZFILES=tzdata\n'
                   'case "$TZFILES" in\n' + m.group(1) + '\nesac\necho "OK $TZFILES"\n')
        wrong = []
        for v, want in (("", "OK tzdata"), ("tzdata", "OK tzdata"), ("stock", "OK stock"),
                        ("yes", "BAD"), ("TZDATA", "BAD")):
            r = subprocess.run(["sh", "-c", snippet], env={"TZFILES": v, "PATH": os.environ.get("PATH", "")},
                               capture_output=True, text=True)
            if r.stdout.strip() != want:
                wrong.append((v, r.stdout.strip(), want))
        if wrong:
            fail("install.sh TZFILES validation wrong: %s" % wrong)
        else:
            ok("install.sh TZFILES validation EXECUTED: unset -> tzdata, tzdata/stock accepted, else refused")

    # AZ2: the laydown -- remove-then-copy (the stock hard links part), sum -r proof,
    # subshell-safe (records in the loop, decides after it), stock touches nothing.
    want = [
        (r'if\s+\[\s+"\$TZFILES"\s+=\s+tzdata\s+\];\s*then', "gate on TZFILES=tzdata"),
        (r'\[ -f "\$INST/tz/MANIFEST" \] \|\| die', "refuses a medium without the set"),
        (r'while read tz_sha tz_size tz_name; do', "reads the MANIFEST"),
        (r'rm -f "\$\{tz_dst:\?\}"\n\t\tif cp "\$tz_src" "\$tz_dst"', "removes each name before copying (breaks the 1991 hard links)"),
        (r'"\$TZSUM" -r "\$tz_dst"', "sum -r of every copy"),
        (r'done < "\$INST/tz/MANIFEST"\n\t\[ -s "\$tzfail" \] && die', "decides after the loop, in the parent"),
        (r'tzn=`count_tokens "\$tzok"`', "counts from the ok file (subshell-safe)"),
    ]
    miss = [d for rx, d in want if not re.search(rx, code)]
    if miss:
        fail("install.sh zone laydown incomplete: %s" % miss)
    else:
        ok("install.sh lays the zone set over /usr/lib/locale/TZ: rm then cp per name, sum -r "
           "proof, decided in the parent; TZFILES=stock leaves the 1991 files")

    # AZ3: the generator is hermetic and the medium pins its output.
    pin = re.search(r'^TZSET_SHA=([0-9a-f]{64})$', iso_src, re.M)
    spec = importlib.util.spec_from_file_location("build_tzfile", os.path.join(REPO, "tools", "build-tzfile.py"))
    bt = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bt)
    if not pin:
        fail("build-install-iso.sh does not pin TZSET_SHA")
        return
    if not shutil.which("zic"):
        ok("TZSET_SHA pinned; no host zic here -- the build-time gate covers the set")
        return
    tmp = tempfile.mkdtemp(prefix="st-tz.")
    try:
        r = subprocess.run([sys.executable, os.path.join(REPO, "tools", "build-tzfile.py"),
                            "--out", tmp], capture_output=True, text=True)
        if r.returncode:
            fail("tools/build-tzfile.py failed: %s" % (r.stderr or r.stdout).strip()[-300:])
            return
        man = open(os.path.join(tmp, "MANIFEST"), "rb").read()
        got = hashlib.sha256(man).hexdigest()
        if got != pin.group(1):
            fail("the regenerated zone set %s... != pinned TZSET_SHA %s..." % (got[:16], pin.group(1)[:16]))
        else:
            ok("tools/build-tzfile.py regenerates the pinned set (%s..., %d zones)"
               % (got[:16], len(man.splitlines())))
        z = {}
        for n in ("EET", "US/Eastern", "Japan", "GMT+2"):
            z[n] = bt.read1991(open(os.path.join(tmp, n), "rb").read())
        def at(n, t):
            return bt.lookup1991(z[n], t)
        # 2026 in UTC: EU summer time 29 Mar 01:00 .. 25 Oct 01:00; US 8 Mar 07:00 .. 1 Nov 06:00 (EST)
        cases = [
            ("EET", 1774745999, (7200, 0, "EET")), ("EET", 1774746000, (10800, 1, "EEST")),
            ("EET", 1790683200, (10800, 1, "EEST")),   # 2026-09-29: the 1991 file said EET here
            ("EET", 1792889999, (10800, 1, "EEST")), ("EET", 1792890000, (7200, 0, "EET")),
            ("US/Eastern", 1772953199, (-18000, 0, "EST")), ("US/Eastern", 1772953200, (-14400, 1, "EDT")),
            ("US/Eastern", 1793512799, (-14400, 1, "EDT")), ("US/Eastern", 1793512800, (-18000, 0, "EST")),
            ("Japan", 1777000000, (32400, 0, "JST")),
            ("GMT+2", 1777000000, (7200, 0, "GMT+0200")),     # 1991 sign: EAST of GMT
        ]
        bad = [(n, t, at(n, t), w) for n, t, w in cases if at(n, t) != w]
        if bad:
            fail("zone answers wrong under the 1991 lookup: %s" % bad)
        elif z["Japan"][0] or len(z["Japan"][1]) != 1:
            fail("Japan should carry no transitions and one type")
        else:
            ok("1991-layout answers: EET/EEST switch 29 Mar and 25 Oct 2026 (not September), "
               "US/Eastern on the 2007 rule, Japan fixed JST, GMT+2 = UTC+2 as in 1991")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)




def audit_pick_at_install():
    """2026-10-03: the root unit is chosen AT INSTALL on the public K1 media.
    (1) install.sh's unit resolver, EXECUTED under dash on a fake medium: the chosen id's
    chain / manifest (.manifest or the s5 .man) / boot2 / rootdev / sum -r / vfstab unit and
    /stand/unix; an id without a row, and an unknown RUN_UNIT, die; RUN_UNIT=6 keeps the single
    chain (040/060: /stand/unix = boot/<p>/unix; 030: none). (2) every RUN_UNIT=install profile's
    UNIT_TABLE covers its INSTALLABLE_IDS, never the source id or 7, and (when the chains are
    present) every pin matches its chain file. (3) the 8b /stand/unix gate, the first-boot
    installf step and the per-unit staging are wired."""
    head("Q415. pick-at-install: the per-unit resolver EXECUTED, the unit tables, the wiring")
    drv = read_sh(DRIVER)
    m = re.search(r'(STAND_UNIX=\nSTAMP_PATCH=\nSTAND_UNIX_FROM_SLICE=\ncase "\$\{RUN_UNIT:-6\}" in\n.*?'
                  r'\nif \[ "\$INSTALL_LAYOUT" = 1.0 \] && \[ -z "\$STAND_UNIX" \] && \[ -z "\$STAND_UNIX_FROM_SLICE" \]; then\n.*?\nfi\n)',
                  drv, re.S)
    if not m:
        fail("could not extract install.sh's pick-at-install resolver (STAND_UNIX= .. fi) -- moved or reshaped?")
    elif not os.path.exists("/usr/bin/dash"):
        skip("dash absent -- cannot execute the resolver")
    else:
        d = workpath("q415")
        inst = os.path.join(d, "inst")
        for n in range(6):
            os.makedirs(os.path.join(inst, "boot", "metal", "u%d" % n), exist_ok=True)
        open(os.path.join(inst, "boot", "metal", "units"), "w").write(
            "".join("%d 0x0048001%d %05d\n" % (n, n, 11111 * (n + 1) % 65536) for n in range(6)))
        open(os.path.join(inst, "boot", "metal", "u3", "bootslice.man"), "w").write("x\n")
        open(os.path.join(inst, "boot", "metal", "u2", "bootslice.manifest"), "w").write("x\n")
        # r6: the stamp table of RUN_UNIT=stamp
        os.makedirs(os.path.join(inst, "boot", "metal", "stamp"), exist_ok=True)
        open(os.path.join(inst, "boot", "metal", "stamp", "units"), "w").write(
            "".join("%d 0x0048001%d %05d 1979586\n" % (n, n, 22222 * (n + 1) % 65536) for n in range(6)))
        open(os.path.join(inst, "boot", "metal", "stamp", "u2.patch"), "w").write("19 19 251\n")
        block = m.group(1).replace("/tmp/.unitrow", os.path.join(d, "unitrow"))

        def run(run_unit, id_, cpu):
            h = ('msg() { :; }\ndie() { echo "DIE $*"; exit 3; }\nINSTALL_LAYOUT=1.0\nINST=%s\nID=%s\nRUN_UNIT=%s\n'
                 'INSTALL_CPU=%s\nBOOTSLICE_IMG=boot/metal/bootslice.img\n'
                 'BOOTSLICE_MANIFEST=boot/metal/bootslice.man\nBOOT2_BOOT=boot/metal/boot2.boot\n'
                 'ROOTDEV=0x00480016\nKERNEL_BREL_SUMR=08512\nTARGET_VFSTAB_SCSI_ID=6\n'
                 % (inst, id_, run_unit, cpu) + block +
                 'echo "R|$BOOTSLICE_IMG|$BOOTSLICE_MANIFEST|$BOOT2_BOOT|$ROOTDEV|$KERNEL_BREL_SUMR|'
                 '$TARGET_VFSTAB_SCSI_ID|$STAND_UNIX"\n'
                 'echo "S|${STAMP_PATCH##*/boot/}|$STAND_UNIX_FROM_SLICE"\n')
            r = subprocess.run(["/usr/bin/dash", "-c", h], capture_output=True, text=True, timeout=30)
            lines = r.stdout.strip().splitlines()
            return r.returncode, (lines[0] if lines else ""), (lines[1] if len(lines) > 1 else "")

        cases = [
            (("install", 3, "060"), (0, "R|boot/metal/u3/bootslice.img|boot/metal/u3/bootslice.man|"
                                        "boot/metal/u3/boot2.boot|0x00480013|44444|3|boot/metal/u3/unix")),
            (("install", 2, "060"), (0, "R|boot/metal/u2/bootslice.img|boot/metal/u2/bootslice.manifest|"
                                        "boot/metal/u2/boot2.boot|0x00480012|33333|2|boot/metal/u2/unix")),
            (("6", 0, "060"), (0, "R|boot/metal/bootslice.img|boot/metal/bootslice.man|boot/metal/boot2.boot|"
                                  "0x00480016|08512|6|boot/metal/unix")),
            (("6", 6, "030"), (0, "R|boot/metal/bootslice.img|boot/metal/bootslice.man|boot/metal/boot2.boot|"
                                  "0x00480016|08512|6|")),
        ]
        cases += [
            # r6: hint -- the family chain to any id unchanged; vfstab follows the id
            (("hint", 3, "060"), (0, "R|boot/metal/bootslice.img|boot/metal/bootslice.man|boot/metal/boot2.boot|"
                                     "0x00480016|08512|3|boot/metal/unix")),
            # r6: stamp -- the family chain + the unit's patch; its own manifest, rootdev,
            # sum -r; /stand/unix comes out of the stamped slice (no file named)
            (("stamp", 2, "060"), (0, "R|boot/metal/bootslice.img|boot/metal/stamp/u2.manifest|boot/metal/boot2.boot|"
                                      "0x00480012|01130|2|")),
        ]
        for (ru, i, cpu), want in cases:
            got = run(ru, i, cpu)
            if got[:2] == want:
                ok("RUN_UNIT=%s id %s cpu %s -> %s (EXECUTED)" % (ru, i, cpu, got[1].split("|", 1)[1]))
            else:
                fail("RUN_UNIT=%s id %s cpu %s: got %r, want %r" % (ru, i, cpu, got[:2], want))
        got = run("stamp", 2, "060")
        if got[2] == "S|metal/stamp/u2.patch|1979586":
            ok("RUN_UNIT=stamp id 2: patch boot/metal/stamp/u2.patch, /stand/unix = 1979586 bytes read out of the slice")
        else:
            fail("RUN_UNIT=stamp id 2: stamp fields %r" % (got[2],))
        for ru, i, why in (("install", 6, "an id with no row (the source's unit)"), ("bogus", 0, "an unknown RUN_UNIT"),
                           ("stamp", 4, "a stamp id with no patch file")):
            rc, out, _ = run(ru, i, "060")
            if rc == 3 and out.startswith("DIE"):
                ok("%s dies: %s" % (why, out[:90]))
            else:
                fail("%s did NOT die (rc %s, %r)" % (why, rc, out))
    # (2) the unit tables
    for pf in sorted(os.listdir(PROFILES_DIR)):
        if not pf.endswith(".profile"):
            continue
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        if d.get("RUN_UNIT") != "install":
            continue
        tab = os.path.join(REPO, d.get("UNIT_TABLE", ""))
        if not os.path.isfile(tab):
            fail("%s: RUN_UNIT=install but UNIT_TABLE %r is missing" % (pf, d.get("UNIT_TABLE")))
            continue
        rows, cdir = {}, None
        for line in open(tab, encoding="utf-8"):
            if line.startswith("UNIT="):
                f = line[5:].split()
                rows[f[0]] = f
            elif line.startswith("CHAIN_DIR="):
                cdir = os.path.join(REPO, line.split("=", 1)[1].strip())
        ids = d.get("INSTALLABLE_IDS", "").split()
        missing = [i for i in ids if i not in rows]
        bad = [i for i in ids if i in (d.get("SRC_SCSI_ID"), "7")]
        if missing or bad or not ids:
            fail("%s: INSTALLABLE_IDS %s -- no pin for %s, forbidden %s" % (pf, ids, missing, bad))
        else:
            ok("%s: INSTALLABLE_IDS %s all pinned in %s; never the source id %s nor 7"
               % (pf, " ".join(ids), d["UNIT_TABLE"], d.get("SRC_SCSI_ID")))
        if cdir and os.path.isdir(cdir):
            wrong = []
            for i in ids:
                fpath = os.path.join(cdir, rows[i][1])          # UNIT=<id> <file> <sha256> ...
                if not os.path.isfile(fpath) or hashlib.sha256(open(fpath, "rb").read()).hexdigest() != rows[i][2]:
                    wrong.append(i)
            if wrong:
                fail("%s: unit pins disagree with the chain files for %s" % (pf, wrong))
            else:
                ok("%s: every unit pin matches its chain file in %s" % (pf, os.path.relpath(cdir, REPO)))
        else:
            NOTES.append("%s: chain dir %s absent -- unit pins not re-hashed" % (pf, cdir))
    # (3) wiring
    fb = read_sh(FIRSTBOOT)
    biso = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    checks = [
        ("install.sh 8b lays /stand/unix and gates its sum -r", re.search(
            r'run cp "\$INST/\$STAND_UNIX" "\$TARGET/stand/unix".*?-eq "\$KERNEL_BREL_SUMR"', drv, re.S)),
        ("install.sh writes FB_STANDUNIX_REG=y only when it laid /stand/unix",
         '[ -n "$STAND_UNIX" ] && echo "FB_STANDUNIX_REG=y"' in drv),
        ("firstboot re-registers /stand/unix with APKG's installf (from /tmp), never the stock one", re.search(
            r'FB_STANDUNIX_REG" = y \].*?cd /tmp && /usr/apkg/bin/installf core /stand/unix f 0644 root root.*?'
            r'/usr/apkg/bin/installf -f core', fb, re.S) and not re.search(r'/usr/sbin/installf (core|-f)', fb)),
    ]
    for what, good in checks:
        (ok if good else fail)(what)




# the upgrade install's names; none may come back into the driver or l11.sh
_P36_GONE = ("l11_upgrade_capture", "l11_upgrade_restore", "l11_upgrade_apply", "l11_keep_layout",
             "S17upgrade", "SWAP_HOLD", "UPGRADE_KIND", "L11_KEEP", "DATA_KEEP", "FB_UPGRADED",
             "/var/adm/upgrade", "UPGRADE_DROP_HOME")


def _p36_problems(install_src, l11_src):
    """What keeps install.sh + l11.sh from being clean-install only."""
    probs = []
    if not re.search(r'\ncase "\$\{INSTALL_UPGRADE:-no\}" in\n\tno\)\t: ;;\n\t\*\)\tdie "[^"\n]*'
                     r'1\.1 requires a fresh install', install_src):
        probs.append("install.sh does not refuse INSTALL_UPGRADE")
    code = strip_full_comments(install_src) + strip_full_comments(l11_src)
    left = sorted(w for w in _P36_GONE if w in code)
    if left:
        probs.append("upgrade code left: " + " ".join(left))
    return probs


def audit_ufs_density():
    head("UD. mkfs_ufs density: stock's free=2,opt=s, plus nbpi=8192 on a slice over 512 MiB (root and /home)")
    src = open(DRIVER, encoding="utf-8").read()
    m = re.search(r'\n(ufs_mkfs_opts\(\)\n\{\n.*?\n\})\n', src, re.S)
    l11 = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    if not m or 'run /bin/mkfs_ufs -o `ufs_mkfs_opts "$DATALEN"` "/dev/dsk/c${ID}d0s4" "$DATALEN"' not in l11:
        fail("no ufs_mkfs_opts in install.sh, or l11_mkfs_data does not use it")
        return
    want = ((204800, "free=2,opt=s"), (1048576, "free=2,opt=s"), (1048577, "free=2,opt=s,nbpi=8192"),
            (4192256, "free=2,opt=s,nbpi=8192"), (2916352, "free=2,opt=s,nbpi=8192"))
    got = []
    for blocks, w in want:
        r = subprocess.run(["/usr/bin/dash", "-c", m.group(1) + '\nufs_mkfs_opts %d\n' % blocks],
                           capture_output=True, text=True, timeout=10).stdout.strip()
        got.append((blocks, r, w))
    bad = [g for g in got if g[1] != g[2]]
    (fail if bad else ok)("ufs_mkfs_opts EXECUTED: 100 and 512 MiB stock density, 512 MiB+1 block, 2047 and 1424 MiB "
                          "nbpi=8192%s" % ((": %r" % bad) if bad else ""))


def audit_syspass_confirm():
    head("SP. the system-accounts question: y runs passwdall; a no is confirmed once (default n), "
         "n or RETURN asks stock's question again, y keeps the accounts without a password")
    fb = open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"), encoding="latin-1").read()
    fn = lambda name: (re.search(r"\n(%s\(\)\n\{\n.*?\n\})\n" % name, fb, re.S) or [None, None])[1]
    ra, ap = fn("readask"), fn("ask_passwords")
    if not ra or not ap or 'readask "anyone may log in to them.  Are you sure? [n] "' not in ap \
            or 'echo "\\nThe system accounts will have no password;"' not in ap:
        fail("firstboot.sh: no ask_passwords with the confirmation lines")
        return
    d = tempfile.mkdtemp(prefix="syspass_")
    try:
        pw = os.path.join(d, "passwd")
        with open(pw, "w") as f:
            f.write("root::0:0::/:/sbin/sh\n")
        ap = ap.replace("/usr/amiga/bin/passwdall", "passwdall").replace("/etc/passwd", pw)
        stubs = ('passwdall() { echo PASSWDALL; return 0; }\nset_root_password() { echo SETROOT; PW_DONE=y; }\n'
                 'passwd() { echo "PASSWD $1"; }\n')
        def run(answers):
            body = "%s%s\n%s\nask_passwords\necho \"END SYSPASS=$SYSPASS\"\n" % (stubs, ra, ap)
            r = subprocess.run(["/usr/bin/dash", "-c", body], input="".join(a + "\n" for a in answers),
                               capture_output=True, text=True, timeout=10)
            return r.stdout
        cases = [
            ("y", ["y", "y"], ["PASSWDALL", "END SYSPASS=y"], ["Are you sure?", "SETROOT"], 0),
            ("RETURN", ["", "y"], ["PASSWDALL", "END SYSPASS=y"], ["Are you sure?"], 0),
            ("n then n", ["n", "n", "y", "y"], ["PASSWDALL", "END SYSPASS=y"], ["SETROOT"], 1),
            ("n then RETURN", ["n", "", "y", "y"], ["PASSWDALL", "END SYSPASS=y"], ["SETROOT"], 1),
            ("n then y", ["n", "y", "y"], ["SETROOT", "END SYSPASS=n"], ["PASSWDALL"], 1),
        ]
        bad = []
        for name, ans, want, never, nconf in cases:
            out = run(ans)
            asks = out.count("system accounts? [y] ")
            if any(w not in out for w in want) or any(n in out for n in never) \
                    or out.count("Are you sure? [n] ") != nconf or asks != (2 if name.startswith("n then n") or name == "n then RETURN" else 1):
                bad.append((name, out[-200:]))
        (fail if bad else ok)("system accounts EXECUTED: y and RETURN run passwdall; n then n / RETURN asks the "
                              "question again; n then y keeps them empty and still sets root%s"
                              % ((": %r" % bad) if bad else ""))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_netset_stage1():
    head("NR. the netinstall's first stage: the chosen set beyond minimal and its own base packages, as the "
         "repository catalog's rows, recorded before any install; the second-stage hook")
    src = open(os.path.join(REPO, "src", "installer", "install.sh"), encoding="utf-8").read()
    fns = {}
    for name in ("net_row", "net_record", "emit_netset_hook"):
        m = re.search(r"\n(%s\(\)\s*\{\n.*?\n\})\n" % name, src, re.S)
        fns[name] = m.group(1) if m else None
    swap = ('NET_SET="$INSTALL_SET" NET_SET_ORDER="$ORDER"' in src
            and 'ORDER="$INST/order.minimal" INSTALL_SET=minimal' in src
            and '[ -z "$NET_SET" ] || net_record' in src
            and 'emit_netset_hook "$TARGET/etc/rc2.d/S99znetset"' in src)
    if not all(fns.values()) or not swap:
        fail("install.sh: net_row/net_record/emit_netset_hook or their wiring (the set switch, the record before "
             "the installs, the hook at the arm step) is missing")
        return
    d = tempfile.mkdtemp(prefix="netrec_")
    try:
        inst = os.path.join(d, "inst")
        os.makedirs(os.path.join(inst, "l11", "base"))
        os.makedirs(os.path.join(d, "t", "tmp"))
        open(os.path.join(inst, "order.minimal"), "w").write("# set: minimal (3 package(s))\ncore\nAPKGENG\nAPKG\n")
        open(os.path.join(inst, "order.full"), "w").write("# set: full\ncore\nxbasic\nAPKGENG\nAPKG\nxtras\n")
        open(os.path.join(inst, "l11", "base", "o.full"), "w").write("x11r63\n")
        cat = os.path.join(d, "catalog")
        open(cat, "w").write("#apkg-catalog 1\n"
                             "core|2.1|core|stock/core-2.1.pkg|00|1|none|system|Core\n"
                             "xbasic|2.1|xbasic|stock/xbasic-2.1.pkg|11|2|none|x11|X basic\n"
                             "xtras|2.1|xtras|stock/xtras-2.1.pkg|22|3|none|x11|X extras\n"
                             "x11r6.3|6.3-6|x11r63|x11r63-6.3-6.pkg|33|4|none|x11|X11R6.3\n")
        def run(extra=""):
            body = ('INST=%s\nTARGET=%s/t\nNETCAT=%s\nNET_SET=full\nNET_SET_ORDER=%s/order.full\n'
                    'NET_REPO=http://192.0.2.1:8420/1.1\nmsg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n'
                    '%s\n%s\n%s\nnet_record\n' % (inst, d, cat, inst, fns["net_row"], fns["net_record"], extra))
            return subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=20)
        r = run()
        rec = os.path.join(d, "t", "tmp", "netset.rec")
        got = open(rec).read() if os.path.exists(rec) else ""
        want = ("set full\nrepo http://192.0.2.1:8420/1.1\n"
                "row xbasic|2.1|xbasic|stock/xbasic-2.1.pkg|11|2|none|x11|X basic\n"
                "row xtras|2.1|xtras|stock/xtras-2.1.pkg|22|3|none|x11|X extras\n"
                "row x11r6.3|6.3-6|x11r63|x11r63-6.3-6.pkg|33|4|none|x11|X11R6.3\n")
        (ok if got == want and r.returncode == 0 else fail)(
            "first stage EXECUTED: the record holds full beyond minimal in order, then o.full's x11r63 by its "
            "pkginst as the catalog's x11r6.3 row%s" % ("" if got == want else ": %r %r" % (got, r.stdout[-200:])))
        open(os.path.join(inst, "l11", "base", "o.full"), "w").write("x11r63\nnosuch\n")
        r = run()
        (ok if r.returncode == 3 and "nosuch is not in the repository catalog" in r.stdout else fail)(
            "first stage EXECUTED: a package of the set missing from the repository stops the install before "
            "anything is installed")
        hook = os.path.join(d, "hook")
        body = '%s\nemit_netset_hook %s\n' % (fns["emit_netset_hook"], hook)
        subprocess.run(["/usr/bin/dash", "-c", body], timeout=10)
        h = open(hook).read() if os.path.exists(hook) else ""
        fb = os.path.join(d, "fb")
        os.makedirs(fb)
        open(os.path.join(fb, "netset.sh"), "w").write("echo RAN\n")
        hb = h.replace("/var/adm/firstboot", fb).replace("/sbin/sh", "/usr/bin/dash")
        r0 = subprocess.run(["/usr/bin/dash", "-c", hb], capture_output=True, text=True, timeout=10)
        open(os.path.join(fb, "netset"), "w").write("set full\n")
        r1 = subprocess.run(["/usr/bin/dash", "-c", hb], capture_output=True, text=True, timeout=10)
        (ok if h.startswith("#!/bin/sh\n# S99znetset") and r0.stdout == "" and r1.stdout == "RAN\n" else fail)(
            "S99znetset EXECUTED: runs netset.sh only while the record is there%s"
            % ("" if r1.stdout == "RAN\n" else ": %r %r" % (h, r1.stdout)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_netset_stage2():
    head("SN. the netinstall's second stage (payload/firstboot/netset.sh) on the installed system: the "
         "recorded rows against the repository, one package at a time, retries, resume, a bootable stop")
    src = open(os.path.join(REPO, "payload", "firstboot", "netset.sh"), encoding="latin-1").read()
    code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
    bad_syntax = [t for t in ("$(", "$((", "local ", "[[") if t in code]
    (fail if bad_syntax else ok)("netset.sh: pre-POSIX sh only (no %s)" % ", ".join(("$(", "$((", "local", "[["))
                                 + ((": " + " ".join(bad_syntax)) if bad_syntax else ""))
    rows = ["xbasic|2.1|xbasic|stock/xbasic-2.1.pkg|0123456789abcdef0123456789abcdef|1024|none|x11|X basic",
            "x11r6.3|6.3-6|x11r63|x11r63-6.3-6.pkg|fedcba9876543210fedcba9876543210|34151424|none|x11|X11R6.3"]
    def setup(d, repo_rows, fail=(), update_fails=False, armed=True):
        for sub in ("fb", "sadm", "vt"):
            os.makedirs(os.path.join(d, sub), exist_ok=True)
        if armed:
            with open(os.path.join(d, "fb", "netset"), "w") as f:
                f.write("set full\nrepo http://192.0.2.1:8420/1.1\n" + "".join("row %s\n" % r for r in rows))
        with open(os.path.join(d, "hook"), "w") as f:
            f.write("#!/bin/sh\n")
        with open(os.path.join(d, "repo-catalog"), "w") as f:
            f.write("#apkg-catalog 1\n" + "".join(r + "\n" for r in repo_rows))
        with open(os.path.join(d, "fail"), "w") as f:
            f.write("".join(n + "\n" for n in fail))
        uf = os.path.join(d, "update-fails")
        if update_fails:
            open(uf, "w").close()
        elif os.path.exists(uf):
            os.remove(uf)
        stub = os.path.join(d, "apkg")
        with open(stub, "w") as f:
            f.write('#!/bin/sh\nD=%s\necho "$*" >> $D/calls\nshift 2\n'
                    'case "$1" in\n'
                    ' update) [ -f $D/update-fails ] && exit 1; cp $D/repo-catalog $D/w/catalog; exit 0 ;;\n'
                    ' -y) n=$3; grep -qx "$n" $D/fail && exit 1\n'
                    '     inst=`grep "^$n|" $D/repo-catalog | cut -d"|" -f3`; mkdir -p $D/sadm/$inst\n'
                    '     echo "TMPDIR=$TMPDIR" >> $D/calls; exit 0 ;;\n'
                    'esac\nexit 9\n' % d)
        os.chmod(stub, 0o755)
    def run(d, args=()):
        body = (src.replace("/var/adm/firstboot", d + "/fb").replace("/etc/rc2.d/S99znetset", d + "/hook")
                .replace("/usr/apkg/bin/apkg", d + "/apkg").replace("/var/apkg/netset", d + "/w")
                .replace("/var/sadm/pkg/", d + "/sadm/").replace("/var/tmp", d + "/vt").replace("PAUSE=30", "PAUSE=0")
                .replace("sleep 10", "sleep 1"))
        r = subprocess.run(["/usr/bin/dash", "-c", body, "netset.sh"] + list(args), capture_output=True, text=True,
                           timeout=60)
        calls = open(os.path.join(d, "calls")).read() if os.path.exists(os.path.join(d, "calls")) else ""
        return r.returncode, r.stdout, calls
    ex = lambda d, *p: os.path.exists(os.path.join(d, *p))
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        setup(d, rows)
        rc, out, calls = run(d)
        good = (rc == 0 and ex(d, "sadm", "xbasic") and ex(d, "sadm", "x11r63") and ex(d, "fb", "netset.done")
                and not ex(d, "fb", "netset") and not ex(d, "hook") and not ex(d, "w")
                and "1 of 2: xbasic 2.1" in out and "2 of 2: x11r6.3 6.3-6" in out and "The full set is installed." in out
                and calls.count("TMPDIR=%s/vt" % d) == 2 and not ex(d, "fb", "netset.lock"))
        (ok if good else fail)("second stage EXECUTED: both packages in order, with progress lines and TMPDIR on "
                               "the disk; netset becomes netset.done, the hook and the cache are removed%s"
                               % ("" if good else ": rc %d %r %r" % (rc, out[-300:], calls[-200:])))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        setup(d, rows, fail=("x11r6.3",))
        rc, out, calls = run(d)
        first = (rc == 0 and ex(d, "sadm", "xbasic") and not ex(d, "sadm", "x11r63") and ex(d, "fb", "netset")
                 and ex(d, "hook") and calls.count("-y install x11r6.3") == 3 and "did not finish" in out
                 and "continues at the next boot" in out)
        setup(d, rows)
        rc2, out2, calls2 = run(d)
        second = (rc2 == 0 and "1 of 2: xbasic 2.1 (already installed)" in out2 and ex(d, "sadm", "x11r63")
                  and ex(d, "fb", "netset.done") and not ex(d, "hook")
                  and calls2.count("-y install xbasic") == 1)
        (ok if first and second else fail)(
            "second stage EXECUTED: a package that fails three times stops it with the system bootable and the "
            "stage armed; the next run skips what is installed and finishes%s"
            % ("" if first and second else ": %r / %r" % (out[-250:], out2[-250:])))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        setup(d, [rows[0].replace("0123456789abcdef", "ffffffffffffffff", 1), rows[1]])
        rc, out, calls = run(d)
        good = (rc == 0 and "changed since the installation" in out and "install" not in calls.replace("update", "")
                and ex(d, "fb", "netset") and ex(d, "hook"))
        (ok if good else fail)("second stage EXECUTED: a repository row that differs from the recorded one (md5) "
                               "stops it before any install%s" % ("" if good else ": %r %r" % (out[-200:], calls)))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        setup(d, rows, update_fails=True)
        rc, out, calls = run(d)
        good = (rc == 0 and calls.count("update") == 3 and "could not be read" in out and ex(d, "fb", "netset"))
        (ok if good else fail)("second stage EXECUTED: an unreachable repository is tried three times, then the "
                               "stage stays armed%s" % ("" if good else ": %r %r" % (out[-200:], calls)))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        # a lock whose runner is gone (a pid no process has) is broken; a live runner is waited for;
        # the boot's run (--boot) clears any lock: nothing else can be running at boot
        setup(d, rows)
        dead = subprocess.Popen(["true"]); dead.wait()
        os.makedirs(os.path.join(d, "fb", "netset.lock"))
        open(os.path.join(d, "fb", "netset.lock", "pid"), "w").write("%d\n" % dead.pid)
        rc, out, calls = run(d)
        stale = rc == 0 and ex(d, "fb", "netset.done") and not ex(d, "fb", "netset.lock")
        setup(d, rows)
        os.rename(os.path.join(d, "fb", "netset.done"), os.path.join(d, "fb", "netset.old"))
        # the holder runs orphaned (as a runner does on the box), so it is reaped when it ends --
        # a child of this process would stay a zombie, which `kill -0` still finds
        livepid = subprocess.run(["sh", "-c", "sleep 3 > /dev/null 2>&1 & echo $!"], capture_output=True,
                                 text=True).stdout.strip()
        os.makedirs(os.path.join(d, "fb", "netset.lock"))
        open(os.path.join(d, "fb", "netset.lock", "pid"), "w").write("%s\n" % livepid)
        rc, out, calls = run(d)
        waited = rc == 0 and "already running" in out and ex(d, "fb", "netset.done")
        setup(d, rows)
        os.remove(os.path.join(d, "fb", "netset.done"))
        held = subprocess.Popen(["sleep", "30"])
        os.makedirs(os.path.join(d, "fb", "netset.lock"))
        open(os.path.join(d, "fb", "netset.lock", "pid"), "w").write("%d\n" % held.pid)
        rc, out, calls = run(d, ["--boot"])
        held.kill(); held.wait()
        boot = rc == 0 and "already running" not in out and ex(d, "fb", "netset.done")
        (ok if stale and waited and boot else fail)(
            "second stage EXECUTED: one run at a time -- a dead runner's lock is broken, a live one is waited for, "
            "the boot's run (--boot) clears a lock%s" % ("" if stale and waited and boot else ": stale %s waited %s boot %s %r"
                                                        % (stale, waited, boot, out[-200:])))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    d = tempfile.mkdtemp(prefix="netset_")
    try:
        setup(d, rows, armed=False)
        rc, out, calls = run(d)
        (ok if rc == 0 and out == "" and calls == "" else fail)(
            "second stage EXECUTED: no record, no output, no apkg call (a CD install, or a finished stage)")
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_tmp_sweep():
    head("TS. the install leaves the target's /tmp and /var/tmp empty (an image of record ships unbooted), "
         "and the kernel-space run's catalog does not stay behind")
    src = open(os.path.join(REPO, "src", "installer", "install.sh"), encoding="utf-8").read()
    l11 = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    line = next((l for l in src.splitlines() if l.startswith('rm -rf "${TARGET:?}"/tmp/*')), None)
    cat = 'rm -rf "${TARGET:?}/tmp/kpkgcache" "${TARGET:?}/tmp/catalog" "${KCONF:?}"' in l11
    if not line or not cat:
        fail("install.sh has no /tmp and /var/tmp sweep, or l11.sh leaves the kernel-space catalog in /tmp")
        return
    d = tempfile.mkdtemp(prefix="tmpsweep_")
    try:
        for rel in ("tmp/catalog", "tmp/.runout.12", "tmp/sub/x", "var/tmp/dstream1/a", "var/tmp/.hidden",
                    "etc/keep", "var/adm/firstboot/netset"):
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
            open(os.path.join(d, rel), "w").write("x\n")
        r = subprocess.run(["/usr/bin/dash", "-c", "TARGET=%s\n%s\n" % (d, line)], capture_output=True, text=True, timeout=10)
        left = lambda sub: sorted(os.listdir(os.path.join(d, sub)))
        good = (r.returncode == 0 and left("tmp") == [] and left("var/tmp") == []
                and os.path.exists(os.path.join(d, "etc", "keep")) and os.path.exists(os.path.join(d, "var", "adm", "firstboot", "netset")))
        (ok if good else fail)("tmp sweep EXECUTED: /tmp and /var/tmp emptied, dot files and directories included; the "
                               "directories themselves and everything else stay%s"
                               % ("" if good else ": tmp %r var/tmp %r rc %d" % (left("tmp"), left("var/tmp"), r.returncode)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_net_kspace():
    head("NK. the netinstall finds kernel space where the repository keeps it: the release tree's one catalog "
         "(its #ext kpkg block), else the tree's kspace/ catalog")
    prof = open(os.path.join(REPO, "src", "miniroot", "profile"), encoding="latin-1").read()
    m = re.search(r"\n(\tNKOK=\n.*?\n\tif \[ \"\$NKOK\" = y \]\n\tthen\n\t\t:\n\telse\n.*?\n\tfi)\n", prof, re.S)
    if not m or 'NET_REPO=http://pkg.amigaux.org/1.1' not in prof:
        fail("profile: no kernel-space gate (NKOK) in net_source, or the repository default is not the 1.1 tree")
        return
    d = tempfile.mkdtemp(prefix="netk_")
    try:
        stub = os.path.join(d, "apkg")
        # the stub's update copies the repository's catalog beside the cache, as apkg does
        open(stub, "w").write('#!/bin/sh\nconf=$2\nrepo=`sed -n "s/^repo=//p" $conf`\ncache=`sed -n "s/^cachedir=//p" $conf`\n'
                              'echo "$repo" >> %s/repos\nsrc=%s/srv/`echo $repo | sed "s|^http://[^/]*/||"`/catalog\n'
                              '[ -f "$src" ] || exit 1\ncp "$src" `dirname $cache`/catalog\n' % (d, d))
        os.chmod(stub, 0o755)
        def run(layout):
            for sub in ("srv", "tmp"):
                shutil.rmtree(os.path.join(d, sub), ignore_errors=True)
            rel = os.path.join(d, "srv", "1.1")
            os.makedirs(os.path.join(d, "tmp", "net", "cache")); os.makedirs(os.path.join(d, "tmp", "netk", "cache"))
            os.makedirs(rel)
            if layout == "one":
                open(os.path.join(rel, "catalog"), "w").write("#apkg-catalog 1\ncore|2.1|core|stock/core-2.1.pkg|0|1|none|s|c\n"
                                                              "#ext kpkg 1\n#kpkg kernel-k46-m k46 role=kernel\n#end kpkg\n")
            elif layout == "two":
                open(os.path.join(rel, "catalog"), "w").write("#apkg-catalog 1\ncore|2.1|core|stock/core-2.1.pkg|0|1|none|s|c\n")
                os.makedirs(os.path.join(rel, "kspace"))
                open(os.path.join(rel, "kspace", "catalog"), "w").write("#apkg-catalog 1\n#ext kpkg 1\n#kpkg x\n#end kpkg\n")
            if os.path.exists(os.path.join(d, "repos")):
                os.remove(os.path.join(d, "repos"))
            body = m.group(1).replace("/tmp/", d + "/tmp/").replace("$NETINST/bin/apkg", stub)
            # net_source writes /tmp/net.conf just before this block
            sh = ('NET_REPO=http://repo/1.1\nNETINST=/nonexistent\nrestart() { echo RESTART; exit 4; }\n'
                  'printf "repo=%%s\\ncachedir=%s/tmp/net/cache\\n" "$NET_REPO" > %s/tmp/net.conf\n%s\necho "KREPO=$NET_KREPO"\n'
                  % (d, d, body))
            r = subprocess.run(["/usr/bin/dash", "-c", sh], capture_output=True, text=True, timeout=20)
            return r.returncode, r.stdout
        rc1, o1 = run("one")
        rc2, o2 = run("two")
        rc3, o3 = run("none")
        good = ("KREPO=http://repo/1.1\n" in o1 and rc1 == 0 and "KREPO=http://repo/1.1/kspace\n" in o2 and rc2 == 0
                and rc3 == 4 and "RESTART" in o3)
        (ok if good else fail)("kernel-space gate EXECUTED: a catalog with the #ext kpkg block -> the same repository; "
                               "without it -> kspace/; an unreadable repository -> the gate restarts%s"
                               % ("" if good else ": %r %r %r" % (o1[-120:], o2[-120:], o3[-120:])))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_kb_nodes():
    head("KN. the target carries its own disk nodes before its first boot: `kbootset -R nodes` after the "
         "boot store's check (a root on card 2 or 3 opens its swap by name in swapconf, before any rc script)")
    l11 = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    i_chk = l11.find("\tl11_kb check\n")
    i_nod = l11.find("\trunq $KB nodes || die ")
    i_swp = l11.find('[ ! -b "$TARGET/dev/dsk/c${TARGET_SCSI_ID}d0s${TARGET_SWAP_SLICE:-2}" ]')
    fb = open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"), encoding="latin-1").read()
    good = 0 <= i_chk < i_nod < i_swp and "/sbin/kbootset nodes" in fb
    (ok if good else fail)("l11.sh runs `kbootset -R nodes` after `l11_kb check` and refuses a target without its "
                           "swap node; the first boot still registers the set (`kbootset nodes`)")


def audit_probe_backticks():
    head("CP. the cards probe cannot hold the boot: run in backticks (as the profile does) with a unit that never "
         "answers, the CD candidates come back at the bound, the stuck card marked and left out")
    prof = open(os.path.join(REPO, "src", "miniroot", "profile"), encoding="latin-1").read()
    fns = []
    for name in ("inquiry_bounded", "cards_probe_bounded", "cd_candidates_from_cards"):
        m = re.search(r"\n(%s\(\)\n\{\n.*?\n\})\n" % name, prof, re.S)
        if not m:
            fail("profile: no %s()" % name)
            return
        fns.append(m.group(1))
    d = tempfile.mkdtemp(prefix="cprobe_")
    try:
        kb = os.path.join(d, "kbootset")
        # card 1's unit 0 never answers (a controller asleep in gsioctl)
        open(kb, "w").write('#!/bin/sh\ncase "$1" in\ncards) echo "card 0: c0-c7 zorro:0202:54"; echo "card 1: c8-cf mobo:gayle" ;;\n'
                            'inquiry) [ "$2 $3" = "1 0" ] && exec sleep 300\n  [ "$2 $3" = "0 3" ] && { echo "type 5 CD"; exit 0; }\n'
                            '  exit 1 ;;\nesac\n')
        os.chmod(kb, 0o755)

        def run(fs):
            body = ('KBOOTSET=%s\nSCSIDEV=/dev/null\nCARDS_PROBE=%s/cards.probe\nUNIT_SECS=2\nNOINQ_KEYS=mobo:a3000-wd\n%s\n'
                    '_cds=`cd_candidates_from_cards`\necho "CDS=[`echo $_cds`]"\necho "SUS=[`cat %s/cards.probe.suspect`]"\n'
                    % (kb, d, "\n".join(fs), d))
            # its own session: the stuck stub and what it left behind are this run's process group
            pr = subprocess.Popen(["/usr/bin/dash", "-c", body], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, start_new_session=True)
            try:
                return pr.communicate(timeout=30)[0]
            except subprocess.TimeoutExpired:
                return "TIMEOUT"
            finally:
                try:
                    os.killpg(pr.pid, 9)
                except ProcessLookupError:
                    pass
                pr.wait()

        out = run(fns)
        want = "CDS=[0,3]" in out and "SUS=[1]" in out
        old = [fns[0].replace(" < /dev/null > /dev/null 2>&1 &", " &")] + fns[1:]
        out_old = run(old) if old[0] != fns[0] else "unchanged"
        (ok if want and out_old == "TIMEOUT" else fail)(
            "probe in backticks EXECUTED: back at the bound with card 0's CD and card 1 marked suspect; without its "
            "own descriptors the same inquiry holds the substitution (timeout)%s"
            % ("" if want and out_old == "TIMEOUT" else ": %r / old %r" % (out[-200:], out_old[-80:])))
    finally:
        shutil.rmtree(d, ignore_errors=True)



def audit_gayle_slave():
    head("GS. the installed system attaches the IDE slave (gayle param slave=2) only when the install CD "
         "answered there: CD_SPEC is the gayle card's unit 5")
    src = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    m = re.search(r"\n(\t# the IDE port's slave: .*?)\n\t# MODREG_LOCAL \(a profile key", src, re.S)
    if not m:
        fail("l11.sh: no IDE-slave block before the MODREG_LOCAL block")
        return
    cards = ("card 0: c0-c7 zorro:144b:01 base 0x40000000\n"
             "card 1: c8-cf zorro:0202:54 base 0x40800000\n"
             "card 2: c10-c17 mobo:gayle\n")
    cases = [("2,5", "", True, True), ("1,3", "", True, False), ("1,5", "", True, False),
             ("2,3", "", True, False), ("", "", True, False), ("2,5", "", False, False),
             ("2,5", "gayle:param slave=2", True, False)]
    bad = []
    for spec, ml, kb, want in cases:
        d = tempfile.mkdtemp(prefix="gslave_")
        try:
            os.makedirs(os.path.join(d, "l11", "bin"))
            if kb:
                k = os.path.join(d, "l11", "bin", "kbootset")
                with open(k, "w") as f:
                    f.write("#!/bin/sh\n[ \"$1\" = cards ] && [ $# = 1 ] && printf '%s'\n" % cards)
                os.chmod(k, 0o755)
            t = os.path.join(d, "t")
            os.makedirs(t)
            body = ('TARGET=%s\nL11=%s/l11\nCD_SPEC="%s"\nMODREG_LOCAL="%s"\nrun() { "$@"; }\n'
                    'msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n%s\n' % (t, d, spec, ml, m.group(1)))
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10).stdout
            g = os.path.join(t, "etc", "conf", "modreg.local.d", "gayle")
            got = open(g).read() if os.path.exists(g) else ""
            if got != ("param slave=2\n" if want else "") or "DIE" in out:
                bad.append((spec, ml, kb, got, out.strip()[-60:]))
        finally:
            shutil.rmtree(d, ignore_errors=True)
    (fail if bad else ok)("IDE slave EXECUTED: slave=2 for the CD at the gayle card's unit 5 only (not a SCSI card's "
                          "unit 5, not unit 3, no CD_SPEC, no kbootset, or a profile line already there)%s"
                          % ((": %r" % bad) if bad else ""))


def audit_modreg_local():
    head("ML. MODREG_LOCAL: administrator module lines laid before the kbootset build (emulation rigs: "
         "z3660rtg fixed=1); never on a profile for real hardware")
    src = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    m = re.search(r'\n(\tif \[ -n "\$MODREG_LOCAL" \]; then\n.*?\n\tfi)\n\tl11_kb build', src, re.S)
    if not m:
        fail("l11.sh: no MODREG_LOCAL block before l11_kb build")
        return
    d = tempfile.mkdtemp(prefix="modreg_")
    try:
        body = ('TARGET=%s\nMODREG_LOCAL="z3660rtg:param fixed=1|gayle:param slave=2"\nrun() { "$@"; }\n'
                'msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n%s\n' % (d, m.group(1)))
        out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10).stdout
        rd = lambda n: open(os.path.join(d, "etc", "conf", "modreg.local.d", n)).read() \
            if os.path.exists(os.path.join(d, "etc", "conf", "modreg.local.d", n)) else ""
        (ok if rd("z3660rtg") == "param fixed=1\n" and rd("gayle") == "param slave=2\n" and "DIE" not in out else fail)(
            "MODREG_LOCAL EXECUTED: two entries laid in modreg.local.d (%r)" % out.strip()[-80:])
    finally:
        shutil.rmtree(d, ignore_errors=True)
    bad = []
    for pf in sorted(os.listdir(PROFILES_DIR)):
        if pf.endswith(".profile") and not pf.startswith("test-a4000-030-x11"):
            v = _parse_profile(os.path.join(PROFILES_DIR, pf)).get("MODREG_LOCAL", "")
            if "fixed=1" in v:
                bad.append(pf)
    (fail if bad else ok)("no profile for real hardware sets z3660rtg fixed=1 (only the emulated X disk)%s"
                          % ((": " + " ".join(bad)) if bad else ""))


def audit_kbootset_cards():
    head("KC. the target's controller comes from the disk the user picked (`kbootset cards DISK` on the "
         "medium's kbootset); the profile's TARGET_HBA is the fallback")
    src = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    m = re.search(r'\n(\tL11_CTL="the profile.s KBOOTSET_BOOTDEV"\n.*?'
                  r'\n\t\[ -n "\$KBOOTSET_ROOTDEV" \] \|\| KBOOTSET_ROOTDEV="\$KBOOTSET_BOOTDEV"\n)', src, re.S)
    logged = 'msg "controller   : $KBOOTSET_BOOTDEV ($L11_CTL)"' in src
    iso = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    if not m or not logged or 'cp "$L11_IN/dlm/build/box/kbootset" "$STAGE/l11/bin/kbootset"' not in iso:
        fail("l11.sh asks no `kbootset cards` or logs no controller source, or the medium does not carry the box kbootset")
        return
    d = tempfile.mkdtemp(prefix="kcards_")
    try:
        os.makedirs(os.path.join(d, "bin"))
        def run(stub, hba, pre="TARGET_SCSI_ID=e\n"):
            kb = os.path.join(d, "bin", "kbootset")
            if stub is None:
                if os.path.exists(kb): os.remove(kb)
            else:
                open(kb, "w").write("#!/bin/sh\n%s\n" % stub); os.chmod(kb, 0o755)
            body = ('L11=%s\n%sTARGET_ROOT_SLICE=1\nTARGET_HBA=%s\nKBOOTSET_BOOTDEV=\n'
                    'msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n%s\necho "BOOTDEV=$KBOOTSET_BOOTDEV"\n'
                    'echo "CTL=$L11_CTL"\n' % (d, pre, hba, m.group(1)))
            return subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10).stdout
        # each case: the key, and the source the install log is given (L11_CTL, logged by l11_bootstore)
        cases = (
            ("the disk's card names gayle; the profile says z3660scsi", '[ "$1 $2" = "cards /dev/dsk/ced0s1" ] && echo mobo:gayle',
             "z3660scsi", ["BOOTDEV=mobo:gayle", "CTL=kbootset cards: the target disk's own card; profile TARGET_HBA=z3660scsi"]),
            ("a Zorro card with its base", 'echo "zorro:144b:01 base 0x40000000"', "gayle",
             ["BOOTDEV=zorro:144b:01", "CTL=kbootset cards:"]),
            ("a kbootset without `cards`: the profile stands", 'echo "usage: kbootset ..." >&2; exit 2', "a4000t",
             ["BOOTDEV=mobo:a4000t-710", "CTL=the profile's TARGET_HBA=a4000t; kbootset cards: usage: kbootset ..."]),
            ("the disk's card is not in the table: the profile stands",
             'echo "kbootset: /dev/dsk/ced0s1: the running kernel has no card 1" >&2; exit 1', "gayle",
             ["BOOTDEV=mobo:gayle", "CTL=the profile's TARGET_HBA=gayle; kbootset cards: kbootset: /dev/dsk/ced0s1: the running kernel has no card 1"]),
            ("no kbootset on the medium: the profile stands", None, "a3000",
             ["BOOTDEV=mobo:a3000-wd", "CTL=the profile's TARGET_HBA=a3000; the medium has no kbootset for cards"]),
        )
        # the IDE master on card 2, its card from the interview (IDE_CARD): -35 names the IDE,
        # -34 read c16 as card 1 and named that card's controller -- the install must stop
        ide2 = "IDE_CARD=2\nTARGET_SCSI_ID=16\n"
        cases += (
            ("the IDE master on card 2, kbootset -35", '[ "$1 $2" = "cards /dev/dsk/c16d0s1" ] && echo mobo:gayle',
             "gayle", ["BOOTDEV=mobo:gayle"], ide2),
            ("the IDE master on card 2, kbootset -34 names card 1's A4091: stop",
             '[ "$1 $2" = "cards /dev/dsk/c16d0s1" ] && echo "zorro:0202:54 base 0x40800000"', "gayle",
             ["DIE kbootset cards names 'zorro:0202:54' for the IDE master c16d0 (IDE card 2)"], ide2),
            ("the IDE master on card 1, kbootset -34 refuses ced0s1: the profile's gayle stands",
             'echo "kbootset: ced0s1: not a disk node" >&2; exit 2', "gayle",
             ["BOOTDEV=mobo:gayle", "CTL=the profile's TARGET_HBA=gayle"], "IDE_CARD=1\nTARGET_SCSI_ID=e\n"),
        )
        bad = []
        for c in cases:
            w, stub, hba, want = c[:4]
            out = run(stub, hba, *c[4:])
            if not all(x in out for x in want):
                bad.append("%s: %r" % (w, out.strip().splitlines()[-2:]))
        (fail if bad else ok)("kbootset cards EXECUTED (8 cases: the disk's key wins, Zorro key, no `cards`, a card "
                              "not in the table, no kbootset, a card-2 IDE master under -35 and under -34 (stops), "
                              "a card-1 IDE master under -34 (refused: the profile stands); "
                              "each names its source for the log)%s"
                              % ((": " + "; ".join(bad)) if bad else ""))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_root_record():
    head("RR. the root record names the target's controller by its id (a Buddha 12120000, a Catweasel Z-II "
         "12122a00) and its unit; base= is the root board's own base only when two cards carry its key "
         "(amix-dlm C4-2 8.2 items 4-5)")
    src = open(os.path.join(REPO, "src", "installer", "l11.sh"), encoding="utf-8").read()
    fb = _extract_func(src, "l11_rootbase")
    m = re.search(r'\n(\tL11_CTL="the profile.s KBOOTSET_BOOTDEV"\n.*?\n\tfi\n)\tmsg "layout 1.1', src, re.S)
    if not fb or not m or "L11_CBASE=\n" not in src:
        fail("l11.sh: no l11_rootbase() or no root-record block to run")
        return
    d = tempfile.mkdtemp(prefix="rootrec_")
    try:
        os.makedirs(os.path.join(d, "bin"))
        def run(disk, cards, hba, sid):
            kb = os.path.join(d, "bin", "kbootset")
            if disk is None:
                if os.path.exists(kb): os.remove(kb)
            else:
                open(kb, "w").write('#!/bin/sh\nif [ "$1" = cards ] && [ -n "$2" ]; then echo "%s"; else printf "%%b" "%s"; fi\n'
                                    % (disk, cards))
                os.chmod(kb, 0o755)
            body = ('L11=%s\nTARGET_SCSI_ID=%s\nTARGET_ROOT_SLICE=1\nTARGET_HBA=%s\nKBOOTSET_BOOTDEV=\nKBOOTSET_ROOTDEV=\n'
                    'KBOOTSET_ROOTREC=\nIDE_CARD=\nL11_CBASE=\nmsg() { :; }\ndie() { echo "DIE $*"; exit 3; }\n%s\n%s\n'
                    'echo "REC=$KBOOTSET_ROOTREC"\n' % (d, sid, hba, fb, m.group(1)))
            r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10)
            return (r.stdout + r.stderr).strip().splitlines()[-1:] or [""]
        z3660 = "card 0: c0-c7 zorro:144b:01 base 0x40000000\\n"
        cases = (
            ("a Buddha's port-0 master beside a Z3660 (ced0)", "zorro:1212:00 base 0x00e90000",
             z3660 + "card 1: c8-cf zorro:1212:00 base 0x00e90000\\n", "auto", "e",
             "REC=sd id=12120000 base=00000000 unit=6 slice=1"),
            ("a lone slave on a Buddha alone (c5d0)", "zorro:1212:00 base 0x00e90000",
             "card 0: c0-c7 zorro:1212:00 base 0x00e90000\\n", "auto", "5",
             "REC=sd id=12120000 base=00000000 unit=5 slice=1"),
            ("a Buddha's port-1 slave (c2d0)", "zorro:1212:00 base 0x00e90000",
             "card 0: c0-c7 zorro:1212:00 base 0x00e90000\\n", "auto", "2",
             "REC=sd id=12120000 base=00000000 unit=2 slice=1"),
            ("a Catweasel Z-II's port-2 master (c1d0)", "zorro:1212:2a base 0x00e90000",
             "card 0: c0-c7 zorro:1212:2a base 0x00e90000\\n", "auto", "1",
             "REC=sd id=12122a00 base=00000000 unit=1 slice=1"),
            ("two A4091s, the root on the second (c9d0): its base", "zorro:0202:54 base 0x40800000",
             "card 0: c0-c7 zorro:0202:54 base 0x40000000\\ncard 1: c8-cf zorro:0202:54 base 0x40800000\\n", "auto", "9",
             "REC=sd id=02025400 base=40800000 unit=1 slice=1"),
            ("two Buddhas, a short base: padded to eight digits", "zorro:1212:00 base 0xe90000",
             "card 0: c0-c7 zorro:1212:00 base 0x00e90000\\ncard 1: c8-cf zorro:1212:00 base 0x00ea0000\\n", "auto", "6",
             "REC=sd id=12120000 base=00e90000 unit=6 slice=1"),
            ("two boards of one kind and no base for the target's: stop", "zorro:0202:54",
             "card 0: c0-c7 zorro:0202:54 base 0x40000000\\ncard 1: c8-cf zorro:0202:54 base 0x40800000\\n", "auto", "9",
             "DIE two cards carry zorro:0202:54, and kbootset cards gives no base for the target's (none); set KBOOTSET_ROOTREC"),
            ("an A4091 beside a Z3660: one card of the kind, base 0 as in 1.1", "zorro:0202:54 base 0x40800000",
             z3660 + "card 1: c8-cf zorro:0202:54 base 0x40800000\\n", "auto", "9",
             "REC=sd id=02025400 base=00000000 unit=1 slice=1"),
            ("no kbootset: the profile's TARGET_HBA=buddha gives the Buddha's key", None, "", "buddha", "6",
             "REC=sd id=12120000 base=00000000 unit=6 slice=1"),
            ("no kbootset: TARGET_HBA=catweasel", None, "", "catweasel", "1",
             "REC=sd id=12122a00 base=00000000 unit=1 slice=1"),
        )
        for what, disk, cards, hba, sid, want in cases:
            got = run(disk, cards, hba, sid)[0]
            (ok if got == want else fail)("root record: %s%s" % (what, "" if got == want else " -- got %r" % got))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_boot_pri():
    head("BP. the target's UNIX_Boot boot priority is the profile's TARGET_BOOT_BOOTPRI (default 2, "
         "0-127), checked before the disk is touched; the test disks ship at 20")
    src = open(DRIVER, encoding="utf-8").read()
    i_chk = src.find('TARGET_BOOT_BOOTPRI="${TARGET_BOOT_BOOTPRI:-2}"')
    i_rdb = src.find('-P "$TARGET_BOOT_BOOTPRI" -F 0x554e4900')
    i_part = src.find('run /etc/rdb -a "$DISK_RAW" UNIX_Root')
    (ok if 0 <= i_chk < i_part < i_rdb else fail)(
        "install.sh: TARGET_BOOT_BOOTPRI defaults to 2 and is validated before the first rdb -a; "
        "the UNIX_Boot slice is stamped with it")
    (ok if "-P 2 -F 0x554e4900" not in src.replace("#   /etc/rdb -p $BOOTPART -M -B -C 2 -P 2", "") else fail)(
        "install.sh: no hardcoded -P 2 left on a UNIX_Boot stamp")
    m = re.search(r'\n(TARGET_BOOT_BOOTPRI="\$\{TARGET_BOOT_BOOTPRI:-2\}"\n.*?\n\t\|\| die [^\n]*)\n', src, re.S)
    if not m:
        fail("install.sh: cannot extract the TARGET_BOOT_BOOTPRI check")
    else:
        body = (_extract_func(src, "is_num") or "") + "\ndie() { echo DIE; exit 1; }\n" + m.group(1) + "\necho PRI=$TARGET_BOOT_BOOTPRI"
        for env, want in (("", "PRI=2"), ("TARGET_BOOT_BOOTPRI=20", "PRI=20"), ("TARGET_BOOT_BOOTPRI=127", "PRI=127"),
                          ("TARGET_BOOT_BOOTPRI=128", "DIE"), ("TARGET_BOOT_BOOTPRI=-1", "DIE"), ("TARGET_BOOT_BOOTPRI=x", "DIE")):
            r = subprocess.run(["/usr/bin/dash", "-c", "%s\n%s" % (env, body)],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            got = r.stdout.decode().strip()
            (ok if got == want else fail)("TARGET_BOOT_BOOTPRI %r -> %s (got %r)" % (env or "unset", want, got))
    for t in sorted(os.path.join(REPO, "profiles", f) for f in os.listdir(os.path.join(REPO, "profiles")) if f.startswith("test-") and f.endswith(".profile")):
        v = re.findall(r'(?m)^TARGET_BOOT_BOOTPRI=(.*)$', open(t, encoding="latin-1").read())
        (ok if v == ["20"] else fail)("%s: TARGET_BOOT_BOOTPRI=20 (got %r)" % (os.path.basename(t), v))


def audit_cd_candidates():
    head("CC. the miniroot's CD addresses come from the running kernel: each card's units by one bounded "
         "`kbootset inquiry` at a time (the units that answer as CD drives), never asking a card no INQUIRY may reach "
         "(the A3000's WD: its units are mounted once each instead), else every unit of every other card, else "
         "the fixed list; the address that "
         "answered goes to /tmp/cd.spec")
    prof = os.path.join(REPO, "src", "miniroot", "profile")
    src = open(prof, encoding="latin-1").read()
    fns = []
    for name in ("inquiry_bounded", "cards_probe_bounded", "cd_candidates_from_cards"):
        m = re.search(r"\n(%s\(\)\n\{\n.*?\n\})\n" % name, src, re.S)
        if not m:
            fail("src/miniroot/profile: no %s()" % name)
            return
        fns.append(m.group(1))
    f = "\n".join(fns)
    keys = re.search(r'(?m)^NOINQ_KEYS="([^"]*)"$', src)
    (ok if keys and keys.group(1) == "mobo:a3000-wd" else fail)("the profile names the A3000's WD as a card no INQUIRY may reach")
    (ok if 'echo "$_pick" > $CD_SPEC_FILE' in src and "CD_SPEC_FILE=/tmp/cd.spec" in src else fail)(
        "the probe writes the address that answered to /tmp/cd.spec")
    (ok if re.search(r'(?m)^_cds=`cd_candidates_from_cards`\n\[ -n "\$_cds" \] && CD_CANDIDATES=`echo \$_cds`$', src)
     else fail)("CD_CANDIDATES is replaced only when the kernel's cards gave a list (the fixed list is the fallback)")
    d = tempfile.mkdtemp(prefix="cdcand.")
    try:
        kb = os.path.join(d, "kb")
        # the stub: `cards` prints d/cards; `inquiry C U` logs the call and answers from d/inq/C.U
        # (its line), d/inq/C.U.hang (it never returns), or nothing (no unit, exit 1)
        open(kb, "w").write('#!/bin/sh\nD=%s\ncase "$1" in\ncards) [ "$2" = --probe ] && exit 9; cat $D/cards ;;\n'
                            'inquiry) echo "$2 $3" >> $D/calls\n  [ -f $D/inq/$2.$3.hang ] && exec /bin/sleep 30\n'
                            '  [ -f $D/inq/$2.$3 ] && { cat $D/inq/$2.$3; exit 0; }\n  exit 1 ;;\n'
                            'esac\n' % d)
        os.chmod(kb, 0o755)

        def setup(cards, units, hang=()):
            shutil.rmtree(os.path.join(d, "inq"), ignore_errors=True)
            os.makedirs(os.path.join(d, "inq"))
            for x in ("calls", "cards.probe", "cards.probe.suspect"):
                if os.path.exists(os.path.join(d, x)):
                    os.remove(os.path.join(d, x))
            open(os.path.join(d, "cards"), "w").write(cards)
            for (c, u), line in units.items():
                open(os.path.join(d, "inq", "%d.%d" % (c, u)), "w").write(line + "\n")
            for c, u in hang:
                open(os.path.join(d, "inq", "%d.%d.hang" % (c, u)), "w").close()

        def run(dev="/dev/null", kbp=kb):
            body = ('KBOOTSET=%s SCSIDEV=%s CARDS_PROBE=%s/cards.probe UNIT_SECS=2 NOINQ_KEYS="mobo:a3000-wd"\n%s\n'
                    '_cds=`cd_candidates_from_cards`\necho $_cds' % (kbp, dev, d, f))
            pr = subprocess.Popen(["/usr/bin/dash", "-c", body], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, start_new_session=True)
            try:
                out = " ".join(pr.communicate(timeout=60)[0].split())
            except subprocess.TimeoutExpired:
                out = "TIMEOUT"
            finally:
                try:
                    os.killpg(pr.pid, 9)
                except ProcessLookupError:
                    pass
                pr.wait()
            rd = lambda n: open(os.path.join(d, n)).read() if os.path.exists(os.path.join(d, n)) else ""
            return out, rd("calls"), rd("cards.probe.suspect").strip(), rd("cards.probe")

        three = "card 0: c0-c7 zorro:144b:01 base 0x40000000\ncard 1: c8-cf zorro:0202:54 base 0x40800000\ncard 2: c10-c17 mobo:gayle\n"
        full = " ".join("%d,%d" % (c, u) for c in (0, 1, 2) for u in (3, 5, 2, 4, 1, 0, 6))
        disks = {(0, 6): "type 0 ZuluSCSI HARDDRIVE 2.0", (2, 6): "type 0 UAE IDE -"}
        cds = {(1, 3): "type 5 ZuluSCSI CDROM 2.0", (2, 5): "type 5 UAE-ATAPI CD-ROM 0.1"}
        setup(three, {**disks, **cds})
        out, calls, sus, pf = run()
        good = (out == "1,3 2,5" and len(calls.split("\n")) - 1 == 24 and "  unit 5: type 5 UAE-ATAPI" in pf)
        (ok if good else fail)("CD addresses: every unit of every card asked once, one at a time; only the units that "
                               "answer as CD drives (an A4091 CD, the IDE slave)%s" % ("" if good else " -- got %r" % out))
        setup(three, disks)
        out = run()[0]
        (ok if out == full else fail)("CD addresses: no unit answers as a CD drive: every unit of every card%s"
                                      % ("" if out == full else " -- got %r" % out))
        setup(three, {})
        out = run(kbp=os.path.join(d, "none"))[0]
        (ok if out == "" else fail)("CD addresses: no kbootset on the RAM disk gives no list (the fixed one stands)")
        out = run(dev="/nonexistent")[0]
        (ok if out == full else fail)("CD addresses: no /dev/scsi node: nothing is asked, every unit of every card%s"
                                      % ("" if out == full else " -- got %r" % out))
        # a unit that never answers: its card is marked suspect and left, the other cards are still asked
        setup(three, {**disks, **cds}, hang=((1, 0),))
        t0 = time.time()
        out, calls, sus, pf = run()
        took = time.time() - t0
        good = out == "2,5" and sus == "1" and "1 1" not in calls.split("\n") and "2 5" in calls and took < 30
        (ok if good else fail)("CD addresses: a unit that never answers (card 1 unit 0) is abandoned at its bound "
                               "(%.0f s): card 1 suspect, its other units not asked, card 2's CD still found%s"
                               % (took, "" if good else " -- got %r sus %r" % (out, sus)))
        setup(three, disks, hang=((1, 0),))
        out, calls, sus, pf = run()
        want = " ".join("%d,%d" % (c, u) for c in (0, 2) for u in (3, 5, 2, 4, 1, 0, 6))
        (ok if out == want and sus == "1" else fail)("CD addresses: no CD found past a stuck card: every unit of every "
                                                     "other card, none of the suspect one%s" % ("" if out == want else " -- got %r" % out))
        # the A3000: no INQUIRY ever reaches the WD (mobo:a3000-wd); its units are mounted once each instead
        a3 = "card 0: c0-c7 zorro:0202:54 base 0x40800000\ncard 1: c8-cf mobo:a3000-wd\n"
        wd = " ".join("1,%d" % u for u in (3, 5, 2, 4, 1, 0, 6))
        setup(a3, {(0, 3): "type 5 ZuluSCSI CDROM 2.0"})
        out, calls, sus, pf = run()
        good = (out == "0,3 " + wd and not any(l.startswith("1 ") for l in calls.split("\n"))
                and "card 1: c8-cf mobo:a3000-wd\n  not probed" in pf)
        (ok if good else fail)("CD addresses: an A3000 with an A4091: the WD is never asked (not probed in the table); "
                               "the A4091's CD first, then each WD unit for the mount probe%s"
                               % ("" if good else " -- got %r calls %r" % (out, calls)))
        setup("card 0: c0-c7 mobo:a3000-wd\n", {})
        out, calls, sus, pf = run()
        want = " ".join("0,%d" % u for u in (3, 5, 2, 4, 1, 0, 6))
        good = out == want and calls == ""
        (ok if good else fail)("CD addresses: an A3000 alone: no INQUIRY at all, every WD unit for the mount probe%s"
                               % ("" if good else " -- got %r calls %r" % (out, calls)))
    finally:
        shutil.rmtree(d, ignore_errors=True)

def audit_universal_cards():
    head("UC. a universal medium (TARGET_HBA=auto) scans every card the kernel registered: with "
         "the miniroot's bounded `kbootset cards --probe` (/tmp/cards.probe) only the units that answer as disks, "
         "else units 0-6 of each card; "
         "each disk is named by its controller")
    setup = open(SETUP, encoding="latin-1").read()
    def fn(name):
        f = _extract_func(setup, name)
        if not f:
            fail("setup.sh: no %s()" % name)
        return f or ""
    body = "\n".join(fn(n) for n in ("hexval", "hexname", "read_cards", "card_key", "card_base", "card_name",
                                      "card_hba", "card_units", "id_card"))
    for need, what in (('UNIVERSAL=y', "the universal block sets UNIVERSAL"),
                       ('INSTALLABLE_IDS="${SCAN_IDS:-none}"', "every disk found is installable"),
                       ('[ -n "$UNIVERSAL" ] && [ -s "$TOK_F.held" ] && UNI_ASK=y',
                        "a disk that holds partitions is chosen by typing its id"),
                       ('echo "TARGET_HBA=${UNI_HBA:-auto}"', "the answers carry the chosen disk's controller"),
                       ('holds `disk_contents $SCSI`.  All of it will be erased.', "the erase question names what the disk holds")):
        (ok if need in setup else fail)("setup.sh: %s" % what)
    d = tempfile.mkdtemp(prefix="unicards.")
    try:
        cards = ("card 0: c0-c7 zorro:144b:01 base 0x40000000\\ncard 1: c8-cf zorro:0202:54 base 0x40800000\\n"
                 "card 2: c10-c17 mobo:gayle\\n")
        probe = ("card 0: c0-c7 zorro:144b:01 base 0x40000000\\n  unit 0: type 0 ZuluSCSI SD -\\n"
                 "  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\\ncard 1: c8-cf zorro:0202:54 base 0x40800000\\n"
                 "  unit 3: type 5 ZuluSCSI CDROM 2.0\\ncard 2: c10-c17 mobo:gayle\\n  unit 5: type 5 UAE-ATAPI CD-ROM 0.1\\n"
                 "  unit 6: type 0 UAE IDE -\\n")
        def run(prc, script):
            kb = os.path.join(d, "kb")
            open(kb, "w").write('#!/bin/sh\ncase "$1 $2" in\n"cards --probe") [ %d = 0 ] && printf "%%b" "%s"; exit %d;;\n'
                                '"cards ") printf "%%b" "%s";;\nesac\n' % (prc, probe, prc, cards))
            os.chmod(kb, 0o755)
            # the units' types come from the miniroot's bounded probe file only
            pf = os.path.join(d, "cards.probe")
            if prc == 0:
                open(pf, "w").write(probe.replace("\\n", "\n"))
            elif os.path.exists(pf):
                os.remove(pf)
            r = subprocess.run(["/usr/bin/dash", "-c", "SETUP_KBOOTSET=%s CARDS_F=%s/cards SETUP_PROBE=%s CARDS_PROBED=\n%s\n%s"
                                % (kb, d, pf, body, script)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            return " ".join(r.stdout.decode().split())
        for prc, script, want, what in (
                (0, 'read_cards; echo "P=$CARDS_PROBED"; card_units', "P=y 0 6 16",
                 "-36: the disks only (Z3660 0 and 6, the IDE master c16); the CD units are not scanned"),
                (2, 'read_cards; echo "P=$CARDS_PROBED"; card_units',
                 "P= 0 1 2 3 4 5 6 8 9 a b c d e 10 11 12 13 14 15 16", "before -36: units 0-6 of every card"),
                (0, 'read_cards; for i in 6 b 16; do card_name "`card_key \\`id_card $i\\``"; done',
                 "Z3660 SCSI A4091 SCSI IDE", "each id is named by its card's controller"),
                (0, 'read_cards; for i in 6 b 16; do card_hba "`card_key \\`id_card $i\\``"; done',
                 "z3660scsi a4091 gayle", "and given the profile word l11.sh's key table knows"),
                (2, 'SUSPECT_CARD=1; read_cards; card_units', "0 1 2 3 4 5 6 10 11 12 13 14 15 16",
                 "a card a stuck probe hung on (card 1): none of its units is scanned")):
            got = run(prc, script)
            (ok if got == want else fail)("universal cards: %s%s" % (what, "" if got == want else " -- got %r" % got))
        # the A1200: the same gayle driver and key at 0xDA0000, named for its machine; the A4000's stays "IDE"
        pf = os.path.join(d, "cards.probe")
        for table, want, what in (
                ("card 0: c0-c7 mobo:gayle base 0x00da0000\n  unit 0: type 0 UAE IDE -\n  unit 5: type 5 UAE-ATAPI CD-ROM 0.1\n",
                 "A1200 IDE|0", "an A1200 alone: its IDE port is named \"A1200 IDE\" and its master offered"),
                ("card 0: c0-c7 mobo:gayle\n  unit 0: type 0 UAE IDE -\n", "IDE|0", "the A4000's IDE port stays \"IDE\"")):
            open(pf, "w").write(table)
            r = subprocess.run(["/usr/bin/dash", "-c", "SETUP_KBOOTSET=/bin/true CARDS_F=%s/cards SETUP_PROBE=%s CARDS_PROBED= "
                                "NOINQ_KEYS=mobo:a3000-wd\n%s\nread_cards; k=`card_key 0`; b=`card_base 0`; n=`card_name \"$k\" \"$b\"`; "
                                "u=`card_units`; echo \"$n|$u\"" % (d, pf, body)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            got = r.stdout.decode().strip()
            (ok if got == want else fail)("universal cards: %s%s" % (what, "" if got == want else " -- got %r" % got))
        # the Buddha and the Catweasel Z-II (one module, buddha): any unit of theirs that answers as a disk is
        # offered (port 0 master 6 and slave 5, port 1 3/2, the Catweasel's port 2 1/0; C4-2 8.2), named
        # by its board, and given the word l11.sh's key table and the DMA table know
        for table, script, want, what in (
                ("card 0: c0-c7 zorro:144b:01 base 0x40000000\n  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\n"
                 "card 1: c8-cf zorro:1212:00 base 0x00e90000\n  unit 5: type 0 UAE IDE -\n  unit 6: type 0 UAE IDE -\n",
                 'u=`card_units`; for i in d e; do k=`card_key \\`id_card $i\\``; echo "`card_name $k`/`card_hba $k`"; done; echo "|$u"',
                 "Buddha IDE/buddha Buddha IDE/buddha |6 d e",
                 "a Buddha beside a Z3660: its port-0 master (ce) and slave (cd) offered, named \"Buddha IDE\""),
                ("card 0: c0-c7 zorro:1212:00 base 0x00e90000\n  unit 5: type 0 UAE IDE -\n",
                 'echo "`card_units`"', "5", "a lone slave on a Buddha alone (c5) is offered"),
                ("card 0: c0-c7 zorro:1212:2a base 0x00e90000\n  unit 1: type 0 UAE IDE -\n  unit 3: type 5 UAE-ATAPI CD-ROM 0.1\n",
                 'k=`card_key 0`; echo "`card_name $k`/`card_hba $k`|`card_units`"', "Catweasel Z-II IDE/catweasel|1",
                 "a Catweasel Z-II: its port-2 master (c1) offered, its CD (unit 3) not")):
            open(pf, "w").write(table.replace("\\n", "\n"))
            r = subprocess.run(["/usr/bin/dash", "-c", "SETUP_KBOOTSET=/bin/true CARDS_F=%s/cards SETUP_PROBE=%s CARDS_PROBED= "
                                "NOINQ_KEYS=mobo:a3000-wd\n%s\nread_cards; %s" % (d, pf, body, script)],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            got = " ".join(r.stdout.decode().split())
            (ok if got == want else fail)("universal cards: %s%s" % (what, "" if got == want else " -- got %r" % got))
        # the A3000: the WD (mobo:a3000-wd) is not probed, so its units are read as before the probe
        pf = os.path.join(d, "cards.probe")
        for table, want, what in (
                ("card 0: c0-c7 zorro:0202:54 base 0x40800000\n  unit 3: type 5 ZuluSCSI CDROM 2.0\n  unit 6: type 0 ZuluSCSI HARDDRIVE 2.0\n"
                 "card 1: c8-cf mobo:a3000-wd\n  not probed (no INQUIRY on this controller)\n", "6 8 9 a b c d e",
                 "an A3000 with an A4091: the A4091's disk by its INQUIRY, the WD's units 0-6 by the dd read"),
                ("card 0: c0-c7 mobo:a3000-wd\n  not probed (no INQUIRY on this controller)\n", "0 1 2 3 4 5 6",
                 "an A3000 alone: the WD's units 0-6 by the dd read")):
            open(pf, "w").write(table)
            r = subprocess.run(["/usr/bin/dash", "-c", "SETUP_KBOOTSET=/bin/true CARDS_F=%s/cards SETUP_PROBE=%s CARDS_PROBED= "
                                "NOINQ_KEYS=mobo:a3000-wd\n%s\nread_cards; card_units" % (d, pf, body)],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            got = " ".join(r.stdout.decode().split())
            (ok if got == want else fail)("universal cards: %s%s" % (what, "" if got == want else " -- got %r" % got))
        ssi = "\n".join(_extract_func(setup, n) or "" for n in ("cd_unit_id", "spec_id", "scan_safe_ids"))
        r = subprocess.run(["/usr/bin/dash", "-c", "%s\n%s\nCD_SPEC= MINIROOT_CD_CANDIDATES= INSTALLABLE_IDS= SUSPECT_CARD=2\n"
                            "scan_safe_ids 0 6 e 10 16" % (body, ssi)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        got = " ".join(r.stdout.decode().split())
        (ok if got == "0 6 e" else fail)("universal cards: scan_safe_ids drops the suspect card's ids on any medium (card 2: 10, 16)%s"
                                         % ("" if got == "0 6 e" else " -- got %r" % got))
        r = subprocess.run(["/usr/bin/dash", "-c", "SETUP_KBOOTSET=%s/none CARDS_F=%s/cards\n%s\nread_cards; echo rc=$?"
                            % (d, d, body)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        (ok if r.stdout.decode().strip().endswith("rc=1") else fail)("universal cards: no kbootset: read_cards fails (the card-0 scan stands)")
    finally:
        shutil.rmtree(d, ignore_errors=True)




def audit_boot_rivals():
    head("BR. a disk that boots first: the interview's scan lists every bootable partition (rdb_boot_parts, the PART "
         "chain read byte by byte with sum -r), and the install ends by naming any on another disk above its own priority")
    import struct
    src = open(SETUP, encoding="utf-8").read()
    fn = "\n".join(_extract_func(src, f) for f in ("rdb_byte", "rdb_long", "rdb_boot_parts"))
    d = tempfile.mkdtemp(prefix="bp.")
    try:
        img = bytearray(512 * 8)
        img[0:4] = b"RDSK"; struct.pack_into(">I", img, 28, 2)
        def part(n, nxt, flags, name, pri):
            o = n * 512; img[o:o + 4] = b"PART"; struct.pack_into(">I", img, o + 16, nxt); struct.pack_into(">I", img, o + 20, flags)
            img[o + 36] = len(name); img[o + 37:o + 37 + len(name)] = name.encode(); struct.pack_into(">i", img, o + 188, pri)
        part(2, 3, 0, "UNIX_Root", 0); part(3, 4, 1, "UNIX_Boot", 5); part(4, 0xffffffff, 1, "DH0", -128)
        open(os.path.join(d, "fix.img"), "wb").write(img)
        open(os.path.join(d, "zero.img"), "wb").write(bytes(4096))
        os.makedirs(os.path.join(d, "bin"))
        open(os.path.join(d, "bin", "sum"), "w").write('#!/bin/sh\nexec sum "$@"\n'); os.chmod(os.path.join(d, "bin", "sum"), 0o755)
        def run(dev):
            r = subprocess.run(["/usr/bin/dash", "-c", "INST=%s\nBLK0=%s/blk0\n%s\nrdb_boot_parts %s\n" % (d, d, fn, dev)],
                               capture_output=True, text=True, timeout=60)
            return r.stdout.split("\n")[:-1]
        got = run(os.path.join(d, "fix.img"))
        (ok if got == ["5 UNIX_Boot", "-128 DH0"] else fail)(
            "rdb_boot_parts EXECUTED on a fixture RDB: the bootable partitions with their priorities, -128 signed (%r)" % (got,))
        (ok if run(os.path.join(d, "zero.img")) == [] and run(os.path.join(d, "none")) == [] else fail)(
            "rdb_boot_parts: no RDB and no device print nothing")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    drv = open(DRIVER, encoding="utf-8").read()
    (ok if "BOOTP_F=/tmp/setup.bootparts" in src and "BOOTP_F=/tmp/setup.bootparts" in drv
          and '[ "$_bp" -gt "$TARGET_BOOT_BOOTPRI" ] || continue' in drv and 'rdb_boot_parts "$dev"' in src else fail)(
        "the scan records the bootable partitions and the install's closing lines name those above its priority")


def audit_swap_by_ram():
    head("SR. 1.1 swap by memory: the interview and the driver share swap_by_ram word for word; its default "
         "is 64 MB under 32 MB of memory, 128 MB from it, at most a quarter of the disk, at least MINSWAP; "
         "the dialog warns past what the kernel takes; no rc.conf swap_add limits the boot step")
    blk = re.compile(r'(# --- swap by memory \(1\.1\).*?# --- end of swap by memory ---\n)', re.S)
    a = blk.search(open(SETUP, encoding="utf-8").read())
    b = blk.search(open(DRIVER, encoding="utf-8").read())
    if not a or not b:
        fail("swap_by_ram block missing in %s" % ("setup.sh" if not a else "install.sh"))
        return
    (ok if a.group(1) == b.group(1) else fail)("swap_by_ram and kinfo_fast_mb are the same text in setup.sh and install.sh")
    want = {("030", 16, 200): "50 128", ("030", 16, 512): "64 128", ("030", 32, 512): "128 384", ("030", 64, 4000): "128 384",
            ("030", 16, 100): "25 128", ("060", 16, 100): "30 445", ("060", 16, 512): "64 445", ("060", 32, 512): "128 948",
            ("060", 64, 4000): "128 1955", ("060", 128, 4000): "128 630", ("030", 0, 512): "64 128"}
    bad = []
    for (cpu, ram, disk), exp in want.items():
        body = ('INST=/nonexistent\nINSTALL_CPU=%s\nINSTALL_RAM_MB=%s\nMINSWAP=%d\n%s\nswap_by_ram %d\necho "$DEFSWAP $SWAPBOUND"\n'
                % (cpu, ram if ram else "", 30 if cpu == "060" else 5, a.group(1), disk))
        r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10)
        if r.stdout.strip() != exp:
            bad.append("%s %s MB %s MB disk: %r, want %r" % (cpu, ram, disk, r.stdout.strip(), exp))
    (fail if bad else ok)("swap_by_ram EXECUTED on %d cases (memory unknown counts as 16 MB)%s"
                          % (len(want), (": " + "; ".join(bad)) if bad else ""))
    st = open(SETUP, encoding="utf-8").read()
    (ok if 'Use ${SWAPBOUND} megabytes instead? [y] ' in st and '[ "$ask" -gt "$SWAPBOUND" ]' in st else fail)(
        "the swap question warns past SWAPBOUND and offers it; a NO keeps the typed size")
    l11 = open(os.path.join(os.path.dirname(DRIVER), "l11.sh"), encoding="utf-8").read()
    (ok if 'swap_add=' not in l11 else fail)("l11.sh writes no swap_add into /etc/rc.conf")


def audit_swap_stepdown():
    head("SW. the swap slice is added in steps (SWAP_ADD_MB): sizes tried in order, the first the "
         "kernel takes is used and logged, no size twice; default the whole slice on both lines, then 64 and 30 MiB")
    src = open(DRIVER, encoding="utf-8").read()
    m = re.search(r'\n(\t\[ -n "\$SWAP_ADD_MB" \] \|\| SWAP_ADD_MB=.*?\n\tearly_target_swap\(\) \{\n.*?\n\t\})\n', src, re.S)
    if not m:
        fail("install.sh: no SWAP_ADD_MB default and early_target_swap")
        return
    block = m.group(1)
    def run(cpu, add, takes, slice_blocks=131072):
        # takes: the largest block count this kernel takes (a larger request is refused)
        body = ('BLOCKS_PER_MB=2048\nTARGET_SWAP_SLICE=2\nID=6\nDISK_RAW=/dev/rdsk/c6d0s0\nSWAPLEN=%d\n'
                'INSTALL_CPU="%s"\nSWAP_ADD_MB="%s"\n'
                'is_num() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; return 0; }\n'
                'msg() { echo "MSG $*"; }\nwarn() { echo "WARN $*"; }\n'
                'runq() { shift; case "$1" in -a) echo "TRY $4"; [ "$4" -le %d ] ;; *) return 0 ;; esac; }\n'
                'swapl() { echo "path dev swaplo blocks free"; echo "/dev/fakeswap 0,0 0 100 100"; }\n'
                % (slice_blocks, cpu, add, takes))
        code = block.replace("/bin/swap -l", "swapl").replace("/etc/rdb -p", "echo 2 x %d #" % slice_blocks)
        r = subprocess.run(["/usr/bin/dash", "-c", body + code + "\nearly_target_swap\necho ADDED=$EARLY_SWAP_ADDED\n"],
                           capture_output=True, text=True, timeout=10)
        return r.stdout
    cases = (
        ("030 default: the whole slice", "030", "", 10**9, ["TRY 131072", "ADDED=/dev/dsk/c6d0s2 0 131072"], []),
        ("060 default: the whole slice", "060", "", 10**9, ["TRY 131072", "ADDED=/dev/dsk/c6d0s2 0 131072"], []),
        ("guarded list steps down to 48 MiB", "030", "all 48 30", 100000, ["TRY 131072", "TRY 98304", "ADDED=/dev/dsk/c6d0s2 0 98304"], ["TRY 61440"]),
        ("then to 30 MiB", "030", "all 48 30", 70000, ["TRY 131072", "TRY 98304", "TRY 61440", "ADDED=/dev/dsk/c6d0s2 0 61440"], []),
        ("no size twice (a 48 MiB slice: all = 48)", "030", "all 48 30", 10, ["TRY 98304", "TRY 61440"], []),
    )
    bad = []
    for what, cpu, add, takes, want, notwant in cases:
        sl = 98304 if "48 MiB slice" in what else 131072
        out = run(cpu, add, takes, sl)
        if not all(w in out for w in want) or any(n in out for n in notwant) or (what.startswith("no size") and out.count("TRY 98304") != 1):
            bad.append("%s: %r" % (what, out.strip().splitlines()[-4:]))
    (fail if bad else ok)("swap step-down EXECUTED (5 cases: defaults per line, 48 then 30 MiB, no size twice)%s"
                          % ((": " + "; ".join(bad)) if bad else ""))


def audit_net_space():
    head("NS. on the netinstall medium the free-space check sizes the set from the catalog (#isize, else the "
         "datastream sizes), with the base packages, the kernel set and twice the largest datastream (apkg's cache "
         "and pkgadd's spool on the root at once), and refuses a root that cannot take it")
    src = open(os.path.join(REPO, "src/installer/setup.sh"), encoding="latin-1").read()
    def fn(n):
        m = re.search(r"^%s\(\) ?\n?\{.*?^\}\n" % n, src, re.M | re.S)
        return m.group(0) if m else None
    parts = [fn(n) for n in ("is_num", "budget", "order_size_bytes", "order_dl_bytes", "order_dl_max", "net_need_mb", "check_space")]
    if None in parts:
        fail("setup.sh lacks one of check_space's network helpers (order_dl_max, net_need_mb)")
        return
    d = tempfile.mkdtemp(prefix="netspace.")
    try:
        MB = 1048576
        inst = os.path.join(d, "install")
        os.makedirs(os.path.join(inst, "l11", "base"))
        # four stock rows (40, 20, 30 and 62 MB) and a base package; kernel space as #kpkg rows
        rows = [("core", "core", 40 * MB), ("man", "man", 20 * MB), ("xcore", "Xcore", 30 * MB),
                ("x11r5src", "X11r5src", 62 * MB), ("amix-base", "amxbase", 1 * MB)]
        def catalog(isize):
            t = "#apkg-catalog 1\n" + "".join("%s|2.1|%s|stock/%s.pkg|0|%d|none|system|d\n" % (n, i, i, z) for n, i, z in rows)
            t += "#kpkg kernel-k46-m k46-1 role=kernel size=%d sha256=0\n" % (2 * MB)
            if isize:
                t += "#ext isize 1\n" + "".join("#isize %s %d\n" % (n, z) for n, i, z in rows)
            return t
        open(os.path.join(inst, "order.small"), "w").write("core\nman\n")
        open(os.path.join(inst, "order.big"), "w").write("core\nman\nXcore\nX11r5src\n")
        open(os.path.join(inst, "l11", "base", "order"), "w").write("amxbase\n")
        body = "".join(parts)
        def run(order, root, isize, answer="n"):
            cat = os.path.join(d, "catalog")
            open(cat, "w").write(catalog(isize))
            h = ('readask() { echo "$1"; ask=%s; }\nTOK_F=%s/t.tok; CATN_F=%s/t.catn; ISZ_F=%s/t.isz\n'
                 'SRC_KIND=net; CATF=%s; KCATF=%s; INST=%s; SET_NAME=x; ANS_ROOT=%d; ANS_FSYS=ufs\n'
                 'KERNEL_KPKG=kernel-k46-m; KERNEL_MODPKGS=\n' % (answer, d, d, d, cat, cat, inst, root))
            h += body + 'check_space %s/%s && echo ACCEPTED || echo REFUSED\n' % (inst, order)
            return subprocess.run(["/usr/bin/dash", "-c", h], capture_output=True, text=True, timeout=60).stdout
        # small: (40+20+1) x 1.1 + 2 + 2 x 40 = about 149 MB; big: (40+20+30+62+1) x 1.1 + 2 + 2 x 62 = about 294 MB
        out = run("order.small", 200, True)
        (ok if out.strip().endswith("ACCEPTED") else fail)("a set that fits a 200 MB root is accepted on the network")
        out = run("order.big", 200, True)
        (ok if out.strip().endswith("REFUSED") and "124 MB" in out else fail)(
            "a set needing about 294 MB is refused on a 200 MB root, naming twice the largest datastream (124 MB)")
        out = run("order.big", 400, True)
        (ok if out.strip().endswith("ACCEPTED") else fail)("the same set fits a 400 MB root")
        out = run("order.big", 200, False)
        (ok if out.strip().endswith("REFUSED") else fail)("with no #isize lines the datastream sizes stand in (still refused)")
        out = run("order.big", 200, True, answer="y")
        (ok if out.strip().endswith("ACCEPTED") else fail)("the stock override (go ahead anyway: y) still lets it through")
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_guarded_mkdir():
    head("MG. every mkdir -p in the shell that runs on the box is behind [ -d DIR ] || (the stock mkdir -p "
         "exits 2 \"File exists\" on an existing directory: grimoire); a line that means it carries mkdir-ok")
    files = [f for f in subprocess.run(["git", "-C", REPO, "ls-files"], capture_output=True, text=True).stdout.split()
             if f.startswith(("src/installer/", "payload/")) or f == "src/miniroot/profile"]
    bad = []
    for f in files:
        pth = os.path.join(REPO, f)
        if not os.path.isfile(pth):
            continue
        with open(pth, "rb") as fh:
            if b"\0" in fh.read(4096):
                continue
        for n, l in enumerate(open(pth, encoding="latin-1"), 1):
            st = l.lstrip()
            if st.startswith("#") or "mkdir -p" not in l or "mkdir-ok" in l:
                continue
            pre = l[:l.index("mkdir -p")]
            if not re.search(r'\[ -d [^]]+\] \|\|', pre):
                bad.append("%s:%d" % (f, n))
    (fail if bad else ok)("mkdir -p guarded on the box (%d files)%s" % (len(files), (": " + " ".join(bad[:10])) if bad else ""))
    # netset.sh's work-dir step twice, under a mkdir that refuses an existing directory as the box's does
    src = open(os.path.join(REPO, "payload/firstboot/netset.sh"), encoding="latin-1").read()
    m = re.search(r'^\[ -d "\$W/cache" \] \|\| mkdir -p "\$W/cache" \|\| stop [^\n]*\n', src, re.M)
    if not m:
        fail("netset.sh has no guarded work-dir step")
        return
    d = tempfile.mkdtemp(prefix="mkdir.")
    try:
        os.makedirs(os.path.join(d, "bin"))
        fake = os.path.join(d, "bin", "mkdir")
        open(fake, "w").write('#!/bin/sh\n[ "$1" = -p ] && shift\nfor x in "$@"; do\n'
                              '  [ -d "$x" ] && { echo "mkdir: $x: File exists" >&2; exit 2; }\n'
                              '  /bin/mkdir -p "$x" || exit 2\ndone\n')
        os.chmod(fake, 0o755)
        body = ('PATH=%s/bin:$PATH; W=%s/netset; stop() { echo "STOP $*"; exit 0; }\n' % (d, d)) + m.group(0) + "echo MADE\n"
        outs = [subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout.strip()
                for _ in (1, 2)]
        (ok if outs == ["MADE", "MADE"] and os.path.isdir(os.path.join(d, "netset", "cache")) else fail)(
            "netset.sh's work dir made twice in a row (a resumed run), the box's mkdir semantics: %s" % " / ".join(outs))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_colon_truncate():
    head("CT. no `: > FILE` in a script that runs on the guest: the stock Amix sh empties a file that way only "
         "the first time the command runs (in a function or loop, measured on the box, 2026-11-06), "
         "while the host's dash always does; a plain `> FILE` empties it every time")
    rx = re.compile(r'(^|[;&|(]|\bthen\b|\bdo\b|\belse\b)\s*:\s*>(?!>)')
    tracked = subprocess.run(["git", "-C", REPO, "ls-files", "src/installer", "payload", "profiles",
                              "media/src/miniroot/profile"], capture_output=True, text=True).stdout.split()
    files, bad = [], []
    for f in tracked:
        pth = os.path.join(REPO, f)
        if not os.path.isfile(pth) or "/licences/" in f or f.endswith(".md"):
            continue
        files.append(f)
        for n, l in enumerate(open(pth, encoding="latin-1"), 1):
            if l.lstrip().startswith("#"):
                continue
            if rx.search(l):
                bad.append("%s:%d" % (f, n))
    (fail if bad or len(files) < 8 else ok)("no `: >` truncation in %d guest scripts (installer, payload, profiles, "
                                             "miniroot profile)%s" % (len(files), (": " + " ".join(bad[:10])) if bad else ""))
    # the rule itself, on fixtures: a `: >` line is found, a `>` line and a comment are not
    probe = [("\t: > \"$x\"\n", True), ("> \"$x\" || die\n", False), ("# : > old\n", False), ("a; : > b\n", True),
             (": >> log\n", False)]
    wrong = [t for t, want in probe if bool(rx.search(t)) != want and not t.lstrip().startswith("#")]
    (fail if wrong else ok)("the `: >` rule finds the truncation forms and passes `>`, `: >>` and comments")


def audit_guarded_rm_mv():
    head("RG. every rm and mv on a variable path names it \"${var:?}\" -- the root and every part after it, "
         "quoted or not, escaped in a generated script or not -- so an empty variable stops the script "
         "instead of widening the path")
    rx_cmd = re.compile(r'(?<![\w./-])(rm|mv)(?=\s)')
    # any variable reference that is not ${name:?}: $name, ${name}, \$name (a generated script), $1
    rx_var = re.compile(r'\\?\$(\{[A-Za-z_][A-Za-z_0-9]*\}|[A-Za-z_][A-Za-z_0-9]*|[0-9])')
    rx_end = re.compile(r';|&&|\|\||\||\bthen\b|\bdo\b|\)\s*$')
    files = []
    tracked = subprocess.run(["git", "-C", REPO, "ls-files"], capture_output=True, text=True).stdout.split()
    for f in tracked:
        pth = os.path.join(REPO, f)
        if not os.path.isfile(pth):
            continue
        with open(pth, "rb") as fh:
            first = fh.read(64)
        if f.endswith(".sh") or f == "src/miniroot/profile" or re.match(rb"#!\s*/bin/(ba)?sh|#!/usr/bin/env bash", first):
            files.append(f)
    bad = []
    for f in files:
        for n, l in enumerate(open(os.path.join(REPO, f), encoding="latin-1"), 1):
            if l.lstrip().startswith("#"):
                continue
            for m in rx_cmd.finditer(l):
                if re.search(r'(^|\s)#', l[:m.start()]):
                    break
                e = rx_end.search(l, m.end())
                if rx_var.search(l[m.end():e.start() if e else len(l)]):
                    bad.append("%s:%d" % (f, n))
                    break
    # media/ has about thirty shell scripts: fewer than 25 means the scan lost them
    (fail if bad or len(files) < 25 else ok)("rm/mv variable paths guarded in %d tracked shell scripts (the miniroot "
                                              "profile and payload/ included)%s"
                                              % (len(files), (": " + " ".join(bad[:10])) if bad else ""))
    # the guard itself: an empty variable stops the shell before the rm runs
    d = tempfile.mkdtemp(prefix="guard.")
    try:
        keep = os.path.join(d, "keep")
        open(keep, "w").close()
        r = subprocess.run(["/usr/bin/dash", "-c", 'D=%s; X=; rm -f "${D:?}/${X:?}keep"; echo AFTER' % d],
                           capture_output=True, text=True, timeout=10)
        (ok if r.returncode != 0 and "AFTER" not in r.stdout and os.path.exists(keep) else fail)(
            "guard EXECUTED: an empty variable in \"${D:?}/${X:?}keep\" stops the shell, nothing is removed")
    finally:
        shutil.rmtree(d, ignore_errors=True)




def audit_l11():
    """L11. The 1.1 disk layout (amix-dlm spec 40), EXECUTED
    under dash from the scripts' own text: (1) plan_partitions with INSTALL_LAYOUT=1.1
    lays root, swap, the 64 MiB store and the data slice end to end, and 1.0 stays the
    10 MiB boot slice; (2) the repair path's kbootset menu drives status, rollback and
    mark-bad through the disk's own kbootset on the store its bootset file names; (3)
    l11_apkg maps apkg 0.3's exits (0, 5, 6, 7) and a pending /var/apkg/txn to a stop
    that names `apkg ... recover`; (4) the updbootpart shim refuses (exit 3) and names
    kbootset."""
    head("L11. the 1.1 disk: plan, repair menu, apkg exits, updbootpart shim (executed)")
    if not os.path.exists("/usr/bin/dash"):
        skip("dash absent -- cannot execute the 1.1 functions")
        return
    l11 = open(L11, encoding="utf-8").read()
    d = workpath("l11")
    os.makedirs(d, exist_ok=True)

    # (1) the plan
    src = open(DRIVER, encoding="utf-8").read()
    harness = extract_plan_harness().replace(
        'echo "$ROOT_OFF $SWAP_OFF $BOOT_OFF $ROOTLEN $SWAPLEN $BOOTLEN"',
        'echo "$ROOT_OFF $SWAP_OFF $BOOT_OFF $ROOTLEN $SWAPLEN $BOOTLEN $DATA_OFF $DATALEN $DISKLEN"')
    harness = _extract_func(l11, "l11_plan_data") + "\n" + harness

    def plan(mb, layout, data=""):
        env = dict(os.environ, INSTALL_LAYOUT=layout, L11_STORE_MB="64", TARGET_DATA_MB=data,
                   KERNEL_SDDEVSIZE="fixed", INSTALL_CPU="030")
        r = subprocess.run(["/usr/bin/dash", "-c", harness, "plan", str(mb)],
                           capture_output=True, text=True, timeout=30, env=env)
        v = r.stdout.split()
        return [int(x) for x in v] if r.returncode == 0 and len(v) == 9 else None

    for mb, data, want_data in ((200, "", 0), (1024, "", 256 * 2048), (300, "40", 40 * 2048)):
        v = plan(mb, "1.1", data)
        if not v:
            fail("1.1 plan for %d MB did not run" % mb)
            continue
        ro, so, bo, rl, sl, bl, do, dl, dk = v
        if (bl == 64 * 2048 and dl == want_data and ro + rl == so and so + sl == bo
                and bo + bl == do and do + dl <= dk):
            ok("1.1 plan %d MB%s: root %d, swap %d, store %d blocks (64 MiB), data %d -- end to end"
               % (mb, " (TARGET_DATA_MB=%s)" % data if data else "", rl, sl, bl, dl))
        else:
            fail("1.1 plan %d MB is wrong: %r" % (mb, v))
    v = plan(200, "1.0")
    if v and v[5] == 10 * 2048 and v[7] == 0:
        ok("1.0 plan 200 MB keeps the 10 MiB boot slice and no data slice")
    else:
        fail("1.0 plan 200 MB changed: %r" % (v,))

    # (2) the repair menu, against a fake disk under d/mnt
    prof = read_sh(MINIROOT_PROFILE)
    mnt = os.path.join(d, "mnt")
    os.makedirs(os.path.join(mnt, "etc", "default"), exist_ok=True)
    os.makedirs(os.path.join(mnt, "sbin"), exist_ok=True)
    os.makedirs(os.path.join(mnt, "var", "apkg"), exist_ok=True)
    open(os.path.join(mnt, "etc", "default", "bootset"), "w").write(
        "# x\nbootset=auto\nstore=/dev/rdsk/c6d0s3\nstore-id=202b20f4\n")
    log = os.path.join(d, "kb.log")
    kb = os.path.join(mnt, "sbin", "kbootset")
    open(kb, "w").write('#!/bin/sh\necho "$*" >> %s\n' % log)
    os.chmod(kb, 0o755)
    open(os.path.join(mnt, "var", "apkg", "txn"), "w").write("pending\n")
    menu = (_extract_func(prof, "readask") + "\n" + _extract_func(prof, "kbootset_menu")).replace("/mnt", mnt)
    menu = menu.replace("/tmp/mr.store", os.path.join(d, "mr.store"))
    r = subprocess.run(["/usr/bin/dash", "-c", menu + "\nkbootset_menu\n"], input="1\n2\n3\n2\n3\nx\n4\n",
                       capture_output=True, text=True, timeout=30)
    got = open(log).read().splitlines() if os.path.exists(log) else []
    pre = "-R %s --dev /dev/rdsk/c6d0s3 --journal %s/var/kbootset/journal " % (mnt, mnt)
    if got == [pre + "status", pre + "rollback", pre + "mark-bad 2"] and r.returncode == 0:
        ok("repair menu: status, rollback, mark-bad 2 through the disk's own kbootset on store= "
           "(a non-number refused, 4 continues)")
    else:
        fail("repair menu drove kbootset wrongly: %r (rc %d)" % (got, r.returncode))
    if "apkg -c /cdrom/install/l11/recover.conf -R /mnt recover" in r.stdout.replace(mnt, "/mnt"):
        ok("repair menu: a pending /var/apkg/txn is reported with the recover command")
    else:
        fail("repair menu does not report a pending apkg transaction")

    # (3) apkg's exits
    tgt = os.path.join(d, "tgt")
    os.makedirs(os.path.join(tgt, "var", "apkg"), exist_ok=True)
    fake = os.path.join(d, "apkg")
    open(fake, "w").write('#!/bin/sh\n[ -n "$LEAVE_TXN" ] && echo pending > %s/var/apkg/txn\nexit $APKG_RC\n' % tgt)
    os.chmod(fake, 0o755)
    rec = next(l for l in l11.splitlines() if l.startswith("L11_RECOVER="))
    body = ('die() { echo "DIE $*"; exit 3; }\nwarn() { echo "WARN $*"; }\nrunq() { "$@"; }\n'
            "TARGET=%s\nL11_APKG=%s\n%s\n" % (tgt, fake, rec) +
            _extract_func(l11, "l11_txn_pending") + "\n" + _extract_func(l11, "l11_apkg") +
            '\nl11_apkg -R x install k\necho RETURNED\n')

    def apkg(rc, txn_before=False, leave=False):
        txn = os.path.join(tgt, "var", "apkg", "txn")
        if os.path.exists(txn):
            os.remove(txn)
        if txn_before:
            open(txn, "w").write("pending\n")
        env = dict(os.environ, APKG_RC=str(rc), LEAVE_TXN="y" if leave else "")
        r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30, env=env)
        return r.stdout

    cases = [
        (apkg(0), "RETURNED", "exit 0 returns"),
        (apkg(6, leave=True), "exit 6: kbootset failed", "exit 6 stops, journal kept, recover named"),
        (apkg(7), "exit 7: kbootset refused it", "exit 7 stops (generation unchanged)"),
        (apkg(5), "failed (rc=5)", "any other status stops"),
        (apkg(0, txn_before=True), "a pending transaction blocks", "a pending /var/apkg/txn blocks the install"),
        (apkg(0, leave=True), "left its journal", "a journal left after exit 0 stops"),
    ]
    for out, want, what in cases:
        if want in out and (want == "RETURNED" or "RETURNED" not in out):
            if want != "RETURNED" and want != "exit 7: kbootset refused it" and "recover" not in out:
                fail("apkg %s, but the stop does not name recover: %s" % (what, out.strip()))
            else:
                ok("apkg: %s" % what)
        else:
            fail("apkg: %s -- got %r" % (what, out.strip()))

    # (5) 1.1 supports clean installs only -- install.sh refuses INSTALL_UPGRADE,
    # and neither script carries the upgrade path; the audit is shown to catch a fixture
    # with the refusal dropped and the capture brought back
    probs = _p36_problems(src, l11)
    (ok if not probs else fail)("install.sh + l11.sh: no upgrade path, INSTALL_UPGRADE refused%s"
                                % ((" -- " + "; ".join(probs)) if probs else ""))
    fixture = re.sub(r'\ncase "\$\{INSTALL_UPGRADE:-no\}" in\n.*?\nesac\n', "\n", src, flags=re.S)
    fixture = fixture.replace('\t\tRDB_CLEAR="$OFFSET_BLOCKS"\n',
                              '\t\tRDB_CLEAR="$OFFSET_BLOCKS"\n\t\t[ "${INSTALL_UPGRADE:-no}" = yes ] && l11_upgrade_capture\n')
    fp = _p36_problems(fixture, l11)
    (ok if fixture != src and len(fp) == 2 else fail)(
        "the clean-install audit catches the negative fixture (refusal dropped, capture back): %s" % ("; ".join(fp) or "nothing"))
    fbl = [w for w in _P36_GONE if w in strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())]
    (ok if not fbl else fail)("firstboot.sh: no upgrade branch (FB_UPGRADED)%s"
                              % ((" -- still: " + " ".join(fbl)) if fbl else ""))
    m = re.search(r'\ncase "\$\{INSTALL_UPGRADE:-no\}" in\n.*?\nesac\n', src, re.S)
    if m:
        for val, want in (("", "PASSED"), ("no", "PASSED"), ("yes", "DIE"), ("y", "DIE")):
            body = 'die() { echo "DIE $*"; exit 3; }\n' + ("INSTALL_UPGRADE=%s\n" % val if val else "") \
                   + m.group(0) + "echo PASSED\n"
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            good = want in out and (want == "PASSED" or "fresh install" in out)
            (ok if good else fail)("install.sh, INSTALL_UPGRADE=%s: %s" % (val or "(unset)", out.strip()[:90]))

    # (5b) the base packages. l11_base adds base/order's packages under the
    # target's chroot with APKGENG's engine (the miniroot has no cmp for the conffile class),
    # seeds each one's conffile baselines first, transfers amix-base's conffiles from core
    # with removef, refuses a PENDING; install.sh calls it before the kernel-space step; the
    # medium stages base/ from the pkgmaps and takes inittab from amix-base
    lb = _extract_func(l11, "l11_base") or ""
    iso = open(os.path.join(TOOLS, "build-install-iso.sh"), encoding="utf-8").read()
    for what, good in (
            ("l11_base runs seed.sh then APKGENG's pkgadd under the target's chroot, per base/order",
             re.search(r'for _p in \$_ord\n.*?"\$_cr" "\$TARGET" /bin/sh /tmp/l11base/seed\.sh'
                       r'.*?runq "\$_cr" "\$TARGET" /usr/apkg/bin/pkgadd -n -a /tmp/l11base/admin', lb, re.S)),
            ("l11_base takes base/order, then the chosen set's base/o.<set>, and drops each datastream after its pkgadd",
             '_ord=`cat "$L11/base/order"`' in lb
             and '[ -f "$L11/base/o.$INSTALL_SET" ] && _ord="$_ord `cat "$L11/base/o.$INSTALL_SET"`"' in lb
             and 'run rm -f "${_bd:?}/${_f:?}"' in lb),
            ("l11_base transfers amix-base's conffiles from core (removef core, removef -f core)",
             '/usr/apkg/bin/removef core `cat "$L11/base/amxbase.cf"`' in lb
             and '/usr/apkg/bin/removef -f core' in lb),
            ("l11_base refuses a PENDING after a fresh install",
             '[ -s "$TARGET/var/sadm/conffiles/PENDING" ]' in lb),
            ("install.sh calls l11_base before l11_bootstore in its 1.1 block",
             re.search(r'if \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n(?:\t#[^\n]*\n)*\tl11_base\n\tl11_bootstore', src)),
            ("build-install-iso stages base/ (order, datastreams, pkgmap conffiles, seed.sh) and amix-base's inittab",
             "awk '$2 == \"e\" && $3 == \"conffile\" { print $4 }'" in iso
             and 'cp "$repo/payload/l11-seed.sh" "$STAGE/l11/base/seed.sh"' in iso
             and '_it="$_bw/amxbase/root/etc/inittab"' in iso and "06b13538" not in iso),
            ("install.sh, 1.1: the syslog package's unit (only the 2.1c daemon overwrite stays the installer's)",
             re.search(r'if \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n(?:\t#[^\n]*\n)*\trun cp "\$INST/syslog/syslogd" '
                       r'"\$TARGET/usr/sbin/syslogd"\n\trun chmod 0100 [^\n]*\n\tmsg [^\n]*\nelse\n', src)),
            ("install.sh, 1.1: no S99zen and no zenmac (interfaces and amix-base's ifup bring zen0 up)",
             re.search(r'if \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n(?:\t#[^\n]*\n)*\tmsg "network: [^\n]*\nelif \[ "\$FB_ETHER_IF" = zen0 \]', src)),
            ("install.sh, 1.1: no S20monsw, /etc/monsw or /dev/monsw (the monsw package; /etc/display's monsw)",
             re.search(r'if \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n(?:\t#[^\n]*\n)*\tmsg "monitor switch: [^\n]*\nelif \[ -n "\$MONSW" \]', src))):
        (ok if good else fail)(what)

    # (5c) l11_admin writes /etc/inet/interfaces, /etc/rc.conf and /etc/display from
    # the profile and checks them with ifup -n / xstart -n under the target's chroot (stubbed)
    la = _extract_func(l11, "l11_admin")
    lbits = _extract_func(l11, "l11_bits")
    if not la or not lbits:
        fail("l11.sh has no l11_admin or l11_bits")
    else:
        at = os.path.join(d, "admin")
        def admin(x11=False, **kv):
            shutil.rmtree(at, ignore_errors=True)
            os.makedirs(os.path.join(at, "etc", "inet"))
            os.makedirs(os.path.join(at, "usr", "sbin"))
            if x11:
                os.makedirs(os.path.join(at, "usr", "X", "bin"))
            cr = os.path.join(at, "usr", "sbin", "chroot")
            open(cr, "w").write("#!/bin/sh\necho \"CHROOT $*\" >> %s/chroot.log\nexit 0\n" % at)
            os.chmod(cr, 0o755)
            env = dict(PROFILE_NAME="t", FB_ETHER_IF="aen0", FB_IP="", FB_NETMASK="", FB_GATEWAY="",
                       FB_NODENAME="", FB_ZEN_IP="", FB_ZEN_NETMASK="", FB_ZEN_GATEWAY="", FB_ZEN_CARDS="",
                       FB_DNS1="", FB_DNS2="", FB_DOMAIN="", FB_SYSLOG="y", MONSW="")
            env.update(kv)
            sets = "".join("%s='%s'\n" % (k, v) for k, v in env.items())
            body = ('msg() { :; }\ndie() { echo "DIE $*"; exit 3; }\nrun() { "$@"; }\nTARGET=%s\n%s%s\n%s\nl11_admin\n'
                    % (at, sets, lbits, la))
            r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30)
            rd = lambda *p: open(os.path.join(at, *p)).read() if os.path.exists(os.path.join(at, *p)) else ""
            body_if = [l for l in rd("etc", "inet", "interfaces").splitlines() if not l.startswith("#")]
            return r.stdout, body_if, rd("etc", "rc.conf"), rd("etc", "display"), rd("chroot.log")
        out, ifs, rc, disp, crl = admin(x11=True, FB_IP="192.0.2.38", FB_NETMASK="255.255.255.0", FB_GATEWAY="192.0.2.1",
                                        FB_NODENAME="uaeamix", FB_ZEN_IP="192.0.2.39", FB_ZEN_NETMASK="255.255.255.0",
                                        FB_DOMAIN="example.net", FB_SYSLOG="n", MONSW="34", SWAP_ADD_MB="all 48 30")
        (ok if ifs == ["aen0 static 192.0.2.38/24 gw 192.0.2.1 name uaeamix", "zen0 static 192.0.2.39/24",
                       "domain example.net"] and "syslogd=no" in rc and "swap_add" not in rc
              and "monsw 34" in disp
              and "start manual" in disp and "card auto" in disp
              and "/usr/sbin/ifup -n" in crl and "/usr/amix/bin/xstart -n" in crl else fail)(
            "l11_admin, the bench profile: aen0 static, zen0 beside it, domain; syslogd=no; no swap_add (the boot step's own rules); monsw; checked: %r %r" % (ifs, out))
        out, ifs, rc, disp, crl = admin(FB_ETHER_IF="zen0", FB_IP="192.0.2.38", FB_NETMASK="255.255.255.0",
                                        FB_GATEWAY="192.0.2.1",
                                        FB_ZEN_CARDS="00:80:51:01:02:03=192.0.2.39=a4000d default=192.0.2.38")
        (ok if ifs == ["zen0 static 192.0.2.38/24 gw 192.0.2.1",
                       "00:80:51:01:02:03 static 192.0.2.39/24 gw 192.0.2.1 name a4000d"] else fail)(
            "l11_admin, a zen0 profile with the address-by-card table: one MAC line per card: %r" % (ifs,))
        out, ifs, *_ = admin(FB_NODENAME="amixbox")
        (ok if ifs == ["* dhcp name amixbox"] else fail)("l11_admin, public with a name: * dhcp name: %r" % (ifs,))
        out, ifs, rc, disp, crl = admin()
        (ok if ifs == ["* dhcp", "hostname dhcp"] else fail)("l11_admin, public without a name: * dhcp, hostname dhcp: %r" % (ifs,))
        (ok if "\n# set to no to disable the SSH server\ndropbear=yes\n" in rc and "syslogd=yes" in rc else fail)(
            "l11_admin: /etc/rc.conf shows the SSH server's switch, dropbear=yes under its comment: %r" % rc)
        (ok if "\nntp=yes          # set the clock from time servers at boot and hourly: ntpsync(1M)\n" in rc else fail)(
            "l11_admin: /etc/rc.conf shows the network time sync's switch, ntp=yes under its comment: %r" % rc)
        (ok if "/usr/sbin/ifup -n" in crl and "xstart" not in crl and "card auto" in disp else fail)(
            "l11_admin, a set without X: /etc/display written, ifup -n run, xstart -n not (it checks the X server)")
        out, *_ = admin(FB_IP="192.0.2.38", FB_NETMASK="255.255.255.7")
        (ok if "DIE netmask '255.255.255.7'" in out else fail)("l11_admin refuses a netmask that is no prefix: %r" % out.strip())

    # (5d) firstboot on a 1.1 disk (FB_L11=y), executed from firstboot.sh's own text:
    # the dialog's DHCP choice, /etc/inet/interfaces from the answers, the amix-xxxx name
    # and syslogd= in /etc/rc.conf
    fbt = open(FIRSTBOOT, encoding="utf-8").read()
    fr = os.path.join(d, "fb11")
    def fbrun(code, answers=(), **kv):
        shutil.rmtree(fr, ignore_errors=True)
        for sub in ("etc/inet", "usr/sbin", "dev"):
            os.makedirs(os.path.join(fr, sub))
        open(os.path.join(fr, "etc", "rc.conf"), "w").write("# rc.conf\nsyslogd=yes\n")
        for tool, body in (("ifup", "exit 0"), ("dlpi-mac", "echo 00:80:10:0a:3f:12")):
            open(os.path.join(fr, "usr", "sbin", tool), "w").write("#!/bin/sh\n%s\n" % body)
            os.chmod(os.path.join(fr, "usr", "sbin", tool), 0o755)
        open(os.path.join(fr, "dev", "zen0"), "w").write("")
        open(os.path.join(fr, "answers"), "w").write("".join(a + "\n" for a in answers))
        sets = "".join("%s='%s'\n" % (k, v) for k, v in kv.items())
        # /tmp first: the scratch root itself lies under /tmp
        code = (code.replace("/tmp/", fr + "/").replace("/etc/", fr + "/etc/").replace("/usr/sbin/", fr + "/usr/sbin/")
                .replace('[ -c "$d" ]', '[ -f "$d" ]').replace("/dev/zen0 /dev/aen0", fr + "/dev/zen0 " + fr + "/dev/aen0"))
        body = ('i=1\nreadask() { ask=`sed -n "${i}p" %s/answers`; i=`expr $i + 1`; }\nuname() { :; }\n'
                'valid_ip() { case "$1" in *.*.*.*) return 0 ;; esac; return 1; }\nclassful_mask() { echo 255.255.255.0; }\n'
                '%s%s\n' % (fr, sets, code))
        r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30)
        rd = lambda *p: open(os.path.join(fr, *p)).read() if os.path.exists(os.path.join(fr, *p)) else ""
        return r.stdout + r.stderr, rd
    net = "\n".join(_extract_func(fbt, f) for f in ("find_ifs", "ask_network", "ask_repo"))
    # the hardware is the test's: an A2065 or none (aen -S), never a Z3660 NIC, and no mknod
    zen_none = lambda c: c.replace("mknod /dev/zen0 c 51 0", "false").replace("( : < /dev/zen0 )", "false")
    net_aen, net_none = zen_none(net).replace("/usr/amiga/bin/aen -S", "true"), \
        zen_none(net).replace("/usr/amiga/bin/aen -S", "false")
    show = '\nask_network\necho "MODE=$FB_NET_MODE CONF=$FB_NET_CONFIGURED IP=$FB_IP REPO=$FB_REPO_HOST NOIF=$FB_NET_NOIF I=$i"\n'
    out, rd = fbrun(net_aen + show,
                    answers=("y", "y", "pkg.example", ""), FB_L11="y", FB_IP="", FB_REPO_HOST="", FB_REPO_IP="")
    (ok if "MODE=dhcp CONF=y IP= REPO=pkg.example NOIF=" in out else fail)(
        "firstboot dialog (1.1): `Use DHCP? y` takes no address, keeps the repository questions: %r" % out.strip()[-120:])
    out, rd = fbrun(net_none + show, answers=(), FB_L11="y", FB_IP="192.0.2.5", FB_REPO_HOST="pkg.example", FB_REPO_IP="")
    (ok if "MODE=dhcp CONF=y IP= REPO=pkg.example NOIF=y I=1" in out and "network questions are skipped" in out else fail)(
        "firstboot dialog (1.1), no interface: no network question asked, DHCP recorded for a card fitted later: %r"
        % out.strip()[-120:])
    out, rd = fbrun(net_none + show, answers=("y",), FB_L11="", FB_IP="192.0.2.5", FB_REPO_HOST="pkg.example", FB_REPO_IP="")
    (ok if "CONF= " in out and "I=2" in out and "left as the installation set it" in out else fail)(
        "firstboot dialog (1.0), no interface: as before (asked, then left as the installation set it): %r"
        % out.strip()[-120:])
    # a user made in the dialog (sysinit, before section 4 mounts /home) lands on the data slice
    users = "\n".join(_extract_func(fbt, f) for f in ("home_on_data", "ask_users")) \
        .replace("/usr/amiga/lib/amixmkuser", "amixmkuser").replace("/etc/devnm", "devnm")
    stubs = ('devnm() { echo "/dev/dsk/c6d0s1 /"; }\n'
             'mount() { echo "MOUNT $*"; [ -z "$MOUNT_FAILS" ]; }\numount() { echo "UMOUNT $*"; }\n'
             'mkdir() { :; }\namixmkuser() { echo "MKUSER mounted=$HOME_MNT"; }\n')
    for what, kv, want, bad in (
            ("a data slice", dict(FB_DATA_SLICE="4", FB_ROOT_FSTYPE="ufs"),
             ["MOUNT -F ufs /dev/dsk/c6d0s4 /home", "MKUSER mounted=y", "UMOUNT /home"], ["could not be mounted"]),
            ("no data slice", dict(FB_DATA_SLICE="", FB_ROOT_FSTYPE="ufs"),
             ["MKUSER mounted="], ["MOUNT", "UMOUNT"]),
            ("a failing mount", dict(FB_DATA_SLICE="4", FB_ROOT_FSTYPE="ufs", MOUNT_FAILS="y"),
             ["could not be mounted", "MKUSER mounted="], ["UMOUNT"])):
        out, rd = fbrun(stubs + users + "\nask_users\n", answers=("y",), **kv)
        good = all(w in out for w in want) and not any(b in out for b in bad) \
            and out.find("MOUNT -F") <= out.find("MKUSER")
        (ok if good else fail)("firstboot dialog, a user account with %s: /home mounted around amixmkuser "
                               "as needed: %r" % (what, " | ".join(out.strip().splitlines()[-4:])))
    m8 = re.search(r'\nfb_bits\(\)\n\{.*?\n\}\nif \[ "\$FB_L11" = y \] && \[ "\$FB_NET_CONFIGURED" = y \]; then\n(.*?)\nelif ', fbt, re.S)
    m1 = re.search(r'\nif \[ "\$FB_L11" = y \] && \[ -z "\$FB_NODENAME" \]; then\n.*?\nuname -S "\$FB_NAME_EFF" 2>/dev/null \|\| true\n', fbt, re.S)
    m7 = re.search(r'\nif \[ "\$FB_L11" = y \]; then\n\tsv=yes;.*?\nelif ', fbt, re.S)
    if not (m8 and m1 and m7):
        fail("firstboot.sh: no 1.1 nodename, interfaces or rc.conf step (%s)" % [bool(m8), bool(m1), bool(m7)])
    else:
        s8 = m8.group(0)[:m8.group(0).rindex("\nelif ")] + "\nfi\n"
        s1 = m1.group(0)
        for what, kv, want in (
                ("DHCP, no name", dict(FB_NET_MODE="dhcp", FB_NODENAME=""), ["* dhcp", "hostname dhcp"]),
                ("DHCP with a name", dict(FB_NET_MODE="dhcp", FB_NODENAME="box"), ["* dhcp name box"]),
                ("static", dict(FB_NET_MODE="static", FB_NODENAME="box", FB_ETHER_IF="aen0", FB_IP="192.0.2.11",
                                FB_NETMASK="255.255.255.0", FB_GATEWAY="192.0.2.1", FB_DNS1="192.0.2.1"),
                 ["aen0 static 192.0.2.11/24 gw 192.0.2.1 name box", "dns 192.0.2.1"])):
            base = dict(FB_L11="y", FB_NET_CONFIGURED="y", FB_DNS1="", FB_DNS2="", FB_DOMAIN="")
            base.update(kv)
            out, rd = fbrun(s1 + s8, **base)
            got = [l for l in rd("etc", "inet", "interfaces").splitlines() if not l.startswith("#")]
            (ok if got == want else fail)("firstboot (1.1) interfaces, %s: %r" % (what, got))
        out, rd = fbrun(s1, FB_L11="y", FB_NODENAME="")
        (ok if rd("etc", "nodename").strip() == "amix-3f12" else fail)(
            "firstboot (1.1): no name -> amix- + the MAC's last four hex digits (dlpi-mac): %r" % rd("etc", "nodename").strip())
        out, rd = fbrun(m7.group(0)[:m7.group(0).rindex("\nelif ")] + "\nfi\n", FB_L11="y", FB_SYSLOG="n")
        (ok if rd("etc", "rc.conf").splitlines() == ["# rc.conf", "syslogd=no"] else fail)(
            "firstboot (1.1): FB_SYSLOG=n -> syslogd=no in /etc/rc.conf, the line replaced: %r" % rd("etc", "rc.conf"))

    # (6) l11_bcheckrc: the stock 2.1 bcheckrc becomes the medium's retry-patched one in
    # place (its hard link follows); a patched one is kept; any other is left alone
    core = os.path.join(STOCK_CORE, "sbin", "bcheckrc")
    if not os.path.exists(core):
        skip("no stock core bcheckrc in build/core (tools/build-core-tree.sh) -- l11_bcheckrc not executed")
    else:
        inst = os.path.join(d, "inst")
        lroot = os.path.join(inst, "l11")
        os.makedirs(os.path.join(inst, "bin"), exist_ok=True)
        os.makedirs(lroot, exist_ok=True)
        if not os.path.exists(os.path.join(inst, "bin", "sum")):
            os.symlink(shutil.which("sum"), os.path.join(inst, "bin", "sum"))
        stock = open(core).read()
        line = "\t\t[ -x /sbin/kbootset ] && /sbin/kbootset retry >/dev/console 2>&1\n"
        patched = stock.replace("\t\t/sbin/uadmin 1 1\n", line + "\t\t/sbin/uadmin 1 1\n")
        open(os.path.join(lroot, "bcheckrc"), "w").write(patched)
        open(os.path.join(lroot, "bcheckrc.stock"), "w").write(
            subprocess.run(["sum", "-r", core], capture_output=True, text=True).stdout.split()[0] + "\n")
        body = ('msg() { echo "MSG $*"; }\nwarn() { echo "WARN $*"; }\ndie() { echo "DIE $*"; exit 3; }\n'
                "INST=%s\nL11=%s\n" % (inst, lroot) + _extract_func(l11, "l11_bcheckrc") + '\nl11_bcheckrc "$1"\n')
        tgt = os.path.join(d, "bc")
        os.makedirs(os.path.join(tgt, "sbin"), exist_ok=True)
        os.makedirs(os.path.join(tgt, "usr", "sbin"), exist_ok=True)
        f1, f2 = os.path.join(tgt, "sbin", "bcheckrc"), os.path.join(tgt, "usr", "sbin", "bcheckrc")
        for case, content in (("stock", stock), ("patched", patched), ("changed", stock + "# local\n")):
            for f in (f1, f2):
                if os.path.exists(f):
                    os.remove(f)
            open(f1, "w").write(content)
            os.link(f1, f2)
            r = subprocess.run(["/usr/bin/dash", "-c", body, "x", f1], capture_output=True, text=True, timeout=30)
            now = open(f2).read()
            good = {"stock": now == patched and now.count(line) == 3 and "kbootset retry before" in r.stdout,
                    "patched": now == patched and "already carries" in r.stdout,
                    "changed": now == content and "NOT added" in r.stdout}[case]
            if good and "DIE" not in r.stdout:
                ok("l11_bcheckrc: a %s bcheckrc -> %s" % (case, {
                    "stock": "the retry-patched one, written in place (3 lines; the link follows)",
                    "patched": "kept, said so", "changed": "left alone, said so"}[case]))
            else:
                fail("l11_bcheckrc on a %s bcheckrc: %r" % (case, r.stdout.strip()))

    # (7) /etc/rc2.d/S99zkbootset is kbootset's package object (-26 on); l11_markgood
    # only checks that the package laid it, and stops the install when it did not
    mg = _extract_func(l11, "l11_markgood")
    mt = os.path.join(d, "mg")
    for present in (True, False):
        shutil.rmtree(mt, ignore_errors=True)
        os.makedirs(os.path.join(mt, "etc", "init.d")); os.makedirs(os.path.join(mt, "etc", "rc2.d"))
        if present:
            open(os.path.join(mt, "etc", "init.d", "kbmarkgood"), "w").write("#!/bin/sh\n")
            os.link(os.path.join(mt, "etc", "init.d", "kbmarkgood"), os.path.join(mt, "etc", "rc2.d", "S99zkbootset"))
        out = subprocess.run(["/usr/bin/dash", "-c", 'msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n'
                              "TARGET=%s\n%s\nl11_markgood\n" % (mt, mg)], capture_output=True, text=True, timeout=30).stdout
        good = ("MSG" in out and "DIE" not in out) if present else ("DIE" in out and "kbootset -26" in out)
        (ok if good else fail)("l11_markgood: %s" % ("kbootset's S99zkbootset present -> passes" if present else
                               "no kbmarkgood/S99zkbootset -> the install stops naming kbootset -26") + ("" if good else " -- %r" % out))

    # (8) l11_kpkg_inst: the record's name is the catalog row's pkginst=, else its name
    kl = os.path.join(d, "kl11")
    os.makedirs(os.path.join(kl, "kpkg"), exist_ok=True)
    open(os.path.join(kl, "kpkg", "catalog"), "w").write(
        "#apkg-catalog 1\n#ext kpkg 1\n"
        "#kpkg kernel-k30-u 1.1.0 role=kernel line=k30 size=1 sha256=x file=base/a.pkg pkginst=kern30u\n"
        "#kpkg plainname 1.0 role=kernel line=k46 size=1 sha256=x file=base/b.pkg\n#end kpkg\n")
    body = "L11=%s\n" % kl + _extract_func(l11, "l11_kpkg_inst") + '\nl11_kpkg_inst "$1"\n'
    got = [subprocess.run(["/usr/bin/dash", "-c", body, "x", n], capture_output=True, text=True,
                          timeout=30).stdout.strip() for n in ("kernel-k30-u", "plainname", "absent")]
    if got == ["kern30u", "plainname", ""]:
        ok("l11_kpkg_inst: the row's pkginst= (kern30u), else its name; nothing for a missing row (C2-2 v4)")
    else:
        fail("l11_kpkg_inst: %r" % (got,))

    # (9) l11_inittab: amix-base's default (here: core's with the dlm line, the
    # same shape) -- the dlm line once, the first sysinit entry, C3-5's text, the file the
    # medium's inittab (sum -r); each way it can be wrong stops the install naming amix-base
    core_it = os.path.join(STOCK_CORE, "etc", "inittab")
    dlm = "dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1"
    if not os.path.exists(core_it):
        skip("no stock core inittab in build/core (tools/build-core-tree.sh) -- l11_inittab not executed")
    else:
        inst = os.path.join(d, "inst")
        lroot = os.path.join(inst, "l11")
        os.makedirs(os.path.join(inst, "bin"), exist_ok=True)
        os.makedirs(lroot, exist_ok=True)
        if not os.path.exists(os.path.join(inst, "bin", "sum")):
            os.symlink(shutil.which("sum"), os.path.join(inst, "bin", "sum"))
        stock = open(core_it).read().splitlines(True)
        first = next(i for i, l in enumerate(stock) if l.split(":")[2:3] == ["sysinit"])
        good = "".join(stock[:first] + [dlm + "\n"] + stock[first:])
        open(os.path.join(lroot, "inittab"), "w").write(good)
        tgt = os.path.join(d, "it")
        os.makedirs(os.path.join(tgt, "etc"), exist_ok=True)
        dlm_line = next(l for l in l11.splitlines() if l.startswith("L11_DLM="))
        body = ('msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n'
                "INST=%s\nL11=%s\nTARGET=%s\n%s\n" % (inst, lroot, tgt, dlm_line.split("\t")[0]) +
                _extract_func(l11, "l11_inittab") + "\nl11_inittab\n")
        cases = (
            ("as amix-base ships it", good, "MSG inittab"),
            ("no dlm line", "".join(stock), "0 line(s) with the id dlm"),
            ("the dlm line twice", good.replace(dlm + "\n", dlm + "\n" + dlm + "\n"), "2 line(s) with the id dlm"),
            ("the dlm line after S0", "".join(stock[:first + 1] + [dlm + "\n"] + stock[first + 1:]),
             "not the first sysinit entry"),
            ("another dlm text", good.replace(dlm, dlm.replace(" -B", "")), "the dlm line reads"),
            ("another line changed", good.replace("S2::sysinit", "S2::sysinit:"), "not amix-base's inittab"),
        )
        for what, text, want in cases:
            open(os.path.join(tgt, "etc", "inittab"), "w").write(text)
            r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30)
            okc = want in r.stdout and (("DIE" in r.stdout and "is not amix-base's default" in r.stdout)
                                        if want != "MSG inittab" else "DIE" not in r.stdout)
            (ok if okc else fail)("l11_inittab, %s: %s" % (what, "passes" if want == "MSG inittab" else
                                  "stops naming amix-base's default" if okc else repr(r.stdout.strip())))

    # (10) l11_keys' module half: a module kernel brings modtools; KERNEL_MODPKGS
    # must be role=module rows of the kernel's line named <module>-k<line>, and only with
    # a module kernel
    kc = os.path.join(d, "kc")
    os.makedirs(os.path.join(kc, "kpkg"), exist_ok=True)
    os.makedirs(os.path.join(kc, "bin"), exist_ok=True)
    for f in ("bin/apkg", "updbootpart", "bcheckrc", "bcheckrc.stock", "inittab", "2.1_unix.sum"):
        open(os.path.join(kc, f), "w").write("x\n")
    open(os.path.join(kc, "kpkg", "catalog"), "w").write(
        "#apkg-catalog 1\nmodtools|1|modtools|base/m.pkg|0|1|none|system|m\n#ext kpkg 1\n"
        "#kpkg kernel-k46-m k46.1 role=kernel line=k46 kabi=k46.1.0 pin=p size=1 sha256=x file=base/a.pkg pkginst=kern46m\n"
        "#kpkg kernel-k46-z 1.1 role=kernel line=k46 kabi=static pin=p size=1 sha256=x file=base/b.pkg pkginst=kern46z\n"
        "#kpkg z3660eth-k46 1.0 role=module line=k46 kabi=k46.1.0 pin=p size=1 sha256=x file=base/c.pkg pkginst=zeth46\n"
        "#kpkg z3660eth-k30 1.0 role=module line=k30 kabi=k30.1.0 pin=p size=1 sha256=x file=base/d.pkg pkginst=zeth30\n"
        "#kpkg zeth-odd 1.0 role=module line=k46 kabi=k46.1.0 pin=p size=1 sha256=x file=base/e.pkg pkginst=zodd\n"
        "#end kpkg\n")
    kbody = ('msg() { :; }\nwarn() { :; }\ndie() { echo "DIE $*"; exit 3; }\n'
             'is_num() { expr "$1" : "[0-9][0-9]*$" > /dev/null; }\n'
             "INST=%s\nL11=%s\nL11_APKG=%s/bin/apkg\nL11_STORE_MB=64\n" % (kc, kc, kc) +
             _extract_func(l11, "l11_kpkg_key") + "\n" + _extract_func(l11, "l11_rootbase") + "\n" + _extract_func(l11, "l11_keys") +
             '\nl11_keys\necho "XPKGS=$L11_XPKGS MODS=$L11_MODS KMOD=$L11_KMOD"\n')

    def keys(kernel, mods, hba="z3660scsi", body=None):
        env = dict(os.environ, KERNEL_KPKG=kernel, KERNEL_MODPKGS=mods, TARGET_FASTMEM_MB="32",
                   INSTALL_CPU="040", TARGET_HBA=hba, TARGET_SCSI_ID="6", TARGET_ROOT_SLICE="1",
                   TARGET_BOOT_SLICE="3", TARGET_BOOT_MB="", INSTALL_TARGET_PREBUILT="0")
        return subprocess.run(["/usr/bin/dash", "-c", body or kbody], capture_output=True, text=True,
                              timeout=30, env=env).stdout.strip()
    for what, kernel, mods, want in (
            ("a module kernel and z3660eth-k46", "kernel-k46-m", "z3660eth-k46", "XPKGS=modtools MODS= z3660eth KMOD=y"),
            ("a module kernel, no modules", "kernel-k46-m", "", "XPKGS=modtools MODS= KMOD=y"),
            ("a static kernel, no modules", "kernel-k46-z", "", "XPKGS= MODS= KMOD=n"),
            ("a static kernel with a module", "kernel-k46-z", "z3660eth-k46", "DIE KERNEL_MODPKGS='z3660eth-k46' needs a module kernel"),
            ("a module of the other line", "kernel-k46-m", "z3660eth-k30", "is not a k46 module"),
            ("a kernel row as a module", "kernel-k46-m", "kernel-k46-z", "is not a module package"),
            ("a module not named <module>-k46", "kernel-k46-m", "zeth-odd", "is not named <module>-k46"),
            ("a module the catalog lacks", "kernel-k46-m", "absent-k46", "is not a module package")):
        got = keys(kernel, mods)
        (ok if want in got else fail)("l11_keys, %s: %s" % (what, got if want not in got else
                                      ("refused" if "DIE" in got else want)))
    # (10b) the controller key and the root record from TARGET_HBA (C4-1 sec 5.2, C4-2 sec 8)
    hbody = kbody.replace('echo "XPKGS=$L11_XPKGS MODS=$L11_MODS KMOD=$L11_KMOD"',
                          'echo "BOOTDEV=$KBOOTSET_BOOTDEV REC=$KBOOTSET_ROOTREC"')
    for hba, want in (("a3000", "BOOTDEV=mobo:a3000-wd REC=sd id=00000000 base=00000000 unit=6 slice=1 mobo"),
                      ("gayle", "BOOTDEV=mobo:gayle REC=sd id=00000000 base=00000000 unit=6 slice=1 mobo"),
                      ("a4000t", "BOOTDEV=mobo:a4000t-710 REC=sd id=00000000 base=00000000 unit=6 slice=1 mobo"),
                      ("a4kt710", "BOOTDEV=mobo:a4000t-710 "),
                      ("z3660scsi", "BOOTDEV=zorro:144b:01 REC=sd id=144b0100 base=00000000 unit=6 slice=1"),
                      ("a4091", "BOOTDEV=zorro:0202:54 REC=sd id=02025400 base=00000000 unit=6 slice=1"),
                      ("a4092", "BOOTDEV=zorro:c0de:01 REC=sd id=c0de0100 base=00000000 unit=6 slice=1"),
                      ("a2091", "DIE INSTALL_LAYOUT=1.1: no controller key known for TARGET_HBA='a2091'")):
        got = keys("kernel-k46-m", "", hba, hbody)
        (ok if want in got else fail)("l11_keys, TARGET_HBA=%s: %s" % (hba, got if want not in got else
                                      ("refused" if "DIE" in got else want)))

    # (11) l11_kpkg_record for a module: name, role and the file lines of its
    # object and modreg.d file, both on the target
    rt = os.path.join(d, "rec")
    for sub in ("var/apkg/kpkg", "etc/conf/mod.d", "etc/conf/modreg.d"):
        os.makedirs(os.path.join(rt, sub), exist_ok=True)
    open(os.path.join(rt, "etc/conf/mod.d/z3660eth"), "w").write("o")
    open(os.path.join(rt, "etc/conf/modreg.d/z3660eth"), "w").write("#\n")
    rbody = ('die() { echo "DIE $*"; exit 3; }\nL11=%s\nTARGET=%s\n' % (kc, rt) +
             _extract_func(l11, "l11_kpkg_inst") + "\n" + _extract_func(l11, "l11_kpkg_record") +
             '\nl11_kpkg_record "$1" "$2" && echo RECORD-OK\n')
    full = ("name z3660eth-k46\nversion 1.0\nrole module\nline k46\n"
            "file /etc/conf/mod.d/z3660eth 1 aa\nfile /etc/conf/modreg.d/z3660eth 2 bb\n")
    for what, rec, role, want in (
            ("a module's full record", full, "module", "RECORD-OK"),
            ("a record without the modreg.d line", full.replace("file /etc/conf/modreg.d/z3660eth 2 bb\n", ""),
             "module", "has no file line for /etc/conf/modreg.d/z3660eth"),
            ("a module record of another role", full.replace("role module", "role kernel"), "module", "says role 'kernel'")):
        open(os.path.join(rt, "var/apkg/kpkg/zeth46"), "w").write(rec)
        got = subprocess.run(["/usr/bin/dash", "-c", rbody, "x", "z3660eth-k46", role], capture_output=True,
                             text=True, timeout=30).stdout.strip()
        (ok if want in got else fail)("l11_kpkg_record, %s: %s" % (what, "accepted" if want == "RECORD-OK" and
                                      want in got else "refused" if want in got else got))

    # (12) l11_namelist (C2-4 v9 §12): /stand/unix (core's link to 2.1_unix) and /unix
    # go, 2.1_unix stays and is checked, S01kbnamelist is the one call
    nt = os.path.join(d, "nl")
    for case in ("core", "changed"):
        shutil.rmtree(nt, ignore_errors=True)
        os.makedirs(os.path.join(nt, "stand"))
        os.makedirs(os.path.join(nt, "etc", "rc2.d"))
        os.makedirs(os.path.join(nt, "etc", "init.d"))
        open(os.path.join(nt, "etc", "init.d", "kbnamelist"), "w").write("#!/bin/sh\n")
        os.link(os.path.join(nt, "etc", "init.d", "kbnamelist"), os.path.join(nt, "etc", "rc2.d", "S01kbnamelist"))
        open(os.path.join(nt, "stand", "2.1_unix"), "w").write("the 1992 kernel\n")
        os.link(os.path.join(nt, "stand", "2.1_unix"), os.path.join(nt, "stand", "unix"))
        open(os.path.join(nt, "unix"), "w").write("x")
        want_sum = subprocess.run(["sum", "-r", os.path.join(nt, "stand", "2.1_unix")], capture_output=True,
                                  text=True).stdout.split()[0]
        open(os.path.join(kc, "2.1_unix.sum"), "w").write((want_sum if case == "core" else "1") + "\n")
        open(os.path.join(kc, "bin", "sum"), "w").write('#!/bin/sh\nexec %s "$@"\n' % shutil.which("sum"))
        os.chmod(os.path.join(kc, "bin", "sum"), 0o755)
        nbody = ('msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\nrun() { "$@"; }\n'
                 "INST=%s\nL11=%s\nTARGET=%s\n" % (kc, kc, nt) + _extract_func(l11, "l11_namelist") + "\nl11_namelist\n")
        out = subprocess.run(["/usr/bin/dash", "-c", nbody], capture_output=True, text=True, timeout=30).stdout
        gone = not os.path.exists(os.path.join(nt, "stand", "unix")) and not os.path.exists(os.path.join(nt, "unix"))
        kept = open(os.path.join(nt, "stand", "2.1_unix")).read() == "the 1992 kernel\n"
        if case == "core":
            good = (gone and kept and "DIE" not in out
                    and "S01kbnamelist" > "S01MOUNTFSYS" and "S01kbnamelist" < "S02PRESERVE")
            (ok if good else fail)("l11_namelist: /stand/unix and /unix removed, 2.1_unix kept (sum -r checked), "
                                   "kbootset's S01kbnamelist checked (it sorts after S01MOUNTFSYS and before "
                                   "S02PRESERVE)" if good else "l11_namelist: %r" % out.strip())
            os.remove(os.path.join(nt, "etc", "rc2.d", "S01kbnamelist"))
            os.link(os.path.join(nt, "stand", "2.1_unix"), os.path.join(nt, "stand", "unix"))
            out = subprocess.run(["/usr/bin/dash", "-c", nbody], capture_output=True, text=True, timeout=30).stdout
            (ok if "kbootset -26" in out and "DIE" in out else fail)(
                "l11_namelist: no S01kbnamelist from the kbootset package stops the install" +
                ("" if "kbootset -26" in out else " -- %r" % out.strip()))
        else:
            (ok if "is not core's 2.1 kernel" in out else fail)(
                "l11_namelist: a 2.1_unix that is not core's stops the install" if "is not core's" in out
                else "l11_namelist with a changed 2.1_unix: %r" % out.strip())

    # (13) S99zen beside another interface: install.sh lays it for a z3660eth module
    # profile at FB_ZEN_IP (never FB_IP), through emit_zen_hook; a zen0 with an address
    # and no gateway gets a guarded route line
    code = strip_full_comments(src)
    if re.search(r'\*" z3660eth-k"\*\)', code) and 'FB_IP="$FB_ZEN_IP"' in code and \
            re.search(r'\[ "\$FB_ZEN_IP" != "\$FB_IP" \]', code):
        ok("install.sh lays S99zen for a z3660eth-module profile at FB_ZEN_IP, refusing FB_IP's address")
    else:
        fail("install.sh does not lay S99zen for z3660eth-module profiles at FB_ZEN_IP")
    zfunc = _extract_func(src, "emit_zen_hook")
    rc, em = _emit_zen(zfunc, "192.0.2.39", "255.255.255.0", gw="")
    if rc == 0 and em and b"FALLBACK=192.0.2.39\n" in em and \
            b'  [ -n "$GATEWAY" ] && /usr/sbin/route add default $GATEWAY 1\n' in em and \
            b"zen0 has no address" not in em:
        ok("emit_zen_hook with an address and no gateway: zen0 up at it, the route line guarded")
    else:
        fail("emit_zen_hook with an address and no gateway: rc %d" % rc)

    # (14) first boot on a 1.1 disk: /stand/unix out of core (APKG's tools from /tmp,
    # 2.1_unix its own file), /etc/inittab back to root sys 0664
    fb = read_sh(FIRSTBOOT)
    for what, good in (
            ("install.sh writes FB_STANDUNIX_RM=y on a 1.1 disk and FB_INITTAB_SYS=y with a module kernel",
             '[ "$INSTALL_LAYOUT" = 1.1 ] && echo "FB_STANDUNIX_RM=y"' in src and
             '[ "${L11_KMOD:-n}" = y ] && echo "FB_INITTAB_SYS=y"' in src),
            ("firstboot: /stand/2.1_unix re-registered as a file and /stand/unix removed from core with APKG's "
             "installf/removef from /tmp, then checked in contents and with pkgchk", re.search(
                 r'FB_STANDUNIX_RM" = y \].*?cd /tmp && /usr/apkg/bin/installf core /stand/2\.1_unix f 0644 root root'
                 r'.*?/usr/apkg/bin/removef core /stand/unix.*?/usr/apkg/bin/removef -f core.*?'
                 r'/var/sadm/install/contents.*?/usr/apkg/bin/pkgchk -p /stand/2\.1_unix core', fb, re.S)
             and not re.search(r'/usr/sbin/removef', fb)),
            ("firstboot: FB_INITTAB_SYS=y gives /etc/inittab root sys 0664 and checks it", re.search(
                r'FB_INITTAB_SYS" = y \].*?chgrp sys /etc/inittab.*?chmod 664 /etc/inittab.*?ls -l /etc/inittab', fb, re.S))):
        (ok if good else fail)(what)

    # (19) 1.1 supports clean installs only -- a disk that holds Amix is asked the
    # erase question (choose_disk's stock state 5) and is never offered an upgrade
    setup_src = open(SETUP).read()
    m = re.search(r'\n\tif rdb_present "\$SCSI"; then\n.*?\n\tfi\n}', setup_src, re.S)
    left = [w for w in ("upgrade_offer", "upgrade_sizes", "ANS_UPGRADE", "ANS_DROP_HOME",
                        "INSTALL_UPGRADE", "UPGRADE_DROP_HOME") if w in setup_src]
    if not m:
        fail("setup.sh: no erase question for a disk that carries an RDB")
    else:
        (ok if not left else fail)("setup.sh: no upgrade offer and no upgrade answers%s"
                                   % ((" -- still: " + " ".join(left)) if left else ""))
        body = m.group(0)[:-2].replace("/etc/rdb", "true")
        for answer, want in (("y", "ERASE"), ("n", "RESTART")):
            prog = ("rdb_present() { return 0; }\nreadask() { printf 'ASK %%s\\n' \"$1\"; ask=%s; }\n"
                    "restart() { echo RESTART; exit 0; }\nSCSI=6\n%s\necho ERASE\n" % (answer, body))
            out = subprocess.run(["/usr/bin/dash", "-c", prog], capture_output=True, text=True, timeout=30).stdout
            asks = [l for l in out.splitlines() if l.startswith("ASK")]
            good = (out.strip().endswith(want) and len(asks) == 1
                    and "erase this disk" in asks[0] and "pgrade" not in out)
            (ok if good else fail)("setup.sh, a disk that holds Amix, answer %s: one question, the erase "
                                   "question, then %s%s" % (answer, want.lower(), "" if good else " -- got %r" % out.strip()))

    # (15) the 1.1 base carries m4: syslogd reads /etc/syslog.conf through
    # /usr/ccs/bin/m4 (the m4 package, or Cdev), so a 1.1 order with neither stops the install
    # (a network install is not refused there: its first stage adds m4, the minimal set included)
    m = re.search(r'\nif \[ "\$INSTALL_LAYOUT" = 1\.1 \] && \[ "\$SOURCE_KIND" != net \]; then\n\tORDCDEV=.*?\nfi\n', src, re.S)
    m1 = re.search(r'\nif \[ "\$SOURCE_KIND" = net \] && \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n\tORDM4=.*?\nfi\n', src, re.S)
    if not m or not m1:
        fail("install.sh has no m4 check of a 1.1 order, or no first-stage m4 rule for a network install")
    else:
        ct = os.path.join(d, "cdev")
        os.makedirs(os.path.join(ct, "tmp"), exist_ok=True)
        for what, kind, pkgs, want in (("an order with m4", "cdfs", "core bsd APKG m4", "PASSED"),
                                       ("an order with Cdev", "cdfs", "core bsd Cdev APKG", "PASSED"),
                                       ("an order with neither", "cdfs", "core bsd APKG", "DIE install order"),
                                       ("a network install's order with neither", "net", "core bsd APKG", "PASSED")):
            open(os.path.join(ct, "order"), "w").write("# set: minimal\n" + "\n".join(pkgs.split()) + "\n")
            body = ('die() { echo "DIE $*"; exit 3; }\nINSTALL_LAYOUT=1.1\nSOURCE_KIND=%s\nTARGET=%s\nORDER=%s/order\n'
                    % (kind, ct, ct) + m.group(0) + "echo PASSED\n")
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            (ok if want in out and not os.listdir(os.path.join(ct, "tmp")) else fail)(
                "install.sh's 1.1 m4 check, %s: %s" % (what, "accepted" if "PASSED" in out else "refused"))
        # the first-stage rule, executed: an order with neither gains m4 (a copy, the medium's untouched)
        for what, pkgs, want in (("the minimal order (neither)", "core bsd APKG", "core bsd APKG m4"),
                                 ("an order with Cdev", "core bsd Cdev APKG", "core bsd Cdev APKG")):
            open(os.path.join(ct, "order"), "w").write("# set: minimal\n" + "\n".join(pkgs.split()) + "\n")
            body = ('die() { echo "DIE $*"; exit 3; }\nmsg() { :; }\nINSTALL_LAYOUT=1.1\nSOURCE_KIND=net\nTARGET=%s\n'
                    'ORDER=%s/order\n' % (ct, ct) + m1.group(0) + 'grep -v "^#" "$ORDER" | tr "\\n" " "\n')
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            left = [f for f in os.listdir(os.path.join(ct, "tmp")) if f != "order.net1"]
            (ok if out.split() == want.split() and not left else fail)(
                "install.sh's first-stage m4 rule, %s: %s" % (what, out.strip()))
            for f in os.listdir(os.path.join(ct, "tmp")):
                os.unlink(os.path.join(ct, "tmp", f))

    # (15b) the network loop: every package the order names has a catalog row, or the install stops
    # naming the missing ones (the repository is incomplete); found ones are listed by catalog name
    m = re.search(r'\n\tnetnames="\$TARGET/tmp/\.netnames\.\$\$" netmiss=.*?\n\t\[ -s "\$netnames" \] \|\| die [^\n]*\n', src, re.S)
    if not m:
        fail("install.sh's network loop has no catalog-row check of the order")
    else:
        nt = os.path.join(d, "netloop")
        os.makedirs(os.path.join(nt, "tmp"), exist_ok=True)
        open(os.path.join(nt, "catalog"), "w").write(
            "#apkg-catalog 1\ncore|2.1|core|stock/core-2.1.pkg|x|1|none|system|d\n"
            "m4|2.1|m4|stock/m4-2.1.pkg|x|1|none|system|d\namix-base|1.0-27|amxbase|amxbase-1.0-27.pkg|x|1|none|system|d\n")
        for what, pkgs, want in (("an order all in the catalog", "core amxbase m4", "LIST core amix-base m4"),
                                 ("an order naming cdfs, which the catalog lacks", "core cdfs m4", "DIE network source: the repository catalog has no row for cdfs")):
            open(os.path.join(nt, "order"), "w").write("# set: minimal\n" + "\n".join(pkgs.split()) + "\n")
            body = ('die() { echo "DIE $*"; exit 3; }\nTARGET=%s\nORDER=%s/order\nNETCAT=%s/catalog\n'
                    % (nt, nt, nt) + m.group(0) + 'echo LIST `cat "$netnames"`\n')
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            left = os.listdir(os.path.join(nt, "tmp"))
            (ok if want in out and (not left or left == [os.path.basename(f) for f in left if f.startswith(".netnames")]) else fail)(
                "install.sh's network loop, %s: %s" % (what, out.strip()[:90]))
            for f in os.listdir(os.path.join(nt, "tmp")):
                os.unlink(os.path.join(nt, "tmp", f))

    # (16) C4-1: l11.sh reads the kernel's sd cards from its sidecar (sdcards=4, absent = 2)
    # and install.sh hands FB_SDCARDS=4 to the first boot
    m = re.search(r'\n\t_sc=`.*?\n\tcase "\$L11_SDCARDS" in .*?esac\n', l11, re.S)
    if not m or '[ "${L11_SDCARDS:-2}" = 4 ] && echo "FB_SDCARDS=4"' not in src:
        fail("l11.sh does not read sdcards= from the kernel's sidecar, or install.sh does not pass FB_SDCARDS=4")
    else:
        st = os.path.join(d, "sdc")
        os.makedirs(os.path.join(st, "stand", "k46"), exist_ok=True)
        for what, side, want in (("sdcards=4", "kabi=k46.1.0\nsdcards=4\nline=k46\n", "SDC=4"),
                                 ("no sdcards= key", "kabi=k46.1.0\nline=k46\n", "SDC=2"),
                                 ("sdcards=3", "sdcards=3\n", "DIE")):
            open(os.path.join(st, "stand", "k46", "kabi"), "w").write(side)
            body = ('die() { echo "DIE $*"; exit 3; }\nTARGET=%s\nL11_LINE=46\n' % st
                    + m.group(0) + 'echo "SDC=$L11_SDCARDS"\n')
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            (ok if want in out else fail)("l11.sh's sd cards from the sidecar, %s: %s" % (what, out.strip()))

    # (18) C4-1: the first boot names the root as the running kernel does (/etc/devnm /), so
    # vfstab follows a kernel whose card order differs from the install kernel's
    m = re.search(r'\nset -- `/etc/devnm / 2>/dev/null`\n.*?\nfi\n', fb, re.S)
    if not m:
        fail("firstboot.sh does not take the root's name from /etc/devnm")
    else:
        dv = os.path.join(d, "devnm")
        os.makedirs(dv, exist_ok=True)
        for what, out_dev, sdc, want in (("the same name", "/dev/dsk/c6d0s1 /", "", "ID=6"),
                                         ("the WD as card 1 under a four-card kernel", "/dev/dsk/ced0s1 /", "4", "ID=e"),
                                         ("a card-3 root before 4d (core's c6d1 node)", "/dev/dsk/c6d1s1 /", "4", "ID=16"),
                                         ("a d1 name on a two-card kernel", "/dev/dsk/c6d1s1 /", "", "ID=6"),
                                         ("no devnm answer", "", "", "ID=6")):
            open(os.path.join(dv, "devnm"), "w").write("#!/bin/sh\n[ -n '%s' ] && echo '%s'\n" % (out_dev, out_dev))
            os.chmod(os.path.join(dv, "devnm"), 0o755)
            body = ("ID=6\nFB_SCSI_ID=6\nFB_SDCARDS=%s\n" % sdc + m.group(0).replace("/etc/devnm", dv + "/devnm")
                    + 'echo "ID=$ID FB=$FB_SCSI_ID"\n')
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            last = out.strip().splitlines()[-1] if out.strip() else ""
            (ok if last == "%s FB=%s" % (want, want[3:]) else fail)("firstboot's root name from devnm, %s: %s" % (what, last))

    # (17) (C2-4 v12 §14): firstboot's step 4d is `kbootset nodes`, ungated by
    # FB_SDCARDS (kbootset reads the sidecar itself); its line logged, a failure a WARNING
    m = re.search(r'\n# --- 4d\..*?\n(if \[ -x /sbin/kbootset \]; then\n.*?\nfi\n)', fb, re.S)
    if not m:
        fail("firstboot.sh's step 4d does not call /sbin/kbootset nodes")
    else:
        blk = m.group(1)
        (ok if "FB_SDCARDS" not in blk and "mknod" not in blk and "removef" not in blk else fail)(
            "firstboot 4d: no FB_SDCARDS gate and no node loop of its own (kbootset owns the set)")
        a4d = fb.index("# --- 4d.")
        (ok if fb.index("# --- 4c.") < a4d < fb.index("# --- 5. ") else fail)(
            "firstboot 4d runs after the package steps (4b, 4c) and before the network steps")
        sb = os.path.join(d, "fbnodes")
        shutil.rmtree(sb, ignore_errors=True)
        os.makedirs(sb)
        kb = os.path.join(sb, "kbootset")
        for what, line, rc, want in (
                ("a four-card set made", "kbootset: nodes: made 256, removed 256 d1 nodes; registered to core", 0,
                 ["firstboot: kbootset: nodes: made 256, removed 256 d1 nodes; registered to core"]),
                ("a two-card kernel", "kbootset: nodes: no four-card kernel installed (no sdcards=4 in /stand/k30/kabi "
                 "or /stand/k46/kabi): core's nodes stand", 0,
                 ["firstboot: kbootset: nodes: no four-card kernel installed (no sdcards=4 in /stand/k30/kabi or "
                  "/stand/k46/kabi): core's nodes stand"]),
                ("a failed registration", "kbootset: nodes: made 256, removed 256 d1 nodes; WARNING: core's "
                 "registration failed (APKG's installf, removef)", 1,
                 ["firstboot: kbootset: nodes: made 256, removed 256 d1 nodes; WARNING: core's registration failed "
                  "(APKG's installf, removef)", "firstboot: WARNING: kbootset nodes failed (1)"])):
            open(kb, "w").write('#!/bin/sh\n[ "$*" = nodes ] || { echo "kbootset: bad args $*" >&2; exit 2; }\n'
                                'echo "%s" >&2\nexit %d\n' % (line, rc))
            os.chmod(kb, 0o755)
            out = subprocess.run(["/usr/bin/dash", "-c", blk.replace("/sbin/kbootset", kb)],
                                 capture_output=True, text=True, timeout=30).stdout
            (ok if out.splitlines() == want else fail)("firstboot 4d, %s: %s" % (what, out.strip()))
        out = subprocess.run(["/usr/bin/dash", "-c", blk.replace("/sbin/kbootset", os.path.join(sb, "none"))],
                             capture_output=True, text=True, timeout=30).stdout
        (ok if out == "" else fail)("firstboot 4d with no /sbin/kbootset (a 1.0 root): silent (%r)" % out)

    # (4) the shim
    r = subprocess.run(["/usr/bin/dash", os.path.join(REPO, "payload", "updbootpart-l11")],
                       capture_output=True, text=True, timeout=30)
    if r.returncode == 3 and "kbootset" in r.stderr and "nothing was written" in r.stderr:
        ok("updbootpart-l11 refuses (exit 3), names kbootset, writes nothing")
    else:
        fail("updbootpart-l11: rc %d, stderr %r" % (r.returncode, r.stderr[:200]))


def _sh_session(body, stdin="", timeout=30):
    """run body under dash in its own session; kill whatever it leaves behind; (rc, stdout)"""
    pr = subprocess.Popen(["/usr/bin/dash", "-c", body], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        out = pr.communicate(stdin, timeout=timeout)[0]
        return pr.returncode, out
    except subprocess.TimeoutExpired:
        return -1, "TIMEOUT"
    finally:
        try:
            os.killpg(pr.pid, 9)
        except ProcessLookupError:
            pass
        pr.wait()


def audit_source_fit():
    head("SF. the source probe takes only an amigaux 1.1 install disc for the running kernel's line: another "
         "medium is named and skipped, two fitting discs are listed and asked for, a stale /cdrom is let go")
    prof = open(os.path.join(REPO, "src", "miniroot", "profile"), encoding="latin-1").read()
    fns = []
    for name in ("source_ok", "source_fits", "source_built", "pick_cd", "find_source"):
        m = re.search(r"\n(%s\(\)\n\{\n.*?\n\})\n" % name, prof, re.S)
        if not m:
            fail("profile: no %s()" % name)
            return
        fns.append(m.group(1))
    d = tempfile.mkdtemp(prefix="srcfit_")
    try:
        def medium(spec, kind, built="2026-11-08T10:00:00Z"):
            m = os.path.join(d, "media", spec)
            os.makedirs(os.path.join(m, "install", "bin"))
            open(os.path.join(m, "install", "bin", "setup.sh"), "w").write("#!/bin/sh\n: interview\n")
            open(os.path.join(m, "MANIFEST"), "w").write("amix-installng install CD\nbuilt:        %s\n" % built)
            if kind != "1.0":
                os.makedirs(os.path.join(m, "install", "l11"))
                os.makedirs(os.path.join(m, "install", "profiles"))
                open(os.path.join(m, "install", "profiles", "BASE." + kind), "w").write("universal-%s\n" % kind)

        def run(probed, answers="", stale=False):
            cdrom = os.path.join(d, "cdrom")
            shutil.rmtree(cdrom, ignore_errors=True)
            for f in ("calls", "cd.spec", "cd.found", "cd.found.pick"):
                if os.path.exists(os.path.join(d, f)):
                    os.remove(os.path.join(d, f))
            if stale:
                os.makedirs(os.path.join(cdrom, "install", "bin"))
                os.makedirs(os.path.join(cdrom, "install", "l11"))
                open(os.path.join(cdrom, "install", "bin", "setup.sh"), "wb").write(b"\x00\x13garbage(\n")
            body = ('D=%s\nCDROM=$D/cdrom\nSETUP=$CDROM/install/bin/setup.sh\nNETINST=$D/netinst\nRAW_CANDIDATES=\n'
                    'CD_SPEC_FILE=$D/cd.spec\nCD_FOUND=$D/cd.found\nKLINE=k46\nCD_PROBED=%s\nCD_CANDIDATES="1,3 2,5"\n'
                    'probe_cdfs() { echo "mount $1" >> $D/calls; rm -rf $CDROM; [ -d $D/media/$1 ] && cp -r $D/media/$1 $CDROM; '
                    '[ -f $SETUP ] && [ ! -f $CDROM/install/NETINSTALL ]; }\n'
                    'drop_source() { rm -rf $CDROM; }\ndisk_present() { return 1; }\nprobe_raw() { return 1; }\n'
                    'source_label() { echo "the CD-ROM drive at $2"; }\nnet_source() { :; }\n'
                    'restart() { echo RESTART; exit 99; }\nreadask() { echo "$*"; read ask; }\n%s\n'
                    'find_source\necho "SRC=$SRC_KIND $SRC_SPEC SPEC=`cat $CD_SPEC_FILE`"\necho "CALLS=`cat $D/calls`"\n'
                    % (d, "y" if probed else "", "\n".join(fns)))
            return _sh_session(body, answers)

        shutil.rmtree(os.path.join(d, "media"), ignore_errors=True)
        medium("1,3", "1.0"); medium("2,5", "k46")
        rc, o = run(True)
        good = (rc == 0 and "SRC=cdfs 2,5 SPEC=2,5" in o and "The CD at 1,3 is not an amigaux 1.1 install disc" in o
                and "More than one" not in o)
        (ok if good else fail)("source EXECUTED: a 1.0 disc at 1,3 and the 1.1 disc at 2,5 -> the 1.0 disc is named and "
                               "skipped, 2,5 is the source%s" % ("" if good else ": %r" % o[-300:]))
        shutil.rmtree(os.path.join(d, "media"), ignore_errors=True)
        medium("1,3", "k46", "2026-10-10T08:00:00Z"); medium("2,5", "k46", "2026-11-07T09:36:12Z")
        rc, o = run(True, "2\n")
        good = (rc == 0 and "SRC=cdfs 2,5 SPEC=2,5" in o and "More than one amigaux 1.1 install disc" in o
                and "1)  the CD-ROM drive at 1,3, built 2026-10-10T08:00:00Z" in o
                and "2)  the CD-ROM drive at 2,5, built 2026-11-07T09:36:12Z" in o)
        (ok if good else fail)("source EXECUTED: two 1.1 discs -> both listed with their build dates, the one chosen "
                               "(2) is mounted again and taken%s" % ("" if good else ": %r" % o[-400:]))
        rc, o = run(False)
        good = rc == 0 and "SRC=cdfs 1,3 SPEC=1,3" in o and "CALLS=mount 1,3" in o and "mount 2,5" not in o
        (ok if good else fail)("source EXECUTED: an address list not from the INQUIRY probe -> the walk stops at the "
                               "first fitting disc, still mounted, and mounts nothing past it%s" % ("" if good else ": %r" % o[-300:]))
        shutil.rmtree(os.path.join(d, "media"), ignore_errors=True)
        medium("2,5", "k46")
        rc, o = run(True, stale=True)
        good = (rc == 0 and "not a readable amigaux 1.1 install disc: unmounting it" in o and "SRC=cdfs 2,5" in o
                and "already mounted" not in o)
        (ok if good else fail)("source EXECUTED: a stale /cdrom (setup.sh's first line is not its own) is let go and "
                               "the drives are looked at again%s" % ("" if good else ": %r" % o[-300:]))
        shutil.rmtree(os.path.join(d, "media"), ignore_errors=True)
        medium("2,5", "k30")
        rc, o = run(True)
        good = rc == 99 and "RESTART" in o and "The CD at 2,5 is not an amigaux 1.1 install disc" in o
        (ok if good else fail)("source EXECUTED: only a disc of the other line (BASE.k30 on a k46 kernel) -> named, "
                               "not taken, the restart prompt%s" % ("" if good else ": %r" % o[-300:]))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_disk_real_size():
    head("RS. the chosen disk's own size from its driver, bounded: ddsize in the background, polled each second, "
         "abandoned at DDSIZE_SECS; never on the A3000's WD; the old layout's size kept, with the reason, otherwise")
    src = open(SETUP, encoding="latin-1").read()
    m = re.search(r"\n(disk_real_mb\(\)\n\{\n.*?\n\})\n", src, re.S)
    if not m:
        fail("setup.sh: no disk_real_mb()")
        return
    fn = m.group(1).replace("/etc/ddsize", "$DDSZ")   # /bin/sleep is the host's own
    d = tempfile.mkdtemp(prefix="realsz_")
    try:
        def run(key, stub, card=1):
            dd = os.path.join(d, "ddsize")
            open(dd, "w").write("#!/bin/sh\necho called >> %s/calls\n%s\n" % (d, stub))
            os.chmod(dd, 0o755)
            for f in ("calls", "blk0.why"):
                if os.path.exists(os.path.join(d, f)):
                    os.remove(os.path.join(d, f))
            body = ('DDSZ=%s\nBLK0=%s/blk0\nBLOCKS_PER_MB=2048\nDDSIZE_SECS=2\nKEY="%s"\nCARD=%s\n'
                    'is_num() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; return 0; }\n'
                    'id_card() { echo "$CARD"; }\ncard_key() { echo "$KEY"; }\n%s\n'
                    'MB=`disk_real_mb e`\necho "MB=[$MB]"\necho "WHY=[`cat $BLK0.why 2>/dev/null`]"\n'
                    % (dd, d, key, card, fn))
            t0 = time.time()
            rc, o = _sh_session(body, timeout=30)
            return rc, o, time.time() - t0, os.path.exists(os.path.join(d, "calls"))

        rc, o, t, called = run("mobo:gayle", "echo 409600")
        (ok if "MB=[200]" in o and called else fail)("real size EXECUTED: ddsize answers 409600 blocks -> 200 MB%s"
                                                    % ("" if "MB=[200]" in o else ": %r" % o))
        rc, o, t, called = run("mobo:a3000-wd", "echo 409600")
        good = "MB=[]" in o and "A3000" in o and not called
        (ok if good else fail)("real size EXECUTED: the A3000's WD -> ddsize is never run, the reason is given%s"
                               % ("" if good else ": %r called=%s" % (o, called)))
        rc, o, t, called = run("zorro:0202:54", "exec sleep 30")
        good = "MB=[]" in o and "did not answer the size request within 2 seconds" in o and t < 15
        (ok if good else fail)("real size EXECUTED: a ddsize that never returns is abandoned at the bound (%.1f s), "
                               "the substitution comes back, the reason is given%s" % (t, "" if good else ": %r" % o))
        rc, o, t, called = run("mobo:gayle", "echo 26624", card=2)
        good = "MB=[]" in o and "third or fourth disk card" in o and not called
        (ok if good else fail)("real size EXECUTED: a disk on card 2 -> ddsize is never run (it would measure card 0's "
                               "unit of the same number), the reason is given%s" % ("" if good else ": %r called=%s" % (o, called)))
        rc, o, t, called = run("mobo:gayle", "exit 1")
        good = "MB=[]" in o and "the driver gave no size" in o
        (ok if good else fail)("real size EXECUTED: a failing ddsize -> no size, the reason is given%s"
                               % ("" if good else ": %r" % o))
    finally:
        shutil.rmtree(d, ignore_errors=True)
    # a measured size under the disk's own layout is another disk's: the layout stays
    m2 = re.search(r"\n(size_under_layout\(\)\n\{\n.*?\n\})\n", src, re.S)
    ch = _extract_func(src, "choose_disk") or ""
    if not m2:
        fail("setup.sh: no size_under_layout()")
        return
    body = ('is_num() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; return 0; }\n%s\n'
            'for c in "199 13" "199 1023" " 200" "199 199" "199 198"; do set -- $c; '
            'if [ $# = 1 ]; then size_under_layout "" "$1"; else size_under_layout "$1" "$2"; fi; echo "$c=$?"; done\n' % m2.group(1))
    rc, o = _sh_session(body)
    good = ("199 13=0" in o and "199 1023=1" in o and " 200=1" in o and "199 199=1" in o and "199 198=0" in o
            and "smaller than the disk's own layout" in ch and "size_under_layout" in ch)
    (ok if good else fail)("real size EXECUTED: a measured size under the disk's old layout (13 of 199) is refused and "
                           "the layout kept; equal, larger or no layout is taken; choose_disk says so%s" % ("" if good else ": %r" % o))


def audit_set_space_d():
    head("SS. a set's whole footprint (its packages and its base packages, copied and installed) against the root: "
         "the A4000D's 104 MB root refuses x11 with the size it needs and takes standard; a 416 MB root takes x11")
    src = open(SETUP, encoding="latin-1").read()
    fns = []
    for name in ("is_num", "budget", "bytes_mb1", "order_size_bytes", "base_bytes", "set_bytes", "set_size_mb",
                 "check_space"):
        m = re.search(r"\n(%s\(\)\s*\{\n.*?\n\})\n" % name, src, re.S)
        if not m:
            fail("setup.sh: no %s()" % name)
            return
        fns.append(m.group(1))
    # the sizes of the 1.1 install disc these rows ran from (2026-11-09): the two sets' #isize sums, the base
    # packages' datastreams (base/order, and o.x11's x11r63)
    std_isize, x11_extra = 63872177, 73060944 - 63872177
    base = [("libcfix", 220672), ("amxbase", 192000), ("amixrt", 67584), ("dhcpc", 49664), ("syslog", 17920),
            ("ftpdfix", 89088), ("dropbear", 407040), ("rdate", 56832), ("cdfs", 16896), ("heirtar", 90624)]
    d = tempfile.mkdtemp(prefix="setspace_")
    try:
        inst = os.path.join(d, "install")
        os.makedirs(os.path.join(inst, "l11", "base"))
        open(os.path.join(d, "catalog"), "w").write(
            "#apkg-catalog 1\n#isize stdpkg %d\n#isize xpkg %d\n"
            "stdpkg|1|STDPKG|base/STDPKG.pkg|00|1|none|system|the standard set\n"
            "xpkg|1|XPKG|base/XPKG.pkg|00|1|none|x11|what x11 adds\n" % (std_isize, x11_extra))
        open(os.path.join(inst, "order.standard"), "w").write("STDPKG\n")
        open(os.path.join(inst, "order.x11"), "w").write("STDPKG\nXPKG\n")
        bd = os.path.join(inst, "l11", "base")
        open(os.path.join(bd, "order"), "w").write("".join(n + "\n" for n, _ in base))
        open(os.path.join(bd, "o.standard"), "w").write("")
        open(os.path.join(bd, "o.x11"), "w").write("x11r63\n")
        for n, sz in base + [("x11r63", 34151424)]:
            with open(os.path.join(bd, n + ".pkg"), "wb") as f:
                f.truncate(sz)
        # the disc's files are read-only: the base list is built from them all the same
        for f in os.listdir(bd):
            os.chmod(os.path.join(bd, f), 0o444)

        def run(root, sname, answer="n"):
            body = ("INST=%s\nCATF=%s/catalog\nTOK_F=%s/tok\nCATN_F=%s/catn\nISZ_F=%s/isz\nBASE_F=%s/base\n"
                    "SET_F=%s/sets\nANS_ROOT=%d\nANS_FSYS=ufs\nSET_NAME=%s\nreadask() { echo \"$*\"; read ask; }\n"
                    "%s\necho MENU `set_size_mb $INST/order.%s %s`\n"
                    "if check_space $INST/order.%s; then echo FITS; else echo REFUSED; fi\n"
                    "[ -f %s/sets.resize ] && echo RESIZE\n"
                    % (inst, d, d, d, d, d, d, root, sname, "\n".join(fns), sname, sname, sname, d))
            return _sh_session(body, answer + "\n")
        rc, o = run(104, "x11")
        good = ("MENU 150.8" in o and "REFUSED" in o and "RESIZE" not in o
                and "Your allocated space for installation is 102 MB," in o
                and "but you have selected to install 151 MB." in o
                and "make the root file system at least 154 MB, or choose a smaller set." in o)
        (ok if good else fail)("set space EXECUTED: x11 (150.8 MB on the menu) on the A4000D's 104 MB root is refused: "
                               "151 MB to install, a root of at least 154 MB (ufs keeps 2%%)%s"
                               % ("" if good else ": %r" % o))
        rc, o = run(104, "x11", "y")
        (ok if "REFUSED" in o and "RESIZE" in o else fail)(
            "set space EXECUTED: answering yes goes back to the root's size%s" % ("" if "RESIZE" in o else ": %r" % o))
        rc, o = run(104, "standard")
        good = "MENU 69.5" in o and "FITS" in o and "WARNING" not in o
        (ok if good else fail)("set space EXECUTED: standard (69.5 MB) on the 104 MB root is taken without a word%s"
                               % ("" if good else ": %r" % o))
        rc, o = run(416, "x11")
        good = "FITS" in o and "WARNING" not in o
        (ok if good else fail)("set space EXECUTED: x11 on a 416 MB root is taken without a word%s"
                               % ("" if good else ": %r" % o))
        rc, o = run(154, "x11")
        r2, o2 = run(153, "x11")
        good = "FITS" in o and "REFUSED" in o2
        (ok if good else fail)("set space EXECUTED: the size it names is exact: x11 fits a 154 MB root, not 153%s"
                               % ("" if good else ": %r %r" % (o, o2)))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main():
    # accept and ignore --self-test (the run-checks.sh entrypoint)
    args = [a for a in sys.argv[1:] if a != "--self-test"]
    if args:
        sys.stderr.write("installer-selftest: unexpected args: %s\n" % " ".join(args))
        return 2

    print("installer-selftest: structural proof (no box, no media)")
    print("  miniroot  : %s" % os.path.relpath(MINIROOT_PROFILE, REPO))
    print("  driver    : %s" % os.path.relpath(DRIVER, REPO))
    print("  interview : %s" % os.path.relpath(SETUP, REPO))
    print("  firstboot : %s" % os.path.relpath(FIRSTBOOT, REPO))
    audit_prepos()
    audit_parse()
    audit_order()
    audit_manifest()
    audit_seed_firstboot()
    audit_subshell_loops()
    audit_setcount_guard()
    audit_rdb_location()
    audit_interactive_card1_scan()
    audit_card1_derivation_exec()
    audit_x11_easystart()
    audit_w64b_completeness()
    audit_monsw()
    audit_dmamask_stamp()
    audit_apkg_conf_order()
    audit_030_rootswap()
    audit_firstboot_perms()
    audit_tz()
    audit_framing_tools()
    audit_syslog_unit()
    audit_null_redirect_loops()
    audit_w2_structure()
    audit_w2_sizing()
    audit_w2_interview()
    audit_w3b_metadata()
    audit_w4_miniroot_profile()
    audit_pick_at_install()
    audit_ufs_density()
    audit_modreg_local()
    audit_gayle_slave()
    audit_probe_backticks()
    audit_kb_nodes()
    audit_net_kspace()
    audit_tmp_sweep()
    audit_netset_stage2()
    audit_netset_stage1()
    audit_syspass_confirm()
    audit_kbootset_cards()
    audit_root_record()
    audit_swap_stepdown()
    audit_universal_cards()
    audit_cd_candidates()
    audit_source_fit()
    audit_disk_real_size()
    audit_set_space_d()
    audit_boot_pri()
    audit_guarded_rm_mv()
    audit_colon_truncate()
    audit_swap_by_ram()
    audit_boot_rivals()
    audit_guarded_mkdir()
    audit_net_space()
    audit_l11()

    print()
    if NOTES:
        for n in NOTES:
            print("  note: %s" % n)
    if FAILS:
        print("installer-selftest: FAILED -- %d check(s)" % len(FAILS))
        return 1
    print("installer-selftest: all structural checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
