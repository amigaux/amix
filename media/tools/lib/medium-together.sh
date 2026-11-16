# tools/lib/medium-together.sh -- the packages a medium must carry together, sourced by build-install-iso.sh.
#
# MIT licence, see LICENSE at the top of the repository.
#
#   medium_together IN TOP WORK
#
# IN is the media's inputs (L11_IN: INPUTS, kpkg/catalog, base/catalog.lines), TOP the amix
# checkout, WORK a scratch directory. The rules are the release step's own,
# TOP/release/together-<release> for the release IN/INPUTS names, read by TOP/build/release-together
# against the medium's catalog: its kernel-space catalog and its base packages' rows, what the
# installer lays on a disk. A card file newer than the base's xstart, say, is refused here rather
# than warned on every installed disk. No rules file for the release: nothing to hold, and said.
# Status 0 every rule holds, 1 one does not (release-together names it) or an input is missing.
medium_together() {
	_mt_rel=$(sed -n 's/^release //p' "$1/INPUTS" 2>/dev/null | sed -n 1p)
	[ -n "$_mt_rel" ] || { echo "medium-together: $1/INPUTS names no release" >&2; return 1; }
	_mt_rules="$2/release/together-$_mt_rel"
	if [ ! -f "$_mt_rules" ]; then
		echo "medium-together: no release/together-$_mt_rel, no rules to hold"
		return 0
	fi
	[ -f "$2/build/release-together" ] || { echo "medium-together: no $2/build/release-together" >&2; return 1; }
	[ -f "$1/kpkg/catalog" ] && [ -f "$1/base/catalog.lines" ] \
		|| { echo "medium-together: $1 lacks kpkg/catalog or base/catalog.lines" >&2; return 1; }
	cat "$1/kpkg/catalog" "$1/base/catalog.lines" > "$3/medium.catalog" || return 1
	python3 "$2/build/release-together" "$_mt_rules" "$3/medium.catalog"
}
