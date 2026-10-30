#!/bin/sh
# bringup.sh -- manual one-shot bring-up of the Z3660 native ethernet on real HW.
# Run ON the box (single-user is fine).  AMIX is SVR4.0: use slink, NOT `ifconfig plumb`.
# An EXAMPLE: the address is the box's own, from /etc/default/zen (the file S99zen
# reads; its header shows the form) or the command line:
#   sh bringup.sh [address [gateway [netmask]]]

ZEN_ADDR= ZEN_NETMASK=255.255.255.0 ZEN_GATEWAY=
[ -r /etc/default/zen ] && . /etc/default/zen
IP=${1:-$ZEN_ADDR}
GW=${2:-$ZEN_GATEWAY}
MASK=${3:-$ZEN_NETMASK}
MAJOR=51
if [ -z "$IP" ]; then
	echo "usage: sh bringup.sh address [gateway [netmask]]  (or set ZEN_ADDR in /etc/default/zen)" >&2
	exit 2
fi

# 1. device node (persists on the on-disk root -- only needed once)
[ -c /dev/zen0 ] || mknod /dev/zen0 c $MAJOR 0

# 2. presence check (driver autoconfigs the Z3660 on first open)
if /usr/amiga/bin/zen -S; then
	echo "zen0: Z3660 ethernet present"
else
	echo "zen0: NOT present (open ENXIO) -- aborting" >&2
	exit 1
fi

# 3. ensure the base inet streams are linked, then link the driver under IP+ARP
/usr/sbin/slink
/usr/sbin/slink addaen /dev/zen0 zen0

# 4. address + bring up (no trailers), default route (trailing 1 = metric, mandatory)
/usr/sbin/ifconfig zen0 $IP netmask $MASK up -trailers
[ -n "$GW" ] && /usr/sbin/route add default $GW 1

/usr/sbin/ifconfig zen0
echo
[ -n "$GW" ] && echo "now try:   ping $GW        (ARP must resolve first -- watch 'zen' counters)"
echo "status:    /usr/amiga/bin/zen"
