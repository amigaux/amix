# pin.sh -- zz9kbus-k30 / zz9kbus-k46: the ZZ9000-family board registry as a kernel module
# (amix-dlm C3-5 sec 1), by sha256.  Sourced by build.sh.
#
# The objects are built by make dist's modules step (or `make -C kernel/modules/zz9kbus/
# module`) into kernel/modules/zz9kbus/build/<line>/mod.d/zz9kbus.  Misc module, boot class
# with match= the boards it serves, unload=never, no majors, no depend=.  Board driver
# packages and zz9ksvc need it.
# 1.0.0-1 (2026-11-01): the first.
# 1.0.0-2 (2026-11-01): rebuilt on kit 3b53a8a (gcc-cross-amix 33ebadc); the
# code is unchanged, only .moddata cc= differs (gcc-2.7.2.3-33ebadc).

KM_NAME=zz9kbus
KM_SHORT=zz9kbus
KM_REPO=kernel/modules/zz9kbus
KM_VERSION=1.0.0-2

KM_K30_OBJ=kernel/modules/zz9kbus/build/k30/mod.d/zz9kbus
KM_K30_SHA=24c00be48a7fc76860d34680b57aab417889569979e63bd05479f96414d73703
KM_K46_OBJ=kernel/modules/zz9kbus/build/k46/mod.d/zz9kbus
KM_K46_SHA=6ea8ca203303128f2e8cde46929dc79b36040e3dfcf8a95a257669428ecab776
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=3b53a8aad7c2bca344bfff064ef0b573b06a520f	# PIN gcc-2.7.2.3-33ebadc

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
