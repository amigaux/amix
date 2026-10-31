# amix-base: the base system this project writes itself (P-36).
NAME=amix-base
PKG=amxbase
VERSION=1.0
PKGREV=9
SUMMARY="Amix base system: boot helpers, the network set-up, the base config files"
DESC="rc.subr and /etc/rc.conf, ifup/ifdown over /etc/inet/interfaces, dlpi-mac, the DHCP hook, the new inetinit, the device-node and swap boot steps, man, and the stock /etc base files as conffiles"
CATEGORY=system
SET=base
LICENSE=MIT
STYLE=hooks
TOOLCHAIN=gcc14
ESSENTIAL=yes
SYSTEM_PATHS="/usr/amix/bin /usr/lib/amix /usr/lib/inet /usr/sbin/ifup /usr/sbin/ifdown /usr/sbin/dlpi-mac"
# /etc/profile and /etc/inittab are built in stage from the stock files:
# profile plus etc/profile.add, inittab plus the dlm line (etc/mkinittab.sh)
STOCK_ETC="/etc/TIMEZONE /etc/nodename /etc/inet/hosts /etc/default/login /etc/inet/strcf"
CONFFILES="/etc/inittab /etc/TIMEZONE /etc/nodename /etc/inet/hosts /etc/default/login /etc/profile /etc/inet/strcf /etc/inet/network-config /etc/inet/rc.inet"
