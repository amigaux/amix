# diffutils — GNU diffutils 2.8.1 for Amix

`diff`, `diff3`, `sdiff` and `cmp` under `/opt/amix/bin`, beside the stock SVR4 tools in
`/usr/bin` (owned by `core`), which this package does not touch. Ours win by PATH.

    sh build/pkg/pkgbuild.sh userland/packages/diffutils        # build + roll
    sh userland/packages/tools/pkg-smoke/prepare.sh userland/packages/diffutils          # stage the on-box acceptance

Package: `diffutil` (PKG ≤ 9 characters), catalog name `diffutils`, category `utility`, set
`extra`, GPL-2.0-or-later (COPYING ships in `/opt/amix/doc/diffutils`). Built with GCC 14
(`TOOLCHAIN=gcc14`, `-m68020-60 -mno-strict-align -O2`). Layout per P-31 §10.9:
`package.sh` holds the metadata, `build.sh` has the hooks only, and `prototype` is the payload.
`pkginfo` is generated.

## Version: 2.8.1

The last release before the gnulib wall (ROADMAP D5). 3.x needs a rebuilt gnulib and
`autoreconf`, which we never run. 2.8.1 carries its own regex, fnmatch, getopt and mkstemp,
so it needs nothing from libamixcompat (D8). With GCC 14 the compat symbols come from the
toolchain's libamixc99. The gate confirms libacompat is never linked.

Source: `https://ftp.gnu.org/gnu/diffutils/diffutils-2.8.1.tar.gz`, sha256
`c5001748…d23f5a`. GNU has no `.sig` for this release. Two independent checks: md5
`71f9c5ae19b60608f6c7f162da86a428` is the value the LFS book publishes, and the kernel.org
mirror serves identical bytes.

## Patches

| Patch | Why |
|---|---|
| `01-diff-posixver-decl.patch` | `diff.c` calls `posix2_version()` without including `posixver.h`. gcc 2.7 compiled the implicit call; GCC 14 rejects it. Upstream added the include after 2.8.1. |
| `02-system-h-mkstemp-decl.patch` | AMIX libc has no `mkstemp`, so configure builds `lib/mkstemp.c`. That file defines `rpl_mkstemp`, but 2.8.1 never maps `mkstemp` to it and no header declares it. `sdiff` calls it, which fails at compile time (implicit declaration) and at link time (undefined `mkstemp`). The patch maps and declares it in `system.h` under `!HAVE_MKSTEMP`. |
| `03-sdiff-merge-exit-status.patch` | `sdiff -o` passed the diff child's status to `ck_editor_status`, which treats any nonzero status as failure. diff exits 1 whenever the files differ, so every completed merge ended with exit 2. That was measured on the box, with the merged file correct. This backports the rule diffutils 2.9 adopted (`check_child_status`, statuses up to `EXIT_FAILURE` are OK). |

## Configure answers pinned (`build.sh`), each asserted against `config.h`

- **`ac_cv_header_stdint_h=no`.** The gcc14 sysroot's compat `stdint.h` satisfies the
  `intmax_t`/`uintmax_t` probes through autoconf's default includes. diffutils' own users
  (`inttostr.h`, `xstrtol.h`, `system.h`, `strtoimax.c`) include only `<inttypes.h>`, which
  AMIX lacks, and failed to compile. With "no", configure defines both as `long long`, as on the
  period toolchain. The make recipe pins the same.
- **`ac_cv_func_vfork=no`.** Cross configure guesses `HAVE_WORKING_VFORK`. vfork is only a
  static member of `usr/ccs/lib/libc.so`, so `system.h` now maps `vfork` to `fork`, which is
  what the bench has proven (make 3.81 pins the same). Seeding `ac_cv_func_vfork_works` has no
  effect: configure overwrites it from `ac_cv_func_vfork`.
- **`ac_cv_path_PR_PROGRAM=/usr/bin/pr`.** `diff -l` pipes through pr. Unpinned, the path would
  come from the host's `AC_PATH_PROG`.
- **`DEFAULT_DIFF_PROGRAM` = `/opt/amix/bin/diff`** (rewritten in `config.h`). Upstream's
  `"diff"` is a PATH lookup. On a stock PATH it finds `/usr/bin/diff`, which knows no
  `--sdiff-merge-assist`, and `sdiff`/`diff3` break. The smoke test runs `sdiff` with the
  stock directories first on PATH to prove it.
- **The tarball's man pages are kept** (`touch man/*.1` after configure). Patches 01 and 03
  make `diff.c`/`sdiff.c` newer than `diff.1`/`sdiff.1`, so make tries to regenerate them
  with help2man. help2man would have to run the cross binary, and `config/missing` leaves both
  pages EMPTY, with exit 0. The driver's empty-file gate now refuses such a payload.

## Limits

- **No large files** (`--disable-largefile`): offsets are 32-bit `off_t`, as everywhere on
  Amix.
- **c-stack is off.** `sigaltstack` does exist in libc.so.1 (syscall 97, declared in
  `<signal.h>`), so the registry's STDC-GATE blocker turned out not to apply. c-stack is off
  only because the XSI stack-overflow test is a run-test, which a cross configure cannot run.
  The cost: deep recursion ends in a plain SIGSEGV instead of a "stack overflow" message.
- **No NLS, no info manual** (the box has no info reader); the man pages ship.
- **Differing binary files exit 2**, as 2.8.1 documents ("considered to cause trouble",
  `diff.texi`); 3.x exits 1. Scripts that test `$? -eq 1` for "different" must allow 2.
- **`malloc`/`realloc` are wrapped** (`rpl_malloc`): the malloc(0) run-test cannot run when
  cross-compiling, so configure takes the safe wrapper.

## Gates (build time)

All of these passed on the 2026-10-29 build:
- no implicit declarations;
- strict flags, with `-mno-strict-align` on every compile line;
- libacompat not linked;
- prototype == staged tree;
- every undefined symbol is exported by libc.so.1;
- the 060 gate with all three scanners, on both the staged tree and the datastream;
- no 040/060-only FPU forms; diff, diff3, sdiff and cmp contain no FPU instructions at all;
- `NEEDED` only `/usr/lib/libc.so.1`;
- no ll printf conversions.

`diff` first came out "untrustworthy" in `scan060-g14.py`. `groups_letter_value` has two
switches back to back, and the linear decode of the first table swallowed the second dispatch's
bound check. The scanner already re-synced and sized that table, but kept the stale first-round
verdict. That was fixed in the scanner (with its own self-test check), not here.

## Test result

See `tests/smoke.sh`. The checks:
- `diff -u` applied with patch reproduces the target byte for byte;
- the context, normal and ed formats (the ed script applied with stock `ed`);
- `-r`, `-N`, `-x` (fnmatch);
- `-I` (regex);
- `-i -b -w -q -y`;
- `-l` through pr;
- binary files;
- `diff3 -m` merge and conflict;
- `sdiff` side by side and an `-o` merge;
- `cmp`, including an offset past 64 KB, and `cmp -l`;
- for the record: whether stock `/usr/bin/diff` has `-u` (ROADMAP X6).

**Bench, 2026-10-29: PASS.** Run on the emulated golden 030 (rig row E1: A3000, 64 MB,
bench-golden kernel 46759dcc), slot 1, rig-run 20261029-214655.
- **Install and removal:** the pushed files matched MANIFEST.sum. Stock `pkgadd` rc 0 installed
  11 files, `pkgchk` rc 0, `tests/smoke.sh` 24/24 ok, stock `pkgrm` rc 0, and afterwards no
  contents-database line names the package.
- **Package:** `diffutil-2.8.1-1.pkg`, md5 `2fed5ef90c8a2f0cddd20a44b760c749`, 213504 bytes.
  A rebuild differs only in pkgmap/cpio mtimes; the payload is identical.
- **Binaries** (`sum -r` / bytes): diff 13253/94360, diff3 63594/22424, sdiff 04547/28084,
  cmp 03876/21904.
- **Evidence:** `Amigaux/tmp/2026-10-29-pkgsmoke-diffutils/run3/E1/`.
- **Earlier runs:** run1 found the sdiff exit status (patch 03) and a wrong expectation in the
  test (binary rc). Run2 passed but shipped two empty man pages (fixed above).

ROADMAP X6 is answered on the box: stock `/usr/bin/diff -u` says `diff: invalid option -u`.
Stock diff has no unified format, so this package is the box's only unified diff.

Not run: real 68030/68060 hardware. The 68060 lane rests on the build gates: all three
scanners are clean, and the binaries contain no FPU instructions.

**Re-mint -2, 2026-10-29: gcc14-cross-amix b51ff39** (the public pin, owner Y3).
- **Objects:** every object is byte-identical to the cf461e3 build.
- **Relink proof:** relinking them against the cf461e3 runtime reproduces the -1 executables
  byte for byte. All the new bytes are runtime: libgcc and libamixc99 were rebuilt under
  -mno-strict-align.
- **Package:** `diffutil-2.8.1-2.pkg`, md5 `baffdea7f68d4017b46e2a4fcb8606d5`, 212992 bytes.
- **Bench:** E1 slot 2, stock pkgadd/pkgchk/pkgrm rc 0, smoke 24/24.
- **Evidence:** `Amigaux/tmp/2026-10-29-g14-repin/`.

## Revision -3: man pages where `man` finds them

The man pages move to `/opt/amix/man/<sect>/<name>` with the package's whatis fragment
`/opt/amix/man/whatis.d/diffutil` (docs/man-pages.md), where the base package's `man` and the stock
`man` find them; the four pages are upstream's, unchanged. Built on the gcc14 container pin: every other payload file is the previous
revision's.
