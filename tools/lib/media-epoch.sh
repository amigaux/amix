# tools/lib/media-epoch.sh -- sourced by every script that writes a 1.1 medium: SOURCE_DATE_EPOCH from
# the inputs ($L11_IN/EPOCH, the dist revision's commit time, tools/build-l11-inputs.sh), so the same
# inputs give the same bytes. dlm's kbootset (media: the set id, the created times) and mkstore honour it;
# the ISOs pin every file and volume date to it (xorriso --set_all_file_dates); the boot disk's FFS dates
# come from tools/lib/xdftool-epoch.py. A caller's own SOURCE_DATE_EPOCH wins; without either the build
# stamps the clock as before (not a medium of record).
media_epoch() {
	if [ -z "${SOURCE_DATE_EPOCH:-}" ] && [ -n "${L11_IN:-}" ] && [ -s "$L11_IN/EPOCH" ]; then
		SOURCE_DATE_EPOCH="$(tr -d ' \n' < "$L11_IN/EPOCH")"
	fi
	case "${SOURCE_DATE_EPOCH:-}" in
		"") ;;
		*[!0-9]*) echo "media-epoch: SOURCE_DATE_EPOCH '$SOURCE_DATE_EPOCH' is not seconds since 1970" >&2; return 1 ;;
		*) export SOURCE_DATE_EPOCH ;;
	esac
	return 0
}
