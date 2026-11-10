# tools/lib/lab-env.sh -- a test bench's own network values, mapped from the tree's documentation values.
#
# The tracked profiles name a network only with documentation values: the 192.0.2.0/24,
# 198.51.100.0/24 and 203.0.113.0/24 ranges (RFC 5737) and the domain example.net. A test bench that
# masters media for its own network keeps its real values in one file outside this repository and
# names it with LAB_ENV; the file may set LAB_NET, LAB_ALT_NET, LAB_SLOT_NET, LAB_DOMAIN, and LAB_WS and
# AMIBERRY_HOME for the bench's own @WS@ and @AMIBERRY@ path tokens. Without LAB_ENV the documentation
# values stand and the tokens are left as they are: that is what a release build (make dist) does.
#
# POSIX sh. The caller sets LAB_REPO (media/) and sources this file:
#     LAB_REPO=$repo; . "$repo/tools/lib/lab-env.sh"
# then maps text with lab_localize (stdin -> stdout) or lab_str "<one string>".
# Applied where a profile is staged onto a medium (build-install-iso.sh).

LAB_NET=192.0.2
LAB_ALT_NET=198.51.100
LAB_SLOT_NET=203.0.113
LAB_DOMAIN=example.net
: "${LAB_REPO:?lab-env.sh: set LAB_REPO before sourcing}"
if [ -n "${LAB_ENV:-}" ]; then
	[ -f "$LAB_ENV" ] || { echo "lab-env.sh: LAB_ENV=$LAB_ENV does not exist" >&2; return 1 2>/dev/null || exit 1; }
	. "$LAB_ENV"
fi

lab_localize() {
	sed -E -e "s/(^|[^0-9.])192\\.0\\.2\\./\\1$LAB_NET./g" \
	    -e "s/(^|[^0-9.])198\\.51\\.100\\./\\1$LAB_ALT_NET./g" \
	    -e "s/(^|[^0-9.])203\\.0\\.113\\./\\1$LAB_SLOT_NET./g" \
	    -e "s/\\bexample\\.net\\b/$LAB_DOMAIN/g" \
	    ${LAB_WS:+-e "s|@WS@|$LAB_WS|g"} \
	    ${AMIBERRY_HOME:+-e "s|@AMIBERRY@|$AMIBERRY_HOME|g"}
}

lab_str() {
	printf '%s\n' "$1" | lab_localize
}
