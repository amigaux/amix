#!/usr/bin/env python3
# gen-catalog.py -- build an apkg catalog (v1) from a staging dir of SVR4
# datastream packages.  Host-side tool (Linux, python3 stdlib only).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Input:  a staging directory containing *.pkg (SVR4 datastream) and/or
#         *.pkg.Z (compress'd datastream), scanned RECURSIVELY -- the
#         repo uses categorized subdirectories (stock/, base/, test/,
#         devel/, ...) and the catalog filename field carries the path
#         relative to the staging root (forward slashes, e.g.
#         stock/net-2.1.pkg).  Optional override files, staging-root
#         level only:
#           deps.conf   "name: dep1,dep2" lines -- wins over APKG_DEPS in
#                       pkginfo.  Keys match the catalog name (post
#                       names.conf mapping); the pkginst (PKG) also matches
#                       as a fallback.
#           names.conf  "PKG: name" lines -- catalog name for a pkginst;
#                       default is lowercased PKG.
#           cats.conf   "name: category" lines -- wins over CATEGORY in
#                       pkginfo.  Same key rule as deps.conf (catalog name,
#                       pkginst as fallback).  A catalog-level taxonomy
#                       override: it re-categorises WITHOUT re-minting a
#                       package, so no .pkg byte -- and no .pkg md5 --
#                       moves.  The authored taxonomy lives in
#                       tools/repo/cats.conf.
#                       It also takes "@group <token>: <gloss>" lines, which
#                       DECLARE the vocabulary.  Declaring any group makes
#                       the set CLOSED: an override naming an undeclared
#                       group is refused (per-package SKIP) and a pkginfo
#                       CATEGORY outside it warns.  A file with no @group
#                       line declares nothing and behaves exactly as before.
#           descs.conf  "name: free text" lines -- wins over APKG_DESC (and
#                       over the NAME fallback) in pkginfo.  Same key rule
#                       as deps.conf/cats.conf.  The description is the one
#                       catalog column an operator may want to change
#                       WITHOUT re-minting -- it is the line the installer
#                       menu and `apkg list/search/info` show -- and until
#                       this existed it was a pure function of the .pkg
#                       bytes, so saying anything new about a shipped
#                       package meant a new package.  The authored file
#                       lives in tools/repo/descs.conf.
#         The same files are also read from --packages-conf DIR (default:
#         amix's userland/packages/conf, generated from the recipes by
#         build/pkg/pkgmeta; 'none' skips it, and a missing one warns).
#         Neither place outranks the other: where both give one package
#         different values the catalog is not written (rc 4, every
#         conflicting package named); see "conf layers" below.
# Output: catalog + catalog.md5 written into the staging dir (or -o DIR).
#
# Catalog format v1 (docs/design.md section 2):
#   header line "#apkg-catalog 1", then one line per package:
#     name|version|pkginst|filename|md5|size|deps|category|description
#   md5/size are of the served file exactly as it sits in staging (i.e. of
#   the .Z file when the package is compressed).  deps = comma-separated
#   names or "none".  No pipes in any field.
#
# Catalog v1 EXTENSION BLOCKS (--isize; see INSTALLED-SIZE BLOCK below):
#   after the entry lines the generator may append comment lines
#     #ext <extname> <extversion>
#     #<extname> <name> <value>
#   A catalog line starting with '#' is a comment in catalog v1, so an
#   extension block is invisible to a v1 field parser.  Extensions are
#   OPT-IN (no flag => the catalog is byte-for-byte what it always was).
#
# ------------------------------------------------- KERNEL-SPACE BLOCK ---
# A kernel, loader or module package (kernel/dlm contracts C2-2 v3, C2-3 v2,
# C3-1, C3-5, D-3) is
# NEVER an ordinary entry: a deployed 0.2.x apkg must not see kernel space.
# It goes into a block after the ordinary entries (and after --isize), every
# line a '#' comment under 2048 bytes:
#
#     #ext kpkg 1
#     #kpkg <name> <version> role=kernel line=<k30|k46> kabi=<tag>
#           pin=<compiler pin> size=<bytes> sha256=<64 hex> file=<path>
#           pkginst=<PKG> [offset=<n> with --raw]
#     #kpkg <name> <version> role=loader line=any loader=<n> size=<bytes>
#           sha256=<64 hex> file=<path> pkginst=<PKG> [offset=<n>]
#     #kpkg <name> <version> role=module line=<k30|k46> kabi=<tag>
#           pin=<compiler pin> size=<bytes> sha256=<64 hex> file=<path>
#           pkginst=<PKG> [offset=<n>]
#     #end kpkg
#
# The keys are role-dependent (C2-2 v3 section 1.1): a loader entry has
# line=any and loader=<n> and never kabi= or pin=.
#
# Not opt-in: a package is kernel space by its content, so a staging root
# without one gives a catalog byte-for-byte as before.  Detected from the
# pkgmap (C2-3): a plain file /stand/k30/kabi or /stand/k46/kabi = a kernel
# package (role=kernel); /stand/loader/ldrinfo = a loader; anything under
# /etc/conf/mod.d/ = a module.  line=, kabi= and pin= come from the
# package's OWN sidecar (/stand/<line>/kabi, read out of the payload
# archive) byte for byte -- never from a table here -- because kbootset's
# gate 2 compares apkg's record (which carries these catalog values) with
# that sidecar, byte for byte.  size= and sha256= are of the served file.
# A loader package's line= and loader= come the same way from its own
# /stand/loader/ldrinfo (C2-3 v2 section 3: one key=value per line,
# version=<n>, line=any, boot1-sha256=, boot2-size=, boot2-sha256=).
# A module package's (stage 3, C3-5 section 1.2) kabi= and pin= come from
# its module object /etc/conf/mod.d/<name> (exactly one): the .moddata
# section (C3-1: the one ELF section of type 13; a 4-byte word, "MD2\0",
# then NUL-terminated key=value strings ending with an empty one), keys
# kabi= and cc=; line= is kabi's family.  No depend= key: C2-2 has none,
# and kbootset's gate 3 enforces module dependencies.
# The kbootset package (/sbin/kbootset) is userland (C2-3 v2 section 4):
# an ordinary entry, nothing special here.
# Refused per package (SKIP, like any malformed package): a sidecar
# missing, unreadable, without kabi/pin/line, or whose line differs from
# its path, or whose sha256=/size= disagree with the packaged unix; an
# ldrinfo without a numeric version= or with a line= other than any, or
# whose boot1-sha256=/boot2-size=/boot2-sha256= disagree with the
# packaged boot1/boot2; a module package without exactly one object in
# /etc/conf/mod.d/, whose object is not ELF32 big-endian ET_REL EM_68K or
# has not exactly one type-13 section, whose .moddata lacks "MD2\0", has a
# key twice (param aside), a name= other than the file name, a kabi= not
# k30|k46.<major>.<minor> or no single-token cc=; a package that is not pure
# files (40 section 6: only f/d of class none, no install scripts; a module
# package may also carry its driver's device nodes, C3-5 v8 section 1.2:
# "c none /dev/<node> <major> <minor> <mode> <owner> <group>", as apkg
# 0.3.2's ds_pure_files() accepts them, and a block driver's nodes
# "b none /dev/dsk/<node> ..." alike, as apkg's next revision does; a c or
# b entry in a kernel or loader package, a p/s/l/other entry, a c node
# outside /dev/ or a b node outside /dev/dsk/ is still refused).
# The private-kernel gate (KSUM_R/BOOT2_SHA) still runs first, unchanged.
#
# Datastream layout parsed here (docs/stock-pkg-system.md section 4, plus
# empirically verified against real Heirloom pkgtrans output):
#   ASCII header, NUL-padded to a 512-byte boundary:
#     # PaCkAgE DaTaStReAm
#     <PKG> <nparts> <maxpsize>
#     # end of header
#   then cpio archives, each starting on a 512-byte boundary.  The first
#   archive carries <PKG>/pkginfo and <PKG>/pkgmap.  Heirloom pkgtrans
#   emits either odc ("070707", portable ASCII) or newc ("070701") cpio
#   depending on build; both are handled.  A malformed package is reported
#   and skipped, never fatal.
#
# ------------------------------------------------------ UFS-ONLY BLOCK ---
# A package whose pkginfo carries APKG_FSTYPE=<type>[,<type>...] installs
# only onto those filesystem types (statvfs f_basetype names: ufs, s5,
# nfs, ...).  The packages set APKG_FSTYPE=ufs on a package with a file
# name over 14 bytes, which s5 cuts (P-35 Option C, 2026-10-30;
# docs/design.md section 2b).  The value is validated here exactly as
# apkg validates it (1..15 of [a-z0-9] per type, comma-separated); a
# malformed one SKIPs the package.  Every marked package is listed after
# the entries (after --isize, before the kernel-space block):
#
#     #ext fstype 1
#     #fstype <catalog-name> <types>
#
# Not opt-in, and like the kernel-space block it is emitted only when
# there is something to say: a staging root without a marked package gives
# a catalog byte-for-byte as before.  Every line starts with '#', so every
# catalog v1 reader skips it (apkg 0.1-0.3 included).  It is information
# for readers that decide before fetching (an installer, a later apkg);
# the check itself is apkg's, on the package's own pkginfo (fsreq.c).
#
# --------------------------------------------------------- ESSENTIAL ---
# APKG_ESSENTIAL=yes marks a package the system cannot boot without; apkg
# refuses to remove or purge it (docs/design.md section 2c).  apkg reads
# the INSTALLED pkginfo, so the catalog carries nothing.  The value must be
# yes or no: apkg counts any other value as yes, so a malformed one SKIPs
# the package here, where the author sees it.
#
# ------------------------------------------------- INSTALLED-SIZE BLOCK ---
# `--isize` appends, after the entry lines:
#
#     #ext isize 1
#     #isize <catalog-name> <bytes>          (one line per package,
#     ...                                     same order as the entries)
#
# <bytes> is the sum of every SIZED object in the package's pkgmap(4) --
# ftypes f/v/e (regular, volatile, editable files) plus i (the pkginfo and
# any install scripts, which land under /var/sadm/pkg/<PKG>/install).
# Directories, symlinks, hard links, devices and pipes carry no size field
# and contribute nothing.
#
# WHY A COMMENT BLOCK AND NOT A 10th FIELD.  The catalog's field grammar is
# full: src/apkg/catalog.c accepts 9 fields, or 10 when the 10th is the RAW
# byte offset, and REJECTS anything else (CAT_EFORMAT) -- so an 11th field
# would brick every already-deployed apkg binary on every box, and stealing
# the 10th collides with --raw.  amix-installng's isocheck.parse_catalog is
# stricter still (exactly 9).  A '#' line, by contrast, is skipped by
# catalog.c's reader and costs no format-version bump, rides the RAW
# metadata region and the CD tree for free (it IS the catalog), and is
# covered by catalog.md5 like everything else.  It is opt-in on top.
#
# The number is a byte sum, i.e. a floor: a real s5 filesystem charges
# 1 KB blocks plus indirect blocks plus directories.  Measured against the
# original Amix 2.1 tape index (hdf/tape21/x00/List, 512-byte blocks) the
# byte sum runs ~6% under the tape figure and a 1 KB-block + indirect +
# directory model lands within ~1% -- so a free-space gate should budget a
# margin, not the bare sum.  See NOTES.md.

import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys

DS_MAGIC = b"# PaCkAgE DaTaStReAm\n"
DS_END = b"# end of header\n"
PKG_TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+.-]*$")

# Kernel-package markers -- the pkginfo params that identify OUR minted kernel
# packages (KERNBENCH/KERNZ3660) specifically.  W6-P mints those packages with
# KSUM_R (the shipped /stand/unix `sum -r`) and BOOT2_SHA (the flags-based
# boot2 loader hash) in pkginfo precisely so a gate can recognise a
# proprietary-derived kernel package WITHOUT unpacking it or keying on
# pathnames.  This is the robust re-key of the licensing gate: STOCK packages
# (notably `core`) ship /stand/unix + /stand/boot2.boot as ORIGINAL Amix
# content and carry NONE of these params, so keying the refusal on the markers
# refuses exactly the kernel packages while leaving stock /stand content -- and
# the explicitly-private installng raw-source build, which clones the golden
# kernel but is no *package* -- untouched.  The kernel/boot2 bytes are
# proprietary-derived (/stand/unix links Commodore SVR4 objects; boot2 is a
# Commodore blob, W6-K section 3), so a marker-matched package is refused from
# the redistributable catalog AND the publish path (the amix-installng Gate-17
# posture, applied to packages): fail closed, no --force.
KERNEL_MARKER_PARAMS = ("KSUM_R", "BOOT2_SHA")

# The UFS-only mark (UFS-ONLY BLOCK above): the pkginfo parameter and its
# grammar, the same as src/apkg/fsreq.c fstype_list_ok().
FSTYPE_PARAM = "APKG_FSTYPE"
FSTYPE_RE = re.compile(r"^[a-z0-9]{1,15}(,[a-z0-9]{1,15})*$")

# The essential mark (ESSENTIAL above), src/apkg/apkg.h APKG_ESSENTIAL_PARAM.
ESSENTIAL_PARAM = "APKG_ESSENTIAL"
ESSENTIAL_VALUES = ("yes", "no")

# RAW self-describing layout (must match src/apkg/source.h byte-for-byte):
# a metadata region at the front (catalog + catalog.md5, NUL-padded),
# then package datastreams at 512-aligned offsets.  --raw appends the
# offset as the catalog's 10th field and packs a raw.img.
RAW_CAT_OFF = 0
RAW_CAT_MAX = 32768
RAW_MD5_OFF = 32768
RAW_MD5_MAX = 512
RAW_DATA_OFF = 65536

# The client's own read limit on ONE catalog entry line.  src/apkg/catalog.c
# reads each line with fgets() into `char line[MAXLINE]` (MAXLINE 2048) and
# treats a full buffer with no trailing newline as "line too long" -- which
# rejects the WHOLE catalog (CAT_EFORMAT), not the offending line.  So the
# longest line the client can actually read is MAXLINE-2 bytes of text plus
# its newline (2046 + '\n' = 2047 chars, leaving room for the NUL).
CATALOG_MAXLINE = 2048
CATALOG_MAX_ENTRY = CATALOG_MAXLINE - 2


def roundup512(n):
    return (n + 511) // 512 * 512


class Malformed(Exception):
    """Package file cannot be parsed; report and skip."""


class PkgNameTooLong(Exception):
    """PKG name exceeds the 9-char SVR4.0 limit; fatal (Gate 7)."""


class PrivateContent(Exception):
    """Package is one of OUR minted kernel packages (KSUM_R/BOOT2_SHA marker);
    its proprietary-derived /stand payload is PRIVATE-only.

    Fatal in a redistributable catalog build and a refuse on the publish
    path (W6-K section 3): it may never enter the NAS / an off-LAN repo.
    """


# ---------------------------------------------------------------- cpio ---

def _walk_cpio_odc(buf, off):
    """Yield (name, data) members of an odc (070707) archive at off."""
    while True:
        hdr = buf[off:off + 76]
        if len(hdr) < 76:
            raise Malformed("truncated odc cpio header")
        if hdr[:6] != b"070707":
            raise Malformed("bad odc cpio magic mid-archive")
        try:
            namesize = int(hdr[59:65], 8)
            filesize = int(hdr[65:76], 8)
        except ValueError:
            raise Malformed("non-octal odc cpio header field")
        name_end = off + 76 + namesize
        if name_end > len(buf):
            raise Malformed("truncated odc cpio member name")
        name = buf[off + 76:name_end - 1].decode("ascii", "replace")
        data_end = name_end + filesize
        if data_end > len(buf):
            raise Malformed("truncated odc cpio member data")
        if name == "TRAILER!!!":
            return
        yield name, buf[name_end:data_end]
        off = data_end


def _walk_cpio_newc(buf, off):
    """Yield (name, data) members of a newc (070701/070702) archive at off."""
    while True:
        hdr = buf[off:off + 110]
        if len(hdr) < 110:
            raise Malformed("truncated newc cpio header")
        if hdr[:6] not in (b"070701", b"070702"):
            raise Malformed("bad newc cpio magic mid-archive")
        try:
            filesize = int(hdr[54:62], 16)
            namesize = int(hdr[94:102], 16)
        except ValueError:
            raise Malformed("non-hex newc cpio header field")
        name_end = off + 110 + namesize
        if name_end > len(buf):
            raise Malformed("truncated newc cpio member name")
        name = buf[off + 110:name_end - 1].decode("ascii", "replace")
        data_off = (name_end + 3) & ~3        # name padded to 4-byte multiple
        data_end = data_off + filesize
        if data_end > len(buf):
            raise Malformed("truncated newc cpio member data")
        if name == "TRAILER!!!":
            return
        yield name, buf[data_off:data_end]
        off = (data_end + 3) & ~3             # data padded to 4-byte multiple


def walk_first_archive(buf, off):
    """Detect the cpio flavor at off and yield its members."""
    magic = buf[off:off + 6]
    if magic == b"070707":
        return _walk_cpio_odc(buf, off)
    if magic in (b"070701", b"070702"):
        return _walk_cpio_newc(buf, off)
    if magic[:2] in (b"\xc7\x71", b"\x71\xc7"):
        raise Malformed("binary cpio (bcpio) archives not supported")
    raise Malformed("no cpio archive after datastream header "
                    "(magic %r)" % magic)


# ---------------------------------------------------------- datastream ---

def parse_datastream(buf):
    """Parse a datastream; return (pkginst, pkginfo_params, pkgmap_text).

    The licensing gate keys on pkginfo params (the kernel-package markers);
    the installed-size block sums the pkgmap.  Both live in the first cpio
    archive, so both are collected in one walk.

    pkgmap_text is None when the first archive carries no pkgmap, or when
    the archive is damaged AFTER pkginfo was read.  That is deliberate: a
    package that catalogued before this walk was extended must still
    catalogue now, just without an installed size.  A damage BEFORE pkginfo
    is Malformed exactly as it always was.
    """
    if not buf.startswith(DS_MAGIC):
        raise Malformed("not a SVR4 datastream (missing '# PaCkAgE "
                        "DaTaStReAm' magic)")
    end = buf.find(DS_END, 0, 8192)
    if end < 0:
        raise Malformed("datastream header not terminated by "
                        "'# end of header'")
    header = buf[len(DS_MAGIC):end].decode("ascii", "replace")
    pkg_lines = [ln for ln in header.splitlines()
                 if ln.strip() and not ln.startswith("#")]
    if not pkg_lines:
        raise Malformed("no package line in datastream header")
    if len(pkg_lines) > 1:
        raise Malformed("multi-package datastream (%d package lines) not "
                        "supported" % len(pkg_lines))
    tokens = pkg_lines[0].split()
    if len(tokens) < 2:
        raise Malformed("bad datastream package line: %r" % pkg_lines[0])
    hdr_pkg = tokens[0]
    if not PKG_TOKEN_RE.match(hdr_pkg):
        raise Malformed("bad PKG token in datastream header: %r" % hdr_pkg)
    try:
        int(tokens[1])
    except ValueError:
        raise Malformed("non-numeric part count in datastream header: %r"
                        % tokens[1])

    arch_off = (end + len(DS_END) + 511) & ~511
    pkginfo_data = None
    pkgmap_data = None
    try:
        for name, data in walk_first_archive(buf, arch_off):
            if name in ("%s/pkginfo" % hdr_pkg, "pkginfo"):
                pkginfo_data = data
            elif name in ("%s/pkgmap" % hdr_pkg, "pkgmap"):
                pkgmap_data = data
            elif name.endswith("/pkginfo") and pkginfo_data is None:
                raise Malformed("first cpio member is %r but header says "
                                "PKG=%s" % (name, hdr_pkg))
            if pkginfo_data is not None and pkgmap_data is not None:
                break
    except Malformed:
        # Damage after pkginfo costs the pkgmap, never the whole entry.
        if pkginfo_data is None:
            raise
        pkgmap_data = None
    if pkginfo_data is None:
        raise Malformed("no pkginfo member in first cpio archive")

    params = parse_pkginfo(pkginfo_data.decode("latin-1"))
    if "PKG" not in params:
        raise Malformed("pkginfo has no PKG parameter")
    if params["PKG"] != hdr_pkg:
        raise Malformed("PKG mismatch: header says %r, pkginfo says %r"
                        % (hdr_pkg, params["PKG"]))
    pkgmap_text = (pkgmap_data.decode("latin-1")
                   if pkgmap_data is not None else None)
    return hdr_pkg, params, pkgmap_text


# pkgmap(4) ftypes that carry a size field.  Layout is positional and the
# size/cksum/modtime triple is ALWAYS the last three tokens, so we index
# from the right -- that survives the class field and any pathname oddity:
#   f/v/e  part ftype class path mode owner group SIZE cksum modtime
#   i      part ftype       path                  SIZE cksum modtime
# Everything else (d/x directories, s symlinks, l hard links, c/b devices,
# p pipes) has no size field and contributes zero.
PKGMAP_SIZED_FTYPES = ("f", "v", "e", "i")


def installed_size(pkgmap_text):
    """Sum the sized objects of a pkgmap(4); return bytes, or None.

    None means "cannot be determined" (no pkgmap, or a pkgmap this parser
    does not trust) -- the caller then emits NO #isize line for the
    package, so a consumer's free-space gate sees an honest absence rather
    than a fabricated zero.
    """
    if pkgmap_text is None:
        return None
    total = 0
    seen = 0
    for line in pkgmap_text.splitlines():
        parts = line.split()
        # ": <nparts> <maxpsize>" is the pkgmap header line
        if not parts or parts[0] == ":" or parts[0].startswith("#"):
            continue
        if len(parts) < 2 or parts[1] not in PKGMAP_SIZED_FTYPES:
            continue
        if len(parts) < 5:
            return None            # sized ftype with no size/cksum/modtime
        try:
            size = int(parts[-3])
        except ValueError:
            return None            # not the layout we think it is
        if size < 0:
            return None
        total += size
        seen += 1
    return total if seen else None


def kernel_package_markers(params):
    """Return the set of kernel-package markers this pkginfo carries.

    Non-empty => the package is one of OUR minted, PRIVATE-only kernel
    packages (KERNBENCH/KERNZ3660); see KERNEL_MARKER_PARAMS.  A marker only
    counts when its value is non-blank -- a bare ``KSUM_R=`` never marks a
    package private.  Keying on pkginfo (not pathnames) is what lets stock
    packages ship /stand/unix + /stand/boot2.boot as original content and
    still pass the gate.
    """
    return set(k for k in KERNEL_MARKER_PARAMS if params.get(k, "").strip())


# ------------------------------------------------------- kernel space ---

KSIDECAR_RE = re.compile(r"^/stand/(k30|k46)/kabi$")
LDRINFO_PATH = "/stand/loader/ldrinfo"
MODDIR_PREFIX = "/etc/conf/mod.d/"
KPKG_ALLOWED_I = ("pkginfo", "depend", "copyright")


def pkgmap_objects(pkgmap_text, basedir):
    """Yield (ftype, class, installed path) for every non-i object."""
    for line in pkgmap_text.splitlines():
        parts = line.split()
        if len(parts) < 4 or parts[0] == ":" or parts[0].startswith("#"):
            continue
        if parts[1] == "i":
            continue
        path = parts[3].split("=", 1)[0]
        if not path.startswith("/"):
            path = basedir.rstrip("/") + "/" + path
        yield parts[1], parts[2], path


def kspace_role(pkgmap_text, basedir):
    """'kernel' / 'loader' / 'module' by the C2-3 paths, or None."""
    if pkgmap_text is None:
        return None
    role = None
    for ftype, _cls, path in pkgmap_objects(pkgmap_text, basedir):
        if ftype != "f":
            continue
        if KSIDECAR_RE.match(path):
            return "kernel"
        if path == LDRINFO_PATH:
            role = "loader"
        elif path.startswith(MODDIR_PREFIX) and role is None:
            role = "module"
    return role


DIGITS_RE = re.compile(r"^[0-9]+$")
OCTAL_RE = re.compile(r"^[0-7]+$")


def cdev_problem(parts):
    """C3-5 v8 section 1.2: None when a module's pkgmap device entry is
    "<part> c none /dev/<node> <major> <minor> <mode> <owner> <group>" or
    "<part> b none /dev/dsk/<node> <major> <minor> <mode> <owner> <group>"
    (decimal major/minor, octal mode); else why not, in apkg's words."""
    if len(parts) < 4:
        return "unreadable pkgmap line %r" % " ".join(parts)
    if parts[2] != "none":
        return "an object in class %s" % parts[2]
    if parts[1] == "b":
        if (not parts[3].startswith("/dev/dsk/")
                or parts[3] == "/dev/dsk/"):
            return "a block device node outside /dev/dsk/: %s" % parts[3]
    elif not parts[3].startswith("/dev/") or parts[3] == "/dev/":
        return "a device node outside /dev/: %s" % parts[3]
    if (len(parts) != 9 or not DIGITS_RE.match(parts[4])
            or not DIGITS_RE.match(parts[5]) or not OCTAL_RE.match(parts[6])):
        return ("a device entry not of the form <major> <minor> <mode> "
                "<owner> <group>: %s" % parts[3])
    return None


def pure_files_problem(pkgmap_text, role=None):
    """40 section 6: None when the pkgmap holds only f/d objects of class
    none, i entries pkginfo/depend/copyright only, and at least one f --
    the rule apkg's ds_pure_files() applies on the box; else why not.
    role "module" also allows its device nodes, c and b (cdev_problem())."""
    nf = 0
    for line in pkgmap_text.splitlines():
        parts = line.split()
        if not parts or parts[0] == ":" or parts[0].startswith("#"):
            continue
        if len(parts) < 3:
            return "unreadable pkgmap line %r" % line
        ftype = parts[1]
        if ftype == "i":
            if parts[2] not in KPKG_ALLOWED_I:
                return "it carries an install script: %s" % parts[2]
        elif ftype in ("f", "d"):
            if parts[2] != "none":
                return "an object in class %s" % parts[2]
            nf += ftype == "f"
        elif ftype in ("c", "b") and role == "module":
            why = cdev_problem(parts)
            if why is not None:
                return why
        else:
            return "an object of type %s%s" % (
                ftype, (" at " + parts[3]) if len(parts) > 3 else "")
    return None if nf else "it installs no file"


def _members(buf, off):
    """Yield (name, data, next_off) of one cpio archive at off (newc or
    odc), the TRAILER!!! included; Malformed on damage."""
    while True:
        magic = buf[off:off + 6]
        if magic in (b"070701", b"070702"):
            hdr = buf[off:off + 110]
            if len(hdr) < 110:
                raise Malformed("truncated newc cpio header")
            filesize = int(hdr[54:62], 16)
            namesize = int(hdr[94:102], 16)
            name_end = off + 110 + namesize
            data_off = (name_end + 3) & ~3
            nxt = (data_off + filesize + 3) & ~3
            name = buf[off + 110:name_end - 1].decode("ascii", "replace")
        elif magic == b"070707":
            hdr = buf[off:off + 76]
            if len(hdr) < 76:
                raise Malformed("truncated odc cpio header")
            namesize = int(hdr[59:65], 8)
            filesize = int(hdr[65:76], 8)
            name_end = off + 76 + namesize
            data_off = name_end
            nxt = data_off + filesize
            name = buf[off + 76:name_end - 1].decode("ascii", "replace")
        else:
            raise Malformed("bad cpio magic at offset %d" % off)
        if data_off + filesize > len(buf):
            raise Malformed("truncated cpio member %r" % name)
        yield name, buf[data_off:data_off + filesize], nxt
        if name == "TRAILER!!!":
            return
        off = nxt


def payload_files(buf, paths, basedir):
    """Read installed paths out of the datastream's payload archives
    (members root/<path>, or reloc/<path relative to BASEDIR>); returns
    {path: bytes} for the ones found."""
    end = buf.find(DS_END, 0, 8192)
    off = (end + len(DS_END) + 511) & ~511
    want = {}
    for p in paths:
        want["root" + p] = p
        b = basedir.rstrip("/")
        if b and p.startswith(b + "/"):
            want["reloc" + p[len(b):]] = p
        elif not b:
            want["reloc" + p] = p
    found = {}
    while off < len(buf) and buf[off:off + 4] == b"0707":
        last = off
        for name, data, nxt in _members(buf, off):
            if name in want:
                found[want[name]] = data
            last = nxt
        off = (last + 511) & ~511
    return found


def kernel_sidecar(buf, params, pkgmap_text):
    """C2-3 section 2: return (line, kabi, pin) from the package's own
    /stand/<line>/kabi, verbatim; Malformed when it cannot be trusted."""
    basedir = params.get("BASEDIR", "/") or "/"
    sidecar = None
    for ftype, _cls, path in pkgmap_objects(pkgmap_text, basedir):
        m = KSIDECAR_RE.match(path)
        if ftype == "f" and m:
            if sidecar is not None:
                raise Malformed("kernel package carries two sidecars")
            sidecar = (path, m.group(1))
    path, pline = sidecar
    unix = "/stand/%s/unix" % pline
    files = payload_files(buf, [path, unix], basedir)
    if path not in files:
        raise Malformed("kernel package: sidecar %s is not in the payload"
                        % path)
    keys = {}
    for raw in files[path].decode("latin-1").split("\n"):
        if "=" not in raw:
            continue
        k, v = raw.split("=", 1)
        keys.setdefault(k, v)
    for k in ("kabi", "pin", "line"):
        v = keys.get(k)
        if v is None or v == "" or len(v.split()) != 1 or v != v.strip():
            raise Malformed("kernel package: sidecar %s has no usable %s= "
                            "(C2-3 section 2)" % (path, k))
    if keys["line"] != pline:
        raise Malformed("kernel package: sidecar says line=%s but sits in "
                        "/stand/%s" % (keys["line"], pline))
    # C2-3 v4 section 2: size= and sha256= describe the unix in the form
    # shipped -- the packaged file -- so they are checked against it.
    if unix in files:
        u = files[unix]
        if "sha256" in keys and keys["sha256"] != hashlib.sha256(u).hexdigest():
            raise Malformed("kernel package: sidecar sha256= is not the "
                            "packaged %s's" % unix)
        if "size" in keys and keys["size"] != str(len(u)):
            raise Malformed("kernel package: sidecar size=%s, packaged %s "
                            "is %d bytes" % (keys["size"], unix, len(u)))
    return keys["line"], keys["kabi"], keys["pin"]


def loader_info(buf, params):
    """C2-3 v2 section 3: return (line, loader version) from the loader
    package's own /stand/loader/ldrinfo; Malformed when it cannot be
    trusted (C2-2 v3 section 1.1 needs line=any and loader=<n>)."""
    basedir = params.get("BASEDIR", "/") or "/"
    b1, b2 = "/stand/loader/boot1", "/stand/loader/boot2"
    files = payload_files(buf, [LDRINFO_PATH, b1, b2], basedir)
    if LDRINFO_PATH not in files:
        raise Malformed("loader package: %s is not in the payload"
                        % LDRINFO_PATH)
    keys = {}
    for raw in files[LDRINFO_PATH].decode("latin-1").split("\n"):
        if "=" in raw:
            k, v = raw.split("=", 1)
            keys.setdefault(k, v)
    ver = keys.get("version", "")
    if not ver.isdigit():
        raise Malformed("loader package: ldrinfo has no numeric version= "
                        "(C2-3 v2 section 3)")
    if keys.get("line") != "any":
        raise Malformed("loader package: ldrinfo says line=%s, a loader is "
                        "line=any (C2-2 v3 section 1.1)"
                        % keys.get("line", "(none)"))
    if b1 in files and "boot1-sha256" in keys and \
            keys["boot1-sha256"] != hashlib.sha256(files[b1]).hexdigest():
        raise Malformed("loader package: ldrinfo boot1-sha256= is not the "
                        "packaged boot1's")
    if b2 in files and "boot2-sha256" in keys and \
            keys["boot2-sha256"] != hashlib.sha256(files[b2]).hexdigest():
        raise Malformed("loader package: ldrinfo boot2-sha256= is not the "
                        "packaged boot2's")
    if b2 in files and "boot2-size" in keys and \
            keys["boot2-size"] != str(len(files[b2])):
        raise Malformed("loader package: ldrinfo boot2-size=%s, packaged "
                        "boot2 is %d bytes" % (keys["boot2-size"],
                                               len(files[b2])))
    return "any", ver


MODDATA_SHT = 13                       # C3-1 section 1: .moddata's type
MODKABI_RE = re.compile(r"^(k30|k46)\.([0-9]+)\.([0-9]+)$")


def moddata_keys(obj, what):
    """C3-1 sections 1 and 3: the key=value strings of a module object's
    .moddata (the one section of type 13); Malformed when the object or
    the section is not what C3-1 says."""
    if len(obj) < 52 or obj[:4] != b"\x7fELF" or obj[4] != 1 or obj[5] != 2:
        raise Malformed("module package: %s is not an ELF32 big-endian "
                        "object (C3-1 section 1)" % what)
    e_type, e_machine = struct.unpack(">HH", obj[16:20])
    if e_type != 1 or e_machine != 4:
        raise Malformed("module package: %s is not ET_REL EM_68K (e_type %d, "
                        "e_machine %d; C3-1 section 1)"
                        % (what, e_type, e_machine))
    e_shoff = struct.unpack(">I", obj[32:36])[0]
    e_shentsize, e_shnum = struct.unpack(">HH", obj[46:50])
    if e_shentsize < 40 or e_shoff + e_shnum * e_shentsize > len(obj):
        raise Malformed("module package: %s has a damaged section header "
                        "table" % what)
    secs = []
    for i in range(e_shnum):
        h = e_shoff + i * e_shentsize
        sh_type, = struct.unpack(">I", obj[h + 4:h + 8])
        sh_off, sh_size = struct.unpack(">II", obj[h + 16:h + 24])
        if sh_type == MODDATA_SHT:
            secs.append((sh_off, sh_size))
    if len(secs) != 1:
        raise Malformed("module package: %s has %d sections of type 13; "
                        ".moddata is exactly one (C3-1 section 1)"
                        % (what, len(secs)))
    off, size = secs[0]
    if size < 12 or size > 2048 or off + size > len(obj):
        raise Malformed("module package: %s .moddata is %d bytes (C3-1: "
                        "12 to 2048)" % (what, size))
    data = obj[off:off + size]
    if data[4:8] != b"MD2\0":
        raise Malformed("module package: %s .moddata has no MD2 marker "
                        "(C3-1 section 3)" % what)
    keys = {}
    for raw in data[8:].split(b"\0"):
        if raw == b"":
            break
        text = raw.decode("latin-1")
        if "=" not in text:
            raise Malformed("module package: %s .moddata string %r is not "
                            "key=value" % (what, text))
        k, v = text.split("=", 1)
        if k == "param":
            continue
        if k in keys:
            raise Malformed("module package: %s .moddata has %s= twice "
                            "(C3-1 section 3)" % (what, k))
        keys[k] = v
    return keys


def module_info(buf, params, pkgmap_text):
    """C3-5 section 1.2: return (line, kabi, pin) of a module package from
    its object's .moddata (kabi=, cc=); Malformed when it cannot be
    trusted."""
    basedir = params.get("BASEDIR", "/") or "/"
    objs = [path for ftype, _cls, path in pkgmap_objects(pkgmap_text, basedir)
            if ftype == "f" and path.startswith(MODDIR_PREFIX)]
    direct = [p for p in objs if "/" not in p[len(MODDIR_PREFIX):]]
    if len(objs) != 1 or len(direct) != 1:
        raise Malformed("module package: %d objects under %s; a module "
                        "package carries exactly one (C3-5 section 1)"
                        % (len(objs), MODDIR_PREFIX))
    path = direct[0]
    files = payload_files(buf, [path], basedir)
    if path not in files:
        raise Malformed("module package: %s is not in the payload" % path)
    keys = moddata_keys(files[path], path)
    fname = path[len(MODDIR_PREFIX):]
    if keys.get("name") != fname:
        raise Malformed("module package: .moddata name=%s, the object is "
                        "%s (C3-1 section 3: equal to the file name)"
                        % (keys.get("name", "(none)"), path))
    m = MODKABI_RE.match(keys.get("kabi", ""))
    if m is None:
        raise Malformed("module package: %s .moddata kabi=%s is not "
                        "k30|k46.<major>.<minor> (C3-1 section 3)"
                        % (path, keys.get("kabi", "(none)")))
    pin = keys.get("cc", "")
    if pin == "" or len(pin.split()) != 1 or pin != pin.strip():
        raise Malformed("module package: %s .moddata has no usable cc= "
                        "(C3-1 section 3)" % path)
    return m.group(1), keys["kabi"], pin


def parse_pkginfo(text):
    """Parse pkginfo(4) KEY=VALUE lines; first occurrence wins."""
    params = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        params.setdefault(key, val)
    return params


# ------------------------------------------------------------------ .Z ---

def decompress_z(path):
    """Decompress a .Z file to bytes via the first available host tool.

    Linux zcat/gzip decode LZW-compress'd (.Z) input natively (verified
    empirically on this bench); uncompress -c is preferred when present.
    """
    for cmd in (["uncompress", "-c"], ["zcat"], ["gzip", "-dc"]):
        if shutil.which(cmd[0]):
            proc = subprocess.run(cmd + [path], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
            if proc.returncode != 0:
                raise Malformed(".Z decompression failed: %s" %
                                proc.stderr.decode("latin-1").strip())
            return proc.stdout
    raise Malformed("no uncompress/zcat/gzip tool found on host for .Z")


# ---------------------------------------------------------------- conf ---

def read_conf(path):
    """Read 'key: value' lines; '#' comments and blank lines ignored."""
    mapping = {}
    with open(path, encoding="utf-8") as fp:
        for lineno, line in enumerate(fp, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                raise SystemExit("%s:%d: expected 'key: value', got %r"
                                 % (path, lineno, line))
            key, val = line.split(":", 1)
            mapping[key.strip()] = val.strip()
    return mapping


# cats.conf carries a SECOND statement type that deps.conf / names.conf do
# not: a GROUP DECLARATION, "@group <token>: <gloss>".  The declarations are
# the taxonomy's vocabulary -- the closed set of categories this repo is
# willing to emit -- promoted out of a comment block so it can be checked
# instead of rotting.  Two things depend on it being machine-readable: the
# installer menu (one heading per group) and the sibling amix-packages
# registry, whose per-package `category:` has to name a group that exists
# here or the catalog grows a heading nobody chose.
GROUP_DECL_PREFIX = "@group"


def read_cats_conf(path):
    """Read cats.conf; return (assignments, groups).

    assignments  {key: category} -- exactly what read_conf() would return
                 for the plain "<name>: <category>" lines.
    groups       {token: gloss} in file order, from the '@group' lines.

    An EMPTY groups dict means the file declares no vocabulary, which is
    what a bare staging cats.conf looks like; the caller then keeps the
    original permissive behaviour and checks token shape only.
    """
    assignments = {}
    groups = {}
    with open(path, encoding="utf-8") as fp:
        for lineno, line in enumerate(fp, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                raise SystemExit("%s:%d: expected 'key: value', got %r"
                                 % (path, lineno, line))
            key, val = line.split(":", 1)
            key = key.strip()
            val = val.strip()
            if not key.startswith("@"):
                assignments[key] = val
                continue
            parts = key.split(None, 1)
            if parts[0] != GROUP_DECL_PREFIX or len(parts) != 2:
                raise SystemExit("%s:%d: unknown statement %r -- cats.conf "
                                 "takes '<name>: <category>' and "
                                 "'@group <token>: <gloss>'"
                                 % (path, lineno, key))
            token = parts[1].strip()
            if not PKG_TOKEN_RE.match(token):
                raise SystemExit("%s:%d: bad group token %r -- a category "
                                 "must be one [A-Za-z0-9][A-Za-z0-9+.-]* "
                                 "token" % (path, lineno, token))
            if token in groups:
                raise SystemExit("%s:%d: group %r declared twice"
                                 % (path, lineno, token))
            groups[token] = val
    return assignments, groups


# ------------------------------------------------------- conf layers ---
# The confs come from TWO places.  The staging root's own deps/names/cats/
# descs.conf (staged from tools/repo by build-packages.sh) carry the stock,
# kernel-space and pkgtools packages; amix's userland/packages/conf/ carries
# the userland packages, generated by build/pkg/pkgmeta from each recipe.
# Neither layer outranks the other.  Per package, each layer is asked in
# the usual key order (catalog name, then pkginst); if both answer and the
# answers differ, that is a CONFLICT and the catalog is not written (rc 4),
# every conflicting package named.  Equal answers are no conflict.  The
# category vocabulary ('@group') is declared in the staging root's
# cats.conf only.
PACKAGES_CONF = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "..", "packages", "conf"))


class ConfConflict(Exception):
    """Two conf layers give one package different values."""


class ConfLayers:
    """One conf (deps, names, cats or descs) read from up to two layers."""

    def __init__(self, what, norm=None):
        self.what = what
        self.norm = norm or (lambda v: " ".join(v.split()))
        self.layers = []

    def add(self, label, mapping):
        self.layers.append((label, mapping))

    def __len__(self):
        return sum(len(m) for _label, m in self.layers)

    def get(self, *keys, default=None):
        """The value for the first of keys a layer has, or default."""
        found = []
        for label, mapping in self.layers:
            for key in keys:
                if key in mapping:
                    found.append((label, key, mapping[key]))
                    break
        if not found:
            return default
        if len(set(self.norm(v) for _l, _k, v in found)) > 1:
            raise ConfConflict("%s: %s" % (self.what, "; ".join(
                "%s/%s says %s: %s" % (label, self.what, key, value)
                for label, key, value in found)))
        return found[0][2]


def as_layers(what, conf, norm=None):
    """Accept a plain dict (one layer) where a ConfLayers is expected."""
    if isinstance(conf, ConfLayers):
        return conf
    layers = ConfLayers(what, norm)
    layers.add("staging", conf or {})
    return layers


def clean_field(value):
    """Catalog fields may not contain pipes or newlines."""
    return " ".join(value.replace("|", "/").split())


def normalize_deps(raw):
    deps = [d.strip() for d in raw.split(",")]
    deps = [d for d in deps if d and d.lower() != "none"]
    return ",".join(deps) if deps else "none"


# ---------------------------------------------------------------- main ---

def fstype_mark(params):
    """The package's APKG_FSTYPE value, or None when it carries none.

    A malformed value refuses the package (per-package SKIP): apkg refuses
    it too, so cataloguing it would publish a package nobody can install.
    """
    if FSTYPE_PARAM not in params:
        return None
    value = params[FSTYPE_PARAM]
    if not FSTYPE_RE.match(value):
        raise Malformed("%s=%r is not a list of filesystem types (1-15 of "
                        "[a-z0-9] each, comma-separated, e.g. ufs)"
                        % (FSTYPE_PARAM, value))
    return value


def essential_check(params):
    """Refuse a package whose APKG_ESSENTIAL is neither yes nor no."""
    value = params.get(ESSENTIAL_PARAM)
    if value is not None and value not in ESSENTIAL_VALUES:
        raise Malformed("%s=%r is not yes or no" % (ESSENTIAL_PARAM, value))


def build_entry(path, relname, deps_conf, names_conf, cats_conf, cat_groups,
                descs_conf, verbose):
    """relname: path relative to the staging root (forward slashes);
    it is emitted verbatim as the catalog filename field."""
    fname = relname
    with open(path, "rb") as fp:
        raw = fp.read()
    if fname.endswith(".Z"):
        buf = decompress_z(path)
    else:
        buf = raw

    pkginst, params, pkgmap_text = parse_datastream(buf)

    # Licensing gate (W6-K section 3), re-keyed to OUR kernel packages: a
    # package whose pkginfo carries the kernel-package markers (KSUM_R /
    # BOOT2_SHA) is one of the minted KERNBENCH/KERNZ3660 kernel packages --
    # proprietary-derived /stand/unix + /stand/boot2.boot, PRIVATE-only.
    # Refuse it from the redistributable catalog, fail closed (fatal, not a
    # per-file SKIP), so the catalog is not written at all.  No override.
    # Stock packages that ship /stand members as ORIGINAL content (core) carry
    # none of these markers and catalog normally, as they always have.
    kmarkers = kernel_package_markers(params)
    if kmarkers:
        raise PrivateContent(
            "package is a PRIVATE kernel package -- pkginfo carries kernel "
            "marker(s) %s (KSUM_R/BOOT2_SHA identify OUR minted KERNBENCH/"
            "KERNZ3660, whose /stand/unix + /stand/boot2.boot payload is "
            "proprietary-derived, W6-K section 3); it may NEVER enter a "
            "redistributable catalog or repo"
            % ", ".join(sorted(kmarkers)))

    # Gate 7: PKG name <= 9 chars.  Stock SVR4.0 Amix pkgadd SILENTLY drops
    # longer names (no error, no package) - see CONTRIBUTING.md hard constraint 1
    # and repackage-stock.py, which enforces the same at build time.  A
    # hand-authored / hand-dropped .pkg must not bypass it: fail closed
    # (fatal, not a per-file SKIP) so the catalog is not written at all.
    if len(pkginst) > 9:
        raise PkgNameTooLong(
            "PKG '%s' (%d chars) exceeds the 9-char SVR4.0 limit; stock "
            "Amix pkgadd would silently drop it" % (pkginst, len(pkginst)))

    for req in ("NAME", "VERSION"):
        if req not in params or not params[req].strip():
            raise Malformed("pkginfo lacks required %s parameter" % req)

    fstype = fstype_mark(params)
    essential_check(params)

    deps_conf = as_layers("deps.conf", deps_conf, normalize_deps)
    names_conf = as_layers("names.conf", names_conf)
    cats_conf = as_layers("cats.conf", cats_conf)
    descs_conf = as_layers("descs.conf", descs_conf)

    name = names_conf.get(pkginst, default=pkginst.lower())
    if not PKG_TOKEN_RE.match(name) or "|" in name:
        raise Malformed("bad catalog name %r for pkginst %s" %
                        (name, pkginst))

    # Kernel space (see KERNEL-SPACE BLOCK at the top): never an ordinary
    # entry; described from the package's own sidecar.
    basedir = params.get("BASEDIR", "/") or "/"
    role = kspace_role(pkgmap_text, basedir)
    if role is not None:
        why = pure_files_problem(pkgmap_text, role)
        if why is not None:
            raise Malformed("kernel-space package is not pure files "
                            "(40 section 6): %s" % why)
        kabi = pin = loader = None
        if role == "loader":
            kline, loader = loader_info(buf, params)
        elif role == "module":
            kline, kabi, pin = module_info(buf, params, pkgmap_text)
        else:
            kline, kabi, pin = kernel_sidecar(buf, params, pkgmap_text)
        version = clean_field(params["VERSION"])
        if len(version.split()) != 1:
            raise Malformed("kernel-space VERSION %r is not one token"
                            % version)
        entry = {
            "kspace": True, "name": name, "version": version,
            "pkginst": pkginst, "filename": fname, "role": role,
            "line": kline, "kabi": kabi, "pin": pin, "loader": loader,
            "size": str(len(raw)),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "md5": hashlib.md5(raw).hexdigest(),
            "fstype": fstype,
        }
        if verbose:
            print("  %s: kernel space role=%s line=%s %s" % (
                fname, role, kline,
                ("loader=%s (ldrinfo)" % loader) if role == "loader" else
                ("kabi=%s pin=%s (%s)" % (kabi, pin, ".moddata"
                                          if role == "module" else
                                          "sidecar"))))
        return entry

    deps_raw = deps_conf.get(name, pkginst,
                             default=params.get("APKG_DEPS", ""))
    # cats.conf is a CATALOG-level taxonomy override: it re-categorises a
    # package without re-minting it, so the served bytes (and the .pkg md5
    # every gate and digest depends on) never move.  Same key rule as
    # deps.conf: catalog name first, pkginst as fallback, pkginfo last.
    # An override is VALIDATED (it is new, hand-authored input, and a
    # category with a space would make apkg reject the whole catalog);
    # the pkginfo fallback keeps its original, unvalidated behaviour.
    cat_override = cats_conf.get(name, pkginst)
    if cat_override is not None:
        category = clean_field(cat_override)
        if not PKG_TOKEN_RE.match(category):
            raise Malformed("cats.conf: bad category %r for %s -- a category "
                            "must be one [A-Za-z0-9][A-Za-z0-9+.-]* token "
                            "(apkg rejects a catalog whose category field "
                            "holds a space)" % (cat_override, name))
        # A declared vocabulary is a CLOSED set.  An override naming a group
        # the file does not declare is either a typo or an unagreed new
        # group; both reach the installer as an extra menu heading nobody
        # chose, so refuse it the way a spacey category is refused -- a
        # per-package SKIP, never an emitted line.
        if cat_groups and category not in cat_groups:
            raise Malformed("cats.conf: undeclared category %r for %s -- "
                            "declare it ('@group %s: <gloss>') or use one of: "
                            "%s" % (category, name, category,
                                    ", ".join(sorted(cat_groups))))
    else:
        category = clean_field(params.get("CATEGORY", "none")) or "none"
        # The pkginfo fallback keeps its original unvalidated behaviour (it
        # is upstream metadata, not hand-authored input here), but when a
        # vocabulary IS declared, a package falling through to an undeclared
        # CATEGORY is exactly the drift the declaration exists to catch.
        if cat_groups and category not in cat_groups:
            print("gen-catalog: warning: %s: pkginfo CATEGORY=%r is not a "
                  "declared cats.conf group -- it will reach the catalog as "
                  "a menu heading of its own (declared: %s)"
                  % (relname, category, ", ".join(sorted(cat_groups))),
                  file=sys.stderr)
    # descs.conf is the same CATALOG-level override one field further
    # over: the description is what the installer menu and `apkg
    # list/search/info` put in front of a user, and until this existed it
    # was a pure function of the package's own pkginfo APKG_DESC -- so
    # telling a user something new about a SHIPPED package (an operator
    # note, a migration warning) meant re-minting the .pkg and moving its
    # md5.  Now it does not.  Same key rule as deps.conf/cats.conf:
    # catalog name first, pkginst as fallback, pkginfo last.
    #
    # Validation is deliberately different from cats.conf's.  A category
    # is a token and a space in one breaks apkg's parser; a description is
    # FREE TEXT and spaces are the whole point (catalog v1 allows them in
    # this field alone).  What is refused here is what the format cannot
    # carry: a '|' (the field separator -- clean_field() would silently
    # rewrite it to '/', and silently rewriting an operator's authored
    # sentence is worse than refusing it) and an empty override (almost
    # always a truncated line, and it would blank a description the
    # pkginfo did supply).  Over-long is caught later, at line assembly,
    # where the whole line is known.
    desc_override = descs_conf.get(name, pkginst)
    if desc_override is not None:
        if "|" in desc_override:
            raise Malformed("descs.conf: description for %s contains '|', "
                            "the catalog field separator -- rewrite it "
                            "without one" % name)
        description = clean_field(desc_override)
        if description == "":
            raise Malformed("descs.conf: empty description for %s -- remove "
                            "the line to fall back to pkginfo APKG_DESC"
                            % name)
    else:
        description = clean_field(params.get("APKG_DESC", params["NAME"]))
    entry = {
        "name": name,
        "version": clean_field(params["VERSION"]),
        "pkginst": pkginst,
        "filename": fname,
        "md5": hashlib.md5(raw).hexdigest(),
        "size": str(len(raw)),
        "deps": normalize_deps(deps_raw),
        "category": category,
        "description": description,
        "fstype": fstype,
    }
    isize = installed_size(pkgmap_text)
    entry["isize"] = None if isize is None else str(isize)
    if " " in entry["version"]:
        print("gen-catalog: warning: %s: VERSION contains spaces (%r); "
              "catalog v1 expects spaces only in description"
              % (fname, entry["version"]), file=sys.stderr)
    if verbose:
        print("  %s: pkginst=%s version=%s deps=%s category=%s isize=%s "
              "desc=%s%s" %
              (fname, pkginst, entry["version"], entry["deps"],
               entry["category"], entry["isize"] or "unknown",
               "descs.conf" if desc_override is not None else "pkginfo",
               (" %s=%s" % (FSTYPE_PARAM, fstype)) if fstype else ""))
    return entry


FIELDS = ("name", "version", "pkginst", "filename", "md5", "size",
          "deps", "category", "description")


def kpkg_line(e):
    """One '#kpkg' line of the kernel-space block (C2-2 v3 section 1.1:
    kabi=/pin= for a kernel, loader= and never kabi=/pin= for a loader)."""
    if e["role"] == "loader":
        keys = "line=%s loader=%s" % (e["line"], e["loader"])
    else:
        keys = "line=%s kabi=%s pin=%s" % (e["line"], e["kabi"], e["pin"])
    line = ("#kpkg %s %s role=%s %s size=%s sha256=%s file=%s pkginst=%s"
            % (e["name"], e["version"], e["role"], keys, e["size"],
               e["sha256"], e["filename"], e["pkginst"]))
    if "offset" in e:
        line += " offset=%s" % e["offset"]
    return line


def build_raw_image(outdir, catalog_bytes, md5_bytes, entries, staging):
    """Pack a self-describing raw slice image (raw.img) to the source.h
    layout: catalog at 0, catalog.md5 at RAW_MD5_OFF, each package's
    served bytes at its assigned offset.  entries must already carry an
    integer-string 'offset'."""
    if len(catalog_bytes) > RAW_CAT_MAX:
        raise SystemExit("gen-catalog: catalog (%d B) exceeds the RAW "
                         "metadata region (%d B)"
                         % (len(catalog_bytes), RAW_CAT_MAX))
    if len(md5_bytes) > RAW_MD5_MAX:
        raise SystemExit("gen-catalog: catalog.md5 (%d B) exceeds the RAW "
                         "md5 region (%d B)" % (len(md5_bytes), RAW_MD5_MAX))
    end = RAW_DATA_OFF
    for e in entries:
        end = int(e["offset"]) + roundup512(int(e["size"]))
    img = bytearray(end)
    img[RAW_CAT_OFF:RAW_CAT_OFF + len(catalog_bytes)] = catalog_bytes
    img[RAW_MD5_OFF:RAW_MD5_OFF + len(md5_bytes)] = md5_bytes
    for e in entries:
        with open(os.path.join(staging, e["filename"]), "rb") as fp:
            data = fp.read()
        off = int(e["offset"])
        img[off:off + len(data)] = data
    path = os.path.join(outdir, "raw.img")
    tmp = path + ".tmp"
    with open(tmp, "wb") as fp:
        fp.write(img)
    os.replace(tmp, path)
    return path, end


def main(argv):
    ap = argparse.ArgumentParser(
        description="Generate an apkg v1 catalog from a staging directory "
                    "of SVR4 datastream packages.")
    ap.add_argument("staging", help="directory containing *.pkg / *.pkg.Z")
    ap.add_argument("-o", "--output-dir", default=None,
                    help="where to write catalog + catalog.md5 "
                         "(default: the staging dir)")
    ap.add_argument("--raw", action="store_true",
                    help="emit a RAW-source catalog (with the byte-offset "
                         "10th column) and a packed raw.img")
    ap.add_argument("--isize", action="store_true",
                    help="append the installed-size extension block "
                         "('#ext isize 1' + '#isize <name> <bytes>' comment "
                         "lines, summed from each pkgmap). Opt-in: without "
                         "it the catalog is byte-for-byte unchanged.")
    ap.add_argument("--scan-private", action="store_true",
                    help="do NOT build a catalog: scan <staging> for OUR "
                         "minted kernel packages (pkginfo carrying the "
                         "KSUM_R/BOOT2_SHA markers) and exit nonzero (rc=3) if "
                         "any are found. The publish-path licensing gate "
                         "(W6-K section 3); fail closed, no override.")
    ap.add_argument("--packages-conf", metavar="DIR", default=PACKAGES_CONF,
                    help="the userland packages' conf directory, read "
                         "alongside the staging root's confs (default: "
                         "amix's userland/packages/conf; 'none' reads only "
                         "the staging root's)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    staging = args.staging
    outdir = args.output_dir or staging
    if not os.path.isdir(staging):
        print("gen-catalog: %s: not a directory" % staging, file=sys.stderr)
        return 1

    deps_conf = ConfLayers("deps.conf", normalize_deps)
    names_conf = ConfLayers("names.conf")
    cats_conf = ConfLayers("cats.conf")
    cat_groups = {}
    descs_conf = ConfLayers("descs.conf")
    layer_dirs = [("staging", staging)]
    if args.packages_conf != "none":
        if os.path.isdir(args.packages_conf):
            layer_dirs.append(("packages", args.packages_conf))
        else:
            print("gen-catalog: warning: no packages conf at %s -- the "
                  "userland packages keep their pkginfo names and "
                  "categories" % args.packages_conf, file=sys.stderr)
    for label, confdir in layer_dirs:
        deps_path = os.path.join(confdir, "deps.conf")
        names_path = os.path.join(confdir, "names.conf")
        cats_path = os.path.join(confdir, "cats.conf")
        descs_path = os.path.join(confdir, "descs.conf")
        if os.path.isfile(deps_path):
            deps_conf.add(label, read_conf(deps_path))
        if os.path.isfile(names_path):
            names_conf.add(label, read_conf(names_path))
        if os.path.isfile(cats_path):
            assignments, groups = read_cats_conf(cats_path)
            if groups and label != "staging":
                raise SystemExit("%s: declares '@group' lines -- the "
                                 "category vocabulary is declared only in "
                                 "the staging root's cats.conf "
                                 "(tools/repo/cats.conf)" % cats_path)
            cat_groups = groups or cat_groups
            cats_conf.add(label, assignments)
        if os.path.isfile(descs_path):
            descs_conf.add(label, read_conf(descs_path))
        if args.verbose:
            print("loaded %s confs from %s" % (label, confdir))
    if args.verbose:
        print("loaded deps.conf: %d override(s)" % len(deps_conf))
        print("loaded names.conf: %d mapping(s)" % len(names_conf))
        print("loaded cats.conf: %d override(s), %d declared group(s)%s"
              % (len(cats_conf), len(cat_groups),
                 (": " + " ".join(cat_groups)) if cat_groups else ""))
        print("loaded descs.conf: %d override(s)" % len(descs_conf))

    # recursive scan: subdirectories are the categorized repo layout;
    # the emitted filename is the path relative to the staging root
    candidates = []
    for dirpath, dirnames, filenames in os.walk(staging):
        dirnames.sort()
        for f in filenames:
            if f.endswith(".pkg") or f.endswith(".pkg.Z"):
                rel = os.path.relpath(os.path.join(dirpath, f), staging)
                candidates.append(rel.replace(os.sep, "/"))
    candidates.sort()

    # --scan-private: the publish-path licensing gate.  Do not build a
    # catalog; just report any package that installs proprietary kernel/boot2
    # payload and exit nonzero.  publish.sh calls this before it rsyncs, so
    # the definition of "private content" lives in exactly one place.
    if args.scan_private:
        offenders = {}
        unparseable = 0
        for fname in candidates:
            path = os.path.join(staging, fname)
            try:
                with open(path, "rb") as fp:
                    raw = fp.read()
                buf = decompress_z(path) if fname.endswith(".Z") else raw
                _pkg, params, _pkgmap = parse_datastream(buf)
                km = kernel_package_markers(params)
                if km:
                    offenders[fname] = km
            except Malformed as exc:
                # Cannot parse => cannot prove clean.  Warn loudly but do not
                # block on this alone: the gate's contract is "carries a kernel
                # marker => refuse"; build-packages.sh only ever emits
                # well-formed datastreams, which this scan reads.
                print("gen-catalog: scan-private: WARNING %s: unparseable "
                      "(%s) -- not scanned" % (fname, exc), file=sys.stderr)
                unparseable += 1
        if offenders:
            for fn in sorted(offenders):
                print("gen-catalog: PRIVATE CONTENT %s is a kernel package "
                      "(pkginfo marker(s) %s) -- refusing (proprietary "
                      "kernel/boot2, W6-K section 3; never redistributable)"
                      % (fn, ", ".join(sorted(offenders[fn]))),
                      file=sys.stderr)
            print("gen-catalog: scan-private: REFUSE (%d private package(s); "
                  "no --force)" % len(offenders), file=sys.stderr)
            return 3
        print("gen-catalog: scan-private: OK (%d package(s) scanned, %d "
              "unparseable; none carry the kernel-package markers)"
              % (len(candidates), unparseable))
        return 0

    entries = []
    seen = {}
    skipped = 0
    conflicts = []
    for fname in candidates:
        path = os.path.join(staging, fname)
        try:
            entry = build_entry(path, fname, deps_conf, names_conf,
                                cats_conf, cat_groups, descs_conf,
                                args.verbose)
            if entry["name"] in seen:
                raise Malformed("duplicate catalog name %r (already "
                                "provided by %s)" %
                                (entry["name"], seen[entry["name"]]))
            seen[entry["name"]] = fname
            entries.append(entry)
        except PkgNameTooLong as exc:
            # Gate 7: fail closed - do NOT write a partial catalog that
            # would omit the offending package while blessing the rest.
            print("gen-catalog: FATAL %s: %s" % (fname, exc),
                  file=sys.stderr)
            print("gen-catalog: catalog NOT written (Gate 7: PKG name > "
                  "9 chars)", file=sys.stderr)
            return 2
        except PrivateContent as exc:
            # Licensing gate (W6-K section 3): fail closed - a kernel-marker
            # (KSUM_R/BOOT2_SHA) package must never be blessed into a
            # redistributable catalog.  No --force.
            print("gen-catalog: FATAL %s: %s" % (fname, exc),
                  file=sys.stderr)
            print("gen-catalog: catalog NOT written (licensing gate: OUR "
                  "kernel packages are PRIVATE-only)",
                  file=sys.stderr)
            return 3
        except ConfConflict as exc:
            # Neither conf layer wins: name every conflict, write nothing.
            print("gen-catalog: CONFLICT %s: %s" % (fname, exc),
                  file=sys.stderr)
            conflicts.append(fname)
        except Malformed as exc:
            print("gen-catalog: SKIP %s: %s" % (fname, exc),
                  file=sys.stderr)
            skipped += 1

    if conflicts:
        print("gen-catalog: catalog NOT written (%d package(s) with "
              "conflicting conf values: %s)"
              % (len(conflicts), " ".join(conflicts)), file=sys.stderr)
        return 4

    if candidates and not entries:
        print("gen-catalog: all %d package file(s) malformed; catalog NOT "
              "written" % skipped, file=sys.stderr)
        return 1
    if not candidates:
        print("gen-catalog: warning: no *.pkg / *.pkg.Z in %s; writing an "
              "empty catalog" % staging, file=sys.stderr)

    kentries = sorted((e for e in entries if e.get("kspace")),
                      key=lambda e: e["name"])
    entries = [e for e in entries if not e.get("kspace")]
    entries.sort(key=lambda e: e["name"])

    # --raw: assign each package a 512-aligned byte offset (deps-order is
    # irrelevant here; the catalog is sorted by name) and append it as the
    # 10th field.  A plain catalog stays 9-field, byte-for-byte as before.
    fields = FIELDS
    if args.raw:
        off = RAW_DATA_OFF
        for e in entries + kentries:
            e["offset"] = str(off)
            off += roundup512(int(e["size"]))
        fields = FIELDS + ("offset",)

    # Gate 8: an entry line apkg's parser cannot read.  catalog.c reads
    # lines with fgets() into a MAXLINE buffer and treats an unterminated
    # read as "line too long" -- which rejects the WHOLE catalog, not the
    # one line.  Every other field here is bounded by its own validation;
    # the description is free text (and, since descs.conf, hand-authored),
    # so this is where an over-long one has to be caught.  Fail CLOSED for
    # the same reason as Gate 7: a partial catalog that quietly omits the
    # offending package while blessing the rest is worse than no catalog.
    lines = []
    for e in entries:
        line = "|".join(e[f] for f in fields)
        nbytes = len(line.encode("utf-8"))
        if nbytes > CATALOG_MAX_ENTRY:
            print("gen-catalog: FATAL %s: catalog entry line is %d bytes; "
                  "apkg refuses a line that does not fit its %d-byte read "
                  "buffer and rejects the WHOLE catalog "
                  "(src/apkg/catalog.c MAXLINE) -- shorten the description "
                  "(descs.conf, or the package's pkginfo APKG_DESC)"
                  % (e["filename"], nbytes, CATALOG_MAXLINE), file=sys.stderr)
            print("gen-catalog: catalog NOT written (Gate 8: entry line "
                  "too long)", file=sys.stderr)
            return 2
        lines.append(line)

    body = "#apkg-catalog 1\n" + "".join(l + "\n" for l in lines)

    # --isize: the installed-size extension block, appended as catalog v1
    # COMMENT lines so the entry lines above stay byte-for-byte what they
    # would have been without the flag (see INSTALLED-SIZE BLOCK at the top
    # of this file).  A package whose pkgmap could not be summed gets no
    # line at all: absence is the honest signal for a free-space gate.
    if args.isize:
        body += "#ext isize 1\n"
        for e in entries:
            if e.get("isize") is None:
                print("gen-catalog: warning: %s: no usable pkgmap; omitting "
                      "its #isize line" % e["filename"], file=sys.stderr)
                continue
            body += "#isize %s %s\n" % (e["name"], e["isize"])

    # The UFS-only block (see the top): emitted only when a package is
    # marked, so a catalog without one is byte-for-byte as before.  Gate 8
    # holds here too.
    marked = [e for e in entries + kentries if e.get("fstype")]
    if marked:
        body += "#ext fstype 1\n"
        for e in marked:
            line = "#fstype %s %s" % (e["name"], e["fstype"])
            if len(line.encode("utf-8")) > CATALOG_MAX_ENTRY:
                print("gen-catalog: FATAL %s: #fstype line is %d bytes "
                      "(limit %d)" % (e["filename"], len(line.encode("utf-8")),
                                      CATALOG_MAX_ENTRY), file=sys.stderr)
                print("gen-catalog: catalog NOT written (Gate 8: entry line "
                      "too long)", file=sys.stderr)
                return 2
            body += line + "\n"

    # The kernel-space block (see the top): emitted only when there is
    # kernel space, so a catalog without it is byte-for-byte as before.
    # Gate 8 holds here too: a '#' line of 2048 bytes would brick 0.2.x.
    if kentries:
        body += "#ext kpkg 1\n"
        for e in kentries:
            line = kpkg_line(e)
            if len(line.encode("utf-8")) > CATALOG_MAX_ENTRY:
                print("gen-catalog: FATAL %s: #kpkg line is %d bytes (limit "
                      "%d)" % (e["filename"], len(line.encode("utf-8")),
                               CATALOG_MAX_ENTRY), file=sys.stderr)
                print("gen-catalog: catalog NOT written (Gate 8: entry line "
                      "too long)", file=sys.stderr)
                return 2
            body += line + "\n"
        body += "#end kpkg\n"

    body_bytes = body.encode("utf-8")

    cat_path = os.path.join(outdir, "catalog")
    tmp_path = cat_path + ".tmp"
    with open(tmp_path, "wb") as fp:
        fp.write(body_bytes)
    os.replace(tmp_path, cat_path)

    md5_line = ("%s  catalog\n" % hashlib.md5(body_bytes).hexdigest())
    md5_bytes = md5_line.encode("utf-8")
    md5_path = os.path.join(outdir, "catalog.md5")
    tmp_path = md5_path + ".tmp"
    with open(tmp_path, "wb") as fp:
        fp.write(md5_bytes)
    os.replace(tmp_path, md5_path)

    print("gen-catalog: wrote %s: %d package(s)%s%s, %d skipped"
          % (cat_path, len(entries),
             (", %d kernel-space" % len(kentries)) if kentries else "",
             (", %d UFS-only (%s)" % (len(marked), " ".join(
                 "%s=%s" % (e["name"], e["fstype"]) for e in marked)))
             if marked else "",
             skipped))

    if args.raw:
        img_path, img_len = build_raw_image(outdir, body_bytes, md5_bytes,
                                            entries + kentries, staging)
        print("gen-catalog: wrote %s: %d bytes (metadata region + %d "
              "package datastream(s))" % (img_path, img_len, len(entries)))
        if args.verbose:
            for e in entries + kentries:
                print("  %s @ %s (%s B) <- %s"
                      % (e["name"], e["offset"], e["size"], e["filename"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
