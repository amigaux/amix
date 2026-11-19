# hosttools.sh -- the shared host tools first on a recipe's PATH, and the gate
# that the recipe used them. Sourced by pkgbuild.sh (this checkout's layout),
# never executed.
#
# MIT licence, see LICENSE at the top of the repository.
#
# The tools whose output Amix reads (gencat, bdftopcf, mkfontdir, imake,
# makedepend) come from build/hosttools, built from our pinned sources, never
# from the build host: the host's write the host's formats and see the host's
# defines and headers (docs/build-tools.md).
#
#     amix_hosttools_setup
#         AMIX_HOSTTOOLS_BIN (a built set's bin/), else build/hosttools/build.sh's;
#         each tool must be there; puts it first on PATH and exports both
#     amix_gate_hosttools_path <when>
#         each name on PATH must be the shared set's: a hook that put another
#         directory first is refused (run before the build and after the stage)
#     amix_gate_hosttools_logs <build dir>
#         the build's logs (<build dir>/*.log) must not run one of these tools
#         by an absolute path to the build host's copy: a path outside the
#         shared set and the build directory, to an executable that exists
#         here. A recipe's own tool built in its tree, and a target path that
#         is not on this host, are not the host's.

case "${0##*/}" in
hosttools.sh)
	echo "[FAIL] hosttools.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_HOSTTOOL_NAMES="gencat bdftopcf mkfontdir imake makedepend"

amix_hosttools_setup() {
	if [ -z "${AMIX_HOSTTOOLS_BIN:-}" ]; then
		AMIX_HOSTTOOLS_BIN=$(sh "$AMIX_TOP/build/hosttools/build.sh") || {
			echo "[FAIL] the shared host tools did not build (build/hosttools/build.sh)" >&2
			return 1
		}
	fi
	AMIX_HOSTTOOLS_BIN=$(cd "$AMIX_HOSTTOOLS_BIN" 2>/dev/null && pwd) || {
		echo "[FAIL] AMIX_HOSTTOOLS_BIN is not a directory" >&2
		return 1
	}
	for _ht_t in $AMIX_HOSTTOOL_NAMES; do
		[ -x "$AMIX_HOSTTOOLS_BIN/$_ht_t" ] || {
			echo "[FAIL] the shared host tools in $AMIX_HOSTTOOLS_BIN have no $_ht_t" >&2
			return 1
		}
	done
	PATH=$AMIX_HOSTTOOLS_BIN:$PATH
	export PATH AMIX_HOSTTOOLS_BIN
	echo "  host tools: $AMIX_HOSTTOOLS_BIN ($AMIX_HOSTTOOL_NAMES)"
}

amix_gate_hosttools_path() {
	_ht_bad=
	for _ht_t in $AMIX_HOSTTOOL_NAMES; do
		_ht_p=$(command -v "$_ht_t" 2>/dev/null) || _ht_p="<none>"
		[ "$_ht_p" = "$AMIX_HOSTTOOLS_BIN/$_ht_t" ] || _ht_bad="$_ht_bad
         $_ht_t is $_ht_p"
	done
	if [ -n "$_ht_bad" ]; then
		echo "[FAIL] $1: the build host's tools come before the shared set ($AMIX_HOSTTOOLS_BIN) on PATH:$_ht_bad" >&2
		echo "       a recipe takes these from build/hosttools (docs/build-tools.md)" >&2
		return 1
	fi
	echo "  host tools gate ($1): $AMIX_HOSTTOOL_NAMES from the shared set"
}

amix_gate_hosttools_logs() {
	_ht_root=$(dirname "$AMIX_HOSTTOOLS_BIN")
	_ht_build=$(cd "$1" && pwd)
	_ht_names=$(echo "$AMIX_HOSTTOOL_NAMES" | tr ' ' '|')
	_ht_hits=$(for _ht_l in "$_ht_build"/*.log; do
		[ -f "$_ht_l" ] || continue
		grep -nEo "(^|[[:space:]\"'=;(&|\`])/[^[:space:]\"'=;()&|\`]*/($_ht_names)([[:space:]\"';)&|\`]|\$)" "$_ht_l" |
		while IFS= read -r _ht_m; do
			_ht_n=${_ht_m%%:*}
			_ht_p=${_ht_m#*:}
			_ht_p=/${_ht_p#*/}
			_ht_p=$(printf '%s' "$_ht_p" | sed "s/[[:space:]\"';)&|\`]*\$//")
			case $_ht_p in
			"$_ht_root"/*|"$_ht_build"/*) continue ;;
			esac
			[ -f "$_ht_p" ] && [ -x "$_ht_p" ] || continue
			echo "         ${_ht_l##*/}:$_ht_n: $_ht_p"
		done
	done)
	if [ -n "$_ht_hits" ]; then
		echo "[FAIL] the build ran the build host's own tools, not the shared set's ($AMIX_HOSTTOOLS_BIN):" >&2
		echo "$_ht_hits" >&2
		echo "       call them by name; build/pkg puts the shared set first on PATH (docs/build-tools.md)" >&2
		return 1
	fi
	echo "  host tools gate (logs): no build host copy of $AMIX_HOSTTOOL_NAMES"
}
