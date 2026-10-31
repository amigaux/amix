#!/bin/sh
# rcscripts.sh -- the kbootset package's boot scripts (kbootset/rc,
# C2-4 sections 9 and 12): kbnamelist and kbmarkgood with a stand-in
# kbootset.  Covered: only "start" runs anything; without rc.subr each
# runs its one call, output on the console, exit 0 whatever kbootset
# says; no kbootset, nothing; with amix-base's rc.subr (read from
# userland/base when the tree has it) the status goes to the log, "=no"
# in rc.conf turns each off, kbmarkgood saying so on the console, and
# "=yes" or no line runs it.  The 1991 sh's limits (C3-5 1.3) are grepped.
# Run from the repository root.
set -e
B=${B:-build}
T=$B/rcscripts
rm -rf $T && mkdir -p $T
T=$(cd $T && pwd)
SUBR=${RC_SUBR_SRC:-../../userland/base/rc/rc.subr}
# a stand-in kbootset: records its arguments, says a line, exits $KBRC
cat > $T/kbootset <<'K'
#!/bin/sh
echo "$*" >> "$KBCALLS"
echo "kbootset: $* said"
exit ${KBRC:-0}
K
chmod 0755 $T/kbootset
export KBCALLS=$T/calls RC_CONSOLE=$T/console RC_KBOOTSET=$T/kbootset
export RC_CONF=$T/rc.conf RC_LOG=$T/rc.log RC_BGLOG=$T/rclog RC_RUN=$T

# run SCRIPT ARG: one run from a clean slate; fails if the script does not exit 0
run() {
	rm -f $T/calls $T/console $T/rc.log
	sh kbootset/rc/$1 $2
}
want() {
	[ "$(cat $T/calls 2>/dev/null)" = "$1" ] || { echo "rcscripts: $2: calls '$(cat $T/calls 2>/dev/null)', want '$1'" >&2; exit 1; }
}

for s in kbnamelist kbmarkgood; do
	case $s in kbnamelist) c=namelist ;; kbmarkgood) c=mark-good ;; esac
	# not start: nothing
	export RC_SUBR=$T/none
	run $s stop; want "" "$s stop"
	run $s; want "" "$s without an argument"
	# without rc.subr: the call, its line on the console, 0 even on status 3
	KBRC=3 run $s start; want "$c" "$s start"
	grep -qx "kbootset: $c said" $T/console
	[ ! -f $T/rc.log ]
	# no kbootset: nothing, 0
	RC_KBOOTSET=$T/nosuch run $s start; want "" "$s without kbootset"
	if [ -r "$SUBR" ]; then
		export RC_SUBR=$SUBR
		rm -f $T/rc.conf
		KBRC=3 run $s start; want "$c" "$s with rc.subr, no rc.conf"
		grep -q " $s: kbootset $c, status 3\$" $T/rc.log
		echo "$s=yes" > $T/rc.conf
		run $s start; want "$c" "$s=yes"
		grep -q " $s: kbootset $c, status 0\$" $T/rc.log
		echo "$s=no" > $T/rc.conf
		run $s start; want "" "$s=no"
		case $s in
		kbmarkgood)
			grep -qx "kbmarkgood: off (kbmarkgood=no in /etc/rc.conf): a trial generation is not kept" $T/console
			grep -q " kbmarkgood: off in rc.conf; nothing marked\$" $T/rc.log ;;
		*)	[ ! -s $T/console ] ;;
		esac
		rm -f $T/rc.conf
	fi
	# the 1991 sh: no $(...), no ${...#...}-style expansions, no printf, no local
	if grep -n '\$(\|\${[A-Za-z_]*[#%]\|printf\|local ' kbootset/rc/$s; then
		echo "rcscripts: $s uses what the 1991 sh lacks" >&2; exit 1
	fi
done
if [ -r "$SUBR" ]; then
	echo "rcscripts: kbnamelist and kbmarkgood, with and without rc.subr, ok"
else
	echo "rcscripts: kbnamelist and kbmarkgood without rc.subr ok ($SUBR not here: the rc.conf half skipped)"
fi
