# dhcp-client: dhcpc, the DHCP client.
NAME=dhcp-client
PKG=dhcpc
VERSION=1.0
PKGREV=10   # -10: gcc14-cross-amix 9d13dcd (release-1.1): fold-mem-offsets off; 4 functions lose correct folds
SUMMARY="DHCP client for the Amix base system"
DESC="dhcpc: gets and keeps an address over DLPI and UDP, applied through amix-base's dhcpc-hook"
CATEGORY=network
SET=base
LICENSE=MIT
STYLE=hooks
TOOLCHAIN=gcc14
DEPENDS="amix-base"
SYSTEM_PATHS="/usr/sbin/dhcpc"
