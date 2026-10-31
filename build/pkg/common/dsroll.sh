# dsroll.sh -- pkgmk and pkgtrans, so that the datastream is the same bytes
# however often, wherever and by whom it is rolled.  Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/dsroll.sh"
#     amix_dsroll <workdir> <destroot> <PKG> <outfile>
#     (with SOURCE_DATE_EPOCH set)
#
# Both roll functions (pkgroll.sh amix_pkgroll, kpkgroll.sh amix_kpkgroll)
# make their datastream here.  Left alone, pkgmk and pkgtrans write what the
# build host had: pkgmap's modtime column is each file's mtime, and each
# newc header carries the spool's inode and device numbers, the builder's
# uid and gid, the wall-clock mtime and modes from the umask; pkgtrans
# archives the members in the order find lists the spool, which is the
# filesystem's.  So:
#
#   1. every staged file and every control file of <workdir> gets the time
#      SOURCE_DATE_EPOCH before pkgmk, so pkgmap says that time;
#   2. pkgmk runs under umask 022; dsnorm.py then sets every spool object's
#      mode from pkgmap and its time to the epoch;
#   3. pkgtrans runs with sortedfind/ first on its PATH: its find sorts;
#   4. dsnorm.py rewrites each newc header in place (ino renumbered, uid,
#      gid and dev 0, mtime the epoch), and refuses a control file that
#      names <workdir>, <destroot> or the checkout; the same paths in the
#      payload are reported (a compiler's __FILE__, not the roll's).
#
# pkgmk sorts pkgmap by path, and pkginfo is pkgmeta's, so with one epoch two
# rolls of one recipe are byte-identical (build/pkg/tests/repro-selftest.sh).

case "${0##*/}" in
dsroll.sh)
	echo "[FAIL] dsroll.sh is sourced, not executed" >&2
	exit 1
	;;
esac

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
	_ds_find=$(command -v find) || { echo "[FAIL] roll: no find" >&2; exit 1; }
	case "$_ds_find" in "$AMIX_PKG_COMMON/sortedfind/"*)
		echo "[FAIL] roll: sortedfind/ is already on PATH" >&2; exit 1 ;; esac

	find "$_ds_root" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
	find "$_ds_work" -maxdepth 1 -type f -exec touch -d "@$SOURCE_DATE_EPOCH" {} +

	_ds_spool="$_ds_work/.spool"
	rm -rf "$_ds_spool"
	mkdir -p "$_ds_spool" "$(dirname "$_ds_out")"
	( umask 022; cd "$_ds_work" && "$AMIX_PKGMK" -o -d "$_ds_spool" -f prototype -r "$_ds_root" ) || {
		echo "[FAIL] pkgmk failed for $_ds_pkg" >&2; exit 1; }
	python3 -I "$AMIX_PKG_COMMON/dsnorm.py" spool "$_ds_spool" "$_ds_pkg" "$SOURCE_DATE_EPOCH" || exit 1

	rm -f "$_ds_out"
	( umask 022; PATH="$AMIX_PKG_COMMON/sortedfind:$PATH" AMIX_REAL_FIND="$_ds_find" \
		"$AMIX_PKGTRANS" -s "$_ds_spool" "$_ds_out" "$_ds_pkg" ) >/dev/null || {
		echo "[FAIL] pkgtrans failed for $_ds_pkg" >&2; exit 1; }
	[ -f "$_ds_out" ] || { echo "[FAIL] pkgtrans produced no $_ds_out" >&2; exit 1; }
	python3 -I "$AMIX_PKG_COMMON/dsnorm.py" stream "$_ds_out" "$SOURCE_DATE_EPOCH" \
		--host "$(cd "$_ds_work" && pwd -P)" --host "$(cd "$_ds_root" && pwd -P)" \
		--host "${AMIX_REPO_ROOT:-}" || { rm -f "$_ds_out"; exit 1; }
	unset _ds_work _ds_root _ds_pkg _ds_out _ds_find _ds_spool
}
