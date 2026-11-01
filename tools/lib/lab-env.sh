# tools/lib/lab-env.sh -- the bench network and paths, mapped from the tree's documentation values.
#
# The tracked profiles, emulator configs and bench tools name the bench network only with
# documentation values: the 192.0.2.0/24, 198.51.100.0/24 and 203.0.113.0/24 ranges (RFC 5737; the last
# the emulator slots' network) and the domain
# example.net. Emulator configs name paths with two tokens: @WS@ (the directory holding this repo
# and its sibling repos) and @AMIBERRY@ (Amiberry's data directory). A bench keeps its real values
# in ONE gitignored file, bench/local.env (template: bench/local.env.example). Without it the
# documentation values stand, which is right for the host-side checks and for reading the tree.
#
# POSIX sh. The caller sets LAB_REPO (this repo's root) and sources this file:
#     LAB_REPO=$repo; . "$repo/tools/lib/lab-env.sh"
# then maps text with lab_localize (stdin -> stdout) or lab_str "<one string>".
# Applied where a profile or a config is staged for the bench (build-install-iso.sh,
# build-raw-source.sh, apply-zen-conf.sh, install-matrix.sh) and to the bench tools' defaults.

LAB_NET=192.0.2
LAB_ALT_NET=198.51.100
LAB_SLOT_NET=203.0.113
LAB_DOMAIN=example.net
: "${LAB_REPO:?lab-env.sh: set LAB_REPO before sourcing}"
LAB_ENV_FILE="$LAB_REPO/bench/local.env"
if [ -f "$LAB_ENV_FILE" ]; then
	. "$LAB_ENV_FILE"
fi
AMIBERRY_HOME="${AMIBERRY_HOME:-$HOME/Amiberry}"
LAB_WS="${LAB_WS:-`cd "$LAB_REPO/.." && pwd`}"
LAB_DOMAIN_NODOT=`printf '%s' "$LAB_DOMAIN" | tr -d .`

lab_localize() {
	sed -E -e "s/(^|[^0-9.])192\\.0\\.2\\./\\1$LAB_NET./g" \
	    -e "s/(^|[^0-9.])198\\.51\\.100\\./\\1$LAB_ALT_NET./g" \
	    -e "s/(^|[^0-9.])203\\.0\\.113\\./\\1$LAB_SLOT_NET./g" \
	    -e "s/\\bexample\\.net\\b/$LAB_DOMAIN/g" \
	    -e "s/\\bexamplenet\\b/$LAB_DOMAIN_NODOT/g" \
	    -e "s|@WS@|$LAB_WS|g" \
	    -e "s|@AMIBERRY@|$AMIBERRY_HOME|g"
}

lab_str() {
	printf '%s\n' "$1" | lab_localize
}
