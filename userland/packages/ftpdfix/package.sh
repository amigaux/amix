# package.sh -- ftpdfix: the stock in.ftpd, its data connection closed safely; assignments only.
NAME=ftpdfix
PKG=ftpdfix
VERSION=2.1
PKGREV=1
SUMMARY="in.ftpd that no longer cuts the end off a download"
DESC="/usr/sbin/in.ftpd, Amix 2.1's own FTP server, with 179 bytes changed so that a download (RETR, LIST, NLST) no longer loses its last bytes while the server still reports 226 Transfer complete. The server shuts down its side of the data connection, waits until the client has read everything and closed (at most 60 s), and only then closes it; the active-mode path no longer sets SO_LINGER. Everything else is the stock file, byte for byte. Built from amix-system at its pin; replaces net's copy, which stays recorded under net."
CATEGORY=network
SET=base
LICENSE="LicenseRef-Amix-System"
STYLE=hooks
TOOLCHAIN=period
ESSENTIAL=yes
SYSTEM_PATHS="/usr/sbin/in.ftpd"
# the stock file and the bytes it must have after the stage hook patches it
STOCK_PATCHED="/usr/sbin/in.ftpd=fab610e3bea2251ad0e7d58d147ab72b50b11723c43099a3a807cd8ecd1ac6e4"
MAN_REPLACES="/usr/sbin/in.ftpd 1m ftpdfix"
SOURCE_EPOCH=1794009600   # 2026-11-07 00:00 UTC, the time stamp of this version
DEPENDS=""
BUILD_DEPENDS=""
