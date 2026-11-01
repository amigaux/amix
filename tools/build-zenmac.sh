#!/usr/bin/env bash
#
# build-zenmac.sh -- cross-build src/zenmac/zenmac.c into payload/zenmac.
#
# zenmac prints the Z3660 ethernet MAC as the z3660eth driver sees it (the address
# of a DLPI DL_BIND_ACK -- see the header of src/zenmac/zenmac.c for why a program
# is needed at all). S99zen's address-by-card step runs it at every boot
# (docs/address-by-card.md); build-install-iso.sh stages the result at
# /install/zenmac and install.sh lays it down at /usr/amiga/bin/zenmac.
#
# The output is a build artefact (gitignored): it is linked against the sysroot's
# crt objects and dynamically against /usr/lib/libc.so.1, so it carries vendor
# startup bytes and is never committed. Rebuild it from the tracked source.
#
# Toolchain: ../gcc-cross-amix (m68k-cbm-sysv4, gcc 2.7.2.3 + binutils 2.8.1). Its
# build/env.sh is sourced when present; AMIX_CROSS_ENV overrides the path.
#
# Usage: tools/build-zenmac.sh [--out FILE]      (default payload/zenmac)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
src="$repo/src/zenmac/zenmac.c"
out="$repo/payload/zenmac"
if [ "${1:-}" = --out ]; then out="$2"; fi

envsh="${AMIX_CROSS_ENV:-$repo/../gcc-cross-amix/build/env.sh}"
if ! command -v m68k-cbm-sysv4-gcc >/dev/null 2>&1; then
  [ -f "$envsh" ] || { echo "build-zenmac: STOP: no m68k-cbm-sysv4-gcc on PATH and no $envsh" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "$envsh"
fi
command -v m68k-cbm-sysv4-gcc >/dev/null 2>&1 || { echo "build-zenmac: STOP: m68k-cbm-sysv4-gcc not found after sourcing $envsh" >&2; exit 1; }

tmp="$(mktemp "${TMPDIR:-/tmp}/zenmac.XXXXXX")"
trap 'rm -f "${tmp:?}"' EXIT
# -m68020: the one binary runs on the 030, 040 and 060 lines alike (no FP at all).
m68k-cbm-sysv4-gcc -O -m68020 -o "$tmp" "$src"

# gates: a big-endian m68k ELF executable whose only DT_NEEDED is the target libc
hdr="$(od -An -tx1 -N20 "$tmp" | tr -d ' \n')"
case "$hdr" in
  7f454c46010201*) ;;
  *) echo "build-zenmac: STOP: output is not a 32-bit big-endian ELF ($hdr)" >&2; exit 1 ;;
esac
[ "${hdr:32:4}" = 0002 ] || { echo "build-zenmac: STOP: e_type ${hdr:32:4}, expected 0002 (ET_EXEC)" >&2; exit 1; }
[ "${hdr:36:4}" = 0004 ] || { echo "build-zenmac: STOP: e_machine ${hdr:36:4}, expected 0004 (m68k)" >&2; exit 1; }
needed="$(m68k-cbm-sysv4-objdump -p "$tmp" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')"
[ "$needed" = "/usr/lib/libc.so.1 " ] || { echo "build-zenmac: STOP: DT_NEEDED is [$needed], expected only /usr/lib/libc.so.1" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
cp "$tmp" "$out"
chmod 0755 "$out"
echo "build-zenmac: $out  $(wc -c <"$out") B  sha256 $(sha256sum "$out" | cut -c1-64)"
