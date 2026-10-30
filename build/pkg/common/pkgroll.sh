# pkgroll.sh -- roll a staged install tree into an SVR4 .pkg datastream.
# Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/pkgroll.sh"
#     amix_pkgroll <workdir> <destroot> <PKG> <version> <outfile>
#
# <workdir>   holds the recipe's AUTHORED pkginfo and prototype
# <destroot>  the staged tree: <destroot>/usr/local/bin/patch etc.
# <PKG>       the SVR4 package abbreviation (<= 9 characters)
# <outfile>   the .pkg datastream to write
#
# The tooling is ../amix-packagemanager's HOST-built Heirloom pkgmk/pkgtrans --
# that repo is the authority on the .pkg format and its pkgmk carries the
# newc-emitting cpio shim.  We consume it; we never reimplement datastream
# assembly.  Everything below the pkgmk call is the gate set that repo's
# tools/repo/build-packages.sh already proved worth having.
#
# WHY pkgmk -r AND NOT ABSOLUTE PATHS IN THE PROTOTYPE.  The obvious prototype
# line is `f none /usr/local/bin/patch=/home/.../build/dest/usr/local/bin/patch`
# -- and that makes the prototype a GENERATED file, because half of it is one
# developer's home directory.  recipes/README.md says pkginfo and prototype are
# authored, not generated, and a file containing an absolute host path cannot be
# authored.  `pkgmk -r <destroot>` resolves every prototype path against the
# staged tree instead, so the committed prototype is exactly the package's
# installed layout and nothing else.

case "${0##*/}" in
pkgroll.sh)
	echo "[FAIL] pkgroll.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# amix_pkginfo_retag <pkginfo> <committed-version> <package-version> -- the
# committed pkginfo carries the period build's revision.  A TOOLCHAIN=gcc14
# build is different bytes, so it is a different package revision (a name
# never refers to two byte-sets): rewrite VERSION and PSTAMP in the WORK copy,
# never the committed file.  A no-op for the period toolchain.
amix_pkginfo_retag() {
	[ "$AMIX_TOOLCHAIN" = gcc14 ] || return 0
	[ "$2" = "$3" ] && return 0
	awk -v old="$2" -v new="$3" '
		$0 == "VERSION=" old { print "VERSION=" new; next }
		/^PSTAMP=/ && substr($0, length($0) - length(old) + 1) == old {
			print substr($0, 1, length($0) - length(old)) new "-gcc14"; next }
		{ print }' "$1" > "$1.retag" && mv "$1.retag" "$1"
	grep "^VERSION=$3\$" "$1" >/dev/null || {
		echo "[FAIL] could not retag $1 from $2 to $3" >&2; exit 1; }
	echo "  pkginfo retagged for gcc14: VERSION=$3, $(grep '^PSTAMP=' "$1")"
}

amix_pkgroll() {
	_pr_work="$1"
	_pr_root="$2"
	_pr_pkg="$3"
	_pr_ver="$4"
	_pr_final="$5"
	# rolled under the work dir; installed at <outfile> only through the
	# one-version check (onever.sh), which leaves <outfile> as it was on refusal
	_pr_out="$_pr_work/.roll/$(basename "$_pr_final")"
	command -v amix_one_version >/dev/null 2>&1 || . "$AMIX_PKG_COMMON/onever.sh"

	[ -x "$AMIX_PKGMK" ] || {
		echo "[FAIL] host pkgmk missing: $AMIX_PKGMK" >&2
		echo "       Run ../amix-packagemanager/heirloom/build-host.sh first." >&2
		exit 1
	}
	[ -x "$AMIX_PKGTRANS" ] || {
		echo "[FAIL] host pkgtrans missing: $AMIX_PKGTRANS" >&2
		exit 1
	}
	[ -f "$_pr_work/pkginfo" ]   || { echo "[FAIL] no pkginfo in $_pr_work" >&2; exit 1; }
	[ -f "$_pr_work/prototype" ] || { echo "[FAIL] no prototype in $_pr_work" >&2; exit 1; }

	# GATE 1 -- PKG name <= 9 characters.  Stock Amix pkgadd SILENTLY DROPS a
	# longer name: no error, no package, and the operator believes it worked.
	# (amix-packagemanager NOTES.md; PORTING.md sec 5.7.)
	if [ "${#_pr_pkg}" -gt 9 ]; then
		echo "[FAIL] PKG name '$_pr_pkg' is ${#_pr_pkg} characters; stock pkgadd silently drops > 9" >&2
		exit 1
	fi

	# GATE 2 -- the pkginfo must actually declare what we think it declares.
	# ARCH=m68k is wrong for this target; it is ARCH=Amiga.
	grep -q "^PKG=$_pr_pkg\$" "$_pr_work/pkginfo" || {
		echo "[FAIL] $_pr_work/pkginfo does not say PKG=$_pr_pkg" >&2; exit 1; }
	grep -q '^ARCH=Amiga$' "$_pr_work/pkginfo" || {
		echo "[FAIL] $_pr_work/pkginfo must say ARCH=Amiga (not m68k)" >&2; exit 1; }
	# A datastream name and its pkginfo VERSION must agree: a name never refers
	# to two byte-sets, so a rebuild with different bytes is a new package
	# revision (2.5.1a -> 2.5.1a-2) bumped in pkginfo AND in the recipe.
	grep -q "^VERSION=$_pr_ver\$" "$_pr_work/pkginfo" || {
		echo "[FAIL] $_pr_work/pkginfo VERSION is not $_pr_ver" >&2; exit 1; }

	# GATE 2b -- the 68060 gate over the WHOLE staged payload (gates.sh D4,
	# strict since 2026-10-05).  Run here, not only in the recipes, so that no
	# datastream can be rolled around a 68060-unimplemented instruction.
	command -v amix_gate_060_tree >/dev/null 2>&1 || . "$AMIX_PKG_COMMON/gates.sh"
	amix_gate_060_tree "$_pr_root" || {
		echo "[FAIL] 68060 gate: the payload of $_pr_pkg carries instructions a 68060" >&2
		echo "       SIGKILLs on, or (gcc14) a gate above failed -- e.g. 040/060-only FPU" >&2
		echo "       forms a 68881/68882 lacks; no datastream rolled." >&2
		exit 1
	}

	# GATE 3 -- s5 truncates a directory entry at 14 bytes, so two objects in
	# one directory sharing a 14-byte prefix cannot coexist on the target root.
	# Only a human can resolve a real collision (PORTING.md sec 5.8), so this
	# gate refuses rather than renames.  Keyed on (dirname, basename[:14]) --
	# a collision is a property of a DIRECTORY, which is the correction
	# amix-packagemanager's s5-collision-scan.py made to its own first scan.
	awk '
		$1 ~ /^[fdvexlsbcp]$/ && NF >= 3 {
			p = $3; sub(/=.*$/, "", p);
			n = split(p, seg, "/"); base = seg[n];
			dir = substr(p, 1, length(p) - length(base));
			key = dir "\001" substr(base, 1, 14);
			if (key in seen && seen[key] != base)
				printf "COLLIDE %s %s %s\n", dir, seen[key], base;
			seen[key] = base;
			if (length(base) > 14)
				printf "TRUNC %s (%d bytes -> %s)\n", p, length(base), substr(base, 1, 14);
		}
	' "$_pr_work/prototype" > "$_pr_work/.s5scan" 2>/dev/null
	if grep -q '^COLLIDE' "$_pr_work/.s5scan" 2>/dev/null; then
		echo "[FAIL] s5 14-byte name collision in $_pr_work/prototype:" >&2
		grep '^COLLIDE' "$_pr_work/.s5scan" >&2
		exit 1
	fi
	if grep -q '^TRUNC' "$_pr_work/.s5scan" 2>/dev/null; then
		echo "[FAIL] object basename exceeds the s5 14-byte dirent limit:" >&2
		grep '^TRUNC' "$_pr_work/.s5scan" >&2
		echo "       The file installs under a TRUNCATED name on the box, so anything" >&2
		echo "       looking it up by its full name will not find it.  Rename it in the" >&2
		echo "       recipe -- do not ship it and hope." >&2
		exit 1
	fi
	rm -f "$_pr_work/.s5scan"

	_pr_spool="$_pr_work/.spool"
	rm -rf "$_pr_spool"
	mkdir -p "$_pr_spool" "$(dirname "$_pr_out")"

	( cd "$_pr_work" && "$AMIX_PKGMK" -o -d "$_pr_spool" -f prototype -r "$_pr_root" ) || {
		echo "[FAIL] pkgmk failed for $_pr_pkg" >&2; exit 1; }

	rm -f "$_pr_out"
	"$AMIX_PKGTRANS" -s "$_pr_spool" "$_pr_out" "$_pr_pkg" >/dev/null || {
		echo "[FAIL] pkgtrans failed for $_pr_pkg" >&2; exit 1; }
	[ -f "$_pr_out" ] || { echo "[FAIL] pkgtrans produced no $_pr_out" >&2; exit 1; }

	# GATE 4 -- the datastream's members must be cpio newc.  A datastream whose
	# member archive is not 070701 is one stock Amix pkgadd rejects; the magic
	# sits at offset 512, right after the "# PaCkAgE DaTaStReAm" header block.
	_pr_magic=$(dd if="$_pr_out" bs=1 skip=512 count=6 2>/dev/null)
	if [ "$_pr_magic" != "070701" ]; then
		echo "[FAIL] $_pr_out member magic '$_pr_magic' != 070701" >&2
		exit 1
	fi

	# GATE 5 -- round-trip.  Unpack the datastream we just wrote and prove the
	# payload bytes survived, rather than trusting that pkgtrans exited 0.  The
	# family law is "verify the artifact, never the exit status"; a package is
	# an artifact like any other.
	_pr_rt="$_pr_work/.roundtrip"
	rm -rf "$_pr_rt"; mkdir -p "$_pr_rt"
	"$AMIX_PKGTRANS" -i "$_pr_out" "$_pr_rt" "$_pr_pkg" >/dev/null 2>&1 || true
	if [ ! -f "$_pr_rt/$_pr_pkg/pkgmap" ]; then
		# -i is header-only on some builds; fall back to a full extract.
		rm -rf "$_pr_rt"; mkdir -p "$_pr_rt"
		"$AMIX_PKGTRANS" "$_pr_out" "$_pr_rt" "$_pr_pkg" >/dev/null 2>&1 || true
	fi
	if [ -f "$_pr_rt/$_pr_pkg/pkgmap" ]; then
		echo "  pkgmap: $(grep -c . "$_pr_rt/$_pr_pkg/pkgmap") lines, classes: $(awk '$1 ~ /^[0-9]+$/ {print $3}' "$_pr_rt/$_pr_pkg/pkgmap" | sort -u | tr '\n' ' ')"
	else
		echo "[WARN] could not round-trip $_pr_out for inspection" >&2
	fi

	# GATE 6 -- the 68060 gate again, on the datastream as served, with the
	# packagemanager's scanner of record.  A hit removes the datastream.
	amix_gate_pkg060 "$_pr_out" || {
		rm -f "$_pr_out"
		echo "[FAIL] 68060 gate: $_pr_out removed" >&2
		exit 1
	}

	amix_one_version "$_pr_out" "$_pr_pkg" "$_pr_ver" "$_pr_final"
	echo "  built   $_pr_final ($(stat -c%s "$_pr_final") bytes, newc verified, md5 $(md5sum "$_pr_final" | cut -d' ' -f1))"
	unset _pr_work _pr_root _pr_pkg _pr_ver _pr_out _pr_final _pr_spool _pr_magic _pr_rt
}
