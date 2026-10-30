# coreutils — GNU coreutils 5.2.1 for Amix

86 GNU programs plus the `groups` script under `/opt/amix/bin`: `ls cp mv rm sort date df du
install stat md5sum sha1sum …`. They sit beside the stock SVR4 tools, which this package
does not touch; ours win by PATH. The headline is **`md5sum` and `sha1sum`**: the box had
no content checksum at all, only `sum`.

    sh recipes/common/pkgbuild.sh recipes/coreutils     # build + roll (interim driver)
    sh tools/pkg-smoke/prepare.sh recipes/coreutils     # stage the on-box acceptance

Package: `coreutil` (PKG ≤ 9 characters), catalog name `coreutils`, category `utility`, set
`extra`, GPL-2.0-or-later (COPYING ships in `/opt/amix/doc/coreutils`). Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`).

**Not shipped:**
- `uptime`: its load average takes the nlist//dev/kmem route, which reads garbage on Amix
  (PORTING.md 3.3);
- `su`: a setuid-root binary from an add-on package is out;
- `hostid`: not built;
- the info manual: the box has no info reader;
- `lib/charset.alias`: an empty table for sysv4.

## Version: 5.2.1

The last 5.x before gnulib became the substrate (D5). One package covers the era trio
(fileutils, textutils, sh-utils).

Source: `https://ftp.gnu.org/gnu/coreutils/coreutils-5.2.1.tar.gz`, sha256 `9f7662c4…c85bf9`.
GPG: good signature from Jim Meyering (DSA key `FDD2DEACD333CBA1`, the maintainer). The
kernel.org mirror serves identical bytes.

## Patches

| Patch | Why |
|---|---|
| `01-fts-dirfd-islnk.patch` | `fts.c` calls `dirfd()` and `S_ISLNK()` but includes neither `lib/dirfd.h` (whose replacement configure builds) nor the `S_ISLNK` fallback. AMIX `<sys/stat.h>` has `S_IFLNK` but no `S_ISLNK`. |
| `02-system-h-mkstemp-decl.patch` | `mkstemp` is mapped to the bundled `rpl_mkstemp` but declared nowhere, and sort/tac call it. |
| `03-who-asprintf-decl.patch` | `who.c` calls `asprintf` (bundled) without including `vasprintf.h`. |
| `04-stat-statvfs-call.patch` | `stat -f` picks `struct statvfs` on SVR4 but still calls `statfs()`, which AMIX does not have. |
| `05-settime-stime.patch` | `settime.c` calls `settimeofday` unconditionally. AMIX has only `stime(2)`, so `date -s` sets whole seconds. |
| `06-seq-no-libm.patch` | seq's `floor`/`rint` exist only in the stock static `libm.a`, so a local pair is built over libc.so.1's `modf` (rint is round-half-even). It was host-checked against libm on 15 values. |
| `07-date-u-writable-tz.patch` | **Found on the box.** `date -u` did `putenv("TZ=UTC0")` with a string literal. AMIX libc.so.1's TZ parser (`getzname`) stores a NUL into the TZ string in place, and GCC 14 puts literals in read-only `.rodata`. So every `date -u` died with SIGSEGV: the PC was in `getzname` at `clrb %a2@`, and the fault address was the `0` of the literal (read from the core's prstatus note). The fix uses a writable array. |

## Configure answers pinned (`build.sh`), asserted where they reach config.h

- **`ac_cv_header_stdint_h=no jm_ac_cv_header_stdint_h=no`**: `intmax_t`/`uintmax_t` become
  `long long`, as on the period toolchain. The sources include only `<inttypes.h>`, which AMIX
  lacks, but the compat `stdint.h` satisfied the probes.
- **`ac_cv_func_vfork=no`**, **`ac_cv_lib_elf_elf_begin=no`**: as the make recipe.
- **Run-tests a cross configure answers "broken" on principle**, where libc.so.1's own
  function is used instead of a gnulib replacement:
  - `ac_cv_func_getgroups_works=yes`;
  - `ac_cv_func_strtod=yes`, which also drops the `pow()` → `-lm` the replacement needs;
  - `jm_cv_func_svid_putenv=yes` (asserted: no `rpl_putenv`).
- **D3**: `amix-pwgr.o` is compiled in `pre_configure` and put in `LIBS`. Every executable
  defines `getpwnam/getpwuid/getgrnam/getgrgid` itself (asserted: 86 of 86 `T`).
- **`MAKE_CFLAGS=-include amix-decls.h`** (select, getrlimit, fchmod): make only. In configure
  the prototypes collide with autoconf's `char f();` probes and turn present functions absent
  (gethostname came out missing that way).
- **No `-lm` anywhere** (`SEQ_LIBM= POW_LIB= SQRT_LIBM=`, asserted on every link line). factor
  never calls `sqrt`; `SQRT_LIBM` is a leftover.
- **The tarball's man pages are kept** (`touch man/*.1`). Otherwise make runs help2man on the
  cross binaries, as in diffutils.

## Linkage

- `NEEDED`: `/usr/lib/libc.so.1` and `libnsl.so` (configure adds `-lnsl` for `gethostbyname`).
  Dynamic linkage against a library on the box redistributes nothing (grimoire, payload-licence
  gate). `libnsl.so` comes with the stock networking that every bench and install image here
  carries.
- Static members of `usr/ccs/lib/libc.so` that libc.so.1 lacks: `getmntent.o` (df's mount
  list) and `getutx.o` (who/users/pinky). These are the same class as tar's
  `gettimeofday.o` under gcc14, and the same static `data.o`/`_ctype.o`/`sh_data.o` every
  dynamically linked Amix program carries.
- **No `libm.a`, no `libgen.a` member** in any binary (link map checked for df).

## Limits

- **FPU**: 23 programs carry FPU instructions (ls/dir/vdir, du, df, cp, mv, rm, install, chmod,
  chown, chgrp, sort, seq, printf, sleep, od, cut, shred, sum, tail, test/`[`, who). None is a
  040/060-only form. Sources include human-readable sizes, seq/printf/sleep arithmetic, and
  libamixc99's `vsnprintf`, which saves `%fp2` in its prologue. So these need an FPU or the
  kernel's FPE on an FPU-less 68LC040/LC060. The other 64 programs have none. This is the
  registry's FP-DOPRNT constraint, recorded rather than patched out.
- No large files (`--disable-largefile`). `date -s` has 1-second resolution (`stime`).
- `stty` needs a terminal. `logname` needs a login tty.

## Gates (build time)

All of these passed on the 2026-10-29 build:
- strict flags, with `-mno-strict-align` on 223/223 compile lines;
- libacompat not linked;
- prototype == staged tree (184 paths);
- no empty file;
- every undefined symbol defined by the binary's own `NEEDED` libraries;
- D3 86/86;
- the 060 gate with all three scanners, on the tree and on the datastream;
- no 040/060-only FPU form;
- no ll printf conversion.

`who`/`users`/`pinky` first came out "untrustworthy". The stock AT&T compiler's switch in
`getutx.o` bounds its index with `cmpa`, which `scan060-g14.py` now recognises (with its own
self-test check).

## Test result

See `tests/smoke.sh`: 95 checks, run as root on the box.

**Content checksums** against host-computed digests of the same awk-generated 511456 bytes:
md5sum, sha1sum, cksum, `md5sum -c` both ways, and `sum -r` equal to the stock `sum -r`.

**D3:**
- `id`, `whoami`, `groups`;
- `chown bin:bin` / `chgrp sys` shown by name in `ls -l` and `stat`;
- `ls -ln`.

**Files:**
- `cp -rp` keeping mode and mtime;
- `mv`, `ln -s`/`readlink`, `ls -l` on a symlink (lstat), `rm -rf`, `mkdir -p`;
- `install -m`, `mkfifo`, `link`/`unlink`, `shred -u`, `dircolors`.

**File systems:** `df` (getmntent), `du`, `stat -f` (statvfs, `Type: ufs`).

**Text:**
- `sort -n`, `sort -S 32k` (temp files) equal to the stock sort, `sort -k`;
- `head`, `tail`, `wc`, `tr`, `cut`, `uniq`, `tac`, `nl`, `join`, `paste`, `comm`;
- `split`, `csplit`, `od`, `fold`, `expand`, `unexpand`, `tsort`, `fmt`, `pr`, `ptx`, `tee`.

**Numbers:**
- `factor` on a 40-bit operand;
- `seq -w`, a negative step, `0.5` steps;
- `printf %5.2f`, `expr`;
- `sleep 2` timed;
- `date -u -d`, `date -d` parse.

**The rest:**
- `basename`/`dirname`, `echo -n`, `env -i`, `test`/`[`, `true`/`false`, `yes`;
- `pathchk`, `pwd`, `dd`, `uname`, `hostname`, `nice -n 5`, `nohup`, `kill -l`;
- `tty` and `stty` on a non-tty, `sync`, `who`, `users`, `pinky`.

**Bench, 2026-10-29: PASS.** Run on the emulated golden 030 (rig row E1: A3000, 64 MB,
bench-golden kernel 46759dcc), slot 1, rig-run 20261029-230323.
- **Install and removal:** the pushed files matched MANIFEST.sum. Stock `pkgadd` rc 0 installed
  177 files, `pkgchk` rc 0, smoke 95/95, stock `pkgrm` rc 0, and no contents-database line was
  left.
- **Package:** `coreutil-5.2.1-1.pkg`, md5 `81300da8b7c9dc5500f9abb0a6b90112`, 3567104 bytes.
- **Binaries** (`sum -r` / bytes): ls 07714/102348, md5sum 08949/36092, sha1sum 35204/36092,
  date 43132/54072, sort 00515/52856, df 09125/52888.
- **Evidence:** `Amigaux/tmp/2026-10-29-pkgsmoke-coreutils/run3/E1/`.
- **Earlier runs:** run1 and run2 failed `date -u` (93/95). The probes (`…/probe`, `…/probe2`,
  with the core file) isolated it to patch 07's cause; the run2 `putenv` seed was not the cause.

Not run: real hardware, and an FPU-less part.

**Re-mint -2, 2026-10-29: gcc14-cross-amix b51ff39** (the public pin, owner Y3).
- **Objects:** every object is byte-identical to the cf461e3 build.
- **Relink proof:** relinking them against the cf461e3 runtime reproduces the -1 executables
  byte for byte. All the new bytes are runtime: libgcc and libamixc99 were rebuilt under
  -mno-strict-align.
- **Package:** `coreutil-5.2.1-2.pkg`, md5 `e5552f7e2b7f753932718eb7d7530f2d`, 3557376 bytes.
- **Bench:** E1 slot 2, stock pkgadd/pkgchk/pkgrm rc 0, smoke 95/95.
- **Evidence:** `Amigaux/tmp/2026-10-29-g14-repin/`.
