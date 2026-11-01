#!/bin/sh
# mkgated.sh -- a stock boot script behind amix-base's rc.conf gate.
#
#   sh userland/base/rc/mkgated.sh <amix-system checkout> <manifest> <name> <out>
#
# <name> is rpc, lp, smtpd or news. The stock bytes are Commodore's and live
# only in amix-system (etc/init.d/<name>); they are checked against their
# sha256 in system/MANIFEST.sha256 first. The output is the gate, then the
# stock script, edited only where a daemon is gated:
#
#   rpc    rpcbind as before; rpc.rwalld, rpc.rusersd and rpc.sprayd only
#          with rc.conf's rwalld=yes, rusersd=yes, sprayd=yes
#   lp     started (lpsched, which starts lpNet) only with lpsched=yes;
#          stopped as before
#   smtpd  started only with smtpd=yes
#   news   the news start as before, mthreads only with mthreads=yes
#
# A missing line is no. The file is installed at the path stock records as
# the script, and its stock S and K links are made to it again.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
[ $# -eq 4 ] || { echo "usage: mkgated.sh <amix-system> <manifest> rpc|lp|smtpd|news <out>" >&2; exit 2; }
name=$3
out=$4
case "$name" in
rpc|lp|smtpd|news) ;;
*) echo "mkgated.sh: $name: not rpc, lp, smtpd or news" >&2; exit 2 ;;
esac
stock="$1/etc/init.d/$name"
want=$(awk -v p="etc/init.d/$name" '$2 == p { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mkgated.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}

# the gate: rc.subr when /usr is there, else every service is off
{
	cat <<'EOF'
# amix-base: the stock script below, behind /etc/rc.conf (rc.conf(4)): its
# service starts only when rc.conf turns it on.
RC_SUBR=${RC_SUBR:-/usr/lib/amix/rc.subr}
if [ -r "$RC_SUBR" ]
then
	. "$RC_SUBR"
else
	rc_enabled() { return 1; }
fi
EOF
	case "$name" in
	smtpd) echo 'rc_enabled smtpd || exit 0' ;;
	lp) echo '[ "$1" != start ] || rc_enabled lpsched || exit 0' ;;
	esac
} > "$out"

# the stock script, and the one edit each for rpc and news, each made once
case "$name" in
rpc)
	sed -e 's;^\(		if \)\(\[ -x /usr/lib/netsvc/\(rwall\|rusers\|spray\)/rpc\.\(rwalld\|rusersd\|sprayd\) \]\)$;\1rc_enabled \4 \&\& \2;' "$stock" >> "$out"
	n=3 pat='if rc_enabled [rs][a-z]*d && \[ -x /usr/lib/netsvc/'
	;;
news)
	sed -e 's;^\(	if \)\(\[ -x /usr/public/lib/newsbin/trn/mthreads \]\)$;\1rc_enabled mthreads \&\& \2;' "$stock" >> "$out"
	n=1 pat='if rc_enabled mthreads && \[ -x '
	;;
*)
	cat "$stock" >> "$out"
	n=0 pat=
	;;
esac
if [ "$n" -gt 0 ]
then
	c=$(grep -c "$pat" "$out" || true)
	[ "$c" -eq "$n" ] || {
		echo "mkgated.sh: $name: $c of the $n gated lines made" >&2
		rm -f "${out:?}"
		exit 1
	}
fi
