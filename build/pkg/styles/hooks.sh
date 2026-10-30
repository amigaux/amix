# styles/hooks.sh: the recipe's own build hook. Sourced by pkgbuild.sh.
#
# MIT licence, see LICENSE at the top of the repository.
# For a tree that neither configure nor make fits (perl's Configure, zlib's
# hand-written configure and objects compiled by the recipe). build.sh
# defines build, which configures and builds (cwd: the source tree) and
# writes every real compile line to $BUILD/make.log itself; the driver's
# strict gates then read that log as they read make's. The configure_args,
# pre_configure and post_configure hooks are not called.

STYLE_LOG=own

build() { echo "[FAIL] STYLE=hooks and build.sh defines no build hook" >&2; exit 1; }

style_configure() { :; }

style_make() {
	build
}
