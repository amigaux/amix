# /etc/profile.d/amix-base.sh -- put /usr/amix/bin just before /usr/bin.
#
# /usr/amix/bin holds only commands that answer for the add-on packages'
# files and pass everything else to the stock command of the same name (man).
# /usr/local/bin stays first; /opt/amix/bin stays last.
case ":$PATH:" in
*:/usr/amix/bin:*)
	;;
*:/usr/bin:*)
	PATH=`echo ":$PATH:" | sed -e 's|:/usr/bin:|:/usr/amix/bin:/usr/bin:|' -e 's|^:||' -e 's|:$||'`
	export PATH
	;;
esac
