# onever.sh -- one version, one set of bytes.  Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/onever.sh"
#     amix_one_version <rolled> <pkginst> <version> <outfile>
#
# Both roll functions (pkgroll.sh amix_pkgroll, kpkgroll.sh amix_kpkgroll)
# write the datastream to a work path first and install it at <outfile>
# only through this check, so every recipe that rolls a package is covered.
# If <pkginst> <version> appears in the catalog of record or any other kspace
# root (build/kspace/repo, next/repo, candidate-*, superseded/repo-*) with
# other bytes, the roll is REFUSED: <rolled> is removed and <outfile>, the
# datastream already there, is left untouched.  A byte-identical rebuild is
# allowed and says so; a version no root lists is new.  AMIX_ONEVER_ROOTS
# (space-separated directories holding a catalog) replaces the root list.
#
# Why: a version names one set of bytes -- the catalog row, an apkg record
# and the Bench's proof all key on it.  kern30m -20 / kern46m -50 re-rolled
# for pkginfo text alone (cfcfe78) made the same versions two byte-sets.
# A datastream is not bit-reproducible here (the newc headers carry the
# spool's inode numbers, pkgmap the control files' mtimes), so in practice
# any rebuild of a listed version is refused: a changed package takes a new
# version, and an unchanged one is not rolled again.

case "${0##*/}" in
onever.sh)
	echo "[FAIL] onever.sh is sourced, not executed" >&2
	exit 1
	;;
esac

amix_onever_roots() {
	if [ -n "${AMIX_ONEVER_ROOTS:-}" ]; then
		echo "$AMIX_ONEVER_ROOTS"
		return
	fi
	_ov_k="$AMIX_REPO_ROOT/build/kspace"     # not AMIX_BUILD_ROOT: gcc14-env moves that
	for _ov_d in "$_ov_k/repo" "$_ov_k/next/repo" "$_ov_k"/candidate-* "$_ov_k"/superseded/repo-*; do
		[ -f "$_ov_d/catalog" ] && printf '%s ' "$_ov_d"
	done
	echo
	unset _ov_k _ov_d
}

amix_one_version() {
	[ -f "$1" ] || { echo "[FAIL] one-version: no rolled datastream $1" >&2; exit 1; }
	# shellcheck disable=SC2046
	python3 -I "$AMIX_PKG_COMMON/onever.py" "$1" "$2" "$3" $(amix_onever_roots) > "$1.onever" 2>&1 \
		&& _ov_rc=0 || _ov_rc=$?     # recipes run under set -e
	sed 's/^/  /' "$1.onever"; rm -f "$1.onever"
	if [ "$_ov_rc" -ne 0 ]; then
		rm -f "$1"
		echo "[FAIL] one-version: $2 $3 not written to $4 (left as it was)" >&2
		unset _ov_rc
		exit 1
	fi
	mkdir -p "$(dirname "$4")"
	mv -f "$1" "$4"
	unset _ov_rc
}
