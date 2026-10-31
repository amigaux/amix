# syslog build hooks. The source tree is a copy of userland/base. Nothing
# is compiled: the daemon is the system's.

build() {
	:
}

stage() {
	mkdir -p "$DEST/etc/init.d" "$DEST/etc/rc2.d" "$DEST/etc/rc0.d" "$DEST/var/log"
	cp syslog/syslogd "$DEST/etc/init.d/syslogd"
	chmod 0444 "$DEST/etc/init.d/syslogd"
	# the run-level names are hard links of the one script, as the
	# installer laid them
	ln "$DEST/etc/init.d/syslogd" "$DEST/etc/rc2.d/S70syslogd"
	ln "$DEST/etc/init.d/syslogd" "$DEST/etc/rc0.d/K50syslogd"
}
