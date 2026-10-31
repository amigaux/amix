# /etc/profile.d/x11r63.sh -- put X11R6.3's commands on PATH, last.
#
# /opt/amix/X11R6/bin (also /usr/X11R6/bin) after everything else, so the
# stock X11R4/R5 commands in /usr/X/bin keep their names where a profile
# puts them first.
case ":$PATH:" in
*:/opt/amix/X11R6/bin:*|*:/usr/X11R6/bin:*)
	;;
*)
	PATH="$PATH:/opt/amix/X11R6/bin"
	export PATH
	;;
esac
