#!/bin/sh
# test-ifparse.sh -- host tests of ifup.subr's interfaces parser.
#
#   sh userland/base/net/test-ifparse.sh [shell [awk]]   (default sh, awk)
#
# The box's awk is the 1988 one (nawk); run this with each awk the host has
# (nawk, mawk, gawk --posix, busybox awk) to keep the program portable.
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
AWK=${2:-awk}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-ifparse.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}

mkdir -p "$T/bin"
printf '#!/bin/sh\nexec %s "$@"\n' "$AWK" > "$T/bin/awk"
chmod +x "$T/bin/awk"

# run <file> <shell commands>: ifup.subr sourced, IF_CONF=<file>
run() {
	f=$1
	shift
	env IF_CONF="$f" PATH="$T/bin:$PATH" $SH -c ". '$here/ifup.subr'; $*" 2>&1
}

cat > "$T/good" <<'EOF'
# /etc/inet/interfaces -- every network interface, one line each.
zen0           dhcp
aen0           static  192.0.2.38/24  gw 192.0.2.1
00:80:51:01:02:04  static  192.0.2.39/24  gw 192.0.2.1  name amix-tower
0:80:10:FF:ff:A    static  100.65.2.3                     # no prefix: class A
hya0	dhcp	198.51.100.7/25	gw 198.51.100.1		# fallback address
eth9           off     192.0.2.50/24     # an off row may keep its address
*              off
# global
dns     192.0.2.14 192.0.2.23   # static nameservers
dns     192.0.2.23 192.0.2.53
domain  example.com
EOF
G="$T/good"

same "dhcp row" "dhcp - - - - zen0" "$(run $G 'if_select zen0 -')"
same "static row" "static 192.0.2.38 255.255.255.0 192.0.2.1 - aen0" "$(run $G 'if_select aen0 -')"
same "MAC row beats the name row" "static 192.0.2.39 255.255.255.0 192.0.2.1 amix-tower 00:80:51:01:02:04" \
    "$(run $G 'if_select aen0 00:80:51:01:02:04')"
same "MAC compared case-blind" "static 192.0.2.39 255.255.255.0 192.0.2.1 amix-tower 00:80:51:01:02:04" \
    "$(run $G 'if_select zen0 00:80:51:01:02:04')"
same "MAC row with short octets" "static 100.65.2.3 255.0.0.0 - - 00:80:10:ff:ff:0a" \
    "$(run $G 'if_select aen1 00:80:10:ff:ff:0a')"
same "short octets in the asked MAC" "static 100.65.2.3 255.0.0.0 - - 00:80:10:ff:ff:0a" \
    "$(run $G 'if_select aen1 0:80:10:ff:ff:a')"
same "a MAC not listed: the name row" "dhcp - - - - zen0" "$(run $G 'if_select zen0 00:11:22:33:44:55')"
same "dhcp with a fallback address" "dhcp 198.51.100.7 255.255.255.128 198.51.100.1 - hya0" "$(run $G 'if_select hya0 -')"
same "off row" "off 192.0.2.50 255.255.255.0 - - eth9" "$(run $G 'if_select eth9 -')"
same "no row: the * row" "off - - - - *" "$(run $G 'if_select aen3 -')"
same "no errors" "0" "$(run $G 'if_errors; echo $?')"
same "dns merged, in order, once each" "192.0.2.14 192.0.2.23 192.0.2.53" "$(run $G 'if_dns')"
same "dns not static" 1 "$(run $G 'if_dns_static; echo $?')"
same "domain" "example.com" "$(run $G 'if_domain')"
same "hostname not from dhcp" 1 "$(run $G 'if_hostname_dhcp; echo $?')"

# no "*" row, no file
printf 'aen0 static 192.0.2.38/24\ndns static 192.0.2.14\nhostname dhcp\n' > "$T/nostar"
same "no row and no *: off" "off - - - - -" "$(run $T/nostar 'if_select zen0 -')"
same "dns static" 0 "$(run $T/nostar 'if_dns_static; echo $?')"
same "dns static keeps the address" "192.0.2.14" "$(run $T/nostar 'if_dns')"
same "hostname dhcp" 0 "$(run $T/nostar 'if_hostname_dhcp; echo $?')"
same "no file: off" "off - - - - -" "$(run $T/none 'if_select aen0 -')"
same "no file: no errors" 0 "$(run $T/none 'if_errors; echo $?')"
same "no file: no dns" "" "$(run $T/none 'if_dns')"
same "empty file: off" "off - - - - -" "$(run /dev/null 'if_select aen0 -')"

# classful defaults and edge prefixes
printf 'a0 static 128.66.5.1\nb0 static 203.0.113.5\nc0 static 100.64.0.1/30\nd0 static 100.64.0.5/9\n' > "$T/class"
same "class B default" "static 128.66.5.1 255.255.0.0 - - a0" "$(run $T/class 'if_select a0 -')"
same "class C default" "static 203.0.113.5 255.255.255.0 - - b0" "$(run $T/class 'if_select b0 -')"
same "/30" "static 100.64.0.1 255.255.255.252 - - c0" "$(run $T/class 'if_select c0 -')"
same "/9" "static 100.64.0.5 255.128.0.0 - - d0" "$(run $T/class 'if_select d0 -')"

# mistakes: each reported with its line, and the interface off (not "*")
cat > "$T/bad" <<'EOF'
aen0 static
zen0 dhcp gw 192.0.2.1
hya0 statik 192.0.2.5/24
aen1 static 192.0.2.300/24
aen2 static 192.0.2.0/24
aen3 static 192.0.2.255/24
aen4 static 192.0.2.4/24 gw 192.0.3.1
aen5 static 192.0.2.5/24 name bad_name
aen6 static 192.0.2.6/24 mtu 1500
aen7 static 192.0.2.7/24 gw
aen8 static 192.0.2.8/31
aen9 static 127.0.0.2
zen1 static 224.0.0.1
00:80:51:01:02 static 192.0.2.9/24
Eth0 static 192.0.2.10/24
aen0 dhcp
zen2
dns
dns 192.0.2.999
domain a b
domain bad..name
hostname static
zen3 static 192.0.2.11/24 gw 192.0.2.11
zen4 static 192.0.2.12/24 gw 192.0.2.1 gw 192.0.2.2
*    dhcp
EOF
e=$(run $T/bad 'if_errors')
same "errors status" 1 "$(run $T/bad 'if_errors >/dev/null; echo $?')"
expect "static needs an address" "interfaces:1: aen0: static needs an address" "$e"
expect "gw without an address" "interfaces:2: zen0: gw needs an address on the same row" "$e"
expect "bad mode" "interfaces:3: hya0: the mode must be dhcp, static or off" "$e"
expect "bad octet" "interfaces:4: aen1: \"192.0.2.300/24\" is not an address" "$e"
expect "network address" "interfaces:5: aen2: 192.0.2.0/24 is the network or broadcast address" "$e"
expect "broadcast address" "interfaces:6: aen3: 192.0.2.255/24 is the network or broadcast address" "$e"
expect "gw off the network" "interfaces:7: aen4: gw 192.0.3.1 is not on 192.0.2.4/24" "$e"
expect "bad name" "interfaces:8: aen5: \"bad_name\" is not a host name" "$e"
expect "unknown word" "interfaces:9: aen6: \"mtu\" is not gw or name" "$e"
expect "gw without a value" "interfaces:10: aen7: \"gw\" needs a value after it" "$e"
expect "/31" "interfaces:11: aen8: the prefix length must be 1 to 30" "$e"
expect "loopback" "interfaces:12: aen9: 127.0.0.2 cannot be an interface address" "$e"
expect "multicast" "interfaces:13: zen1: 224.0.0.1 cannot be an interface address" "$e"
expect "five-octet MAC" "interfaces:14: \"00:80:51:01:02\" is not a MAC address" "$e"
expect "upper-case name" "interfaces:15: \"Eth0\" is not an interface name" "$e"
expect "duplicate row" "interfaces:16: a second row for aen0 (the first is line 1)" "$e"
expect "no mode" "interfaces:17: \"zen2\" has no mode" "$e"
expect "empty dns" "interfaces:18: dns needs at least one address" "$e"
expect "bad dns" "interfaces:19: dns: \"192.0.2.999\" is not an address" "$e"
expect "domain two words" "interfaces:20: domain takes one domain name" "$e"
expect "bad domain" "interfaces:21: domain takes one domain name" "$e"
expect "hostname static" "interfaces:22: the only hostname line" "$e"
expect "gw is the address" "interfaces:23: zen3: gw is the interface address itself" "$e"
expect "second gw" "interfaces:24: zen4: a second gw" "$e"
same "one line per mistake" 24 "$(echo "$e" | wc -l | tr -d ' ')"
same "bad row: off, not *" "off - - - - aen0" "$(run $T/bad 'if_select aen0 -')"
same "bad mode: off" "off - - - - hya0" "$(run $T/bad 'if_select hya0 -')"
same "bad row with a MAC asked: off" "off - - - - aen4" "$(run $T/bad 'if_select aen4 00:00:00:00:00:01')"
same "unlisted: *" "dhcp - - - - *" "$(run $T/bad 'if_select aen99 -')"
same "bad dns line adds nothing" "" "$(run $T/bad 'if_dns')"

echo "test-ifparse: $pass passed, $fail failed ($SH, $AWK)"
[ "$fail" -eq 0 ]
