# syslog: the system log's boot step and configuration.
NAME=syslog
PKG=syslog
VERSION=1.0
PKGREV=1
SUMMARY="System log: the syslogd boot step and /etc/syslog.conf"
DESC="init.d/syslogd on rc.subr (on unless rc.conf says syslogd=no), the stock syslog.conf as a conffile, /var/log and /dev/conslog; the daemon is the system's /usr/sbin/syslogd"
CATEGORY=system
SET=base
LICENSE=MIT
STYLE=hooks
# nothing is compiled: no cross toolchain, and any compile is refused
TOOLCHAIN=none
DEPENDS="amix-base"
SYSTEM_PATHS="/dev/conslog"
# the stock bytes, from amix-system (sha256-checked); the admin edits it
STOCK_ETC="/etc/syslog.conf"
CONFFILES="/etc/syslog.conf"
