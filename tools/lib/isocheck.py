# tools/lib/isocheck.py -- the install-CD's hard constraints, as checkable functions.
#
# Every constraint here corresponds to a way the disc SILENTLY misbehaves on Amix:
# nothing in this file guards against a loud failure. They are separated from
# tools/build-iso.sh so that build-iso.sh --self-test can drive each one against a
# crafted violation and prove it actually fires -- a constraint that has never been
# observed to fail is an assumption, not a check.
#
# Checks operate on the MASTERED IMAGE wherever the constraint is only observable
# after mastering (renames, on-disc names, session count, catalog resolution). A
# staging tree that looks right and an image that came out wrong is precisely the
# failure mode these exist to catch, so verifying the inputs would miss the point.
#
# Stdlib-only, python3. Synthetic fixtures only; no proprietary content.

import hashlib
import os
import re

# ODFS_NAME_MAX on Amix is 512. The 128-byte cap that appears in ODFileSystem is
# the AmigaOS platform limit, NOT ours -- checking against 128 would reject
# perfectly legal discs, and checking against nothing would let cdfs truncate.
ODFS_NAME_MAX = 512

SECTOR = 2048
ISO_VD_SIG = b"CD001"


class Violation(object):
    """One constraint failure, with enough context to act on."""

    def __init__(self, kind, detail, hint=""):
        self.kind = kind
        self.detail = detail
        self.hint = hint

    def __str__(self):
        s = "[%s] %s" % (self.kind, self.detail)
        if self.hint:
            s += "\n        %s" % self.hint
        return s


# ---------------------------------------------------------------- pathnames ---

def walk_rel(root):
    """Every file under root, as a sorted list of '/'-joined relative paths."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for f in sorted(filenames):
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            out.append(rel.replace(os.sep, "/"))
    return sorted(out)


def walk_rel_dirs(root):
    """Every directory under root, as sorted relative paths."""
    out = []
    for dirpath, dirnames, _ in os.walk(root):
        dirnames.sort()
        for d in dirnames:
            rel = os.path.relpath(os.path.join(dirpath, d), root)
            out.append(rel.replace(os.sep, "/"))
    return sorted(out)


def check_no_spaces(paths):
    """NO SPACES in any pathname on the disc -- a HARD error, never a warning.

    Precedent: exactly one file was excluded tape-wide from the whole 28,866-member
    stock repackaging ('.../MacFS/TrueType Fonts') because prototype(5) cannot
    represent a space in a pathname. A disc that carries one produces a package the
    installer cannot describe, and it does so quietly."""
    bad = []
    for p in paths:
        if " " in p or "\t" in p:
            bad.append(Violation(
                "space-in-pathname", "%r contains whitespace" % p,
                "prototype(5) cannot represent a space in a pathname; the stock "
                "repackaging excluded its single offender tape-wide for this reason."))
    return bad


def check_name_length(paths, limit=ODFS_NAME_MAX):
    """Every path COMPONENT must fit ODFS_NAME_MAX (512 on Amix)."""
    bad = []
    for p in paths:
        for comp in p.split("/"):
            if len(comp) > limit:
                bad.append(Violation(
                    "name-too-long",
                    "component %d bytes (limit %d) in %r" % (len(comp), limit, p),
                    "ODFS_NAME_MAX is %d on Amix; the 128 cap is the AmigaOS "
                    "platform only." % limit))
    return bad


def check_no_compression(paths):
    """NO .Z on the disc.

    We have 700 MB of medium and a 68030: zcat costs more than the sectors it
    saves, and decompressing needs writable temp space the installer environment
    may not have. gen-catalog.py accepts .pkg.Z, so this must be refused here
    rather than assumed absent."""
    bad = []
    for p in paths:
        if p.endswith(".Z"):
            bad.append(Violation(
                "compressed-payload", "%r is compress(1)-compressed" % p,
                "A 68030 spends more time in zcat than in the extra sectors, and "
                "the installer environment may have no writable temp space."))
    return bad


def check_no_collisions(paths):
    """No two entries in one directory may collide under case folding.

    cdfs applies deterministic ~2/~3 renaming on a name collision. A rename
    silently breaks the catalog's `filename` lookup: the catalog says one thing and
    the disc holds another, and nothing reports it. This is the PRE-flight half;
    check_zero_renames() below is the authoritative post-master half."""
    bad = []
    seen = {}
    for p in paths:
        d, _, base = p.rpartition("/")
        key = (d, base.lower())
        if key in seen:
            bad.append(Violation(
                "name-collision",
                "%r and %r collide case-insensitively in %r" % (seen[key], p, d or "/"),
                "cdfs would rename one to ~2, and the catalog's filename lookup "
                "would then miss it silently."))
        else:
            seen[key] = p
    return bad


def check_zero_renames(staged_paths, disc_paths):
    """ZERO collision renames: the disc's names must equal the staged names exactly.

    This is the authoritative check, because it reads the MASTERED image: it catches
    a cdfs-style ~2/~3 rename, an ISO9660 truncation, a lost Rock Ridge name (which
    would surface as FOO.PKG;1) and a dropped file, all as the same assertion. If
    Rock Ridge were off, every name would mismatch here."""
    bad = []
    s, d = set(staged_paths), set(disc_paths)
    for p in sorted(s - d):
        bad.append(Violation(
            "missing-on-disc", "%r was staged but is not on the mastered disc" % p,
            "If a same-directory name collided, cdfs/ISO renaming is the usual cause."))
    for p in sorted(d - s):
        bad.append(Violation(
            "renamed-on-disc", "%r is on the disc but was never staged" % p,
            "This is the shape of a ~2/~3 collision rename or an ISO9660 name "
            "mangle -- the catalog's filename lookup will not find it."))
    return bad


# ------------------------------------------------------------------ session ---

def count_volume_descriptor_sets(img):
    """Count ISO9660 Primary Volume Descriptors in the image.

    SINGLE SESSION ONLY. The Amix cdfs kernel backend leaves read_toc and
    read_last_session_lba NULL, so a second session is not merely unsupported -- it
    is INVISIBLE. Anything written there is silently absent, which is far worse than
    a mount failure. Each session carries its own volume-descriptor set, so more
    than one PVD means more than one session."""
    n = 0
    offs = []
    for lba in range(16, len(img) // SECTOR):
        base = lba * SECTOR
        if img[base + 1:base + 6] == ISO_VD_SIG and img[base] == 1:
            n += 1
            offs.append(lba)
    return n, offs


def check_single_session(img):
    """Exactly one PVD, and it must sit at LBA 16.

    MEASURED 2026-07-19, and the reason this check reads the image instead of
    trusting the build command: xorriso's NATIVE `-outdev ... -commit` path emits a
    GROWABLE layout -- the session is written at LBA 32 with its own PVD at 48, plus
    a relocated superblock at 16 -- i.e. two descriptor sets on a disc nobody asked
    to be multisession.  `xorriso -as mkisofs` emits the classic single-set layout
    with one PVD at 16.  A reader with read_toc/read_last_session_lba NULL, which is
    exactly what the Amix cdfs backend is, has no way to resolve that ambiguity, so
    we require the unambiguous form."""
    n, offs = count_volume_descriptor_sets(img)
    if n == 1 and offs == [16]:
        return []
    if n == 0:
        return [Violation("not-an-iso",
                          "no ISO9660 primary volume descriptor found",
                          "Expected a PVD at LBA 16.")]
    if n == 1:
        return [Violation(
            "pvd-not-at-16",
            "the only primary volume descriptor is at LBA %d, not 16" % offs[0],
            "Amix cdfs has no read_toc; it looks for the descriptor set at LBA 16.")]
    return [Violation(
        "multisession",
        "%d primary volume descriptors (LBAs %s) -- this image carries %d "
        "descriptor sets" % (n, ", ".join(str(o) for o in offs), n),
        "Amix cdfs leaves read_toc/read_last_session_lba NULL: anything past the "
        "first set is INVISIBLE, so its content silently does not exist. "
        "xorriso's native -outdev/-commit produces this growable layout; "
        "-as mkisofs produces the single-set form.")]


def check_no_joliet(img):
    """Joliet must be OFF, deliberately rather than by default.

    cdfs precedence is RR > Joliet > plain ISO, so with Rock Ridge present a Joliet
    tree is never resolved through -- it is just a second, unverified set of names
    that can disagree with the one the catalog was generated against.  A
    supplementary volume descriptor (type 2) is how Joliet announces itself."""
    n = 0
    for lba in range(16, len(img) // SECTOR):
        base = lba * SECTOR
        if img[base + 1:base + 6] == ISO_VD_SIG and img[base] == 2:
            n += 1
    if n:
        return [Violation(
            "joliet-present",
            "%d supplementary volume descriptor(s) -- Joliet is on" % n,
            "Drop -J: with Rock Ridge present cdfs never resolves through Joliet, "
            "so it is an unverified second name space for no benefit.")]
    return []


def check_blank_system_id(img):
    """The primary volume descriptor's System ID must be blank.

    The A4091/A4092 ROM's mounter (a4092_cdfs.rom, CD boot on by default) gives a
    data CD boot priority 2 when the System ID reads "CDTV" or "AMIGA BOOT", and -1
    otherwise (reference/a4091-software 3rdparty/mounter/mounter.c:1155-1219). At 2
    the install CD would outrank the installer's UNIX_Boot (1) and steal the boot,
    so the disc carries no System ID at all. xorriso leaves it blank unless -sysid
    is given; this holds it there."""
    base = 16 * SECTOR
    if img[base:base + 6] != b"\x01" + ISO_VD_SIG:
        return [Violation("no-pvd", "no primary volume descriptor at LBA 16",
                          "The image is not an ISO9660 disc.")]
    sysid = img[base + 8:base + 40]
    if sysid.strip(b" \x00"):
        return [Violation(
            "system-id-set",
            "PVD System ID is %r, not blank" % sysid.rstrip(b" \x00").decode("latin-1"),
            "Drop -sysid: a 'CDTV' / 'AMIGA BOOT' System ID makes the A4092 ROM boot the "
            "CD at pri 2, above the installer's UNIX_Boot.")]
    return []


def check_rockridge(img):
    """Rock Ridge must be present.

    cdfs hybrid precedence is RR > Joliet > plain ISO, so RR is what our reads
    actually resolve through. The SUSP extension-reference records the identifier;
    its absence means the disc would resolve through the 8.3-mangled ISO namespace
    and every name would be wrong."""
    if b"RRIP_1991A" in img or b"IEEE_P1282" in img:
        return []
    return [Violation(
        "no-rock-ridge",
        "no Rock Ridge extension identifier (RRIP_1991A / IEEE_P1282) in the image",
        "Without RR, cdfs falls back to the mangled ISO9660 namespace and every "
        "on-disc pathname differs from what the catalog records.")]


# ------------------------------------------------------------------ CD boot ---
# The bootable install CD (amix-dlm docs/spec/10-boot-loader.md §4.4, D-3 §10):
# the A4091/A4092 ROM mounts the disc with its CD filesystem (ODFileSystem, ROM
# profile: ISO9660 + Rock Ridge + Joliet, precedence RR > Joliet > plain ISO,
# names compared case-insensitively) and Kickstart runs S/Startup-Sequence, which
# runs SYS:BOOT/amix-cdboot. The tree comes from amix-dlm's `mkstore -C`.

CDBOOT_SYSTEM_ID = "AMIGA BOOT"
CDBOOT_LINES = ("K30", "K46")
_CDBOOT_LINE_NAME = re.compile(
    r"^(CONTROL|G[0-9]{1,4}\.GMF|G[0-9]{1,4}[KR]\.BIN|G[0-9]{1,4}M[0-9]{2}\.BIN)$")


def check_system_id(img, want):
    """The PVD System ID must read `want` (the CD-boot disc: "AMIGA BOOT").

    The mounter compares the System ID (PVD offset 8) by prefix against "CDTV" and
    "AMIGA BOOT" and gives a match boot priority 2, anything else -1
    (3rdparty/mounter/mounter.c:1157-1219); at -1 the disc never boots ahead of a
    hard disk."""
    base = 16 * SECTOR
    if img[base:base + 6] != b"\x01" + ISO_VD_SIG:
        return [Violation("no-pvd", "no primary volume descriptor at LBA 16",
                          "The image is not an ISO9660 disc.")]
    sysid = img[base + 8:base + 40].rstrip(b" \x00").decode("latin-1")
    if sysid != want:
        return [Violation(
            "system-id-wrong", "PVD System ID is %r, want %r" % (sysid, want),
            "Master with -sysid '%s': without it the A4091/A4092 ROM gives the disc "
            "boot priority -1." % want)]
    return []


def check_cdboot_tree(tree):
    """The mkstore -C tree is what the CD boot path reads, and nothing else.

    /BOOT/amix-cdboot, /S/Startup-Sequence running it, and at least one line
    directory /BOOT/K30 or /BOOT/K46 holding CONTROL (2048 bytes) and only
    G<n>.GMF / G<n>K.BIN / G<n>R.BIN / G<n>M<nn>.BIN: 8.3 names, so the line
    directories read the same with or without Rock Ridge."""
    bad = []

    def v(kind, detail):
        bad.append(Violation(kind, detail,
                             "Rebuild the tree with amix-dlm's mkstore -C DIR -x amix-cdboot."))

    top = sorted(os.listdir(tree)) if os.path.isdir(tree) else []
    if top != ["BOOT", "S"]:
        v("cdboot-top", "tree top level is %r, want ['BOOT', 'S']" % top)
        return bad
    boot = os.path.join(tree, "BOOT")
    if not os.path.isfile(os.path.join(boot, "amix-cdboot")):
        v("cdboot-no-loader", "no BOOT/amix-cdboot")
    lines = []
    for e in sorted(os.listdir(boot)):
        p = os.path.join(boot, e)
        if e == "amix-cdboot":
            continue
        if e not in CDBOOT_LINES or not os.path.isdir(p):
            v("cdboot-stray", "BOOT/%s is not amix-cdboot or a line directory %s"
              % (e, "/".join(CDBOOT_LINES)))
            continue
        lines.append(e)
        names = sorted(os.listdir(p))
        ctl = os.path.join(p, "CONTROL")
        if not os.path.isfile(ctl) or os.path.getsize(ctl) != SECTOR:
            v("cdboot-control", "BOOT/%s/CONTROL missing or not %d bytes" % (e, SECTOR))
        for n in names:
            if not _CDBOOT_LINE_NAME.match(n) or not os.path.isfile(os.path.join(p, n)):
                v("cdboot-name", "BOOT/%s/%s is not a line-directory member (8.3 name)" % (e, n))
    if not lines:
        v("cdboot-no-line", "neither BOOT/K30 nor BOOT/K46 is present")
    s = os.path.join(tree, "S")
    if sorted(os.listdir(s)) != ["Startup-Sequence"]:
        v("cdboot-s", "S/ holds %r, want ['Startup-Sequence']" % sorted(os.listdir(s)))
    else:
        text = open(os.path.join(s, "Startup-Sequence"), "rb").read().decode("latin-1")
        cmds = [l.strip() for l in text.splitlines()
                if l.strip() and not l.strip().startswith(";")]
        if cmds != ["SYS:BOOT/amix-cdboot"]:
            v("cdboot-startup", "S/Startup-Sequence runs %r, want ['SYS:BOOT/amix-cdboot']" % cmds)
    return bad


def iso_plain_paths(img):
    """Every file and directory of the image by its PLAIN ISO9660 name, Rock Ridge
    ignored: the version suffix ';1' and a trailing '.' dropped, as ODFileSystem's
    ISO backend shows them. Returns {path: is_dir}."""
    def le32(b, o):
        return int.from_bytes(b[o:o + 4], "little")

    pvd = 16 * SECTOR
    out = {}

    def walk(lba, size, prefix, depth):
        if depth > 8:
            return
        data = img[lba * SECTOR:lba * SECTOR + size]
        off = 0
        while off < len(data):
            n = data[off]
            if n == 0:
                off = (off // SECTOR + 1) * SECTOR
                continue
            rec = data[off:off + n]
            nl = rec[32]
            name = rec[33:33 + nl]
            off += n
            if name in (b"\x00", b"\x01"):
                continue
            nm = name.decode("latin-1").split(";")[0].rstrip(".")
            path = prefix + nm
            isdir = bool(rec[25] & 2)
            out[path] = isdir
            if isdir:
                walk(le32(rec, 2), le32(rec, 10), path + "/", depth + 1)

    root = img[pvd + 156:pvd + 156 + 34]
    walk(le32(root, 2), le32(root, 10), "", 0)
    return out


def check_cdboot_plain_names(img, tree):
    """Each line-directory member keeps its exact 8.3 name in the plain ISO9660
    namespace, so a reader without Rock Ridge (or one that drops it) still finds
    BOOT/K30/CONTROL and the generation files the control block names."""
    plain = iso_plain_paths(img)
    bad = []
    for line in CDBOOT_LINES:
        d = os.path.join(tree, "BOOT", line)
        if not os.path.isdir(d):
            continue
        for n in sorted(os.listdir(d)):
            p = "BOOT/%s/%s" % (line, n)
            if plain.get(p) is not False:
                bad.append(Violation(
                    "cdboot-plain-name", "%s has no plain ISO9660 name of its own" % p,
                    "The line directories must read the same without Rock Ridge; "
                    "master with -iso-level 3 and keep the names 8.3 uppercase."))
    return bad


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def check_cdboot_disc(tree, disc):
    """The mastered disc carries the mkstore tree byte for byte, and BOOT/amix-cdboot
    is executable: ODFileSystem turns a Rock Ridge mode without the owner execute bit
    into FIBF_EXECUTE (platform/amiga/handler_main.c:1488-1495), and AmigaDOS then
    refuses to run the loader from S/Startup-Sequence."""
    bad = []
    for rel in walk_rel(tree):
        a, b = os.path.join(tree, rel), os.path.join(disc, rel)
        if not os.path.isfile(b):
            bad.append(Violation("cdboot-missing", "%s is not on the disc" % rel))
        elif _sha256(a) != _sha256(b):
            bad.append(Violation("cdboot-differs", "%s on the disc differs from the tree" % rel))
    ld = os.path.join(disc, "BOOT", "amix-cdboot")
    if os.path.isfile(ld) and not os.stat(ld).st_mode & 0o100:
        bad.append(Violation(
            "cdboot-not-executable",
            "BOOT/amix-cdboot has mode %o on the disc: no owner execute bit"
            % (os.stat(ld).st_mode & 0o7777),
            "Stage it 0755 before mastering; -rational-rock keeps an execute bit "
            "only when one is set."))
    return bad


# ------------------------------------------------------------------ catalog ---

def parse_catalog(text):
    """Parse an apkg v1 catalog. Returns (rows, violations).

    Format: '#apkg-catalog 1' header, then
    name|version|pkginst|filename|md5|size|deps|category|description

    A line beginning with '#' is a COMMENT in catalog v1 and is skipped --
    apkg's own src/apkg/catalog.c has skipped them since its first commit, and
    amix-packagemanager's generator uses that to append opt-in EXTENSION BLOCKS
    after the entry lines:

        #ext <extname> <extversion>
        #<extname> <key> <value>          (one per package)

    One exists today, `isize` (gen-catalog.py --isize), carrying each package's
    installed size in bytes. Until W3b this parser was 9-fields-EXACTLY and
    counted every one of those lines as a malformed entry, which is why
    amix-packagemanager's docs/design.md named it as the one known
    non-conforming consumer and why nothing was allowed to pass --isize into
    the ISO path. It conforms now: comment lines are skipped, so a catalog with
    an extension block and a catalog without one both parse identically, and
    the media path is free to carry the block."""
    FIELDS = ("name", "version", "pkginst", "filename", "md5", "size",
              "deps", "category", "description")
    bad = []
    lines = text.splitlines()
    if not lines or not lines[0].startswith("#apkg-catalog 1"):
        return [], [Violation("bad-catalog",
                              "missing '#apkg-catalog 1' header line")]
    rows = []
    for n, line in enumerate(lines[1:], 2):
        if not line.strip():
            continue
        if line.startswith("#"):
            continue            # catalog v1 comment / extension-block trailer
        parts = line.split("|")
        if len(parts) != len(FIELDS):
            bad.append(Violation("bad-catalog",
                                 "line %d has %d fields, expected %d"
                                 % (n, len(parts), len(FIELDS))))
            continue
        rows.append(dict(zip(FIELDS, parts)))
    return rows, bad


def parse_catalog_isize(text):
    """Parse the `isize` extension block. Returns {catalog-name: bytes}.

    ABSENCE IS UNKNOWN, NEVER ZERO. A package with no `#isize` line is simply
    not in the returned mapping -- gen-catalog.py deliberately omits the line
    (with a stderr warning) when a pkgmap cannot be summed, so a consumer that
    defaulted a missing entry to 0 would turn "we do not know" into "it costs
    nothing", which is the one wrong answer for a free-space gate.

    A malformed value is likewise dropped rather than guessed at; check_catalog_
    isize() below is what turns that into a visible violation."""
    out = {}
    for line in text.splitlines():
        if not line.startswith("#isize "):
            continue
        parts = line.split()
        if len(parts) != 3:
            continue
        try:
            n = int(parts[2])
        except ValueError:
            continue
        if n >= 0:
            out[parts[1]] = n
    return out


def check_catalog_isize(rows, text):
    """If the catalog declares an `isize` block, it must be well-formed.

    Opt-in by construction: a catalog with no `#ext isize` header produces no
    violations at all (that is the backward-compatible case and it must stay
    silent). When the block IS present it is load-bearing -- the installer's
    package menu sizes every named set from it and gates free space on it -- so
    a block that names a package the catalog does not carry, or that repeats a
    name, or whose value is not a non-negative integer, is a mastering fault
    worth refusing rather than a cosmetic one."""
    lines = text.splitlines()
    if not any(l.startswith("#ext isize ") for l in lines):
        if any(l.startswith("#isize ") for l in lines):
            return [Violation(
                "bad-isize-block",
                "the catalog carries #isize lines but no '#ext isize <version>' "
                "header",
                "An extension block without its header is not discoverable; "
                "gen-catalog.py --isize always writes the header first.")]
        return []
    known = set(r["name"] for r in rows)
    bad = []
    seen = set()
    for n, line in enumerate(lines, 1):
        if not line.startswith("#isize "):
            continue
        parts = line.split()
        if len(parts) != 3:
            bad.append(Violation("bad-isize-block",
                                 "line %d: expected '#isize <name> <bytes>', "
                                 "got %r" % (n, line)))
            continue
        name, val = parts[1], parts[2]
        if not val.isdigit():
            bad.append(Violation("bad-isize-block",
                                 "line %d: %s has a non-numeric size %r"
                                 % (n, name, val)))
        if name in seen:
            bad.append(Violation("bad-isize-block",
                                 "line %d: duplicate #isize entry for %s"
                                 % (n, name)))
        seen.add(name)
        if name not in known:
            bad.append(Violation(
                "bad-isize-block",
                "line %d: #isize names %r, which is not a catalog row"
                % (n, name),
                "The block is generated from the same staging scan as the "
                "entries; a name here that is not an entry means the two "
                "disagree about what is on the disc."))
    return bad


def check_catalog_resolves(rows, disc_root, pkgs_prefix="pkgs"):
    """Every catalog row must resolve to a real file on the disc, size and md5.

    Read against the EXTRACTED IMAGE, not the staging tree: the point is that what
    the catalog promises is what the disc actually holds."""
    bad = []
    for r in rows:
        rel = "%s/%s" % (pkgs_prefix, r["filename"])
        path = os.path.join(disc_root, rel.replace("/", os.sep))
        if not os.path.isfile(path):
            bad.append(Violation(
                "catalog-dangling",
                "catalog row %r points at %r, which is not on the disc"
                % (r["name"], rel),
                "A ~2/~3 collision rename produces exactly this."))
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        if str(len(data)) != r["size"]:
            bad.append(Violation(
                "catalog-size-mismatch",
                "%s: catalog says %s bytes, disc holds %d"
                % (rel, r["size"], len(data))))
        got = hashlib.md5(data).hexdigest()
        if got != r["md5"]:
            bad.append(Violation(
                "catalog-md5-mismatch",
                "%s: catalog md5 %s, disc md5 %s" % (rel, r["md5"], got)))
    return bad


def check_no_orphan_packages(rows, disc_paths, pkgs_prefix="pkgs"):
    """Converse of the above: no .pkg on the disc may be absent from the catalog.

    An uncatalogued package is invisible to the installer and pure wasted medium --
    and it is the tell-tale of a staging step that copied more than the selection
    asked for."""
    listed = set("%s/%s" % (pkgs_prefix, r["filename"]) for r in rows)
    bad = []
    for p in disc_paths:
        if p.startswith(pkgs_prefix + "/") and (p.endswith(".pkg") or p.endswith(".pkg.Z")):
            if p not in listed:
                bad.append(Violation(
                    "uncatalogued-package",
                    "%r is on the disc but in no catalog row" % p,
                    "The installer cannot see it; it is only wasted medium."))
    return bad
