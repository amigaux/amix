# ksh93-record.sh record|verify BUILD ANSWERS -- the answers of dtksh's ksh93
# feature probes, from an Amix box (README.md, dtksh).  Runs in the toolchain
# image with the box's network, AMIX_HOST and AMIX_PASS (root's) set and the
# toolchain's environment (build/pkg/common/gcc14-env.sh).  BUILD: a cde build directory
# (out/build/userland/cde), whose ksh93-src (the patched source, unbuilt) is
# built here in a copy, with the options of ksh93-probes/shopts.
# record: probe runs ANSWERS has no answer to are run on the box and added
#   (a new file is a whole recording).
# verify: every probe is run on the box again, into a new file, which is then
#   compared with ANSWERS; any difference is listed and fails.
# MIT licence, see LICENSE in userland/packages.
mode=$1 B=$2 A=$3
here=$(cd "$(dirname "$0")" && pwd)
case $mode in record|verify) ;; *) echo "usage: ksh93-record.sh record|verify BUILD ANSWERS" >&2; exit 2;; esac
: "${AMIX_HOST:?}" "${AMIX_PASS:?}" "${CC:?the toolchain environment}"
[ -d "$B/ksh93-src" ] && [ -f "$B/ksh93-probes/shopts" ] || {
	echo "ksh93-record.sh: $B is not a cde build directory (ksh93-src, ksh93-probes/shopts)" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/ksh93-record.XXXXXX") || exit 1
cp -R "$B/ksh93-src" "$W/ksh93" || exit 1
out=$A
[ $mode = verify ] && out=$W/answers
PCC_HEAD="# dtksh's ksh93: the answers of its feature probes, recorded on Amix (README.md, dtksh)
# toolchain: gcc14-cross-amix $(sed -n 's/.* //p' /opt/amix/PINS/gcc14-cross-amix.pin 2>/dev/null)"
PCC_STORE=$W/store; mkdir -p "$PCC_STORE"
export PCC_HEAD PCC_STORE
python3 -I "$here/prund.py" "$W/sock" "$out" > "$W/prund.log" 2>&1 &
d=$!
i=0; while [ $i -lt 60 ] && ! grep -q ready "$W/prund.log"; do sleep 1; i=$((i + 1)); done
grep -q ready "$W/prund.log" || { cat "$W/prund.log" >&2; kill $d; exit 1; }
PCC_ANSWERS=$out PCC_MODE=record PCC_SOCK=$W/sock sh "$here/ksh93.sh" "$W/ksh93" "$PCC_STORE" "$(cat "$B/ksh93-probes/shopts")"
rc=$?
kill $d
grep -c '^ok ' "$W/prund.log" | sed 's/$/ probe runs recorded on the box/'
if [ $mode = verify ] && [ $rc = 0 ]; then
	python3 -I "$here/probeans.py" diff "$A" "$out"; rc=$?
fi
# kept when it failed, for its logs
if [ $rc = 0 ]; then
	case $W in "${TMPDIR:-/tmp}"/ksh93-record.*) rm -rf -- "${W:?}";; esac
else
	echo "ksh93-record.sh: the build and its logs are in $W" >&2
fi
exit $rc
