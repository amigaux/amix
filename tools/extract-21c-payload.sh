#!/usr/bin/env bash
#
# extract-21c-payload.sh -- pull the golden-proven vendor pieces the installer
# lays down out of the USER-SUPPLIED Amix 2.1c patch media, into the gitignored
# payload/21c/ tree, gated by pinned `sum -r` fingerprints. Fail-closed.
#
# WHY. Two P5.4 field findings (M-RUN-P5.4, 2026-08) need vendor bytes on the
# install media that the base-8 package set does not provide:
#
#   * /stand framing tools -- updbootpart's reframe pipeline needs
#     /stand/boot1.boot and a local /stand/makeiblk (its gate 5a fails closed
#     without them; on M-RUN4b the KERN handoff died "framed image is empty"
#     until the pair was ferried by hand from the bench golden). The goldens run
#     the 2.1c PATCHED makeiblk (14,924 B, sum -r 58483) -- that is the pair the
#     metal reframe was PROVEN with, so that is the pair the installer lays down.
#     (boot1.boot is NOT in the 2.1c patch -- the 2.1 original IS the golden's
#     copy; the media staging sources it from the extracted core tree, not here.)
#
#   * the syslog unit -- a base-8 install has core's /usr/sbin/syslogd (2.1,
#     22,368 B) but NO /etc/init.d/syslogd, NO rc links, NO /etc/syslog.conf and
#     no /var/log -- so it cannot log at all (kerntools
#     docs/inetd-telnet-throttle.md proved how expensive that silence is). The
#     complete, proven unit is the 2.1c patch's: init script (with the vendor
#     disable-`exit`), conf 1.1, and the "major revisions" 2.1c syslogd
#     (22,728 B) -- the exact combination the golden images run and the throttle
#     doc validated end to end.
#
# Both live in the 2.1c patch archive (archive.lha -> var/patch/archive.cpio),
# which is USER-SUPPLIED proprietary Commodore media: the extraction output under
# payload/21c/ is gitignored and referenced by checksum only (the repository's
# licensing rule -- same posture as every other golden-derived payload input).
#
#   tools/extract-21c-payload.sh                 # extract + verify (idempotent)
#   tools/extract-21c-payload.sh --check         # verify an existing payload/21c only
#   tools/extract-21c-payload.sh --archive PATH  # non-default archive.lha location
#
# Requires: lha (or lhasa), cpio. Exit 0 = extracted+verified; nonzero = STOP.

set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/.." && pwd)"

ARCHIVE="${ARCHIVE:-$repo/work/patch-extract/var/patch/archive.lha}"
OUT="$repo/payload/21c"
CHECK_ONLY=0

while [ $# -gt 0 ]; do case "$1" in
  --check)   CHECK_ONLY=1; shift;;
  --archive) ARCHIVE="$2"; shift 2;;
  -h|--help)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0;;
  *) echo "extract-21c-payload: unknown argument: $1" >&2; exit 2;;
esac; done

die() { echo "extract-21c-payload: STOP: $*" >&2; exit 1; }

# The pinned fingerprints (BSD `sum -r` checksum + byte size). These are the
# 2.1c patch's own bytes, cross-checked against the golden lineage: makeiblk
# 58483/14924 is the value the M-RUN-P5.4 ferry reassembled byte-perfect on
# metal; the syslog trio is the unit the throttle doc inventoried on the full
# 2.1c image (syslogd 22,728 B). A mismatch means the wrong/damaged archive --
# refuse, never stage.
declare -A WANT_SUM=(
  [stand/makeiblk]=58483
  [etc/syslog.conf]=63870
  [etc/init.d/syslogd]=14047
  [usr/sbin/syslogd]=53154
)
declare -A WANT_SIZE=(
  [stand/makeiblk]=14924
  [etc/syslog.conf]=1928
  [etc/init.d/syslogd]=727
  [usr/sbin/syslogd]=22728
)

sumr() { sum -r "$1" | awk '{print $1}'; }

verify() {
  local rc=0 f want got size
  for f in "${!WANT_SUM[@]}"; do
    if [ ! -f "$OUT/$f" ]; then
      echo "extract-21c-payload: MISSING $OUT/$f" >&2; rc=1; continue
    fi
    got="$(sumr "$OUT/$f")"; size="$(wc -c <"$OUT/$f")"
    want="${WANT_SUM[$f]}"
    if [ "$((10#$got))" -ne "$((10#$want))" ] || [ "$size" -ne "${WANT_SIZE[$f]}" ]; then
      echo "extract-21c-payload: FINGERPRINT MISMATCH $f: sum -r $got/$size bytes," \
           "expected $want/${WANT_SIZE[$f]}" >&2
      rc=1
    else
      printf 'extract-21c-payload: OK %-20s sum -r %05d  %6d bytes\n' "$f" "$((10#$got))" "$size"
    fi
  done
  return $rc
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  verify || die "payload/21c failed verification (re-run without --check to re-extract)"
  echo "extract-21c-payload: payload/21c verified."
  exit 0
fi

# Idempotence: a payload/21c that already verifies is left alone.
if verify >/dev/null 2>&1; then
  verify
  echo "extract-21c-payload: payload/21c already extracted + verified (no work)."
  exit 0
fi

[ -f "$ARCHIVE" ] || die "2.1c patch archive not found: $ARCHIVE
  This is USER-SUPPLIED proprietary media (the Amix 2.1c patch, archive.lha ->
  var/patch/archive.cpio). Place/extract it there, or pass --archive PATH."

LHA="$(command -v lha || command -v lhasa || true)"
[ -n "$LHA" ] || die "need lha or lhasa on the host to unpack $ARCHIVE"
command -v cpio >/dev/null || die "need cpio on the host"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp:?}"' EXIT

( cd "$tmp" && "$LHA" x "$ARCHIVE" >/dev/null 2>&1 ) || true
CPIO="$tmp/var/patch/archive.cpio"
[ -f "$CPIO" ] || die "archive.lha did not yield var/patch/archive.cpio (wrong archive?)"

# Extract ONLY the needed members (the archive holds the whole 2.1c replace set).
( cd "$tmp" && cpio -idm --no-absolute-filenames \
    'stand/makeiblk' 'etc/syslog.conf' 'etc/init.d/syslogd' 'usr/sbin/syslogd' \
    < "$CPIO" 2>/dev/null ) || true

mkdir -p "$OUT/stand" "$OUT/etc/init.d" "$OUT/usr/sbin"
for f in stand/makeiblk etc/syslog.conf etc/init.d/syslogd usr/sbin/syslogd; do
  [ -f "$tmp/$f" ] || die "member $f not found in the cpio (wrong/damaged archive?)"
  chmod u+r "$tmp/$f"   # the archive ships syslogd mode 0100 (--x------)
  rm -f "${OUT:?}/${f:?}"       # a prior copy may be read-only (archive modes)
  cp "$tmp/$f" "$OUT/$f"
done
# The archive ships usr/sbin/syslogd mode 0500 and cp preserves nothing here;
# make the staged copies host-readable so the media build can stage them (the
# on-disc + on-target modes are set by the staging/laydown, not by these).
chmod u+rw,go+r "$OUT/stand/makeiblk" "$OUT/etc/syslog.conf" \
                "$OUT/etc/init.d/syslogd" "$OUT/usr/sbin/syslogd"

verify || die "extraction produced wrong bytes -- refusing to leave a bad payload/21c"
echo "extract-21c-payload: done -> $OUT (gitignored; proprietary vendor bytes)"
