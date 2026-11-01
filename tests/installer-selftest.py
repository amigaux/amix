#!/usr/bin/env python3
#
# installer-selftest.py -- structural proof of the installer driver + payload,
# host-side, no box, no media, no proprietary inputs. This is the W5.3 evidence
# that the artifacts are "complete, gated, and structurally proven"; the
# end-to-end on-box run is W5.4.
#
# It proves TWENTY things, each fail-closed (M added in W6-RAW.1, N in W6-RAW.2b,
# O in W6-I, P in METAL-FIX.4, Q + R in P5.4-FT, S in W1, T with the W1 bench
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
#      runs on a THIN miniroot that lacks basename/sed/touch/date (W5.4c proved
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
#      (W5.4d: the pkgadd loop's `npkgs` and the verify loop's `vok`/`vfails`
#      reverted to zero -> "installed 0 package(s)" and a false-firing arm guard).
#      This audit flags any redirect-fed loop whose body assigns a variable that is
#      referenced after the loop, and passes the temp-file idiom that survives it.
#      Negative fixtures (the exact W5.4d pattern) prove it fires; positive controls
#      (the temp-file idiom, a non-redirected loop) prove it does not over-fire.
#   I. PRE-POSIX `set --` COUNTING GUARD. The subshell-safe count (H) tallies a temp
#      file after the loop, but `set -- `cat FILE`; $#` is itself a trap: on the
#      miniroot sh an EMPTY `set --` is a no-op on $@ (confirmed on-box), so an empty
#      file returns a STALE count (W5.4e-run-1: the empty vfails "counted" the vok 3
#      and the verify false-failed). This flags any `set -- `cmd`` count not
#      `[ -s ]`-guarded; a negative fixture fires, the guarded idiom passes.
#   J. FIRST-BOOT INIT WIRING (W5.4f). The armed payload only runs if the target
#      init invokes it; the STOCK init does not (cold boot #1 fell into the stock
#      sysinit dialog). This audits that install.sh's arm step (a) WRITES
#      /etc/rc2.d/S16firstboot -- a NEW, driver-written, non-package file that runs
#      firstboot.sh iff PENDING exists -- and (b) DISARMS the stock dialog
#      (`chmod -x /usr/amiga/bin/system.setup`, the stock's own once-only lever).
#      A DRIFT-LOCK extracts the driver's emit_firstboot_hook and re-runs it,
#      proving it reproduces the tracked payload/firstboot/S16firstboot template
#      byte-for-byte; the hook is pre-POSIX + parses + references only
#      target-present tools; and firstboot.sh removes PENDING (once-only).
#   K. W6.4b INSTALLER COMPLETENESS. The driver (a) runs the CD-resident static
#      contents-fsck over the freshly built <root>/var/sadm/install/contents AFTER
#      the pkgadd loop and BEFORE arming first-boot, FAIL CLOSED (any non-zero ->
#      `die`, no `|| true`-style softening, CHECK-ONLY / never `-r`); and (b) WRITES
#      /etc/apkg.conf on the target with the live-repo line, on the miniroot
#      (identity-independent -> not first-boot), via echo + redirection only. A
#      negative fixture proves the fail-open (`contents-fsck ... || true`) is caught.
#   L. W6.4c REPO-HOST BAKING (zero-touch apkg). A fresh install cannot resolve the
#      apkg repo's hostname (no DNS on the bench LAN; firstboot section 5 baked only
#      the box's OWN nodename), so W6.4b's `apkg update` worked only after a MANUAL
#      /etc/inet/hosts edit. W6.4c bakes the repo host too: the profile carries
#      FB_REPO_HOST + FB_REPO_IP (paired); install.sh passes them through
#      firstboot.conf; firstboot.sh appends "<ip> <host>" to /etc/inet/hosts at
#      identity-bake time -- guarded (skip-but-log when either is empty: a repo-less
#      profile is legal), duplicate-safe (strip any prior host line, then append
#      one), and NEVER touching network-config. This audit FIRES on a missing
#      firstboot append whenever a profile carries the vars; a negative fixture
#      proves the append check fires and the bench profile's canonical values are
#      pinned.
#   Q. P5.4-FT /stand FRAMING TOOLS. updbootpart's reframe pipeline (gate 5a)
#      fails closed without /stand/boot1.boot + an executable local
#      /stand/makeiblk; on M-RUN4b the KERN handoff on a fresh metal base-8
#      install died "framed image is empty" until the pair was ferried by hand.
#      This audits that the driver LAYS BOTH DOWN (cp from /install/stand,
#      chmod 0644/0755) after the base transplant, that the media staging
#      fingerprint-pins them (boot1.boot 41892/1024 -- the 2.1 original the 2.1c
#      patch never touched; makeiblk 58483/14924 -- the 2.1c build the goldens
#      run and the metal reframe was proven with), that every framing source
#      updbootpart gates on is driver-guaranteed, and (when a staged tree is
#      present) that the staged bytes match the pins. A negative fixture proves
#      the laydown check fires.
#   R. P5.4 SYSLOG UNIT. A base-8 install has core's syslogd BINARY but no unit
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
#   S. W1 DRIVER PLUMBING. The interview (W2) needs somewhere to land its
#      answers, so W1 turns the driver's remaining hardcodes into profile KEYS
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
#      FB_DNS1/FB_DNS2 are RECORDED and applied NOWHERE (W5 owns application);
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
#      TWO defects -- the P5.4-FT syslog unit laid down one of eight /var/log
#      stubs and then hard-stopped every install, and W1's lost+found preseed was
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

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, os.pardir))
sys.path.insert(0, os.path.join(HERE, "lib"))
from sumr import bsd_sum_r                                        # noqa: E402

DRIVER = os.path.join(REPO, "src", "installer", "install.sh")
SETUP = os.path.join(REPO, "src", "installer", "setup.sh")
# the 1.1 layout's half of the driver, sourced by install.sh (INSTALL_LAYOUT=1.1)
L11 = os.path.join(REPO, "src", "installer", "l11.sh")
# W4: the miniroot's own /etc/profile -- the install script the console login
# shell sources. It is the STRICTEST of the three on-box scripts (it runs with
# nothing mounted), so it takes the same audits under the same allowlist.
MINIROOT_PROFILE = os.path.join(REPO, "src", "miniroot", "profile")
FIRSTBOOT = os.path.join(REPO, "payload", "firstboot", "firstboot.sh")
HOOK = os.path.join(REPO, "payload", "firstboot", "S16firstboot")
UPDBOOTPART = os.path.join(REPO, "payload", "updbootpart")
ZENHOOK = os.path.join(REPO, "payload", "S99zen")
PROTO = os.path.join(REPO, "miniroot", "miniroot.proto")
PROFILES_DIR = os.path.join(REPO, "profiles")
ISO_BUILDER = os.path.join(HERE, "build-install-iso.sh")
EXTRACT_21C = os.path.join(HERE, "extract-21c-payload.sh")
STAGE_DIR = os.environ.get("INSTALLSEL_STAGE",
                           os.path.join(REPO, "work", "install-tree"))
RAW_BUILDER = os.path.join(HERE, "build-raw-source.sh")
RAW_PROFILE = os.path.join(PROFILES_DIR, "bench-a3000-a4091-raw.profile")
METAL_RAW_PROFILE = os.path.join(PROFILES_DIR, "metal-a4000-z3660-raw.profile")
WRITE_BOOTCHAIN = os.path.join(HERE, "write-bootchain.py")
GEN_ORDER = os.path.join(HERE, "gen-install-order.py")
MKROOT = os.path.join(HERE, "mkroot.sh")
# amix userland/pkgtools at the set's revision (tools/build-l11-inputs.sh): the
# authored repo metadata build-install-iso.sh reads (deps.conf, sets.conf, cats.conf)
PT_REPO = os.path.join(REPO, "work", "l11", "pkgtools", "tools", "repo")
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
    # audit misreading the WORD inside a quoted stock string. W5 made that
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
    # the W6.2 six-package selection -- NOT the shipped base set (that grew to
    # EIGHT at W6.4b and is checked immediately below). Kept because it isolates
    # the cdfs edge: cdfs joined at W6.2 so an installed box can mount CDs, and
    # cdfs->core must keep it anywhere after core with no APKG/APKGENG present.
    r = run_order(["core", "bsd", "net", "text", "sysadm", "cdfs"])
    seq = [l for l in r.stdout.splitlines() if l and not l.startswith("#")]
    if r.returncode == 0 and seq and seq[0] == "core" and \
            seq == ["core", "bsd", "net", "text", "sysadm", "cdfs"]:
        ok("W6.2 six-package selection -> core first (cdfs after core): %s"
           % " ".join(seq))
    else:
        fail("W6.2 six-package order wrong (rc=%d): %r" % (r.returncode, seq))
    # W6.4b GROWN base set: EIGHT packages -- the package client (APKGENG engine +
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
    is extracted too (the W1 size-override validation calls it), so the harness
    stays a transcription of the driver rather than a stand-in for it. The
    override keys come in from the ENVIRONMENT, exactly as sourcing a profile
    would set them -- unset means "stock default", the pre-W1 behaviour."""
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


def audit_presets():
    """P. THE CANONICAL Z3660 PRESET TEMPLATES AND THE CROSS-REPO SCSI GATE.

    ★ WHY THIS AUDIT EXISTS. "The disk is at SCSI unit 6" is ONE FACT WRITTEN IN TWO
    REPOS: this tree states it as a profile's TARGET_SCSI_ID, and the Z3660 firmware
    states it as `scsiN <slot>` in a preset on the card's SD. Nothing checked that the
    two agreed, and on 2026-09-08 a hand-written preset said `scsi0` while every profile
    here said 6 -- against kernels rootdev-stamped for unit 6 (minor = slice<<4 |
    (card<<3 | unit): 0x16 -> card 0 unit 6, 0x1E -> card 1 unit 6). The firmware
    presented the disk at unit 0, the kernel looked for unit 6, and root could not be
    mounted. The templates below are the canonical shapes; this gate is the agreement.
    """
    head("P. canonical Z3660 preset templates + the cross-repo SCSI-unit gate")
    pdir = os.path.join(REPO, "profiles", "presets")
    if not os.path.isdir(pdir):
        fail("profiles/presets/ is missing -- the canonical preset templates are gone")
        return
    templates = sorted(f for f in os.listdir(pdir) if f.endswith(".preset"))
    if not templates:
        fail("no .preset templates in profiles/presets/")
        return
    ok("found %d canonical preset template(s): %s" % (len(templates), " ".join(templates)))

    for t in templates:
        txt = open(os.path.join(pdir, t), encoding="utf-8").read()
        # 1. every template must name the profile it pairs with
        m = re.search(r'(?m)^#profile:\s*(\S+)\s*$', txt)
        if not m:
            fail("%s carries no `#profile:` line -- nothing says which profile it pairs with" % t)
            continue
        prof = m.group(1)
        ppath = os.path.join(REPO, "profiles", prof + ".profile")
        if not os.path.isfile(ppath):
            fail("%s names profile %r, which does not exist" % (t, prof))
            continue
        ptxt = open(ppath, encoding="utf-8").read()
        pm = re.search(r'(?m)^TARGET_SCSI_ID=(\S+)\s*$', ptxt)
        if not pm:
            fail("%s: profile %s declares no TARGET_SCSI_ID" % (t, prof))
            continue
        want = pm.group(1)

        # 2. ★ THE GATE: the preset must map the disk at exactly that SCSI unit,
        #    and must NOT map it at any other.
        mapped = [(n, v) for n, v in re.findall(r'(?m)^scsi([0-6])\s+(\S+)\s*$', txt)
                  if v != "-1"]
        if len(mapped) != 1:
            fail("%s maps %d SCSI units (%s) -- exactly one disk is expected"
                 % (t, len(mapped), ", ".join("scsi" + n for n, _ in mapped) or "none"))
        elif mapped[0][0] != want:
            fail("★ CROSS-REPO DISAGREEMENT: %s maps the disk at scsi%s but profile %s "
                 "declares TARGET_SCSI_ID=%s -- a kernel stamped for unit %s cannot mount "
                 "a disk presented at unit %s"
                 % (t, mapped[0][0], prof, want, want, mapped[0][0]))
        else:
            ok("%s maps the disk at scsi%s == %s's TARGET_SCSI_ID (the fact agrees "
               "across both repos)" % (t, want, prof))

        # 3. kickstart 0 is a RESERVED VALUE ("use the motherboard ROM"), never a slot.
        km = re.search(r'(?m)^kickstart\s+(\S+)\s*$', txt)
        if km and km.group(1) == "0":
            fail("%s sets `kickstart 0`, which selects the machine's OWN motherboard ROM "
                 "-- it is a reserved value, not a free table slot, and a 3.2.x mobo ROM "
                 "carries no Unix bootstrap" % t)
        else:
            ok("%s does not use the reserved `kickstart 0`" % t)

        # 4. the validated clock rows: real 060 -> 80, emulated -> 50. Anything else
        #    is a row this card has not passed on (100 fails CIA; 50 blackscreens the 060).
        bm = re.search(r'(?m)^bootmode\s+(\S+)\s*$', txt)
        cm = re.search(r'(?m)^cpufreq\s+(\S+)\s*$', txt)
        if bm and cm:
            want_f = "80" if bm.group(1) == "CPU" else "50"
            if cm.group(1) == want_f:
                ok("%s: bootmode %s with cpufreq %s (the validated clock row)"
                   % (t, bm.group(1), cm.group(1)))
            else:
                fail("%s: bootmode %s with cpufreq %s -- the validated row is %s "
                     "(real 060 @50 = black screen; emulated @100 = CIAB Timer A no ICR)"
                     % (t, bm.group(1), cm.group(1), want_f))
        # (checks 1-4 above are per-template; the vfstab-id check below is per-profile
        #  and runs once, on the profile the template names)
        if t == templates[0]:
            drv = open(os.path.join(REPO, "src", "installer", "install.sh"), encoding="utf-8").read()
            # UNSET MUST BE A NO-OP. The whole safety of adding a destination-controller
            # key is that every existing profile, which omits it, emits the same byte it
            # always did -- so the fallback form is the property, not the key.
            if re.search(r'FB_SCSI_ID=\$\{TARGET_VFSTAB_SCSI_ID:-\$ID\}', drv):
                ok("install.sh emits FB_SCSI_ID as ${TARGET_VFSTAB_SCSI_ID:-$ID} -- unset is "
                   "byte-identical to TARGET_SCSI_ID, so every existing profile is unchanged")
            else:
                fail("install.sh does not emit FB_SCSI_ID with the TARGET_VFSTAB_SCSI_ID "
                     "fallback -- either the key is gone or unset is no longer a no-op")
            vm = re.search(r'(?m)^TARGET_VFSTAB_SCSI_ID=(\S*)\s*$', ptxt)
            if vm and vm.group(1):
                v = vm.group(1)
                if re.match(r'^[0-9a-fA-F]$', v):
                    ok("%s sets TARGET_VFSTAB_SCSI_ID=%s -- ONE hex digit "
                       "(minor = slice<<4 | (card<<3 | unit); card 1 unit 6 is 'e', never '14')"
                       % (prof, v))
                else:
                    fail("%s sets TARGET_VFSTAB_SCSI_ID=%r, which is not one hex digit -- the "
                         "controller field is a nibble" % (prof, v))

        # 5. placeholders must still be placeholders -- a template with a real card's
        #    slot baked in will be copied onto a card where it is wrong.
        for ph in ("@HDF_SLOT@", "@KICKSTART@"):
            if ph in txt:
                ok("%s keeps %s a placeholder (per-card, must be filled from that card's cfg)" % (t, ph))
            else:
                fail("%s has lost the %s placeholder -- a baked-in per-card value will be "
                     "wrong on the next card" % (t, ph))


def audit_arith():
    head("E. partition arithmetic: driver sh == mkroot.sh layout")
    try:
        harness = extract_plan_harness()
    except StopIteration:
        fail("could not extract plan_partitions from the driver")
        return
    hp = workpath("plan.sh")
    with open(hp, "w") as fh:
        fh.write(harness)
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    have_rdbtool = subprocess.call(["sh", "-c", "command -v rdbtool >/dev/null"]) == 0
    if not have_rdbtool:
        skip("rdbtool absent -- the driver-vs-mkroot REAL layout cross-check is "
             "skipped (not a pass); running the sh arithmetic for consistency only")

    sizes = [50, 100, 120, 121, 200, 300]
    tmpd = os.path.join(workdir(), "arith")
    os.makedirs(tmpd, exist_ok=True)
    all_matched = True
    for mb in sizes:
        r = subprocess.run([sh, hp, str(mb)], capture_output=True, text=True)
        if r.returncode != 0:
            fail("driver plan_partitions rc=%d for %dMB: %s"
                 % (r.returncode, mb, r.stderr.strip()))
            all_matched = False
            continue
        vals = r.stdout.split()
        if len(vals) != 6:
            fail("driver plan output malformed for %dMB: %r" % (mb, r.stdout))
            all_matched = False
            continue
        d_root_off, d_swap_off, d_boot_off, d_rootlen, d_swaplen, d_bootlen = map(int, vals)
        if not have_rdbtool:
            continue
        out = os.path.join(tmpd, "mk%d.img" % mb)
        rr = subprocess.run(["bash", MKROOT, "--no-mkfs", "--size-mb", str(mb),
                             "--out", out], capture_output=True, text=True)
        lay = out + ".layout.json"
        if rr.returncode != 0 or not os.path.isfile(lay):
            fail("mkroot.sh failed for %dMB: %s" % (mb, rr.stderr.strip()[-200:]))
            all_matched = False
            continue
        L = json.load(open(lay))
        sl = dict((s["role"], s) for s in L["slices"])
        m_root_off = sl["root"]["offset_bytes"] // 512
        m_swap_off = sl["swap"]["offset_bytes"] // 512
        m_boot_off = sl["boot"]["offset_bytes"] // 512
        m_rootlen = sl["root"]["size_bytes"] // 512
        m_swaplen = sl["swap"]["size_bytes"] // 512
        m_bootlen = sl["boot"]["size_bytes"] // 512
        match = (d_root_off == m_root_off and d_swap_off == m_swap_off and
                 d_boot_off == m_boot_off and d_rootlen == m_rootlen and
                 d_swaplen == m_swaplen and d_bootlen == m_bootlen)
        if match:
            ok("%3dMB: driver == mkroot  root@%d(%d) swap@%d(%d) boot@%d(%d) blocks"
               % (mb, m_root_off, m_rootlen, m_swap_off, m_swaplen, m_boot_off, m_bootlen))
        else:
            all_matched = False
            fail("%dMB MISMATCH driver(root@%d/%d swap@%d/%d boot@%d/%d) != "
                 "mkroot(root@%d/%d swap@%d/%d boot@%d/%d)"
                 % (mb, d_root_off, d_rootlen, d_swap_off, d_swaplen, d_boot_off, d_bootlen,
                    m_root_off, m_rootlen, m_swap_off, m_swaplen, m_boot_off, m_bootlen))
    if not have_rdbtool and all_matched:
        ok("driver plan_partitions ran clean for %d sizes (mkroot cross-check skipped)"
           % len(sizes))

    # --- W1: TARGET_ROOT_MB / TARGET_SWAP_MB overrides ----------------------
    # The two sizes the stock installer ASKED for become optional profile keys.
    # Three properties, all fail-closed:
    #   1. UNSET == the pre-W1 arithmetic, byte for byte (proven by re-running the
    #      same harness with the vars explicitly empty and diffing the output);
    #   2. a valid override actually MOVES the layout, stays cylinder-aligned, and
    #      keeps root+swap+boot inside the disk;
    #   3. every stock FLOOR/CEILING refuses: root < MINROOT(16), root > ROOTMAX
    #      (would leave < MINSWAP), swap < MINSWAP(5), swap > what remains, and a
    #      non-numeric value.
    def plan(mb, env=None):
        e = dict(os.environ)
        e["TARGET_ROOT_MB"] = ""
        e["TARGET_SWAP_MB"] = ""
        e["TARGET_BOOT_MB"] = ""
        if env:
            e.update(env)
        return subprocess.run([sh, hp, str(mb)], capture_output=True, text=True, env=e)

    base = plan(300)
    empty = plan(300, {"TARGET_ROOT_MB": "", "TARGET_SWAP_MB": "", "TARGET_BOOT_MB": ""})
    if base.returncode == 0 and base.stdout == empty.stdout:
        ok("override keys UNSET/empty reproduce the stock default layout exactly "
           "(300MB -> %s)" % base.stdout.strip())
    else:
        fail("empty TARGET_ROOT_MB/TARGET_SWAP_MB changed the default layout "
             "(%r vs %r)" % (base.stdout, empty.stdout))

    ovr = plan(300, {"TARGET_ROOT_MB": "100", "TARGET_SWAP_MB": "40"})
    if ovr.returncode == 0:
        v = [int(x) for x in ovr.stdout.split()]
        root_off, swap_off, boot_off, rootlen, swaplen, bootlen = v
        secs = 64
        checks = (rootlen == 100 * 2048 and swaplen == 40 * 2048
                  and rootlen % secs == 0 and swaplen % secs == 0
                  and swap_off == root_off + rootlen
                  and boot_off == swap_off + swaplen
                  and boot_off + bootlen <= 300 * 2048)
        if checks:
            ok("valid override honoured on a 300MB disk: root 100MB swap 40MB, "
               "cylinder-aligned, slices contiguous and inside the disk")
        else:
            fail("override layout wrong for root=100/swap=40 on 300MB: %r" % v)
    else:
        fail("valid override rc=%d: %s" % (ovr.returncode, ovr.stderr.strip()))

    # --- TARGET_BOOT_MB: the boot slice becomes a profile key ----------------
    # Stock never ASKED for this size, it STATED it, so there is no stock prompt
    # whose bounds to mirror -- what must hold is that the slice actually moves,
    # that the megabytes come out of ROOT and nothing else, and that the driver
    # and mkroot.sh still lay down the SAME disk. The last one is the point: the
    # driver plans on the box and mkroot plans on the host, and a boot-slice size
    # that only one of them knows about produces a target whose slice map the
    # other does not believe in -- silently, because both halves stay internally
    # consistent.
    b_base = plan(300)
    b_ovr = plan(300, {"TARGET_BOOT_MB": "12"})   # r6e: default 10, override 12
    if b_base.returncode == 0 and b_ovr.returncode == 0:
        v0 = [int(x) for x in b_base.stdout.split()]
        v4 = [int(x) for x in b_ovr.stdout.split()]
        _, _, _, root0, swap0, boot0 = v0
        root_off4, swap_off4, boot_off4, root4, swap4, boot4 = v4
        checks = (boot4 == 12 * 2048 and boot0 == 10 * 2048
                  and root4 == root0 - 2 * 2048          # the 2 MB comes out of root
                  and swap4 == swap0                     # and NOT out of swap
                  and swap_off4 == root_off4 + root4
                  and boot_off4 == swap_off4 + swap4
                  and boot_off4 + boot4 <= 300 * 2048
                  and root4 % 64 == 0 and boot4 % 64 == 0)
        if checks:
            ok("TARGET_BOOT_MB=12 honoured on a 300MB disk: boot 10->12MB, the 2MB "
               "comes out of ROOT (%d->%d blocks), swap unchanged, slices "
               "contiguous, cylinder-aligned and inside the disk" % (root0, root4))
        else:
            fail("TARGET_BOOT_MB=12 layout wrong on 300MB: default=%r override=%r" % (v0, v4))
    else:
        fail("TARGET_BOOT_MB plan failed: base rc=%d ovr rc=%d (%s)"
             % (b_base.returncode, b_ovr.returncode, b_ovr.stderr.strip()))

    # driver == mkroot with the override live, on a real RDB
    if have_rdbtool:
        mb = 300
        r = plan(mb, {"TARGET_BOOT_MB": "4"})
        out = os.path.join(tmpd, "mkboot%d.img" % mb)
        rr = subprocess.run(["bash", MKROOT, "--no-mkfs", "--size-mb", str(mb),
                             "--boot-mb", "4", "--out", out],
                            capture_output=True, text=True)
        lay = out + ".layout.json"
        if r.returncode == 0 and rr.returncode == 0 and os.path.isfile(lay):
            d = [int(x) for x in r.stdout.split()]
            L = json.load(open(lay))
            sl = dict((x["role"], x) for x in L["slices"])
            m = [sl["root"]["offset_bytes"] // 512, sl["swap"]["offset_bytes"] // 512,
                 sl["boot"]["offset_bytes"] // 512, sl["root"]["size_bytes"] // 512,
                 sl["swap"]["size_bytes"] // 512, sl["boot"]["size_bytes"] // 512]
            if d == m:
                ok("%3dMB + TARGET_BOOT_MB=4: driver == mkroot --boot-mb 4  "
                   "root@%d(%d) swap@%d(%d) boot@%d(%d) blocks" % (mb, m[0], m[3], m[1], m[4], m[2], m[5]))
            else:
                fail("%dMB + boot=4 MISMATCH driver=%r != mkroot=%r" % (mb, d, m))
        else:
            fail("%dMB + boot=4 cross-check could not run (driver rc=%d, mkroot rc=%d)"
                 % (mb, r.returncode, rr.returncode))

    for name, mb, env, needle in [
        ("root below MINROOT", 300, {"TARGET_ROOT_MB": "8"}, "below the stock minimum root"),
        ("root above ROOTMAX", 300, {"TARGET_ROOT_MB": "295"}, "free for swap"),
        ("swap below MINSWAP", 300, {"TARGET_SWAP_MB": "2"}, "below the stock minimum swap"),
        ("swap above remaining", 300, {"TARGET_ROOT_MB": "250", "TARGET_SWAP_MB": "90"},
         "remaining after root"),
        ("non-numeric root", 300, {"TARGET_ROOT_MB": "lots"}, "is not a number"),
        ("non-numeric swap", 300, {"TARGET_SWAP_MB": "-5"}, "is not a number"),
        ("boot below MINBOOT", 300, {"TARGET_BOOT_MB": "1"}, "below the minimum boot partition"),
        ("non-numeric boot", 300, {"TARGET_BOOT_MB": "big"}, "is not a number"),
        ("boot bigger than the disk", 300, {"TARGET_BOOT_MB": "400"}, "disk too small for a"),
    ]:
        r = plan(mb, env)
        if r.returncode != 0 and needle in (r.stderr + r.stdout):
            ok("override refused: %-22s -> die (%s)" % (name, needle))
        else:
            fail("override NOT refused: %s (rc=%d, out=%r err=%r)"
                 % (name, r.returncode, r.stdout.strip(), r.stderr.strip()))

    # r6 (owner 2026-10-06): the 040/060 kernels link a 61440-sector (30 MB) swapfile, so on
    # INSTALL_CPU 040/060 30 MB is the swap DEFAULT and the FLOOR -- even below the 120 MB
    # BREAKPT, where the 030 line keeps the stock 18 MB.
    r30, r18 = plan(100, {"INSTALL_CPU": "060"}), plan(100, {"INSTALL_CPU": "030"})
    if r30.returncode == 0 and r18.returncode == 0:
        s30, s18 = int(r30.stdout.split()[4]), int(r18.stdout.split()[4])
        if s30 == 61440 and s18 == 18 * 2048:
            ok("100MB disk: swap default 30 MB (61440 blocks) on the 060 line, the stock 18 MB on the 030 line")
        else:
            fail("100MB swap defaults wrong: 060 %d blocks (want 61440), 030 %d (want %d)" % (s30, s18, 18 * 2048))
    else:
        fail("the 060/030 swap-default plans did not run (rc %d / %d)" % (r30.returncode, r18.returncode))
    for cpu, swap, want_ok in (("060", "18", False), ("040", "29", False), ("060", "30", True), ("030", "18", True)):
        r = plan(300, {"INSTALL_CPU": cpu, "TARGET_SWAP_MB": swap})
        if want_ok and r.returncode == 0:
            ok("INSTALL_CPU=%s TARGET_SWAP_MB=%s accepted" % (cpu, swap))
        elif not want_ok and r.returncode != 0 and "68040/68060" in r.stderr:
            ok("INSTALL_CPU=%s TARGET_SWAP_MB=%s refused, saying why" % (cpu, swap))
        else:
            fail("INSTALL_CPU=%s TARGET_SWAP_MB=%s: rc %d err %r" % (cpu, swap, r.returncode, r.stderr.strip()))


# ---------------------------------------------------------------------------
# F. seed steps + first-boot safety
# ---------------------------------------------------------------------------
def _mnttab_write(text):
    """Classify the seed's /etc/mnttab root-line write as 'overwrite' | 'append' |
    None. Operates on comment-stripped driver text (real commands only). `>>` is
    tested first because the `>` pattern would otherwise match the second `>` of an
    append. METAL-FIX.2: the write MUST be an OVERWRITE of the "/" root entry. The
    fs field is the RUNNING MINIROOT's own ($MINIROOT_FSTYPE -- s5 on the 030 line,
    ufs on the 040/060 line, derived from INSTALL_CPU), NOT the target's; a
    hardcoded literal or a $TARGET_ROOT_FSTYPE there is a defect (audit AA6)."""
    if re.search(r'echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>>\s*/etc/mnttab', text):
        return "append"
    if re.search(r'echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>\s*/etc/mnttab', text):
        return "overwrite"
    return None


# --- F/TZ: the colon form, now that the ZONE is a profile key (W1) -----------
# W6.3 REGRESSION GUARD, extended to the parametrized emission. The TIMEZONE line
# MUST use the SVR4 tzfile-pathname form `TZ=:<pathname>` (LEADING COLON): only
# the colon makes ctime(3)/tzset(3) read the tzfile; the colon-less
# `TZ=US/Eastern` is parsed as a POSIX rule string and BUS-ERRORs date/who -r/
# ls -l/cron/sac at 474D5400 on cold boot (cascading into rc2 `test: unknown
# operator S`). W1 makes the ZONE a key (FB_TZ) but deliberately NOT the colon --
# the colon is emitted by CODE so no profile, answers file or stripped quote can
# ever produce the broken form. So the audit demands exactly that shape:
#   * firstboot.sh emits `TZ=:$FB_TZ` (literal colon, then the variable);
#   * firstboot.sh DEFAULTS FB_TZ (an old firstboot.conf must not yield `TZ=:`);
#   * install.sh passes FB_TZ into firstboot.conf and STRIPS a leading colon off
#     the profile value (`TZ=::US/Eastern` is just as dead);
#   * every profile carries a zone-shaped FB_TZ (contains a '/').


def _fb_tz_emission(fb_code):
    """Classify firstboot.sh's TZ= emission on comment-stripped code:
    'param'  -- TZ=:$FB_TZ / TZ=:${FB_TZ}   (the required W1 shape)
    'literal'-- TZ=:<something/else>        (a hardcoded zone, pre-W1)
    'nocolon'-- TZ=<anything> with no colon  (the bus-error form)
    None     -- no TZ= assignment at all."""
    # Only an EMISSION counts, so the pattern is anchored on the `echo "TZ=` that
    # writes /etc/TIMEZONE. W5 made that precision necessary: this file now also
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
           "COLON emitted by code (W6.3 + W1)")
    elif kind == "literal":
        fail("firstboot.sh still HARDCODES the timezone zone -- W1 parametrizes it "
             "as FB_TZ (the literal made every profile's zone a no-op)")
    else:
        fail("firstboot.sh TIMEZONE must be `TZ=:$FB_TZ` (leading colon emitted by "
             "code) -- got %r; the colon-less form BUS-ERRORs date/who -r/ls -l at "
             "cold boot (W6.3)" % kind)
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
    # the whole point of the W6 public flavor: a profile that ARMS THE DIALOG
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

    # --- /etc/mnttab root line (METAL-FIX.2) ---------------------------------
    # The RUNNING miniroot ships no /etc/mnttab on FRESH media; pkgadd/apkg open()
    # it before installing and abort with "unable to open mount table (/etc/mnttab)"
    # (M-RUN froze exactly here). The seed must WRITE the "/" root line -- and
    # OVERWRITE (`>`), never append, so a stale/contaminated table (the reused-bench-
    # floppy trap that masked this for two waves) is REPLACED. get_mntinfo keys off
    # the SHORTEST mount point being exactly "/".
    mode = _mnttab_write(code)
    if mode == "overwrite":
        ok('seed writes /etc/mnttab root line `echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab` '
           "(OVERWRITE, replaces a stale/contaminated table; METAL-FIX.2)")
    elif mode == "append":
        fail("seed writes /etc/mnttab with `>>` (append) -- must be `>` (OVERWRITE) so a "
             "stale/contaminated table is replaced, not appended to (METAL-FIX.2)")
    else:
        fail('seed does not write the /etc/mnttab root line `/dev/root / $MINIROOT_FSTYPE '
             'rw 0` -- pkgadd/apkg abort with "unable to open mount table (/etc/mnttab)" '
             "on FRESH media (METAL-FIX.2); the fs field is the miniroot's own, not a literal")
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
    # absence, or this check is worthless (the exact METAL-FIX.2 regression).
    neg = re.sub(r'\n[^\n]*echo\s+"/dev/root / \$MINIROOT_FSTYPE rw 0"\s*>+\s*/etc/mnttab[^\n]*', "", code)
    if _mnttab_write(neg) is None:
        ok("negative fixture fires: a seed with no /etc/mnttab write is flagged absent")
    else:
        fail("negative fixture did NOT fire: a missing mnttab write was not caught")

    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    # NEVER write network-config: no redirection into it, and no tool naming it as
    # an ARGUMENT. W5 forced the distinction between a write and a MENTION: the
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
# idiom). runq is the W1 output-routing twin of run (it returns the rc instead of
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
# firstboot.sh runs on the FULL installed target (core+base transplanted), so the
# complete SVR4 userland is present. These are the tools it deliberately uses that
# the miniroot itself lacks -- documented, and NOT granted to install.sh.
FIRSTBOOT_EXTRA = {
    # the APPLY half (W1/W6.4c/W5): target tools the miniroot lacks
    "sed", "uname", "true", "grep", "ed", "domainname",
    # the DIALOG half (W5, `firstboot.sh --dialog`). Every one of these is here
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
    # Q-4.15 trap ii: re-register the installer-laid /stand/unix (040/060) in the core
    # package -- the stock pkgtools installf, a core member on every installed target
    "installf",
    # S3-31: a 1.1 disk's /stand/unix out of the core package -- APKGENG's heirloom
    # removef and pkgchk (/usr/apkg/bin), from the APKG set every target carries
    "removef", "pkgchk",
    # C4-1: the root's name as the running kernel numbers it (stat only, a core member;
    # updbootpart and bcheckrc use it the same way)
    "devnm",
    # S5-44 R2: step 4d's `kbootset nodes` (C2-4 §14), the kbootset package every 1.1 disk
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


def load_proto_tools():
    """Basenames of every file/symlink the tracked miniroot.proto carries. The
    allowlist is DERIVED here -- there is no second hardcoded copy of the list."""
    if not os.path.isfile(PROTO):
        return None
    tools = set()
    for line in open(PROTO, encoding="utf-8"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) < 6:
            continue
        if parts[0] in ("f", "l"):
            tools.add(os.path.basename(parts[5]))
    return tools


def _defined_funcs(text):
    return set(re.findall(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)', text))


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
    # emit_* functions echo whole target scripts in single quotes (P-3's S99zen
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


def _classify(word, funcnames, proto_tools, extras):
    """Return the offending token if `word` is not allowed, else None."""
    if word.startswith("/cdrom/"):
        return None
    if word.startswith("/"):
        base = word.rsplit("/", 1)[-1]
        return None if (base in proto_tools or base in extras) else word
    if word in SH_BUILTINS or word in SH_KEYWORDS:
        return None
    if word in funcnames or word in proto_tools or word in extras:
        return None
    return word


def tool_violations(text, proto_tools, extras):
    funcnames = _defined_funcs(text)
    bad = []
    for w in command_words(text):
        v = _classify(w, funcnames, proto_tools, extras)
        if v is not None:
            bad.append(v)
    return bad


def audit_tool_allowlist():
    head("G. miniroot-tool allowlist (every command is a builtin, a proto binary, or /cdrom)")
    proto_tools = load_proto_tools()
    if proto_tools is None:
        fail("miniroot.proto not found (%s) -- allowlist cannot be derived"
             % os.path.relpath(PROTO, REPO))
        return
    ok("derived %d tool names from miniroot.proto (no second hardcoded copy)"
       % len(proto_tools))

    dwords = list(command_words(read_sh(DRIVER)))
    swords = list(command_words(read_sh(SETUP)))
    fwords = list(command_words(read_sh(FIRSTBOOT)))
    mwords = list(command_words(read_sh(MINIROOT_PROFILE)))

    # NON-VACUITY: a parser that yields nothing would make this audit a vacuous
    # pass -- the very bug class it exists to catch. Require the known-present
    # commands to actually be extracted before trusting a clean result.
    need_d = {"cp", "dd", "expr", "msg", "die", "/etc/rdb"}
    miss_d = need_d - set(dwords)
    need_f = {"sed", "echo", "mv"}
    miss_f = need_f - set(fwords)
    # setup.sh is MEDIUM-resident but runs on the SAME thin miniroot, so it gets
    # the identical strict allowlist (no target-side extras). Its known-present
    # commands are the disk probe (dd), the arithmetic (expr) and the two stock
    # /etc tools the interview is allowed to reach for.
    need_s = {"dd", "expr", "cat", "/etc/rdb", "read", "echo"}
    miss_s = need_s - set(swords)
    if miss_s:
        fail("allowlist parser is not exercising setup.sh (vacuity guard): missing %s"
             % sorted(miss_s))
    else:
        ok("parser exercises setup.sh (%d cmds incl dd/expr/cat/rdb/read/echo)"
           % len(swords))
    # W4: the miniroot install script. Its known-present commands are the two
    # mount front-ends it probes with, the keymap applier and the disk probe --
    # i.e. exactly the four things that would make a clean result vacuous.
    need_m = {"/usr/lib/fs/cdfs/mount", "/etc/mount", "/etc/sioc", "dd"}
    miss_m = need_m - set(mwords)
    if miss_m:
        fail("allowlist parser is not exercising src/miniroot/profile (vacuity "
             "guard): missing %s" % sorted(miss_m))
    else:
        ok("parser exercises src/miniroot/profile (%d cmds incl the cdfs/s5 mount "
           "helpers, sioc and dd)" % len(mwords))
    if miss_d or miss_f:
        fail("allowlist parser is not exercising the scripts (vacuity guard): "
             "install.sh missing %s, firstboot.sh missing %s"
             % (sorted(miss_d), sorted(miss_f)))
    else:
        ok("parser exercises the scripts (install.sh %d cmds incl cp/dd/expr/rdb; "
           "firstboot.sh %d incl sed/echo/mv)" % (len(dwords), len(fwords)))

    # install.sh -- STRICT miniroot allowlist, no target-side extras. Its functions
    # include l11.sh's: the driver sources that file for a 1.1 layout.
    dfuncs = _defined_funcs(open(DRIVER).read() + open(L11).read())
    dbad = [w for w in dwords if _classify(w, dfuncs, proto_tools, DRIVER_EXTRA)]
    if dbad:
        fail("install.sh references tool(s) the miniroot does NOT carry: %s"
             % ", ".join(sorted(set(dbad))))
    else:
        ok("install.sh: every command resolves to a builtin, a miniroot.proto binary, or /cdrom")

    # l11.sh -- the 1.1 layout: sourced into the driver on the miniroot, so the
    # driver's own strict allowlist (and its functions) apply.
    lwords = list(command_words(read_sh(L11)))
    need_l = {"dd", "expr", "die", "msg", "rm"}
    lbad = [w for w in lwords if _classify(w, dfuncs, proto_tools, DRIVER_EXTRA)]
    if need_l - set(lwords):
        fail("allowlist parser is not exercising l11.sh (vacuity guard): missing %s"
             % sorted(need_l - set(lwords)))
    elif lbad:
        fail("l11.sh references tool(s) the miniroot does NOT carry: %s"
             % ", ".join(sorted(set(lbad))))
    else:
        ok("l11.sh: every command (%d) resolves to a builtin, a miniroot.proto binary, "
           "a driver function or /cdrom" % len(lwords))

    # setup.sh -- the interview. MEDIUM-resident, but it executes on the thin
    # miniroot exactly like the driver, so it gets the SAME strict allowlist:
    # no sed, no touch, no basename, no grep, no od.
    sbad = [w for w in swords if _classify(w, _defined_funcs(open(SETUP).read()),
                                           proto_tools, DRIVER_EXTRA)]
    if sbad:
        fail("setup.sh references tool(s) the miniroot does NOT carry: %s"
             % ", ".join(sorted(set(sbad))))
    else:
        ok("setup.sh: every command resolves to a builtin, a miniroot.proto binary, or /cdrom")

    # src/miniroot/profile -- the strictest of the three: it runs with NOTHING
    # mounted, so /cdrom is not even an escape hatch until its own probe has
    # succeeded. Same strict allowlist; one extra, the RAM-disk medium's guarded modadmin.
    mbad = [w for w in mwords if _classify(w, _defined_funcs(read_sh(MINIROOT_PROFILE)),
                                           proto_tools, PROFILE_EXTRA)]
    if mbad:
        fail("src/miniroot/profile references tool(s) the miniroot does NOT carry: %s"
             % ", ".join(sorted(set(mbad))))
    else:
        ok("src/miniroot/profile: every command resolves to a builtin or a "
           "miniroot.proto binary")

    # firstboot.sh -- runs on the FULL target; documented per-script extras.
    fbad = [w for w in fwords if _classify(w, _defined_funcs(open(FIRSTBOOT).read()),
                                           proto_tools, FIRSTBOOT_EXTRA)]
    if fbad:
        fail("firstboot.sh references tool(s) outside allowlist + documented extras %s: %s"
             % (sorted(FIRSTBOOT_EXTRA), ", ".join(sorted(set(fbad)))))
    else:
        ok("firstboot.sh: allowlist + documented target extras %s cover every command"
           % sorted(FIRSTBOOT_EXTRA))

    # NEGATIVE FIXTURES -- the audit MUST fire on a driver reaching for an absent
    # tool, or it is worthless. Each crafted script must be flagged for its tool.
    neg = [
        ("plain sed",        "#!/bin/sh\nsed 's/a/b/' /tmp/x\n",              "sed"),
        ("sed via run",      "#!/bin/sh\nrun sed -e s/x/y/ /tmp/z\n",         "sed"),
        ("sed in backticks", "#!/bin/sh\nv=`sed -n 1p /tmp/z`\necho $v\n",    "sed"),
        ("touch",            "#!/bin/sh\ntouch /tmp/marker\n",                "touch"),
        ("basename backtick","#!/bin/sh\nb=`basename /a/b/c`\necho $b\n",     "basename"),
        ("date",             "#!/bin/sh\nn=`date`\necho $n\n",                "date"),
    ]
    for name, script, needle in neg:
        bad = tool_violations(script, proto_tools, set())
        if needle in bad:
            ok("negative fixture fires: %-18s -> flagged %r" % (name, needle))
        else:
            fail("negative fixture DID NOT fire: %s (expected %r; got %r)"
                 % (name, needle, bad))

    # POSITIVE control -- a miniroot-clean script must NOT be flagged.
    pos = ("#!/bin/sh\nrun() { \"$@\"; }\n"
           "run cp /a /b\nx=`expr 1 + 1`\ncase $x in 2) : ;; esac\n"
           "/etc/rdb -a /dev/rdsk/c6d0s0\n")
    pbad = tool_violations(pos, proto_tools, set())
    if pbad:
        fail("positive control wrongly flagged clean commands: %r" % pbad)
    else:
        ok("positive control (run/cp/expr/case/:/rdb only) passes clean")


# ---------------------------------------------------------------------------
# H. subshell-loop audit -- redirect-fed `while read` loops must be subshell-safe
# ---------------------------------------------------------------------------
# The miniroot's 1991 SVR4 /bin/sh runs a `while ... done < FILE` loop in a
# SUBSHELL, so a variable MUTATED inside the loop body reverts to its pre-loop
# value at `done` (W5.4d: `npkgs` -> "installed 0 package(s)" while all 5 packages
# were installed; `vok` -> the aggregate guard `[ $vok -gt 0 ]` false-fired and the
# driver refused to arm first-boot). This audit FLAGS the exact defect class: a
# redirect-fed loop (`done < ...`) whose BODY assigns a variable that is then
# REFERENCED AFTER the loop. The subshell-safe idiom -- record to a temp file
# inside the loop, count/test it in the PARENT after `done` -- has no such
# assign-inside/use-after and passes. Negative fixtures (the W5.4d pattern) prove
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

    ★ BENCH-MEASURED 2026-08-11 (matrix run w3b2-cdi). W3b read the medium's set
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

    # NEGATIVE FIXTURES -- the audit MUST fire on the exact W5.4d defect, both the
    # pkgadd shape (`npkgs`) and the verify shape (`vok`), inside single AND double
    # quotes for the post-loop reference.
    neg = [
        ("W5.4d pkgadd (npkgs, dq ref)",
         '#!/bin/sh\nnpkgs=0\nwhile read pkg; do\n'
         '  npkgs=`expr "$npkgs" + 1`\ndone < /cd/order\n'
         'echo "installed $npkgs package(s)"\n', "npkgs"),
        ("W5.4d verify (vok, guard ref)",
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

    # --- H2 (W3b): no redirected `read`, and no redirected brace group -------
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
# `set --`. (W5.4e-run-1: vok counted 3, then the empty vfails file "counted" 3 too
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
# J. first-boot init wiring (W5.4f) -- rc2 hook + stock-dialog disarm
# ---------------------------------------------------------------------------
# The payload was ARMED by earlier waves but nothing in the STOCK target init
# invoked it, so cold boot #1 fell into the stock sysinit dialog. W5.4f closes
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


def audit_firstboot_wiring():
    head("J. first-boot init wiring (W5.4f): rc2 hook + stock-dialog disarm")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # J1: the arm step WRITES the rc2.d hook (driver-written, not a CD copy).
    if re.search(r'emit_firstboot_hook\s+"\$TARGET/etc/rc2\.d/S\d\dfirstboot"', code):
        ok("arm step writes /etc/rc2.d/S??firstboot via emit_firstboot_hook "
           "(driver-written; not a package member)")
    else:
        fail("arm step does not write /etc/rc2.d/S??firstboot via emit_firstboot_hook")

    # J2: DRIFT-LOCK -- run the driver's OWN emit_firstboot_hook and compare its
    # output byte-for-byte to the tracked reference payload/firstboot/S16firstboot.
    ref = None
    if not os.path.isfile(HOOK):
        fail("hook template missing: %s" % os.path.relpath(HOOK, REPO))
    else:
        ref = open(HOOK, "rb").read()
        try:
            func = _extract_func(driver_src, "emit_firstboot_hook")
        except StopIteration:
            func = None
            fail("could not extract emit_firstboot_hook() from the driver")
        if func:
            sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
            hp = workpath("emit.sh")
            outp = workpath("hook.out")
            if os.path.exists(outp):
                os.unlink(outp)
            with open(hp, "w") as fh:
                fh.write(func + '\nemit_firstboot_hook "$1"\n')
            r = subprocess.run([sh, hp, outp], capture_output=True, text=True)
            emitted = open(outp, "rb").read() if os.path.isfile(outp) else None
            if r.returncode == 0 and emitted is not None and emitted == ref:
                ok("drift-lock: emit_firstboot_hook reproduces "
                   "payload/firstboot/S16firstboot byte-for-byte (%d bytes)" % len(ref))
            else:
                fail("drift-lock FAILED: emit_firstboot_hook output != template "
                     "(rc=%d, emitted=%d bytes, ref=%d bytes)"
                     % (r.returncode, len(emitted) if emitted else 0, len(ref)))

    # J3: the hook itself is pre-POSIX clean, parses, guards on PENDING, invokes
    # firstboot.sh, and (task minimum) references only target-present tools.
    if os.path.isfile(HOOK):
        hook = open(HOOK, encoding="utf-8").read()
        hcode = strip_full_comments(hook)
        hits = [(why, m.group(0)) for pat, why in PATTERNS
                for m in re.finditer(pat, hcode)]
        if hits:
            for why, tok in hits:
                fail("hook: pre-POSIX violation %r (%s)" % (tok, why))
        else:
            ok("hook: no $(...), $(( )), export VAR=val, wc, [[ ]], or local")
        sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
        if subprocess.call([sh, "-n", HOOK]) == 0:
            ok("hook: %s -n clean" % sh)
        else:
            fail("hook: %s -n parse failed" % sh)
        if re.search(r'\[\s+-f\s+"\$FB/PENDING"\s+\]', hcode) and \
                re.search(r'firstboot\.sh', hcode):
            ok("hook runs firstboot.sh iff the PENDING marker exists (inert after)")
        else:
            fail("hook does not guard on PENDING and invoke firstboot.sh")
        proto_tools = load_proto_tools()
        if proto_tools is None:
            fail("miniroot.proto not found -- cannot check hook tool references")
        else:
            hbad = tool_violations(hook, proto_tools, set())
            if hbad:
                fail("hook references tool(s) the target may not carry: %s"
                     % ", ".join(sorted(set(hbad))))
            else:
                ok("hook: every command is a builtin or /sbin/sh (target-present)")

    # J4: the arm step DISARMS the stock sysinit dialog (chmod -x system.setup).
    if re.search(r'SETUP="\$TARGET/usr/amiga/bin/system\.setup"', code) and \
            re.search(r'chmod\s+0?644\s+"\$SETUP"', code):
        ok("arm step disarms the stock sysinit dialog "
           "(chmod -x /usr/amiga/bin/system.setup -- the stock once-only mechanism)")
    else:
        fail("arm step does not disarm /usr/amiga/bin/system.setup "
             "(the stock dialog would still fire at sysinit on cold boot #1)")

    # J5: firstboot.sh removes PENDING -- the once-only half the hook relies on.
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    if re.search(r'rm\s+-f\s+"\$\{MARK:\?\}"', fb):
        ok("firstboot.sh removes the PENDING marker when done (once-only)")
    else:
        fail("firstboot.sh does NOT remove PENDING -- would re-run every boot")

    # J6: the /dev-regeneration probe (/usr/amiga/lib/atdevs) MUST be gated so a
    # CARD-1 root never runs it. atdevs is a probe, not a generator -- it opens
    # /dev/dsk/c0d0s0 first, and on the real Z3660 under amix_mode NO card 0 is the
    # phantom A3091, so that open bus-errors in the driver's initialize() -> a
    # supervisor-mode kernel panic (pc=0x800D578), METAL-CONFIRMED 2026-09-14 on
    # the installed 060 first boot. firstboot skips the probe when the root
    # controller is card 1 (FB_SCSI_ID in 8..f; ced0 = e); card-0 roots (the
    # 030/040 bench line) keep the historical probe, where card 0 is the real HBA.
    # Key on the INVOCATION path, not the bare word "atdevs": the card-1 arm's
    # skip message mentions atdevs in prose, but only the card-0 arm actually
    # RUNS /usr/amiga/lib/atdevs.
    ATDEVS = "/usr/amiga/lib/atdevs"
    if ATDEVS not in fb:
        # atdevs gone entirely is fine (no probe = no card-0 open) but makes this
        # gate check vacuous -- surface it so a silent refactor cannot hide a
        # future un-gated re-introduction.
        ok("firstboot.sh no longer runs atdevs at all -- no /dev probe to gate "
           "(J6 gate check inert; re-point it if a probe is reintroduced)")
    else:
        m = re.search(r'case\s+"\$FB_SCSI_ID"\s+in(.*?)\besac\b', fb, re.S)
        if not m:
            fail("firstboot.sh runs the atdevs /dev probe but NOT under a "
                 "`case \"$FB_SCSI_ID\"` card guard -- a card-1 install would open "
                 "card 0 (phantom A3091) and PANIC on the real LC060")
        else:
            block = m.group(0)
            # C4-1: only a card-0 root (one digit 0..7) probes; every other root (8..f,
            # 10..1f) falls to the default arm, which must not run atdevs
            card0_arm = re.search(r'\n\t\[0-7\]\)(.*?);;', block, re.S)
            other_arm = re.search(r'\n\t\*\)(.*?);;', block, re.S)
            if card0_arm and ATDEVS in card0_arm.group(1) and other_arm and ATDEVS not in other_arm.group(1):
                ok("firstboot.sh gates the atdevs /dev probe on FB_SCSI_ID: only a "
                   "card-0 root (0..7) probes; a card-1..3 root (8..f, 10..1f) SKIPS it "
                   "so the phantom card-0 A3091 is never opened")
            else:
                fail("firstboot.sh's atdevs gate does not limit the probe to card-0 roots "
                     "(FB_SCSI_ID 0..7) -- a card-1 install could still run the "
                     "probe and bus-error on card 0 (pc=0x800D578)")

    # J6b: nothing ELSE in firstboot.sh opens a hardcoded card-0..7 disk node.
    # firstboot resolves root by dev_t (bcheckrc devnm) and names devices only as
    # c${FB_SCSI_ID}d0sN -- so a literal /dev/[r]dsk/c[0-7]dN would be a stray
    # bus-error landmine on the real LC060. There must be none.
    stray = sorted(set(re.findall(r'/dev/r?dsk/c[0-7]d\d', fb)))
    if stray:
        fail("firstboot.sh opens hardcoded card-0..7 node(s) %s besides the gated "
             "atdevs probe -- each is a bus-error landmine on the real LC060"
             % ", ".join(stray))
    else:
        ok("firstboot.sh names disk devices only as c${FB_SCSI_ID}d0sN "
           "(no hardcoded c0..c7 node) -- the gated atdevs probe is the sole card path")


# ---------------------------------------------------------------------------
# EG. non-blank target guard -- refuse to erase an existing Amix root unless the
#     profile opts in with TARGET_ERASE_OK=yes.
# ---------------------------------------------------------------------------
# The author path /etc/rdb -c (wipes the RDB) + mkfs the root slice -- it DESTROYS
# the target. A fresh zeroed target has no RDB, so `/etc/rdb -p 1` names nothing and
# the guard is transparent; an already-installed target's slice 1 is UNIX_Root, and
# without the guard a mis-selected re-run would silently reinstall over it (metal-
# confirmed re-wipe). The guard must (1) exist, gated on TARGET_ERASE_OK, reading
# rdb slice 1; (2) refuse BEFORE the destructive `/etc/rdb -c`; (3) be opted into by
# the demo profiles ONLY (their Preset A is a deliberate reinstall) so every other
# profile is protected by the default refuse.
def audit_erase_guard():
    head("EG. non-blank target guard: refuse to erase an Amix root unless TARGET_ERASE_OK=yes")
    driver_src = open(DRIVER, encoding="utf-8").read()
    try:
        fn = _extract_func(driver_src, "build_target_author")
    except StopIteration:
        fn = None
        fail("could not extract build_target_author() from the driver")
    if fn:
        scode = strip_full_comments(fn)
        gated = re.search(r'\[\s*"\$\{TARGET_ERASE_OK:-no\}"\s*!=\s*yes\s*\]', scode)
        unatt = re.search(r'\[\s*"\$\{INSTALL_UNATTENDED:-no\}"\s*=\s*yes\s*\]', scode)
        rdsk = re.search(r'RDSK\*\)', scode)
        rdbfall = re.search(r'/etc/rdb\s+"\$DISK_RAW"\s*>\s*/dev/null', scode)
        refuse = re.search(r'\[\s*"\$_tgt_rdb"\s*=\s*yes\s*\]', scode)
        logged = re.search(r'read as BLANK', scode)
        anyrdb = bool(rdsk and rdbfall and refuse)
        if gated and unatt and anyrdb and logged:
            ok("build_target_author refuses a target carrying ANY RDB (RDSK magic at "
               "block 0 OR /etc/rdb parses one -- an AmigaOS disk too, not only a "
               "UNIX_Root slice), gated on INSTALL_UNATTENDED=yes AND TARGET_ERASE_OK"
               "!=yes; and it logs the blank fall-through so an unattended wipe is "
               "never silent (fail-closed, overnight review 2026-09-16)")
        else:
            fail("build_target_author's non-blank guard is wrong (erase_gate=%s "
                 "unattended_gate=%s any_rdb=%s logged_fallthrough=%s) -- either an "
                 "author cell is refused over its own target, or a partitioned disk "
                 "is silently erased" % (bool(gated), bool(unatt), anyrdb, bool(logged)))
        mdie = re.search(r'die "target c\$\{ID\}d0 already carries', scode)
        mcreate = re.search(r'run /etc/rdb -c\b', scode)
        if mdie and mcreate and mdie.start() < mcreate.start():
            ok("the guard's die precedes `/etc/rdb -c` (the RDB wipe) -- it refuses "
               "BEFORE anything on the target is destroyed")
        elif mdie and mcreate:
            fail("the guard's die comes AFTER `/etc/rdb -c` -- the RDB is wiped before it refuses")
        else:
            fail("could not locate both the guard die and `/etc/rdb -c` in "
                 "build_target_author (die=%s create=%s)" % (bool(mdie), bool(mcreate)))
    optin = []
    for pf in sorted(os.listdir(PROFILES_DIR)):
        if not pf.endswith(".profile"):
            continue
        if _parse_profile(os.path.join(PROFILES_DIR, pf)).get("TARGET_ERASE_OK") == "yes":
            optin.append(pf)
    # The deliberate-reinstall demo line (Preset A repeat-install) is the ONLY place
    # TARGET_ERASE_OK=yes is allowed. It is the home pair PLUS the 2026-09-19
    # mobile-venue pair (metal-a4000-z3660-060-mobile{,-unattended}) -- the home pair
    # with only FB_IP/FB_GATEWAY changed, i.e. the same repeat-install demo on the
    # event's travel-router subnet. Every OTHER profile must stay protected.
    DEMO_ERASE_OK = ("metal-a4000-z3660-060.profile",
                     "metal-a4000-z3660-060-unattended.profile",
                     "metal-a4000-z3660-060-mobile.profile",
                     "metal-a4000-z3660-060-mobile-unattended.profile",
                     # K1 card master (card 0): the same install-preset semantics
                     "metal-a4000-z3660-060-k1.profile",
                     "metal-a4000-z3660-060-k1-unattended.profile",
                     # r6 (D-2): the master K1 twins inherit the bench re-install line.
                     "metal-a4000-z3660-060-k1-r6.profile",
                     "metal-a4000-z3660-060-k1-unattended-r6.profile")
    for prof in DEMO_ERASE_OK:
        if prof in optin:
            ok("%s opts into TARGET_ERASE_OK=yes (the deliberate-reinstall demo line)" % prof)
        else:
            fail("%s does not set TARGET_ERASE_OK=yes -- Preset A on an installed card "
                 "would REFUSE, breaking the repeat-install demo" % prof)
    extra = sorted(set(optin) - set(DEMO_ERASE_OK))
    if extra:
        fail("profile(s) other than the demo line opt into TARGET_ERASE_OK=yes: %s "
             "-- each is then unprotected against an accidental re-wipe" % ", ".join(extra))
    else:
        ok("ONLY the demo profiles (home + mobile + K1) opt in; every other profile is protected "
           "by the default refuse")


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
#     firmware (2026-09-26, P-2).
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
# K. W6.4b installer completeness -- contents-fsck fail-closed step + apkg.conf
# ---------------------------------------------------------------------------
# Two W6.4b additions to the driver, both audited fail-closed:
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
    """W6: firstboot makes the installed system X-READY before the X packages
    exist. The X set (xcore/xbasic/olcore) is an apkg step the operator runs
    LATER; the stock login PATH carries no /usr/bin/X11 and no LD_LIBRARY_PATH,
    and olwm's libXol.so is in /usr/lib (not the X binaries' own /usr/X/lib). The
    fix lives in OUR firstboot (the stock X bytes are proprietary) and must be
    SVR4-Bourne-safe + idempotent (firstboot can re-run if the dialog spans boots)."""
    print()
    print("== W6. X11 easy-start (firstboot: PATH/lib env + one-command startx) ==")
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

    # apkg PATH: /opt/amix/bin appended LAST on /etc/profile PATH (owner rule: last,
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
           "precedence (owner rule: last, never first); fixes `less: command not found`")
    else:
        fail("the /opt/amix/bin PATH append is wrong (present=%s grep-guard=%s "
             "after-X11=%s)" % (amix_path, amix_guard, amix_last))

    # The owner-approved OPEN LOOK desktop: olwm (window frames) + olwsm (the
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


def audit_apkg_timeouts():
    """W6-d: the install-time apkg (raw.conf, LOCAL raw slice) fails FAST -- a short
    SRC_APKG_TIMEOUT (APKG 0.2 has no 'retries' key) -- so an unattended re-power
    cannot hang for minutes on a dead device; the INSTALLED /etc/apkg.conf keeps the
    package DEFAULTS so the live post-install network fetch (Xcore) is not cut short."""
    print()
    print("== W6-d. apkg timeouts: install-time fails fast, installed keeps defaults ==")
    drv = read_sh(DRIVER)

    if re.search(r'echo\s+"timeout=', drv):
        ok("install.sh raw.conf carries a timeout -- the install-time apkg reads a "
           "LOCAL slice, so a stall is a dead device, not a slow mirror; the timeout "
           "is the fail-fast")
    else:
        fail("install.sh raw.conf does not set a timeout -- an unattended install "
             "could hang on a dead local read")

    if re.search(r'echo\s+"retries=', drv):
        fail("install.sh raw.conf still sets retries -- APKG 0.2 has no 'retries' key "
             "and warns \"unknown key 'retries', ignored\" on every RAW install; the "
             "timeout alone is the fail-fast")
    else:
        ok("install.sh raw.conf does not set retries -- APKG 0.2 has no such key, so "
           "the short timeout is the fail-fast for the LOCAL slice read")

    m = re.search(r'APKG_CONF="\$TARGET/etc/apkg\.conf".*?\}\s*>\s*"\$APKG_CONF"',
                  drv, re.S)
    if not m:
        fail("could not locate the installed /etc/apkg.conf write block in install.sh")
    elif re.search(r'timeout=|retries=', m.group(0)):
        fail("the installed /etc/apkg.conf pins timeout/retries -- it must keep the "
             "package defaults so the live post-install network fetch survives")
    else:
        ok("the installed /etc/apkg.conf keeps the package defaults (no timeout/retries "
           "pinned) -- the post-install network Xcore fetch is not cut short")

    for prof in ("metal-a4000-z3660-060", "metal-a4000-z3660-060-unattended"):
        pf = open(os.path.join(REPO, "profiles", prof + ".profile"),
                  encoding="utf-8").read()
        mm = re.search(r'^SRC_APKG_TIMEOUT=(\d+)', pf, re.M)
        val = int(mm.group(1)) if mm else None
        if val is not None and val <= 60:
            ok("%s: SRC_APKG_TIMEOUT=%d (short -- install-time fail-fast)" % (prof, val))
        else:
            fail("%s: SRC_APKG_TIMEOUT=%s is not short (<=60) -- an unattended dead "
                 "read could hang" % (prof, val))


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
    head("K. W6.4b installer completeness: contents-fsck fail-closed + /etc/apkg.conf")
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
    # (W1 routes the call through `runq`, the output-routing wrapper that RETURNS
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

    # K4: the driver writes /etc/apkg.conf with the repo line. W1 de-hardcodes the
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
    # RE-POINT it. Until W5 the repository was purely a profile fact, so
    # firstboot.sh touching apkg.conf at all was the finding. W5 makes the repo
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
            ok("first-boot re-points apkg.conf only in the W5 shape: %s"
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
# L. W6.4c repo-host baking -- zero-touch apkg out of the box
# ---------------------------------------------------------------------------
# W6.4b PROVED apkg-over-network works, but only after a MANUAL /etc/inet/hosts
# edit: the fresh box has no DNS and firstboot baked only its own nodename, so it
# could not resolve the repo host (files.example.net). W6.4c makes it zero-touch:
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


def _fb_appends_repo_host(fb_code):
    """True iff firstboot.sh appends the repo host to /etc/inet/hosts, guarded on
    BOTH FB_REPO_HOST and FB_REPO_IP being non-empty. `fb_code` is comment-stripped."""
    guarded = (re.search(r'\[\s+-n\s+"\$FB_REPO_HOST"\s+\]', fb_code) and
               re.search(r'\[\s+-n\s+"\$FB_REPO_IP"\s+\]', fb_code))
    # echo "<ip> <host>" >> a hosts file (the temp hosts.rp$$ or /etc/inet/hosts)
    appended = re.search(r'echo\s+"\$FB_REPO_IP[^"]*\$FB_REPO_HOST"\s*>>\s*\S*hosts\S*',
                         fb_code)
    lands = re.search(r'/etc/inet/hosts', fb_code)
    return bool(guarded and appended and lands)


def audit_repo_host():
    head("L. W6.4c repo-host baking: profile vars + firstboot /etc/inet/hosts append (zero-touch apkg)")
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    drv = strip_full_comments(open(DRIVER, encoding="utf-8").read())

    # L1: firstboot appends the repo host to /etc/inet/hosts under the two-var guard.
    if _fb_appends_repo_host(fb):
        ok('firstboot.sh appends "$FB_REPO_IP $FB_REPO_HOST" to /etc/inet/hosts, '
           "guarded on both vars non-empty")
    else:
        fail("firstboot.sh does NOT append the repo host to /etc/inet/hosts under a "
             "[ -n FB_REPO_HOST ] && [ -n FB_REPO_IP ] guard")
    # L2: duplicate guard -- a sed line-strip of the host precedes the append, and
    # it is written as TWO -e expressions. It used to be one alternation
    # (`\([ TAB]\|$\)`), which SVR4 sed cannot parse: MEASURED inert on the bench
    # 2026-08-12, i.e. the guard had never once fired and a re-run appended the
    # repo host a second time. Requiring both expressions is what keeps the fix
    # from being quietly written back into the form that cannot work.
    if re.search(r'-e "/\[ \t\]\$FB_REPO_HOST\[ \t\]/d"', fb) and \
            re.search(r'-e "/\[ \t\]\$FB_REPO_HOST\\?\$/d"', fb):
        ok("firstboot.sh strips any prior repo-host line before appending, as two "
           "-e expressions (token-followed-by-space, token-at-end-of-line) -- SVR4 "
           "sed has no `\\|` alternation")
    else:
        fail("firstboot.sh has no PORTABLE duplicate guard for $FB_REPO_HOST: it "
             "needs two -e expressions, one for [ TAB] and one for end-of-line")
    # L3: skip-but-log when the repo vars are empty (a repo-less profile is legal).
    if re.search(r'skipping repo hosts entry', fb):
        ok("firstboot.sh logs a skip when FB_REPO_HOST/FB_REPO_IP are empty "
           "(repo-less profile is legal)")
    else:
        fail("firstboot.sh does not log-and-skip the append when the repo vars are empty")
    # (network-config is never written -- proven for the WHOLE firstboot.sh in audit F;
    # not re-checked here, since firstboot legitimately LOGS "network-config UNTOUCHED".)

    # L5: install.sh passes both vars into firstboot.conf.
    if re.search(r'echo\s+"FB_REPO_HOST=\$FB_REPO_HOST"', drv) and \
            re.search(r'echo\s+"FB_REPO_IP=\$FB_REPO_IP"', drv):
        ok("install.sh writes FB_REPO_HOST + FB_REPO_IP into firstboot.conf")
    else:
        fail("install.sh does not pass FB_REPO_HOST/FB_REPO_IP through to firstboot.conf")

    # L6: profiles carry the vars, PAIRED; the bench profile has the canonical values.
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    if not profs:
        fail("no profiles found under %s -- cannot check repo-host vars"
             % os.path.relpath(PROFILES_DIR, REPO))
        return
    with_repo = []
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        has_host = "FB_REPO_HOST" in d
        has_ip = "FB_REPO_IP" in d
        if has_host != has_ip:
            fail("%s defines only one of FB_REPO_HOST/FB_REPO_IP -- they must be paired"
                 % pf)
        elif has_host and has_ip:
            ok("%s carries paired FB_REPO_HOST=%r FB_REPO_IP=%r"
               % (pf, d["FB_REPO_HOST"], d["FB_REPO_IP"]))
            if d["FB_REPO_HOST"] and d["FB_REPO_IP"]:
                with_repo.append(pf)
    # bench canonical values are pinned (the acceptance rig).
    bench = os.path.join(PROFILES_DIR, "bench-a3000-a4091.profile")
    if os.path.isfile(bench):
        d = _parse_profile(bench)
        if d.get("FB_REPO_HOST") == "pkg.amigaux.org" and d.get("FB_REPO_IP") == "52.59.174.203":
            ok("bench profile pins FB_REPO_HOST=pkg.amigaux.org FB_REPO_IP=52.59.174.203")
        else:
            fail("bench profile repo host/ip not the canonical pkg.amigaux.org/52.59.174.203 "
                 "(the old LAN files.example.net/192.0.2.2 is retired) (got %r / %r)"
                 % (d.get("FB_REPO_HOST"), d.get("FB_REPO_IP")))
    else:
        fail("bench-a3000-a4091.profile missing -- cannot pin the canonical repo host/ip")

    # L7: the fires-on-missing-append cross-check -- if ANY profile carries non-empty
    # repo vars, firstboot.sh MUST append the repo host, or the bake is a dead letter.
    if with_repo and not _fb_appends_repo_host(fb):
        fail("profile(s) %s carry FB_REPO_HOST/FB_REPO_IP but firstboot.sh never appends "
             "the repo host to /etc/inet/hosts" % ", ".join(with_repo))
    elif with_repo:
        ok("profile(s) %s carry repo vars AND firstboot.sh appends the repo host "
           "(no dead-letter bake)" % ", ".join(with_repo))

    # NEGATIVE FIXTURE -- a firstboot that carries the repo var but omits the append
    # MUST be flagged, or L1/L7 are worthless.
    neg = ('#!/bin/sh\n. "$CONF"\n'
           'echo "repo host is $FB_REPO_HOST at $FB_REPO_IP"\n')
    if not _fb_appends_repo_host(strip_full_comments(neg)):
        ok("negative fixture fires: a firstboot that omits the /etc/inet/hosts append is flagged")
    else:
        fail("negative fixture did NOT fire: a missing-append firstboot passed the append check")
    # POSITIVE control -- the guarded strip+append snippet passes.
    pos = ('#!/bin/sh\n'
           'if [ -n "$FB_REPO_HOST" ] && [ -n "$FB_REPO_IP" ]; then\n'
           '  sed "/[ \t]$FB_REPO_HOST\\([ \t]\\|$\\)/d" /etc/inet/hosts > /etc/inet/hosts.rp$$\n'
           '  echo "$FB_REPO_IP\t$FB_REPO_HOST" >> /etc/inet/hosts.rp$$\n'
           '  mv /etc/inet/hosts.rp$$ /etc/inet/hosts\n'
           'fi\n')
    if _fb_appends_repo_host(strip_full_comments(pos)):
        ok("positive control passes: the guarded strip+append snippet is accepted")
    else:
        fail("positive control wrongly rejected the guarded strip+append snippet")


# ---------------------------------------------------------------------------
# M. W6-RAW.1 RAW source arm -- SOURCE_KIND dimension + apkg SRC_RAW branch
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


def _apkg_softened(text):
    """Offending line if an apkg invocation is softened with a `|| true`/`|| :`/
    `|| continue`/`|| warn`/`|| echo` that would swallow its nonzero exit (the
    fail-OPEN trap). Comment lines stripped first."""
    for l in strip_full_comments(text).splitlines():
        if '"$APKG"' not in l and "apkg " not in l:
            continue
        if re.search(r'\|\|\s*(true|:|continue|warn\b|echo\b)', l):
            return l.strip()
    return None


def audit_raw_arm():
    head("M. W6-RAW.1 RAW source arm: SOURCE_KIND dimension + apkg SRC_RAW branch")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # M1: every profile carries SOURCE_KIND (default cdfs is legal, but the two
    # shipped CD profiles pin it explicitly); the raw profile is SOURCE_KIND=raw.
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    if not profs:
        fail("no profiles found under %s" % os.path.relpath(PROFILES_DIR, REPO))
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        sk = d.get("SOURCE_KIND", "cdfs")
        if sk not in ("cdfs", "raw"):
            fail("%s: SOURCE_KIND=%r is not cdfs or raw" % (pf, sk))
        else:
            ok("%s: SOURCE_KIND=%s" % (pf, sk))

    # M2: the raw profile exists and carries the RAW source keys.
    if not os.path.isfile(RAW_PROFILE):
        fail("raw profile missing: %s" % os.path.relpath(RAW_PROFILE, REPO))
    else:
        d = _parse_profile(RAW_PROFILE)
        if d.get("SOURCE_KIND") == "raw" and d.get("SRC_SCSI_ID") \
                and d.get("SRC_PAYLOAD_SLICE") and d.get("SRC_RAW_SLICE"):
            ok("bench-a3000-a4091-raw: SOURCE_KIND=raw SRC_SCSI_ID=%s payload=s%s raw=s%s"
               % (d["SRC_SCSI_ID"], d["SRC_PAYLOAD_SLICE"], d["SRC_RAW_SLICE"]))
        else:
            fail("raw profile lacks SOURCE_KIND=raw + SRC_SCSI_ID/SRC_PAYLOAD_SLICE/"
                 "SRC_RAW_SLICE (got %r)" % d)

    # M3: the driver defaults SOURCE_KIND to cdfs, validates cdfs|raw, dies on else.
    if re.search(r'\[\s+-n\s+"\$SOURCE_KIND"\s+\]\s+\|\|\s+SOURCE_KIND=cdfs', code):
        ok("driver defaults SOURCE_KIND to cdfs (backward-compatible)")
    else:
        fail("driver does not default SOURCE_KIND to cdfs")
    if re.search(r'case\s+"\$SOURCE_KIND"\s+in', code) and \
            re.search(r'die\s+"profile SOURCE_KIND=.*is not', code):
        ok("driver validates SOURCE_KIND (case cdfs|raw|*) and dies on an unknown kind")
    else:
        fail("driver does not fail closed on an unknown SOURCE_KIND")

    # M4: the RAW branch writes raw.conf with the SRC_RAW repo, a TARGET-backed
    # cache, and the CD-resident engine paths (echo + redirection only).
    if re.search(r'echo\s+"repo=raw:\$SRC_RAW_DEV"', code) and \
            re.search(r'echo\s+"cachedir=\$APKGCACHE"', code) and \
            re.search(r'APKGCACHE="\$TARGET/tmp/', code) and \
            re.search(r'echo\s+"pkgadd=\$INST/bin/pkgadd"', code) and \
            re.search(r'>\s*"\$RAWCONF"', code):
        ok("RAW branch writes raw.conf (repo=raw:<dev>, cachedir on the target, "
           "pkgadd=<CD>/bin/pkgadd) via echo+redirection")
    else:
        fail("RAW branch does not write raw.conf with repo=raw: + target cache + CD pkgadd")

    # M5: the RAW branch runs apkg update THEN apkg -R install, both FAIL CLOSED.
    upd = re.search(r'"\$APKG"\s+-c\s+"\$RAWCONF"\s+update\s+\|\|\s+die', code)
    ins = re.search(r'"\$APKG"\s+-c\s+"\$RAWCONF"\s+-R\s+"\$TARGET"\s+install\s+"\$@"\s+\|\|\s+die',
                    code)
    if upd and ins:
        ok("RAW branch: `apkg update` and `apkg -R $TARGET install \"$@\"`, both `|| die` (fail closed)")
    else:
        fail("RAW branch apkg update/install not both guarded by `|| die` "
             "(update=%s install=%s)" % (bool(upd), bool(ins)))
    soft = _apkg_softened(driver_src)
    if soft:
        fail("an apkg invocation is SOFTENED (fail-open): %s" % soft)
    else:
        ok("no `|| true`/`|| :`-style softening on any apkg invocation")

    # M6: the RAW branch must NEVER set APKG_ROOT (client root != install target).
    if re.search(r'\bAPKG_ROOT=', code):
        fail("driver assigns APKG_ROOT -- the client root must NOT be the install "
             "target (use -R for the target; leave APKG_ROOT unset). See conf.c.")
    else:
        ok("driver never sets APKG_ROOT (target is -R only; client root stays unset)")

    # M7: install order == apkg names. The RAW branch passes the order-file tokens
    # verbatim to apkg; that only works if the raw catalog's NAMES match the tokens.
    # The driver must read the order file and `set --` the tokens (subshell-safe).
    if re.search(r'set\s+--\s+`cat\s+"\$rawnames"`', code) and \
            re.search(r'npkgs=\$#', code):
        ok("RAW branch builds the install set from the order file (subshell-safe temp "
           "file + `[ -s ]`-guarded `set --`), passes tokens verbatim to apkg")
    else:
        fail("RAW branch does not build the apkg name list from the order file safely")

    # M8: the /cdrom-payload-mount convention is documented in the driver (the exact
    # `/etc/mount <dev> /cdrom 0 s5` command appears, so the operator/metal builder
    # knows how the payload slice is mounted).
    if re.search(r'/etc/mount\s+\$SRC_PAYLOAD_BLK\s+\$CDROOT\s+0\s+s5', driver_src) or \
            re.search(r'mount\s+\$SRC_PAYLOAD_BLK\s+\$CDROOT\s+0\s+s5', driver_src):
        ok("driver documents the payload-at-/cdrom mount convention "
           "(/etc/mount $SRC_PAYLOAD_BLK $CDROOT 0 s5)")
    else:
        fail("driver does not document the `/etc/mount <payload> /cdrom 0 s5` convention")

    # M9: the raw source-disk builder exists and reuses the staging path.
    if os.path.isfile(RAW_BUILDER):
        b = open(RAW_BUILDER, encoding="utf-8").read()
        if "--stage-only" in b and "gen-catalog.py" in b and "raw:" in b:
            ok("tools/build-raw-source.sh present (reuses --stage-only staging, "
               "gen-catalog --raw, SRC_RAW layout)")
        else:
            fail("build-raw-source.sh does not reuse --stage-only staging + gen-catalog --raw")
        # M9b: the s5 14-char filename adaptation (bench finding, W6-RAW.1). The
        # payload slice is s5 (DIRSIZ=14), so the builder must s5-safe the tree --
        # rename bootslice.manifest -> bootslice.man and fail closed on any staged
        # filename >14 chars -- or the driver cannot read the profile/manifest.
        if "bootslice.man" in b and ">14 chars" in b:
            ok("build-raw-source.sh s5-safes the payload tree (bootslice.man rename + "
               ">14-char fail-closed guard -- the s5 DIRSIZ=14 bench finding)")
        else:
            fail("build-raw-source.sh lacks the s5 14-char adaptation (bootslice.man "
                 "rename + >14-char guard) -- the payload slice is s5 (DIRSIZ=14)")
    else:
        fail("raw source-disk builder missing: %s" % os.path.relpath(RAW_BUILDER, REPO))

    # NEGATIVE FIXTURES -- the fail-closed checks must actually fire.
    neg_soft = ('APKG="$INST/bin/apkg"\n'
                '"$APKG" -c "$RAWCONF" -R "$TARGET" install "$@" || true\n')
    if _apkg_softened(neg_soft):
        ok("negative fixture fires: `apkg ... install || true` is flagged fail-open")
    else:
        fail("negative fixture did NOT fire: a softened apkg install was not caught")
    neg_root = 'APKG_ROOT="$TARGET"; export APKG_ROOT\n'
    if re.search(r'\bAPKG_ROOT=', neg_root):
        ok("negative fixture fires: an APKG_ROOT assignment is detectable")
    else:
        fail("negative fixture did NOT fire: APKG_ROOT assignment check is broken")


def audit_bootable_source():
    head("N. W6-RAW.2b bootable METAL source disk: profile + --bootable builder mode")

    # N1: the metal RAW profile exists and carries the bootable-source keys.
    if not os.path.isfile(METAL_RAW_PROFILE):
        fail("metal RAW profile missing: %s" % os.path.relpath(METAL_RAW_PROFILE, REPO))
        return
    d = _parse_profile(METAL_RAW_PROFILE)
    if d.get("SOURCE_KIND") == "raw" and d.get("SRC_SCSI_ID") == "0" \
            and d.get("SRC_PAYLOAD_SLICE") == "4" and d.get("SRC_RAW_SLICE") == "5":
        ok("metal-a4000-z3660-raw: SOURCE_KIND=raw SRC_SCSI_ID=0 payload=s4 raw=s5 "
           "(source disk at metal id 0)")
    else:
        fail("metal RAW profile lacks SOURCE_KIND=raw + SRC_SCSI_ID=0 + payload=s4/raw=s5 "
             "(got SOURCE_KIND=%r SRC_SCSI_ID=%r payload=%r raw=%r)"
             % (d.get("SOURCE_KIND"), d.get("SRC_SCSI_ID"),
                d.get("SRC_PAYLOAD_SLICE"), d.get("SRC_RAW_SLICE")))

    # N2: the source boot chain kernel identity (c0s1unix, rootdev id-0 slice-1,
    # brel sum -r 28387 -- the P5.4 r4 rebuild of 2026-08-16: probed support.c
    # (the cross path's glob-vs-conf kpatch gap, closed by kerntools'
    # work/patch-carrier-r4), both z3660 direct maps, the advanced cdfs pin
    # 673cd9f4, a3091/a2091 at be2f5e3; superseded line: 51865 r3, 24949 r2,
    # 33696 r1, 04333 48-era) and the target root (unchanged id-6 slice-1).
    if d.get("SRC_MINIROOT_KERNEL") == "c0s1unix" \
            and d.get("SRC_MINIROOT_ROOTDEV") == "0x00480010" \
            and d.get("SRC_KERNEL_BREL_SUMR") == "28387":
        ok("source boot kernel = c0s1unix, rootdev 0x00480010 (id 0 slice 1), brel sum -r 28387 (P5.4 r4)")
    else:
        fail("metal RAW profile source-kernel keys wrong (SRC_MINIROOT_KERNEL=%r "
             "SRC_MINIROOT_ROOTDEV=%r SRC_KERNEL_BREL_SUMR=%r)"
             % (d.get("SRC_MINIROOT_KERNEL"), d.get("SRC_MINIROOT_ROOTDEV"),
                d.get("SRC_KERNEL_BREL_SUMR")))
    if d.get("ROOTDEV") == "0x00480016" and d.get("TARGET_SCSI_ID") == "6" \
            and d.get("MINIROOT_KERNEL") == "c6s1unix":
        ok("target unchanged: ROOTDEV 0x00480016 (id 6 slice 1), target kernel c6s1unix")
    else:
        fail("metal RAW profile target keys drifted from the metal profile "
             "(ROOTDEV=%r TARGET_SCSI_ID=%r MINIROOT_KERNEL=%r)"
             % (d.get("ROOTDEV"), d.get("TARGET_SCSI_ID"), d.get("MINIROOT_KERNEL")))

    # N2b (Wave C2, re-pinned after plan B2): the 040 line's SOURCE profile --
    # INSTALL_CPU=040, a ufs target, the 040 miniroot kernel rooted at id 0 slice 1
    # (0x00480010), and boot2-040 SELECTED BY CONTRACT IDENTITY (`good_040`, which
    # amix-kerntools promoted into contracts/bootchain-v1.json on 2026-08-19 after
    # the B1 metal proof) rather than pinned by literal hash. Both the source
    # chain's loader (SRC_BOOT2_IDENTITY) and the payload boot slice's
    # (BOOTSLICE_BOOT2_IDENTITY) must name it: the payload slice is lifted from the
    # same boot2-040 donor, so a profile that named only one of them would be
    # refused by the other gate -- correctly, but confusingly.
    p040 = os.path.join(PROFILES_DIR, "metal-a4000-z3660-040.profile")
    if not os.path.isfile(p040):
        fail("040 source profile missing: metal-a4000-z3660-040.profile")
    else:
        d40 = _parse_profile(p040)
        if d40.get("INSTALL_CPU") == "040" and d40.get("TARGET_ROOT_FSTYPE") == "ufs" \
                and d40.get("SRC_MINIROOT_ROOTDEV") == "0x00480010" \
                and d40.get("SOURCE_KIND") == "raw" \
                and d40.get("SRC_BOOT2_IDENTITY") == "good_040" \
                and d40.get("BOOTSLICE_BOOT2_IDENTITY") == "good_040":
            ok("metal-a4000-z3660-040: INSTALL_CPU=040, ufs target, source rootdev "
               "0x00480010 (id 0 slice 1), boot2 identity good_040 on BOTH the "
               "source chain and the payload boot slice -- the 040 install line, "
               "source side (target-boot keys are C4)")
        else:
            fail("metal-a4000-z3660-040 source-side keys wrong (INSTALL_CPU=%r "
                 "TARGET_ROOT_FSTYPE=%r SOURCE_KIND=%r SRC_MINIROOT_ROOTDEV=%r "
                 "SRC_BOOT2_IDENTITY=%r BOOTSLICE_BOOT2_IDENTITY=%r)"
                 % (d40.get("INSTALL_CPU"), d40.get("TARGET_ROOT_FSTYPE"),
                    d40.get("SOURCE_KIND"), d40.get("SRC_MINIROOT_ROOTDEV"),
                    d40.get("SRC_BOOT2_IDENTITY"),
                    d40.get("BOOTSLICE_BOOT2_IDENTITY")))
        # A profile may pin the loader ONE way, never two: the identity key and a
        # literal sha answer the same question, and honouring both would silently
        # report on a loader the profile did not name. (The builder refuses the
        # pair at run time; this catches it at edit time.)
        if d40.get("SRC_BOOT2_SHA256"):
            fail("metal-a4000-z3660-040 still carries SRC_BOOT2_SHA256=%r beside "
                 "SRC_BOOT2_IDENTITY -- the literal-hash escape hatch is for a "
                 "loader with NO contract row; good_040 has one since 2026-08-19"
                 % d40.get("SRC_BOOT2_SHA256"))
        else:
            ok("metal-a4000-z3660-040 pins its loader exactly once (contract "
               "identity, no leftover literal SRC_BOOT2_SHA256)")
        # ★ THE LOADER SELECTION IS A PROPERTY OF THE CPU LINE, NOT OF ONE FILE.
        # Wave C3 added a SECOND 040 profile (bench-a3000-040), so this can no
        # longer be "everything except metal-a4000-z3660-040": the rule it was
        # written to protect is that a profile's INSTALL_CPU and its loader
        # selection are the same fact stated twice, and any disagreement is a
        # medium framed with a loader its kernel line cannot use.
        #
        #   INSTALL_CPU absent (the 030 line) => select NOTHING. That is what keeps
        #     those profiles on the contract's DEFAULT identity `good` and their
        #     media byte-identical; selecting it explicitly is how a future contract
        #     edit silently re-points them.
        #   INSTALL_CPU 040|060                => select `good_040` on BOTH keys
        #     (the source chain and the payload boot slice are different media
        #     positions, each gated once), and never a literal SRC_BOOT2_SHA256
        #     beside it -- the escape hatch is for a loader with no contract row,
        #     and good_040 has had one since 2026-08-19.
        stray, wrong = [], []
        for pf in sorted(f for f in os.listdir(PROFILES_DIR)
                         if f.endswith(".profile")):
            dp = _parse_profile(os.path.join(PROFILES_DIR, pf))
            sel = (dp.get("SRC_BOOT2_IDENTITY"), dp.get("BOOTSLICE_BOOT2_IDENTITY"))
            # r6 (D-2): a `*-r6*.profile` rides the RTH1 root-hint loader instead --
            # good_040_rth (040/060) or good_rth (030), contract CANDIDATES -- on the
            # same keys, by the same one-fact rule. The Gayle bench row R7 (-R7row) rides it too.
            if dp.get("INSTALL_LAYOUT") == "1.1":
                # the 1.1 layout boots the amix-dlm loader from its store: no 1.0
                # boot2 identity is selected, and none may be
                if sel[0] or sel[1] or dp.get("SRC_BOOT2_SHA256"):
                    wrong.append("%s (1.1 selects a 1.0 boot2)" % pf)
                continue
            if ".profile" in pf and ("-r6" in pf or "-R7row" in pf):
                want = ("good_040_rth", "good_040_rth") if dp.get("INSTALL_CPU") in ("040", "060") else None
                ok30 = sel in ((None, "good_rth"), ("good_rth", "good_rth"))
                if (want and sel != want) or (not want and not ok30) or dp.get("SRC_BOOT2_SHA256"):
                    wrong.append("%s (r6: SRC=%r BOOTSLICE=%r SHA=%r)"
                                 % (pf, sel[0], sel[1], dp.get("SRC_BOOT2_SHA256")))
            elif dp.get("INSTALL_CPU") in ("040", "060"):
                if sel != ("good_040", "good_040") or dp.get("SRC_BOOT2_SHA256"):
                    wrong.append("%s (SRC=%r BOOTSLICE=%r SHA=%r)"
                                 % (pf, sel[0], sel[1], dp.get("SRC_BOOT2_SHA256")))
            elif sel[0] or sel[1] or dp.get("SRC_BOOT2_SHA256"):
                stray.append(pf)
        if stray:
            fail("030 profile(s) now select a boot2 identity: %s -- the 030 line's "
                 "loader of record is the contract default `good`, and selecting it "
                 "explicitly is how a future contract edit silently re-points them"
                 % ", ".join(stray))
        elif wrong:
            fail("040/060 profile(s) do not select good_040 on BOTH loader keys (r6: good_040_rth / good_rth): %s"
                 % ", ".join(wrong))
        else:
            ok("loader selection follows the CPU line: every 030 profile selects "
               "nothing (=> contract default `good`), every 040/060 profile selects "
               "good_040 on both the source chain and the payload boot slice")

    # N2c (Wave C3): the BENCH 040 profile -- the one that closes the C4 INTERIM on
    # this one rig. metal-a4000-z3660-040 carries the donor's 030 target chain by
    # declared intent (its ★C4 note): on metal that is a deferral, because an 030
    # z3660scsi chain at least exists there. On the BENCH it is a WALL -- that chain
    # cannot boot the emulated A3000 at all -- so this profile pins a 68040 TARGET
    # kernel, and these are the keys that say so:
    #
    #   KERNEL_BREL_SUMR 52867   the 040 target brel (elf2brel over the producer's
    #                            own `unix-040`, which already ships rootdev
    #                            0x00480016 = id 6 slice 1 -- the --id 6 stamp is a
    #                            zero-byte no-op, verified 2026-08-19). It is a GATE:
    #                            build-bootslice.py compares it against the kernel it
    #                            actually pulls out of BOOTSLICE_SOURCE_HDF, so a
    #                            donor that was never re-kerneled is caught by the
    #                            number instead of at the first cold boot.
    #   MINIROOT_KERNEL          names that kernel rather than the 030 `c6s1unix`,
    #                            so the two 040 profiles cannot be confused in a log.
    #   SRC_KERNEL_BREL_SUMR 06634  the SOURCE chain is the SAME artifact the metal
    #                            040 medium frames (both rigs put the source disk at
    #                            id 0), and the shared number is itself a check: a
    #                            medium framed with the TARGET kernel by mistake is
    #                            refused here.
    #   TARGET_HBA a3000 / FB_ETHER_IF aen0  the bench rig, not the Z3660 metal one.
    pb40 = os.path.join(PROFILES_DIR, "bench-a3000-040.profile")
    if not os.path.isfile(pb40):
        fail("bench 040 profile missing: bench-a3000-040.profile (Wave C3)")
    else:
        db = _parse_profile(pb40)
        want = {"INSTALL_CPU": "040", "SOURCE_KIND": "raw", "SRC_SCSI_ID": "0",
                "SRC_KERNEL_BREL_SUMR": "06634", "SRC_MINIROOT_ROOTDEV": "0x00480010",
                "TARGET_ROOT_FSTYPE": "ufs", "TARGET_HBA": "a3000",
                "TARGET_SCSI_ID": "6", "TARGET_DISK_MB": "100",
                "ROOTDEV": "0x00480016", "KERNEL_BREL_SUMR": "52867",
                "MINIROOT_KERNEL": "unix-040-target-c6s1",
                "FB_NODENAME": "uaeamix", "FB_IP": "192.0.2.38",
                "FB_ETHER_IF": "aen0"}
        bad = {k: (v, db.get(k)) for k, v in want.items() if db.get(k) != v}
        if bad:
            fail("bench-a3000-040 keys wrong: %s"
                 % "; ".join("%s want %r got %r" % (k, v[0], v[1])
                             for k, v in sorted(bad.items())))
        else:
            ok("bench-a3000-040: 040 SOURCE chain (brel 06634, rootdev id 0 slice 1) "
               "+ a 68040 TARGET boot chain (brel 52867, rootdev id 6 slice 1) on the "
               "bench rig (a3000 SCSI, aen0, uaeamix) -- the C4 interim closed for "
               "this cell")
        # The two 040 profiles must not share a payload boot directory: the payload
        # slice is s5 and a medium carries exactly ONE profile's boot slice, so two
        # profiles under one dir name would be two different kernels with one name.
        if db.get("BOOTSLICE_IMG") == d40.get("BOOTSLICE_IMG"):
            fail("bench-a3000-040 and metal-a4000-z3660-040 share BOOTSLICE_IMG=%r "
                 "-- two different target kernels staged under one payload path"
                 % db.get("BOOTSLICE_IMG"))
        else:
            ok("the two 040 profiles stage their boot slices under different payload "
               "dirs (%s vs %s)" % (db.get("BOOTSLICE_IMG"), d40.get("BOOTSLICE_IMG")))
        # And the whole point of the split: the bench target chain is NOT the metal
        # one. If these two ever agree, somebody re-pinned one of them by copy.
        if db.get("KERNEL_BREL_SUMR") == d40.get("KERNEL_BREL_SUMR"):
            fail("bench-a3000-040 and metal-a4000-z3660-040 declare the SAME target "
                 "KERNEL_BREL_SUMR (%r) -- the bench profile exists precisely because "
                 "the metal donor's chain cannot boot the bench rig"
                 % db.get("KERNEL_BREL_SUMR"))
        else:
            ok("the bench 040 target kernel is not the metal 040 profile's C4 "
               "placeholder (%s vs %s)"
               % (db.get("KERNEL_BREL_SUMR"), d40.get("KERNEL_BREL_SUMR")))

    # N3: the source boot chain's bootpri is STRICTLY BELOW the target's -- this is
    # what makes the freshly-installed id-6 disk win the post-install boot with no
    # config edits. A profile that violated it would be a silent boot-loops-to-the-
    # installer trap, so assert it here too (belt to the builder's runtime `-lt`).
    try:
        sbp = int(d.get("SRC_BOOT_BOOTPRI", ""))
        tbp = int(d.get("TARGET_BOOT_BOOTPRI", ""))
        if sbp < tbp:
            ok("bootpri: source slice-3 = %d  <  target slice-3 = %d (id-6 wins post-install)"
               % (sbp, tbp))
        else:
            fail("SRC_BOOT_BOOTPRI (%d) is NOT < TARGET_BOOT_BOOTPRI (%d) -- the source "
                 "disk would keep winning the boot and the installed id-6 disk never runs"
                 % (sbp, tbp))
    except ValueError:
        fail("metal RAW profile lacks integer SRC_BOOT_BOOTPRI/TARGET_BOOT_BOOTPRI "
             "(got %r / %r)" % (d.get("SRC_BOOT_BOOTPRI"), d.get("TARGET_BOOT_BOOTPRI")))

    # N4: the builder implements --bootable + do_author_bootable, and needs its
    # own boot-chain framer.
    if not os.path.isfile(RAW_BUILDER):
        fail("raw source-disk builder missing: %s" % os.path.relpath(RAW_BUILDER, REPO))
        return
    b = open(RAW_BUILDER, encoding="utf-8").read()
    bcode = strip_full_comments(b)
    if "--bootable" in bcode and "do_author_bootable" in bcode and \
            re.search(r'if\s+\[\s+-n\s+"\$BOOTABLE"\s+\];\s+then\s+do_author_bootable', bcode):
        ok("build-raw-source.sh: --bootable routes --author to do_author_bootable")
    else:
        fail("build-raw-source.sh does not route --bootable to a do_author_bootable path")
    if not os.path.isfile(WRITE_BOOTCHAIN):
        fail("write-bootchain.py (the source boot-chain framer) missing")

    # N5: the fixed 5-slice layout is authored in order (sdpart.c order == PART
    # order): miniroot UNI\1, swap resv (STRUCTURAL), boot UNI\0 bootable, payload
    # UNI\1, raw DATA. Assert the load-bearing rdbtool add/addimg lines exist.
    layout_ok = (
        re.search(r'addimg\s+"\$work/miniroot\.img"\s+name=UNIX_Root\s+dostype=0x554e4901', bcode)
        and re.search(r'name=UNIX_Swap\s+\\?\s*\n?\s*dostype=0x72657376', bcode)
        and re.search(r'dostype=0x554e4900\s+bootable=1\s+pri="\$SRC_BOOT_BOOTPRI"\s+automount=1\s+boot_blocks=2', bcode)
        and re.search(r'addimg\s+"\$work/payload\.img"\s+name=InstPayload\s+dostype=0x554e4901', bcode)
        and re.search(r'name=AmixRawDist\s+\\?\s*\n?\s*dostype=0x44415441', bcode))
    if layout_ok:
        ok("5-slice layout authored in order: s1 miniroot(UNI\\1) s2 swap(resv) "
           "s3 boot(UNI\\0 bootable pri) s4 payload(UNI\\1) s5 raw(DATA)")
    else:
        fail("build-raw-source.sh --bootable does not author the fixed 5-slice layout "
             "(miniroot/swap/boot/payload/raw) via rdbtool addimg/add")

    # N5b: the swap placeholder is documented as STRUCTURAL (the slice-N==Nth-PART
    # trap) so nobody "cleans it up".
    if re.search(r'STRUCTURAL', b) and re.search(r'slice N ==? Nth PART|Nth PART block', b):
        ok("swap slice is documented STRUCTURAL (slice N == Nth PART block -- do not omit)")
    else:
        fail("build-raw-source.sh does not flag the swap slice as STRUCTURAL")

    # N6: the layout is FIXED -- the builder asserts SRC_PAYLOAD_SLICE=4 / RAW=5 and
    # SRC_BOOT_BOOTPRI < TARGET_BOOT_BOOTPRI (fail-closed).
    if re.search(r'\[\s+"\$SRC_PAYLOAD_SLICE"\s+=\s+4\s+\]', bcode) and \
            re.search(r'\[\s+"\$SRC_RAW_SLICE"\s+=\s+5\s+\]', bcode):
        ok("builder asserts the fixed --bootable slot numbers (payload=4, raw=5)")
    else:
        fail("builder does not fail closed on wrong --bootable slot numbers")
    if re.search(r'\[\s+"\$SRC_BOOT_BOOTPRI"\s+-lt\s+"\$TARGET_BOOT_BOOTPRI"\s+\]', bcode):
        ok("builder asserts SRC_BOOT_BOOTPRI < TARGET_BOOT_BOOTPRI at author time (fail closed)")
    else:
        fail("builder does not assert the source bootpri is below the target's")

    # N7: the source boot chain is FRAMED via write-bootchain.py (kernel + donor),
    # NOT re-implemented -- so the kerntools round-trip gate runs on the source disk.
    if re.search(r'write-bootchain\.py"?\s+--image\s+"\$TMPOUT"', bcode) and \
            re.search(r'--kernel\s+"\$SRC_KERNEL_BREL"', bcode) and \
            re.search(r'--donor\s+"\$SRC_BOOT_DONOR"', bcode):
        ok("slice-3 boot chain is framed by write-bootchain.py (kernel+donor => "
           "bootchain-verify round-trip runs on the SOURCE disk)")
    else:
        fail("build-raw-source.sh does not frame slice 3 via write-bootchain.py --kernel/--donor")

    # N8: the kernel identity gate -- the framed slice-3 kernel's sum -r must equal
    # the profile's SRC_KERNEL_BREL_SUMR (a wrong/renamed brel is caught).
    if re.search(r'SRC_KERNEL_BREL_SUMR', bcode) and \
            re.search(r'framed kernel sum -r', b):
        ok("builder gates the framed kernel's sum -r against SRC_KERNEL_BREL_SUMR")
    else:
        fail("builder does not gate the framed kernel identity (sum -r vs profile)")

    # N8b (Wave C2, re-pinned after plan B2): a medium SELECTS its slice-3 loader,
    # and the selection is threaded all the way to the sibling gate.
    #
    # Two profile keys, and the builder must read BOTH and refuse the pair:
    #   SRC_BOOT2_IDENTITY  a contract identity KEY (the 040/060 line: good_040,
    #                       promoted 2026-08-19) -> --boot2-identity
    #   SRC_BOOT2_SHA256    a LITERAL hash, the escape hatch for a loader that has
    #                       no contract row yet -> --expect-boot2-sha
    # Both empty (the 030 line) => byte-identical call, contract default `good`.
    # Accepting both at once would silently report on a loader the profile did not
    # name, so the refusal is part of the contract this audit pins.
    if re.search(r'SRC_BOOT2_IDENTITY="\$\(read_profile_key SRC_BOOT2_IDENTITY\)"', bcode) and \
            re.search(r'--boot2-identity \$\{?SRC_BOOT2_IDENTITY', bcode):
        ok("build-raw-source.sh reads SRC_BOOT2_IDENTITY and passes it as "
           "--boot2-identity to write-bootchain.py (the 040 line selects good_040 "
           "by contract key, so the hash lives in exactly one file)")
    else:
        fail("build-raw-source.sh does not thread SRC_BOOT2_IDENTITY -> "
             "--boot2-identity (the 040 line could not select good_040 and would "
             "be framed against the 030 loader)")
    if re.search(r'SRC_BOOT2_SHA256="\$\(read_profile_key SRC_BOOT2_SHA256\)"', bcode) and \
            re.search(r'--expect-boot2-sha \$\{?SRC_BOOT2_SHA256', bcode):
        ok("build-raw-source.sh still supports the literal SRC_BOOT2_SHA256 pin "
           "(--expect-boot2-sha) for a loader with no contract row yet")
    else:
        fail("build-raw-source.sh dropped the SRC_BOOT2_SHA256 -> "
             "--expect-boot2-sha escape hatch; the next pre-promotion loader "
             "would have nowhere to be named")
    if re.search(r'SRC_BOOT2_IDENTITY.*\n?.*SRC_BOOT2_SHA256.*\n?.*die ', bcode) or \
            re.search(r'BOTH SRC_BOOT2_IDENTITY', b):
        ok("build-raw-source.sh refuses a profile that sets BOTH the identity key "
           "and a literal sha (they pin the same thing)")
    else:
        fail("build-raw-source.sh accepts SRC_BOOT2_IDENTITY and SRC_BOOT2_SHA256 "
             "together -- one would silently win and the log would name the other")
    wb = strip_full_comments(open(WRITE_BOOTCHAIN, encoding="utf-8").read()) \
        if os.path.isfile(WRITE_BOOTCHAIN) else ""
    if re.search(r'"--identity"', wb) and re.search(r'"--boot2-sha"', wb) and \
            re.search(r'identity=\(args\.boot2_identity', wb) and \
            re.search(r'boot2_sha=\(args\.expect_boot2_sha', wb):
        ok("write-bootchain.py forwards the selection to the kerntools round-trip "
           "gate (--identity for a contract key, --boot2-sha for a literal pin) so "
           "both gates judge the SAME loader; a wrong donor boot2 is still caught "
           "-- NOT forwarded for --allow-unproven-boot2 alone")
    else:
        fail("write-bootchain.py does not forward the boot2 selection to its "
             "round-trip gate -- the sibling verifier would refuse the very loader "
             "the framing was told to expect")
    if re.search(r'args\.boot2_identity and args\.expect_boot2_sha', wb):
        ok("write-bootchain.py refuses --boot2-identity together with "
           "--expect-boot2-sha (mutually exclusive, as the sibling gate is)")
    else:
        fail("write-bootchain.py accepts --boot2-identity and --expect-boot2-sha "
             "together -- accept-and-ignore on the one question that decides which "
             "loader ships")
    # The DEFAULT is this repo's own constant, not whatever the contract's
    # default_identity happens to say: following the contract blindly would let an
    # edit in another repo silently re-point every 030 medium built here.
    b2id_p = os.path.join(REPO, "tools", "lib", "boot2id.py")
    if os.path.isfile(b2id_p):
        b2 = open(b2id_p, encoding="utf-8").read()
        if re.search(r'^DEFAULT_IDENTITY\s*=\s*"good"$', b2, re.M) and \
                re.search(r'contract_default\s*!=\s*DEFAULT_IDENTITY', b2):
            ok("tools/lib/boot2id.py: DEFAULT_IDENTITY is the constant `good` and "
               "a contract whose default_identity disagrees is a hard stop, not a "
               "silent follow")
        else:
            fail("tools/lib/boot2id.py does not pin DEFAULT_IDENTITY=`good` with a "
                 "contract cross-check -- a contract edit elsewhere could re-point "
                 "every 030 medium built here")
        if re.search(r'"wrong-proven"', b2):
            ok("boot2id.classify diagnoses 'the OTHER proven loader' as its own "
               "verdict (contract unknown_policy: it must be NAMED, not reported "
               "as an unrecognised blob)")
        else:
            fail("boot2id.classify folds a wrong-but-proven loader into 'unknown' "
                 "-- a wrong donor would read as a corrupt one")
    else:
        fail("tools/lib/boot2id.py missing -- the shared boot2 identity resolver "
             "both writers gate against")

    # N8c (Wave C2): the slice-1 miniroot read-back accepts a UFS miniroot (the
    # 040/060 line). It dispatches on the image's OWN superblock
    # (rootfs-type.identify), never a flag, so a ufs miniroot is never walked as s5
    # and the s5 arm is byte-behaviourally unchanged. This lives inside the author
    # step's python heredoc, which strip_full_comments removes, so match RAW `b`.
    if re.search(r'rootfs_type\.identify\(mr\)', b) and \
            re.search(r'mr_kind == "ufs"', b) and \
            re.search(r'ufs\.read_dir\(img, ufs\.ROOT_INO', b):
        ok("slice-1 read-back dispatches s5/ufs on the miniroot's own superblock "
           "(the 040/060 line's UFS miniroot is accepted; s5 arm unchanged)")
    else:
        fail("build-raw-source.sh slice-1 read-back is still s5-only -- a UFS "
             "miniroot (040/060 line) would fail the author-side gate")

    # N9: the on-box + host-side SMOKE exists (miniroot read-only member spot-check
    # and boot-slice host re-attestation) and there is NO bench boot attempt.
    #
    # ★ Wave C3: the smoke's `mount -F` is DERIVED, not literal. It read `-F s5`
    # until 2026-08-19, which on the 040/060 line fails at the MOUNT
    # (MRMOUNT_FAILED) -- an error that reads as "the image is broken" when the
    # truth is "the reader was told the wrong filesystem". MR_FSTYPE now comes off
    # the same INSTALL_CPU key the miniroot glob extension does, exactly as
    # install.sh derives MINIROOT_FSTYPE, so the miniroot's filesystem and the CPU
    # line stay ONE fact. The check demands the derivation AND its use: a file that
    # computed MR_FSTYPE and then still mounted a literal would pass a use-only
    # check, and a file that mounted `-F $MR_FSTYPE` without ever setting it would
    # pass a derivation-only one.
    def _mrfs_derived(src):
        """The three facts that make the smoke's -F follow the CPU line, not luck:
        the s5 FLOOR (an --author/--populate run whose profile omits INSTALL_CPU
        stays on s5), the 040/060 ARM, and the USE at the mount."""
        return bool(re.search(r'^MR_FSTYPE=s5\b', src, re.M)
                    and re.search(r'040\|060\)\s+_mrext=ufsimg;\s+MR_FSTYPE=ufs', src)
                    and re.search(r'\*\)\s+_mrext=s5img;\s+MR_FSTYPE=s5', src)
                    and re.search(r'mount\s+-F\s+\$MR_FSTYPE\s+-r\b', src))

    if re.search(r'MRSMOKE_DONE', b) and _mrfs_derived(b) \
            and re.search(r'boot slice 3 .*re-attestation|boot slice 3 VERIFIED host-side', b):
        ok("--populate --bootable smokes the miniroot (ro member spot-check, -F "
           "DERIVED from INSTALL_CPU) + boot slice (host re-attestation); no bench boot")
    else:
        fail("build-raw-source.sh --populate --bootable lacks the miniroot + boot-slice smoke")
    # Each half of that derivation must actually be load-bearing. Three plausible
    # wrong versions, two of them edits somebody would make believing they were
    # simplifying:
    for label, broken in (
        ("the smoke mount reverted to the hardcoded literal `-F s5` (right on the "
         "030 line, and the 040/060 line's UFS miniroot then fails at the mount)",
         re.sub(r'mount -F \$MR_FSTYPE -r', 'mount -F s5 -r', b)),
        ("the 040/060 arm of the MR_FSTYPE derivation left at s5 (the glob would "
         "still pick the .ufsimg miniroot, and the smoke would mount it as s5)",
         re.sub(r'(040\|060\) _mrext=ufsimg; MR_FSTYPE=)ufs', r'\1s5', b)),
        ("MR_FSTYPE defaulting to ufs instead of s5 (an --author/--populate run "
         "with no INSTALL_CPU -- i.e. every 030 profile -- would mount its s5 "
         "miniroot as ufs)",
         re.sub(r'^MR_FSTYPE=s5\b', 'MR_FSTYPE=ufs', b, flags=re.M)),
    ):
        if broken == b:
            fail("negative fixture did not modify build-raw-source.sh at all (%s)" % label)
        elif _mrfs_derived(broken):
            fail("audit N9 does NOT fire on: %s" % label)
        else:
            ok("N9 fires on: %s" % label)
    if re.search(r'NO boot attempt on the bench', b):
        ok("builder documents that the disk's BOOT is NOT proven on the bench (metal-only)")
    else:
        skip("builder does not explicitly state the no-bench-boot rule (docs cover it)")


# ---------------------------------------------------------------------------
# O. W6-I updbootpart -- the on-box boot-slice reframe tool (kernel upgrade)
# ---------------------------------------------------------------------------
# payload/updbootpart is the on-box finisher for "kernel upgrade via a package":
# `updbootpart --backup` -> `pkgadd KERNBENCH` -> `updbootpart` reframes the UNI\0
# boot slice from the freshly-landed /stand/unix so the next cold boot runs the new
# kernel. install.sh lays it onto every fresh target at /usr/sbin/updbootpart --
# additive, NOT a package member. ★ W5.5: it is STAGED ON THE MEDIUM at
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
#     0755), fails closed on pre-W5.5 media, and carries no here-doc at all;
#   * strip_heredocs still works, proven with fixtures (audit Z's here-doc law, now
#     ZERO bytes for every miniroot script, is what keeps the helper needed).

# updbootpart runs on the FULL installed target; these are the tools it deliberately
# uses that the thin miniroot lacks (documented, and NOT granted to install.sh), plus
# makeiblk = /stand/makeiblk, invoked cwd-relative as ./makeiblk.
UPDBOOT_EXTRA = {"sum", "wc", "cmp", "pkgparam", "makeiblk", "devnm"}
# pre-POSIX pitfalls that STILL apply on the target's 1991 SVR4 sh -- everything in
# PATTERNS EXCEPT the `wc` rule (wc is present on the full installed box).
TARGET_PATTERNS = [(p, why) for (p, why) in PATTERNS if r'\bwc\b' != p]


def _updboot_softened(text):
    """Offending line if any command in updbootpart is softened with a
    `|| true`/`|| :`/`|| warn`/`|| echo` that would swallow a nonzero exit (the
    fail-OPEN trap). `|| die`, `|| exit`, `|| { dumplog; die ...}` are fail-CLOSED and
    fine. Comment lines stripped first."""
    for l in strip_full_comments(text).splitlines():
        if re.search(r'\|\|\s*(true|:|warn\b|echo\b)\b', l):
            return l.strip()
    return None


def _updboot_tool_violations(text, proto_tools):
    """Tool allowlist for the TARGET script: like tool_violations, but normalises a
    cwd-relative `./makeiblk` to its basename first (makeiblk is a documented extra)."""
    funcnames = _defined_funcs(text)
    bad = []
    for w in command_words(text):
        norm = w[2:] if w.startswith("./") else w
        if _classify(norm, funcnames, proto_tools, UPDBOOT_EXTRA) is not None:
            bad.append(w)
    return bad


def _updboot_prologue(text):
    """updbootpart's prologue -- everything from `PROG=updbootpart` down to the end
    of the hexval() helper. That is PROG/STAND/msg/warn/die/sumr/is_num and the
    trap, EXTRACTED rather than transcribed, so the rollback test below runs the
    tool's real helpers (a `sumr` that stopped stripping the block count would fail
    the test instead of quietly agreeing with a copy of itself)."""
    m = re.search(r'(?ms)^PROG=updbootpart$.*?^\}$\n(?=\n# -{10,}\n# 0\. parse)', text)
    return m.group(0) if m else None


def _updboot_ksum_and_rollback(text):
    """Sections 3 and 4 -- `resolve the EXPECTED kernel sum` and `--rollback` -- as
    ONE runnable snippet, cut from the `# 3.` banner to just before the `5. GATES`
    banner.

    ★ THE CUT IS DELIBERATELY ORDER-AGNOSTIC, and that is what makes the test
    non-vacuous. Anchoring the start on `EXPECT_KSUM="$KSUM"` instead would, on the
    PRE-FIX tool (rollback first, ksum resolution second), have excluded the rollback
    block entirely -- and "/stand/unix was left untouched" is trivially true of a
    snippet that contains no `cp`. Cutting by SECTION NUMBER captures both arms in
    whatever order they appear, so the pre-fix tool runs its copy, and the assertions
    below actually judge it."""
    m = re.search(r'(?ms)^# -{10,}\n# 3\..*?(?=\n# -{10,}\n# 5\. GATES)', text)
    return m.group(0) if m else None


def _updboot_devderive(text):
    """The devnm -> ROOTSPEC (vfstab only cross-checked) -> CN/CN_VAL block, cut from the
    `ROOTSPEC=` assignment to just before the boot-node existence checks. Extracted, not
    transcribed, so a regression in the REAL regex fails this test rather than a copy of
    it agreeing with itself."""
    m = re.search(r'(?ms)^ROOTSPEC=`/etc/devnm /.*?^BOOT_RAW="/dev/rdsk/c\$\{CN\}d0s3"$', text)
    return m.group(0) if m else None


def _updboot_boot2gate(text):
    """The two BOOT2_SUMR pins and the `5c` boot2-loader gate, as a runnable pair."""
    pins = re.search(r'(?ms)^BOOT2_SUMR=\d+.*?^BOOT2_SUMR_040=\d+', text)
    # NB: end the cut on the die message, not on the first column-0 `fi` -- the
    # is_num block that classifies the loader closes with one of those, and cutting
    # there would hand the test a snippet that decides nothing and prints nothing.
    gate = re.search(r'(?ms)^kboot2=`sumr .*?refusing to frame"\nfi$', text)
    if not pins or not gate:
        return None
    return pins.group(0) + "\n" + gate.group(0)


def _run_devderive(rootspec, vfroot=None):
    """Run the tool's REAL device-derivation with `/etc/devnm /` stubbed to name
    `rootspec` as the mounted root, against a fixture vfstab whose "/" row is `vfroot`
    (default: the same device). Returns (rc, cn, cn_val, stderr)."""
    tool = open(UPDBOOTPART, encoding="utf-8").read()
    pro, blk = _updboot_prologue(tool), _updboot_devderive(tool)
    if pro is None or blk is None:
        return None
    d = workpath("devderive")
    os.makedirs(d, exist_ok=True)
    vf = os.path.join(d, "vfstab")
    with open(vf, "w") as fh:
        fh.write("#device\tdevice\tmount\n%s\t/dev/rdsk/x\t/\tufs\t1\tno\t-\n"
                 % (rootspec if vfroot is None else vfroot))
    stub = "devnm_stub() { %s }\n" % ('echo "%s /";' % rootspec if rootspec else "return 1;")
    scr = os.path.join(d, "dd.sh")
    with open(scr, "w") as fh:
        fh.write(pro + "\nVFSTAB=\"%s\"\n" % vf + stub
                 + blk.replace("/etc/devnm /", "devnm_stub") + "\necho \"CN=$CN CN_VAL=$CN_VAL\"\n")
    r = subprocess.run(["sh", scr], capture_output=True, text=True)
    cn = cnv = None
    m = re.search(r'CN=(\S*) CN_VAL=(\S*)', r.stdout)
    if m:
        cn, cnv = m.group(1), m.group(2)
    return r.returncode, cn, cnv, r.stderr


def _run_boot2gate(sumr_value):
    """Run the REAL 5c boot2 gate with sumr() stubbed to one value.
    Returns (rc, stdout, stderr)."""
    tool = open(UPDBOOTPART, encoding="utf-8").read()
    pro, gate = _updboot_prologue(tool), _updboot_boot2gate(tool)
    if pro is None or gate is None:
        return None
    d = workpath("boot2gate")
    os.makedirs(d, exist_ok=True)
    stand = os.path.join(d, "stand")
    os.makedirs(stand, exist_ok=True)
    open(os.path.join(stand, "boot2.boot"), "w").write("x")
    scr = os.path.join(d, "b2.sh")
    with open(scr, "w") as fh:
        fh.write(pro + "\nSTAND=\"%s\"\nsumr() { echo %s; }\n" % (stand, sumr_value) + gate + "\n")
    r = subprocess.run(["sh", scr], capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _run_rollback(label, oldunix, unix, ksum, mode="rollback"):
    """Run updbootpart's real ksum-resolution + rollback arms against a fixture
    /stand, with `sh`. Returns (rc, stdout, stderr, unix_bytes_after)."""
    tool = open(UPDBOOTPART, encoding="utf-8").read()
    pro = _updboot_prologue(tool)
    arms = _updboot_ksum_and_rollback(tool)
    if pro is None or arms is None:
        return None
    stand = workpath("stand_%s" % label)
    os.makedirs(stand, exist_ok=True)
    if oldunix is not None:
        with open(os.path.join(stand, "OLDunix"), "wb") as fh:
            fh.write(oldunix)
    with open(os.path.join(stand, "unix"), "wb") as fh:
        fh.write(unix)
    hp = workpath("rollback_%s.sh" % label)
    with open(hp, "w") as fh:
        fh.write(pro
                 + '\nSTAND=%s\nMODE=%s\nPKG=\nKSUM=%s\n' % (stand, mode, ksum)
                 + arms
                 + '\necho REACHED-THE-REFRAME-GATES\n')
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    r = subprocess.run([sh, hp], capture_output=True, text=True)
    with open(os.path.join(stand, "unix"), "rb") as fh:
        after = fh.read()
    return r.returncode, r.stdout, r.stderr, after


def _heredoc_body(driver_src, delim="UPDBOOTPART_EOF"):
    """The literal body install.sh emits between `<<'DELIM'` and the closing DELIM."""
    m = re.search(r"<<'%s'\n(.*?)\n%s\n" % (delim, delim), driver_src, re.S)
    return (m.group(1) + "\n") if m else None


def audit_updbootpart():
    head("O. W6-I updbootpart -- on-box boot-slice reframe tool (kernel upgrade via package)")
    if not os.path.isfile(UPDBOOTPART):
        fail("payload/updbootpart missing: %s" % os.path.relpath(UPDBOOTPART, REPO))
        return
    tool = open(UPDBOOTPART, encoding="utf-8").read()
    code = strip_full_comments(tool)

    # O1: pre-POSIX (target set -- wc allowed) + sh -n parse.
    hits = [(why, m.group(0)) for pat, why in TARGET_PATTERNS
            for m in re.finditer(pat, code)]
    if hits:
        for why, tok in hits:
            fail("updbootpart: pre-POSIX violation %r (%s)" % (tok, why))
    else:
        ok("updbootpart: no $(...), $(( )), export VAR=val, [[ ]], or local "
           "(wc is allowed on the full target)")
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    if subprocess.call([sh, "-n", UPDBOOTPART]) == 0:
        ok("updbootpart: %s -n clean" % sh)
    else:
        fail("updbootpart: %s -n parse failed" % sh)

    # O2: TARGET-tool allowlist (proto + documented full-box extras + ./makeiblk).
    proto_tools = load_proto_tools()
    if proto_tools is None:
        fail("miniroot.proto not found -- cannot derive the tool allowlist")
    else:
        words = list(command_words(tool))
        need = {"dd", "cat", "cp", "expr", "sum", "cmp", "pkgparam", "wc"}
        miss = need - set(w[2:] if w.startswith("./") else w for w in words)
        if miss:
            fail("allowlist parser is not exercising updbootpart (vacuity guard): "
                 "missing %s" % sorted(miss))
        else:
            ok("parser exercises updbootpart (%d cmds incl dd/cat/cp/expr/sum/cmp/"
               "pkgparam/wc)" % len(words))
        bad = _updboot_tool_violations(tool, proto_tools)
        if bad:
            fail("updbootpart references tool(s) outside proto + extras %s: %s"
                 % (sorted(UPDBOOT_EXTRA), ", ".join(sorted(set(bad)))))
        else:
            ok("updbootpart: every command is a builtin, a proto binary, a defined "
               "function, or an extra %s / ./makeiblk" % sorted(UPDBOOT_EXTRA))

    # O3: FAIL-CLOSED gates -- KSUM, boot2 loader, readback cmp each die; no softening.
    for needle, desc in [
        (r'die\s+"kernel identity gate FAILED', "KSUM gate dies on mismatch"),
        (r'die\s+"boot2 loader gate FAILED', "boot2-loader gate dies on mismatch"),
        (r'die\s+"READBACK MISMATCH', "readback cmp dies on any diff"),
        (r'die\s+"no expected kernel sum', "reframe refuses without an expected KSUM"),
    ]:
        if re.search(needle, code):
            ok("fail-closed: %s" % desc)
        else:
            fail("updbootpart missing fail-closed gate: %s" % desc)
    soft = _updboot_softened(tool)
    if soft:
        fail("updbootpart SOFTENS a command (fail-open `|| true`/`|| :`/...): %s" % soft)
    else:
        ok("no `|| true`/`|| :`/`|| warn`/`|| echo` softening anywhere in updbootpart")

    # O3b: --rollback GATES BEFORE IT WRITES. A gate that fires after the write is
    # not a gate, and this one did: MEASURED 2026-08-15, a --backup had rotated a
    # truncated /stand/unix into OLDunix and `--rollback --ksum 55482` printed
    # "restoring ... (sum -r 61907)" and only THEN "STOP: kernel identity gate
    # FAILED" -- leaving /stand/unix corrupted on the box, saved only by the fact
    # that it was still running off the intact boot frame. These checks RUN the
    # tool's own ksum-resolution + rollback arms against a fixture /stand, so the
    # assertion is what the code does, not what it looks like.
    idx_gate = code.find('$STAND/OLDunix sum -r')
    idx_cp = code.find('cp "$STAND/OLDunix" "$STAND/unix"')
    if idx_gate >= 0 and idx_cp >= 0 and idx_gate < idx_cp:
        ok("rollback ORDER: the OLDunix identity gate is textually before the "
           "`cp OLDunix unix` (write-last)")
    else:
        fail("rollback ORDER: the OLDunix identity gate does not precede the copy "
             "(gate@%d, cp@%d) -- a refusal would corrupt /stand/unix" % (idx_gate, idx_cp))

    GOOD = b"GOOD-KERNEL-ELF" * 64
    TRUNC = b"TRUNCATED"
    good_sum = subprocess.run(["sum", "-r"], input=GOOD, capture_output=True).stdout.split()[0].decode()
    # (1) THE DEFECT: OLDunix does not match the expected sum. /stand/unix must be
    #     byte-identical afterwards, and the STOP message must be the one operators
    #     already know.
    r = _run_rollback("badold", TRUNC, GOOD, good_sum)
    if r is None:
        fail("could not extract updbootpart's prologue / ksum+rollback arms -- the "
             "rollback ordering test cannot run (that is a FAIL, not a skip)")
    else:
        rc, out, err, after = r
        if rc != 0 and "STOP: kernel identity gate FAILED" in err:
            ok("rollback with a wrong-sum OLDunix EXITS NONZERO with the STOP "
               "kernel-identity message")
        else:
            fail("rollback with a wrong-sum OLDunix did not STOP (rc=%d, err=%r)"
                 % (rc, err.strip()))
        if after == GOOD:
            ok("rollback with a wrong-sum OLDunix leaves /stand/unix BYTE-UNTOUCHED "
               "(%d bytes, unchanged) -- the 2026-08-15 landmine cannot be re-laid"
               % len(after))
        else:
            fail("rollback with a wrong-sum OLDunix OVERWROTE /stand/unix (%d bytes "
                 "-> %d) -- this is the defect itself" % (len(GOOD), len(after)))
        if "REACHED-THE-REFRAME-GATES" not in out:
            ok("a refused rollback never reaches the reframe gates")
        else:
            fail("a refused rollback fell through to the reframe")
    # (2) the HAPPY path still works -- a gate that only ever refuses is no better
    #     than one that never does.
    r = _run_rollback("goodold", GOOD, b"NEW-KERNEL", good_sum)
    if r is not None:
        rc, out, err, after = r
        if rc == 0 and after == GOOD and "REACHED-THE-REFRAME-GATES" in out:
            ok("rollback with a MATCHING OLDunix restores it over /stand/unix and "
               "falls through to the reframe gates")
        else:
            fail("rollback with a matching OLDunix did not restore + continue "
                 "(rc=%d, unix==OLDunix: %s, err=%r)"
                 % (rc, after == GOOD, err.strip()))
    # (3) no expected sum at all: it must refuse BEFORE the copy too (this arm is
    #     what moving the resolution above the rollback block bought).
    r = _run_rollback("noksum", GOOD, b"NEW-KERNEL", "")
    if r is not None:
        rc, out, err, after = r
        if rc != 0 and "no expected kernel sum" in err and after == b"NEW-KERNEL":
            ok("`--rollback` with neither --ksum nor --pkg refuses BEFORE the copy "
               "-- /stand/unix untouched (fail closed)")
        else:
            fail("`--rollback` without an expected sum did not refuse before the "
                 "copy (rc=%d, unix=%r)" % (rc, after[:32]))

    # O3b: BEHAVIOURAL -- the card-1 root and the 040 loader, run through the tool's
    # OWN code rather than asserted about its text. These three defects shipped
    # together and each one alone is enough to stop a kernel install on a ced0s1
    # image, which is what the card-3 hand-over disks are:
    #   (A) the controller regex was decimal-only, so `ced0s1` yielded an EMPTY CN
    #       and the tool refused to guess -- correct behaviour on a wrong reading;
    #   (B) the boot2 gate pinned only `good` (14193), so a `good_040` slice (27860)
    #       was refused with a message that named the WRONG culprit as fact;
    #   (C) the ROOTDEV gate compared a hexval'd id (14) against the CN STRING ("e").
    for spec, want_cn, want_val, why in (
            ("/dev/dsk/c6d0s1", "6", "6",  "the 030 card-0 root still parses (no regression)"),
            ("/dev/dsk/ced0s1", "e", "14", "a card-1 root parses, and CN_VAL is its NUMERIC value"),
            ("/dev/dsk/c0d0s1", "0", "0",  "card 0 parses"),
            ("/dev/dsk/cfd0s1", "f", "15", "the top of the nibble parses")):
        got = _run_devderive(spec)
        if got is None:
            fail("could not extract updbootpart's device-derivation block")
            break
        rc, cn, cnv, err = got
        if rc == 0 and cn == want_cn and cnv == want_val:
            ok("updbootpart %s: %s -> CN=%s CN_VAL=%s" % (why, spec, cn, cnv))
        else:
            fail("updbootpart device-derivation wrong for %s: rc=%d CN=%r CN_VAL=%r (%s)"
                 % (spec, rc, cn, cnv, err.strip()[:120]))
    # and it still REFUSES what is not a cNd0s1 with a single hex N
    for spec in ("/dev/dsk/c6d0s3", "/dev/dsk/cgd0s1", "/dev/dsk/c10d0s1", "/dev/dsk/hd0"):
        got = _run_devderive(spec)
        if got and got[0] != 0:
            ok("updbootpart REFUSES a root device it cannot read: %s" % spec)
        else:
            fail("updbootpart ACCEPTED a bad root device %s (rc=%s CN=%r)"
                 % (spec, got[0] if got else "?", got[1] if got else "?"))
    # D-2 (RTH1, 2026-10-05): the root is the MOUNTED one (`/etc/devnm /`), not vfstab's
    # install-time "/" row. A moved disk (vfstab c6d0s1, mounted c2d0s1) frames onto c2d0s3
    # and says so; no devnm answer refuses.
    got = _run_devderive("/dev/dsk/c2d0s1", vfroot="/dev/dsk/c6d0s1")
    if got and got[0] == 0 and got[1] == "2" and "a moved disk" in got[3]:
        ok("updbootpart on a MOVED disk (vfstab c6d0s1, mounted c2d0s1) frames c2d0s3 and warns")
    else:
        fail("updbootpart did not follow the mounted root on a moved disk: %r" % (got,))
    got = _run_devderive("", vfroot="/dev/dsk/c6d0s1")
    if got and got[0] != 0 and "devnm" in got[3]:
        ok("updbootpart REFUSES when /etc/devnm names no root (never falls back to vfstab)")
    else:
        fail("updbootpart did not refuse an empty devnm answer: %r" % (got,))
    # the boot2 gate: BOTH proven loaders pass, anything else is refused as UNPROVEN
    for val, name in ((14193, "good"), (27860, "good_040")):
        got = _run_boot2gate(val)
        if got and got[0] == 0 and name in got[1]:
            ok("updbootpart boot2 gate ACCEPTS the proven loader %s (sum -r %d)" % (name, val))
        else:
            fail("updbootpart boot2 gate rejected the proven loader %s (%d): %r"
                 % (name, val, (got[2] if got else "extract failed")[:160]))
    got = _run_boot2gate(12345)
    if got and got[0] != 0 and "unproven" in got[2] and "name-based" not in got[2]:
        ok("updbootpart boot2 gate REFUSES an unrecognised loader as UNPROVEN, without "
           "asserting which specific loader it is (the contract's unknown_policy)")
    else:
        fail("updbootpart boot2 gate did not refuse an unknown loader correctly: %r"
             % ((got[2] if got else "extract failed")[:200]))

    # O4: derives the boot slice from the mounted root (NOT hardcoded), ./makeiblk, boot2
    # fingerprint 14193, frame-to-temp-then-readback-cmp, exact pipeline shape.
    checks = [
        (r'/etc/vfstab', "reads /etc/vfstab (a cross-check only)"),
        (r'ROOTSPEC=`/etc/devnm /', "derives the root from the MOUNTED root (`/etc/devnm /`, D-2)"),
        (r'done\s*<\s*"\$VFSTAB"', "parses the vfstab `/` line in a read loop"),
        (r"expr\s+\"\$ROOTSPEC\"\s+:\s+'/dev/dsk/c\\\(", "extracts controller N from the root device (never hardcoded)"),
        (r'BOOT_BLK="/dev/dsk/c\$\{CN\}d0s3"', "boot slice = cNd0s3 built from the derived N"),
        (r'\./makeiblk\s+boot2\.boot', "invokes ./makeiblk boot2.boot (cwd-relative)"),
        (r'\./makeiblk\s+unix', "invokes ./makeiblk unix"),
        (r'cat\s+boot1\.boot', "frames boot1.boot | iblk boot2 | boot2 | iblk unix | unix"),
        (r'dd\s+conv=sync\s+of="\$FRAME"', "frames to a TEMP file first (conv=sync)"),
        (r'dd\s+if="\$FRAME"\s+of="\$BOOT_BLK"', "dd's the temp frame to the boot slice"),
        (r'cmp\s+"\$FRAME"\s+"\$BACK"', "reads the slice BACK and cmp's it byte-for-byte"),
        (r'BOOT2_SUMR=14193', "pins the flags-based boot2 fingerprint sum -r 14193 (`good`)"),
        (r'BOOT2_SUMR_040=27860', "pins the 040/060 flags-based loader sum -r 27860 (`good_040`)"),
        (r"c\\\(\[0-9a-fA-F\]", "matches a HEX controller digit (card 1 is `ced0s1`, never c14d0)"),
        (r'CN_VAL', "keeps a NUMERIC controller value for comparisons (paths use the string)"),
        (r'\[ "\$rid" = "\$CN_VAL" \]', "compares the decoded ROOTDEV id against CN_VAL, one base"),
        (r'sync\s*\n\s*sync', "sync; sync after the slice write"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok("updbootpart %s" % desc)
        else:
            fail("updbootpart does NOT: %s" % desc)
    # NO hardcoded slice device (a literal /dev/dsk/c<digit>d0s...): the N must come
    # from vfstab. The device strings must use ${CN}, never a baked-in controller id.
    if re.search(r'/dev/r?dsk/c[0-9]', code):
        fail("updbootpart hardcodes a /dev/*dsk/c<digit>... device -- N must come from vfstab")
    else:
        ok("updbootpart hardcodes no /dev/*dsk/c<digit> device (slice built from $CN)")

    # O5: DRIFT-LOCK -- the BUILDER stages the tracked master onto the medium, byte
    # for byte, and STOPS if the staged copy differs (W5.5). Until this wave the
    # drift lock was free: the body lived inside install.sh as a quoted here-doc and
    # this audit diffed the two. Moving it onto the medium bought back 16 of the
    # install floppy's 46 free blocks (measured: the 1991 sh materialized it as
    # /tmp/sh<pid>, 15,427 B, for the life of the install shell) -- and the lock has
    # to be re-established mechanically, in the one place that can still see both
    # files: the builder.
    driver_src = open(DRIVER, encoding="utf-8").read()
    if os.path.isfile(ISO_BUILDER):
        b = open(ISO_BUILDER, encoding="utf-8").read()
        staged = re.search(r'cp\s+-p\s+"\$repo/payload/updbootpart"\s+"\$STAGE/updbootpart"', b)
        gated = re.search(r'cmp\s+-s\s+"\$repo/payload/updbootpart"\s+"\$STAGE/updbootpart"\s+\|\|', b)
        chm = re.search(r'chmod\s+0755\s+"\$STAGE/updbootpart"', b)
        if staged and gated and chm:
            ok("drift-lock: build-install-iso.sh stages payload/updbootpart at "
               "/install/updbootpart and STOPS unless the staged copy is byte-identical "
               "(%d bytes)" % len(tool))
        else:
            fail("build-install-iso.sh does not stage payload/updbootpart with a "
                 "byte-identity gate (cp=%s cmp=%s chmod=%s)"
                 % (bool(staged), bool(gated), bool(chm)))
    else:
        fail("tools/build-install-iso.sh not found -- cannot check the staging drift lock")

    # O6: the driver INSTALLS it from the MEDIUM -- cp $INST/updbootpart ->
    # /usr/sbin/updbootpart, chmod 0755, and it fails closed on media mastered
    # before W5.5 (no silent no-updbootpart install). Still additive: NOT a package
    # member, so attestation (a function of what pkgadd RECORDED) is unmoved.
    dcode = strip_full_comments(driver_src)
    if re.search(r'cp\s+"\$INST/updbootpart"\s+"\$TARGET/usr/sbin/updbootpart"', dcode) and \
            re.search(r'chmod\s+0755\s+"\$TARGET/usr/sbin/updbootpart"', dcode):
        ok("install.sh copies $INST/updbootpart -> /usr/sbin/updbootpart + chmod 0755")
    else:
        fail("install.sh does not cp + chmod /usr/sbin/updbootpart in the arm step")
    if re.search(r'\[\s+-f\s+"\$INST/updbootpart"\s+\]\s+\|\|\s+die', dcode):
        ok("install.sh FAILS CLOSED when the medium carries no updbootpart "
           "(pre-W5.5 media cannot silently install without it)")
    else:
        fail("install.sh does not die when $INST/updbootpart is missing")
    if re.search(r"<<'UPDBOOTPART_EOF'", driver_src):
        fail("the updbootpart here-doc is BACK in install.sh -- that is 16 of the "
             "install floppy's 46 free blocks, on every install (W5.5)")
    else:
        ok("updbootpart is no longer a driver here-doc: it rides the medium, so the "
           "880-block install floppy pays nothing for it")

    # O7: strip_heredocs is still exercised. install.sh no longer HAS a here-doc, so
    # the old non-vacuity probe (target-only tokens hidden from the miniroot audits)
    # cannot fire on the real driver any more; the fixtures below are what keep the
    # helper honest, and the here-doc law in audit Z is what keeps it needed.
    # fixtures: a here-doc body is stripped; text without a here-doc is untouched.
    heredoc_fx = ("a=1\ncat > /t <<'EOF'\nsed -e s/x/y/\nwc -c foo\nEOF\nb=2\n")
    stripped = strip_heredocs(heredoc_fx)
    if "sed" not in stripped and "wc" not in stripped and "a=1" in stripped and "b=2" in stripped:
        ok("strip_heredocs fixture: body (sed/wc) removed, surrounding code kept")
    else:
        fail("strip_heredocs fixture failed: %r" % stripped)
    no_heredoc = "x=1\nsed -e s/a/b/ f\n"
    if strip_heredocs(no_heredoc) == no_heredoc:
        ok("strip_heredocs is a no-op on text with no here-doc")
    else:
        fail("strip_heredocs altered text that has no here-doc")


# ---------------------------------------------------------------------------
# P. METAL-FIX.4 zen0 bring-up laydown -- driver lays /etc/rc2.d/S99zen for metal
#    (zen0) profiles, IP-parameterized; the profiles carry the right IP + interface
# ---------------------------------------------------------------------------
# A base install ships only the STOCK a2065/aen0 inet userland, inert on metal (no
# A2065 board) -- so a fresh metal install has NO working ethernet. Metal ethernet is
# z3660eth, interface zen0 (cdevsw major 51 -- renumbered from 48 on 2026-07-30; media
# mastered from this tree REQUIRE kernels that register z3660eth at 51, the P5.4 set).
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
# P-3 (address by card, 2026-09-26) adds the text tools of the lookup/hosts step
# (sed/grep/awk/cmp -- all on the installed target) and `uname` for the nodename.
ZEN_EXTRA = {"slink", "ifconfig", "route", "sleep", "sed", "grep", "awk", "cmp", "uname"}
_ZEN_TESTIP = "203.0.113.7"          # deliberately NOT .38/.39 -- a hardcoded IP mismatches
_ZEN_TESTMASK = "255.255.0.0"
_ZEN_TESTGW = "203.0.113.254"        # deliberately NOT .2.1 -- a hardcoded gateway mismatches
_ZEN_TESTDOM = "example.org"      # deliberately NOT example.net
ZENSELFTEST = os.path.join(REPO, "tools", "zen-conf-selftest.sh")


def _zen_master_concrete(ip=_ZEN_TESTIP, mask=_ZEN_TESTMASK, gw=_ZEN_TESTGW,
                         dom=_ZEN_TESTDOM):
    """The tracked payload/S99zen master with its @FB_IP@/@FB_NETMASK@/@FB_GATEWAY@/
    @FB_DOMAIN@ placeholders resolved to concrete values (a valid, runnable S99zen)."""
    txt = open(ZENHOOK, encoding="utf-8").read()
    return (txt.replace("@FB_IP@", ip).replace("@FB_NETMASK@", mask)
            .replace("@FB_GATEWAY@", gw).replace("@FB_DOMAIN@", dom))


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


def audit_zen_bringup():
    head("P. METAL-FIX.4 zen0 bring-up laydown: driver lays /etc/rc2.d/S99zen (IP-parameterized) + metal profiles")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)

    # P1: the arm step lays S99zen via emit_zen_hook, guarded on FB_ETHER_IF=zen0,
    # chmod 0744, refuses an empty FB_IP, and is EMITTED (never copied from the CD).
    if re.search(r'if\s+\[\s+"\$FB_ETHER_IF"\s+=\s+zen0\s+\];\s*then', code) and \
            re.search(r'emit_zen_hook\s+"\$TARGET/etc/rc2\.d/S99zen"', code):
        ok("arm step lays /etc/rc2.d/S99zen via emit_zen_hook, guarded on FB_ETHER_IF=zen0 "
           "(driver-written; not a package member)")
    else:
        fail("arm step does not lay /etc/rc2.d/S99zen via emit_zen_hook under an "
             "FB_ETHER_IF=zen0 guard")
    if re.search(r'chmod\s+0744\s+"\$TARGET/etc/rc2\.d/S99zen"', code):
        ok("S99zen laid down chmod 0744")
    else:
        fail("S99zen is not chmod 0744 in the arm step")
    if re.search(r'\[\s+-n\s+"\$FB_IP"\s+\]\s+\|\|\s+die', code):
        ok("driver refuses a zen0 profile with an empty FB_IP (fail closed -- the bring-up "
           "needs a literal IP)")
    else:
        fail("driver does not fail closed on a zen0 profile with an empty FB_IP")
    # W1: the default route's gateway is FB_GATEWAY (it was the literal 192.0.2.1
    # inside emit_zen_hook). Same fail-closed shape as FB_IP -- an empty value would
    # write `route add default  1`.
    if re.search(r'\[\s+-n\s+"\$FB_GATEWAY"\s+\]\s+\|\|\s+die', code):
        ok("driver refuses a zen0 profile with an empty FB_GATEWAY (fail closed -- the "
           "laydown writes a literal default route)")
    else:
        fail("driver does not fail closed on a zen0 profile with an empty FB_GATEWAY")
    if re.search(r'route add default 192\.168\.2\.1', code):
        fail("emit_zen_hook still HARDCODES the 192.0.2.1 default route -- W1 makes it "
             "the profile key FB_GATEWAY")
    else:
        ok("emit_zen_hook carries no hardcoded 192.0.2.1 default route (FB_GATEWAY)")
    if re.search(r'cp\s+\S*S99zen', code) or re.search(r'/cdrom\S*S99zen', code):
        fail("install.sh COPIES S99zen from the CD -- it must be driver-EMITTED (additive)")
    else:
        ok("S99zen is driver-emitted, not a CD copy (additive, not a package member)")

    # P2: DRIFT-LOCK -- emit_zen_hook run with a test IP/mask reproduces payload/S99zen
    # (placeholders resolved) byte-for-byte, and a SECOND IP flows through ($FB_IP, not
    # hardcoded).
    func = None
    if not os.path.isfile(ZENHOOK):
        fail("zen hook master missing: %s" % os.path.relpath(ZENHOOK, REPO))
    else:
        try:
            func = _extract_func(driver_src, "emit_zen_hook")
        except StopIteration:
            fail("could not extract emit_zen_hook() from the driver")
        if func:
            ref = _zen_master_concrete().encode()
            rc, emitted = _emit_zen(func, _ZEN_TESTIP, _ZEN_TESTMASK)
            if rc == 0 and emitted is not None and emitted == ref:
                ok("drift-lock: emit_zen_hook reproduces payload/S99zen byte-for-byte with "
                   "FB_IP/FB_NETMASK substituted (%d bytes)" % len(ref))
            else:
                fail("drift-lock FAILED: emit_zen_hook output != master with placeholders "
                     "resolved (rc=%d, emitted=%d bytes, ref=%d bytes)"
                     % (rc, len(emitted) if emitted else 0, len(ref)))
            rc2, emitted2 = _emit_zen(func, "203.0.113.9", "255.240.0.0", "203.0.113.1",
                                      "lan.test")
            want2 = _zen_master_concrete("203.0.113.9", "255.240.0.0", "203.0.113.1",
                                         "lan.test").encode()
            if rc2 == 0 and emitted2 == want2 and emitted2 and \
                    b"203.0.113.9" in emitted2 and b"203.0.113.1" in emitted2 and \
                    b"DOMAIN=lan.test" in emitted2:
                ok("emit_zen_hook tracks $FB_IP AND $FB_GATEWAY (a second distinct "
                   "IP/gateway pair flows through -- neither is hardcoded)")
            else:
                fail("emit_zen_hook does not track $FB_IP/$FB_GATEWAY (hardcoded?) -- the "
                     "second pair did not flow through")

        # P2b (P-15 I2): the ADDRESS-LESS form (FB_IP + FB_GATEWAY empty) is the master
        # plus exactly the leave-down guard after the zen.conf block and a gateway-guarded
        # route line -- nothing else moves, so the LAN form above stays byte-identical.
        if func:
            rc3, emitted3 = _emit_zen(func, "", "", "", "")
            want3 = _zen_master_concrete("", "", "", "")
            fi_route = "fi\n(\n  sleep 5\n"
            guard = ('fi\nif [ -z "$ADDR" ]; then\n\techo "S99zen: zen0 has no address -- '
                     'left down (the first-boot dialog sets one, or FALLBACK= in '
                     '/etc/rc2.d/S99zen)"\n\texit 0\nfi\n(\n  sleep 5\n')
            rline = "  /usr/sbin/route add default $GATEWAY 1\n"
            if want3.count(fi_route) == 1 and want3.count(rline) == 1:
                want3 = want3.replace(fi_route, guard).replace(
                    rline, '  [ -n "$GATEWAY" ] && /usr/sbin/route add default $GATEWAY 1\n')
                if rc3 == 0 and emitted3 == want3.encode():
                    ok("address-less emit_zen_hook = master + the leave-down guard + a "
                       "gateway-guarded route, nothing else (%d bytes)" % len(emitted3))
                else:
                    fail("address-less emit_zen_hook differs from master + guard (rc=%d)" % rc3)
            else:
                fail("cannot locate the zen.conf-block end / route line in payload/S99zen")

    # P3: the master itself -- pre-POSIX, parses, self-heals /dev/zen0, backgrounds,
    # literal IP (never uname -n), target-tool allowlist.
    if os.path.isfile(ZENHOOK):
        concrete = _zen_master_concrete()
        raw = open(ZENHOOK, encoding="utf-8").read()
        hits = [(why, m.group(0)) for pat, why in PATTERNS
                for m in re.finditer(pat, strip_full_comments(concrete))]
        if hits:
            for why, tok in hits:
                fail("S99zen: pre-POSIX violation %r (%s)" % (tok, why))
        else:
            ok("S99zen: no $(...), $(( )), export VAR=val, wc, [[ ]], or local")
        sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
        hp = workpath("s99zen.concrete")
        with open(hp, "w") as fh:
            fh.write(concrete)
        if subprocess.call([sh, "-n", hp]) == 0:
            ok("S99zen: %s -n clean (placeholders resolved)" % sh)
        else:
            fail("S99zen: %s -n parse failed" % sh)
        if re.search(r'\[\s+-c\s+/dev/zen0\s+\]\s+\|\|\s+mknod\s+/dev/zen0\s+c\s+51\s+0', raw):
            ok("S99zen self-heals /dev/zen0 (mknod c 51 0 if absent -- cdevsw major 51)")
        else:
            fail("S99zen does not self-heal /dev/zen0 via `mknod /dev/zen0 c 51 0` "
                 "(major renumbered 48 -> 51 on 2026-07-30 -- media from this tree need "
                 "51-registering kernels)")
        if re.search(r'mknod\s+/dev/zen0\s+c\s+48\s+0', raw):
            fail("S99zen still carries the RETIRED major 48 (`mknod /dev/zen0 c 48 0`) -- "
                 "z3660eth renumbered to 51 on 2026-07-30")
        else:
            ok("S99zen carries no stale `c 48 0` node (the retired major)")
        if re.search(r'\)\s*>\s*/tmp/zen-bringup\.log\s+2>&1\s+&', raw):
            ok("S99zen backgrounds the whole bring-up (a datapath fault can never hang the boot)")
        else:
            fail("S99zen does not background the bring-up (a datapath fault could hang boot)")
        if re.search(r'slink\s+addaen\s+/dev/zen0\s+zen0', raw) and \
                re.search(r'ifconfig\s+zen0\s+\S+\s+netmask\s+\S+\s+up\s+-trailers', raw):
            ok("S99zen brings zen0 up the SVR4.0 way (slink addaen + ifconfig ... up -trailers, no plumb)")
        else:
            fail("S99zen missing the slink addaen + ifconfig zen0 ... up -trailers bring-up")
        # W1: the master's default route is a PLACEHOLDER, resolved at laydown --
        # a literal here would silently re-hardcode the bench/metal LAN gateway.
        # P-3 moved the four laydown values into parameter LINES at the top
        # (FALLBACK=/NETMASK=/GATEWAY=/DOMAIN=), which the route line reads.
        if re.search(r'(?m)^GATEWAY=@FB_GATEWAY@$', raw) and \
                re.search(r'route\s+add\s+default\s+\$GATEWAY\s+1', raw):
            ok("S99zen master parameterizes the default route (@FB_GATEWAY@)")
        else:
            fail("S99zen master does not carry the @FB_GATEWAY@ default-route "
                 "placeholder (W1 de-hardcodes 192.0.2.1)")
        if re.search(r'route\s+add\s+default\s+192\.168\.2\.1', raw):
            fail("S99zen master still hardcodes the 192.0.2.1 default route")
        else:
            ok("S99zen master carries no hardcoded 192.0.2.1 default route")
        if re.search(r'(?m)^GATEWAY=%s$' % re.escape(_ZEN_TESTGW), concrete) and \
                re.search(r'route\s+add\s+default\s+\$GATEWAY\s+1', concrete):
            ok("S99zen resolves to a concrete default route when the placeholder is filled")
        else:
            fail("S99zen's resolved form has no concrete `route add default <gw> 1`")
        # the ifconfig/route CODE (comments stripped) must not reach for a NAME --
        # `ifconfig zen0 \`uname -n\`` stalls boot on SVR4.0 via a DNS lookup. P-3
        # legitimately READS the nodename (uname -n) and SETS it (uname -S) for the
        # address-by-card step; neither feeds ifconfig, which takes $ADDR -- a
        # dotted quad the lookup validated, or the laydown's literal FALLBACK.
        code_lines = strip_full_comments(concrete).splitlines()
        named = [l for l in code_lines
                 if re.search(r'\b(ifconfig|route)\b', l) and
                 re.search(r'uname|`|\$\(|\$NAME|\$NEW|\$OLD', l)]
        unames = [l.strip() for l in code_lines if re.search(r'\buname\b', l)]
        bad_unames = [l for l in unames if not re.search(r'\buname\s+-[nS]\b', l)]
        if named or bad_unames:
            fail("S99zen CODE feeds a NAME to ifconfig/route or uses uname beyond -n/-S "
                 "(uname -n in the ifconfig stalls boot on SVR4.0): %s" % (named + bad_unames))
        else:
            ok("S99zen ifconfig/route take a literal IP (never uname -n); uname only reads/sets "
               "the nodename (%d use(s))" % len(unames))
        if re.search(r'ifconfig\s+zen0\s+\$ADDR\s+netmask\s+\$NETMASK\s+up\s+-trailers', raw) \
                and re.search(r'(?m)^FALLBACK=@FB_IP@$', raw) \
                and re.search(r'(?m)^NETMASK=@FB_NETMASK@$', raw) \
                and re.search(r'(?m)^DOMAIN=@FB_DOMAIN@$', raw) \
                and re.search(r'(?m)^ADDR=\$FALLBACK$', raw):
            ok("S99zen: the laydown address is FALLBACK=@FB_IP@ and ifconfig takes $ADDR "
               "(= FALLBACK unless /etc/inet/zen.conf names this card)")
        else:
            fail("S99zen: missing the FALLBACK=@FB_IP@/NETMASK=/DOMAIN= parameter lines or "
                 "the `ADDR=$FALLBACK` default feeding `ifconfig zen0 $ADDR`")
        proto_tools = load_proto_tools()
        if proto_tools is None:
            fail("miniroot.proto not found -- cannot check S99zen tool references")
        else:
            words = list(command_words(concrete))
            basewords = set(w.rsplit("/", 1)[-1] for w in words)
            need = {"mknod", "slink", "ifconfig", "route", "sleep"}
            miss = need - basewords
            if miss:
                fail("allowlist parser is not exercising S99zen (vacuity guard): missing %s"
                     % sorted(miss))
            else:
                ok("parser exercises S99zen (%d cmds incl mknod/slink/ifconfig/route/sleep)"
                   % len(words))
            bad = [w for w in words
                   if _classify(w, _defined_funcs(concrete), proto_tools, ZEN_EXTRA) is not None]
            if bad:
                fail("S99zen references tool(s) outside proto + net extras %s: %s"
                     % (sorted(ZEN_EXTRA), ", ".join(sorted(set(bad)))))
            else:
                ok("S99zen: every command is a builtin, a proto binary, or a net extra %s"
                   % sorted(ZEN_EXTRA))

    # P4: the metal profiles carry FB_IP=192.0.2.39 + FB_ETHER_IF=zen0; EVERY zen0
    # profile has a non-empty FB_IP; the bench profiles keep aen0 (untouched).
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    if not profs:
        fail("no profiles found under %s" % os.path.relpath(PROFILES_DIR, REPO))
        return
    zen_profiles = []
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        if d.get("FB_ETHER_IF") == "zen0":
            zen_profiles.append(pf)
            # P-15 I2: the public flavor (dialog armed) lays down an ADDRESS-LESS
            # S99zen -- both keys empty, the dialog's 8a re-point fills them.
            if d.get("FIRSTBOOT_DIALOG") == "y" and not d.get("FB_IP"):
                if d.get("FB_GATEWAY"):
                    fail("%s: dialog flavor with FB_GATEWAY=%s but no FB_IP -- a route "
                         "without an address" % (pf, d["FB_GATEWAY"]))
                else:
                    ok("%s: zen0 dialog flavor, address-less laydown (FB_IP/FB_GATEWAY "
                       "empty; zen0 down until the first-boot dialog sets them)" % pf)
                continue
            if d.get("FB_IP"):
                ok("%s: FB_ETHER_IF=zen0 with non-empty FB_IP=%s" % (pf, d["FB_IP"]))
            else:
                fail("%s: FB_ETHER_IF=zen0 but FB_IP is EMPTY -- firstboot bakes no hosts line "
                     "and the zen0 bring-up has no IP (METAL-FIX.4)" % pf)
            if d.get("FB_GATEWAY"):
                ok("%s: FB_ETHER_IF=zen0 with non-empty FB_GATEWAY=%s"
                   % (pf, d["FB_GATEWAY"]))
            else:
                fail("%s: FB_ETHER_IF=zen0 but FB_GATEWAY is EMPTY -- the laydown would "
                     "write a broken `route add default  1` (W1)" % pf)
    for name in ("metal-a4000-z3660.profile", "metal-a4000-z3660-raw.profile"):
        p = os.path.join(PROFILES_DIR, name)
        if not os.path.isfile(p):
            fail("metal profile missing: %s" % name)
            continue
        d = _parse_profile(p)
        if d.get("FB_ETHER_IF") == "zen0" and d.get("FB_IP") == "192.0.2.39":
            ok("%s: FB_ETHER_IF=zen0 FB_IP=192.0.2.39 (the established metal box address; .38 is the bench emulator)"
               % name)
        else:
            fail("%s: expected FB_ETHER_IF=zen0 + FB_IP=192.0.2.39, got FB_ETHER_IF=%r FB_IP=%r"
                 % (name, d.get("FB_ETHER_IF"), d.get("FB_IP")))
    if not zen_profiles:
        fail("no profile carries FB_ETHER_IF=zen0 -- the metal networking laydown is a dead letter")
    for name in ("bench-a3000-a4091.profile", "bench-a3000-a4091-raw.profile"):
        p = os.path.join(PROFILES_DIR, name)
        if os.path.isfile(p):
            d = _parse_profile(p)
            if d.get("FB_ETHER_IF") == "aen0":
                ok("%s keeps FB_ETHER_IF=aen0 (a2065 bench path untouched by the zen0 laydown)" % name)
            else:
                fail("%s: FB_ETHER_IF=%r -- the bench profile must stay aen0 (no zen0 laydown "
                     "on the a2065 bench)" % (name, d.get("FB_ETHER_IF")))

    # P5 (P-3 address by card): the lookup/hosts/mkconf/start logic of the master is
    # exercised end to end by tools/zen-conf-selftest.sh (fake MACs, a sandboxed
    # boot path, dash when present); FB_ZEN_CARDS reaches firstboot.conf and
    # firstboot.sh renders it through S99zen's own mkconf; zenmac is laid down.
    if os.path.isfile(ZENSELFTEST):
        r = subprocess.run(["sh", ZENSELFTEST], capture_output=True, text=True)
        last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
        if r.returncode == 0:
            ok("zen-conf-selftest green: %s" % last)
        else:
            fail("zen-conf-selftest FAILED: %s" % (r.stdout + r.stderr).strip()[-600:])
    else:
        fail("tools/zen-conf-selftest.sh missing")
    if re.search(r'echo\s+"FB_ZEN_CARDS=\\"\$FB_ZEN_CARDS\\""', driver_src):
        ok("install.sh writes FB_ZEN_CARDS (quoted) into firstboot.conf")
    else:
        fail("install.sh does not pass FB_ZEN_CARDS through to firstboot.conf (quoted)")
    if re.search(r'run\s+cp\s+"\$INST/zenmac"\s+"\$TARGET/usr/amiga/bin/zenmac"', code):
        ok("install.sh lays /usr/amiga/bin/zenmac down from the medium (zen0 MAC reader)")
    else:
        fail("install.sh does not lay down /usr/amiga/bin/zenmac")
    fbsrc = open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"),
                 encoding="utf-8").read()
    if re.search(r'S99zen\s+mkconf\s+\$FB_ZEN_CARDS\s*>\s*/etc/inet/zen\.cf\$\$', fbsrc) \
            and re.search(r'\[\s+-f\s+/etc/inet/zen\.conf\s+\]', fbsrc):
        ok("firstboot.sh renders FB_ZEN_CARDS via `S99zen mkconf` into a NEW /etc/inet/zen.conf "
           "(an existing table is never overwritten)")
    else:
        fail("firstboot.sh does not render /etc/inet/zen.conf via S99zen mkconf (once)")
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        cards = d.get("FB_ZEN_CARDS", "")
        if not cards:
            continue
        badw = [w for w in cards.split()
                if not re.match(r'^(([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|default)='
                                r'\d+\.\d+\.\d+\.\d+(=[A-Za-z0-9][-A-Za-z0-9]*)?$', w)]
        if d.get("FB_ETHER_IF") != "zen0":
            fail("%s: FB_ZEN_CARDS on a non-zen0 profile (it would never be read)" % pf)
        elif badw:
            fail("%s: FB_ZEN_CARDS has malformed word(s) %s (want MAC=ADDR=NAME / default=ADDR)"
                 % (pf, badw))
        else:
            ok("%s: FB_ZEN_CARDS well-formed (%d row(s))" % (pf, len(cards.split())))

    # NEGATIVE FIXTURES -- the hardcoded-IP + empty-FB_IP checks must actually fire.
    if os.path.isfile(ZENHOOK) and func:
        # a hardcoded IP in the emit would break the drift-lock: prove a master-vs-
        # hardcoded mismatch is detectable.
        hard = _zen_master_concrete().replace(_ZEN_TESTIP, "192.0.2.39").encode()
        if hard != _zen_master_concrete().encode():
            ok("negative fixture: a hardcoded-IP S99zen differs from the FB_IP-parameterized "
               "master (the drift-lock would catch it)")
        else:
            fail("negative fixture broken: a hardcoded-IP substitution did not change the master")
    neg = re.sub(r'\n[^\n]*\[\s+-n\s+"\$FB_IP"\s+\]\s+\|\|\s+die[^\n]*', "", code)
    if not re.search(r'\[\s+-n\s+"\$FB_IP"\s+\]\s+\|\|\s+die', neg):
        ok("negative fixture fires: a driver with no `[ -n FB_IP ] || die` zen0 gate is flagged")
    else:
        fail("negative fixture did NOT fire: the empty-FB_IP gate check is broken")


# ---------------------------------------------------------------------------
# Q. P5.4-FT /stand framing tools -- driver-guaranteed updbootpart framing sources
# ---------------------------------------------------------------------------
# updbootpart's reframe pipeline needs /stand/boot1.boot, /stand/boot2.boot and an
# executable local /stand/makeiblk (its gate 5a fails closed without them). On
# M-RUN4b (M-RUN-P5.4, 2026-08) the KERN-package handoff on a fresh metal base-8
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


def _staged_pin_check(relpath, want_sum, want_size):
    """Check one staged file against its pin. Returns None when the staged tree
    is absent (caller reports ONE skip); ok()/fail()s otherwise."""
    p = os.path.join(STAGE_DIR, relpath)
    if not os.path.isfile(p):
        fail("staged tree present but %s is MISSING from it" % relpath)
        return True
    data = open(p, "rb").read()
    got = bsd_sum_r(data)
    if got == want_sum and len(data) == want_size:
        ok("staged %s: sum -r %05d / %d bytes == pin" % (relpath, got, len(data)))
    else:
        fail("staged %s: sum -r %05d / %d bytes != pin %05d / %d"
             % (relpath, got, len(data), want_sum, want_size))
    return True


def audit_framing_tools():
    head("Q. P5.4-FT /stand framing tools: driver lays boot1.boot + makeiblk (updbootpart gate 5a)")
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

    # Q4: the media staging pins the bytes fail-closed and pulls makeiblk from the
    # gated 2.1c extraction.
    if not os.path.isfile(ISO_BUILDER):
        fail("build-install-iso.sh missing -- cannot check the staging pins")
    else:
        bsrc = open(ISO_BUILDER, encoding="utf-8").read()
        for pat, desc in [
            (r'sum_gate\s+"\$STAGE/stand/boot1\.boot"\s+41892\s+1024',
             "staging pins boot1.boot 41892/1024 (fail-closed sum_gate)"),
            (r'sum_gate\s+"\$STAGE/stand/makeiblk"\s+58483\s+14924',
             "staging pins makeiblk 58483/14924 (fail-closed sum_gate)"),
            (r'extract-21c-payload\.sh', "staging runs the gated 2.1c extractor"),
            (r'cp\s+"\$CORE_T/stand/boot1\.boot"',
             "boot1.boot sourced from the extracted core tree (the 2.1 original)"),
            (r'cp\s+"\$repo/payload/21c/stand/makeiblk"',
             "makeiblk sourced from payload/21c (the 2.1c patched build)"),
        ]:
            if re.search(pat, bsrc):
                ok(desc)
            else:
                fail("build-install-iso.sh does NOT: %s" % desc)
    if os.path.isfile(EXTRACT_21C):
        esrc = open(EXTRACT_21C, encoding="utf-8").read()
        if re.search(r'\[stand/makeiblk\]=58483', esrc) and \
                re.search(r'\[stand/makeiblk\]=14924', esrc):
            ok("extract-21c-payload.sh pins makeiblk 58483/14924")
        else:
            fail("extract-21c-payload.sh does not pin makeiblk 58483/14924")
    else:
        fail("tools/extract-21c-payload.sh missing (the gated 2.1c extraction)")

    # Q5: LIVE staged bytes (when a staged /install tree exists). SKIP, never a
    # silent pass, when there is no staged tree on this host.
    if os.path.isdir(os.path.join(STAGE_DIR, "stand")):
        for rel, (ws, wz) in sorted(FT_PINS.items()):
            _staged_pin_check(rel, ws, wz)
    else:
        skip("no staged /install tree at %s -- staged framing-tool bytes not "
             "verified here (build-install-iso.sh --stage-only produces one)"
             % os.path.relpath(STAGE_DIR, REPO))

    # NEGATIVE FIXTURE -- a driver stripped of the laydown is flagged.
    neg = re.sub(r'\n[^\n]*cp\s+"\$INST/stand/boot1\.boot"[^\n]*', "", code)
    if not re.search(r'cp\s+"\$INST/stand/boot1\.boot"\s+"\$TARGET/stand/boot1\.boot"', neg):
        ok("negative fixture fires: a driver without the boot1.boot laydown is flagged")
    else:
        fail("negative fixture did NOT fire: the boot1.boot laydown check is broken")


# ---------------------------------------------------------------------------
# R. P5.4 syslog unit -- base-8 ships no unit; the driver lays down the 2.1c one
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
    head("R. P5.4 syslog unit: driver lays the ENABLED 2.1c unit (base-8 ships none)")
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

    # R4: the STAGING transform + pins in build-install-iso.sh -- one vendor
    # `exit` pre-gated, transformed to `#exit`, verified, the pid file trusted only when
    # `ps -p` shows a syslogd (stale-pid fix), and pinned 28819/967;
    # conf + daemon pinned too.
    if not os.path.isfile(ISO_BUILDER):
        fail("build-install-iso.sh missing -- cannot check the syslog staging")
    else:
        bsrc = open(ISO_BUILDER, encoding="utf-8").read()
        for pat, desc in [
            (r"grep -c '\^exit\$'", "pre-gates the vendor copy (exactly ONE bare `exit`)"),
            (r"sed 's/\^exit\$/#exit/'", "comments the vendor `exit` (the §5 enablement) host-side"),
            (r"grep -q '\^exit\$' \"\$STAGE/syslog/syslogd\.init\"",
             "verifies NO live `exit` survives the transform"),
            (r'sum_gate\s+"\$STAGE/syslog/syslogd\.init"\s+28819\s+967',
             "pins the ENABLED init 28819/967"),
            (r"s=`ps -p \$pid 2> /dev/null \| grep syslogd`",
             "trusts /etc/syslog.pid only when ps shows a syslogd (an earlier boot's pid can be any process)"),
            (r'sum_gate\s+"\$STAGE/syslog/syslog\.conf"\s+63870\s+1928',
             "pins syslog.conf 63870/1928"),
            (r'sum_gate\s+"\$STAGE/syslog/syslogd"\s+53154\s+22728',
             "pins the 2.1c syslogd 53154/22728"),
        ]:
            if re.search(pat, bsrc):
                ok("staging %s" % desc)
            else:
                fail("build-install-iso.sh staging does NOT: %s" % desc)

    # R5: LIVE staged bytes (when a staged /install tree exists): pins + the
    # enabled-copy property. SKIP, never a silent pass, otherwise.
    if os.path.isdir(os.path.join(STAGE_DIR, "syslog")):
        for rel, (ws, wz) in sorted(SYSLOG_PINS.items()):
            _staged_pin_check(rel, ws, wz)
        sp = os.path.join(STAGE_DIR, "syslog", "syslogd.init")
        if os.path.isfile(sp):
            if _live_exit_check(open(sp, encoding="utf-8").read()):
                ok("staged syslogd.init is the ENABLED copy (no live `exit`, one `#exit`)")
            else:
                fail("staged syslogd.init still carries a live `exit` (or a bad transform) "
                     "-- fresh installs would ship a DEAD syslog unit")
    else:
        skip("no staged /install tree at %s -- staged syslog bytes not verified "
             "here (build-install-iso.sh --stage-only produces one)"
             % os.path.relpath(STAGE_DIR, REPO))

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
# S. W1 driver plumbing -- the input keys the interview will land in
# ---------------------------------------------------------------------------
# W1 turns the driver's remaining hardcodes into profile KEYS and restores two
# stock steps it had dropped, all non-interactively and all behaviour-preserving
# when the keys carry today's values. This audits each seam fail-closed:
#
#   S1 PROFILE BY PATH   -- install.sh accepts a profile by PATH as well as by
#      name, so the W2 interview can hand it /tmp/answers.profile (the medium is
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
#      applies them (that is W5); a firstboot that started applying DNS would be
#      caught here.
#   S8 KEY COVERAGE      -- every tracked profile carries every new key.

W1_KEYS = ["INSTALL_VERBOSE", "TARGET_ROOT_MB", "TARGET_SWAP_MB", "FB_TZ",
           "FB_GATEWAY", "FB_DNS1", "FB_DNS2", "FB_KMAP", "FB_REPO_URL"]

# The stage strings W1 takes VERBATIM from the original installer. The first two
# are echo lines in the stock /etc/profile (the stock install script itself); the
# third is amixpkg's per-package printf. All three live on the stock root floppy,
# so when that image is available they are checked against its actual bytes.
STOCK_STAGE_STRINGS = [
    "Making filesystems.  This will take a few minutes.",
    "Please wait while the partitions are checked...",
    "Installing %s",
]
STOCK_ROOT_ADF = os.path.join(REPO, "floppies", "orig", "amix_21_root.adf")


def _extract_span(src, start_prefix, end_prefix):
    """The lines from the first line starting with `start_prefix` through the
    closing `}` (column 0) of the block that starts with `end_prefix`."""
    lines = src.splitlines()
    i = next(k for k, l in enumerate(lines) if l.startswith(start_prefix))
    j = next(k for k, l in enumerate(lines) if l.startswith(end_prefix))
    jend = next(k for k in range(j + 1, len(lines)) if lines[k] == "}")
    return "\n".join(lines[i:jend + 1])


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


def _audit_w1_profile_path(code, driver_src):
    # the three resolution arms must be present in the source...
    arms = [
        (r'\*/\*\)\s*PROFILE_FILE="\$PROFILE_ARG"', "a '/'-bearing argument is a PATH"),
        (r'if\s+\[\s+-f\s+"\$PROFILE_ARG"\s+\]', "a bare argument naming an existing FILE is a path"),
        (r'PROFILE_FILE="\$INST/profiles/\$PROFILE_ARG\.profile"', "otherwise the NAME form (unchanged)"),
    ]
    for pat, desc in arms:
        if re.search(pat, code):
            ok("profile resolution: %s" % desc)
        else:
            fail("profile resolution missing: %s" % desc)
    # ...and the block must actually RESOLVE that way when run. The resolution is
    # a case/esac (not a {} block), so slice it from the assignment to its `esac`.
    m = re.search(r'PROFILE_ARG="\$1"\n.*?\nesac\n', driver_src, re.S)
    block = m.group(0) if m else None
    if not block:
        fail("could not extract the profile-resolution block from the driver")
        return
    d = os.path.join(workdir(), "profres")
    os.makedirs(os.path.join(d, "profiles"), exist_ok=True)
    open(os.path.join(d, "profiles", "byname.profile"), "w").write("PROFILE_NAME=byname\n")
    open(os.path.join(d, "bare.profile"), "w").write("PROFILE_NAME=bare\n")
    open(os.path.join(d, "answers.profile"), "w").write("PROFILE_NAME=answers\n")
    harness = ('INST="$1"\nshift\n' + block + '\necho "$PROFILE_FILE"\n')
    cases = [
        ("name form", ["byname"], os.path.join(d, "profiles", "byname.profile")),
        ("absolute path", [os.path.join(d, "answers.profile")],
         os.path.join(d, "answers.profile")),
        ("relative path with /", ["./answers.profile"], "./answers.profile"),
        ("bare existing filename", ["bare.profile"], "bare.profile"),
    ]
    for name, args, want in cases:
        r = subprocess.run(["/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh",
                            "-c", harness, "sh", d] + args,
                           capture_output=True, text=True, cwd=d)
        got = r.stdout.strip()
        if r.returncode == 0 and got == want:
            ok("profile-by-path resolves %-22s -> %s" % (name, got))
        else:
            fail("profile-by-path %s resolved to %r (want %r, rc=%d, err=%r)"
                 % (name, got, want, r.returncode, r.stderr.strip()))


def _audit_w1_log(code, driver_src):
    # structure
    checks = [
        (r'(?m)^LOGFILE=[ \t]*(#.*)?$', "LOGFILE starts EMPTY (the pre-mount window has no target to log to)"),
        (r'(?m)^RUNOUT=[ \t]*(#.*)?$', "RUNOUT (child-output scratch) starts empty"),
        (r'(?m)^VERBOSE=[ \t]*(#.*)?$', "VERBOSE starts empty (quiet is the default)"),
        (r'logline\(\)', "a logline helper exists"),
        (r'if\s+\[\s+-n\s+"\$LOGFILE"\s+\];\s*then\s*\n\s*echo\s+"\$\*"\s+>>\s+"\$LOGFILE"',
         "logline appends only when a log is open"),
        (r'msg\(\)\s+\{\s*echo\s+"\$PROG:\s+\$\*";\s*logline', "msg goes to console AND log"),
        (r'warn\(\)\s+\{[^\n]*logline', "warn goes to console AND log"),
        (r'die\(\)\s+\{[^\n]*logline', "die goes to console AND log"),
        (r'stage\(\)\s+\{\s*echo\s+"\$\*";\s*logline\s+"\$\*";\s*\}',
         "stage prints UNPREFIXED to console AND log (the stock voice)"),
        (r'runq\(\)', "a runq wrapper exists (routes child output, returns the rc)"),
        (r'run\(\)\s+\{\s*\n\s*runq\s+"\$@"\s+\|\|\s+die', "run delegates to runq and still dies"),
        (r'"\$@"\s+>\s+"\$RUNOUT"\s+2>&1', "runq captures child stdout+stderr to the scratch file"),
        (r'cat\s+"\$RUNOUT"\s+>>\s+"\$LOGFILE"', "runq appends the captured output to the log"),
        (r'LOGFILE="\$TARGET/var/adm/install\.log"', "the log is <target>/var/adm/install.log"),
        (r'\[\s+-d\s+"\$TARGET/var/adm"\s+\]\s+\|\|\s+run\s+mkdir\s+-p\s+"\$TARGET/var/adm"',
         "the log directory is mkdir'd (guarded) before the first append"),
        (r':\s*>\s*"\$LOGFILE"\s+\|\|\s+die', "the log is created fail-closed"),
        (r'RUNOUT="\$TARGET/tmp/\.runout\.\$\$"', "the scratch file lives under <target>/tmp"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok("install log: %s" % desc)
        else:
            fail("install log MISSING: %s" % desc)
    # there is no tee on the miniroot -- the driver must never reach for one
    if re.search(r'\btee\b', code):
        fail("driver references `tee` -- the miniroot has none (that is why runq "
             "cats a temp file twice)")
    else:
        ok("install log: no `tee` anywhere in the driver (miniroot has none)")
    # INSTALL_VERBOSE parsing: default n, y/n accepted, anything else dies
    if re.search(r'\[\s+-n\s+"\$INSTALL_VERBOSE"\s+\]\s+\|\|\s+INSTALL_VERBOSE=n', code) and \
            re.search(r'die\s+"profile INSTALL_VERBOSE=', code):
        ok("install log: INSTALL_VERBOSE defaults to n and fails closed on a bad value")
    else:
        fail("INSTALL_VERBOSE is not defaulted to n / does not fail closed on a bad value")
    # ORDER: mount -> open the log -> seed -> pkgadd loop
    i_mount = code.find('run /etc/mount "$ROOT_BLK"')
    i_open = code.find('LOGFILE="$TARGET/var/adm/install.log"')
    i_seed = code.find("seeding target root")
    i_order = code.find('done < "$ORDER"')
    if 0 <= i_mount < i_open < i_seed < i_order:
        ok("install log opens right after the target mount, before the seed and the "
           "package loop (pre-mount window is console-only by construction)")
    else:
        fail("install-log open is mis-ordered (mount@%d open@%d seed@%d loop@%d)"
             % (i_mount, i_open, i_seed, i_order))
    # the seed must NOT re-create $TARGET/tmp (the 1991 mkdir -p fails on an
    # existing leaf, and the log step already made it)
    m = re.search(r'run mkdir -p "\$TARGET/etc"[^\n]*', code)
    if m and '"$TARGET/tmp"' not in m.group(0):
        ok("install log: the seed no longer mkdir's <target>/tmp (the log step made it; "
           "the 1991 mkdir -p would fail on the existing leaf)")
    else:
        fail("the seed still mkdir's <target>/tmp after the log step created it -- "
             "the miniroot's mkdir -p returns 2 on an existing leaf (W5.4f)")
    # the opening marker must NAME the console-only pre-mount window
    if re.search(r'logline\s+"NOTE: the PRE-MOUNT window', code):
        ok("install log opens with the marker line declaring the pre-mount window")
    else:
        fail("the install log has no opening marker declaring the console-only "
             "pre-mount window")

    # --- BEHAVIOURAL: run the extracted helpers in both modes ---------------
    try:
        helpers = _extract_span(driver_src, "logline() {", "run() {")
    except StopIteration:
        fail("could not extract the logline..run helper block from the driver")
        return
    body = ('PROG=install.sh\nLOGFILE=\nRUNOUT=\n' + helpers +
            '\nLOGFILE="$1"\nRUNOUT="$2"\n: > "$LOGFILE"\n'
            'msg "hello"\nstage "Installing core"\nrun echo child-output\n'
            'runq false\necho "rc=$?"\n')
    for mode, vset in (("quiet", ""), ("verbose", "1")):
        logp = workpath("w1log_%s.txt" % mode)
        outp = workpath("w1out_%s.txt" % mode)
        script = ("VERBOSE=%s\n" % ('1' if vset else '')) + body
        r = _run_sh(script, [logp, outp])
        console = r.stdout
        log = open(logp).read() if os.path.isfile(logp) else ""
        want_log = ["install.sh: hello", "Installing core", "+ echo child-output",
                    "child-output", "+ false"]
        missing = [w for w in want_log if w not in log]
        if r.returncode == 0 and not missing:
            ok("install log (%s): the log captured stage messages, the `+ cmd` echoes "
               "and the child output" % mode)
        else:
            fail("install log (%s): log incomplete (rc=%d, missing %s)"
                 % (mode, r.returncode, missing))
        if mode == "quiet":
            if "Installing core" in console and "install.sh: hello" in console \
                    and "+ echo child-output" not in console \
                    and "child-output" not in console:
                ok("install log (quiet): console shows stage messages only -- the "
                   "`+ cmd` echo and the child output went to the log alone")
            else:
                fail("install log (quiet): console leaked child output or the `+ cmd` "
                     "echo: %r" % console)
        else:
            if "+ echo child-output" in console and "child-output" in console:
                ok("install log (verbose): console mirrors the `+ cmd` echo and the "
                   "child output (cat-twice, no tee)")
            else:
                fail("install log (verbose): console did not mirror the child output: %r"
                     % console)
    # a FAILING child is shown on the console in BOTH modes -- prove it in quiet
    logp = workpath("w1log_fail.txt")
    script = ("VERBOSE=\nPROG=install.sh\nLOGFILE=\nRUNOUT=\n" + helpers +
              '\nLOGFILE="$1"\nRUNOUT="$2"\n: > "$LOGFILE"\n'
              'runq sh -c "echo boom >&2; exit 7"\necho "rc=$?"\n')
    r = _run_sh(script, [logp, workpath("w1out_fail.txt")])
    if "boom" in r.stdout and "rc=7" in r.stdout:
        ok("install log (quiet): a FAILING child's output is still shown on the "
           "console, and runq returns its exit status (7)")
    else:
        fail("install log (quiet): a failing child's output/rc did not reach the "
             "console: %r" % r.stdout)


def _audit_w1_stage_strings(code):
    for s in STOCK_STAGE_STRINGS:
        if s == "Installing %s":
            hit = re.search(r'stage\s+"Installing \$pkg"', code)
            desc = 'stage "Installing $pkg"  (amixpkg\'s "Installing %s")'
        else:
            hit = re.search(r'stage\s+"%s"' % re.escape(s), code)
            desc = 'stage "%s"' % s
        if hit:
            ok("stock stage string used: %s" % desc)
        else:
            fail("driver does not emit the stock stage string: %s" % desc)
    if os.path.isfile(STOCK_ROOT_ADF):
        blob = open(STOCK_ROOT_ADF, "rb").read()
        bad = [s for s in STOCK_STAGE_STRINGS if s.encode("latin1") not in blob]
        if not bad:
            ok("all %d stage strings are VERBATIM in the stock root floppy "
               "(%s)" % (len(STOCK_STAGE_STRINGS),
                         os.path.relpath(STOCK_ROOT_ADF, REPO)))
        else:
            fail("stage string(s) not found verbatim in the stock root floppy: %s" % bad)
    else:
        skip("stock root floppy absent (%s) -- the stage strings are not checked "
             "against the original's bytes here"
             % os.path.relpath(STOCK_ROOT_ADF, REPO))


def _audit_w1_keymap(code, profiles):
    checks = [
        (r'KMAPDIR="\$TARGET/usr/amiga/lib/kmap"', "resolves the target kmap dir"),
        (r'if\s+\[\s+-n\s+"\$FB_KMAP"\s+\]\s+&&\s+\[\s+"\$FB_KMAP"\s+!=\s+usa\s+\];\s*then',
         "bakes only for a non-empty, non-`usa` FB_KMAP (stock: usa links nothing)"),
        (r'run rm -f "\$\{KMAPDIR:\?\}/default\.kmap"', "removes any existing default.kmap first (stock)"),
        (r'run ln "\$KMAPDIR/\$FB_KMAP" "\$KMAPDIR/default\.kmap"',
         "HARD-links the chosen map to default.kmap (stock `ln`, never `ln -s`)"),
        (r'\[\s+-f\s+"\$KMAPDIR/\$FB_KMAP"\s+\]\s+\|\|\s+die',
         "fails closed when the named map does not exist on the target"),
        (r'echo\s+"FB_KMAP=\$FB_KMAP"', "records FB_KMAP in firstboot.conf"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok("keymap bake: %s" % desc)
        else:
            fail("keymap bake MISSING: %s" % desc)
    if re.search(r'ln\s+-s\s+[^\n]*default\.kmap', code):
        fail("keymap bake uses `ln -s` -- stock used a HARD link (a dangling symlink "
             "would fail silently at /etc/sysinit)")
    else:
        ok("keymap bake: no `ln -s` (hard link only, as stock)")
    # the tracked profiles must all carry the key; a set value must be a real map
    valid = {"cdn", "ch1", "ch2", "d", "dk", "e", "f", "gb", "i", "n", "s",
             "usa", "usa0", "usa1", "usa2", ""}
    bad = ["%s=%r" % (pf, d.get("FB_KMAP")) for pf, d in profiles
           if "FB_KMAP" not in d or d.get("FB_KMAP") not in valid]
    if not bad:
        ok("every profile carries FB_KMAP and its value is a stock map or empty")
    else:
        fail("profile FB_KMAP problems: %s" % ", ".join(bad))
    # NEGATIVE FIXTURE
    neg = re.sub(r'\n[^\n]*run ln "\$KMAPDIR/\$FB_KMAP"[^\n]*', "", code)
    if not re.search(r'run ln "\$KMAPDIR/\$FB_KMAP" "\$KMAPDIR/default\.kmap"', neg):
        ok("negative fixture fires: a driver without the default.kmap link is flagged")
    else:
        fail("negative fixture did NOT fire: the keymap-link check is broken")


def _audit_w1_disksize(code, profiles, proto_tools):
    checks = [
        (r'PROBE_BLOCKS=`/etc/ddsize "\$DISK_RAW"', "probes the target with /etc/ddsize (the stock input)"),
        (r'is_num\s+"\$PROBE_BLOCKS"', "is_num-guards the probe (fail closed on an unreadable disk)"),
        (r'DISK_MB=`expr\s+"\$PROBE_BLOCKS"\s+/\s+"\$BLOCKS_PER_MB"`', "converts blocks -> MB (/2048)"),
        (r'(?m)^DISK_MB="\$TARGET_DISK_MB"', "a pinned TARGET_DISK_MB is taken first"),
        (r'\[\s+-n\s+"\$DISK_MB"\s+\]\s+\|\|\s+DISK_MB=100', "100 MB stays the last-resort fallback"),
        (r'msg\s+"disk size    : no TARGET_DISK_MB pinned -- probing',
         "announces the probe BEFORE calling it (a wedge is then diagnosable)"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok("disk size: %s" % desc)
        else:
            fail("disk size MISSING: %s" % desc)
    # ★ THE LOAD-BEARING ONE (bench finding 2026-08-11): a PINNED TARGET_DISK_MB
    # must SHORT-CIRCUIT the probe -- /etc/ddsize against /dev/rdsk/c6d0s0 WEDGED
    # the install on the bench rig (matrix 20260811-094255-cd: the driver printed
    # its banner, the kernel printed `a3091: 0x1 0 0x0`, and it never advanced;
    # install gate FAIL). There is no timeout tool on the miniroot, so a hang here
    # cannot be bounded -- the only safe posture is not to call it when a profile
    # already says the size. This check FIRES on an unconditional probe.
    m = re.search(r'(?m)^DISK_MB="\$TARGET_DISK_MB"\n'
                  r'if\s+\[\s+-n\s+"\$DISK_MB"\s+\];\s*then\n'
                  r'(?:.*\n)*?else\n'
                  r'(?:.*\n)*?\tPROBE_BLOCKS=`/etc/ddsize', code)
    if m:
        ok("disk size: a pinned TARGET_DISK_MB SHORT-CIRCUITS the probe -- ddsize is "
           "not called at all on the tracked profiles (bench: an unconditional probe "
           "wedged the install on the a3091 path)")
    else:
        fail("disk size: the /etc/ddsize probe is NOT inside the `TARGET_DISK_MB is "
             "empty` else-branch -- an unconditional probe WEDGED the bench install "
             "(a3091, matrix 20260811-094255-cd); it must never run when the profile "
             "pins the size")
    # exactly ONE ddsize INVOCATION (a backticked command substitution) -- the
    # other mentions are message text, which is fine and is what tells an operator
    # where a wedge happened.
    nprobe = len(re.findall(r'`\s*/etc/ddsize\b', code))
    if nprobe == 1:
        ok("disk size: exactly one /etc/ddsize INVOCATION in the driver (the other "
           "mentions are operator-facing message text)")
    else:
        fail("disk size: %d /etc/ddsize invocations in the driver -- there must be "
             "exactly one, inside the unpinned branch" % nprobe)
    if proto_tools and "ddsize" in proto_tools:
        ok("disk size: /etc/ddsize IS carried by the tracked miniroot.proto (the probe "
           "is not wishful thinking)")
    else:
        fail("disk size: the miniroot.proto does not carry ddsize -- the probe would "
             "fail on every install")
    # the size-override keys exist on every profile, and the tracked ones are EMPTY
    # (a non-empty value here would silently move the attested acceptance layout)
    bad = [pf for pf, d in profiles
           if "TARGET_ROOT_MB" not in d or "TARGET_SWAP_MB" not in d]
    if not bad:
        ok("every profile carries TARGET_ROOT_MB + TARGET_SWAP_MB")
    else:
        fail("profile(s) missing the size-override keys: %s" % ", ".join(bad))
    # an IMAGE_KIT=y profile's layout IS its product (the pre-installed images)
    nonempty = ["%s(root=%r swap=%r)" % (pf, d.get("TARGET_ROOT_MB"), d.get("TARGET_SWAP_MB"))
                for pf, d in profiles
                if (d.get("TARGET_ROOT_MB") or d.get("TARGET_SWAP_MB")) and d.get("IMAGE_KIT") != "y"]
    if not nonempty:
        ok("every tracked profile leaves the size overrides EMPTY -- the attested "
           "layouts are the stock arithmetic, unchanged")
    else:
        fail("tracked profile(s) pin a size override, which moves the attested "
             "layout: %s" % ", ".join(nonempty))


def _audit_w1_lostfound(code):
    checks = [
        (r'LOSTFOUND="\$TARGET/lost\+found"', "resolves <target>/lost+found"),
        (r'for i in 0 1 2 3 4 5 6 7 8 9; do', "iterates the stock 0-9 outer digits"),
        (r'for j in 0 1 2 3 4 5 6 7 8 9; do', "iterates the stock 0-9 inner digits"),
        (r'cp /dev/null "\$LOSTFOUND/\$i\$j"\s+\|\|\s+die',
         "creates each of the 100 slots with `cp /dev/null` (not `: >`, which only "
         "fires on the first loop iteration), fail-closed"),
        (r'\[\s+-f\s+"\$LOSTFOUND/99"\s+\]\s+\|\|\s+die',
         "ASSERTS a LAST-iteration slot exists (catches a create that lies)"),
        (r'rm -f "\$\{LOSTFOUND:\?\}/\$i\$j"\s+\|\|\s+die', "removes them again (an s5 directory keeps the space)"),
        (r'\[\s+-d\s+"\$LOSTFOUND"\s+\]', "only mkdir's the directory when it is absent"),
    ]
    for pat, desc in checks:
        if re.search(pat, code):
            ok("lost+found: %s" % desc)
        else:
            fail("lost+found MISSING: %s" % desc)
    # exactly 100 slots: two nested 0-9 loops for the create and two for the clear
    nloops = len(re.findall(r'for [ij] in 0 1 2 3 4 5 6 7 8 9; do', code))
    if nloops == 4:
        ok("lost+found: exactly two nested 0-9/0-9 loops (100 slots created, 100 removed)")
    else:
        fail("lost+found: expected 4 digit loops (create + clear), found %d" % nloops)
    # ORDER: after the package loop (the stock position), before the final fsck
    i_order = code.find('done < "$ORDER"')
    i_lf = code.find('LOSTFOUND="$TARGET/lost+found"')
    i_fsck = code.find("unmounting target and running a final fsck")
    if 0 <= i_order < i_lf < i_fsck:
        ok("lost+found preseed runs after the package transplant and before the "
           "final unmount/fsck (the stock position)")
    else:
        fail("lost+found preseed is mis-ordered (loop@%d preseed@%d fsck@%d)"
             % (i_order, i_lf, i_fsck))


def _audit_w1_dns(code, fb, profiles):
    if re.search(r'echo\s+"FB_DNS1=\$FB_DNS1"', code) and \
            re.search(r'echo\s+"FB_DNS2=\$FB_DNS2"', code):
        ok("DNS: install.sh records FB_DNS1 + FB_DNS2 in firstboot.conf")
    else:
        fail("DNS: install.sh does not record FB_DNS1/FB_DNS2 in firstboot.conf")
    # W1 was PLUMBING ONLY. W5 APPLIES the keys -- and the shape of that
    # application is the whole finding, because a HALF-applied DNS is the
    # 3-minutes-per-boot failure the grimoire measured. Required: all five parts
    # present, in ONE branch, gated on the dialog having configured the network
    # AND on a literal-IP (zen0) flavor, with aen0 refused OUT LOUD rather than
    # half-served.
    parts = [(r'>\s*/etc/resolv\.conf', "1 resolv.conf (nameservers only)"),
             (r'ln -f /usr/lib/libsockdns\.so /usr/lib/libsocket\.so',
              "2 the libsockdns relink (ln -f, atomic)"),
             (r'cp /etc/netconfig\.DNS /etc/netconfig',
              "3 the DNS transport table"),
             (r'cp /dev/null /etc/domain', "4 an EMPTY /etc/domain"),
             (r"sed 's/ifconfig lo0 localhost up/ifconfig lo0 127\.0\.0\.1 up/'",
              "5 the literal-IP loopback bring-up")]
    missing = [d for p, d in parts if not re.search(p, fb)]
    if not missing:
        ok("DNS: firstboot.sh applies ALL FIVE parts (%s)"
           % "; ".join(d for _, d in parts))
    else:
        fail("DNS: firstboot.sh applies only part of the enablement -- missing %s "
             "(a half-enabled resolver costs ~3 min on every boot)"
             % ", ".join(missing))
    if re.search(r'if\s+\[\s+-n\s+"\$FB_DNS1"\s+\];\s*then\s*\n\s*if\s+\[\s+"\$FB_ETHER_IF"\s+!=\s+zen0\s+\]', fb):
        ok("DNS: gated on FB_DNS1, and a non-zen0 flavor is refused FIRST "
           "(aen0's boot ifconfig lives in network-config, which is never edited)")
    else:
        fail("DNS: the FB_DNS1 branch does not refuse non-zen0 flavors up front")
    if re.search(r'if\s+\[\s+"\$FB_NET_CONFIGURED"\s+=\s+y\s+\];\s*then', fb):
        ok("DNS + the other network extras are gated on FB_NET_CONFIGURED=y, which "
           "only the first-boot dialog sets -- an unattended install is unchanged")
    else:
        fail("the network extras are not gated on FB_NET_CONFIGURED -- an "
             "unattended install would grow steps it never had")
    # the S69inet edit is IN PLACE: that file is a hard link to /etc/init.d/inetinit
    if re.search(r'>\s*/tmp/S69inet\.fb\$\$\s*\\\n\s*&&\s*cp /tmp/S69inet\.fb\$\$ /etc/rc2\.d/S69inet', fb):
        ok("DNS part 5 edits /etc/rc2.d/S69inet IN PLACE (sed to /tmp, `cp` back) -- "
           "it is one inode with /etc/init.d/inetinit; a mv would break the link")
    else:
        fail("DNS part 5 does not edit S69inet in place (cp back over the inode)")
    if re.search(r'mv\s+[^\n]*\s+/etc/rc2\.d/S69inet', fb):
        fail("DNS part 5 uses `mv` onto /etc/rc2.d/S69inet -- that breaks the hard "
             "link to /etc/init.d/inetinit and the edit silently stops applying")
    else:
        ok("no `mv` onto S69inet anywhere in firstboot.sh")
    bad = [pf for pf, d in profiles if "FB_DNS1" not in d or "FB_DNS2" not in d]
    if not bad:
        ok("every profile carries FB_DNS1 + FB_DNS2")
    else:
        fail("profile(s) missing the DNS keys: %s" % ", ".join(bad))


def audit_w1_plumbing():
    head("S. W1 driver plumbing: profile-by-path, install log, stock stages, keymap, "
         "real disk size, lost+found, DNS keys")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    if not profs:
        fail("no profiles found under %s" % os.path.relpath(PROFILES_DIR, REPO))
        return
    profiles = [(pf, _parse_profile(os.path.join(PROFILES_DIR, pf))) for pf in profs]

    _audit_w1_profile_path(code, driver_src)
    _audit_w1_log(code, driver_src)
    _audit_w1_stage_strings(code)
    _audit_w1_keymap(code, profiles)
    _audit_w1_disksize(code, profiles, load_proto_tools())
    _audit_w1_lostfound(code)
    _audit_w1_dns(code, fb, profiles)

    # S8: every tracked profile defines every W1 key (a missing key silently falls
    # back to a driver default, which is exactly the drift W1 exists to end).
    for pf, d in profiles:
        miss = [k for k in W1_KEYS if k not in d]
        if miss:
            fail("%s is missing W1 key(s): %s" % (pf, ", ".join(miss)))
        else:
            ok("%s carries all %d W1 keys" % (pf, len(W1_KEYS)))


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
# It cost two shipped defects: the P5.4-FT syslog unit shipped ONE of its eight
# /var/log stubs and then hard-stopped the install, and W1's lost+found preseed
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
        ("P5.4-FT /var/log stubs",
         '#!/bin/sh\nfor lf in alert bus-errors console; do\n'
         '\t: > "$TARGET/var/log/$lf" || die "cannot create"\n'
         '\trun chmod 0644 "$TARGET/var/log/$lf"\ndone\n'),
        ("W1 lost+found preseed (nested)",
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
# U. W2 INTERVIEW -- structure (src/installer/setup.sh)
# ---------------------------------------------------------------------------
# setup.sh is the interactive veneer: it asks, it composes an answers profile,
# it execs the proven driver. Audits A/B/G/H/I/T already cover it as miniroot
# sh; THIS audit covers the properties that are specific to being an interview
# on a blind console in front of a five-minute transplant.
#
#   U1  THE SCAN NEVER CALLS ddsize. W1 proved one unconditional
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
#       redirect stdin from /dev/null -- METAL-FIX.3: an inherited stdin is what
#       hung M-RUN1 on the 1991 pkgadd's prompt, and the interview is the first
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
# "the disk you want to $MODE" because it also did repairs (repair mode is W4,
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
# W3b activates the rest of amixpkg's package screens, so the rest of its
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
STOCK_SYSSETUP = os.path.join(REPO, "build", "core", "root", "usr", "amiga", "bin", "system.setup")
STOCK_SUMMARY_STRING = "Do you wish to change any of these? [n] "

SCAN_PATH_FUNCS = ("scan_disks", "disk_size_hint", "rdb_present", "rdb_extent_mb")


def audit_w2_structure():
    head("U. W2 interview structure (setup.sh: no ddsize in the scan, stdin "
         "discipline, stock wording)")
    if not os.path.isfile(SETUP):
        fail("src/installer/setup.sh is missing -- the W2 interview is the wave's "
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
            fail("setup.sh's SCAN path calls /etc/ddsize in %s -- W1 proved an "
                 "unconditional ddsize WEDGES the install on the bench a3091 path "
                 "and the miniroot has no timeout tool; a per-id scan multiplies "
                 "the exposure" % ", ".join(dirty))
        else:
            ok("the scan path (%s) never references ddsize" % ", ".join(SCAN_PATH_FUNCS))

    # Count ddsize as a COMMAND, not as text: the chooser also NAMES the probe
    # in the line it prints before running it (so a console that wedges says
    # exactly where), and a naive substring count would read those as calls.
    chooser = _extract_func(src, "choose_disk") or ""
    nds_file = list(command_words(src)).count("/etc/ddsize")
    nds_chooser = list(command_words(chooser)).count("/etc/ddsize")
    if nds_file == 1 and nds_chooser == 1 and "DDSIZE_SAFE" in strip_full_comments(chooser):
        ok("ddsize is INVOKED exactly once in the whole interview, inside "
           "choose_disk, behind the DDSIZE_SAFE gate, on ONE already-chosen id")
    else:
        fail("expected exactly one ddsize INVOCATION, inside choose_disk and gated "
             "on DDSIZE_SAFE; found %d in the file / %d in choose_disk, gated=%s"
             % (nds_file, nds_chooser,
                "DDSIZE_SAFE" in strip_full_comments(chooser)))

    # --- U2: SCAN_IDS derived-checked against the proto ---------------------
    m = re.search(r'SCAN_IDS="([0-9 ]+)"', code)
    if not m:
        fail("setup.sh has no SCAN_IDS default -- the scanned id list is unpinned")
    elif not os.path.isfile(PROTO):
        skip("miniroot.proto absent -- SCAN_IDS cannot be derived-checked")
    else:
        # Only CARD-0 units (device index < 8; minor low nibble = card<<3|unit, so
        # card 0 is index 0-7) belong to the interview's SCAN_IDS. The card-1 nodes
        # (c8d0.. / ced0, index >= 8) exist for the RAW/unattended real-060 path,
        # which install.sh raw reaches by device string, not by the interview scan --
        # so they must NOT be required in SCAN_IDS (and the interview must not scan
        # card 1, whose card-0 phantom is fatal to probe on the real LC060).
        proto_ids = set()
        for line in open(PROTO, encoding="utf-8"):
            mm = re.search(r'/dev/dsk/c(\d+)d0s0\b', line)
            if mm and int(mm.group(1)) < 8:
                proto_ids.add(int(mm.group(1)))
        want = sorted(proto_ids)
        got = sorted(int(x) for x in m.group(1).split())
        if got != want:
            fail("setup.sh SCAN_IDS=%s but miniroot.proto ships card-0 /dev/dsk/cNd0s0 "
                 "for %s -- the scan would miss a disk or probe a device node "
                 "that does not exist" % (got, want))
        else:
            ok("SCAN_IDS %s == the CARD-0 ids miniroot.proto carries (derived; card-1 "
               "nodes are the raw-path devices, deliberately not scanned)" % got)
        if 4 in got or 4 in want:
            fail("SCSI id 4 is scannable -- stock reserved it for the tape drive "
                 "and the miniroot ships no c4d0 node; the refusal must stay structural")
        else:
            ok("SCSI id 4 is absent from BOTH the proto and SCAN_IDS -- stock's "
               "tape-drive refusal is structural, not a special case")

    # --- U3: the transplant's stdin -----------------------------------------
    m = re.search(r'(?m)^\s*sh\s+"\$INST/bin/install\.sh"\s+"\$ANSWERS"\s*<\s*/dev/null\s*$',
                  code)
    if m:
        ok("setup.sh runs the driver with stdin from /dev/null (METAL-FIX.3 "
           "preserved: the transplant never inherits the interview's console)")
    else:
        fail("setup.sh must run `sh \"$INST/bin/install.sh\" \"$ANSWERS\" "
             "< /dev/null` -- an inherited stdin is what hung M-RUN1 on the 1991 "
             "pkgadd prompt (METAL-FIX.3)")
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
        # ★ W5 (bench-measured): the answers profile is the base profile's
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
        (r'TARGET_ROOT_MB=\$ANS_ROOT', "the root answer lands in W1's driver key"),
        (r'TARGET_SWAP_MB=\$ANS_SWAP', "the swap answer lands in W1's driver key"),
        (r'INSTALL_VERBOSE=\$ANS_VERBOSE', "the verbose answer lands in W1's driver key"),
        (r'INSTALL_SET=\$SET_NAME', "the chosen set's NAME lands in W3b's driver key"),
        (r'INSTALL_ORDER=\$SET_ORDER', "the chosen set's ORDER FILE lands in W3b's driver key"),
        (r'INSTALL_ATTESTED=\$SET_ATT',
         "the set's attestation posture is recorded, so a waived digest gate is "
         "never silent (plan 5.7)"),
        (r'W2-ANSWERS-BEGIN', "the beacon's BEGIN marker (the blind-console harness greps it)"),
        (r'W2-ANSWERS-END', "the beacon's END marker"),
        # ★ THE FLOPPY BUDGET (W4, bench-measured). The root filesystem here is
        # an 880-block floppy with ~46 blocks free; $ANSWERS alone is 12 of them
        # (the base profile is copied whole -- the medium is read-only), and the
        # static pkgadd needs room on this same filesystem for
        # /usr/apkg/sadm/install/scripts. Echoing the WHOLE composed profile as
        # the beacon spent another 12 and killed W4's first interactive run:
        # `Floppy fd0: no space` -> `pkgadd: ERROR: unable to make packaging
        # directory` -> `STOP: base-OS install FAILED for package(s): core`.
        # (W3b survived the same shape with SIX blocks to spare -- luck.) The
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
             "its packaging directory (W4 bench: `Floppy fd0: no space` then "
             "`pkgadd: ERROR: unable to make packaging directory`)")
    else:
        ok("the beacon is never the whole profile (the floppy-space defect W4 "
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
    if os.path.isfile(STOCK_ROOT_ADF):
        blob = open(STOCK_ROOT_ADF, "rb").read()
        # /etc/profile AND /bin/amixpkg are both files ON this floppy, so one
        # byte scan of the image covers the interview and the menu together.
        bad = [(ours, theirs) for (ours, theirs) in table
               if (theirs or ours).encode("latin1") not in blob]
        if bad:
            for ours, theirs in bad:
                fail("%r is NOT on the stock root floppy -- it is not stock "
                     "wording, or it drifted" % (theirs or ours))
        else:
            ndev = len([1 for (_, t) in table if t])
            ok("all %d quoted strings are present BYTE-FOR-BYTE in %s (the stock "
               "installer + amixpkg themselves); %d carry a DECLARED deviation "
               "where stock parameterised what we resolve"
               % (len(table), os.path.relpath(STOCK_ROOT_ADF, REPO), ndev))
    else:
        skip("%s absent -- the stock-wording cross-check is skipped (not a pass)"
             % os.path.relpath(STOCK_ROOT_ADF, REPO))

    # --- U7: every tracked profile declares the two W2 keys ------------------
    # Same discipline W1 applied to its own keys: a key whose default is silent
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
            fail("profile %s does not declare %s (the W2 interview keys)" % (f, miss))
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

    # E-BIG (KT-32): the stock-kernel root ceiling is REAL in both halves -- a 1000 MB
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


# W6: the two stock machine-class probes the miniroot carries, as sandbox stubs.
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
             base_lines=None, kinfo_line=None):
    """disks: {id: (mb, has_rdb, [(name, start, len), ...])}

    sets:         text of the medium's /install/sets table (W3b), or None for a
                  pre-W3b medium that has none (the interview must still show
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
    # W6 machine-class probes. `machine=None` means NEITHER PROBE EXISTS, which
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
    head("W. the W2 interview, ACTUALLY RUN (sandboxed conversations)")
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
    # --- W3b fixtures: a medium that carries a set table + a per-set order ----
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
          "W2-ANSWERS-BEGIN", "W2-ANSWERS-END"]),
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
         {0: (500, True, [("Payload", 128, 900000)]), 5: (80, False, []),
          6: (100, True, W_BENCH_PARTS)},
         ["y", "", "", "", "", ""], {"profile": p_src},
         ["source -- not installable", "no kernel on this medium for id 5"],
         [], ["TARGET_SCSI_ID=6"]),
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

        # ---- W3b: the three-tier menu -------------------------------------
        ("W3b tiers: the medium's /install/sets drives amixpkg's THREE rows, "
         "each sized from the catalog",
         bench, ["y", "", "", "1", "", ""], dict(w3),
         ["(1)  Standard Amiga UNIX installation      33.5 MB",
          "(2)  Everything on the disc                37.9 MB",
          "(3)  Custom selection"], [],
         ["INSTALL_SET=standard", "INSTALL_ATTESTED=y",
          "install/order.standard"]),
        ("W3b tiers: row 1 points the driver at that set's OWN order file, "
         "row 2 at the medium's",
         bench, ["y", "", "", "2", "", ""], dict(w3), [], [],
         ["INSTALL_SET=minimal", "INSTALL_ATTESTED=y"]),
        ("W3b attestation: an ATTESTED row says nothing about attestation",
         bench, ["y", "", "", "1", "", ""], dict(w3),
         ["Package set:\t\tstandard"], ["unattested selection"], []),
        ("W3b attestation: a row the medium marks n is called an UNATTESTED "
         "SELECTION on the confirmation screen and in the profile",
         bench, ["y", "", "", "2", "", ""], dict(w3u),
         ["Package set:\t\tmedia -- unattested selection"], [],
         ["INSTALL_SET=media", "INSTALL_ATTESTED=n"]),
        ("W3b tiers: a pre-W3b medium (no /install/sets) still shows three "
         "rows with the same numbering",
         bench, ["y", "", "", "1", "", ""], {"catalog": W_CATALOG},
         ["(1)  Standard Amiga UNIX installation      37.9 MB",
          "(2)  Everything on the disc",
          "(3)  Custom selection"], [],
         ["INSTALL_SET=default", "INSTALL_ATTESTED=y"]),

        # ---- W3b: the custom table ----------------------------------------
        ("W3b custom: the frozen amixpkg table renders, opens on the standard "
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
        ("W3b custom: `all` selects everything on the disc",
         bench, ["y", "", "", "3", "all", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (8 packages)"], [], []),
        ("W3b custom: `none` leaves the mandatory core and nothing else",
         bench, ["y", "", "", "3", "none", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (1 packages)"], [], []),
        ("W3b custom: `standard` restores the medium's row-1 set",
         bench, ["y", "", "", "3", "all", "standard", "GO", "", ""], dict(w3),
         ["Software:\t\tCustom selection (5 packages)"], [], []),
        ("W3b custom: DESELECTING a package takes its DEPENDENTS with it "
         "(APKGENG off -> APKG off; the catalog's apkg->apkgeng edge)",
         bench, ["y", "", "", "3", "all", "APKGENG", "GO", "", ""], dict(w3),
         ["no       APKG       Remote client",
          "Software:\t\tCustom selection (6 packages)"], [], []),
        ("W3b custom: SELECTING a package brings its DEPENDENCIES in "
         "(APKG on -> APKGENG on)",
         bench, ["y", "", "", "3", "none", "APKG", "GO", "", ""], dict(w3),
         ["yes      APKGENG",
          "Software:\t\tCustom selection (3 packages)"], [], []),
        ("W3b custom: core is mandatory and refuses to be deselected",
         bench, ["y", "", "", "3", "core", "GO", "", ""], dict(w3),
         ["core is required and cannot be deselected."], [], []),
        ("W3b custom: an unknown name gets amixpkg's own message, not a crash",
         bench, ["y", "", "", "3", "zzz", "GO", "", ""], dict(w3),
         ["Unknown package:  zzz"], [], []),
        ("W3b custom: no #isize block -> every size is `?` and NO total is "
         "printed (a partial total is worse than none)",
         bench, ["y", "", "", "3", "GO", "", ""],
         {"sets": w3_sets, "extra_orders": w3_orders,
          "catalog": "\n".join(W_CATALOG.splitlines()[:9]) + "\n"},
         ["Inst     Name       Description"], [" Total: "], []),

        # ---- W3b: the free-space check ------------------------------------
        ("W3b space: an overcommitted selection gets stock's WARNING and its "
         "override, and declining goes back to the menu",
         bench, ["y", "30", "", "2", "n", "1", "y", "", ""], dict(w3),
         ["WARNING:  Your allocated space for installation is 30 MB,",
          "but you have selected to install 37 MB.",
          "Go ahead with the installation anyway? [n] "], [],
         ["INSTALL_SET=standard", "TARGET_ROOT_MB=30"]),
        ("W3b space: the stock override is honoured -- `y` installs anyway",
         bench, ["y", "30", "", "2", "y", "", ""], dict(w3), [], [],
         ["INSTALL_SET=minimal", "TARGET_ROOT_MB=30"]),
        ("W3b space: a selection that FITS is never questioned",
         bench, ["y", "", "", "2", "", ""], dict(w3), [],
         ["Go ahead with the installation anyway?"], []),

        # ---- W6: the two COVERAGE HOLES, surfaced in-product (plan sec. 6) --
        # Neither of these can be triggered on hardware we own -- there is no
        # IDE-only Amiga and no A2090 on this bench, and Amiberry cannot present
        # one -- so the decision LOGIC is driven here instead, against the
        # miniroot's own probe interface. The one arm that IS hardware-proven is
        # the negative: work/install-matrix/w6-oldboot measured 524288 and
        # "A3000 Internal SCSI" on the canonical rig, and those exact strings
        # are what the "modern machine" case below feeds in.
        ("a machine with NO disks at all gets stock's own line AND the IDE pointer: the A4000's "
         "port takes a master only (a disk not seen is most likely the slave), A1200/A600 not",
         {}, ["", ""], {},
         ["No hard disks are attached to this system.",
          "An IDE disk on the A4000's own port is used as the MASTER only:",
          "The IDE port of an A1200 or A600 is not supported.",
          "UNIX needs a SCSI host adapter"], ["There is no Amiga UNIX IDE driver"], []),
        ("W6 coverage: a KICKSTART 1.3 machine (romsize 262144) is refused by "
         "name, before any size is asked for",
         bench, ["y", "", ""], {"machine": {"rom": "echo 262144"}},
         ["This machine is not supported by this installation disc.",
          "Its Kickstart ROM is 262144 bytes.",
          "original Amiga UNIX 2.1 distribution"],
         ["How many megabytes for the root file system"], []),
        ("W6 coverage: an A2090 controller is refused by name",
         bench, ["y", "", ""],
         {"machine": {"controller": 'echo "A2090 Controller"'}},
         ["This machine is not supported by this installation disc.",
          "Its disk controller is an A2090.",
          "old 2620/2630 ROM"],
         ["How many megabytes for the root file system"], []),
        ("W6 coverage: the MEASURED bench answers (524288 / `A3000 Internal "
         "SCSI`) are NOT refused -- the threshold is cleared by zero margin",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {}}, ["Software:"],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("W6 coverage: FAILS OPEN when romsize cannot answer (its own "
         "`Can't get ROM size` error is not a number)",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {"rom": 'echo "Can\'t get ROM size"'}}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("W6 coverage: FAILS OPEN when dioc says nothing at all (the shape a "
         "node with no disk behind it produced on the bench)",
         bench, ["y", "", "", "1", "", ""],
         {"machine": {"controller": ":"}}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),
        ("W6 coverage: FAILS OPEN when neither probe is installed at all",
         bench, ["y", "", "", "1", "", ""], {}, [],
         ["This machine is not supported by this installation disc."],
         ["TARGET_SCSI_ID=6"]),

        # ---- UFS: the root filesystem is not asked (P-35) -------------------
        ("UFS: the root filesystem is NOT asked -- the summary and the beacon "
         "say ufs, and no s5/ufs menu is shown",
         bench, ["y", "79", "18", "1", "n", "n"], {},
         ["Root file system type:\tufs"],
         ["What file system type is the root partition?",
          "Traditional UNIX file system"],
         ["TARGET_ROOT_FSTYPE=ufs"]),
        # The 2% superuser reserve: W_CATALOG_79 sizes the disc's own set at
        # exactly 79 budgeted MB against a 79 MB root -- the one megabyte where
        # `-o free=2` decides the answer.
        ("UFS: the 2% superuser reserve is subtracted from the free-space check "
         "-- 79 MB of packages into a 79 MB ufs root is an OVERCOMMIT, and the "
         "operator is told the honest 78",
         bench, ["y", "79", "18", "1", "y", "n", "n"],
         {"catalog": W_CATALOG_79},
         ["WARNING:  Your allocated space for installation is 78 MB,",
          "but you have selected to install 79 MB.",
          "Go ahead with the installation anyway? [n] "], [],
         ["TARGET_ROOT_FSTYPE=ufs", "TARGET_ROOT_MB=79"]),
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
# X. W3b -- PACKAGE METADATA: the catalog parser, the media builders, the driver
# ---------------------------------------------------------------------------
# W3b's on-box half (the three-tier menu, the custom table, the free-space
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
#       BEHAVIOURALLY, including the bug W3b exists to fix: `--set full` used to
#       select only stock/*.pkg, so a Full install shipped no cdfs and no package
#       manager.
#   X4  a set advertised on the medium as ATTESTED must have a real reference
#       digest in the matrix, and vice versa. A disc that promises a digest-gated
#       set the matrix cannot gate is a promise with nothing behind it.
#   X5  the driver's INSTALL_ORDER / INSTALL_SET / INSTALL_ATTESTED keys, incl.
#       the property that makes them safe: an empty INSTALL_ORDER must resolve to
#       exactly the pre-W3b $INST/order, and core-first must still be checked in
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
MATRIX = os.path.join(HERE, "install-matrix.sh")
BUILD_ISO = os.path.join(HERE, "build-iso.sh")

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
    head("X. W3b package metadata (catalog parser, media builders, driver keys)")

    # --- X1: the catalog parser conforms ------------------------------------
    sys.path.insert(0, os.path.join(HERE, "lib"))
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
        skip("work/l11/pkgtools/tools/repo/sets.{conf,py} absent (tools/build-l11-inputs.sh) -- the set "
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
                     "exactly the W3b bug: a Full install with no CD filesystem "
                     "and no package manager"
                     % sorted({"cdfs", "apkgeng", "apkg"} - set(got)))
                bad = 1
        if not bad:
            ok("sets.conf resolves to the locked memberships %s, and `full` "
               "carries cdfs/apkgeng/apkg (the --set full bug W3b fixes)"
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
    elif not os.path.isfile(MATRIX):
        skip("tools/install-matrix.sh absent -- attestation cannot be cross-checked")
    else:
        mx = open(MATRIX, encoding="utf-8").read()
        refs = dict((n, d) for (n, d, _o) in
                    re.findall(r'^([a-z][a-z0-9-]*)\|([^|\n]*)\|([^|\n]*)$',
                               mx, re.M))
        adv = m.group(1).split()
        missing = [s for s in adv if refs.get(s, "-") in ("", "-")]
        if missing:
            fail("build-install-iso.sh advertises set(s) %s as attested, but "
                 "install-matrix.sh has no reference DIGEST for them (missing "
                 "row, or a `-` placeholder) -- the disc would promise a digest "
                 "gate the matrix cannot apply" % missing)
        else:
            ok("every advertised attested set %s has a real reference digest in "
               "the matrix's SET_REFS" % adv)
        # ★ A CPU-LINE VARIANT IS THE SAME MEDIUM SET, MEASURED ON ANOTHER KERNEL
        # LINE (Wave C3). `minimal-040` installs the eight packages `minimal`
        # installs, off a medium that still calls the set `minimal` in its own
        # /install/sets -- the suffix records WHICH KERNEL LINE laid the tree down,
        # because the 040 line's first attestation has to be measured rather than
        # inherited from the 030 one. So the advertisement check is against the
        # BASE name: the medium advertises `minimal`, and that is the promise it
        # can actually keep. A suffix naming a set the builder never advertises is
        # still an orphan.
        def _base_set(name):
            for suf in ("-040", "-060"):
                if name.endswith(suf):
                    return name[:-len(suf)]
            return name
        orphan = [s for s, d in refs.items()
                  if d not in ("", "-") and _base_set(s) not in adv]
        if orphan:
            fail("install-matrix.sh has a reference DIGEST for %s, which the "
                 "media builder does not advertise as attested (nor is it a CPU-line "
                 "variant of one) -- the medium would call a gated set unattested"
                 % orphan)
        else:
            ok("every matrix reference digest belongs to a set the media builder "
               "advertises, or is a CPU-line variant of one (a `-` row is a set "
               "awaiting its first attestation run, and is correctly NOT advertised)")
        # And the variant must not drift into a DIFFERENT selection: a `<set>-040`
        # row whose base has no reference at all would be a CPU variant of nothing.
        badvar = [s for s in refs
                  if _base_set(s) != s and refs.get(_base_set(s), "") in ("", "-")]
        if badvar:
            fail("CPU-line variant(s) %s have no attested BASE set -- a variant is "
                 "the same selection on another kernel line, so the base is what "
                 "gives it meaning" % badvar)
        else:
            ok("every CPU-line variant row sits beside an attested base set")
        if refs.get("minimal", "") in ("", "-"):
            fail("the matrix has no reference digest for `minimal` -- that is the "
                 "canonical base-8 and every other cell is compared to it")
        else:
            ok("`minimal` carries a reference digest (%s)" % refs["minimal"])

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
         "a medium with NO sets table (pre-W3b, or a raw slice) is left alone "
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
         "W5.4e subshell trap, which would silently never downgrade anything",
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
             "an unset INSTALL_ORDER resolves to exactly the pre-W3b order file"),
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
    # made in a subshell and lost (the W5.4e lesson, still the sharpest edge here)
    if re.search(r'\[ -f "\$ORDERFIRST" \] \|\| echo "\$pkg" > "\$ORDERFIRST"', dcode):
        ok("driver: the first-package probe records to a FILE inside the "
           "redirect-fed loop and decides in the parent")
    else:
        fail("driver: the core-first probe must record to a file and decide "
             "after the loop -- a variable set inside `done < FILE` is lost")

    # --- X6: every profile declares the W3b keys ----------------------------
    prof = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile"))
    if not prof:
        fail("no profiles found in %s -- X6 would be vacuous" % PROFILES_DIR)
    for f in prof:
        keys = _parse_profile(os.path.join(PROFILES_DIR, f))
        miss = [k for k in ("INSTALL_ORDER", "INSTALL_SET", "INSTALL_ATTESTED")
                if k not in keys]
        if miss:
            fail("profile %s does not declare %s (the W3b set keys)" % (f, miss))
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
# Y. W4 MINIROOT INSTALL SCRIPT (src/miniroot/profile -> /etc/profile)
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
#       redirects the transplant's stdin from /dev/null (METAL-FIX.3).
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
    head("Y. W4 miniroot install script (src/miniroot/profile: order, keymap, "
         "probe, hand-off)")
    if not os.path.isfile(MINIROOT_PROFILE):
        fail("src/miniroot/profile is missing -- the W4 miniroot has no install "
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
    # path, and the METAL-FIX.3 invariant is what actually matters: the transplant
    # must never inherit the console stdin. So assert the invariant directly (every
    # install.sh call carries `< /dev/null`) rather than banning the reference --
    # the interactive path still reaches the driver through setup.sh (audit W2).
    inst_calls = [ln for ln in code.splitlines() if "install.sh" in ln]
    if not inst_calls:
        ok("the driver is never exec'd directly (the interview owns the console "
           "and hands the transplant a /dev/null stdin)")
    else:
        bad = [ln for ln in inst_calls if "< /dev/null" not in ln]
        if bad:
            fail("src/miniroot/profile invokes install.sh WITHOUT `< /dev/null` "
                 "(METAL-FIX.3: the transplant must never inherit the console "
                 "stdin): %s" % "; ".join(x.strip() for x in bad))
        else:
            ok("install.sh is reached only on the unattended path, and every call "
               "hands it a /dev/null stdin (METAL-FIX.3 held without setup.sh)")

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

    if os.path.isfile(STOCK_ROOT_ADF):
        blob = open(STOCK_ROOT_ADF, "rb").read()
        bad = []
        for r in rows:
            if r.startswith("11)"):
                continue
            if r.encode("latin-1") not in blob:
                bad.append(r)
        if bad:
            for b in bad:
                fail("keymap row %r is NOT on the stock root floppy -- it is not "
                     "stock's data, or it drifted (Latin-1 bytes included)" % b)
        else:
            ok("all %d unchanged keymap rows are byte-for-byte the stock "
               "/etc/id_kmap's, accented bytes included; row 11 is the declared "
               "relabel" % (len(rows) - 1))
    else:
        skip("%s absent -- the keymap rows are not cross-checked (not a pass)"
             % os.path.relpath(STOCK_ROOT_ADF, REPO))

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
    if re.search(r'^CD_CANDIDATES="1,3 0,3 0,2 1,2"$', code, re.M):
        ok("the cdfs probe order is pinned 1,3 -> 0,3 -> 0,2 -> 1,2 (hardcoded HERE: it "
           "cannot come from the medium it is looking for; 0,3 = a sole A4091 as card 0)")
    else:
        fail("CD_CANDIDATES must be exactly \"1,3 0,3 0,2 1,2\"")
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
    elif not os.path.isfile(PROTO):
        skip("miniroot.proto absent -- SCAN_IDS cannot be derived-checked")
    else:
        # CARD-0 units only (index < 8); card-1 nodes (c8d0/ced0) are the raw-path
        # devices, deliberately not part of the interview scan (and card 1 must not
        # be scanned -- the card-0 phantom is fatal to probe on the real LC060).
        proto_ids = set()
        for line in open(PROTO, encoding="utf-8"):
            mm = re.search(r'/dev/dsk/c(\d+)d0s0\b', line)
            if mm and int(mm.group(1)) < 8:
                proto_ids.add(int(mm.group(1)))
        want = sorted(proto_ids)
        got = sorted(int(x) for x in m.group(1).split())
        if got != want:
            fail("profile SCAN_IDS=%s but miniroot.proto carries card-0 /dev/dsk/cNd0s0 "
                 "for %s" % (got, want))
        elif 4 in got:
            fail("SCSI id 4 is scannable -- stock reserved it for the tape drive")
        else:
            ok("SCAN_IDS %s == the ids miniroot.proto actually carries, id 4 "
               "structurally absent (derived, not a second hardcoded copy)" % got)

    # --- Y6: stock wording, byte-for-byte ----------------------------------
    absent = [ours for (ours, _) in STOCK_PROFILE_STRINGS if ours not in src]
    if absent:
        for a in absent:
            fail("src/miniroot/profile does not carry the stock string %r" % a)
    else:
        ok("the install script carries all %d quoted stock strings"
           % len(STOCK_PROFILE_STRINGS))
    if os.path.isfile(STOCK_ROOT_ADF):
        blob = open(STOCK_ROOT_ADF, "rb").read()
        bad = [(o, t) for (o, t) in STOCK_PROFILE_STRINGS
               if (t or o).encode("latin-1") not in blob]
        if bad:
            for o, t in bad:
                fail("%r is NOT on the stock root floppy -- it is not stock "
                     "wording, or it drifted" % (t or o))
        else:
            ndev = len([1 for (_, t) in STOCK_PROFILE_STRINGS if t])
            ok("all %d quoted strings are present BYTE-FOR-BYTE in %s (the stock "
               "install script itself); %d carry a DECLARED deviation where stock "
               "parameterised what we resolve"
               % (len(STOCK_PROFILE_STRINGS),
                  os.path.relpath(STOCK_ROOT_ADF, REPO), ndev))
    else:
        skip("%s absent -- the stock-wording cross-check is skipped (not a pass)"
             % os.path.relpath(STOCK_ROOT_ADF, REPO))


# ---------------------------------------------------------------------------
# Z. W5 -- the first-boot configuration dialog
# ---------------------------------------------------------------------------
# W5: the dialog TRAVELS IN firstboot.sh (the `--dialog` entry point) and the
# stock sysinit slot gets a three-line STUB that execs it. payload/firstboot/
# system.setup is that stub -- the master the driver's emitter is drift-locked
# against -- NOT the dialog. See the here-doc law (Z0) for why.
DIALOG_STUB = os.path.join(REPO, "payload", "firstboot", "system.setup")
# Stock artifacts the dialog quotes. Each string must appear BYTE-FOR-BYTE in the
# named recovered file; a missing core tree is a SKIP, never a silent pass.
STOCK_CORE = os.path.join(REPO, "build", "core", "root")   # tools/build-core-tree.sh
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


def _sed_alternations(text):
    """Every `\\|` inside a sed expression. SVR4 sed has NO alternation -- `\\|` is a
    GNU extension -- and the failure mode is silent: the expression simply matches
    nothing. MEASURED on the bench 2026-08-12: both of firstboot.sh's
    duplicate-guards were written with `\\([ \\t]\\|$\\)` and had been inert since
    W6.4c, so the repo-host line was appended a second time on the first re-run.
    A guard that cannot fire is worse than no guard, because it is BELIEVED."""
    return [l.strip() for l in strip_full_comments(text).splitlines()
            if re.search(r'\bsed\b', l) and r'\|' in l]


def _s5_truncation_collisions(text):
    """Pairs of literal on-target paths whose BASENAMES collide once s5 truncates
    them to 14 characters. `$$` expands to a pid, so it is modelled at its longest
    (5 digits) -- the worst case is the one that has to be safe.

    This is the W5 bench finding, and it cost a file: `firstboot.conf` is exactly
    14 characters, so `firstboot.conf.new` IS `firstboot.conf`. The consequence
    was not a failed rename but total loss -- `sed ... "$CONF" > "$NEWCONF"`
    truncated its own input before sed read a byte, and `mv` then found source and
    destination identical and took the file with it."""
    paths = set(re.findall(r'(/[A-Za-z0-9_./$-]+)', strip_full_comments(text)))
    trunc = {}
    for p in paths:
        if "*" in p:
            continue
        base = p.rsplit("/", 1)[-1].replace("$$", "99999")
        if not base or base.startswith("$"):
            continue
        key = (p.rsplit("/", 1)[0], base[:14])
        trunc.setdefault(key, set()).add(p)
    return [sorted(v) for v in trunc.values() if len(v) > 1]


def _dialog_clean_exit_block(src):
    """The tail of the summary loop from the CHANGE decision to the final exit --
    the only place the dialog is allowed to disarm itself."""
    i = src.find('[ "$CHANGE" = no ] || continue')
    return src[i:] if i >= 0 else ""


def _run_emitter(driver_src, name):
    """RUN one of the driver's `emit_*` functions and return what it wrote. The
    same drift-lock method audit J uses for the rc2 hook: extracting the function
    and executing it proves the emitter, not a regex about the emitter."""
    try:
        func = _extract_func(driver_src, name)
    except StopIteration:
        return None
    if not func:
        return None
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    hp = workpath("emit_%s.sh" % name)
    outp = workpath("emit_%s.out" % name)
    if os.path.exists(outp):
        os.unlink(outp)
    with open(hp, "w") as fh:
        fh.write(func + '\n%s "$1"\n' % name)
    r = subprocess.run([sh, hp, outp], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(outp):
        return None
    return open(outp, encoding="utf-8").read()


def _dialog_section(fb_src):
    """The DIALOG half of firstboot.sh: from its banner comment to the `--dialog`
    dispatch. Everything after that is the APPLY half."""
    i = fb_src.find("# THE FIRST-BOOT CONFIGURATION DIALOG")
    # anchor on the DISPATCH, not on the first `case "$1" in`: the dialog's own
    # is_num() and valid_ip() open with that line, and cutting there would end the
    # section forty lines in -- with every resilience check silently passing over
    # code it never saw.
    m = re.search(r'(?m)^case "\$1" in\n\t--dialog\)', fb_src)
    if i < 0 or not m:
        return ""
    return fb_src[i:m.start()]


def _heredoc_bodies(text):
    """Every here-doc body in a script, as a list. On the miniroot each one is a
    REAL FILE on the 880-block install floppy for the whole life of the shell --
    see the here-doc law in audit Z.

    ★ FULL-LINE COMMENTS ARE SKIPPED (W5.5). They were not, and the scanner
    therefore counted the PROSE that described a here-doc as a here-doc: the
    comment above emit_updbootpart said "a QUOTED here-doc (<<'UPDBOOTPART_EOF')"
    and the scan started THERE, swallowing 391 bytes of comment and code before
    the real body. That is where W5's "15,818 B" figure came from -- the real
    body was 15,427, as `ls -l /tmp/sh<pid>` on the box says. A budget check that
    measures the wrong thing is worse than none, and after W5.5 the failure mode
    inverts: a comment MENTIONING a here-doc would have no closing delimiter and
    the scan would swallow the rest of the file. Only whole-line comments are
    dropped, so a real opener with a trailing comment is still caught."""
    out = []
    lines = [("" if l.lstrip().startswith("#") else l) for l in text.split("\n")]
    i = 0
    while i < len(lines):
        m = _HEREDOC_OPEN.search(lines[i])
        if m:
            delim = m.group(2)
            body = []
            i += 1
            while i < len(lines) and lines[i].strip() != delim:
                body.append(lines[i])
                i += 1
            out.append("\n".join(body))
        i += 1
    return out


def audit_w5_dialog():
    head("Z. W5 first-boot configuration dialog (payload/firstboot/system.setup): "
         "drift lock, resilience contract, stock wording, the two tiers")
    if not os.path.isfile(DIALOG_STUB):
        fail("payload/firstboot/system.setup is missing -- the sysinit slot has no "
             "entry point to write")
        return
    stub = read_sh(DIALOG_STUB)
    driver_src = open(DRIVER, encoding="utf-8").read()
    dcode = strip_full_comments(driver_src)
    fb_src = read_sh(FIRSTBOOT)
    fb = strip_full_comments(fb_src)
    src = _dialog_section(fb_src)
    code = strip_full_comments(src)
    if not src:
        fail("firstboot.sh has no `--dialog` section -- the W5 dialog is not there")
        return

    # --- Z0: THE HERE-DOC LAW (bench-measured 2026-08-12; TIGHTENED TO ZERO in W5.5)
    # The 1991 SVR4 sh MATERIALIZES EVERY HERE-DOC BODY INTO A FILE UNDER /tmp WHEN
    # IT PARSES THE SCRIPT -- proven on the box: a here-doc inside a function that
    # is never called still leaves /tmp/sh<pid> behind for the life of the shell.
    # On the miniroot /tmp IS the 880-block install floppy, which has 46 free
    # blocks (superblock tfree, 1 KB logical blocks), and the static pkgadd needs
    # some of them for its packaging directory. W5's first attempt put the ~29 KB
    # dialog in a second here-doc in the driver; the shell ran the floppy out of
    # space before the driver printed its first line, and BOTH the interactive and
    # the unattended cell died with `Floppy fd0: no space` -> `pkgadd: ERROR:
    # unable to make packaging directory`.
    #
    # W5 could only afford to cap this at "one here-doc, <= 16 KB", because the
    # driver still carried updbootpart's body. W5.5 moved that body onto the
    # medium, so the honest budget is now ZERO -- and zero is also the discipline
    # every other on-target file in this driver already follows: emit_firstboot_
    # hook, emit_zen_hook and emit_system_setup are plain `echo` lines, and
    # updbootpart/firstboot.sh are copied off the medium. On the miniroot you
    # write a file with `echo`, or you copy it from the medium. You do not write
    # it with a here-doc.
    #
    # WHAT IT COST, measured (run w55-m1, 2026-08-12): with the driver parsed, the
    # miniroot's /tmp held `sh250`, 15,427 bytes -- 16 of the floppy's 46 free
    # 1 KB blocks (34 x 512-byte units as `ls -l` totals them), on every install
    # since W6-I.
    FLOPPY_HEREDOC_BUDGET = 0
    for label, path in (("install.sh", DRIVER), ("setup.sh", SETUP),
                        ("miniroot profile", MINIROOT_PROFILE)):
        bodies = _heredoc_bodies(read_sh(path))
        total = sum(len(b) for b in bodies)
        if total > FLOPPY_HEREDOC_BUDGET:
            fail("%s carries %d here-doc(s), %d bytes = %d of the install floppy's "
                 "46 free 1 KB blocks -- each one is a REAL FILE on that floppy from "
                 "the moment the shell PARSES this script, and since W5.5 the budget "
                 "is ZERO: write the file with `echo` lines, or stage it on the medium "
                 "and cp it (see /install/updbootpart)"
                 % (label, len(bodies), total, (total + 1023) // 1024))
        else:
            ok("%s: no here-doc at all -- nothing of it is materialized on the "
               "880-block install floppy at PARSE time" % label)
    # Non-vacuity: the scanner must still SEE a here-doc when there is one, and must
    # NOT see one in a comment that merely mentions the syntax (the W5 mismeasure).
    if len(_heredoc_bodies("cat > /t <<'EOF'\nbody\nEOF\n")) == 1:
        ok("here-doc law: the scanner does detect a real here-doc (non-vacuity)")
    else:
        fail("here-doc law: the scanner no longer detects a real here-doc -- the "
             "budget check above is vacuous")
    if _heredoc_bodies("# the body is a QUOTED here-doc (<<'EOF'), emitted literally\nx=1\n") == []:
        ok("here-doc law: a COMMENT mentioning <<'EOF' is not counted as one "
           "(what inflated W5's 15,818-byte figure)")
    else:
        fail("here-doc law: a comment mentioning a here-doc opener is still counted")
    if "SYSTEM_SETUP_EOF" in driver_src:
        fail("the dialog is back in a driver here-doc -- that is the 78-block "
             "floppy overrun that failed every cell on 2026-08-12")
    else:
        ok("the dialog is NOT in a driver here-doc: it travels in firstboot.sh, "
           "which the medium already carries and the driver already copies")

    # --- Z1: the dialog's own code (inside firstboot.sh) ---------------------
    # firstboot.sh as a whole is covered by audits A/B/G; these pin the DIALOG
    # section specifically, so a regression cannot hide in the bigger file.
    hits = [(why, m.group(0)) for pat, why in TARGET_PATTERNS
            for m in re.finditer(pat, code)]
    if hits:
        for why, tok in hits:
            fail("dialog: pre-POSIX violation %r (%s)" % (tok, why))
    else:
        ok("dialog section: no $(...), $(( )), export VAR=val, [[ ]] or `local`")
    if re.search(r'case "\$1" in\n\t--dialog\)\n\t\trun_dialog\n\t\texit 0',
                 fb_src):
        ok("firstboot.sh dispatches `--dialog` to run_dialog and exits -- one file, "
           "two entry points, one set of FB_ variables")
    else:
        fail("firstboot.sh has no `--dialog` dispatch")
    if fb_src.find('case "$1" in') < fb_src.find('[ -f "$MARK" ]'):
        ok("the dialog dispatch precedes the PENDING check (the dialog runs at "
           "sysinit, where PENDING is not its business)")
    else:
        fail("the `--dialog` dispatch is behind the PENDING check")

    # --- Z2: the STUB, and the DRIFT LOCK on it -----------------------------
    checks = [
        (r'^exec /sbin/sh /var/adm/firstboot/firstboot\.sh --dialog$',
         "execs the payload's dialog entry point"),
    ]
    for pat, why in checks:
        if re.search(pat, stub, re.M):
            ok("dialog stub: %s" % why)
        else:
            fail("dialog stub MISSING: %s" % why)
    if len(stub) < 600 and "'" not in stub and "\\" not in stub:
        ok("dialog stub is %d bytes and free of quotes and backslashes -- which is "
           "what lets the driver emit it with plain `echo` lines instead of a "
           "here-doc" % len(stub))
    else:
        fail("dialog stub is too big or carries a quote/backslash the echo-based "
             "emitter cannot reproduce (%d bytes)" % len(stub))
    emitted = _run_emitter(driver_src, "emit_system_setup")
    if emitted is None:
        fail("install.sh has no emit_system_setup -- the driver cannot write the "
             "sysinit slot")
    elif emitted == stub:
        ok("DRIFT LOCK: install.sh's emit_system_setup REPRODUCES "
           "payload/firstboot/system.setup byte-for-byte (%d bytes), proven by "
           "RUNNING it" % len(stub))
    else:
        fail("DRIFT: emit_system_setup does not reproduce the tracked stub "
             "(%d vs %d bytes)" % (len(emitted or ""), len(stub)))

    # --- Z4: THE RESILIENCE CONTRACT ----------------------------------------
    ndisarm = len(re.findall(r'chmod -x', code))
    if ndisarm == 1:
        ok("resilience: exactly ONE `chmod -x` in the whole dialog")
    else:
        fail("resilience: %d `chmod -x` occurrences -- the disarm must exist exactly "
             "once, at the clean exit" % ndisarm)
    tail = _dialog_clean_exit_block(code)
    if "chmod -x" in tail:
        ok("resilience: the disarm is inside the summary loop's CLEAN EXIT branch "
           "(an interruption or a power cycle re-runs the whole dialog)")
    else:
        fail("resilience: the `chmod -x` is NOT in the clean-exit branch -- the "
             "dialog could disarm itself before it finished")
    if re.search(r'if write_conf; then', tail) and \
            tail.find("write_conf") < tail.find("chmod -x"):
        ok("resilience: the answers are written to firstboot.conf BEFORE the disarm "
           "(a crash between the two costs a re-run, never the answers)")
    else:
        fail("resilience: the conf write does not precede the disarm")
    m = re.search(r'if \[ "\$PW_DONE" = "" \]; then(.*?)fi\n', tail, re.S)
    if m and "exit 0" in m.group(1) and tail.find('"$PW_DONE"') < tail.find("chmod -x"):
        ok("resilience: the FORCED ROOT PASSWORD -- an unset password exits BEFORE "
           "the disarm, so the dialog re-arms until it has been set")
    else:
        fail("resilience: the PW_DONE gate does not stand between the summary and "
             "the disarm -- the forced-password guarantee would be empty")
    if re.search(r"trap 'INTR=y' 2", code) and not re.search(r"trap '[^']*exit[^']*' 2", code):
        ok("resilience: SIGINT is trapped to a FLAG, never to an exit (Ctrl-C "
           "re-asks; it can never leave the dialog un-armed)")
    else:
        fail("resilience: the SIGINT trap is missing or exits")
    rk = _extract_func(src, "readask")
    if rk and re.search(r'if \[ -n "\$INTR" \]', rk) and "continue" in rk and \
            re.search(r'run again at the next boot', rk) and "exit 0" in rk:
        ok("resilience: readask re-asks on an interrupt and exits ARMED on EOF (an "
           "unreadable console costs one boot message, never a hang)")
    else:
        fail("resilience: readask does not implement the interrupt/EOF contract")

    # --- Z5: the conf writer is idempotent ----------------------------------
    wc = _extract_func(src, "write_conf")
    if not wc:
        fail("dialog: cannot extract write_conf -- the collection half is unproven")
    else:
        checks = [
            (r"-e '/\^FB_NODENAME=/d'", "strips the keys it owns before appending"),
            (r"-e '/\^# W5-DIALOG-/d'", "strips its own previous block markers"),
            (r'> "\$NEWCONF"', "writes to a TEMP file"),
            (r"grep '\^# W5-DIALOG-END\$' \"\$NEWCONF\"",
             "verifies the closing marker BEFORE it replaces the conf"),
            (r'mv "\$\{NEWCONF:\?\}" "\$\{CONF:\?\}"', "moves it into place (atomic)"),
        ]
        bad = [d for p, d in checks if not re.search(p, wc)]
        if bad:
            for d in bad:
                fail("dialog write_conf MISSING: %s" % d)
        else:
            ok("dialog write_conf: %s" % "; ".join(d for _, d in checks))
        # every key the dialog writes must also be stripped first, or a re-run
        # would leave two assignments and the LAST one would silently win
        written = set(re.findall(r'echo "(FB_[A-Z0-9_]+)=', wc))
        stripped = set(re.findall(r"-e '/\^(FB_[A-Z0-9_]+)=/d'", wc))
        if written and written <= stripped:
            ok("dialog write_conf: all %d FB_ keys it writes are stripped first "
               "(a re-run REPLACES its block, it never accumulates)" % len(written))
        else:
            fail("dialog write_conf: key(s) written but not stripped first: %s"
                 % ", ".join(sorted(written - stripped)))

    # --- Z6: the hard rules -------------------------------------------------
    if _writes_network_config(code):
        fail("dialog WRITES /etc/inet/network-config -- the one forbidden file")
    else:
        ok("dialog never writes /etc/inet/network-config")
    code_nc, why = _strip_setclk_rerun(code)
    if why:
        fail("dialog: " + why)
    if re.search(r'\b(date\s+[0-9]|setclk\b|stime\b)', code_nc):
        fail("dialog appears to SET the clock -- forbidden (the RTC/lastchg trap)")
    else:
        ok("dialog never sets the clock (the date/time question is deliberately "
           "gone; only `date` for the summary line)")
    if re.search(r'>\s*/etc/domain', code):
        fail("dialog writes /etc/domain -- a set domain is appended to EVERY "
             "resolver lookup; the domain belongs in the hosts FQDN alias only")
    else:
        ok("dialog never writes /etc/domain (the resolver-append trap)")
    if re.search(r'echo\s+"TZ=', code):
        fail("dialog writes a TZ= line itself -- /etc/TIMEZONE is the stock zone "
             "menu's to write and firstboot.sh's to re-emit; the colon must only "
             "ever be emitted by code that owns it")
    else:
        ok("dialog never writes a TZ= line: it runs the stock zone menu and READS "
           "the zone back (FB_TZ is the bare zone, FB_TZ_KEEP tells firstboot so)")
    if re.search(r'FB_TZ=`expr "\$ZSET" : \':\\\(\.\*\\\)\'`', code) and \
            re.search(r'FB_TZ_KEEP=y', code):
        ok("dialog strips the leading colon off the zone it recorded, and sets "
           "FB_TZ_KEEP so firstboot leaves the menu's own /etc/TIMEZONE alone")
    else:
        fail("dialog does not record the zone in the bare, colon-less form")
    # the nonstandard-zone escape must clear FB_TZ, or `TZ=:GMT0` becomes reachable
    if re.search(r'\?\*\)\n\s*# The "Other \(nonstandard\)" escape', src) or \
            re.search(r'FB_TZ=\n\s*FB_TZ_KEEP=y', code):
        ok("dialog CLEARS FB_TZ when the zone is a POSIX rule string, so no data "
           "path can ever produce the bus-erroring `TZ=:GMT0`")
    else:
        fail("dialog does not clear FB_TZ for a nonstandard (POSIX-rule) zone")

    # --- Z7: stock wording, byte-for-byte against the recovered artifacts ----
    if not os.path.isdir(STOCK_CORE):
        skip("the extracted stock core is absent (%s) -- the dialog's quoted stock "
             "strings are not checked against the originals here"
             % os.path.relpath(STOCK_CORE, REPO))
    else:
        missing_here = [s for _, s in DIALOG_STOCK_STRINGS if s not in src]
        if missing_here:
            for s in missing_here:
                fail("dialog does not carry the stock string %r" % s)
        else:
            ok("dialog carries all %d quoted stock strings"
               % len(DIALOG_STOCK_STRINGS))
        bad = []
        for rel, s in DIALOG_STOCK_STRINGS:
            p = os.path.join(STOCK_CORE, rel)
            if not os.path.isfile(p):
                bad.append("%s (file absent)" % rel)
                continue
            blob = open(p, "rb").read()
            if s.encode("latin1") not in blob:
                bad.append("%r not in %s" % (s, rel))
        if bad:
            for b in bad:
                fail("stock-string check: %s" % b)
        else:
            ok("all %d strings are BYTE-FOR-BYTE in the recovered stock scripts "
               "(amixnode / amixhosts / system.setup)" % len(DIALOG_STOCK_STRINGS))

    # --- Z8: the two tiers, in the driver -----------------------------------
    checks = [
        (r'\[ -n "\$FIRSTBOOT_DIALOG" \] \|\| FIRSTBOOT_DIALOG=n',
         "FIRSTBOOT_DIALOG defaults to n -- an unattended install is unchanged"),
        (r'if \[ "\$FIRSTBOOT_DIALOG" = y \]; then\n\t\techo "\+ emit_system_setup \$SETUP"',
         "arms the dialog ONLY under FIRSTBOOT_DIALOG=y"),
        (r'run chmod 0755 "\$SETUP"', "armed means EXECUTABLE (sysinit's own gate)"),
        (r'run chmod 0644 "\$SETUP"',
         "the unattended tier keeps the stock `chmod -x` disarm, byte-unchanged"),
        (r'echo "FB_DIALOG=\$FIRSTBOOT_DIALOG"',
         "records FB_DIALOG in firstboot.conf so S16 knows which tier it is in"),
        (r'die "profile \$PROFILE_NAME sets FIRSTBOOT_DIALOG=y but the target has no \$SETUP',
         "fails closed if the sysinit slot is not there to take"),
    ]
    bad = [d for p, d in checks if not re.search(p, driver_src)]
    if bad:
        for d in bad:
            fail("driver arm step MISSING: %s" % d)
    else:
        ok("driver arm step: %s" % "; ".join(d for _, d in checks))
    # NEGATIVE FIXTURE: a driver that armed unconditionally must be caught
    neg = re.sub(r'if \[ "\$FIRSTBOOT_DIALOG" = y \]; then\n\t\techo "\+ emit_system_setup \$SETUP"',
                 'echo "+ emit_system_setup $SETUP"', driver_src)
    if not re.search(r'if \[ "\$FIRSTBOOT_DIALOG" = y \]; then\n\t\techo "\+ emit_system_setup \$SETUP"', neg):
        ok("negative fixture fires: an unconditionally-armed dialog is flagged")
    else:
        fail("negative fixture did NOT fire: the arm-gate check is broken")
    if re.search(r'echo "FIRSTBOOT_DIALOG=y"', open(SETUP, encoding="utf-8").read()):
        ok("the interview writes FIRSTBOOT_DIALOG=y -- interactive installs, and "
           "only interactive installs, arm the dialog")
    else:
        fail("setup.sh does not write FIRSTBOOT_DIALOG=y into the answers profile")

    # --- Z7b: the repository-address question must have an EXIT (W6) ---------
    # The distro-neutral public flavor ships FB_REPO_HOST with an EMPTY
    # FB_REPO_IP -- we know where the packages live, we cannot know that name's
    # address on somebody else's LAN. The address loop re-asks until valid_ip
    # accepts, and an empty answer against an empty default becomes an empty
    # $ask, which valid_ip refuses forever: a public disc would have hung its
    # own first boot at a question with no answerable value. This is exactly the
    # class of bug a profile-only "pure data change" is supposed not to have, so
    # the escape is audited, not just written.
    if re.search(r'if \[ "\$ask" = "" \] && \[ -z "\$FB_REPO_IP" \]; then',
                 code):
        ok("the repository-address question accepts RETURN when there is no "
           "default -- the public flavor cannot hang its own first boot")
    else:
        fail("the repository-address loop has no empty-default escape: with "
             "FB_REPO_HOST set and FB_REPO_IP empty (the public flavor) it "
             "re-asks forever")
    if re.search(r'Package downloads will not resolve it until it is', code):
        ok("...and it says the consequence out loud rather than pretending an "
           "address it was not given")
    else:
        fail("the empty-address escape does not state its consequence")
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    profiles = [(pf, _parse_profile(os.path.join(PROFILES_DIR, pf))) for pf in profs]
    bad = ["%s=%r" % (pf, d.get("FIRSTBOOT_DIALOG")) for pf, d in profiles
           if d.get("FIRSTBOOT_DIALOG") not in ("n", "y")]
    if not bad:
        ok("every tracked profile declares FIRSTBOOT_DIALOG explicitly (n = the "
           "unattended LAN flavors, y = the distro-neutral public flavor)")
    else:
        fail("profile(s) with no explicit FIRSTBOOT_DIALOG: %s" % ", ".join(bad))
    _audit_public_flavor(profiles)


    # --- Z8b: the two ON-BOX PORTABILITY RULES this wave measured ------------
    # Both were found by RUNNING the dialog and the apply half on the bench, and
    # neither is visible to `sh -n` or to any allowlist: they are properties of
    # SVR4 sed and of the s5 filesystem, not of the shell.
    for label, path in (("firstboot.sh", FIRSTBOOT), ("dialog stub", DIALOG_STUB),
                        ("install.sh", DRIVER), ("setup.sh", SETUP),
                        ("miniroot profile", MINIROOT_PROFILE)):
        bad = _sed_alternations(read_sh(path))
        if bad:
            for l in bad:
                fail("%s: sed alternation `\\|` -- SVR4 sed has none, so this "
                     "expression matches NOTHING (silently): %s" % (label, l))
        else:
            ok("%s: no `\\|` in any sed expression (SVR4 sed has no alternation)"
               % label)
    if _sed_alternations('sed "/[ ]x\\([ ]\\|$\\)/d" f\n'):
        ok("negative fixture fires: the exact inert form firstboot.sh carried "
           "until 2026-08-12 is caught")
    else:
        fail("negative fixture did NOT fire: the sed-alternation check is broken")
    for label, path in (("firstboot.sh", FIRSTBOOT), ("dialog stub", DIALOG_STUB)):
        cols = _s5_truncation_collisions(read_sh(path))
        if cols:
            for c in cols:
                fail("%s: paths collide under s5's 14-character truncation: %s "
                     "(a temp that IS its target destroys the file)"
                     % (label, " == ".join(c)))
        else:
            ok("%s: every on-target path stays distinct under s5's 14-character "
               "name truncation" % label)
    if _s5_truncation_collisions('CONF=/var/adm/firstboot/firstboot.conf\n'
                                 'NEW=/var/adm/firstboot/firstboot.conf.new\n'):
        ok("negative fixture fires: firstboot.conf vs firstboot.conf.new -- the "
           "exact pair that cost the file on the bench -- is caught")
    else:
        fail("negative fixture did NOT fire: the s5 truncation check is broken")

    # --- Z9: the apply half (firstboot.sh) ----------------------------------
    checks = [
        (r'if \[ "\$FB_DIALOG" = y \] && \[ ! -f "\$DIALOG_DONE" \]; then\n\tDIALOG_PENDING=y',
         "an incomplete dialog is detected by the DIALOG-DONE marker"),
        (r'if \[ -n "\$DIALOG_PENDING" \]; then\n\techo "firstboot: mechanical steps applied; PENDING KEPT',
         "PENDING is KEPT when the dialog has not completed (the mechanical steps "
         "still ran, so the box boots healthy)"),
        (r'if \[ "\$FB_TZ_KEEP" = y \] && \[ -f /etc/TIMEZONE \]; then',
         "the stock zone menu's own /etc/TIMEZONE is left alone"),
        (r'if \[ "\$FB_ROOT_TELNET" = n \]; then\n\t+sed \'s/\^#CONSOLE=/CONSOLE=/\'',
         "root-telnet=n RESTRICTS root to the console; y keeps today's `#CONSOLE=`"),
        (r'if \[ "\$FB_SYSLOG" = n \] && \[ -f /etc/init\.d/syslogd \]; then',
         "syslog is only touched when the answer was n"),
    ]
    bad = [d for p, d in checks if not re.search(p, fb)]
    if bad:
        for d in bad:
            fail("firstboot apply MISSING: %s" % d)
    else:
        ok("firstboot apply: %s" % "; ".join(d for _, d in checks))
    # the syslog edit must be IN PLACE -- three hard links share that inode
    if re.search(r'&& cp /tmp/syslogd\.fb\$\$ /etc/init\.d/syslogd', fb):
        ok("syslog toggle writes THROUGH the inode (`cp` back), so S70syslogd and "
           "K50syslogd -- the other two names of that one inode -- follow it")
    else:
        fail("syslog toggle does not cp back over /etc/init.d/syslogd")
    if re.search(r'mv\s+[^\n]*/etc/init\.d/syslogd', fb):
        fail("syslog toggle uses `mv` onto /etc/init.d/syslogd -- that breaks the "
             "S70/K50 hard links and the edit stops applying after a reboot")
    else:
        ok("no `mv` onto /etc/init.d/syslogd (the link topology survives)")
    # the aen0 route writer: pre-probe, ONE ed run, post-verify
    checks = [
        (r'nex=`grep -c \'\^exit \' /etc/inet/rc\.inet`', "pre-probes the anchor line"),
        (r'nrt=`grep -c \'\^\[ \t\]\*/usr/sbin/route add default\' /etc/inet/rc\.inet`',
         "pre-probes for a route that is already there"),
        (r'if \[ "\$nex" = 1 \] && \[ "\$nrt" = 0 \]; then', "edits only the shape it recognises"),
        (r'\} \| ed - /etc/inet/rc\.inet', "ONE ed run"),
        (r'got=`grep -c ".*route add default \$FB_GATEWAY 1.*" /etc/inet/rc\.inet`',
         "post-verifies the inserted line"),
        (r'cp /tmp/rc\.inet\.fb\$\$ /etc/inet/rc\.inet', "restores the original if it did not verify"),
    ]
    bad = [d for p, d in checks if not re.search(p, fb)]
    if bad:
        for d in bad:
            fail("rc.inet route writer MISSING: %s" % d)
    else:
        ok("rc.inet default-route writer follows the ed half-patch discipline: %s"
           % "; ".join(d for _, d in checks))
# --- Z7c: THE DISTRO-NEUTRAL PUBLIC FLAVOR (P8.3, W6) -----------------------
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


def _public_flavor_problems(name, d):
    """The P8.3 rules, as a pure function so the negative fixtures can drive it."""
    probs = []
    for key, what in PUBLIC_MUST_BE_EMPTY:
        v = d.get(key)
        # An IMAGE KIT (IMAGE_KIT=y: the install runs on the bench and the finished
        # disk IS the product, e.g. the C6 Gayle-IDE CF image) has a disk size that
        # is a fact of the image, not of the operator's disk -- and the bench
        # cannot probe it (/etc/ddsize wedges the A3000 path). That one key only.
        if v and key == "TARGET_DISK_MB" and d.get("IMAGE_KIT") == "y":
            continue
        if v:
            probs.append("%s bakes %s=%r (%s)" % (name, key, v, what))
    node = d.get("FB_NODENAME") or ""
    if not node and d.get("INSTALL_LAYOUT") == "1.1":
        pass   # a 1.1 first boot accepts an empty name (DHCP's, else amix-xxxx)
    elif not node:
        probs.append("%s has no FB_NODENAME at all -- the dialog needs a default "
                     "to offer" % name)
    elif node in PUBLIC_FORBIDDEN_NODENAMES:
        probs.append("%s defaults to the LAN nodename %r" % (name, node))
    if d.get("FB_ROOT_TELNET") != "y":
        probs.append("%s does not default root-telnet to ENABLED (decision 8.6): "
                     "FB_ROOT_TELNET=%r" % (name, d.get("FB_ROOT_TELNET")))
    host = d.get("FB_REPO_HOST") or ""
    url = d.get("FB_REPO_URL") or ""
    if host and url and ("//" + host + "/") not in url and not url.endswith("//" + host):
        probs.append("%s: FB_REPO_URL %r does not name FB_REPO_HOST %r -- the "
                     "baked hosts line would resolve nothing" % (name, url, host))
    # Each release's tree has its own fixed path on the published repository: 1.0 at the
    # root (the frozen 1.0 media), 1.1 at /1.1 (no trailing slash: apkg fetches
    # <repo>/catalog). The dialog swaps only the host and keeps the path.
    if host == "pkg.amigaux.org" and url:
        want = "http://pkg.amigaux.org/1.1" if d.get("INSTALL_LAYOUT") == "1.1" else "http://pkg.amigaux.org"
        if url != want:
            probs.append("%s: FB_REPO_URL %r is not its release's repository tree %s"
                         % (name, url, want))
    return probs


def _audit_public_flavor(profiles):
    pub = [(pf, d) for pf, d in profiles if d.get("FIRSTBOOT_DIALOG") == "y"]
    if not pub:
        fail("NO distro-neutral public profile exists (P8.3): no tracked profile "
             "arms the first-boot dialog, so every disc this tree can master "
             "bakes somebody's LAN")
        return
    probs = []
    for pf, d in pub:
        probs += _public_flavor_problems(pf, d)
    if probs:
        for p in probs:
            fail("public flavor: %s" % p)
    else:
        ok("public flavor(s) %s bake NO LAN facts: %s all empty; generic "
           "nodename; root-telnet enabled; repo URL names the repo host"
           % (", ".join(pf for pf, _ in pub),
              "/".join(k for k, _ in PUBLIC_MUST_BE_EMPTY)))
    # P-15 I1: a public CD/ISO medium carries ONLY its own profile (build-install-iso
    # MEDIUM_PROFILES=requested) -- the LAN profiles beside it would ship the bench's
    # addresses. RAW (self-booting hdf) media keep only the target profile anyway.
    leak = [pf for pf, d in pub
            if d.get("SOURCE_KIND", "") != "raw" and d.get("MEDIUM_PROFILES") != "requested"]
    if leak:
        fail("public CD flavor(s) %s would carry every LAN profile on the disc: set "
             "MEDIUM_PROFILES=requested" % ", ".join(leak))
    else:
        ok("every public CD flavor carries only its own profile (MEDIUM_PROFILES=requested)")
    iso_src = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    if re.search(r'requested\)\s+for _p in "\$\{PROFILES\[@\]\}"; do\s+lab_localize < "\$repo/profiles/\$_p\.profile"', iso_src):
        ok("build-install-iso honours MEDIUM_PROFILES=requested (only the --profile names staged)")
    else:
        fail("build-install-iso does not implement MEDIUM_PROFILES=requested")
    # The LAN flavors are the other half of the contract: they must NOT arm the
    # dialog, or an unattended matrix run would stop at a question forever.
    lan = [pf for pf, d in profiles if d.get("FIRSTBOOT_DIALOG") == "n"]
    if lan:
        ok("the unattended LAN flavors keep FIRSTBOOT_DIALOG=n (%s)"
           % ", ".join(lan))
    else:
        fail("no profile is FIRSTBOOT_DIALOG=n -- the unattended tier has no "
             "profile left and every matrix cell would stop at a question")
    # NEGATIVE FIXTURES -- each way the guarantee could quietly die.
    good = dict((k, "") for k, _ in PUBLIC_MUST_BE_EMPTY)
    good.update({"FB_NODENAME": "amix", "FB_ROOT_TELNET": "y",
                 "FB_REPO_HOST": "pkg.amigaux.org",
                 "FB_REPO_URL": "http://pkg.amigaux.org"})
    if _public_flavor_problems("fixture", good) == []:
        ok("public-flavor fixture: a clean neutral profile passes")
    else:
        fail("public-flavor fixture: a clean neutral profile was REJECTED (%s)"
             % _public_flavor_problems("fixture", good))
    for label, key, val in (
            ("a baked address", "FB_IP", "192.0.2.38"),
            ("a baked gateway", "FB_GATEWAY", "192.0.2.1"),
            ("a baked repo address", "FB_REPO_IP", "192.0.2.2"),
            ("a baked domain", "FB_DOMAIN", "example.net"),
            ("a pinned disk size", "TARGET_DISK_MB", "100"),
            ("the bench nodename", "FB_NODENAME", "uaeamix"),
            ("root-telnet silently off", "FB_ROOT_TELNET", "n"),
            ("a repo URL naming another host", "FB_REPO_URL",
             "http://files.example.net/html/amix")):
        b = dict(good)
        b[key] = val
        if _public_flavor_problems("fixture", b):
            ok("public-flavor gate fires on %s" % label)
        else:
            fail("public-flavor gate does NOT fire on %s (%s=%r)"
                 % (label, key, val))




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


def _ufs_checks(code):
    """The driver-text predicates, as {name: bool}. Taking the TEXT (not the
    path) is what lets the negative fixtures below drive the same code."""
    return {
        "default_ufs": bool(re.search(
            r'^\[ -n "\$TARGET_ROOT_FSTYPE" \] \|\| TARGET_ROOT_FSTYPE=ufs$',
            code, re.M)),
        "validated": bool(re.search(
            r'case "\$TARGET_ROOT_FSTYPE" in\s*\n\s*ufs\)\s*: ;;\s*\n'
            r'\s*s5\)\s*die [^\n]*\n\s*\*\)\s*die ', code)),
        "mkfs_ufs_block": bool(re.search(
            r'run /bin/mkfs_ufs %s "\$ROOT_BLK" "\$ROOTLEN"'
            % re.escape(_UFS_OPT), code)),
        "no_s5_tools": not re.search(r'\b(?:mkfs|fsck)_s5\b|/usr/lib/fs/s5/', code),
        "no_composed_name": not re.search(r'\b(?:mkfs|fsck)_\$\{?[A-Za-z_]', code),
        "no_labelit": "labelit" not in code,
        "prebuilt_retired": bool(re.search(
            r'^\[ "\$\{INSTALL_TARGET_PREBUILT:-0\}" = 1 \] && die ', code, re.M)),
        "mnttab_miniroot_fstype": bool(re.search(
            r'^echo "/dev/root / \$MINIROOT_FSTYPE rw 0" > /etc/mnttab$', code, re.M)),
        "install_cpu_default_030": bool(re.search(
            r'^\[ -n "\$INSTALL_CPU" \] \|\| INSTALL_CPU=030$', code, re.M)),
        "miniroot_fstype_derived": bool(re.search(
            r'case "\$INSTALL_CPU" in\s+030\)\s+MINIROOT_FSTYPE=s5 ;;'
            r'\s+040\|060\)\s+MINIROOT_FSTYPE=ufs ;;\s+\*\)\s+die ', code)),
        "mount_parameterised": bool(re.search(
            r'run /etc/mount "\$ROOT_BLK" "\$TARGET" 0 "\$TARGET_ROOT_FSTYPE"',
            code)),
        "final_fsck_ufs": "run /bin/fsck_ufs \"$ROOT_RAW\"" in code,
        "emits_fb_key": bool(re.search(
            r'echo "FB_ROOT_FSTYPE=\$TARGET_ROOT_FSTYPE"', code)),
    }


def audit_ufs_target():
    head("AA. UFS target filesystem (driver): stock's recipe, the two traps, and "
         "the first-boot handoff")
    driver_src = open(DRIVER, encoding="utf-8").read()
    code = strip_full_comments(driver_src)
    got = _ufs_checks(code)

    for key, msg in (
        ("default_ufs",
         "TARGET_ROOT_FSTYPE defaults to ufs -- s5 is not a target (P-35)"),
        ("validated",
         "TARGET_ROOT_FSTYPE=s5 is refused with its reason and anything else but "
         "ufs fails CLOSED -- never a silent fallback"),
        ("mkfs_ufs_block",
         "the mkfs is stock's line: `mkfs_ufs %s` on the BLOCK node, size in "
         "512-blocks" % _UFS_OPT),
        ("no_s5_tools",
         "no mkfs_s5, fsck_s5 or s5 back end anywhere in the driver's code"),
        ("no_composed_name",
         "no `mkfs_$VAR` / `fsck_$VAR` composed program name anywhere -- every "
         "first word stays a literal audit G can resolve against the proto"),
        ("no_labelit",
         "no labelit (there is no ufs labelit on the medium; stock ran it on "
         "neither filesystem)"),
        ("prebuilt_retired",
         "INSTALL_TARGET_PREBUILT=1 is refused -- mkroot.sh mints s5 only, and s5 "
         "is not a target"),
        ("mnttab_miniroot_fstype",
         "the /etc/mnttab seed line names the running MINIROOT's own fs "
         "($MINIROOT_FSTYPE) -- not the target, so it must never take "
         "$TARGET_ROOT_FSTYPE, and not a hardcoded literal (wrong on the 040/060 "
         "UFS line)"),
        ("install_cpu_default_030",
         "INSTALL_CPU defaults to 030 -- the COMPATIBILITY floor: a profile or "
         "medium written before the key serves the s5-miniroot 030 line and seeds "
         "`s5` byte-identically"),
        ("miniroot_fstype_derived",
         "MINIROOT_FSTYPE is DERIVED from INSTALL_CPU (030 => s5, 040|060 => ufs, "
         "else die) -- ONE source of truth, and the 040/060 line is UFS-only"),
        ("mount_parameterised",
         "the target mount passes the type straight to mount(2) "
         "(/etc/mount has no type table of its own)"),
        ("final_fsck_ufs",
         "the post-unmount fsck_ufs is there (the ONLY fsck of the run)"),
        ("emits_fb_key",
         "the type is handed to the first boot as FB_ROOT_FSTYPE"),
    ):
        if got[key]:
            ok(msg)
        else:
            fail("driver: %s -- NOT found" % msg)

    # --- the medium actually carries what the ufs arm reaches for -------------
    tools = load_proto_tools()
    if tools is None:
        fail("miniroot.proto missing -- cannot check the ufs back end is on the medium")
    else:
        for t in ("mkfs_ufs", "fsck_ufs"):
            if t in tools:
                ok("miniroot.proto carries /bin/%s (so audit G's allowlist covers "
                   "it the moment the driver names it -- no proto change was "
                   "needed for the UFS lane)" % t)
            else:
                fail("miniroot.proto does not carry %s -- the ufs arm would die "
                     "on the box" % t)
        proto_txt = open(PROTO, encoding="utf-8").read()
        if "/usr/lib/fs/ufs/labelit" in proto_txt:
            fail("the proto now carries a ufs labelit -- the driver's 'no labelit "
                 "on ufs' arm is based on its ABSENCE; decide deliberately")
        else:
            ok("the proto carries NO /usr/lib/fs/ufs/labelit -- which is why the "
               "ufs arm skips the step (and why skipping costs the 46-free-block "
               "floppy nothing)")

    # --- the first boot's half ------------------------------------------------
    fb = strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())
    if re.search(r'^\[ -n "\$FB_ROOT_FSTYPE" \] \|\| FB_ROOT_FSTYPE=s5$', fb, re.M):
        ok("firstboot.sh defaults FB_ROOT_FSTYPE to s5 -- a firstboot.conf written "
           "by an older driver writes the identical vfstab it always did")
    else:
        fail("firstboot.sh does not default FB_ROOT_FSTYPE to s5")
    if re.search(r'case "\$FB_ROOT_FSTYPE" in\s*\n\s*s5\|ufs\)', fb):
        ok("firstboot.sh validates FB_ROOT_FSTYPE too -- vfstab column 4 is what "
           "every later boot's fsck and root mount dispatch on, and a typo there "
           "only shows up at the NEXT boot")
    else:
        fail("firstboot.sh does not validate FB_ROOT_FSTYPE")
    if re.search(r'echo "\$ROOT_BLK\t\$ROOT_RAW\t/\t\$FB_ROOT_FSTYPE\t1\tno\t-"', fb):
        ok("/etc/vfstab column 4 is $FB_ROOT_FSTYPE, with the block node in "
           "column 1 and the CHAR node in the fsckdev column (which matters more "
           "on ufs: that is the fsck that actually runs at every boot)")
    else:
        fail("firstboot.sh's vfstab root row is not "
             "$ROOT_BLK $ROOT_RAW / $FB_ROOT_FSTYPE 1 no -")
    # NO generated vfstab row may say `yes` in column 6 (mount at boot). The kernel
    # mounts root itself from its baked-in rootdev, so mountall's attempt EBUSYs and
    # prints three alarming lines on EVERY boot (metal 2026-08-15: "mount: Device
    # busy / mount: /dev/dsk/cNd0s1 on /: Device busy / mount: giving up on: /").
    # The swap row is not a mount at all. Stock's own here-doc ends `1  no  -`; the
    # `yes` was ours. This is a row-wise scan rather than a second literal, so a row
    # added later is covered without anybody remembering to extend the check.
    vrows = re.findall(r'echo "\$(?:ROOT|SWAP)_BLK\t[^"]*"', fb)
    yesrows = [r for r in vrows if "\tyes\t" in r]
    if len(vrows) < 2:
        fail("vacuity: found %d generated vfstab rows in firstboot.sh, expected the "
             "root row and the swap row" % len(vrows))
    elif yesrows:
        for r in yesrows:
            fail("a generated vfstab row orders mountall to mount at boot (column 6 "
                 "`yes`) -- the kernel already mounted root; this is the EBUSY "
                 "grumble: %s" % r)
    else:
        ok("neither generated vfstab row says `yes` in the mount-at-boot column "
           "(%d rows scanned) -- no EBUSY grumble on any boot" % len(vrows))
    if not [r for r in re.findall(r'echo "\$(?:ROOT|SWAP)_BLK\t[^"]*"',
                                  'echo "$ROOT_BLK\t$ROOT_RAW\t/\ts5\t1\tyes\t-"')
            if "\tyes\t" in r]:
        fail("negative fixture did NOT fire: the mount-at-boot scan is broken")
    else:
        ok("negative fixture fires: the exact `1 yes -` root row this installer "
           "wrote until 2026-08-15 is caught")

    # --- every tracked profile declares it ------------------------------------
    profs = sorted(f for f in os.listdir(PROFILES_DIR) if f.endswith(".profile")) \
        if os.path.isdir(PROFILES_DIR) else []
    if not profs:
        fail("no profiles found under %s" % os.path.relpath(PROFILES_DIR, REPO))
    for pf in profs:
        d = _parse_profile(os.path.join(PROFILES_DIR, pf))
        v = d.get("TARGET_ROOT_FSTYPE")
        if v == "ufs":
            ok("%s declares TARGET_ROOT_FSTYPE=%s" % (pf, v))
        else:
            fail("%s declares TARGET_ROOT_FSTYPE=%r -- must be ufs (s5 is not a "
                 "target, P-35; an absent key falls back to a driver default, "
                 "which is exactly the drift the key exists to end)" % (pf, v))
        # INSTALL_CPU is OPTIONAL (absent => 030, the compatibility floor). When
        # present it must be legal, and the 040/060 line is UFS-only -- s5 is
        # structurally broken under 4 KiB pages, so a 040/060 profile that laid an
        # s5 TARGET root would author a filesystem its own kernel cannot mount.
        cpu = d.get("INSTALL_CPU")
        if cpu is None:
            ok("%s omits INSTALL_CPU -- defaults to the 030 s5-miniroot line" % pf)
        elif cpu not in ("030", "040", "060"):
            fail("%s declares INSTALL_CPU=%r -- must be 030, 040 or 060" % (pf, cpu))
        elif cpu in ("040", "060") and v != "ufs":
            fail("%s declares INSTALL_CPU=%s but TARGET_ROOT_FSTYPE=%r -- the "
                 "040/060 line is UFS-only (s5 is structurally broken under 4 KiB "
                 "pages)" % (pf, cpu, v))
        else:
            ok("%s declares INSTALL_CPU=%s (coherent with TARGET_ROOT_FSTYPE=%s)"
               % (pf, cpu, v))

    # --- NEGATIVE FIXTURES: each check must actually FIRE ---------------------
    # A gate that can only ever pass is indistinguishable from no gate. Every
    # fixture below is a plausible wrong version of this change, not a nonsense
    # one: three of the five are edits somebody would make believing they were
    # tidying up.
    for label, broken, key in (
        ("the mnttab seed line parameterised by the TARGET's fs type (the most "
         "plausible wrong 'fix' in this change -- it would describe the RUNNING "
         "MINIROOT as a filesystem it is not, to the one consumer that reads it)",
         code.replace('echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab',
                      'echo "/dev/root / $TARGET_ROOT_FSTYPE rw 0" > /etc/mnttab'),
         "mnttab_miniroot_fstype"),
        ("the mnttab seed reverted to the hardcoded literal `s5` (correct on the "
         "030 line, but it describes the 040/060 line's UFS miniroot AS s5 to "
         "pkgadd/apkg -- exactly the C1 deferral this change closes)",
         code.replace('echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab',
                      'echo "/dev/root / s5 rw 0" > /etc/mnttab'),
         "mnttab_miniroot_fstype"),
        ("the 040/060 arm of the MINIROOT_FSTYPE derivation left at s5 (the ufs "
         "miniroot would seed an s5 mnttab -- pkgadd/apkg told the wrong fs)",
         re.sub(r'(040\|060\)\s+MINIROOT_FSTYPE=)ufs', r'\1s5', code),
         "miniroot_fstype_derived"),
        ("INSTALL_CPU defaulting to 040 instead of 030 (an old profile that omits "
         "the key would suddenly serve the ufs-miniroot line and seed `ufs`)",
         re.sub(r'(\[ -n "\$INSTALL_CPU" \] \|\| INSTALL_CPU=)030', r'\g<1>040', code),
         "install_cpu_default_030"),
        ("mkfs_ufs pointed at the RAW node 'for consistency' with the s5 arm "
         "(stock fed it the block node, and it is the node the mount then uses)",
         code.replace('run /bin/mkfs_ufs %s "$ROOT_BLK"' % _UFS_OPT,
                      'run /bin/mkfs_ufs %s "$ROOT_RAW"' % _UFS_OPT),
         "mkfs_ufs_block"),
        ("the mkfs composed as `mkfs_${TARGET_ROOT_FSTYPE}` (the obvious "
         "refactor, and one the tool allowlist can no longer resolve)",
         code.replace('run /bin/mkfs_ufs %s "$ROOT_BLK"' % _UFS_OPT,
                      'run /bin/mkfs_${TARGET_ROOT_FSTYPE} %s "$ROOT_BLK"' % _UFS_OPT),
         "no_composed_name"),
        ("an s5 arm brought back beside the ufs mkfs",
         code.replace('run /bin/mkfs_ufs %s "$ROOT_BLK" "$ROOTLEN"' % _UFS_OPT,
                      'run /bin/mkfs_ufs %s "$ROOT_BLK" "$ROOTLEN"\n'
                      '\trun /bin/mkfs_s5 "$ROOT_RAW" "$ROOTLEN"' % _UFS_OPT),
         "no_s5_tools"),
        ("the prebuilt-mode refusal dropped, so the driver would mount whatever "
         "mkroot.sh minted (s5) under a ufs vfstab",
         re.sub(r'^\[ "\$\{INSTALL_TARGET_PREBUILT:-0\}" = 1 \] && die [^\n]*\n', "",
                code, flags=re.M),
         "prebuilt_retired"),
        ("labelit called after the mkfs (there is no ufs back end on the "
         "medium, so this dies mid-install with the target half-built)",
         code.replace('run /bin/mkfs_ufs %s "$ROOT_BLK" "$ROOTLEN"' % _UFS_OPT,
                      'run /bin/mkfs_ufs %s "$ROOT_BLK" "$ROOTLEN"\n'
                      '\trun /usr/lib/fs/ufs/labelit "$ROOT_RAW" root ROOT'
                      % _UFS_OPT),
         "no_labelit"),
        ("s5 accepted again instead of refused",
         re.sub(r'(case "\$TARGET_ROOT_FSTYPE" in\n\tufs\)\t: ;;\n)\ts5\)\tdie [^\n]*\n',
                r'\1\ts5)\t: ;;\n', code),
         "validated"),
        ("the fallback reverted to s5",
         code.replace('|| TARGET_ROOT_FSTYPE=ufs', '|| TARGET_ROOT_FSTYPE=s5'),
         "default_ufs"),
    ):
        if broken == code:
            fail("negative fixture did not modify the driver at all (%s) -- the "
                 "check below would be vacuous" % label)
            continue
        if _ufs_checks(broken)[key]:
            fail("audit AA does NOT fire on: %s" % label)
        else:
            ok("fires on %s" % label)


def _fp_checks(code):
    """Structural presence of the §5b installed-tree ufs FP patch, on stripped code."""
    return {
        # only runs for a ufs target AND only when the medium staged /install/fpfix,
        # so an s5 or un-patched medium is byte-unaffected (the presence gate).
        "gated": ('"$TARGET_ROOT_FSTYPE" = ufs' in code) and ('-d "$FPFIX"' in code),
        # patches BOTH installed binaries at their real (symlink-resolved) paths.
        "both_paths": ("/usr/lib/fs/ufs/mkfs" in code) and ("/usr/lib/fs/ufs/fsck" in code),
        # verifies the written binary by sum -r against the staged expected value.
        "verify_sum": ('-r "$fp_dst"' in code) and ('[ "$fp_got" = "$fp_exp" ]' in code),
        # fail-closed: a mismatch dies before first-boot is armed.
        "fail_closed": ("REFUSING to arm" in code and "5b:" in code),
    }


def audit_installed_fp_patch():
    head("AB. Installed-tree ufs FP patch (BLIZZARD F2-M1): install.sh §5b + medium "
         "staging + the 040/060 profile default")
    code = strip_full_comments(open(DRIVER, encoding="utf-8").read())
    got = _fp_checks(code)
    for key, msg in (
        ("gated",
         "§5b runs ONLY for a ufs target AND only when /install/fpfix is present, so "
         "every s5/030 and un-patched medium is byte-unchanged"),
        ("both_paths",
         "it patches BOTH /usr/lib/fs/ufs/{mkfs,fsck} (the real paths /etc/fs/ufs "
         "resolves to via the core symlink)"),
        ("verify_sum",
         "each written binary is verified by `sum -r` against the staged expected "
         "value -- a mis-patched fsck cannot slip through"),
        ("fail_closed",
         "a sum mismatch DIES before first-boot is armed (fail closed)"),
    ):
        if got[key]:
            ok("§5b: %s" % msg)
        else:
            fail("§5b: MISSING -- %s" % msg)

    # negative fixtures: each guard must actually be load-bearing.
    for label, needle in (
        ("the sum-compare line removed", '[ "$fp_got" = "$fp_exp" ]'),
        ("the fpfix presence gate removed", '[ -d "$FPFIX" ]'),
    ):
        broken = code.replace(needle, "", 1)
        if broken == code:
            fail("negative fixture did not modify the driver (%s) -- vacuous" % label)
            continue
        b = _fp_checks(broken)
        if all(b.values()):
            fail("audit AB does NOT fire on: %s" % label)
        else:
            ok("fires on %s" % label)

    # the medium-build side must stage the pair, and the 040/060 profiles must ask
    # for it -- otherwise §5b is dead code no medium ever triggers.
    iso = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    if 'MINIROOT_FP_PATCH' in iso and 'fpfix' in iso and 'patch-ufs-fp.py' in iso:
        ok("build-install-iso.sh stages /install/fpfix when the profile sets "
           "MINIROOT_FP_PATCH (patch-ufs-fp.py on core's ufs pair)")
    else:
        fail("build-install-iso.sh does NOT stage /install/fpfix -- §5b would never fire")
    for prof in ("metal-a4000-z3660-040", "bench-a3000-040"):
        p = open(os.path.join(REPO, "profiles", prof + ".profile"), encoding="utf-8").read()
        if re.search(r'(?m)^MINIROOT_FP_PATCH=yes\s*$', p):
            ok("profile %s sets MINIROOT_FP_PATCH=yes (LC060 default)" % prof)
        else:
            fail("profile %s does NOT set MINIROOT_FP_PATCH=yes" % prof)


def _profile_keys(path):
    d = {}
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k, v = ln.split("=", 1)
        d[k.strip()] = v.strip()
    return d


def _unatt_checks(code):
    """Presence of the miniroot unattended gate, on stripped code."""
    call = re.search(r'(?m)^unattended_check$', code)
    kmap = re.search(r'(?m)^ask_kmap$', code)
    return {
        # the two functions exist and the check is called at top level BEFORE ask_kmap.
        "defined": ("unattended_check()" in code) and ("unattended_run()" in code),
        "before_kmap": bool(call and kmap and call.start() < kmap.start()),
        # RAW candidates only -- never the cdfs list (the second-mount panic class).
        "raw_only": ("$RAW_CANDIDATES" in code) and ("CD_CANDIDATES" not in
                    code[code.find("unattended_check()"):code.find("ask_kmap")] if "unattended_check()" in code else False),
        # double gate: the marker AND the profile key.
        "double_gate": ('-f "$UNATT_MARK"' in code) and ("INSTALL_UNATTENDED=yes)" in code),
        # the driver is handed a /dev/null stdin, and a clean halt ends the run.
        "stdin_and_halt": ("install.sh" in code and "< /dev/null" in code
                           and "/etc/uadmin 2 0" in code),
    }


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


def audit_x11kit_k1():
    head("AX. K1: the RTG X11 kit (X11KIT=rtg) + the card-0 twin profiles")
    driver_src = open(DRIVER, encoding="utf-8", errors="replace").read()
    code = strip_full_comments(driver_src)
    iso_src = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()

    # AX1: up-front validation, EXECUTED.
    m = re.search(r'\ncase "\$X11KIT" in\n(.*?)\nesac\n', code, re.S)
    if not m:
        fail("install.sh has no up-front `case \"$X11KIT\"` validation")
    else:
        snippet = 'die() { echo BAD; exit 1; }\ncase "$X11KIT" in\n' + m.group(1) + '\nesac\necho OK\n'
        wrong = []
        for v, want in (("", "OK"), ("none", "OK"), ("rtg", "OK"), ("RTG", "BAD"), ("yes", "BAD"), ("rtg ", "BAD")):
            r = subprocess.run(["sh", "-c", snippet], env={"X11KIT": v, "PATH": os.environ.get("PATH", "")},
                               capture_output=True, text=True)
            if r.stdout.strip() != want:
                wrong.append((v, r.stdout.strip(), want))
        if wrong:
            fail("install.sh X11KIT validation wrong: %s" % wrong)
        else:
            ok("install.sh X11KIT validation EXECUTED: ''/none/rtg accepted, anything else refused")

    # AX2: the laydown, as the Z3660 station's MG5 install.sh did it.
    want = [
        (r'if\s+\[\s+"\$X11KIT"\s+=\s+rtg\s+\];\s*then', "gate on X11KIT=rtg"),
        (r'run\s+cp\s+"\$INST/x11kit/Xzz9000"\s+"\$TARGET/opt/amix/bin/Xzz9000"', "Xzz9000"),
        (r'run\s+chmod\s+0755\s+"\$TARGET/opt/amix/bin/Xzz9000"', "Xzz9000 755"),
        (r'run\s+cp\s+"\$INST/x11kit/startx-rtg"\s+"\$TARGET/opt/amix/bin/startx-rtg"', "startx-rtg"),
        (r'run\s+chmod\s+0755\s+"\$TARGET/opt/amix/bin/startx-rtg"', "startx-rtg 755"),
        (r'run\s+cp\s+"\$INST/x11kit/rtg-kbdback"\s+"\$TARGET/opt/amix/bin/rtg-kbdback"', "rtg-kbdback (RT-10)"),
        (r'run\s+chmod\s+0755\s+"\$TARGET/opt/amix/bin/rtg-kbdback"', "rtg-kbdback 755"),
        (r'for xf in Xzz9000 rtg-kbdback startx-rtg zz9k_monsw xinitrc-rtg; do\n\t\tcase', "every kit copy re-checked"),
        (r'\[ "\$xs_got" = "\$xs_want" \] \|\| die', "sum -r of each copy == the medium's (cut 4)"),
        (r'run\s+cp\s+"\$INST/x11kit/zz9k_monsw"\s+"\$TARGET/opt/amix/bin/zz9k_monsw"', "zz9k_monsw"),
        (r'run\s+chmod\s+0755\s+"\$TARGET/opt/amix/bin/zz9k_monsw"', "zz9k_monsw 755"),
        (r'run\s+cp\s+"\$INST/x11kit/xinitrc-rtg"\s+"\$TARGET/\.xinitrc-rtg"', ".xinitrc-rtg"),
        (r'run\s+chmod\s+0644\s+"\$TARGET/\.xinitrc-rtg"', ".xinitrc-rtg 644"),
        (r'run\s+mknod\s+"\$TARGET/dev/zz9000"\s+c\s+49\s+0', "/dev/zz9000 c 49 0"),
        (r'run\s+chmod\s+0644\s+"\$TARGET/dev/zz9000"', "/dev/zz9000 0644"),
        (r"echo\s+'PATH=\$PATH:/usr/X/bin; export PATH'\s+>>\s+\"\$TARGET/etc/profile\"", "/usr/X/bin on PATH"),
        (r'run\s+rm\s+-f\s+"\$\{TARGET:\?\}/etc/rtg-monswitch"', "/etc/rtg-monswitch never left behind"),
    ]
    miss = [d for rx, d in want if not re.search(rx, code)]
    if re.search(r'>\s*"?\$TARGET/etc/rtg-monswitch', code):
        miss.append("something WRITES /etc/rtg-monswitch")
    if miss:
        fail("install.sh RTG kit laydown incomplete/wrong: %s" % miss)
    else:
        ok("install.sh lays down the RTG kit as MG5 did (4x755 in /opt/amix/bin incl. rtg-kbdback, "
           "each copy sum -r-verified against the medium, /.xinitrc-rtg 644, "
           "/dev/zz9000 c 49 0, /usr/X/bin on PATH, /etc/rtg-monswitch never written)")

    # AX3 (cut 4): the RTG kit's own manifest is the pin -- KIT.sha256 pinned by hash,
    # build/out checked against it at build time -- plus zz9k_monsw's own pin.
    pins = dict(re.findall(r'^(X11KIT_[A-Z]+_SHA)=([0-9a-f]{64})', iso_src, re.M))
    if sorted(pins) != ["X11KIT_KIT_SHA", "X11KIT_MONSW_SHA"]:
        fail("build-install-iso.sh must pin KIT.sha256 and zz9k_monsw (got %s)" % sorted(pins))
    elif "sha256sum --quiet -c \"$X11KIT_KIT\"" not in iso_src:
        fail("build-install-iso.sh does not check build/out against KIT.sha256")
    else:
        ok("build-install-iso.sh pins the RTG KIT.sha256 and zz9k_monsw and checks build/out "
           "against the kit (STOPs on a mismatch)")
        rtg = os.path.join(REPO, os.pardir, "amix-z3660rtg")
        kit = os.path.join(rtg, "x11", "KIT.sha256")
        if not os.path.isfile(kit):
            ok("KIT.sha256 not present here -- the build-time gate covers it")
        elif hashlib.sha256(open(kit, "rb").read()).hexdigest() != pins["X11KIT_KIT_SHA"]:
            fail("amix-z3660rtg x11/KIT.sha256 no longer hashes to X11KIT_KIT_SHA -- a new kit, re-pin deliberately")
        else:
            bad = []
            for line in open(kit):
                h, n = line.split()
                f = os.path.join(rtg, "build", "out", n)
                if os.path.isfile(f) and hashlib.sha256(open(f, "rb").read()).hexdigest() != h:
                    bad.append(n)
            if bad:
                fail("amix-z3660rtg build/out differs from KIT.sha256: %s" % bad)
            else:
                ok("KIT.sha256 == pin (%s...) and every present build/out file matches it"
                   % pins["X11KIT_KIT_SHA"][:16])
        mon = os.path.join(rtg, "build", "tools", "zz9k_monsw")
        if os.path.isfile(mon) and hashlib.sha256(open(mon, "rb").read()).hexdigest() != pins["X11KIT_MONSW_SHA"]:
            fail("zz9k_monsw no longer hashes to X11KIT_MONSW_SHA")

    # AX4: which profiles carry X11KIT -- exactly the K1 twins -- and the twins differ
    # from their card-1 bases ONLY in the K1 keys.
    k1 = {"metal-a4000-z3660-060-k1.profile": "metal-a4000-z3660-060.profile",
          "metal-a4000-z3660-060-k1-unattended.profile": "metal-a4000-z3660-060-unattended.profile"}
    carriers = []
    for pf in sorted(os.listdir(PROFILES_DIR)):
        if pf.endswith(".profile") and _parse_profile(os.path.join(PROFILES_DIR, pf)).get("X11KIT", "") not in ("", "none"):
            carriers.append(pf)
    # P-15 I2: the public K1 twins carry the same kit (they are the K1 media, made public).
    k1pub = {"public-a4000-z3660-060-k1.profile": "metal-a4000-z3660-060-k1.profile",
             "public-a4000-z3660-060-k1-unattended.profile": "metal-a4000-z3660-060-k1-unattended.profile"}
    # MD-1 (bench): the K1 unattended install retargeted at the A4092 Zulu (card 1).
    k1md1 = {"metal-a4000-z3660-060-k1-a4092-unattended.profile":
             "metal-a4000-z3660-060-k1-unattended.profile"}
    # CD-1 (bench): the K1 interactive install sourced from a CD on the A4092 Zulu.
    k1cd = {"metal-a4000-z3660-060-a4092cd.profile": "metal-a4000-z3660-060-k1.profile"}
    # CD-2 (bench): CD-1 with the target on the A4092 Zulu (card 1 id 1).
    k1cd2 = {"metal-a4000-z3660-060-a4092cd2.profile": "metal-a4000-z3660-060-a4092cd.profile"}
    # S3-45 (stage 3's exit row): the 1.1 module-kernel bench profiles with the RTG desktop,
    # each its l11 base plus z3660rtg and the kit, nothing else (drift-locked here).
    s345 = {"bench-a4000-z3660-060-cd-l11-rtg.profile": "bench-a4000-z3660-060-cd-l11.profile",
            "bench-a3000-a4091-l11-rtg.profile": "bench-a3000-a4091-l11.profile"}
    for rp, bp in sorted(s345.items()):
        rk = _parse_profile(os.path.join(PROFILES_DIR, rp))
        bk = _parse_profile(os.path.join(PROFILES_DIR, bp))
        d = sorted(k for k in set(rk) | set(bk) if rk.get(k) != bk.get(k)
                   and k not in ("PROFILE_NAME", "PROFILE_DESC", "KERNEL_MODPKGS", "X11KIT"))
        mods = rk.get("KERNEL_MODPKGS", "").split()
        if d or rk.get("X11KIT") != "rtg" or not any(m.startswith("z3660rtg-k") for m in mods):
            fail("%s is not %s plus z3660rtg and X11KIT=rtg (also differs on %s)" % (rp, bp, d))
        else:
            ok("%s = %s plus z3660rtg (%s) and X11KIT=rtg, nothing else" % (rp, bp, " ".join(mods)))
    carriers = [c for c in carriers if c not in s345]
    # r6 (D-2): a `<base>-r6[-tag].profile` re-cut carries the kit exactly when its r5 base does.
    _base = sorted(list(k1) + list(k1pub) + list(k1md1) + list(k1cd) + list(k1cd2))
    r6c = [c for c in carriers if "-r6" in c]
    # The PUBLIC CD flavours (owner 2026-10-07) carry the kit exactly when their metal r6 twin does.
    pubcd = {"public-a4000-z3660-060-a4092cd-r6.profile": "metal-a4000-z3660-060-a4092cd-r6.profile",
             "public-a4000-z3660-060-a4092cd2-r6.profile": "metal-a4000-z3660-060-a4092cd2-r6.profile"}
    # The A3000 + 68060 disk image (owner 2026-10-26): an r7 profile of its own, no r5 base;
    # the RTG kit is for its ZZ9000 (Zorro II), so it carries X11KIT by itself.
    pubimg = {"public-a3000-060-wd-r6.profile"}
    r6bad = [c for c in r6c if not (c in pubcd and pubcd[c] in r6c) and c not in pubimg
             and re.sub(r"-r6(-[a-z0-9]+)?\.profile$", ".profile", c) not in _base]
    carriers = [c for c in carriers if "-r6" not in c and not c.startswith("image-")]   # the pre-installed images: own class
    if r6bad:
        fail("r6 profile(s) carry X11KIT but their r5 base does not: %s" % r6bad)
    elif r6c:
        ok("X11KIT on the r6 re-cuts follows their r5 bases: %s" % ", ".join(r6c))
    if sorted(carriers) == sorted(list(k1) + list(k1pub) + list(k1md1) + list(k1cd) + list(k1cd2)):
        ok("X11KIT=rtg is set on exactly the two K1 twins, their two public twins, "
           "the MD-1 A4092 twin and the CD-1 / CD-2 A4092-CD twins")
    else:
        fail("X11KIT carriers %s != the K1 twins + public twins + MD-1 twin + CD-1/CD-2 twins %s"
             % (carriers, sorted(list(k1) + list(k1pub) + list(k1md1) + list(k1cd) + list(k1cd2))))
    k1_keys = {"SRC_SCSI_ID": "6", "SRC_MINIROOT_KERNEL": "KD060-Z-r5-c0-u6",
               "SRC_MINIROOT_ROOTDEV": "0x00480016", "SRC_KERNEL_BREL_SUMR": "55291",
               "TARGET_SCSI_ID": "0", "TARGET_VFSTAB_SCSI_ID": "6", "ROOTDEV": "0x00480016",
               "KERNEL_BREL_SUMR": "55291", "MINIROOT_KERNEL": "KD060-Z-r5-c0-u6",
               "BOOTSLICE_SOURCE_HDF": "work/bootslice-donor/k1-KD060-Z-r5-c0-u6.hdf",
               # O5 r5 (KT-46): the re-pinned KD060-Z carries the sddevsize fix
               "KERNEL_SDDEVSIZE": "fixed",
               "X11KIT": "rtg", "FB_TZ": "EET", "FB_TZNUM": "27",
               # REL-2: a K1 installer beats a stock pri-0 AmigaOS DH0, loses to the installed disk (2)
               "SRC_BOOT_BOOTPRI": "1",
               # Q-4.15: the bench K1 media keep the fixed unit-6 root
               "RUN_UNIT": "6"}
    for twin, base in sorted(k1.items()):
        tp, bp = os.path.join(PROFILES_DIR, twin), os.path.join(PROFILES_DIR, base)
        if not (os.path.isfile(tp) and os.path.isfile(bp)):
            fail("K1 twin or base missing: %s / %s" % (twin, base))
            continue
        t, b = _parse_profile(tp), _parse_profile(bp)
        bad = [k for k, v in k1_keys.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in k1_keys and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        if bad or diff:
            fail("%s: K1 keys wrong %s / unexpected differences from %s: %s" % (twin, bad, base, diff))
        else:
            ok("%s = %s + exactly the card-0 K1 keys (source 6 / target 0 / rootdev 0x00480016 / "
               "KD060-Z r5 c0-u6 sum -r 55291, sddevsize fixed) + X11KIT=rtg + FB_TZ=EET (menu index 27)" % (twin, base))

    # AX5 (P-15 I2): each public K1 twin is its bench K1 twin with ONLY the public FB_*
    # seam changed -- the install rig (kernel, chain, ids, kit, MONSW) is identical, so
    # the bench proof of the K1 media carries over and only the seam needs its own cells.
    pub_seam = {"FB_NODENAME": "amix", "FB_DOMAIN": "", "FB_TZNUM": "", "FB_TZ": "",
                "FB_IP": "", "FB_NETMASK": "", "FB_GATEWAY": "", "FB_ZEN_CARDS": "",
                "FB_REPO_IP": "", "FIRSTBOOT_DIALOG": "y", "TARGET_DISK_MB": "",
                "TARGET_ERASE_OK": None,
                # Q-4.15 pick-at-install: the public media root the unit they install to
                "RUN_UNIT": "install", "INSTALLABLE_IDS": "0 1 2 3 4 5",
                "UNIT_TABLE": "profiles/units/KD060-Z-r5.units", "TARGET_VFSTAB_SCSI_ID": ""}
    for pub, bench in sorted(k1pub.items()):
        pp, bp = os.path.join(PROFILES_DIR, pub), os.path.join(PROFILES_DIR, bench)
        if not (os.path.isfile(pp) and os.path.isfile(bp)):
            fail("public K1 twin or its bench twin missing: %s / %s" % (pub, bench))
            continue
        t, b = _parse_profile(pp), _parse_profile(bp)
        bad = [k for k, v in pub_seam.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in pub_seam
                      and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        if bad or diff:
            fail("%s: public seam wrong %s / unexpected differences from %s: %s"
                 % (pub, bad, bench, diff))
        else:
            ok("%s = %s + exactly the public FB_* seam (dialog on, no LAN/zone/card facts, "
               "probed target size, erase refused, installer bootpri 1 (REL-2))" % (pub, bench))

    # AX6 (MD-1): the A4092 Zulu twin is the bench K1 unattended profile with ONLY the
    # card-1 target keys changed: the boot-slice kernel (KD060-ZA-c1-u6, rootdev ced0s1),
    # the vfstab controller (e = card 1 | unit 6), the sddevsize class, and no re-wipe.
    md1_keys = {"ROOTDEV": "0x0048001E", "TARGET_VFSTAB_SCSI_ID": "e", "KERNEL_BREL_SUMR": "61397",
                "BOOTSLICE_SOURCE_HDF": "work/bootslice-donor/md1-KD060-ZA-dl4-c1-u6.hdf",
                "KERNEL_SDDEVSIZE": "fixed", "TARGET_ERASE_OK": None, "TARGET_DISK_MB": "512",
                # the MD-1 image (2026-10-03, fa74c511) was built on the KT-12g SOURCE kernel; the
                # K1 twin moved to O5 r5 after it, MD-1 stays bench-only and is not re-cut
                "SRC_MINIROOT_KERNEL": "KD060-Z-KT12g-c0-u6", "SRC_KERNEL_BREL_SUMR": "08512",
                "MINIROOT_KERNEL": "KD060-Z-KT12g-c0-u6"}
    for twin, base in sorted(k1md1.items()):
        tp, bp = os.path.join(PROFILES_DIR, twin), os.path.join(PROFILES_DIR, base)
        if not (os.path.isfile(tp) and os.path.isfile(bp)):
            fail("MD-1 twin or its base missing: %s / %s" % (twin, base))
            continue
        t, b = _parse_profile(tp), _parse_profile(bp)
        bad = [k for k, v in md1_keys.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in md1_keys
                      and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        if bad or diff:
            fail("%s: card-1 keys wrong %s / unexpected differences from %s: %s"
                 % (twin, bad, base, diff))
        else:
            ok("%s = %s + exactly the card-1 target keys (ZA-c1-u6 61397, rootdev ced0s1, "
               "vfstab e, sddevsize fixed, erase refused, 512 MB Zulu image)" % (twin, base))

    # AX7 (CD-1): the A4092-CD twin is the bench K1 interactive profile with ONLY the
    # source keys changed: cdfs at 1,3 (the Zulu CD, card 1 id 3), the boot .hdf's
    # KD060-ZA-CD miniroot kernel, the RAW-only keys gone, and no re-wipe. The target
    # (ids, chain, kernel, identity, kit) is the K1 one byte for byte.
    cd1_keys = {"SOURCE_KIND": "cdfs", "CD_SPEC": "1,3",
                "SRC_MINIROOT_KERNEL": "KD060-ZA-CD-c0-u6", "MINIROOT_KERNEL": "KD060-ZA-CD-c0-u6",
                "SRC_KERNEL_BREL_SUMR": "28708",
                "SRC_PAYLOAD_SLICE": None, "SRC_RAW_SLICE": None, "SRC_APKG_TIMEOUT": None,
                "RAW_EXTRA_PKGS": None, "TARGET_ERASE_OK": None, "INSTALL_UNATTENDED": None,
                "SRC_SCSI_ID": "6", "TARGET_SCSI_ID": "0"}
    for twin, base in sorted(k1cd.items()):
        tp, bp = os.path.join(PROFILES_DIR, twin), os.path.join(PROFILES_DIR, base)
        if not (os.path.isfile(tp) and os.path.isfile(bp)):
            fail("CD-1 twin or its base missing: %s / %s" % (twin, base))
            continue
        t, b = _parse_profile(tp), _parse_profile(bp)
        bad = [k for k, v in cd1_keys.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in cd1_keys
                      and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        if bad or diff:
            fail("%s: CD-1 source keys wrong %s / unexpected differences from %s: %s"
                 % (twin, bad, base, diff))
        else:
            ok("%s = %s + exactly the CD-1 source keys (cdfs 1,3, KD060-ZA-CD c0-u6 28708 boot kernel, "
               "no RAW keys, erase refused, interactive)" % (twin, base))

    # AX9 / AX10 (CD-2): the metal and the emulator CD-2 profiles are their CD-1 twins with
    # ONLY the target keys changed -- the Zulu / A4091 disk at card 1 unit 1 (c9d0), the
    # KD060-ZA c1-u1 chain (rootdev c9d0s1), the profile-named scan -- source unchanged.
    cd2_keys = {"TARGET_HBA": "a4091", "TARGET_SCSI_ID": "9", "TARGET_VFSTAB_SCSI_ID": "9",
                "TARGET_SCAN_IDS": "9", "ROOTDEV": "0x00480019", "KERNEL_BREL_SUMR": "27291",
                "BOOTSLICE_SOURCE_HDF": "work/bootslice-donor/cd2-KD060-ZA-c1-u1.hdf",
                "TARGET_DISK_MB": "512", "TARGET_ERASE_OK": None,
                # the boot disk stays on the Z3660 while the target moves to card 1, so
                # its controller is named for its DosEnvec Mask (tools/lib/dmamask.py)
                "SRC_HBA": "z3660scsi"}
    for twin, base, tag in (("metal-a4000-z3660-060-a4092cd2.profile", "metal-a4000-z3660-060-a4092cd.profile", "AX9"),
                            ("bench-a4000-z3660-060-a4092cd2.profile", "bench-a4000-z3660-060-a4092cd.profile", "AX10")):
        tp, bp = os.path.join(PROFILES_DIR, twin), os.path.join(PROFILES_DIR, base)
        if not (os.path.isfile(tp) and os.path.isfile(bp)):
            fail("%s: CD-2 twin or its base missing: %s / %s" % (tag, twin, base))
            continue
        t, b = _parse_profile(tp), _parse_profile(bp)
        bad = [k for k, v in cd2_keys.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in cd2_keys
                      and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        if bad or diff:
            fail("%s %s: CD-2 target keys wrong %s / unexpected differences from %s: %s"
                 % (tag, twin, bad, base, diff))
        else:
            ok("%s %s = %s + exactly the CD-2 target keys (A4092/A4091 card 1 id 1 = c9d0, "
               "KD060-ZA c1-u1 27291, scan id 9 only, 512 MB, erase refused)" % (tag, twin, base))

    # AX8 (CD-1 emulator twin, cell cd1-emu): the fd060-cd bench profile with ONLY the
    # CD-1 source/target keys changed -- cdfs 1,3, the KD060-ZA-CD boot .hdf at unit 6,
    # target unit 0 rooting c6d0s1 after the move -- so the matrix's bench-identity
    # gates and the `minimal` reference digest carry over unchanged.
    cd1e = ("bench-a4000-z3660-060-a4092cd.profile", "bench-a4000-z3660-060-cd.profile")
    cd1e_keys = {"CD_SPEC": "1,3", "TARGET_SCSI_ID": "0", "TARGET_VFSTAB_SCSI_ID": "6", "RUN_UNIT": "6",
                 "SRC_SCSI_ID": "6", "SRC_MINIROOT_KERNEL": "KD060-ZA-CD-c0-u6",
                 "SRC_MINIROOT_ROOTDEV": "0x00480016", "SRC_KERNEL_BREL_SUMR": "28708",
                 "SRC_BOOT_BOOTPRI": "1", "TARGET_BOOT_BOOTPRI": "2",
                 "MINIROOT_KERNEL": "KD060-ZA-CD-c0-u6"}
    tp, bp = os.path.join(PROFILES_DIR, cd1e[0]), os.path.join(PROFILES_DIR, cd1e[1])
    if not (os.path.isfile(tp) and os.path.isfile(bp)):
        fail("CD-1 emulator twin or its base missing: %s / %s" % cd1e)
    else:
        t, b = _parse_profile(tp), _parse_profile(bp)
        bad = [k for k, v in cd1e_keys.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b)
                      if t.get(k) != b.get(k) and k not in cd1e_keys
                      and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        m = _parse_profile(os.path.join(PROFILES_DIR, "metal-a4000-z3660-060-a4092cd.profile"))
        drift = [k for k in ("CD_SPEC", "SRC_SCSI_ID", "SRC_MINIROOT_KERNEL", "SRC_MINIROOT_ROOTDEV",
                             "SRC_KERNEL_BREL_SUMR", "SRC_BOOT_BOOTPRI", "SRC_BOOT2_IDENTITY",
                             "TARGET_SCSI_ID", "TARGET_VFSTAB_SCSI_ID", "ROOTDEV", "KERNEL_BREL_SUMR",
                             "BOOTSLICE_SOURCE_HDF") if t.get(k) != m.get(k)]
        if bad or diff or drift:
            fail("%s: CD-1 keys wrong %s / unexpected differences from %s: %s / drift from the metal "
                 "CD-1 profile: %s" % (cd1e[0], bad, cd1e[1], diff, drift))
        else:
            ok("%s = %s + exactly the CD-1 source/target keys, and its boot/target chain keys equal "
               "the metal CD-1 profile's" % cd1e)


def audit_cd2_card1_target():
    head("CD2. a card-1 target (CD-2, 2026-10-05): profile-named scan, CD unit + host ids never opened, nodes made")
    setup = open(SETUP, encoding="latin-1").read()
    drv = open(DRIVER, encoding="latin-1").read()
    proto = open(PROTO, encoding="utf-8").read()

    def fn(text, name):
        m = re.search(r"(?m)^%s\(\)\n\{\n.*?\n\}\n" % re.escape(name), text, re.S)
        return m.group(0) if m else None

    # the majors the helpers hard-code are miniroot.proto's own
    pb = re.search(r"(?m)^b\s+(?:\S+\s+){4}/dev/dsk/c0d0s0\s+(\d+),0\s*$", proto)
    pc = re.search(r"(?m)^c\s+(?:\S+\s+){4}/dev/rdsk/c0d0s0\s+(\d+),0\s*$", proto)
    for name, text in (("setup.sh", setup), ("install.sh", drv)):
        bm = re.search(r"(?m)^SD_BMAJ=(\d+)$", text)
        cm = re.search(r"(?m)^SD_CMAJ=(\d+)$", text)
        if pb and pc and bm and cm and (bm.group(1), cm.group(1)) == (pb.group(1), pc.group(1)):
            ok("%s: SD_BMAJ/SD_CMAJ %s/%s == miniroot.proto's sd majors" % (name, bm.group(1), cm.group(1)))
        else:
            fail("%s: SD_BMAJ/SD_CMAJ do not match miniroot.proto's /dev/[r]dsk majors" % name)
    # one helper, two copies: they must be the same text
    for f in ("hexval", "hexname", "cd_unit_id", "ensure_disk_nodes"):
        a, b = fn(setup, f), fn(drv, f)
        if a and b and a == b:
            ok("%s() is byte-identical in setup.sh and install.sh" % f)
        else:
            fail("%s() differs between setup.sh and install.sh (or is missing)" % f)
    # the scan honours TARGET_SCAN_IDS and filters AFTER the profile is sourced
    i_prof = setup.find('. "$PROFILE_FILE"')
    i_scan = setup.find('SCAN_IDS="$TARGET_SCAN_IDS"')
    i_filt = setup.find("SCAN_IDS=`scan_safe_ids $SCAN_IDS`")
    if 0 <= i_prof < i_scan < i_filt:
        ok("setup.sh: TARGET_SCAN_IDS replaces the scan, then scan_safe_ids filters it, after the profile is sourced")
    else:
        fail("setup.sh: TARGET_SCAN_IDS / scan_safe_ids are missing or run before the profile is sourced")

    if not os.path.exists("/usr/bin/dash"):
        skip("dash absent -- the CD2 behaviour cases cannot run")
        return
    # route B (2026-10-08): setup.sh's copy of the miniroot's CD probe walk must be the walk itself
    mp = open(MINIROOT_PROFILE, encoding="latin-1").read()
    mc = re.search(r'(?m)^CD_CANDIDATES="([^"]*)"$', mp)
    sc = re.search(r'(?m)^MINIROOT_CD_CANDIDATES="([^"]*)"$', setup)
    if mc and sc and mc.group(1) == sc.group(1):
        ok("setup.sh MINIROOT_CD_CANDIDATES == src/miniroot/profile CD_CANDIDATES (%s)" % sc.group(1))
    else:
        fail("setup.sh MINIROOT_CD_CANDIDATES differs from src/miniroot/profile CD_CANDIDATES (or is missing)")
    body = (sc.group(0) if sc else "") + "\n" + "\n".join(
        fn(setup, f) for f in ("hexval", "hexname", "cd_unit_id", "spec_id", "scan_safe_ids"))
    body += "\nSD_BMAJ=18\nSD_CMAJ=40\n" + fn(setup, "ensure_disk_nodes").replace("/bin/mknod", "echo MKNOD")
    cases = [
        ("CD_SPEC=1,3 INSTALLABLE_IDS=9", "scan_safe_ids 8 9 a b c d e f", "8 9 c d e",
         "card-1 scan drops the CD (b), the other card-1 CD candidate (a) and the host (f)"),
        ("CD_SPEC=1,3 INSTALLABLE_IDS=6", "scan_safe_ids 0 1 2 3 5 6", "0 1 5 6",
         "route B: public classic (CD_SPEC 1,3, the CD found at 0,3) never opens card-0 ids 2/3"),
        ("CD_SPEC=0,3 INSTALLABLE_IDS=6", "scan_safe_ids 0 1 2 3 5 6", "0 1 5 6", "bench A4000/030 (CD_SPEC 0,3): same scan"),
        ('CD_SPEC=1,3 INSTALLABLE_IDS="0 1 2 3 4 5"', "scan_safe_ids 0 1 2 3 5 6 4", "0 1 2 3 5 6 4",
         "K1 (units 0-5 installable): candidate ids 2/3 that are installable stay"),
        ("CD_SPEC=0,2 INSTALLABLE_IDS=0", "scan_safe_ids 0 1 2 3 5 6", "0 1 5 6", "a Z3660 CD (0,2) is dropped from the card-0 scan"),
        ("CD_SPEC= INSTALLABLE_IDS=0", "scan_safe_ids 0 7 9 f", "0 9", "no CD candidate among them: only the host ids go"),
        ("CD_SPEC=1,3", "spec_id 0,3; spec_id 1,2", "3\na", "spec_id: 0,3 -> 3, 1,2 -> a"),
        ("CD_SPEC=1,3", "cd_unit_id", "b", "cdfs 1,3 is controller digit b"),
        ("CD_SPEC=1,3", "ensure_disk_nodes 9 | grep 'dsk/c9d0s1 '", "MKNOD /dev/dsk/c9d0s1 b 18 25\nMKNOD /dev/rdsk/c9d0s1 c 40 25",
         "c9d0s1 = 18,25 / 40,25 (the stock /dev's c9d0s1)"),
        ("CD_SPEC=1,3", "ensure_disk_nodes z; echo rc=$?", "rc=1", "a non-digit id is refused"),
        # C4-1 (four cards): c10-c1f, the card's high bit is minor bit 7
        ("CD_SPEC=1,3", "ensure_disk_nodes 1e | grep 'dsk/c1ed0s1 '", "MKNOD /dev/dsk/c1ed0s1 b 18 158\nMKNOD /dev/rdsk/c1ed0s1 c 40 158",
         "C4-1: c1ed0s1 (card 3 unit 6) = 18,158: slice 1, card bit 0 = 1, unit 6, bit 7"),
        ("CD_SPEC=1,3", "ensure_disk_nodes 10 | grep 'dsk/c10d0s0 '", "MKNOD /dev/dsk/c10d0s0 b 18 128\nMKNOD /dev/rdsk/c10d0s0 c 40 128",
         "C4-1: c10d0s0 (card 2 unit 0) = 18,128"),
        ("CD_SPEC=", "hexval 1f; hexval 1a; hexval 20; echo .", "31\n26\n\n.", "C4-1: hexval 1f = 31, 1a = 26, 20 refused"),
        ("CD_SPEC=", "hexname 14; hexname 16; hexname 31", "e\n10\n1f", "C4-1: hexname 14 = e, 16 = 10, 31 = 1f"),
        ("CD_SPEC=3,3", "cd_unit_id", "1b", "C4-1: cdfs 3,3 is controller number 1b"),
        ("CD_SPEC= INSTALLABLE_IDS=16", "scan_safe_ids 16 17 1e 1f", "16 1e", "C4-1: the card-2/3 host ids 17 and 1f go"),
    ]
    for env, call, want, what in cases:
        r = subprocess.run(["/usr/bin/dash", "-c", "%s\n%s\n%s" % (env, body, call)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        got = r.stdout.decode().strip()
        if got == want:
            ok("CD2 behaviour: %s" % what)
        else:
            fail("CD2 behaviour: %s -- got %r, want %r" % (what, got, want))
    # D-2 (r6): every installable id is added to the scan (then filtered), so the
    # picker can offer unit 4 and card-1 ids the miniroot ships no node for.
    m = re.search(r'(?ms)^for _id in \$INSTALLABLE_IDS\ndo\n\tcase " \$SCAN_IDS ".*?^SCAN_IDS=`scan_safe_ids \$SCAN_IDS`$', setup)
    if not m:
        fail("setup.sh: the D-2 installable-id union block is missing")
    else:
        for env, want, what in (
                ('SCAN_IDS="0 1 2 3 5 6"; INSTALLABLE_IDS="0 1 2 3 4 5"; CD_SPEC=', "0 1 2 3 5 6 4",
                 "public K1 (INSTALLABLE_IDS 0-5): unit 4 joins the scan"),
                ('SCAN_IDS="9"; INSTALLABLE_IDS="9"; CD_SPEC=1,3', "9",
                 "CD-2: the profile-named id only"),
                ('SCAN_IDS="0 1 2 3 5 6"; INSTALLABLE_IDS="6 b"; CD_SPEC=1,3', "0 1 5 6",
                 "an installable id that IS the CD's unit is still dropped; non-installable CD candidates go")):
            r = subprocess.run(["/usr/bin/dash", "-c", "%s\n%s\n%s\necho \"$SCAN_IDS\"" % (env, body, m.group(0))],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            got = r.stdout.decode().strip()
            if got == want:
                ok("D-2 scan union: %s -> %s" % (what, got))
            else:
                fail("D-2 scan union: %s -- got %r, want %r" % (what, got, want))
    # install.sh refuses the CD's unit and the host ids as a target
    seg = drv[drv.index('[ -n "`hexval "$ID"`" ]'):drv.index('if [ ! -b "/dev/dsk/c${ID}d0s0" ]')]
    pre = "\n".join(fn(drv, f) for f in ("hexval", "hexname", "cd_unit_id")) + '\ndie() { echo "DIE $*"; exit 1; }\n'
    for env, want in (("ID=b SOURCE_KIND=cdfs CD_SPEC=1,3", "DIE"), ("ID=7 SOURCE_KIND=cdfs CD_SPEC=1,3", "DIE"),
                      ("ID=f SOURCE_KIND=raw", "DIE"), ("ID=9 SOURCE_KIND=cdfs CD_SPEC=1,3", "PASS"),
                      ("ID=x SOURCE_KIND=cdfs CD_SPEC=1,3", "DIE"), ("ID=1f SOURCE_KIND=raw", "DIE"),
                      ("ID=1e SOURCE_KIND=raw", "PASS"), ("ID=1b SOURCE_KIND=cdfs CD_SPEC=3,3", "DIE")):
        r = subprocess.run(["/usr/bin/dash", "-c", "%s\n%s\n%s\necho PASS" % (env, pre, seg)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        got = "DIE" if "DIE" in r.stdout.decode() else ("PASS" if "PASS" in r.stdout.decode() else r.stdout.decode())
        if got == want:
            ok("CD2 install.sh target guard: %s -> %s" % (env.split()[0], want))
        else:
            fail("CD2 install.sh target guard: %s -> %r, want %s" % (env, got, want))



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


def audit_rth1_byte_writer():
    head("RTH1W. D-2 byte writer: install.sh's oct_file/put_bytes/byte_is EXECUTED (stamp u6->u2, an RTO1 record)")
    drv = read_sh(DRIVER)

    def fn(name):
        m = re.search(r"(?ms)^%s\(\)\s*\{\n.*?\n\}\n" % re.escape(name), drv)
        return m.group(0) if m else None
    funcs = [fn(n) for n in ("is_num", "oct_file", "put_bytes", "byte_is")]
    if None in funcs:
        fail("could not extract install.sh's byte-writer helpers")
        return
    q = os.path.join(REPO, "..", "amix-kerntools", "work", "k0-chains", "KD060-Z", "q415", "bootslice")
    u6, u2 = os.path.join(q, "KD060-Z-c0-u6.bootslice"), os.path.join(q, "KD060-Z-c0-u2.bootslice")
    if not (os.path.isfile(u6) and os.path.isfile(u2)) or not os.path.exists("/usr/bin/dash"):
        skip("kerntools q415 bootslices or dash absent -- the byte writer cannot be executed")
        return
    d = workpath("rth1w")
    os.makedirs(os.path.join(d, "inst", "bin"), exist_ok=True)
    os.makedirs(os.path.join(d, "tgt", "tmp"), exist_ok=True)
    sumbin = os.path.join(d, "inst", "bin", "sum")
    if not os.path.exists(sumbin):
        os.symlink(shutil.which("sum") or "/usr/bin/sum", sumbin)
    dev = os.path.join(d, "slice3")
    shutil.copyfile(u6, dev)
    tool = os.path.join(REPO, "tools", "rth1-media.py")
    pt = os.path.join(d, "pt")
    subprocess.run([sys.executable, tool, "stamp", "--family", u6, "--unit", "2:%s" % u2, "--out", pt],
                   capture_output=True, check=True)
    rows = [l.split() for l in open(os.path.join(pt, "u2.patch")) if l.strip() and not l.startswith("#")]
    # a regular file stands in for the raw slice: GNU dd truncates on seek= without notrunc
    # (a raw device never does), so a wrapper adds it for writes to the stand-in only.
    pre = ("dd() { case \"$*\" in *of=%s*) command dd \"$@\" conv=notrunc ;; *) command dd \"$@\" ;; esac; }\n"
           "INST=%s\nTARGET=%s\n" % (dev, os.path.join(d, "inst"), os.path.join(d, "tgt"))) + "".join(funcs)
    script = pre
    for blk, off, o in rows:
        script += ('oct_file %s/tgt/tmp/b %s && put_bytes %s %s %s 1 %s/tgt/tmp/b || echo PUTFAIL\n'
                   'dd if=%s of=%s/tgt/tmp/r bs=512 skip=%s count=1 2>/dev/null\n'
                   'byte_is %s/tgt/tmp/r %s %s || echo CHKFAIL\n'
                   % (d, o, dev, blk, off, d, dev, d, blk, d, off, o))
    script += "byte_is %s/tgt/tmp/r %s 000 && echo FALSEPASS\n" % (d, rows[-1][1])
    r = subprocess.run(["/usr/bin/dash", "-c", script], capture_output=True, text=True, timeout=120)
    same = open(dev, "rb").read() == open(u2, "rb").read()
    if same and "FAIL" not in r.stdout and "FALSEPASS" not in r.stdout and len(rows) == 3:
        ok("stamp u6 -> u2 with the miniroot's tools: %d byte(s), result == kerntools' q415 u2 bootslice; "
           "byte_is refuses a wrong byte" % len(rows))
    else:
        fail("stamp u6 -> u2: identical=%s rows=%d out=%r err=%r" % (same, len(rows), r.stdout[-200:], r.stderr[-200:]))
    # an RTO1 record: 28 bytes at block 19 +256, each read back
    rt = os.path.join(d, "rto1")
    subprocess.run([sys.executable, tool, "rto1", "--chain", u6, "--ids", "9", "--card", "1", "0", "0xC0DE0100", "0",
                    "--out", rt], capture_output=True, check=True)
    row = [l.split() for l in open(rt) if l.strip() and not l.startswith("#")][0]
    octs = row[3:]
    shutil.copyfile(u6, dev)
    script = pre + "oct_file %s/tgt/tmp/rec %s && put_bytes %s 19 256 28 %s/tgt/tmp/rec || echo PUTFAIL\n" % (
        d, " ".join(octs), dev, d)
    script += "dd if=%s of=%s/tgt/tmp/rb bs=512 skip=19 count=1 2>/dev/null\n" % (dev, d)
    for i, o in enumerate(octs):
        script += "byte_is %s/tgt/tmp/rb %d %s || echo CHKFAIL%d\n" % (d, 256 + i, o, i)
    r = subprocess.run(["/usr/bin/dash", "-c", script], capture_output=True, text=True, timeout=120)
    got = open(dev, "rb").read()
    import struct as _st
    rec = got[0x2700:0x271c]
    want_rest = open(u6, "rb").read()
    rest_same = got[:0x2700] == want_rest[:0x2700] and got[0x271c:] == want_rest[0x271c:]
    if (rec[:4] == b"RTO1" and sum(_st.unpack(">7I", rec)) & 0xffffffff == 0 and _st.unpack(">7I", rec)[2] == 1
            and rest_same and "FAIL" not in r.stdout and len(octs) == 28):
        ok("RTO1 for id 9 (card 1 unit 1, id 0xc0de0100) written at 0x2700, 28 bytes read back one by one, "
           "nothing else in the slice changed")
    else:
        fail("RTO1 write: rec=%r rest_same=%s out=%r" % (rec, rest_same, r.stdout[-200:]))


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
    # a genuine stock /etc/rdb RDB (RDSK at block 2): the first MiB of the metal golden, read-only
    gold = os.path.join(REPO, "..", "amix-images", "masters", "amix-z3660-metal-golden-2026-07-15.hdf")
    if os.path.isfile(gold):
        with open(gold, "rb") as fh:
            img = fh.read(1 << 20)
        r, got = run(img, "a4092")
        probs = dm.check_image(got, 0x07FFFFFE)[0]
        if r.returncode == 0 and not probs and only_mask_moved(img, got):
            ok("the stock-authored metal golden's RDB (RDSK at 2, /etc/rdb's Mask 0xFFFFFFFC) -> 0x07FFFFFE, "
               "checksums close, nothing else moved")
        else:
            fail("metal golden RDB: rc=%d problems=%s out=%r" % (r.returncode, probs, r.stdout[-200:]))
    else:
        skip("amix-images metal golden absent -- the genuine /etc/rdb RDB case is not run")


def audit_fd060_omit():
    head("AT. P-15 I5: the 040/060 root floppy's omit list (miniroot/fd060.omit)")
    path = os.path.join(REPO, "miniroot", "fd060.omit")
    if not os.path.isfile(path):
        fail("miniroot/fd060.omit missing")
        return
    omitted = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            omitted.append(line.split()[0])
    # Each omitted tool may be CALLED only from the s5 arms the 040/060 line can never
    # take (the interview and the driver lock that line to ufs); the tape-installer
    # tools may not be called at all. A new caller anywhere fails here, before a
    # floppy that lacks the tool ships.
    allowed = {"fsck_s5": [r'run /bin/fsck_s5 "\$ROOT_RAW"', r'fsck_s5 -y \$UPART'],
               "mkfs_s5": [r'run /bin/mkfs_s5 "\$ROOT_RAW" "\$ROOTLEN"'],
               "labelit": [r'run /usr/lib/fs/s5/labelit "\$ROOT_RAW" root ROOT'],
               "mtret": [], "viper_kludge": [], "zcat": []}
    srcs = [DRIVER, SETUP, MINIROOT_PROFILE,
            os.path.join(REPO, "payload", "firstboot", "firstboot.sh")]
    bad = []
    for o in omitted:
        name = os.path.basename(o)
        if name not in allowed:
            bad.append("%s has no reviewed caller rule" % o)
            continue
        for f in srcs:
            code = strip_full_comments(open(f, encoding="latin-1").read())
            for ln in code.split("\n"):
                if re.search(r'(^|[\s/;|&(`])%s(\s|$|;)' % re.escape(name), ln):
                    t = ln.strip()
                    if not any(re.search(a, t) for a in allowed[name]):
                        bad.append("%s: %s calls %s" % (os.path.basename(f), t[:80], name))
    if bad:
        for b in bad:
            fail("fd060.omit: %s" % b)
    else:
        ok("fd060.omit: %d omitted tools, every caller is a ufs-excluded s5 arm or none "
           "(%s)" % (len(omitted), ", ".join(os.path.basename(o) for o in omitted)))
    # The s5 arms must really be the ELSE of a ufs test on the paths the 040/060 line runs.
    drv = strip_full_comments(open(DRIVER, encoding="latin-1").read())
    setup = strip_full_comments(open(SETUP, encoding="latin-1").read())
    if re.search(r'^\s*ANS_FSYS=ufs\b', setup, re.M) and "ANS_FSYS=s5" not in setup \
            and "What file system type" not in setup:
        ok("fd060.omit: the interview composes ufs and never asks (P-35) -- the s5 tools are unreachable")
    else:
        fail("fd060.omit: setup.sh can compose a non-ufs root again -- the s5 tools would be reachable")


def audit_firstboot_perms():
    head("AU. the first-boot state dir is root's alone (P-15, 2026-10-03)")
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
    if "mv $HOSTS.zn$$ $HOSTS && chmod 444 $HOSTS" not in zen:
        miss2.append("S99zen hosts 0444 after its own-row rewrite")
    if miss2:
        fail("boot-time rewrites leave world-writable files (init's umask is 0): %s" % miss2)
    else:
        ok("boot-time rewrites restore modes: /etc/inet/hosts 0444 (firstboot x2, S99zen), "
           "/etc/tz.index 0644")


def audit_rtc():
    head("AR. IN-rtc: RTC=setclk (our Y2K, gated setclk over the stock one + /etc/clkzone) and "
         "the grimoire-20 aging floor")
    driver_src = open(DRIVER, encoding="utf-8", errors="replace").read()
    code = strip_full_comments(driver_src)
    iso_src = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    patch = open(os.path.join(REPO, "src", "setclk", "setclk-y2k.patch"), encoding="utf-8").read()

    # AR1: RTC validation, EXECUTED (default setclk; none; nothing else).
    m = re.search(r'\n\[ -n "\$RTC" \] \|\| RTC=setclk\ncase "\$RTC" in\n(.*?)\nesac\n', code, re.S)
    if not m:
        fail("install.sh has no RTC default + validation")
    else:
        snippet = ('die() { echo BAD; exit 1; }\n[ -n "$RTC" ] || RTC=setclk\ncase "$RTC" in\n'
                   + m.group(1) + '\nesac\necho "OK $RTC"\n')
        wrong = []
        for v, want in (("", "OK setclk"), ("setclk", "OK setclk"), ("none", "OK none"),
                        ("yes", "BAD"), ("SETCLK", "BAD")):
            r = subprocess.run(["sh", "-c", snippet], env={"RTC": v, "PATH": os.environ.get("PATH", "")},
                               capture_output=True, text=True)
            if r.stdout.strip() != want:
                wrong.append((v, r.stdout.strip(), want))
        if wrong:
            fail("install.sh RTC validation wrong: %s" % wrong)
        else:
            ok("install.sh RTC validation EXECUTED: unset -> setclk, setclk/none accepted, else refused")

    # AR2: the laydown -- over the STOCK file (keeps amiga:amiga), 0755, clkzone default ":<FB_TZ>".
    want = [
        (r'\[ -n "\$FB_CLKZONE" \] \|\| FB_CLKZONE=":\$FB_TZ"', "FB_CLKZONE defaults to :<FB_TZ> (the RTC keeps local time)"),
        (r'if\s+\[\s+"\$RTC"\s+=\s+setclk\s+\];\s*then', "gate on RTC=setclk"),
        (r'run\s+cp\s+"\$INST/setclk"\s+"\$TARGET/usr/amiga/bin/setclk"', "our setclk over the stock file"),
        (r'run\s+chmod\s+0755\s+"\$TARGET/usr/amiga/bin/setclk"', "setclk 0755"),
        (r'echo\s+"\$FB_CLKZONE"\s+>\s+"\$TARGET/etc/clkzone"', "/etc/clkzone written"),
        (r'run\s+chmod\s+0644\s+"\$TARGET/etc/clkzone"', "/etc/clkzone 0644"),
        (r'\[ -f "\$TARGET/usr/amiga/bin/setclk" \] \|\| die', "refuses when there is no stock setclk to replace"),
    ]
    miss = [d for rx, d in want if not re.search(rx, code)]
    if miss:
        fail("install.sh setclk laydown incomplete: %s" % miss)
    else:
        ok("install.sh lays our setclk ONTO the stock file (cp keeps amiga:amiga), 0755, and writes "
           "/etc/clkzone (default :<FB_TZ>); RTC=none touches nothing")

    # AR3: the medium pins the binary; the patch carries the gate and both console lines.
    pin = re.search(r'^SETCLK_SHA=([0-9a-f]{64})$', iso_src, re.M)
    pbin = os.path.join(REPO, "payload", "setclk")
    if not pin:
        fail("build-install-iso.sh does not pin SETCLK_SHA")
    elif os.path.isfile(pbin):
        got = hashlib.sha256(open(pbin, "rb").read()).hexdigest()
        if got == pin.group(1):
            ok("payload/setclk hashes to the pinned SETCLK_SHA (%s...)" % got[:16])
        else:
            fail("payload/setclk sha256 %s != pinned %s" % (got[:16], pin.group(1)[:16]))
    else:
        ok("SETCLK_SHA pinned; payload/setclk not built here -- the build-time gate covers it")
    need = ["%02d%02d%02d%02d%03d", "tmpbuf[8] = '2'", "694224000L", "2145916799L",
            "not plausible (1992..2037), clock left alone", "-> system clock set",
            "utc = mktime(&tm);", "stime(&utc)", "putenv(bexleyTZ);", ":%02d %s (%s)",
            "tm.tm_isdst = 1;", "localtime(&utc)->tm_isdst > 0"]
    missing = [n for n in need if n not in patch]
    added = "\n".join(l for l in patch.splitlines() if l.startswith("+"))
    if missing:
        fail("setclk-y2k.patch lacks %s" % missing)
    elif re.search(r'^-.*/usr/bin/date', patch, re.M) is None or "/usr/bin/date" in added:
        fail("setclk-y2k.patch: the rc path must drop date(1) for mktime + stime (IN-rtc-2)")
    else:
        ok("setclk-y2k.patch: %03d year scan, 4-digit year, the 1992..2037 gate, both "
           "console lines, and the clock set to the second (mktime in /etc/clkzone, summer "
           "time re-read with tm_isdst 1, + stime; the date(1) call removed)")

    # AR4 (grimoire 20): every root-password path the installer controls leaves root's
    # lastchg/aging fields EMPTY, so a battery clock set back can never expire the password.
    rs = open(os.path.join(REPO, "payload", "firstboot", "root.shadow"), encoding="utf-8").read().strip()
    fb = open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"), encoding="utf-8").read()
    bad = []
    if not re.match(r'^root:[^:]*:::::::$', rs):
        bad.append("payload/firstboot/root.shadow is not root:<hash>::::::: (%r)" % rs.split(":")[2:])
    if "printf 'root:%s:::::::\\n'" not in iso_src:
        bad.append("build-install-iso's FB_ROOT_SEED_PW path does not write empty aging fields")
    if 's|^root:[^:]*:.*|root:$newhash:::::::|' not in fb:
        bad.append("firstboot's shadow rewrite does not leave the aging fields empty")
    # ...and the dialog's own passwd/amixmkuser steps (which stamp lastchg with the clock
    # of the moment) are followed by clear_lastchg, whose sed is EXECUTED here.
    if not re.search(r'ask_passwords\n\s*ask_users\n\s*clear_lastchg\n', fb):
        bad.append("the first-boot dialog does not run clear_lastchg after ask_passwords/ask_users")
    m = re.search(r"sed '(s\|\^\\\(\[\^:\]\*:\[\^:\]\*:\\\)\[\^:\]\*:\|\\1:\|)' /etc/shadow", fb)
    if not m:
        bad.append("clear_lastchg's sed expression not found")
    else:
        r = subprocess.run(["sed", m.group(1)], input="root:H:20000:0:99:7:::\nu:h::::::\n",
                           capture_output=True, text=True)
        if r.stdout != "root:H::0:99:7:::\nu:h::::::\n":
            bad.append("clear_lastchg's sed does not empty ONLY field 3 (got %r)" % r.stdout)
    if bad:
        fail("grimoire-20 aging floor: %s" % bad)
    else:
        ok("grimoire-20: root.shadow, the FB_ROOT_SEED_PW path and firstboot's rewrite all leave "
           "root's lastchg/aging EMPTY, and the first-boot dialog clears every account's lastchg "
           "after its passwd steps (sed EXECUTED) -- a clock set back cannot expire a password")


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


def audit_ide_kit():
    head("AI. C6: the A4000 Gayle-IDE CF kit profiles (public-a4000-ide[-unattended])")
    base = os.path.join(PROFILES_DIR, "public-a3000-a4091.profile")
    ide_keys = {"TARGET_ROOT_FSTYPE": "ufs", "TARGET_DISK_MB": "512", "KERNEL_BREL_SUMR": "19293",
                "MINIROOT_KERNEL": "K030-IDE-c0-u6",
                "BOOTSLICE_SOURCE_HDF": "work/bootslice-donor/ide-K030-IDE-c0-u6.hdf",
                "BOOTSLICE_IMG": "boot/ide/bootslice.img", "BOOTSLICE_MANIFEST": "boot/ide/bootslice.manifest",
                "BOOT2_BOOT": "boot/ide/boot2.boot", "TARGET_VFSTAB_SCSI_ID": "6",
                "IMAGE_KIT": "y", "RTC": "setclk", "KERNEL_SDDEVSIZE": "stock",
                "TARGET_HBA": "gayle"}   # where the CF runs: its RDB Mask (tools/lib/dmamask.py)
    twins = {"public-a4000-ide.profile": {}, "public-a4000-ide-unattended.profile": {"INSTALL_UNATTENDED": "yes"}}
    b = _parse_profile(base) if os.path.isfile(base) else None
    for twin, extra in sorted(twins.items()):
        tp = os.path.join(PROFILES_DIR, twin)
        if b is None or not os.path.isfile(tp):
            fail("C6: %s or its base is missing" % twin)
            continue
        t = _parse_profile(tp)
        want = dict(ide_keys, **extra)
        bad = [k for k, v in want.items() if t.get(k) != v]
        diff = sorted(k for k in set(t) | set(b) if t.get(k) != b.get(k)
                      and k not in want and k not in ("PROFILE_NAME", "PROFILE_DESC"))
        forbidden = [k for k in ("MONSW", "X11KIT", "FB_ZEN_CARDS", "BOOTSLICE_BOOT2_IDENTITY")
                     if t.get(k) not in (None, "", "none")]
        if bad or diff or forbidden or t.get("FB_ETHER_IF") == "zen0":
            fail("C6 %s: IDE keys wrong %s / unexpected differences from the public base %s / "
                 "Z3660-lane keys %s" % (twin, bad, diff, forbidden))
        else:
            ok("C6 %s = public-a3000-a4091 + exactly the IDE image-kit keys (K030-IDE sum -r 19293, "
               "root c6d0s1 ufs, 512 MB image, stock `good` boot2 by default, RTC=setclk%s); no "
               "Z3660/RTG/monsw keys" % (twin, ", unattended" if extra else ""))
    # The dialog's zone choice follows into /etc/clkzone (a public image cannot know
    # the zone its owner's battery clock is kept in).
    fb = open(os.path.join(REPO, "payload", "firstboot", "firstboot.sh"), encoding="latin-1").read()
    if re.search(r'if \[ -f /etc/clkzone \] && \[ -n "\$ZSET" \]; then\n\s*echo "\$ZSET" > /etc/clkzone', fb):
        ok("firstboot: the dialog's timezone choice is written to /etc/clkzone when setclk is installed")
    else:
        fail("firstboot: the dialog's timezone choice does not follow into /etc/clkzone")


def audit_pick_at_install():
    """Q-4.15 (owner, 2026-10-03): the root unit is chosen AT INSTALL on the public K1 media.
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
        # D-2 (r6): the stamp table of RUN_UNIT=stamp
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
            # D-2 (r6): hint -- the family chain to any id unchanged; vfstab follows the id
            (("hint", 3, "060"), (0, "R|boot/metal/bootslice.img|boot/metal/bootslice.man|boot/metal/boot2.boot|"
                                     "0x00480016|08512|3|boot/metal/unix")),
            # D-2 (r6): stamp -- the family chain + the unit's patch; its own manifest, rootdev,
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
        ("build-install-iso stages one chain per unit (--expect-sumr --write-kernel) + boot/<p>/units",
         "--expect-sumr" in biso and '>> "$outdir/units"' in biso),
        ("build-install-iso ships boot/<p>/unix for every 040/060 chain", "040|060) BSARGS+=(--write-kernel)" in biso),
    ]
    for what, good in checks:
        (ok if good else fail)(what)


def audit_unattended():
    head("AC. Unattended demo-card path (v3): the miniroot gate + the drift-locked "
         "profile + the marker")
    code = strip_full_comments(read_sh(MINIROOT_PROFILE))
    got = _unatt_checks(code)
    for key, msg in (
        ("defined", "unattended_check() + unattended_run() are defined"),
        ("before_kmap", "unattended_check runs at top level BEFORE ask_kmap, so a "
                        "gated card needs ZERO console input"),
        ("raw_only", "it probes only $RAW_CANDIDATES, never the cdfs list -- the "
                     "second-mount panic class cannot arise"),
        ("double_gate", "double-gated: the /install/UNATTENDED marker AND an on-slice "
                        "INSTALL_UNATTENDED=yes are both required"),
        ("stdin_and_halt", "the driver gets a /dev/null stdin and a clean `/etc/uadmin "
                           "2 0` ends the run (METAL-FIX.3 held; known end state)"),
    ):
        if got[key]:
            ok("AC: %s" % msg)
        else:
            fail("AC: MISSING -- %s" % msg)

    # negative fixtures: the two gate halves must be load-bearing.
    for label, needle in (
        ("the marker check removed", '-f "$UNATT_MARK"'),
        ("the profile-key check removed", "INSTALL_UNATTENDED=yes)"),
    ):
        broken = code.replace(needle, "", 1)
        if broken == code:
            fail("negative fixture did not modify the profile (%s) -- vacuous" % label)
            continue
        if _unatt_checks(broken)["double_gate"]:
            fail("audit AC does NOT fire on: %s" % label)
        else:
            ok("fires on %s" % label)

    # drift lock: -060-unattended must equal -060 on EVERY key except the three.
    base = _profile_keys(os.path.join(REPO, "profiles", "metal-a4000-z3660-060.profile"))
    un = _profile_keys(os.path.join(REPO, "profiles", "metal-a4000-z3660-060-unattended.profile"))
    allowed = {"PROFILE_NAME", "PROFILE_DESC", "INSTALL_UNATTENDED"}
    diffs = [k for k in set(base) | set(un)
             if k not in allowed and base.get(k) != un.get(k)]
    if diffs:
        fail("metal-a4000-z3660-060-unattended DIFFERS from -060 on %s -- drift; "
             "the two must match on every key but %s" % (sorted(diffs), sorted(allowed)))
    elif un.get("INSTALL_UNATTENDED") != "yes":
        fail("metal-a4000-z3660-060-unattended does NOT set INSTALL_UNATTENDED=yes")
    elif base.get("INSTALL_UNATTENDED") == "yes":
        fail("metal-a4000-z3660-060 (interactive) unexpectedly sets INSTALL_UNATTENDED=yes")
    else:
        ok("metal-a4000-z3660-060-unattended == -060 on every key except "
           "PROFILE_NAME/DESC + INSTALL_UNATTENDED=yes (drift-locked)")

    # build-install-iso writes the marker only under the key.
    iso = open(os.path.join(REPO, "tools", "build-install-iso.sh"), encoding="utf-8").read()
    if "INSTALL_UNATTENDED" in iso and '"$STAGE/UNATTENDED"' in iso:
        ok("build-install-iso.sh writes /install/UNATTENDED gated on INSTALL_UNATTENDED")
    else:
        fail("build-install-iso.sh does NOT write /install/UNATTENDED under the key")

    # CARD-1 topology guard: the metal-060 line installs on the real LC060 where
    # touching ANY card-0 device (c0..c7) bus-errors (FPE-R7-METAL 3.1). SRC_SCSI_ID
    # and TARGET_SCSI_ID are used directly as c<ID>d0, so BOTH must resolve to card 1
    # (minor-nibble >> 3 == 1). This is the exact bug the v2/v3 media shipped
    # (SRC=0=c0d0, TARGET=6=c6d0, both card 0) which panicked on metal.
    for pk in (base, un):
        pn = pk.get("PROFILE_NAME", "?")
        for key in ("SRC_SCSI_ID", "TARGET_SCSI_ID"):
            v = pk.get(key, "")
            try:
                card = int(v, 16) >> 3
            except ValueError:
                fail("%s: %s=%r is not a hex device index" % (pn, key, v)); continue
            if card == 1:
                ok("%s: %s=%s is CARD 1 (device c%sd0) -- never card 0" % (pn, key, v, v))
            else:
                fail("%s: %s=%s resolves to CARD %d (c%sd0) -- on the real LC060 the "
                     "first I/O to a card-0 node bus-errors; the metal-060 line must "
                     "be card 1 (e.g. SRC_SCSI_ID=e / TARGET_SCSI_ID=8)"
                     % (pn, key, v, card, v))


# P-36: the upgrade install's names; none may come back into the driver or l11.sh
_P36_GONE = ("l11_upgrade_capture", "l11_upgrade_restore", "l11_upgrade_apply", "l11_keep_layout",
             "S17upgrade", "SWAP_HOLD", "UPGRADE_KIND", "L11_KEEP", "DATA_KEEP", "FB_UPGRADED",
             "/var/adm/upgrade", "UPGRADE_DROP_HOME")


def _p36_problems(install_src, l11_src):
    """What keeps install.sh + l11.sh from being clean-install only (P-36)."""
    probs = []
    if not re.search(r'\ncase "\$\{INSTALL_UPGRADE:-no\}" in\n\tno\)\t: ;;\n\t\*\)\tdie "[^"\n]*'
                     r'1\.1 requires a fresh install, P-36', install_src):
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
        def run(stub, hba):
            kb = os.path.join(d, "bin", "kbootset")
            if stub is None:
                if os.path.exists(kb): os.remove(kb)
            else:
                open(kb, "w").write("#!/bin/sh\n%s\n" % stub); os.chmod(kb, 0o755)
            body = ('L11=%s\nTARGET_SCSI_ID=e\nTARGET_ROOT_SLICE=1\nTARGET_HBA=%s\nKBOOTSET_BOOTDEV=\n'
                    'msg() { echo "MSG $*"; }\ndie() { echo "DIE $*"; exit 3; }\n%s\necho "BOOTDEV=$KBOOTSET_BOOTDEV"\n'
                    'echo "CTL=$L11_CTL"\n' % (d, hba, m.group(1)))
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
        bad = []
        for w, stub, hba, want in cases:
            out = run(stub, hba)
            if not all(x in out for x in want):
                bad.append("%s: %r" % (w, out.strip().splitlines()[-2:]))
        (fail if bad else ok)("kbootset cards EXECUTED (5 cases: the disk's key wins, Zorro key, no `cards`, a card "
                              "not in the table, no kbootset; each names its source for the log)%s"
                              % ((": " + "; ".join(bad)) if bad else ""))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def audit_swap_stepdown():
    head("SW. the swap slice is added in steps (SWAP_ADD_MB): sizes tried in order, the first the "
         "kernel takes is used and logged, no size twice; default 30 MiB on 030, all on 040/060")
    src = open(DRIVER, encoding="utf-8").read()
    m = re.search(r'\n(\t\[ -n "\$SWAP_ADD_MB" \] \|\| case .*?\n\tearly_target_swap\(\) \{\n.*?\n\t\})\n', src, re.S)
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
        ("030 default: 30 MiB only", "030", "", 10**9, ["TRY 61440", "ADDED=/dev/dsk/c6d0s2 0 61440"], ["TRY 131072"]),
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


def audit_guarded_rm_mv():
    head("RG. every rm and mv on a variable path names it \"${var:?}\" (an empty variable stops the "
         "script instead of widening the path)")
    import glob
    rx_cmd = re.compile(r'(?<![\w-])(rm|mv)(?=\s)')
    rx_var = re.compile(r'"\$(\{[A-Za-z_][A-Za-z_0-9]*\}|[A-Za-z_][A-Za-z_0-9]*)')
    rx_end = re.compile(r';|&&|\|\||\||\bthen\b|\bdo\b')
    bad = []
    files = sorted(glob.glob(os.path.join(REPO, "tools", "*.sh")) + glob.glob(os.path.join(REPO, "tools", "lib", "*.sh"))
                   + glob.glob(os.path.join(REPO, "src", "installer", "*.sh")) + glob.glob(os.path.join(REPO, "payload", "*.sh"))
                   + glob.glob(os.path.join(REPO, "payload", "firstboot", "*.sh")))
    for f in files:
        for n, l in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
            if l.lstrip().startswith("#"):
                continue
            for m in rx_cmd.finditer(l):
                if re.search(r'(^|\s)#', l[:m.start()]):
                    break
                e = rx_end.search(l, m.end())
                if rx_var.search(l[m.end():e.start() if e else len(l)]):
                    bad.append("%s:%d" % (os.path.relpath(f, REPO), n))
    (fail if bad else ok)("rm/mv variable paths guarded in %d scripts%s"
                          % (len(files), (": " + " ".join(bad[:8])) if bad else ""))


def audit_ufs_rootcap():
    head("UC. the ufs ceiling: a 1.1 root is refused above 2047 MiB (4194303 blocks), in the interview "
         "and in the driver; the stock kernel's smaller cap still wins")
    for path, name in ((SETUP, "setup.sh"), (DRIVER, "install.sh")):
        src = open(path, encoding="utf-8").read()
        m = re.search(r'\n(\tROOTCAP= ROOTCAP_WHY=.*?\n\tfi\n)', src, re.S)
        if not m:
            fail("%s: no ROOTCAP block with the 1.1 ufs ceiling" % name)
            continue
        wrong = []
        for layout, fixed, want in (("1.1", "fixed", "2047"), ("1.0", "fixed", ""),
                                    ("1.1", "", "602"), ("", "fixed", "")):
            body = ('BLOCKS_PER_MB=2048\nSDDEV_CAP_BLOCKS=1234567\nINSTALL_LAYOUT="%s"\nKERNEL_SDDEVSIZE="%s"\n%s'
                    'echo "CAP=$ROOTCAP"\n' % (layout, fixed, m.group(1)))
            r = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=10)
            if r.stdout.strip() != "CAP=" + want:
                wrong.append((layout, fixed, r.stdout.strip(), want))
        (fail if wrong else ok)("%s: root cap EXECUTED -- 1.1 = 2047, 1.0 = none, the stock 602 MB cap "
                                "wins below it%s" % (name, (": %r" % wrong) if wrong else ""))
    im = open(os.path.join(REPO, "tools", "install-matrix.sh"), encoding="utf-8").read()
    (ok if ': > "$RUN/serial.log"\n    python3 "$KT/tools/rig-serial.py"' in im else fail)(
        "install-matrix: the floppy cells' serial capture starts from an empty serial.log (a reused "
        "outdir's old 'starting the kernel' would end the volume follower)")


def audit_l11():
    """L11. The 1.1 disk layout (amix-dlm spec 40, stage 2 S2-30/S2-31), EXECUTED
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

    # (5) P-36: 1.1 supports clean installs only -- install.sh refuses INSTALL_UPGRADE,
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
        "the P-36 audit catches the negative fixture (refusal dropped, capture back): %s" % ("; ".join(fp) or "nothing"))
    fbl = [w for w in _P36_GONE if w in strip_full_comments(open(FIRSTBOOT, encoding="utf-8").read())]
    (ok if not fbl else fail)("firstboot.sh: no upgrade branch (FB_UPGRADED)%s"
                              % ((" -- still: " + " ".join(fbl)) if fbl else ""))
    m = re.search(r'\ncase "\$\{INSTALL_UPGRADE:-no\}" in\n.*?\nesac\n', src, re.S)
    if m:
        for val, want in (("", "PASSED"), ("no", "PASSED"), ("yes", "DIE"), ("y", "DIE")):
            body = 'die() { echo "DIE $*"; exit 3; }\n' + ("INSTALL_UPGRADE=%s\n" % val if val else "") \
                   + m.group(0) + "echo PASSED\n"
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            good = want in out and (want == "PASSED" or "fresh install, P-36" in out)
            (ok if good else fail)("install.sh, INSTALL_UPGRADE=%s: %s" % (val or "(unset)", out.strip()[:90]))

    # (5b) the base packages. l11_base adds base/order's packages under the
    # target's chroot with APKGENG's engine (the miniroot has no cmp for the conffile class),
    # seeds each one's conffile baselines first, transfers amix-base's conffiles from core
    # with removef, refuses a PENDING; install.sh calls it before the kernel-space step; the
    # medium stages base/ from the pkgmaps and takes inittab from amix-base
    lb = _extract_func(l11, "l11_base") or ""
    iso = open(os.path.join(HERE, "build-install-iso.sh"), encoding="utf-8").read()
    for what, good in (
            ("l11_base runs seed.sh then APKGENG's pkgadd under the target's chroot, per base/order",
             re.search(r'for _p in \$_ord\n.*?"\$_cr" "\$TARGET" /bin/sh /tmp/l11base/seed\.sh'
                       r'.*?runq "\$_cr" "\$TARGET" /usr/apkg/bin/pkgadd -n -a /tmp/l11base/admin', lb, re.S)),
            ("l11_base takes base/order, then the chosen set's base/o.<set>, and drops each datastream after its pkgadd",
             '_ord=`cat "$L11/base/order"`' in lb
             and '[ -f "$L11/base/o.$INSTALL_SET" ] && _ord="$_ord `cat "$L11/base/o.$INSTALL_SET"`"' in lb
             and 'run rm -f "${_bd:?}/$_f"' in lb),
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
                       "domain example.net"] and "syslogd=no" in rc and "\nswap_add=all 48 30\n" in rc
              and "monsw 34" in disp
              and "start manual" in disp and "card auto" in disp
              and "/usr/sbin/ifup -n" in crl and "/usr/amix/bin/xstart -n" in crl else fail)(
            "l11_admin, the bench profile: aen0 static, zen0 beside it, domain; syslogd=no; swap_add; monsw; checked: %r %r" % (ifs, out))
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

    # (10) S3-31 l11_keys' module half: a module kernel brings modtools; KERNEL_MODPKGS
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
             _extract_func(l11, "l11_kpkg_key") + "\n" + _extract_func(l11, "l11_keys") +
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

    # (11) S3-31 l11_kpkg_record for a module: name, role and the file lines of its
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

    # (12) S3-31 l11_namelist (C2-4 v9 §12): /stand/unix (core's link to 2.1_unix) and /unix
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

    # (13) S3-31 S99zen beside another interface: install.sh lays it for a z3660eth module
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

    # (14) S3-31 first boot on a 1.1 disk: /stand/unix out of core (APKG's tools from /tmp,
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

    # (19) P-36: 1.1 supports clean installs only -- a disk that holds Amix is asked the
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
    m = re.search(r'\nif \[ "\$INSTALL_LAYOUT" = 1\.1 \]; then\n\tORDCDEV=.*?\nfi\n', src, re.S)
    if not m:
        fail("install.sh has no m4 check of a 1.1 order")
    else:
        ct = os.path.join(d, "cdev")
        os.makedirs(os.path.join(ct, "tmp"), exist_ok=True)
        for what, pkgs, want in (("an order with m4", "core bsd APKG m4", "PASSED"),
                                 ("an order with Cdev", "core bsd Cdev APKG", "PASSED"),
                                 ("an order with neither", "core bsd APKG", "DIE install order")):
            open(os.path.join(ct, "order"), "w").write("# set: minimal\n" + "\n".join(pkgs.split()) + "\n")
            body = ('die() { echo "DIE $*"; exit 3; }\nINSTALL_LAYOUT=1.1\nTARGET=%s\nORDER=%s/order\n'
                    % (ct, ct) + m.group(0) + "echo PASSED\n")
            out = subprocess.run(["/usr/bin/dash", "-c", body], capture_output=True, text=True, timeout=30).stdout
            (ok if want in out and not os.listdir(os.path.join(ct, "tmp")) else fail)(
                "install.sh's 1.1 m4 check, %s: %s" % (what, "accepted" if "PASSED" in out else "refused"))

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

    # (17) S5-44 R2 (C2-4 v12 §14): firstboot's step 4d is `kbootset nodes`, ungated by
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
    audit_arith()
    audit_presets()
    audit_seed_firstboot()
    audit_tool_allowlist()
    audit_subshell_loops()
    audit_setcount_guard()
    audit_firstboot_wiring()
    audit_erase_guard()
    audit_rdb_location()
    audit_interactive_card1_scan()
    audit_card1_derivation_exec()
    audit_x11_easystart()
    audit_apkg_timeouts()
    audit_w64b_completeness()
    audit_repo_host()
    audit_raw_arm()
    audit_bootable_source()
    audit_updbootpart()
    audit_zen_bringup()
    audit_monsw()
    audit_x11kit_k1()
    audit_rtc()
    audit_fd060_omit()
    audit_cd2_card1_target()
    audit_rth1_byte_writer()
    audit_dmamask_stamp()
    audit_apkg_conf_order()
    audit_030_rootswap()
    audit_firstboot_perms()
    audit_tz()
    audit_ide_kit()
    audit_framing_tools()
    audit_syslog_unit()
    audit_w1_plumbing()
    audit_null_redirect_loops()
    audit_w2_structure()
    audit_w2_sizing()
    audit_w2_interview()
    audit_w3b_metadata()
    audit_w4_miniroot_profile()
    audit_w5_dialog()
    audit_ufs_target()
    audit_installed_fp_patch()
    audit_unattended()
    audit_pick_at_install()
    audit_ufs_density()
    audit_modreg_local()
    audit_kbootset_cards()
    audit_swap_stepdown()
    audit_guarded_rm_mv()
    audit_ufs_rootcap()
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
