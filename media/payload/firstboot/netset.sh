#!/bin/sh
# netset.sh -- the network installation's second stage, on the installed system.
#
# The netinstall medium installs a minimal system (the minimal set over HTTP, the base
# packages from its image, the kernel set, the boot store) and records the rest of the
# chosen set in /var/adm/firstboot/netset: the set's name, the repository, and one catalog
# row per package still to install, in install order. /etc/rc2.d/S99znetset runs this at
# the end of run level 2 -- the network is up, swap is on, the boot generation is marked
# good -- and the console login comes after it. It can also be run by hand:
#
#     /sbin/sh /var/adm/firstboot/netset.sh
#
# Each package is installed with apkg, one at a time, from the repository the installation
# used. Before the first one, every recorded row must still be the repository catalog's row
# (name, version, file, md5, size): apkg then refuses any datastream whose size or md5 is not
# its row's, so these are the bytes the installation chose. A package already installed is
# skipped, so a run that was interrupted continues where it stopped. A failure (no network,
# a changed repository, a package that will not install after three tries) stops here, says
# what is missing, and leaves the system as it is: bootable, with the packages installed so
# far, and this stage armed for the next boot. When every package is in, netset becomes
# netset.done and the rc2 hook is removed.
#
# One run at a time (the lock directory netset.lock, holding the runner's pid): a run started
# while another is going waits for it, then finds the record gone or continues it. The boot's
# run (--boot, from the rc2 hook) clears a lock left by a run the last shutdown cut short.
#
# PRE-POSIX SVR4 /bin/sh: no $(...), no $(( )), no `local`; a redirected loop runs in a
# subshell, so loops that must set variables read from a here-variable through `set --`.

FB=/var/adm/firstboot
NS=$FB/netset
LOG=$FB/netset.log
HOOK=/etc/rc2.d/S99znetset
APKG=/usr/apkg/bin/apkg
W=/var/apkg/netset
CONF=$W/apkg.conf
LOCK=$FB/netset.lock
TRIES=3
PAUSE=30

[ -f "$NS" ] || exit 0

# one run at a time
[ "$1" != --boot ] || rm -rf "${LOCK:?}"
WAITED=
until mkdir "$LOCK" 2> /dev/null
do
	p=`cat "$LOCK/pid" 2> /dev/null`
	if [ -n "$p" ] && kill -0 "$p" 2> /dev/null; then
		[ -n "$WAITED" ] || echo "The network installation is already running (process $p); waiting for it."
		WAITED=y
		sleep 10
	elif [ -n "$p" ]; then
		rm -rf "${LOCK:?}"
	else
		# a lock with no pid yet: its runner is writing it, or died doing so
		e=`expr ${e:-0} + 1`
		[ $e -lt 30 ] || rm -rf "${LOCK:?}"
		sleep 1
	fi
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "${LOCK:?}"' 0
[ -f "$NS" ] || exit 0

say()
{
	echo "$*"
	echo "$*" >> "$LOG"
}

stop()
{
	say ""
	say "The network installation of the $SET set did not finish:"
	say "$*"
	say "The system works with the packages installed so far.  The installation"
	say "continues at the next boot, or now with:  /sbin/sh $FB/netset.sh"
	rm -f "${W:?}"/cache/*.pkg
	exit 0
}

# row_of FILE NAME -- the catalog row of NAME in FILE (its first field), or nothing
row_of()
{
	while read _l
	do
		case "$_l" in
			"$2|"*)	echo "$_l"; break ;;
		esac
	done < "$1"
}

SET=`sed -n 's/^set //p' "$NS"`
REPO=`sed -n 's/^repo //p' "$NS"`
sed -n 's/^row //p' "$NS" > "$FB/netset.rows" || exit 0
NAMES=`sed 's/|.*//' "$FB/netset.rows"`
set -- $NAMES
N=$#
[ -n "$SET" ] && [ -n "$REPO" ] || { echo "netset: $NS names no set or no repository" >> "$LOG"; exit 0; }
[ -x "$APKG" ] || { SET=${SET:-chosen}; stop "there is no $APKG on this system."; }

echo "# netset: `date`" >> "$LOG"
say ""
say "Installing the rest of the $SET set from $REPO: $N packages."
# a resumed run finds the work dir of the run that stopped: the stock mkdir -p fails on it (rc 2)
[ -d "$W/cache" ] || mkdir -p "$W/cache" || stop "cannot make $W."
{
	echo "repo=$REPO"
	echo "cachedir=$W/cache"
} > "$CONF" || stop "cannot write $CONF."

t=1
until "$APKG" -c "$CONF" update >> "$LOG" 2>&1
do
	[ $t -lt $TRIES ] || stop "the repository $REPO could not be read."
	say "The repository did not answer; trying again in $PAUSE seconds."
	sleep $PAUSE
	t=`expr $t + 1`
done

# the rows the installation recorded must still be the repository's
for name in $NAMES
do
	want=`row_of "$FB/netset.rows" "$name"`
	got=`row_of "$W/catalog" "$name"`
	[ -n "$got" ] || stop "the repository changed since the installation: it has no $name."
	[ "$got" = "$want" ] || stop "the repository changed since the installation: $name is not the package the installation chose."
done

k=0
for name in $NAMES
do
	k=`expr $k + 1`
	row=`row_of "$FB/netset.rows" "$name"`
	ver=`expr "$row" : '[^|]*|\([^|]*\)|'`
	inst=`expr "$row" : '[^|]*|[^|]*|\([^|]*\)|'`
	if [ -d "/var/sadm/pkg/$inst" ]; then
		say "  $k of $N: $name $ver (already installed)"
		continue
	fi
	say "  $k of $N: $name $ver"
	t=1
	until TMPDIR=/var/tmp "$APKG" -c "$CONF" -y install "$name" >> "$LOG" 2>&1
	do
		rm -f "${W:?}"/cache/*.pkg
		[ $t -lt $TRIES ] || stop "$name $ver did not install (the log: $LOG)."
		say "  $name did not install; trying again in $PAUSE seconds."
		sleep $PAUSE
		t=`expr $t + 1`
	done
	[ -d "/var/sadm/pkg/$inst" ] || stop "apkg installed $name but /var/sadm/pkg/$inst is not there."
	echo "installed $row" >> "$LOG"
	rm -f "${W:?}"/cache/*.pkg
done

mv "${NS:?}" "${NS:?}.done"
rm -f "${HOOK:?}" "${FB:?}/netset.rows"
rm -rf "${W:?}"
say "The $SET set is installed."
exit 0
