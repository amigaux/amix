# build/pkg/tests

`test-pkgmeta` is the host test of `pkgmeta`; run it with `make -C build test`
from the top of the repository. It needs only Python 3 and `/bin/sh`.

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

When a recipe changes there, copy its `package.sh` and its new references
here in the same commit.
