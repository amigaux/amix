# fetch.sh -- checksum-verified source fetch.  Sourced, never executed.
#
#     . "$REPO/recipes/common/fetch.sh"
#     amix_fetch "$URL" "$SHA256" "$BUILD/patch-2.5.9.tar.gz"
#
# Modelled on ../amix-040-060-port/tools/netbsd-pin.sh, and it keeps that
# script's two load-bearing properties:
#
#   1. THE PIN LIVES IN THE RECIPE, NOT HERE.  This file knows how to verify a
#      digest; it never knows what any digest should be.  The 040-060 lane's
#      note is exactly right -- "a check whose expected value exists in several
#      copies is a check that will eventually disagree with itself" -- so each
#      recipe's pin.sh holds one URL and one sha256, and everything else reads
#      it from there.
#
#   2. VERIFY BEFORE EXTRACT, NOT AFTER.  The digest is checked on the file on
#      disk before any caller is allowed to touch it.  Extracting first and
#      checking afterwards means the wrong bytes have already been unpacked, and
#      a build that then fails leaves a tree nobody can attribute.
#
# Downloads land in the recipe's build dir (gitignored).  A file already present
# and already matching is NOT re-downloaded -- that makes a rebuild offline-safe
# and keeps the bench from re-pulling 200 KB it already has.

case "${0##*/}" in
fetch.sh)
	echo "[FAIL] fetch.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# amix_sha256 <file> -- print the digest, or die.
amix_sha256() {
	sha256sum "$1" | cut -d' ' -f1
}

# amix_verify <file> <expected-sha256> -- the gate.  Prints the digest it
# accepted so a build log records exactly which bytes it was made from.
amix_verify() {
	_av_f="$1"
	_av_want="$2"
	[ -n "$_av_want" ] || {
		echo "[FAIL] amix_verify: called with no expected digest" >&2
		exit 1
	}
	[ -f "$_av_f" ] || {
		echo "[FAIL] source tarball not found: $_av_f" >&2
		exit 1
	}
	_av_got=$(amix_sha256 "$_av_f")
	[ "$_av_got" = "$_av_want" ] || {
		echo "[FAIL] $_av_f is not the pinned source tarball" >&2
		echo "       sha256   $_av_got" >&2
		echo "       expected $_av_want" >&2
		echo "       Different bytes are different upstream source, and everything this" >&2
		echo "       recipe measured was measured on the pinned ones.  The pin is the" >&2
		echo "       recipe's own pin.sh; do not edit it to match a download." >&2
		exit 1
	}
	echo "      source sha256 $_av_got  (pinned, verified)"
	unset _av_f _av_want _av_got
}

# amix_fetch <url> <expected-sha256> <destfile>
#
# Downloads to a sibling .part file and only renames after the digest matches,
# so an interrupted transfer can never be mistaken for a complete one -- the
# same failure shape amixsync.py hit when the 1991 ftpd's missing SIZE command
# made a truncation gate silently vacuous (PORTING.md sec 7).
amix_fetch() {
	_af_url="$1"
	_af_want="$2"
	_af_dst="$3"

	if [ -f "$_af_dst" ] && [ "$(amix_sha256 "$_af_dst")" = "$_af_want" ]; then
		echo "  cached  $_af_dst"
		amix_verify "$_af_dst" "$_af_want"
		unset _af_url _af_want _af_dst
		return 0
	fi

	mkdir -p "$(dirname "$_af_dst")"
	echo "  fetch   $_af_url"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 -o "$_af_dst.part" "$_af_url" || {
			echo "[FAIL] download failed: $_af_url" >&2
			rm -f "$_af_dst.part"
			exit 1
		}
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$_af_dst.part" "$_af_url" || {
			echo "[FAIL] download failed: $_af_url" >&2
			rm -f "$_af_dst.part"
			exit 1
		}
	else
		echo "[FAIL] neither curl nor wget on PATH" >&2
		exit 1
	fi

	amix_verify "$_af_dst.part" "$_af_want"
	mv "$_af_dst.part" "$_af_dst"
	unset _af_url _af_want _af_dst
}
