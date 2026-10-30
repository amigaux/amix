# grep — the recipe

**Package `grep` 2.5.1a** — GNU grep with recursive/`-o`/`--color`. GPL-2.0-or-later.
Metadata and source pin: [`package.sh`](package.sh); build hooks: [`build.sh`](build.sh).

    sh build/pkg/pkgbuild.sh userland/packages/grep

## ★ Coexistence, the worked case

Stock ships SVR4 `grep` at `/usr/bin/grep` (→`/sbin/grep`), owned by `core`, with no
`-r`/`-o`/`--color` and a shaky `-E`. This package **does not touch it** — ours installs to
`/opt/amix/bin/grep` and wins for interactive users purely by PATH order, while stock scripts that
hard-code `/usr/bin/grep` keep stock behaviour (`docs/coexistence.md §2–3`). Nothing lands outside
`/opt/amix`, so the `pkgadd` conflict machinery never fires and a stock `pkgrm` can never take our
binary with it.

## Result

Builds clean — **zero implicit declarations**, m68k SVR4 ELF, **D4-clean**. **Bench-proven** on the
emulated golden 030 (2026-08-30): `pkgadd`, then `grep -rn` found a pattern across two files with
`file:line:` prefixes, `-o` printed only the match, `--color=always` emitted an ANSI escape, `-E`
alternation matched; `pkgchk` 0, `pkgrm` clean.

## Why 2.5.1a — the bundled regex, forced

The last GPLv2 grep, and the deciding factor is that it carries its **own** `regex.c` (the GNU
`re_compile_pattern`/`re_search` API). **The box has no POSIX `regcomp` at all** (D8), so a grep that
expects the system to provide it is unbuildable. The trap the REGEX-NONE blocker names is that a
compile-test for a system regex *succeeds* under gcc 2.7's implicit declarations even when the
symbol is absent — so this recipe passes **`--with-included-regex`** to force `regex.o` into
`LIBOBJS` and then **asserts** it is in the link (via `config.status`), rather than trusting the
flag.

## The two source patches, both measured

- [`patches/01-system-h-svr4.patch`](patches/01-system-h-svr4.patch) — grep's `--color` parser calls
  **`strcasecmp`**, which is absent from `libc.so.1` and declared by no SVR4 header (it lives only in
  the networking archives / libamixcompat). The patch declares it; `-lacompat` supplies the symbol,
  statically linked. The same patch defines **`S_ISSOCK`**, which SVR4 leaves undefined though
  `S_IFSOCK` (0xC000) exists.
- [`patches/02-savedir-isdir-decl.patch`](patches/02-savedir-isdir-decl.patch) — gnulib's `savedir.c`
  calls `isdir()` (defined in `isdir.c`) without a prototype; gcc 2.7 would compile it as
  int-returning implicitly. Harmless here, but a defect this line does not wave through.

`strcasecmp` is the only thing grep needs from libamixcompat; `depends.build: [libamixcompat]`
stands (unlike gzip/less).

## ★ D4 — the published package fails it (found 2026-09-26)

The "D4-clean" above was reported by a gate that could not fire (`docs/recipes.md`). Under the
corrected, encoding-based gate the published `grep-2.5.1a.pkg` carries **two** register/memory-
source 64-bit multiplies — gnulib's `strtoull` (`lib/strtol.c`, QUAD instance) and the `uintmax_t`
`bkm_scale` in `lib/xstrtol.c` — both on the `-A`/`-B`/`-C`/`-m` argument path (`xstrtoumax`). The
68LC060 does not implement that form and the kernel does not emulate it, so those options are
expected to SIGKILL grep there (static finding; not run on metal). The 030 is unaffected.
[`patches/03-d4-strtoull-muldi3.patch`](patches/03-d4-strtoull-muldi3.patch) and
[`patches/04-d4-xstrtoumax-muldi3.patch`](patches/04-d4-xstrtoumax-muldi3.patch) route both
products through libgcc's `__muldi3`; the rebuilt binary is D4-clean. The **published** artifact is
not fixed until a re-mint with a distinguishable version is published.

**Re-minted 2026-09-26 as package `2.5.1a-2`** — same upstream tarball, package revision 2
(`build.sh` `PKGVERSION`, which it checks against `pkginfo`'s `VERSION`), datastream
`grep-2.5.1a-2.pkg` (md5 `e84604a1…`, 139264 B). D4 on the binary extracted from the datastream:
0 bad, 0 `#imm`. `tests/smoke.sh` now also checks `-A 3`, `-B 2`, `-C 1`, `-m 1` — the argument
path D4 moved — and passed on the emulated golden 030. Staged for publication in the batch-2 root
(`BATCH-1.md`); the catalog name stays `grep`.

## Package shape

`/opt/amix/bin/{grep,egrep,fgrep}`, man pages under `/opt/amix/man/man1/`,
`COPYING`/`NEWS`/`README` under `/opt/amix/doc/grep/`. `egrep`/`fgrep` are grep's own `/bin/sh`
wrappers, rewritten to `exec /opt/amix/bin/grep -E|-F …` by **absolute** path so they work regardless
of PATH. Pure file payload (D9), nothing outside `/opt/amix`, no symlink into a stock tree.

## GCC 14 revisions

The current package is built with GCC 14 (`TOOLCHAIN=gcc14`); the period build stopped at `-2`.
Each revision is new bytes, so a new version: `-3` was `-mcpu=68060` (never published; its FPU
forms kill make on a 68882), `-4` `-m68020-60`, `-5` the same on gcc14-cross-amix cf461e3
(pointers returned in `%a0` and `%d0`, structs via `%a0`, as AMIX's compilers and libc do), `-6`
the same with `-mno-strict-align`, `-7` the same objects relinked on the public pin b51ff39 (only
the runtime it links differs). Under GCC 14 `strcasecmp` comes from the toolchain runtime
`libamixc99`, which the specs link, so nothing from libamixcompat is linked; and configure's
`stdint.h` answer is pinned to the period one (`no`): with the compat `stdint.h` the `off_t` probe
fails and `off_t` becomes a macro.

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt `-7` has
the recorded `-7`'s payload (every file's sha256 and mode), pkginfo, pkgmap (mtimes aside) and
catalog line.
