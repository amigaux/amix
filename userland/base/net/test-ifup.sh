#!/bin/sh
# test-ifup.sh -- host tests of ifup, ifdown and dhcpc-hook against fake
# ifconfig, slink, route, dlpi-mac, dhcpc and uname, in a scratch tree.
#
#   sh userland/base/net/test-ifup.sh [shell [awk]]   (default sh, awk)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
AWK=${2:-awk}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-ifup.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { [ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"; }
expect() { case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac; }
refuse() { case "$3" in *"$2"*) bad "$1: unwanted [$2] in [$3]" ;; *) ok ;; esac; }

B=$T/bin
mkdir -p "$B" "$T/st" "$T/link.d" "$T/lib" "$T/var/dhcpc" "$T/dev"
# the awk asked for, by its full path (a bare name would find this stub)
set -- $AWK
a=$(command -v "$1"); shift
printf '#!/bin/sh\nexec %s %s "$@"\n' "$a" "$*" > "$B/awk"
set --
# ifconfig: <if> shows the state (exit 1 when not linked); <if> <a> netmask
# <m> up -trailers sets it; <if> down
cat > "$B/ifconfig" <<EOF
#!/bin/sh
S=$T/st
echo "ifconfig \$*" >> \$S/calls
i=\$1
[ -f \$S/linked.\$i ] || { echo "ifconfig: \$i: no such interface" >&2; exit 1; }
case "\$2" in
"")
	if [ -f \$S/if.\$i ]; then
		set -- \`cat \$S/if.\$i\`
		echo "\$i: flags=23<\$3,BROADCAST,NOTRAILERS>"
		echo "	inet \$1 netmask \`echo \$2 | awk -F. '{ printf "%02x%02x%02x%02x", \$1, \$2, \$3, \$4 }'\` broadcast 0.0.0.0"
	else
		echo "\$i: flags=0<>"
	fi
	;;
down)
	[ -f \$S/if.\$i ] && set -- \`cat \$S/if.\$i\` && echo "\$1 \$2 DOWN" > \$S/if.\$i
	;;
*)
	echo "\$2 \$4 UP" > \$S/if.\$i
	;;
esac
exit 0
EOF
cat > "$B/slink" <<EOF
#!/bin/sh
echo "slink \$*" >> $T/st/calls
if [ "\${1:-}" = addaen ]; then
	if [ -f $T/st/slinkfail ]; then rm -f $T/st/slinkfail; exit 1; fi
	: > $T/st/linked.\$3
fi
exit 0
EOF
cat > "$B/route" <<EOF
#!/bin/sh
echo "route \$*" >> $T/st/calls
case "\$1" in
add) [ -f $T/st/route ] && exit 1; echo "\$3" > $T/st/route ;;
delete) [ "\`cat $T/st/route 2>/dev/null\`" = "\$3" ] || exit 1; rm -f $T/st/route ;;
esac
exit 0
EOF
# dlpi-mac: the MAC of a node from st/mac.<node name>, else "no such interface"
cat > "$B/dlpi-mac" <<EOF
#!/bin/sh
n=\`basename "\$1"\`
[ -f $T/st/mac.\$n ] || exit 1
cat $T/st/mac.\$n
EOF
# dhcpc -b <secs> <if>: status from st/dhcpc.rc; on 0 it calls the hook
cat > "$B/dhcpc" <<EOF
#!/bin/sh
echo "dhcpc \$*" >> $T/st/calls
r=\`cat $T/st/dhcpc.rc 2>/dev/null || echo 2\`
if [ "\$1" = -x ]; then
	rm -f $T/var/dhcpc/\$2.pid
	DHCP_ROUTER=192.0.2.1 $SH $here/dhcpc-hook \$2 RELEASE
	exit 0
fi
if [ \$r = 0 ]; then
	: > $T/var/dhcpc/\$3.pid
	DHCP_ADDR=192.0.2.77 DHCP_MASK=255.255.255.0 DHCP_ROUTER=192.0.2.1 DHCP_DNS="192.0.2.53 192.0.2.14" \\
	    DHCP_HOSTNAME=leasename $SH $here/dhcpc-hook \$3 BOUND
fi
exit \$r
EOF
cat > "$B/uname" <<EOF
#!/bin/sh
case "\$1" in
-n) cat $T/st/nodename ;;
-S) echo "\$2" > $T/st/nodename ;;
esac
EOF
printf '#!/bin/sh\necho "mknod $*" >> %s/st/calls\n: > "$1"\n' "$T" > "$B/mknod"
printf '#!/bin/sh\n:\n' > "$B/domainname"
chmod +x "$B/"*

printf 'aen\t%s/dev/aen\t0\t18\ttrue\n' "$T" > "$T/link.d/aen"
printf 'zen %s/dev/zen 0 51 false   # no such board\n' "$T" > "$T/link.d/z3660eth"
echo "00:80:10:ff:ff:01" > "$T/st/mac.aen0"
echo "00:80:10:ff:ff:02" > "$T/st/mac.aen1"
: > "$T/lib/libsockdns.so"; : > "$T/lib/libsocket.so"
printf 'tcp DNS\n' > "$T/netconfig.DNS"; printf 'tcp plain\n' > "$T/netconfig"
echo "example.com" > "$T/domain"

reset() {
	rm -f "$T/st/"if.* "$T/st/"linked.* "$T/st/route" "$T/st/calls" "$T/st/dhcpc.rc" "$T/st/slinkfail" \
	    "$T/primary" "$T/var/ifup.primary" "$T/var/dhcpc/"*
	echo "oldname" > "$T/st/nodename"
	printf '# hosts\n127.0.0.1\tlocalhost\n192.0.2.99\toldname oldname.example.com\n192.0.2.5\tother\n' > "$T/hosts"
	rm -f "$T/resolv.conf" "$T/rc.log"
}
run() { # run <cmd> <args...>: one of the three, with the test tree
	c=$1
	shift
	env PATH="$B:$PATH" RC_SUBR="$here/../rc/rc.subr" IF_SUBR="$here/ifup.subr" \
	    RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" RC_KBOOTSET="$T/none" \
	    IF_CONF="$T/interfaces" IF_LINKD="$T/link.d" IF_HOSTS="$T/hosts" IF_NODENAME="$T/nodename" \
	    IF_RESOLV="$T/resolv.conf" IF_NETCONFIG="$T/netconfig" IF_DOMAINF="$T/domain" IF_LIB="$T/lib" \
	    IF_STATE="$T/var" IF_LEASES="$T/var/dhcpc" IFCONFIG="$B/ifconfig" ROUTE="$B/route" \
	    SLINK="$B/slink" DLPIMAC="$B/dlpi-mac" DHCPC="${DHCPC_PATH:-$B/dhcpc}" \
	    $SH "$here/$c" "$@" 2>&1
}
echo "ifup_dhcpwait=5" > "$T/rc.conf"

# --- static on two cards, by name and by MAC
cat > "$T/interfaces" <<'EOF'
aen0               static  192.0.2.38/24  gw 192.0.2.1
00:80:10:ff:ff:02  static  198.51.100.9/25  gw 198.51.100.1  name tower
*                  off
dns     192.0.2.14 192.0.2.23
domain  example.com
EOF
reset
o=$(run ifup -a); r=$?
same "ifup -a status" 0 "$r"
expect "aen0 up" "ifup: aen0: 192.0.2.38 netmask 255.255.255.0 up" "$o"
expect "aen1 by MAC" "ifup: aen1: 198.51.100.9 netmask 255.255.255.128 up" "$o"
expect "route from the first" "ifup: aen0: default route 192.0.2.1" "$o"
same "one default route" "192.0.2.1" "$(cat "$T/st/route")"
same "primary" aen0 "$(cat "$T/var/ifup.primary")"
expect "slink once each" "slink addaen $T/dev/aen0 aen0" "$(cat "$T/st/calls")"
same "slink calls" 2 "$(grep -c '^slink addaen' "$T/st/calls")"
refuse "absent driver skipped" "zen" "$(cat "$T/st/calls")"
same "host name from the row" tower "$(cat "$T/st/nodename")"
same "nodename file" tower "$(cat "$T/nodename")"
expect "hosts own line" "192.0.2.38	oldname oldname.example.com" "$(cat "$T/hosts")"
same "old line gone" "" "$(grep '^192.0.2.99' "$T/hosts")"
expect "other lines kept" "192.0.2.5	other" "$(cat "$T/hosts")"
same "resolv.conf" "nameserver 192.0.2.14
nameserver 192.0.2.23" "$(cat "$T/resolv.conf")"
same "libsocket is libsockdns" "$(ls -i "$T/lib/libsockdns.so" | awk '{print $1}')" "$(ls -i "$T/lib/libsocket.so" | awk '{print $1}')"
same "netconfig" "tcp DNS" "$(cat "$T/netconfig")"
same "domain emptied" "" "$(cat "$T/domain")"
expect "logged" "ifup: aen0: 192.0.2.38 netmask 255.255.255.0 up" "$(cat "$T/rc.log")"

# --- the same again changes nothing
: > "$T/st/calls"
o=$(run ifup -a)
expect "rerun: already up" "aen0: 192.0.2.38 netmask 255.255.255.0 already up" "$o"
refuse "rerun: no slink" "slink addaen" "$(cat "$T/st/calls")"
refuse "rerun: no address set" "ifconfig aen0 192.0.2.38" "$(cat "$T/st/calls")"
refuse "rerun: dns untouched" "dns:" "$o"

# --- -n says, does nothing
reset
o=$(run ifup -n)
expect "-n aen0" "ifup: aen0 (00:80:10:ff:ff:01): static 192.0.2.38 255.255.255.0 gw 192.0.2.1 name - (row aen0)" "$o"
expect "-n aen1" "ifup: aen1 (00:80:10:ff:ff:02): static 198.51.100.9" "$o"
same "-n: nothing run" "" "$(grep -v '^mknod' "$T/st/calls" 2>/dev/null)"

# --- one interface by name; an unknown one
reset
o=$(run ifup aen1); r=$?
same "ifup aen1" 0 "$r"
expect "only aen1" "aen1: 198.51.100.9" "$o"
refuse "not aen0" "aen0:" "$o"
o=$(run ifup aen5 hya0); r=$?
same "unknown: status" 1 "$r"
expect "unknown unit" "aen5: no such interface here" "$o"
expect "unknown driver" "hya0: no such interface here" "$o"

# --- slink fails once: one retry after the base plumbing
reset
: > "$T/st/slinkfail"
o=$(run ifup aen0)
expect "retried" "aen0: 192.0.2.38" "$o"
same "base slink between" "slink addaen $T/dev/aen0 aen0
slink
slink addaen $T/dev/aen0 aen0" "$(grep '^slink' "$T/st/calls" | sed 's/ *$//')"

# --- dhcp: lease, no lease, no dhcpc, fallback
cat > "$T/interfaces" <<'EOF'
aen0   dhcp   192.0.2.40/24  gw 192.0.2.1
aen1   dhcp
dns    192.0.2.14
EOF
reset
echo 0 > "$T/st/dhcpc.rc"
o=$(run ifup aen0)
expect "dhcpc bounded" "dhcpc -b 5 aen0" "$(cat "$T/st/calls")"
expect "lease applied" "aen0: 192.0.2.77 netmask 255.255.255.0 up" "$o"
expect "lease said" "aen0: DHCP lease applied" "$o"
same "dns merged" "nameserver 192.0.2.14
nameserver 192.0.2.53" "$(cat "$T/resolv.conf")"
same "no hostname from the lease without hostname dhcp" oldname "$(cat "$T/st/nodename")"
reset
echo 2 > "$T/st/dhcpc.rc"
o=$(run ifup aen0 aen1); r=$?
expect "no lease: fallback" "aen0: static fallback 192.0.2.40" "$o"
expect "fallback applied" "aen0: 192.0.2.40 netmask 255.255.255.0 up" "$o"
expect "no fallback: down" "aen1: no static fallback; left down" "$o"
same "status with one down" 1 "$r"
reset
o=$(DHCPC_PATH="$T/nodhcpc" run ifup aen0)
expect "no dhcpc" "aen0: dhcp, but $T/nodhcpc is not installed" "$o"
expect "no dhcpc: fallback" "aen0: 192.0.2.40 netmask" "$o"

# --- the hook: hostname dhcp, dns static, EXPIRE, RELEASE, RENEW
cat > "$T/interfaces" <<'EOF'
aen0   dhcp   192.0.2.40/24  gw 192.0.2.1
aen1   dhcp   name rowname
dns    static 192.0.2.14
hostname dhcp
EOF
reset
: > "$T/st/linked.aen0"; : > "$T/st/linked.aen1"
o=$(DHCP_ADDR=192.0.2.77 DHCP_MASK=255.255.255.0 DHCP_ROUTER=192.0.2.1 DHCP_DNS=192.0.2.53 \
    DHCP_HOSTNAME=leasename run dhcpc-hook aen0 BOUND)
expect "hook BOUND" "aen0: 192.0.2.77 netmask 255.255.255.0 up" "$o"
same "hostname dhcp" leasename "$(cat "$T/st/nodename")"
same "dns static: no lease servers" "nameserver 192.0.2.14" "$(cat "$T/resolv.conf")"
o=$(DHCP_ADDR=192.0.2.78 DHCP_MASK=255.255.255.0 DHCP_HOSTNAME=leasename run dhcpc-hook aen1 BOUND)
same "row name beats the lease" rowname "$(cat "$T/st/nodename")"
o=$(DHCP_ADDR=192.0.2.77 DHCP_MASK=255.255.255.0 DHCP_ROUTER=192.0.2.1 run dhcpc-hook aen0 RENEW)
refuse "RENEW, same address: no ifconfig" "netmask 255.255.255.0 up" "$o"
o=$(DHCP_ADDR=192.0.2.79 DHCP_OLD_ADDR=192.0.2.77 DHCP_MASK=255.255.255.0 DHCP_ROUTER=192.0.2.1 run dhcpc-hook aen0 REBIND)
expect "REBIND, new address" "aen0: 192.0.2.79 netmask 255.255.255.0 up" "$o"
o=$(DHCP_ROUTER=192.0.2.1 run dhcpc-hook aen0 EXPIRE)
expect "EXPIRE: down" "aen0: down" "$o"
expect "EXPIRE: route off" "aen0: default route 192.0.2.1 removed" "$o"
expect "EXPIRE: fallback" "aen0: lease ended; static fallback 192.0.2.40" "$o"
expect "EXPIRE: fallback up" "aen0: 192.0.2.40 netmask 255.255.255.0 up" "$o"
o=$(DHCP_ROUTER=192.0.2.1 run dhcpc-hook aen1 RELEASE)
expect "RELEASE: down" "aen1: down" "$o"
o=$(run dhcpc-hook aen0 BOGUS); r=$?
same "unknown reason" 1 "$r"

# --- ifdown: static, and a lease released through dhcpc
cat > "$T/interfaces" <<'EOF'
aen0   static 192.0.2.38/24 gw 192.0.2.1
aen1   dhcp
EOF
reset
run ifup aen0 > /dev/null
o=$(run ifdown aen0)
expect "ifdown static" "aen0: down" "$o"
same "route removed" "" "$(cat "$T/st/route" 2>/dev/null)"
expect "interface down" "DOWN" "$(cat "$T/st/if.aen0")"
: > "$T/st/linked.aen1"; : > "$T/var/dhcpc/aen1.pid"
o=$(run ifdown aen1)
expect "ifdown via dhcpc -x" "dhcpc -x aen1" "$(cat "$T/st/calls")"

# --- a bad row: off, never "*"
printf 'aen0 statik 192.0.2.38/24\n* static 192.0.2.50/24\n' > "$T/interfaces"
reset
o=$(run ifup aen0)
expect "bad row reported" "ifup: interfaces:1: aen0: the mode must be dhcp, static or off" "$o"
expect "bad row: off" "ifup: aen0 (00:80:10:ff:ff:01): off" "$o"
refuse "not the * address" "192.0.2.50" "$o"

# --- link.d without the major column: the registry's, or no node made
mkdir -p "$T/link2.d"
printf 'aen %s/dev/aen 0 true\n' "$T" > "$T/link2.d/aen"
printf '#!/bin/sh\n[ "$1 $2" = "major aen" ] && echo "c 18" && exit 0\nexit 1\n' > "$B/kb18"
chmod +x "$B/kb18"
links() { # links <kbootset>: if_links over link2.d
	: > "$T/st/calls"; : > "$T/rc.log"
	env PATH="$B:$PATH" RC_LOG="$T/rc.log" RC_KBOOTSET="$1" IF_LINKD="$T/link2.d" DLPIMAC="$B/dlpi-mac" \
	    $SH -c ". '$here/../rc/rc.subr'; . '$here/ifup.subr'; if_links" 2>&1
}
o=$(links "$B/kb18")
expect "no major column: the unit found" "aen0 $T/dev/aen0 00:80:10:ff:ff:01" "$o"
expect "no major column: the registry's major" "mknod $T/dev/aen0 c 18 0" "$(cat "$T/st/calls")"
refuse "no major column: no packaging error" "packaging error" "$(cat "$T/rc.log")"
o=$(links "$T/none")
expect "no major, no registry: the unit still probed" "aen0 $T/dev/aen0 00:80:10:ff:ff:01" "$o"
refuse "no major, no registry: no mknod" "mknod" "$(cat "$T/st/calls")"
expect "no major, no registry: said" "cannot make $T/dev/aen0: the registry gives aen no major" "$(cat "$T/rc.log")"

echo "test-ifup: $pass passed, $fail failed ($SH, $AWK)"
[ "$fail" -eq 0 ]
