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


def clean_field(value):
    """Catalog fields may not contain pipes or newlines."""
    return " ".join(value.replace("|", "/").split())


def normalize_deps(raw):
    deps = [d.strip() for d in raw.split(",")]
    deps = [d for d in deps if d and d.lower() != "none"]
    return ",".join(deps) if deps else "none"


# ---------------------------------------------------------------- main ---

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

    name = names_conf.get(pkginst, pkginst.lower())
    if not PKG_TOKEN_RE.match(name) or "|" in name:
        raise Malformed("bad catalog name %r for pkginst %s" %
                        (name, pkginst))

    deps_raw = deps_conf.get(name, deps_conf.get(pkginst,
                             params.get("APKG_DEPS", "")))
    # cats.conf is a CATALOG-level taxonomy override: it re-categorises a
    # package without re-minting it, so the served bytes (and the .pkg md5
    # every gate and digest depends on) never move.  Same key rule as
    # deps.conf: catalog name first, pkginst as fallback, pkginfo last.
    # An override is VALIDATED (it is new, hand-authored input, and a
    # category with a space would make apkg reject the whole catalog);
    # the pkginfo fallback keeps its original, unvalidated behaviour.
    cat_override = cats_conf.get(name, cats_conf.get(pkginst))
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
    desc_override = descs_conf.get(name, descs_conf.get(pkginst))
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
    }
    isize = installed_size(pkgmap_text)
    entry["isize"] = None if isize is None else str(isize)
    if " " in entry["version"]:
        print("gen-catalog: warning: %s: VERSION contains spaces (%r); "
              "catalog v1 expects spaces only in description"
              % (fname, entry["version"]), file=sys.stderr)
    if verbose:
        print("  %s: pkginst=%s version=%s deps=%s category=%s isize=%s "
              "desc=%s" %
              (fname, pkginst, entry["version"], entry["deps"],
               entry["category"], entry["isize"] or "unknown",
               "descs.conf" if desc_override is not None else "pkginfo"))
    return entry


FIELDS = ("name", "version", "pkginst", "filename", "md5", "size",
          "deps", "category", "description")


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
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    staging = args.staging
    outdir = args.output_dir or staging
    if not os.path.isdir(staging):
        print("gen-catalog: %s: not a directory" % staging, file=sys.stderr)
        return 1

    deps_conf = {}
    names_conf = {}
    cats_conf = {}
    cat_groups = {}
    descs_conf = {}
    deps_path = os.path.join(staging, "deps.conf")
    names_path = os.path.join(staging, "names.conf")
    cats_path = os.path.join(staging, "cats.conf")
    descs_path = os.path.join(staging, "descs.conf")
    if os.path.isfile(deps_path):
        deps_conf = read_conf(deps_path)
        if args.verbose:
            print("loaded deps.conf: %d override(s)" % len(deps_conf))
    if os.path.isfile(names_path):
        names_conf = read_conf(names_path)
        if args.verbose:
            print("loaded names.conf: %d mapping(s)" % len(names_conf))
    if os.path.isfile(cats_path):
        cats_conf, cat_groups = read_cats_conf(cats_path)
        if args.verbose:
            print("loaded cats.conf: %d override(s), %d declared group(s)%s"
                  % (len(cats_conf), len(cat_groups),
                     (": " + " ".join(cat_groups)) if cat_groups else ""))
    if os.path.isfile(descs_path):
        descs_conf = read_conf(descs_path)
        if args.verbose:
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
        except Malformed as exc:
            print("gen-catalog: SKIP %s: %s" % (fname, exc),
                  file=sys.stderr)
            skipped += 1

    if candidates and not entries:
        print("gen-catalog: all %d package file(s) malformed; catalog NOT "
              "written" % skipped, file=sys.stderr)
        return 1
    if not candidates:
        print("gen-catalog: warning: no *.pkg / *.pkg.Z in %s; writing an "
              "empty catalog" % staging, file=sys.stderr)

    entries.sort(key=lambda e: e["name"])

    # --raw: assign each package a 512-aligned byte offset (deps-order is
    # irrelevant here; the catalog is sorted by name) and append it as the
    # 10th field.  A plain catalog stays 9-field, byte-for-byte as before.
    fields = FIELDS
    if args.raw:
        off = RAW_DATA_OFF
        for e in entries:
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

    print("gen-catalog: wrote %s: %d package(s), %d skipped"
          % (cat_path, len(entries), skipped))

    if args.raw:
        img_path, img_len = build_raw_image(outdir, body_bytes, md5_bytes,
                                            entries, staging)
        print("gen-catalog: wrote %s: %d bytes (metadata region + %d "
              "package datastream(s))" % (img_path, img_len, len(entries)))
        if args.verbose:
            for e in entries:
                print("  %s @ %s (%s B) <- %s"
                      % (e["name"], e["offset"], e["size"], e["filename"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
