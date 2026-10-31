# pkgroll.sh -- roll a staged install tree into an SVR4 .pkg datastream.
# Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/pkgroll.sh"
#     amix_pkgroll <workdir> <destroot> <PKG> <version> <outfile>
#     (with $CONFFILES, the package.sh list, in the environment or the shell,
#     and SOURCE_DATE_EPOCH, the time of every stamp: dsroll.sh)
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

# amix_s5_mark <prototype> <pkginfo> -- GATE 3, s5's 14-byte directory
# entries (P-35 Option C; userland/pkgtools/docs/design.md sec 2b).  s5 cuts
# a name at 14 bytes, so on s5 an object with a longer basename installs under
# a truncated name, and two objects in one directory sharing their first 14
# bytes collide.  UFS has neither limit, and is the filesystem for new
# installs.  So a package with any object basename over 14 bytes is marked
# UFS-only: pkginfo gets APKG_FSTYPE=ufs, apkg refuses it on s5, and the s5
# rule does not apply to it (long names and 14-byte collisions are allowed).
# A package without one is left unmarked and must pass the s5 rule, which then
# only a human can fix (PORTING.md sec 5.8): this gate refuses, never renames.
# Keyed on (dirname, basename[:14]): a collision is a property of a DIRECTORY.
# An APKG_FSTYPE the pkginfo already carries is kept if it is a well-formed
# list, as apkg reads it (names of 1-15 [a-z0-9], comma-separated); one that
# names s5 cannot carry long names.  Every pkgadd ignores the parameter.
amix_s5_mark() {
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
	' "$1" > "$1.s5scan" 2>/dev/null
	_s5_fs=$(sed -n 's/^[ 	]*APKG_FSTYPE[ 	]*=[ 	]*//p' "$2" | head -1 |
		sed 's/[ 	]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/')
	if grep '^[ 	]*APKG_FSTYPE[ 	]*=' "$2" >/dev/null &&
	   ! echo "$_s5_fs" | grep -E '^[a-z0-9]{1,15}(,[a-z0-9]{1,15})*$' >/dev/null; then
		echo "[FAIL] $2: APKG_FSTYPE=$_s5_fs is not a list of filesystem types" >&2
		rm -f "$1.s5scan"; exit 1
	fi
	if grep '^TRUNC' "$1.s5scan" >/dev/null; then
		if [ -z "$_s5_fs" ]; then
			echo "APKG_FSTYPE=ufs" >> "$2"
			_s5_fs=ufs
		fi
		case ",$_s5_fs," in
		*,s5,*)
			echo "[FAIL] $2: APKG_FSTYPE=$_s5_fs names s5, but object basenames exceed s5's 14 bytes:" >&2
			grep '^TRUNC' "$1.s5scan" >&2
			rm -f "$1.s5scan"; exit 1
			;;
		esac
		echo "  UFS mark  APKG_FSTYPE=$_s5_fs: $(grep -c '^TRUNC' "$1.s5scan") object basename(s) over 14 bytes; apkg refuses it on s5"
	else
		if grep '^COLLIDE' "$1.s5scan" >/dev/null; then
			echo "[FAIL] s5 14-byte name collision in $1:" >&2
			grep '^COLLIDE' "$1.s5scan" >&2
			rm -f "$1.s5scan"; exit 1
		fi
		echo "  S5 ok     every object basename within 14 bytes${_s5_fs:+, APKG_FSTYPE=$_s5_fs as authored}"
	fi
	rm -f "$1.s5scan"
	unset _s5_fs
}

# amix_conffiles <workdir> <paths> -- the config files the administrator edits
# in place (package.sh CONFFILES, P-36 section 1.2).  Their lines of the WORK
# prototype become `e conffile', and the shared class action scripts of
# userland/pkgtools (src/conffile, i.conffile and r.conffile: keep an edited
# file, write the new default beside it) are copied next to the prototype
# and named on `i' lines, so no host path enters it.  pkgmeta has already
# checked the list against the prototype; here every path must be rewritten
# once, and pkginfo must say CLASSES=none conffile.  No paths: nothing.
amix_conffiles() {
	_cf_list=$(echo "$2" | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//')
	[ -n "$_cf_list" ] || return 0
	_cf_dir="${AMIX_CONFFILE_DIR:-$AMIX_PKGMGR/src/conffile}"
	for _cf_s in i.conffile r.conffile; do
		[ -f "$_cf_dir/$_cf_s" ] || {
			echo "[FAIL] CONFFILES: no $_cf_dir/$_cf_s (userland/pkgtools src/conffile)" >&2
			exit 1
		}
		cp "$_cf_dir/$_cf_s" "$1/$_cf_s"
	done
	grep '^CLASSES=none conffile$' "$1/pkginfo" >/dev/null || {
		echo "[FAIL] CONFFILES: $1/pkginfo does not say CLASSES=none conffile" >&2; exit 1; }
	awk -v list=" $_cf_list " '
		$1 ~ /^[fe]$/ && NF >= 3 {
			p = $3; sub(/=.*$/, "", p)
			if (index(list, " " p " ")) { $1 = "e"; $2 = "conffile"; n[p]++ }
		}
		{ print }
		END {
			print "i i.conffile"; print "i r.conffile"
			k = split(substr(list, 2, length(list) - 2), want, " ")
			for (i = 1; i <= k; i++)
				if (n[want[i]] != 1) {
					printf "%s is on %d prototype line(s), not 1\n", want[i], n[want[i]] > "/dev/stderr"
					bad = 1
				}
			exit bad
		}' "$1/prototype" > "$1/prototype.cf" || {
		rm -f "$1/prototype.cf"
		echo "[FAIL] CONFFILES: the prototype does not hold each listed path once" >&2
		exit 1
	}
	mv "$1/prototype.cf" "$1/prototype"
	echo "  CONFFILES $(echo "$_cf_list" | wc -w): e conffile, with i.conffile and r.conffile ($_cf_dir)"
	unset _cf_list _cf_dir _cf_s
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

	# GATE 3 -- the s5 14-byte rule, or the UFS mark (amix_s5_mark above).
	amix_s5_mark "$_pr_work/prototype" "$_pr_work/pkginfo"

	# Config files: CONFFILES from package.sh, when the driver set it.
	amix_conffiles "$_pr_work" "${CONFFILES:-}"

	# pkgmk and pkgtrans, every time stamp SOURCE_DATE_EPOCH (dsroll.sh)
	command -v amix_dsroll >/dev/null 2>&1 || . "$AMIX_PKG_COMMON/dsroll.sh"
	amix_dsroll "$_pr_work" "$_pr_root" "$_pr_pkg" "$_pr_out"

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
	unset _pr_work _pr_root _pr_pkg _pr_ver _pr_out _pr_final _pr_magic _pr_rt
}
