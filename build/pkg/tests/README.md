# build/pkg/tests

`test-pkgmeta` is the host test of `pkgmeta` and `check-packages`;
`test-pkgbuild` is the host test of the driver and `layout.sh`;
`test-s5mark` is the host test of `pkgroll.sh`'s GATE 3, the s5 rule and
the UFS mark (`APKG_FSTYPE=ufs`, P-35); `test-conffile` the host test of its
`CONFFILES` step (P-36), with stand-ins for userland/pkgtools' class action
scripts. Run them with
`make -C build test` from the top of the repository. They need Python 3,
`/bin/sh`, git, make and tar.

`test-pkgbuild` copies the driver into a throwaway amix tree and builds small
packages against a stub harness that records the environment it is given.
That covers both harness layouts, the three styles, sources from a tarball,
from `src/` and from `SRCPKG`, and one refusal per check.

The fixtures are the reference the framework has to match:

- `recipes/{diffutils,bzip2,coreutils}/package.sh`: the three recipes'
  `package.sh` files as they are in amix-packages at `d53600f`, unchanged.
- `expect/<name>.pkginfo`: the pkginfo amix-packages' interim driver
  (`recipes/common/pkgbuild.sh`) wrote for each of them (`pkgwork/pkginfo` of
  the builds at `d53600f`; the same bytes as the pkginfo inside each rolled
  package).
- `expect/catalog`: what amix-packagemanager's `tools/repo/gen-catalog.py`
  wrote over the three rolled packages, with that repository's `names.conf`,
  `cats.conf`, `deps.conf` and `descs.conf`. The md5 and size fields are of
  those packages; the test passes them to `pkgmeta catalog` and compares the
  whole line.

The harness selftests (`run-selftests`, `make -C build selftests`) prove the
gates of `build/pkg/common` can fail: `gate060-selftest.sh` (the 68060
gate), `gate-gcc14-selftest.sh` (the gcc14 gates and the toolchain pin) and
`onever-selftest.sh` (the one-version guard, against the kernel-space
catalog of record in an amix-packages checkout, `AMIX_KSPACE_REPO`; without
one it exits 77, a SKIP). They need both cross toolchains and the host
pkgtools, which `run-selftests` builds when missing; CI runs them in the
build container.

When a recipe changes there, copy its `package.sh` and its new references
here in the same commit.
