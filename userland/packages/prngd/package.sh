# package.sh -- prngd 0.9.29 (P-31 sec 10.9); assignments only.
NAME=prngd
PKG=prngd
VERSION=0.9.29
PKGREV=1
SUMMARY="prngd 0.9.29 entropy daemon"
DESC="PRNGD 0.9.29, the pseudo-random number gathering daemon: an EGD-protocol socket (/var/run/egd-pool) for ssh/TLS on a box with no /dev/random, fed by sampling system commands. Always give it a socket argument. Not started by the package: see /opt/amix/etc/init.d/prngd. Installs /opt/amix/sbin/prngd and /opt/amix/bin/prngd-ctl."
CATEGORY=system
SET=extra
LICENSE=BSD-4-Clause
URL=https://downloads.sourceforge.net/project/prngd/prngd/0.9.29/prngd-0.9.29.tar.gz
SHA256=e48669c3b78f82a3e2fee3e2ca3e749bba1679d691be587bf70d9a1225842e7c
STYLE=make
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
