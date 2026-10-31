# dsroll.sh -- pkgmk and pkgtrans, so that the datastream is the same bytes
# however often, wherever and by whom it is rolled.  Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/dsroll.sh"
#     amix_dsroll <workdir> <destroot> <PKG> <outfile>
#     (with SOURCE_DATE_EPOCH set)
#
# Both roll functions (pkgroll.sh amix_pkgroll, kpkgroll.sh amix_kpkgroll)
# make their datastream here.  Under SOURCE_DATE_EPOCH, pkgmk and pkgtrans
# (userland/pkgtools, ad02a5a) write what depends only on the inputs and the
# epoch: pkgmap's modtime column and every spool time are the epoch, spool
# modes are pkgmap's, the members are archived in sorted order, and each
# newc header says ino in archive order, uid, gid and dev 0, mtime the epoch.
# Before pkgmk, arnorm.py gives every ar archive of the payload the member
# headers `ar D` writes (date, uid and gid 0, mode 644), since a recipe's
# make runs `$(AR) rc` and gcc14's ar is not deterministic.
# dsnorm.py then checks the datastream for all of that, and never writes:
# anything else is refused.  It also refuses a control file that names
# <workdir>, <destroot>, the build root or the checkout.  The same paths in
# the payload are refused for a gcc14 build, whose compiler remaps them
# (gcc14-env.sh), and reported for the period compiler, which cannot (make
# dist gives it fixed paths in the container).
#
# pkgmk sorts pkgmap by path, and pkginfo is pkgmeta's, so with one epoch two
# rolls of one recipe are byte-identical (build/pkg/tests/repro-selftest.sh).
#
# Before pkgmk, amix_classes checks what pkgmk would otherwise decide: a
# pkginfo without PSTAMP gets the build host's name and the date from pkgmk,
# and a class the prototype uses but pkginfo's CLASSES does not list is only
# a pkgmk warning, while stock pkgadd installs only the listed classes and
# skips the rest without a word (pkginfo(4); a module's device nodes, C3-5
# section 1.2).  Without a CLASSES line pkgmk lists every class itself.

case "${0##*/}" in
dsroll.sh)
	echo "[FAIL] dsroll.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# amix_classes <prototype> <pkginfo> -- refuses a pkginfo without PSTAMP, and
# an object of a class that pkginfo's CLASSES does not list.
amix_classes() {
	grep '^PSTAMP=.' "$2" >/dev/null || {
		echo "[FAIL] $2 has no PSTAMP; pkgmk would write the build host's name and the date" >&2
		exit 1
	}
	_cl_list=$(sed -n 's/^CLASSES=//p' "$2" | head -1 | sed 's/^"\(.*\)"$/\1/')
	grep '^CLASSES=' "$2" >/dev/null || return 0
	awk -v list=" $_cl_list " '
		/^[ \t]*[#!]/ || NF < 3 { next }
		{ t = $1; c = $2; if (t ~ /^[0-9]+$/) { t = $2; c = $3 } }
		t ~ /^[fevdxlspcb]$/ && index(list, " " c " ") == 0 { printf "%s %s %s\n", t, c, (t == $1 ? $3 : $4) }
	' "$1" | sed 's/^/       /' > "$1.classes"
	if [ -s "$1.classes" ]; then
		echo "[FAIL] objects of a class pkginfo's CLASSES ($_cl_list) does not list; stock pkgadd skips them:" >&2
		cat "$1.classes" >&2
		rm -f "$1.classes"; exit 1
	fi
	rm -f "$1.classes"
	unset _cl_list
}

# amix_host_paths <path>... -- `--host <path>' for each build-host path a
# datastream must not name.  A one-component path is left out: /src is the
# build container's fixed checkout (gcc14 writes it for the checkout too),
# no host's own, and ordinary text in a package's documentation.
amix_host_paths() {
	for _hp in "$@"; do
		case "$_hp" in /*/*) printf -- '--host %s\n' "$_hp" ;; esac
	done
	unset _hp
}

amix_dsroll() {
	_ds_work="$1"
	_ds_root="$2"
	_ds_pkg="$3"
	_ds_out="$4"
	case "${SOURCE_DATE_EPOCH:-}" in
	''|*[!0-9]*)
		echo "[FAIL] roll: SOURCE_DATE_EPOCH '${SOURCE_DATE_EPOCH:-}' is not a number of seconds;" >&2
		echo "       every time stamp of the datastream is taken from it" >&2
		exit 1
		;;
	esac
	export SOURCE_DATE_EPOCH
	amix_classes "$_ds_work/prototype" "$_ds_work/pkginfo"
	# a static library's member headers carry the build's time and uid
	python3 -I "$AMIX_PKG_COMMON/arnorm.py" "$_ds_root" || exit 1

	_ds_spool="$_ds_work/.spool"
	rm -rf "$_ds_spool"
	mkdir -p "$_ds_spool" "$(dirname "$_ds_out")"
	( cd "$_ds_work" && "$AMIX_PKGMK" -o -d "$_ds_spool" -f prototype -r "$_ds_root" ) || {
		echo "[FAIL] pkgmk failed for $_ds_pkg" >&2; exit 1; }

	rm -f "$_ds_out"
	"$AMIX_PKGTRANS" -s "$_ds_spool" "$_ds_out" "$_ds_pkg" >/dev/null || {
		echo "[FAIL] pkgtrans failed for $_ds_pkg" >&2; exit 1; }
	[ -f "$_ds_out" ] || { echo "[FAIL] pkgtrans produced no $_ds_out" >&2; exit 1; }
	# shellcheck disable=SC2046 (one --host and one path per word)
	python3 -I "$AMIX_PKG_COMMON/dsnorm.py" stream "$_ds_out" "$SOURCE_DATE_EPOCH" \
		$(amix_host_paths "$(cd "$_ds_work" && pwd -P)" "$(cd "$_ds_root" && pwd -P)" \
			"${AMIX_REPO_ROOT:-}" "${AMIX_BUILD_ROOT:-}") \
		${AMIX_PREFIX_MAP:+--refuse-payload} || { rm -f "$_ds_out"; exit 1; }
	unset _ds_work _ds_root _ds_pkg _ds_out _ds_spool
}
