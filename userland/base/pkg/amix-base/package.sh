# amix-base: the base system this project writes itself.
NAME=amix-base
PKG=amxbase
VERSION=1.0
PKGREV=35
SUMMARY="Amix base system: boot helpers, the network set-up, the base config files"
DESC="rc.subr and /etc/rc.conf, ifup/ifdown over /etc/inet/interfaces, dlpi-mac, the DHCP hook, the new inetinit, the device-node and swap boot steps, the time sync (ntpsync), shutdown with its request to init seen through (initwait), the display set-up (xstart), man, the stock /etc base files as conffiles, and /etc/group with the audio group and the sound device's node /dev/audio"
CATEGORY=system
SET=base
LICENSE=MIT
STYLE=hooks
TOOLCHAIN=gcc14
ESSENTIAL=yes
SYSTEM_PATHS="/usr/amix/bin /usr/lib/amix /usr/lib/inet /usr/sbin/ifup /usr/sbin/ifdown /usr/sbin/dlpi-mac /usr/sbin/ntpsync /usr/sbin/initwait /usr/sbin/shutdown /sbin/shutdown /dev/audio"
# /etc/profile, /etc/inittab and /etc/default/login are built in stage from
# the stock files: profile plus etc/profile.add, inittab plus the dlm line
# (etc/mkinittab.sh), login with ULIMIT=4194303 (etc/mklogin.sh); /etc/group
# likewise, with audio::20: added (etc/mkgroup.sh). /dev/audio is in its
# driver's class, audio, which pkgadd lays after the conffile class: on a
# fresh system the group comes from this package's own /etc/group.
# /usr/sbin/shutdown (and its stock link /sbin/shutdown) is the stock script
# with its last line made the initwait request (rc/mkshutdown.sh): not a
# conffile, so an update replaces it
STOCK_ETC="/etc/TIMEZONE /etc/nodename /etc/inet/hosts /etc/inet/strcf"
CONFFILES="/etc/inittab /etc/TIMEZONE /etc/nodename /etc/inet/hosts /etc/default/login /etc/profile /etc/inet/strcf /etc/inet/network-config /etc/inet/rc.inet /etc/group"
