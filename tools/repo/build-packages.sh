#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# build-packages.sh — stage and build the project's SVR4 datastream packages
# with the HOST-built heirloom pkgmk/pkgtrans (newc-emitting cpio shim baked in).
#
# Usage: build-packages.sh [--apkg] [--eng] [--cdfs] [--demo] [--all]
#                          [--m4]
#                          [--kernbench] [--kernz3660] [--kern] [<stagingdir>]
# Default stagingdir: <repo>/build/repo-staging
#
# --m4 mints `m4`, the stock /usr/ccs/bin/m4 alone, carved out of the factory
# Cdev package on the install tape (hdf/tape21, gitignored) into
# <stagingdir>/stock/ beside the 27 repackaged stock packages.  Not part of
# --all or the bare default: like the stock set it needs the tape.
#
# The KERNEL arms (--kernbench/--kernz3660/--kern) mint the PRIVATE kernel
# packages and are NEVER part of --all or the bare default (which build only
# the redistributable set).  They stage into a SEPARATE private dir
# ($KERNEL_STAGING, default build/kernel-private) so private packages are
# physically apart from the redistributable staging; the publish path also
# refuses any package carrying /stand/unix or /stand/boot2.boot (W6-K sec 3).
#
# MIT License, amix-packagemanager project.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOSTBIN="$REPO/heirloom/build-host/bin"
PKGMK="$HOSTBIN/pkgmk"
PKGTRANS="$HOSTBIN/pkgtrans"
# VER_APKG: 0.2.2 is master's source (release decision, 2026-09-26).  0.2.1
# names the hotfix mint from branch apkg-0.2.1-hotfix (d73ecbc +
# unblock_alarm only, md5 d69db8aa...) -- minted, never published, superseded
# by 0.2.2.  Never re-use 0.2.1 for a master build -- NOTES 2026-09-26.
# 0.2.3 (2026-10-06): /etc/apkg.conf moves from `e none` to `e apkgconf` with
# the class action script src/apkg/i.apkgconf, so an upgrade keeps the box's
# own file; the default also ships as /usr/apkg/lib/apkg.conf.  0.2.2
# (feb57752...) stays what it is.  NOTES 2026-10-06.
# 0.3.0 (2026-10-26): kernel space (amix-dlm C2-2 v4, C2-3 v4, C2-4 v2) --
# the #ext kpkg block, SHA-256, /var/apkg/kpkg records, the kbootset
# trigger, the journal and `apkg recover`, `upgrade` of several names.
# STAGED FOR THE 1.1 MEDIA, NOT PUBLISHED: minted into its own staging dir
# (build/repo-staging-apkg030); the public catalog and the publish line of
# record still say 0.2.3 until the owner decides the publish.  NOTES
# 2026-10-26.
# 0.3.1 (2026-10-26): one kernel package per line (C2-2 v5 sec 2.1) -- a
# kernel install pkgrm's the other package of its line first.  Same rule:
# its own staging dir (build/repo-staging-apkg031), NOT published; 0.3.0
# (e6e7b7d5...) stays what it is.  NOTES 2026-10-26.
# 0.3.2 (2026-10-26): a module package may carry device entries (amix-dlm
# C3-5 v4 sec 1.2: `c none /dev/<node>`).  Same rule: its own staging dir
# (build/repo-staging-apkg032), NOT published; 0.3.1 (45b809cd...) stays
# what it is.  NOTES 2026-10-26.
# 0.3.3 (2026-10-26): a module package may also carry block nodes under
# /dev/dsk (amix-dlm C3-5 v8 sec 1.2, abfaaac).  Same rule: its own staging
# dir (build/repo-staging-apkg033), NOT published; 0.3.2 (9d6de726...)
# stays what it is.  NOTES 2026-10-26.
VER_APKG="0.3.3"
# VER_ENG: 1.12.1 (2026-10-05) -- the first engine mint whose binaries carry
# no 68060-unimplemented integer instruction (heirloom/amix-cc expands the
# 64-bit multiply; scan060 gates it below).  1.12.0 names TWO different
# byte-sets already (published fb2f08f4..., the 2026-07-05 pre-984192a mint
# that SIGKILLs installf on an 060, and the 2026-08-06 r3 re-mint 4ba15121...),
# so the number moves.  NOTES 2026-10-05.
# 1.12.2 (2026-10-05, same day) -- the same source rebuilt through the
# gcc-cross-amix 2ab2b22 wrapper, which now owns the multiply expansion and
# also preserves X (amix-cc's copy clobbered it and is removed).  +8 bytes
# per multiply site, so the bytes differ from 1.12.1's, and the number moves
# again.  1.12.1 (19905d2a...) was minted, NEVER PUBLISHED, and is superseded.
# 1.12.3 (2026-10-06) -- pkginstall endofclass() records the on-disk size,
# cksum and mtime of an e/v object a class action script installed, so a
# plain pkgchk is clean after i.apkgconf keeps /etc/apkg.conf.  1.12.2
# (f5858094...) stays what it is.  NOTES 2026-10-06.
VER_ENG="1.12.3"
VER_DEMO="1.0"
# m4: the stock bytes of the Amix 2.1 tape, so the stock set's VERSION.
VER_M4="2.1"
# cdfs package version: "0.1" (our first mint) with the amix-cdfs provenance
# commit as the build id -- style matches the T6 fixture's "2.3-1" and keeps
# the filename HTTP-safe (only [A-Za-z0-9.-]; no '+' that a naive server would
# decode to a space when apkg GETs it).  Bump the "0.1" on repackaging.
VER_CDFS="0.1-g8de83cf"
# Kernel-package versions: house convention "<REV>-<date>" (like cdfs's
# "0.1-g8de83cf"), where REV = the shipped /stand/unix `sum -r` (so the
# package identity carries the binary's checksum) and the date = mint day.
# Bump the date on a re-mint.  P5.4 (2026-08-06) superseded the W6-P
# identities (KERNBENCH 45473-2026.07.23, KERNZ3660 00961-2026.07.23) with
# the Wave-1 rebuilds (z3660eth major-51 renumber + aen security patch in
# the link; KERNBENCH's mix gains z3660eth).  Both payloads are the gated
# relocunix (ET_REL) bytes: the P5.4 bench build proved /stand/unix == the
# gated relocunix BYTE-EXACT, so the W6-U slice-vs-relocunix representation
# split is gone and REV = the relocunix sum -r.  See
# build/kernel-packages/{bench,onbox}/unix.provenance.
#
# POISONED (2026-08-06, same day): the FIRST P5.4 successors (KERNBENCH
# 45343-2026.08.06, KERNZ3660 05929-2026.08.06) linked the UNVALIDATED
# upstream-sync-2026-07 libcdfskern.o (95826 B, md5 a01c7396...) -- on metal
# the remount canary panicked (Bus Error 482F87AC, cdfs corruption class;
# Packet D FAILED, sync line frozen).  NEVER mint/deploy those identities;
# their .pkg files are quarantined under build/kernel-private/POISONED/
# with a .POISONED suffix.  Record: amix-kerntools docs/kernel-packages.md
# sec 4a-bis + each payload's .provenance sibling.  (The causal attribution
# of that panic was corrected at r3 -- see below; this block's wording gets
# its formal correction in the coming doc pass.)
#
# r2 SUPERSEDED (2026-08-07) -- never deploy 53963/14821: the r2 successors
# (KERNBENCH 53963-2026.08.06, KERNZ3660 14821-2026.08.06) carried the
# proven 8de83cf-line cdfs WITH a latent stack-sdcom defect --
# amix_kern_submit() handed the sd layer a STACK-allocated sdcom (the AMIX
# kernel stack lives in the per-process u-area window), which the HBA
# completion ISR dereferenced in a foreign process context.  NOT the cross
# toolchain.  Fixed in amix-cdfs main @ 9360542 (per-call kmem_zalloc/
# kmem_free); bench falsification flipped both kill-recipes green.  The r3
# payloads carried the FIXED cdfs (96198 B, md5 58ff932f..., sum -r 32976;
# pin-enforced, kerntools 6258301).  Record: amix-kerntools
# docs/kernel-packages.md sec 4a-ter.
#
# r4 (2026-08-16) -- ADDITIVE, NOT a retraction.  r3 (64049/45833) was NOT
# defective: it is metal-green (2026-08-07 calibration, 15/15 cycles + 25/25
# rapids on both) and its .pkg pair stays valid-in-place in kernel/ as the
# previous line.  What r4 adds is the whole P5.4 regeneration batch that
# accumulated after r3 was cut, built as ONE line (the bench build reused the
# combined build's own patched image, so both kernels carry byte-identical
# batch inputs):
#   * probed support.c        -- amix-a4091 support.c.patch (adf3875 line);
#                                kernel-patches.conf row live @ kerntools
#                                5183993.  The two-register anti-alias A3000
#                                SCSI probe; the 0x7000000 RAM-size guess is
#                                provably gone from both disassemblies.
#   * z3660scsi direct map    -- amix-z3660scsi 8293cdc (NEVER FLOWN before
#                                r4); symbol z3660_direct_map (combined only).
#   * z3660net direct map     -- amix-z3660net b89c5d2; symbol
#                                z3660eth_direct_map.  With the row above,
#                                98 sptmap pages (33 + 65) return to the map.
#   * cdfs errno de-laundering-- amix-cdfs e0ef11a, pin @ kerntools 811dd0c;
#                                exp md5 673cd9f43a928d0e57e3a9c32cecb9a4,
#                                96366 B, sum -r 56869 ("pin OK" in both logs).
#   * z3660eth major 51       -- baked BINARY-side, not merely source-side.
#   * a3091/a2091 start-queue lifecycle fix (amix-a4091 be2f5e3) rode in for
#     free: kpatch read the golden's stale .kprev and re-established both from
#     pristine stock.
# KMIX CONSEQUENCE: `support-stock` is RETIRED from the KERNBENCH line -- the
# r4 bench kernel links the PROBED support.c, so the tag would be a false
# assertion.  The kerntools vocabulary has no `support-probed`/`support-fixed`
# tag yet (registering one is a vocabulary change), and an ABSENT group-4 tag
# asserts nothing either way -- so the tag is simply dropped.
# Record: amix-kerntools docs/kernel-packages.md sec 4a-quater (43c54e7) and
# its CHANGELOG 2026-08-15 metal postscript.
VER_KERNBENCH="49667-2026.08.16"
VER_KERNZ3660="60364-2026.08.16"

do_apkg=0; do_eng=0; do_cdfs=0; do_demo=0; do_kernbench=0; do_kernz3660=0
do_m4=0
STAGING=""
for a in "$@"; do
  case "$a" in
    --apkg) do_apkg=1 ;;
    --eng)  do_eng=1 ;;
    --cdfs) do_cdfs=1 ;;
    --demo) do_demo=1 ;;
    --m4)   do_m4=1 ;;
    --all)  do_apkg=1; do_eng=1; do_cdfs=1; do_demo=1 ;;
    --kernbench) do_kernbench=1 ;;
    --kernz3660) do_kernz3660=1 ;;
    --kern)      do_kernbench=1; do_kernz3660=1 ;;
    *) STAGING="$a" ;;
  esac
done
# Bare invocation builds the redistributable set only.  A kernel-only request
# must NOT trip the redistributable default, so the guard checks every arm.
if [ $do_apkg -eq 0 ] && [ $do_eng -eq 0 ] && [ $do_cdfs -eq 0 ] && [ $do_demo -eq 0 ] \
   && [ $do_m4 -eq 0 ] && [ $do_kernbench -eq 0 ] && [ $do_kernz3660 -eq 0 ]; then
  do_apkg=1; do_eng=1; do_cdfs=1; do_demo=1
fi
STAGING="${STAGING:-$REPO/build/repo-staging}"
# Private staging for kernel packages -- deliberately NOT $STAGING.
KSTAGING="${KERNEL_STAGING:-$REPO/build/kernel-private}"

[ -x "$PKGMK" ] || { echo "host pkgmk missing — run heirloom/build-host.sh first" >&2; exit 1; }
mkdir -p "$STAGING"
# pkgtrans chdir's internally, so a RELATIVE staging arg makes the output path
# resolve against pkgtrans's own cwd and fail (silent errno=2, no .pkg).
# Resolve to an absolute path now that the dir exists.
STAGING="$(cd "$STAGING" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# build <name> <version> <subdir> [stagingdir] — expects
# $WORK/<name>/{pkginfo,prototype} prepared and produces
# <stagingdir>/<subdir>/<name>-<version>.pkg (datastream, newc members).
# <subdir> is the categorized repo directory (base/, test/, ...) that ends up
# in the catalog filename field; <stagingdir> defaults to $STAGING (the
# redistributable staging) and is overridden to $KSTAGING for kernel packages.
build_one() {
  name="$1"; ver="$2"; subdir="$3"; stg="${4:-$STAGING}"
  # PKG name <= 9 chars (CONTRIBUTING.md hard constraint 1): stock Amix pkgadd
  # SILENTLY drops longer names.  Fail closed for anything this script mints.
  if [ "${#name}" -gt 9 ]; then
    echo "FATAL: PKG name '$name' (${#name} chars) exceeds the 9-char SVR4.0 limit" >&2
    exit 1
  fi
  spool="$WORK/spool-$name"
  mkdir -p "$spool" "$stg/$subdir"
  ( cd "$WORK/$name" && "$PKGMK" -o -d "$spool" -f prototype )
  # Link gate (fail closed): every `s`/`l` entry in the MINTED pkgmap must
  # carry an absolute target that resolves to a path this package itself
  # declares.  APKG 0.2 shipped a relative symlink target that the stock
  # Amix pkgadd turned into /../apkg/bin/apkg on the metal -- this gate is
  # what stops that shipping again.
  python3 "$REPO/tools/repo/pkgmap-symlink-gate.py" "$spool/$name/pkgmap"
  out="$stg/$subdir/$name-$ver.pkg"
  rm -f "$out"
  "$PKGTRANS" -s "$spool" "$out" "$name"
  # verify the datastream carries newc (070701) members at offset 512
  magic="$(dd if="$out" bs=1 skip=512 count=6 2>/dev/null)"
  if [ "$magic" != "070701" ]; then
    echo "FATAL: $out member magic '$magic' != 070701 (stock Amix pkgadd would reject)" >&2
    exit 1
  fi
  echo "built $out ($(stat -c%s "$out") bytes, newc verified)"
}

# gate_060 <pkg> -- refuse a package of OUR compiled binaries that carries a
# 68060-unimplemented integer instruction (vector 61; the kernel SIGKILLs the
# process).  Fail closed: a hit, or no ELF inspected, removes the package.
gate_060() {
  if ! python3 "$REPO/tools/repo/scan060.py" "$1"; then
    echo "FATAL: $1 fails the 68060 gate (tools/repo/scan060.py)" >&2
    rm -f "$1"
    exit 1
  fi
}

# gate_kernel <file> <expected sum -r first field> <expected size> — refuse a
# kernel payload whose BSD 16-bit `sum -r` or size does not match the proven
# identity.  This is the identity gate that stands between the mint and
# shipping the WRONG kernel bytes (fail closed).
gate_kernel() {
  f="$1"; want_sum="$2"; want_size="$3"
  [ -f "$f" ] || { echo "FATAL: kernel payload missing: $f" >&2; exit 1; }
  got_size="$(stat -c%s "$f")"
  if [ "$got_size" != "$want_size" ]; then
    echo "FATAL: $f is $got_size B, expected $want_size B" >&2; exit 1
  fi
  got_sum="$(sum -r "$f" | awk '{print $1}')"
  if [ "$got_sum" != "$want_sum" ]; then
    echo "FATAL: $f sum -r $got_sum, expected $want_sum" >&2; exit 1
  fi
  echo "kernel payload OK: $f (sum -r $got_sum, $got_size B)"
}

if [ $do_apkg -eq 1 ]; then
  A="$WORK/APKG"; mkdir -p "$A"
  [ -f "$REPO/src/apkg/apkg.amix" ] || { echo "src/apkg/apkg.amix missing (make amix)"; exit 1; }
  [ -f "$REPO/src/contents-fsck/contents-fsck.amix" ] || { echo "contents-fsck.amix missing"; exit 1; }
  cat > "$A/pkginfo" <<EOF
PKG=APKG
NAME=apkg - Amix remote package client
ARCH=Amiga
VERSION=$VER_APKG
CATEGORY=application
CLASSES=none apkgconf
APKG_DESC=Remote package client: update/list/search/install over HTTP
EOF
  cat > "$A/apkg.conf" <<EOF
# apkg configuration
repo=http://pkg.amigaux.org
cachedir=/var/apkg/cache
# The admin(4) file handed to pkgadd/pkgrm with -a.  This package ships it,
# which also means pkgrm APKG deletes it -- so apkg re-creates it whenever it
# is missing rather than trusting it to be there (that assumption bricked the
# upgrade verb on metal, 2026-09-16).  An admin file you have edited is left
# alone.  The upgrade verb derives admin.overwrite beside it, carrying your
# keys with instance=overwrite.
admin=/var/apkg/admin
# v1.1: the heirloom engine is the default (tolerant parser, corrupt-DB
# capable, bench-proven E2E). apkg falls back to /usr/sbin/* automatically
# if APKGENG is not installed. Uncomment to force the stock engine:
# pkgadd=/usr/sbin/pkgadd
# pkgrm=/usr/sbin/pkgrm
#
# --- fetch path (all optional; these ARE the built-in defaults) ---
# timeout is seconds of network SILENCE tolerated mid-transfer, NOT a cap
# on how long a transfer may take: the timer restarts on every chunk that
# arrives. Sizing it against package size is a mistake -- an 8.2 MB package
# over the measured ~37 KB/s A4000D -> pkg.amigaux.org path is ~220 s of
# perfectly healthy transfer. Lower it if you want an unattended run to
# give up sooner on a dead link.
timeout=300
# resolve + TCP connect get their own, much shorter budget, so a host that
# is simply down fails in seconds.
connect_timeout=30
# extra attempts after a NETWORK failure, and the backoff before the first
# (it doubles each time). A non-200 HTTP status is an answer, not a
# failure, and is never retried.
retries=2
retry_delay=5
# bytes between progress lines on stderr; 0 silences them, -v quarters the
# interval. Nothing is printed for a transfer smaller than one interval.
progress=262144
# socket read buffer (clamped to 512..262144) and 301/302 hops followed.
bufsize=8192
redirects=1
# The TCP receive window. 0 = LEAVE IT ALONE, and that is the default
# because it was MEASURED, not out of caution. Two wire captures of a real
# 68LC060 A4000D fetching from pkg.amigaux.org over z3660eth
# (2026-09-14/15) found:
#   - SO_RCVBUF 64 K asked for before connect(); the box advertised win
#     4096 in its SYN and in all 2999 steady-state ACKs. The socket option
#     does not reach this tcp module at all.
#   - Raising the window really does work via the ioctl below (16384 seen
#     on the wire) -- and it is SLOWER: 4096 ~54 KB/s, 8192 ~32 KB/s,
#     16384 ~36-40 KB/s, with server-side retransmits going 1.0% -> 3.6%.
#   - The reason is an RX-path loss cliff at ~8 segments in flight
#     (~10 KB): <=7 segments per burst lose 2-3%, 8 lose ~60%, >=9 lose
#     ~100%, and every loss costs a server RTO. The stock 4096 window
#     admits at most 8 segments (7*536+344) and so sits exactly at the
#     loss-free edge -- near-optimal for this driver as it stands.
# The real lever is the RX drop mechanism (Z3660 firmware discarding its
# whole backlog on overflow, and/or the 16.67 ms poll quantum) and it is
# not in this client. DO NOT raise this expecting speed.
#
# Setting it above 0 is an OPERATOR KNOB, and it does two things:
#   1. STREAMS INITQPARMS (IQP_RQ|IQP_HIWAT) on the tcp module -- the one
#      that actually moves the window. Needs ROOT. It rewrites the
#      module's DEFAULT high-water mark, so it changes every TCP stream
#      opened on the box afterwards, not just apkg's, and it stands until
#      REBOOT. Nothing can read the old value back (the ioctl is set-only
#      and sockmod's cached SO_RCVBUF starts at 0), so apkg does not
#      restore it: put it back with rcvbuf=4096 on a root run, or reboot.
#      Capped at 65535 because the ioctl carries a 16-bit value.
#   2. SO_RCVBUF before connect(), the non-root fallback. On Amix it does
#      not reach TCP; do not read the 'apkg -v' getsockopt line as proof.
# If you do set it, 16384 is the highest worth considering: MSS to a
# non-local host is pinned at 536 and the Z3660 firmware RX ring has 32
# usable slots, so past 32*536 (~17 KB) the ring itself overruns and that
# firmware DISCARDS its whole queued backlog instead of back-pressuring.
rcvbuf=0
# SO_SNDBUF. apkg sends requests and receives bodies, so this does not
# affect fetch throughput; 0 leaves the stack default.
sndbuf=0
#
# --- name resolution (all optional; these ARE the built-in defaults) ---
# Stock Amix has NO resolver. gethostbyname() reads /etc/inet/hosts and
# nothing else; a resolv.conf on this box is inert, nothing reads it. And the
# package repository is a NAME-BASED VIRTUAL HOST -- a request whose Host: is
# a bare IP is answered 404 -- so the repo URL must carry the NAME. On a
# stock box that means one of these two:
#
#   1. a hosts line, which is what the demo media ships:
#        echo '52.59.174.203   pkg.amigaux.org' >> /etc/inet/hosts
#   2. a nameserver here, which makes apkg resolve the name itself.
#
# apkg's resolver is a STUB: one UDP A query per attempt, recursion
# requested, no cache, no search list, no TCP fallback, no resolv.conf. It
# answers apkg's OWN lookups and nothing else -- telnet, ftp and the rest of
# the box still read /etc/inet/hosts, so keep that file as you need it.
#
# The default list is EMPTY: with no nameserver line apkg resolves exactly as
# it always did, out of the hosts file alone. The hosts file is consulted
# FIRST in any case, so a line you wrote by hand always wins over DNS and a
# box that works today cannot regress. Repeat the key for more than one
# server; they are tried in the order written. An IPv4 address only (a name
# here would be a bootstrap problem); ':port' is accepted after it but is
# only for testing. A line with an empty value clears the list.
nameserver=
# seconds per QUERY ATTEMPT (a UDP query comes back fast or is lost), and
# extra attempts per nameserver. Every configured server is asked in turn
# regardless, so the worst case for a name nobody answers is
# nameservers x (dns_retries+1) x dns_timeout seconds.
dns_timeout=5
dns_retries=2
EOF
  cat > "$A/admin" <<EOF
mail=
instance=quit
partial=nocheck
runlevel=nocheck
idepend=nocheck
rdepend=nocheck
space=quit
setuid=nocheck
conflict=nocheck
action=nocheck
basedir=default
EOF
  # /usr/bin/apkg -> /usr/apkg/bin/apkg: put the client on the STOCK PATH so a
  # fresh install can just type `apkg` (the real binary lives under the
  # parallel /usr/apkg prefix, which is NOT on the default PATH).  This is an
  # `s` (symlink) pkgmap entry -- SVR4 s5 supports symlinks and stock core's
  # own pkgmap uses exactly this form (e.g. `s none /usr/bin/uname=/sbin/uname`);
  # like core's, and like the `l` hard-link lines in the APKGENG arm, an `s`
  # line carries NO mode/owner/group.  /usr/bin already exists (owned by core)
  # -- we drop only the link, never re-declare the directory, so this adds
  # exactly one contents record and touches no core-owned object.
  #
  # THE TARGET MUST BE ABSOLUTE (fixed 2026-09-16).  APKG 0.2 shipped the
  # RELATIVE form `../apkg/bin/apkg`, which is what the SVR4 spec wants and
  # what OUR heirloom pkgadd does correctly (verified host-side: it creates
  # `apkg -> ../apkg/bin/apkg`).  But /usr/apkg/bin is not on the default
  # PATH, so the pkgadd an operator actually types is the STOCK 1991
  # /usr/sbin/pkgadd -- and on the metal (A4000D/68LC060,
  # 2026-09-16) that one prefixed the basedir onto the link SOURCE as well as
  # the destination and created
  #       /usr/bin/apkg -> /../apkg/bin/apkg
  # i.e. the nonexistent /apkg/bin/apkg, so `apkg` on PATH was "not found"
  # straight after a successful install.  An absolute target survives BOTH
  # engines and matches what stock core's own pkgmap does.  Under `pkgadd -R`
  # the link inside the alt-root then points at the absolute path, which is
  # correct once that root is the running root -- and dangling if you follow
  # it from the build host, which is the accepted trade for a link that works
  # on the machine it was built for.  tools/repo/pkgmap-symlink-gate.py
  # enforces this at mint time; build_one runs it on every package.
  # Version 0.2 (2026-09-16).  The house rule for APKG is a plain "0.1"/"0.2"
  # with no build-id (unlike cdfs, whose suffix pins an EXTERNAL repo's commit),
  # and it moves when the SHIPPED BINARY changes -- which it now has: the fetch
  # timeout became an inactivity timer and the whole fetch path became
  # /etc/apkg.conf keys, and the socket buffers became keys with it.
  #
  # NOTE on 0.1: catalog v1 keys on NAME, so it CANNOT carry both versions --
  # gen-catalog.py refuses a staging dir holding both ("duplicate catalog name
  # 'apkg'") and catalog_find() returns the first match, so a hand-written
  # duplicate would be ambiguous to every client.  What APKG-0.1.pkg needs is
  # not a catalog entry but survival ON THE SERVER: a box that already has 0.1
  # never re-fetches it and the Saku medium carries the bytes locally, so
  # decatalogued-but-present is exactly right.  publish.sh rsyncs with
  # --delete --delete-excluded, so keep APKG-0.1.pkg IN STAGING or the publish
  # will remove it.  The bundled /etc/apkg.conf template above gained the nine
  # fetch keys in the same change, so an 0.2 install documents its own knobs.
  #
  # Version 0.2.1 (2026-09-15, branch apkg-0.2.1-hotfix).  A HOTFIX mint, and
  # its whole point is that it is minimal: this branch is d73ecbc -- the exact
  # tree the published APKG-0.2.pkg was built from -- plus ONE function,
  # unblock_alarm(), so the demo delta a maintainer has to weigh before Saturday is
  # one function and not a release.  The bug it closes hangs the client on a
  # SECOND stalled fetch (a longjmp out of the SIGALRM handler never unblocks
  # SIGALRM, so the retry's alarm() is armed and never delivered) -- with the
  # shipped default retries=2, i.e. on the demo cards.  Every other payload in
  # the package is byte-identical to 0.2's, the /etc/apkg.conf template above
  # included (rcvbuf=0), which is asserted by the mint note in docs/.  The
  # version moves because the SHIPPED BINARY changed, per the house rule above;
  # the third component says "same 0.2, one fix".  NOT published unless the
  # maintainer says so -- see docs/apkg-0.2.1-hotfix.md.  (It never was: 0.2.1 was
  # minted but NEVER PUBLISHED, and is superseded by 0.2.2.)
  #
  # Version 0.2.2 (2026-09-26, master).  Release decision: the release is
  # master's whole src/apkg -- the canonical pkg.amigaux.org compiled-in
  # default (dcece20), the blocked-SIGALRM fix (unblock_alarm, as in 0.2.1)
  # and the stub DNS resolver with its nameserver=/dns_timeout=/dns_retries=
  # keys (eed3210).  The /etc/apkg.conf template above therefore differs from
  # 0.2's/0.2.1's: it documents the DNS keys.  The third component moves past
  # 0.2.1 because that number already names a minted artefact with different
  # bytes; one version, one tree.
  #
  # Version 0.2.3 (2026-10-06).  /etc/apkg.conf was `e none`, and SVR4 pkgadd
  # treats an `e` object in class none exactly like `f`: it copies the
  # package's file over whatever is there.  `apkg upgrade apkg` 0.2 -> 0.2.2
  # therefore reset every edited conf (amix-installng, emulated LC060).  It is
  # now `e apkgconf`, installed by the class action script i.apkgconf: the
  # default goes in only when the file is absent, an existing file is kept.
  # Both engines honour it: the stock Amix 2.1 pkginstall carries the same
  # <pkg>/install/i.<class> + /sbin/sh + ENDOFCLASS machinery (its strings;
  # a run on a box is owed) as the heirloom one (run host-side).  The
  # contents DB still records the package's cksum for the object, so a kept
  # local file shows in a plain pkgchk, as any edited `e` file does;
  # `pkgchk -n` (skip editable files) is the clean post-install check.
  # The default itself also ships as the plain file /usr/apkg/lib/apkg.conf.
  # The template's BYTES are 0.2.2's (md5 8dada8d9...): a box whose conf is
  # still that default upgrades with a clean plain pkgchk.  Changing them
  # makes every such box's kept conf differ from its new record.
  # /var/apkg/admin stays `e none`, so an upgrade still replaces an edited
  # admin file -- out of this change's scope, a follow-up in NOTES 2026-10-06.
  #
  # Version 0.3.0 (2026-10-26).  The apkg binary and apkg.1 change (kernel
  # space, see VER_APKG); every other payload byte, the /etc/apkg.conf
  # template included (md5 8dada8d9..., T23), is 0.2.3's.  Staged for the
  # 1.1 media, NOT published.
  #
  # Version 0.3.1 (2026-10-26).  The apkg binary and apkg.1 change again
  # (one kernel package per line); every other payload byte is 0.3.0's.
  # Staged for the 1.1 media, NOT published.
  #
  # Version 0.3.2 (2026-10-26).  The apkg binary and apkg.1 change again
  # (module device entries); every other payload byte is 0.3.1's.  Staged
  # for the 1.1 media, NOT published.
  #
  # Version 0.3.3 (2026-10-26).  The apkg binary and apkg.1 change again
  # (block nodes under /dev/dsk); every other payload byte is 0.3.2's.
  # Staged for the 1.1 media, NOT published.
  cat > "$A/prototype" <<EOF
i pkginfo
i i.apkgconf=$REPO/src/apkg/i.apkgconf
d none /usr/apkg 0755 root sys
d none /usr/apkg/bin 0755 root sys
f none /usr/apkg/bin/apkg=$REPO/src/apkg/apkg.amix 0755 root sys
s none /usr/bin/apkg=/usr/apkg/bin/apkg
f none /usr/apkg/bin/contents-fsck=$REPO/src/contents-fsck/contents-fsck.amix 0755 root sys
f none /usr/apkg/bin/amix-sadm-migrate=$REPO/tools/migrate/amix-sadm-migrate.sh 0755 root sys
d none /usr/apkg/man 0755 root sys
d none /usr/apkg/man/man1 0755 root sys
f none /usr/apkg/man/man1/apkg.1=$REPO/src/apkg/apkg.1 0644 root sys
d none /usr/apkg/lib 0755 root sys
f none /usr/apkg/lib/apkg.conf=$A/apkg.conf 0644 root sys
e apkgconf /etc/apkg.conf=$A/apkg.conf 0644 root sys
d none /var/apkg 0755 root sys
d none /var/apkg/cache 0755 root sys
e none /var/apkg/admin=$A/admin 0644 root sys
EOF
  build_one APKG "$VER_APKG" base
  gate_060 "$out"
fi

if [ $do_eng -eq 1 ]; then
  E="$WORK/APKGENG"; mkdir -p "$E"
  B="$REPO/heirloom/build-amix"
  for t in pkginfo pkgparam pkgtrans pkgadd pkgrm installf pkgchk pkgmk pkgproto; do
    [ -f "$B/bin/$t" ] || { echo "engine binary $t missing — run heirloom/build-amix.sh"; exit 1; }
  done
  [ -f "$B/sadm-helpers/pkginstall" ] || { echo "pkginstall helper missing"; exit 1; }
  cat > "$E/pkginfo" <<EOF
PKG=APKGENG
NAME=SVR4 pkg engine (heirloom port) - fixed pkgadd/pkgrm + missing tools
ARCH=Amiga
VERSION=$VER_ENG
CATEGORY=application
CLASSES=none
APKG_DESC=Heirloom SVR4 pkg tools: tolerant contents parser, removef/pkgask, man pages
EOF
  {
    echo "i pkginfo"
    echo "d none /usr/apkg 0755 root sys"
    echo "d none /usr/apkg/bin 0755 root sys"
    for t in pkginfo pkgparam pkgtrans pkgadd pkgrm installf pkgchk pkgmk pkgproto; do
      echo "f none /usr/apkg/bin/$t=$B/bin/$t 0755 root sys"
    done
    # argv[0] dispatch aliases
    echo "l none /usr/apkg/bin/pkgask=/usr/apkg/bin/pkgadd"
    echo "l none /usr/apkg/bin/removef=/usr/apkg/bin/installf"
    echo "d none /usr/apkg/sadm 0755 root sys"
    echo "d none /usr/apkg/sadm/install 0755 root sys"
    echo "d none /usr/apkg/sadm/install/bin 0755 root sys"
    echo "f none /usr/apkg/sadm/install/bin/pkginstall=$B/sadm-helpers/pkginstall 0755 root sys"
    echo "f none /usr/apkg/sadm/install/bin/pkgremove=$B/sadm-helpers/pkgremove 0755 root sys"
    echo "d none /usr/apkg/doc 0755 root sys"
    echo "f none /usr/apkg/doc/OPENSOLARIS.LICENSE=$REPO/heirloom/LICENSE/OPENSOLARIS.LICENSE 0644 root sys"
    echo "f none /usr/apkg/doc/CALDERA.LICENSE=$REPO/heirloom/LICENSE/CALDERA.LICENSE 0644 root sys"
    echo "d none /usr/apkg/man 0755 root sys"
    echo "d none /usr/apkg/man/man1 0755 root sys"
    echo "d none /usr/apkg/man/man1m 0755 root sys"
    echo "d none /usr/apkg/man/man5 0755 root sys"
    for m in "$REPO"/heirloom/man/*.1; do
      [ -f "$m" ] && echo "f none /usr/apkg/man/man1/$(basename "$m")=$m 0644 root sys"
    done
    for m in "$REPO"/heirloom/man/*.1m; do
      [ -f "$m" ] && echo "f none /usr/apkg/man/man1m/$(basename "$m")=$m 0644 root sys"
    done
    for m in "$REPO"/heirloom/man/*.5; do
      [ -f "$m" ] && echo "f none /usr/apkg/man/man5/$(basename "$m")=$m 0644 root sys"
    done
  } > "$E/prototype"
  build_one APKGENG "$VER_ENG" base
  gate_060 "$out"
fi

if [ $do_cdfs -eq 1 ]; then
  # ---- cdfs: the CD/optical-filesystem USERLAND, so an INSTALLED Amix box
  # can mount CDs.  OURS (not stock).  Wave-5 finding: a fresh install of the
  # base five ships NO cdfs userland (`/usr/lib/fs/cdfs` absent) even though
  # the cdfs KERNEL side is already in the target kernel (core).  This package
  # closes exactly that gap and nothing more:
  #   * /usr/lib/fs/cdfs        the fstype helper dir (0755 bin bin)
  #   * /usr/lib/fs/cdfs/mount  the SVR4 mount(1M) helper (`mount -F cdfs ...`)
  #   * /cdrom                  the conventional mount point (0755 bin bin)
  #
  # Ownership/mode follow the CLOSEST stock-core convention, read straight from
  # core's pkgmap: `/usr/lib/fs` and every `/usr/lib/fs/<fstype>` dir are
  # `0755 bin bin` and the fs `mount` helpers are `bin bin` (fd/mount is
  # 0755 bin bin verbatim); the closest root-dir analog to a mount point is
  # `/mnt` = `0755 bin bin`.  amix-cdfs's own platform/amix/README.md installs
  # the helper `chmod 755`, matching.
  #
  # PROVENANCE (recorded + asserted):
  #   binary           : ../amix-cdfs/build/amix/mount
  #   amix-cdfs commit : 8de83cf  (its 'reviewed' tag; ODFileSystem->Amix port)
  #   sum -r           : 33315  5        (BSD 16-bit rotate sum / 512-blk count)
  #   size             : 5026 bytes
  #   md5              : d20169094f9953a051484781c4e176bd
  #   ELF              : m68k SVR4, dynamically linked (interp /usr/lib/libc.so.1)
  #
  # GATE 1 (single-entry invariant): `/usr/lib/fs/cdfs/` MUST contain exactly
  # one file -- `mount`.  umount(1M) does NOT exec a per-fstype helper, but a
  # STRAY file there (e.g. a `umount`) makes umount(1M) try to exec it, fail
  # with rc 1, and NOT call umount(2) -- the CD stays mounted, silently (proven
  # on the bench; see amix-cdfs platform/amix/README.md).  This prototype puts
  # nothing else in that directory.
  #
  # GATE 3 (version lineage): the shipped binary MUST come from amix-cdfs
  # >= 31e8c3b, the page-crossing-DMA fix lineage -- older cdfs DMAs into
  # buffers that can cross a page and zero unrelated physical frames.  We
  # assert 8de83cf descends from 31e8c3b before packaging; fail closed if not.
  CDFS_REPO="$REPO/../amix-cdfs"
  CDFS_MOUNT="$CDFS_REPO/build/amix/mount"
  CDFS_PROV_COMMIT="8de83cf"      # amix-cdfs 'reviewed' HEAD this was built at
  CDFS_MIN_COMMIT="31e8c3b"       # page-crossing-DMA fix (Gate 3 floor)
  [ -f "$CDFS_MOUNT" ] || {
    echo "cdfs mount helper missing: $CDFS_MOUNT (build amix-cdfs first)" >&2
    exit 1; }
  # Gate 3: assert the provenance commit descends from the DMA-fix floor.
  if git -C "$CDFS_REPO" rev-parse --verify -q "${CDFS_MIN_COMMIT}^{commit}" >/dev/null 2>&1 \
     && git -C "$CDFS_REPO" rev-parse --verify -q "${CDFS_PROV_COMMIT}^{commit}" >/dev/null 2>&1; then
    if git -C "$CDFS_REPO" merge-base --is-ancestor "$CDFS_MIN_COMMIT" "$CDFS_PROV_COMMIT"; then
      echo "cdfs Gate 3 OK: amix-cdfs $CDFS_PROV_COMMIT descends from $CDFS_MIN_COMMIT (page-cross DMA fix)"
    else
      echo "FATAL cdfs Gate 3: amix-cdfs $CDFS_PROV_COMMIT does NOT descend from $CDFS_MIN_COMMIT" >&2
      exit 1
    fi
  else
    echo "cdfs Gate 3: WARNING - cannot reach amix-cdfs git to assert lineage; trusting recorded provenance ($CDFS_PROV_COMMIT >= $CDFS_MIN_COMMIT)" >&2
  fi
  C="$WORK/cdfs"; mkdir -p "$C"
  cat > "$C/pkginfo" <<EOF
PKG=cdfs
NAME=cdfs - CD/optical filesystem mount helper (amix-cdfs port)
ARCH=Amiga
VERSION=$VER_CDFS
CATEGORY=system
CLASSES=none
APKG_DESC=CD/optical filesystem (ISO9660/RockRidge/Joliet) userland mount helper; kernel side ships in core. Built from amix-cdfs $CDFS_PROV_COMMIT.
EOF
  # Exactly the minimal, exact contents (Gate 1: nothing else under cdfs/).
  cat > "$C/prototype" <<EOF
i pkginfo
d none /usr/lib/fs/cdfs 0755 bin bin
f none /usr/lib/fs/cdfs/mount=$CDFS_MOUNT 0755 bin bin
d none /cdrom 0755 bin bin
EOF
  build_one cdfs "$VER_CDFS" base
fi

if [ $do_demo -eq 1 ]; then
  for p in DEMOLIB AMIXDEMO; do
    D="$WORK/$p"; mkdir -p "$D/files"
    low="$(echo "$p" | tr 'A-Z' 'a-z')"
    echo "hello from $low $VER_DEMO" > "$D/files/$low.txt"
    cat > "$D/pkginfo" <<EOF
PKG=$p
NAME=$low demo package
ARCH=Amiga
VERSION=$VER_DEMO
CATEGORY=test
CLASSES=none
APKG_DESC=Demo package for apkg E2E testing
EOF
    cat > "$D/prototype" <<EOF
i pkginfo
d none /usr/apkg 0755 root sys
d none /usr/apkg/demo 0755 root sys
f none /usr/apkg/demo/$low.txt=$D/files/$low.txt 0644 root sys
EOF
    build_one "$p" "$VER_DEMO" test
  done
fi

# ======================================================================
# KERNEL PACKAGES (PRIVATE-only; W6-K W6-P).  Payloads are proprietary-
# derived (/stand/unix links Commodore SVR4 objects; /stand/boot2.boot is a
# Commodore blob), so these NEVER go to $STAGING/the public repo -- they build into
# $KSTAGING and the publish path refuses anything carrying those paths.
#
# Payloads live under the gitignored build/kernel-packages/ (never committed):
#   bench/unix    the P5.4r4 bench kernel, a4091+z3660eth+cdfs
#                                             (sum -r 49667, 1586312 B, ET_REL)
#   onbox/unix    the P5.4r4 combined metal kernel, z3660scsi+z3660eth+cdfs
#                                             (sum -r 60364, 1587524 B, ET_REL)
#   boot2.boot    the flags-based loader, sha256 f287ff3a... (acquired + gated)
# Override sources with KERNBENCH_SRC / KERNZ3660_SRC / BOOT2_SRC; the gates
# below (sum -r + size for the kernels, sha256 for boot2) are always enforced.
# ======================================================================
if [ $do_m4 -eq 1 ]; then
  # ---- m4: the stock /usr/ccs/bin/m4 ALONE, so a box can run syslogd
  # without the 10 MB C development set.  The stock 2.1c syslogd (core) pipes
  # /etc/syslog.conf through /usr/ccs/bin/m4 unconditionally; without m4 the
  # conf parses empty and nothing is ever logged (every 1.1 install,
  # 2026-10-26).  Only Cdev ships m4.
  #
  # PROVENANCE: Amix 2.1 install tape, package Cdev (tape file 04, plain
  # newc, the List's third entry), member usr/ccs/bin/m4.  The bytes, mode,
  # owner and mtime come from that member's cpio header via
  # repackage-stock.py --member, exactly as the stock set gets them.
  #
  # SHARED WITH Cdev, ON PURPOSE.  Both packages deliver /usr/ccs/bin/m4, and
  # the gate below makes the m4 pkgmap row field-identical to Cdev's
  # (`f none 0755 bin bin 23004 51597 690829200`).  SVR4 pkgadd treats a
  # path another package already owns as a conflict only when its contents
  # (size, cksum, mtime) or attributes (mode, owner, group) differ
  # (heirloom libinst/pkgdbmerg.c, pkginstall/check.c ckconflct()); an
  # identical row just adds the package to the path's package list, and
  # pkgrm of one keeps the file for the other.  So m4 and Cdev install in
  # either order and remove independently.  NOTES 2026-10-26.
  M4_TAPE="$REPO/hdf/tape21"
  M4_LIST="$M4_TAPE/x00/List"
  [ -f "$M4_LIST" ] && [ -f "$M4_TAPE/04" ] || {
    echo "FATAL: install tape missing: $M4_TAPE (hdf/tape21, gitignored)" >&2; exit 1; }
  # tape file 04 is the List's third package (files 02.. carry the List in
  # order, repackage-stock.py FIRST_PKG_TAPE_FILE) -- refuse anything else
  if ! sed -n 3p "$M4_LIST" | grep -q '^pkg=Cdev[[:space:]]'; then
    echo "FATAL: $M4_LIST line 3 is not pkg=Cdev" >&2; exit 1
  fi
  M="$WORK/m4"; mkdir -p "$M"
  attr="$(python3 "$REPO/tools/repo/repackage-stock.py" \
            --member Cdev:usr/ccs/bin/m4 --out "$M/m4")"
  # Identity gate (fail closed): the member must be the factory Cdev
  # contents row for /usr/ccs/bin/m4 -- mode, owner, group, size, sum(1)
  # checksum and mtime.  Anything else would make the shared path a conflict.
  M4_ROW="0755 bin bin 23004 51597 690829200"
  set -- $attr
  got="$1 $2 $3 $4 $(sum -s "$M/m4" | awk '{print $1}') $5"
  if [ "$got" != "$M4_ROW" ]; then
    echo "FATAL: tape m4 is '$got', expected the Cdev row '$M4_ROW'" >&2; exit 1
  fi
  echo "m4 member OK: $got (md5 $(md5sum < "$M/m4" | cut -c1-32))"
  cat > "$M/pkginfo" <<EOF
PKG=m4
NAME=m4 macro processor (from the C Development system)
ARCH=Amiga
VERSION=$VER_M4
CATEGORY=system
CLASSES=none
APKG_DESC=m4 macro processor alone, /usr/ccs/bin/m4: syslogd reads /etc/syslog.conf through it. The same file as in cdev, either or both may be installed (Amix 2.1 stock, Cdev tape member)
EOF
  # /usr, /usr/ccs and /usr/ccs/bin are core's (and Cdev's) with these exact
  # attributes; declaring them the same way is a shared directory, not a
  # conflict.
  cat > "$M/prototype" <<EOF
i pkginfo
d none /usr 0755 bin bin
d none /usr/ccs 0755 bin bin
d none /usr/ccs/bin 0755 bin bin
f none /usr/ccs/bin/m4=$M/m4 0755 bin bin
EOF
  build_one m4 "$VER_M4" stock
  # the minted row must be the Cdev row, field for field (path/type/class too)
  if ! grep -aq "^1 f none /usr/ccs/bin/m4 $M4_ROW\$" "$out"; then
    echo "FATAL: $out pkgmap row for /usr/ccs/bin/m4 is not '$M4_ROW'" >&2
    rm -f "$out"; exit 1
  fi
  echo "m4 pkgmap row OK: 1 f none /usr/ccs/bin/m4 $M4_ROW"
fi

KPKG="$REPO/build/kernel-packages"
BOOT2_GATE="$REPO/../amix-kerntools/tools/boot2-sha-gate.sh"
BOOT2_SHA="f287ff3a759d6f80304fa35bb53e1479fc98056836b44a16824bd3e3f8fdba78"

if [ $do_kernbench -eq 1 ] || [ $do_kernz3660 -eq 1 ]; then
  # Acquire + sha-verify the shared flags-based boot2 via kerntools' gate.
  # The gate REFUSES the name-based install-media loader (5ab360b1...) that
  # D245s on metal, and any unknown sha.  The blob is never committed.
  [ -x "$BOOT2_GATE" ] || { echo "FATAL: boot2 gate missing: $BOOT2_GATE" >&2; exit 1; }
  BOOT2_SRC="${BOOT2_SRC:-$REPO/../amix-kerntools/work/boot2-proven.bin}"
  mkdir -p "$KPKG"
  bash "$BOOT2_GATE" --boot2 "$BOOT2_SRC" --out "$KPKG/boot2.boot" --quiet \
    || { echo "FATAL: boot2 acquisition/verification failed (need the proven" >&2
         echo "       flags-based loader; set BOOT2_SRC to its path)" >&2; exit 1; }
  echo "boot2 OK: $KPKG/boot2.boot (sha256 $BOOT2_SHA)"
fi

if [ $do_kernbench -eq 1 ]; then
  KB_DST="$KPKG/bench/unix"
  KB_SRC="${KERNBENCH_SRC:-$REPO/../amix-kerntools/work/p54r4-bench-smoke/relocunix}"
  mkdir -p "$KPKG/bench"
  [ -f "$KB_SRC" ] || {
    echo "FATAL: KERNBENCH payload missing: $KB_SRC" >&2
    echo "       the P5.4r4 bench kernel (sum -r 49667, 1586312 B) is expected" >&2
    echo "       at ../amix-kerntools/work/p54r4-bench-smoke/relocunix," >&2
    echo "       or set KERNBENCH_SRC." >&2
    exit 1; }
  # Gate the SOURCE first, then copy, then re-gate the staged copy.  Gating
  # only the destination (as this did until 2026-08-16) meant a REFUSED mint
  # had already overwritten build/kernel-packages/bench/unix with the bad
  # bytes -- the gate fired correctly but left known-bad payload staged for
  # whatever read it next.  Fail closed BEFORE the staging area is touched;
  # the second call still catches a truncated/failed copy.
  gate_kernel "$KB_SRC" 49667 1586312
  [ "$KB_SRC" != "$KB_DST" ] && cp "$KB_SRC" "$KB_DST"
  gate_kernel "$KB_DST" 49667 1586312
  cat > "$KPKG/bench/unix.provenance" <<PROV
KERNBENCH  /stand/unix  provenance
==================================
kernel class : a4091 + z3660eth + cdfs  (bench profile: PROBED support.c,
               scsi.c GSIO patch, per-unit DMA-bounce + start-queue-lifecycle
               a3091/a2091 fix, z3660eth at cdevsw 51, aen security patch in
               the link).  No z3660scsi -- z3660_direct_map is absent from
               this kernel and present in KERNZ3660, as the family demands.
rootdev      : 0x00480016  (c6d0s1 / config c6s1unix; SCSI target 6, slice 1)
shipped bytes: 1586312 B   sum -r 49667   md5 8072e610afa7060fb0c96b8536280b42
               sha256 2e575509907f1b697940b3342f775977bbeae916efb1cec90914d508a9476274
cdfs         : the ERRNO-DE-LAUNDERING object (amix-cdfs e0ef11a; exp
               96366 B, md5 673cd9f43a928d0e57e3a9c32cecb9a4, sum -r 56869)
               -- enforced by the kerntools fstypes.conf md5 provenance pin
               (kerntools 811dd0c; build log "(pin OK)").
support.c    : PROBED, not stock.  amix-a4091 support.c.patch (adf3875 line),
               applied by kpatch via the kernel-patches.conf always: row that
               went live at kerntools 5183993.  autocon() disassembly shows
               the TWO-REGISTER anti-alias probe (0x55/0xAA through SASR
               0xDD0041 + SCMD 0xDD0043, behind the VPOSR AGA gate); the
               0x7000000 RAM-size guess occurs ZERO times in the kernel.
               THIS RETIRES THE `support-stock` KMIX TAG on this line.
source       : the P5.4 r4 bench rebuild + bench-smoke run (amix-kerntools
               work/p54r4-bench-smoke/relocunix; run manifest provenance.txt
               + gates.tsv beside it).  Bench-smoke 8/8 PASS: four-arm
               buildgate STABLE after 2 builds (sum=49667), d245 relinkguard
               clean (new ref key d59fdc6d5d96), COLD BOOT to run-level 2 +
               LAN with on-box /stand/unix sum -r 49667, digest 3/3 vs host
               truth, teardown confirmed.  nm -u = {edata,end,etext}.  Built
               from the SAME patched image as the combined r4 kernel, so both
               r4 kernels carry byte-identical batch inputs.  The package
               ships the relocunix (ET_REL) bytes verbatim, KSUM_R = the
               relocunix sum -r.
supersedes   : KERNBENCH 64049-2026.08.07 (r3) -- ADDITIVE supersession, not
               a retraction: r3 is metal-green (2026-08-07 calibration) and
               its .pkg stays valid-in-place in kernel/ as the previous line.
               r4 simply carries the whole P5.4 regeneration batch that
               accumulated after r3 was cut.
               Lineage: r2 53963-2026.08.06 superseded-in-place (latent
               stack-sdcom defect, amix-cdfs 9360542), r1 45343-2026.08.06
               quarantined (POISONED/), W6-P 45473-2026.07.23 kept intact.
status       : bench-smoke GREEN (cold boot to run-level 2 + LAN, digest 3/3).
               NOT metal-flown -- this is the a4091 BENCH family; the r4
               metal proof belongs to the combined KERNZ3660 kernel (60364,
               flown 2026-08-15).
PROV
  K="$WORK/KERNBENCH"; mkdir -p "$K"
  cat > "$K/pkginfo" <<EOF
PKG=KERNBENCH
NAME=Amix kernel - a4091 + z3660eth + cdfs (bench, per-unit-bounce a3091 fix)
ARCH=Amiga
VERSION=$VER_KERNBENCH
CATEGORY=system
CLASSES=none
ROOTDEV=0x00480016
CONFIG=c6s1unix
KMIX=a4091,z3660eth,cdfs,a3091-fixed,a2091-fixed,scsi-gsio
KSUM_R=49667
BOOT2_SHA=$BOOT2_SHA
APKG_DESC=PRIVATE kernel package (NOT redistributable): /stand/unix bench kernel a4091+z3660eth+cdfs+a3091-fixed, probed support.c, rootdev c6s1unix 0x00480016, sum -r 49667; plus flags-based /stand/boot2.boot. pkgadd copies to /stand; installng updbootpart reframes the boot slice.
EOF
  # Payload class `none`, modes/owners per stock core's /stand entries
  # (read from core.cont: /stand 0755 root root, /stand/unix and
  # /stand/boot2.boot 0644 root root).  NO class-action / postinstall; NOTHING
  # touches a raw device -- the boot-slice reframe is installng's updbootpart.
  cat > "$K/prototype" <<EOF
i pkginfo
d none /stand 0755 root root
f none /stand/unix=$KB_DST 0644 root root
f none /stand/boot2.boot=$KPKG/boot2.boot 0644 root root
EOF
  build_one KERNBENCH "$VER_KERNBENCH" kernel "$KSTAGING"
fi

if [ $do_kernz3660 -eq 1 ]; then
  KZ_DST="$KPKG/onbox/unix"
  KZ_SRC="${KERNZ3660_SRC:-$REPO/../amix-kerntools/work/kernel-packages/p54r4-combined/unix}"
  mkdir -p "$KPKG/onbox"
  [ -f "$KZ_SRC" ] || {
    echo "FATAL: KERNZ3660 payload missing: $KZ_SRC" >&2
    echo "       the P5.4r4 combined metal kernel (sum -r 60364, 1587524 B) is" >&2
    echo "       expected at ../amix-kerntools/work/kernel-packages/p54r4-combined/unix," >&2
    echo "       or set KERNZ3660_SRC." >&2
    exit 1; }
  # Gate the SOURCE before it overwrites the staged payload -- see the
  # KERNBENCH arm above for why the destination-only gate was not enough.
  gate_kernel "$KZ_SRC" 60364 1587524
  [ "$KZ_SRC" != "$KZ_DST" ] && cp "$KZ_SRC" "$KZ_DST"
  gate_kernel "$KZ_DST" 60364 1587524
  cat > "$KPKG/onbox/unix.provenance" <<PROV
KERNZ3660  /stand/unix  provenance
==================================
kernel class : z3660scsi (piscsi) + z3660eth (net) + cdfs  (A4000 + Z3660 metal)
rootdev      : 0x00480016  (c6d0s1 / config c6s1unix; SCSI target 6, slice 1)
shipped bytes: 1587524 B   sum -r 60364   md5 23b4b8983435acdf900fa343cb33281d
               sha256 ff8bda02db7e6c0ae5281df59a8f06aa7b2d97271d2b711a49bb01c01074da58
cdfs         : the ERRNO-DE-LAUNDERING object (amix-cdfs e0ef11a; exp
               96366 B, md5 673cd9f43a928d0e57e3a9c32cecb9a4, sum -r 56869)
               -- enforced by the kerntools fstypes.conf md5 provenance pin
               (kerntools 811dd0c; build log "(pin OK)").
support.c    : PROBED, not stock (amix-a4091 support.c.patch, adf3875 line;
               kernel-patches.conf row @ kerntools 5183993).  kpatch verdict
               "4 target(s) checked, 3 applied (1 already present)"; new
               stamps a3091 2c1d3aa68cc5, a2091 5594f3d72b02, support.c
               aafd7b83c52d, aen 323873fd5ae0 unchanged.
direct maps  : FIRST kernel to fly BOTH.  z3660_direct_map (amix-z3660scsi
               8293cdc -- never flown before r4) and z3660eth_direct_map
               (amix-z3660net b89c5d2); together they return 98 sptmap pages
               (33 + 65) to the map.  Both disassembly-proven: span gate,
               direct arm sets the flag and does plain window arithmetic with
               NO sptalloc call; the sptalloc arm is retained.
source       : the P5.4 r4 combined rebuild (amix-kerntools
               work/kernel-packages/p54r4-combined/unix; provenance sibling
               there).  Metal-family kernel, z3660eth at cdevsw 51 proven
               BINARY-side ((0xada4-44-0xa31c)/52 = 51 exactly, stride
               corroborated by (cdevcnt-cdevsw)/52 = 70 = CDEVSIZE).
               Built on a WORK COPY of the golden image; combined clean-gate
               STABLE after 1 builds (undef=0, checkunix-clean, relgate-clean);
               pulled byte-exact (box 60364 == host 60364); nm -u =
               {edata,end,etext}; relsim COMPLAINTS=0 (29310 R_68K_32);
               d245-judge CLEAN; rootdev-assert PASS 0x00480016 + scsi-slice
               media pairing.  Same relocunix (ET_REL) representation
               KERNZ3660 has always shipped.
supersedes   : KERNZ3660 45833-2026.08.07 (r3) -- ADDITIVE supersession, not
               a retraction: r3 is metal-green (2026-08-07 calibration) and
               its .pkg stays valid-in-place in kernel/ as the previous line.
               Lineage: r2 14821-2026.08.06 superseded-in-place (latent
               stack-sdcom defect, amix-cdfs 9360542), r1 05929-2026.08.06
               quarantined (POISONED/), W6-P 00961-2026.07.23 kept intact.
status       : METAL-PROVEN 2026-08-15 (P5.4 R3) -- the
               updbootpart reframe was byte-clean, TWO cold power-to-network
               boots (~270 s each), and adb read z3660_direct_map = 1 AND
               z3660eth_direct_map = 1 live on the hardware, so the 98
               reclaimed sptmap pages are hardware fact, not a gate result.
               Record: amix-kerntools CHANGELOG 2026-08-15 metal postscript.
               60364 is now the last METAL-VALIDATED kernel identity.
PROV
  Z="$WORK/KERNZ3660"; mkdir -p "$Z"
  cat > "$Z/pkginfo" <<EOF
PKG=KERNZ3660
NAME=Amix kernel - z3660scsi + z3660eth + cdfs (A4000+Z3660 metal)
ARCH=Amiga
VERSION=$VER_KERNZ3660
CATEGORY=system
CLASSES=none
ROOTDEV=0x00480016
CONFIG=c6s1unix
KMIX=z3660scsi,z3660eth,cdfs
KSUM_R=60364
BOOT2_SHA=$BOOT2_SHA
APKG_DESC=PRIVATE kernel package (NOT redistributable): /stand/unix metal kernel z3660scsi+z3660eth+cdfs, probed support.c, both direct maps, rootdev c6s1unix 0x00480016, sum -r 60364; plus flags-based /stand/boot2.boot. pkgadd copies to /stand; installng updbootpart reframes the boot slice.
EOF
  cat > "$Z/prototype" <<EOF
i pkginfo
d none /stand 0755 root root
f none /stand/unix=$KZ_DST 0644 root root
f none /stand/boot2.boot=$KPKG/boot2.boot 0644 root root
EOF
  build_one KERNZ3660 "$VER_KERNZ3660" kernel "$KSTAGING"
fi

# Install the canonical authored dependency graph into the staging root so
# gen-catalog.py picks it up (includes the demo amixdemo->demolib edge).
# Redistributable staging only -- kernel packages are never cataloged.
#
# descs.conf rides along for the same reason and with the same safety: it
# names only packages WE mint, so staging it moves exactly those catalog
# lines and no others.
#
# names.conf rides along too, and its safety argument is DIFFERENT -- worth
# spelling out, because the descs.conf one does not apply.  names.conf is not
# "ours only": its sole entry today is `amixbench`, which the sibling
# amix-packages repo mints, not us.  It is safe because a package ABSENT from
# it keeps gen-catalog.py's default (the pkginst, lowercased), so staging it
# moves exactly the lines it names and no others -- the same structural
# property reached by a different route.
#
# It is staged here because the failure mode is SILENT: without it a package
# whose name cannot be its pkginst (the 9-char SVR4 ceiling) comes out in the
# catalog under its short instance name, with no error and no warning -- a
# wrong but perfectly well-formed catalog.  amix-benchmark/amixbench is the
# first such package and it was staged BY HAND for its publish; that hand
# step is what this line removes.
#
# cats.conf rides along as well -- since 2026-09-26, by decision of the
# consolidation review ("make the taxonomy live at the next publish").
# Until then it was DELIBERATELY not staged, and its safety argument is the
# opposite of descs.conf's: staging it DOES move lines we did not mint.  All
# 27 stock packages ship CATEGORY=system, so the first catalog generated from
# a staging that carries it re-categorises every stock line that is not base
# OS (net/uucp -> network, the seven source trees -> source, the X stack ->
# x11, ...) plus our own apkg/apkgeng (application -> system).  That is the
# point of the file and the change that was asked for.  It moves no .pkg
# byte and no .pkg md5 -- only catalog lines -- and a later edit here is one
# regenerate away.  The expected diff against the live catalog is recorded
# in NOTES.md (the 2026-09-26 PREPARED publish), so the next publish is
# reviewed as "these lines change category", not discovered.
if [ $do_apkg -eq 1 ] || [ $do_eng -eq 1 ] || [ $do_cdfs -eq 1 ] || [ $do_demo -eq 1 ] \
   || [ $do_m4 -eq 1 ]; then
  cp "$REPO/tools/repo/deps.conf" "$STAGING/deps.conf"
  cp "$REPO/tools/repo/descs.conf" "$STAGING/descs.conf"
  cp "$REPO/tools/repo/names.conf" "$STAGING/names.conf"
  cp "$REPO/tools/repo/cats.conf" "$STAGING/cats.conf"
  echo "staging: $STAGING"
  ls -laR "$STAGING"
fi

if [ $do_kernbench -eq 1 ] || [ $do_kernz3660 -eq 1 ]; then
  echo "PRIVATE kernel staging: $KSTAGING"
  ls -laR "$KSTAGING"
fi
