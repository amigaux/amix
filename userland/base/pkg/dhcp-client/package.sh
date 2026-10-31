# dhcp-client: dhcpc, the DHCP client (P-36 D-N14 to D-N18).
NAME=dhcp-client
PKG=dhcpc
VERSION=1.0
PKGREV=2
SUMMARY="DHCP client for the Amix base system"
DESC="dhcpc: gets and keeps an address over DLPI and UDP, applied through amix-base's dhcpc-hook"
CATEGORY=network
SET=base
LICENSE=MIT
STYLE=hooks
TOOLCHAIN=gcc14
DEPENDS="amix-base"
SYSTEM_PATHS="/usr/sbin/dhcpc"
