#!/usr/bin/env bash
# build-setclk.sh -- build the Y2K-fixed setclk (IN-rtc) into payload/setclk.
#
# The stock Amix 2.1 /usr/amiga/bin/setclk formats the year with %02d and has
# 11-byte buffers, so from 2000 on it reads the battery clock wrong and hands
# date(1) a bad argument ("date: bad conversion"). The community fixed it in the
# source (src/setclk/setclk-y2k.patch has the provenance). The source itself is
# Commodore's and is NEVER committed: this tool lifts it out of the user-supplied
# stock amigasrc package (sha-pinned), applies our patch, and cross-builds it with
# gcc-cross-amix. Output payload/setclk is a build artefact (gitignored).
#
# Usage: tools/build-setclk.sh [--pkg amigasrc-2.1.pkg] [--out FILE] [--keep-src DIR]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"
PKG="$repo/../amix-packagemanager/build/repo-staging/stock/amigasrc-2.1.pkg"
PKG_SHA=01de21f232828acb8e4bf4e266e6c069ab3db81ac3240fb03868c1b132626ed0
SRC_SHA=03a00a434cff9137eaca276dab073cacd1003c0a0e2eff9493c058086b104901
PATCH="$repo/src/setclk/setclk-y2k.patch"
OUT="$repo/payload/setclk"; KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pkg) PKG="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --keep-src) KEEP="$2"; shift 2;;
    *) echo "usage: $0 [--pkg amigasrc-2.1.pkg] [--out FILE] [--keep-src DIR]" >&2; exit 2;;
  esac
done
die() { echo "build-setclk: STOP: $*" >&2; exit 1; }
[ -f "$PKG" ] || die "no stock amigasrc package at $PKG (user-supplied; pass --pkg)"
[ "$(sha256sum "$PKG" | cut -c1-64)" = "$PKG_SHA" ] || die "$PKG sha256 != $PKG_SHA"

envsh="${AMIX_CROSS_ENV:-$repo/../gcc-cross-amix/build/env.sh}"
if ! command -v m68k-cbm-sysv4-gcc >/dev/null 2>&1; then
  [ -f "$envsh" ] || die "no m68k-cbm-sysv4-gcc on PATH and no $envsh"
  # shellcheck disable=SC1090
  . "$envsh"
fi
command -v m68k-cbm-sysv4-gcc >/dev/null 2>&1 || die "m68k-cbm-sysv4-gcc not found after sourcing $envsh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/setclk.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
# The datastream's cpio is newc (070701): 110-byte header, name, pad to 4, body.
python3 - "$PKG" "$tmp/setclk.c" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
nm = b'root/usr/amiga/src/cmd/setclk/setclk.c\x00'
i = d.find(nm)
if i < 0: sys.exit("setclk.c not found in the package datastream")
h = d.rfind(b'070701', 0, i)
hdr = d[h:h + 110]
fs, ns = int(hdr[54:62], 16), int(hdr[94:102], 16)
off = 110 + ns; off += (-off) % 4
open(sys.argv[2], 'wb').write(d[h + off:h + off + fs])
PY
[ "$(sha256sum "$tmp/setclk.c" | cut -c1-64)" = "$SRC_SHA" ] || die "extracted setclk.c sha256 != $SRC_SHA"
(cd "$tmp" && patch -s -p1 --no-backup-if-mismatch < "$PATCH") || die "setclk-y2k.patch does not apply"
[ -z "$KEEP" ] || { mkdir -p "$KEEP"; cp "$tmp/setclk.c" "$KEEP/setclk.c"; }

# The stock Makefile builds with plain gcc; build the same way the fieldkit tools
# are: AMIX_USER_CFLAGS (the T-9 defines, -m68020) from gcc-cross-amix's env.
# shellcheck disable=SC2086
m68k-cbm-sysv4-gcc ${AMIX_USER_CFLAGS:--O -m68020} -o "$tmp/setclk" "$tmp/setclk.c" \
  || die "cross build failed"

hdr="$(od -An -tx1 -N20 "$tmp/setclk" | tr -d ' \n')"
case "$hdr" in 7f454c46010201*) ;; *) die "output is not a 32-bit big-endian ELF ($hdr)";; esac
[ "${hdr:32:4}" = 0002 ] || die "e_type ${hdr:32:4}, expected 0002 (ET_EXEC)"
[ "${hdr:36:4}" = 0004 ] || die "e_machine ${hdr:36:4}, expected 0004 (m68k)"
needed="$(m68k-cbm-sysv4-objdump -p "$tmp/setclk" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')"
[ "$needed" = "/usr/lib/libc.so.1 " ] || die "DT_NEEDED is [$needed], expected only /usr/lib/libc.so.1"
strings "$tmp/setclk" | grep -q '%02d%02d%02d%02d%03d' || die "the %03d year scan is not in the binary"
strings "$tmp/setclk" | grep -q "not plausible (1992..2037)" || die "the plausibility gate is not in the binary"
strings "$tmp/setclk" | grep -q "/usr/bin/date" && die "the rc path still runs date(1) (IN-rtc-2: mktime + stime)"
strings "$tmp/setclk" | grep -q ":%02d %s (%s) -> system clock set" || die "the to-the-second console line is not in the binary"

mkdir -p "$(dirname "$OUT")"; cp "$tmp/setclk" "$OUT"; chmod 0755 "$OUT"
echo "build-setclk: $OUT  $(wc -c <"$OUT") B  sha256 $(sha256sum "$OUT" | cut -c1-64)"
