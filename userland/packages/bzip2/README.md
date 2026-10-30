# bzip2 — bzip2 1.0.8 for Amix

`bzip2`, `bunzip2`, `bzcat`, `bzip2recover`, the `bzgrep`/`bzmore`/`bzdiff` wrappers (with
their `bzegrep`/`bzfgrep`/`bzless`/`bzcmp` names), and `libbz2.a` + `bzlib.h`, under
`/opt/amix`. Stock Amix has no bzip2 at all.

    sh recipes/common/pkgbuild.sh recipes/bzip2      # build + roll (interim driver, STYLE=make)
    sh tools/pkg-smoke/prepare.sh recipes/bzip2      # stage the on-box acceptance

Package: `bzip2`, catalog name `bzip2`, category `archive` (P-31 §10.9 decision 3, which names
bzip2 under archive; the live `cats.conf` declares the group at the next owner-approved
publish), set `extra`. Licence: the bzip2-1.0.6 licence, BSD-style; LICENSE ships in
`/opt/amix/doc/bzip2`. Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`) from the plain
Makefile (`STYLE=make`: the driver passes CC/AR/RANLIB/CFLAGS; there is no configure).

## Version: 1.0.8

The current release. It fixes CVE-2019-12900 (an out-of-bounds write in the decompressor),
which 1.0.2, the archived Amix build, still carries. A decompressor that runs on untrusted input
should be the patched one. Plain C, no autotools, no gnulib.

Source: `https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz`, sha256 `ab5a0317…c4a2269`.
GPG: good signature from Mark Wielaard (key `12768A96795990107A0D2FDFFC57E3CCACD99A78`,
maintainer since 1.0.7). The kernel.org mirror serves identical bytes.

## Patches

| Patch | Why |
|---|---|
| `01-bzip2recover-u64-print.patch` | bzip2recover prints its 64-bit block offsets with `%Lu`. AMIX libc's printf reads `%Lu`/`%llu` as a 32-bit long, which garbles that number and every argument after it. A small decimal formatter now prints them with `%s`, so the gcc14 llprintf gate has nothing to find. |
| `02-bzgrep-bourne.patch` | `$(...)` → backticks, for the 1992 Bourne shell. The `printf(1)` step is folded into the pipeline. The last `sed` gets an extra newline, because **AMIX sed silently drops a final line that has no newline**. Measured on the box: the file-name prefix came out empty. Host-checked identical to upstream for names containing `\`, `|`, `&` and spaces. |
| `03-bzdiff-no-mktemp.patch` | AMIX has no `mktemp(1)`. bzdiff now makes a private mode-700 directory instead. `mkdir` fails if the name exists, so a planted file or link is never followed. |
| `04-bzip2-fp-report-out-of-line.patch` | The `-v` ratio report is the only floating point in `compressStream`, but GCC 14 saved `%fp2-%fp3` in `compressStream`'s *prologue*. Every compression therefore executed an FPU instruction, even without `-v`. That kills bzip2 on an FPU-less 68LC040/68LC060 without the kernel FPE. The report moves to a `noinline` function. |

## Build notes

- **`-include amix-decls.h`**: bzip2.c calls `fchmod` (to copy the input's mode). libc.so.1
  exports it (`SYS_fchmod` 93), but no AMIX header declares it. The prototype is now in
  `recipes/common/gcc14/amix-decls.h`.
- **No large files**: the driver's CFLAGS replace the Makefile's `-D_FILE_OFFSET_BITS=64`,
  and `post_build` asserts it never reached a compile line. Files over 2 GB are out, as
  everywhere on Amix.
- **Targets `libbz2.a bzip2 bzip2recover` only**: `all` includes `test`, which would run the
  cross binary on the host. Upstream's test vectors run on the box instead (below).
- **The alias names are hard links** (prototype `l`), because stock pkgadd prepends the root to
  a relative symlink target (PORTING.md 7). Upstream's `ln -s` would have broken.

## Limits

- **FPU**: the gate counts 40 FPU instructions in bzip2 and 13 in `libbz2.a`, so it reports
  "NEEDS an FPU". After patch 04 every one of them is on a verbose-only path:
  - `reportRatio` (`-v`);
  - the `verbosity >= 3` branches of `BZ2_compressBlock` and `BZ2_blockSort` (checked in the
    disassembly).

  Default compression and all decompression execute none. On an FPU-less part without FPE,
  only `-v`/`-vvv` would fault. bzip2recover has no FPU instructions at all.
- `bzmore`/`bzless` call the stock `more` (no `less` dependency); `bzless` is just bzmore
  under that name, as upstream.
- No `bzip2-shared` / `libbz2.so` (`Makefile-libbz2_so` is not built): Amix userland links
  static.

## Gates (build time)

All of these passed on the 2026-10-29 build:
- strict flags, with `-mno-strict-align` on 9/9 compile lines;
- libacompat not linked;
- prototype == staged tree (33 paths);
- no empty file;
- every undefined symbol is exported by libc.so.1;
- the 060 gate with all three scanners, on the staged tree and on the datastream (`scan060.py`
  hits on bzip2 are all table data or odd addresses);
- no 040/060-only FPU form;
- `NEEDED` only `/usr/lib/libc.so.1`;
- no ll printf conversion.

## Test result

See `tests/smoke.sh`. Upstream's three test vectors (`tests/fixtures`) are pushed with it. The
checks:
- upstream's `make test` on the box: `-1/-2/-3` compression byte-identical to upstream's
  `.bz2`, and decompression, including `-s`;
- a file round trip that keeps the mode (`fchmod`), plus `-k`, `-t` and `bzcat`;
- the hard links;
- `-t` on a non-bzip2 file → rc 2;
- the `-v` report;
- bzip2recover on a multi-block file cut in half: 4 blocks, 64-bit offsets printed right, and
  the recovered data an exact prefix of the original;
- bzgrep on one file and on two (with `file:` prefixes);
- bzegrep;
- bzdiff on two `.bz2` files, with its temp directory removed;
- bzcmp;
- bzmore.

**Bench, 2026-10-29: PASS.** Run on the emulated golden 030 (rig row E1: A3000, 64 MB,
bench-golden kernel 46759dcc), slot 1, rig-run 20261029-220828.
- **Install and removal:** the pushed files matched MANIFEST.sum. Stock `pkgadd` rc 0 installed
  18 files, `pkgchk` rc 0, smoke 23/23, stock `pkgrm` rc 0, and no contents-database line was
  left.
- **Package:** `bzip2-1.0.8-1.pkg`, md5 `65e99c401f29f801e4685d5983f6c408`, 221696 bytes.
- **Binaries** (`sum -r` / bytes): bzip2 59958/80092 (bunzip2 and bzcat are the same file),
  bzip2recover 45819/11144. `libbz2.a` is 64010 bytes; its sum differs per build (ar
  timestamps).
- **Evidence:** `Amigaux/tmp/2026-10-29-pkgsmoke-bzip2/run2/E1/`.
- **Run1** failed the two-file bzgrep and led to the sed finding above. The probe of the pieces
  is in `…/probe/run/E1/probe.log`.

Not run: real 68030/68060 hardware, and an FPU-less part.

**Re-mint -2, 2026-10-29: gcc14-cross-amix b51ff39** (the public pin, owner Y3).
- **Objects:** every object is byte-identical to the cf461e3 build.
- **Relink proof:** relinking them against the cf461e3 runtime reproduces the -1 executables
  byte for byte. All the new bytes are runtime: libgcc and libamixc99 were rebuilt under
  -mno-strict-align.
- **Package:** `bzip2-1.0.8-2.pkg`, md5 `2b10de77a92e2da2338972da68a8f6eb`, 218624 bytes.
- **Bench:** E1 slot 2, stock pkgadd/pkgchk/pkgrm rc 0, smoke 23/23.
- **Evidence:** `Amigaux/tmp/2026-10-29-g14-repin/`.
