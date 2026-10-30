# Contributing to userland/pkgtools

This is a shipped system under maintenance, not an investigation. Before changing anything, read
[`NOTES.md`](NOTES.md): it is the session-by-session record and **the authority on current
state**. If any other document (including this one) disagrees with it, NOTES.md wins and the other
document is stale. Engine port detail lives in [`heirloom/AMIX-PORT.md`](heirloom/AMIX-PORT.md).

## Hard constraints

These were learned on real Amix systems. Violating them fails silently.

1. **PKG names must be at most 9 characters.** Stock Amix `pkgadd` silently drops a longer one: no
   error, no package. `tools/repo/build-packages.sh` enforces this, and anything that mints a PKG
   name must too. A longer user-facing name goes through `tools/repo/names.conf` (catalog name to
   pkginst), or for a recipe-built package through amix's `userland/packages/conf/names.conf`.

2. **Keep alternate-root paths well under about 110 characters.** `libadm/pkginfo.c` `svr4info()`
   originally used a fixed 128-byte buffer and smashed the stack for `-R` roots longer than about
   105 characters. This tree widened it to `PATH_MAX`, but stock Amix tools and any unaudited path
   still carry the original limit.

3. **`pkgadd -R <altroot>`** works with this engine (the old alt-root crash was a toolchain modulo
   miscompile, fixed in the gcc-cross-amix wrapper; see `heirloom/AMIX-PORT.md` item 0). A full
   base-set `-R` install on real hardware is still unproven, and constraints 1 and 2 still bind.

4. **Everything installs under the parallel prefix `/usr/apkg`, never over stock.** User tools go
   to `/usr/apkg/bin`, sadm helpers to `/usr/apkg/sadm/install/bin`. Stock `/usr/sadm`, `/usr/bin`
   and the factory admin file are never touched. `/var/sadm` is the shared database. Keeping the
   stock tools usable side by side is the rescue path.

Also worth knowing before a test run on an Amix box (details in `heirloom/AMIX-PORT.md`):
`/etc/mnttab` on Amix is tab-separated text, not binary; Amix `cpio` reads concatenated archives to
EOF with no trailer stop; Amix shared-libc `getpwnam()` crashes on first call, so `compat/`
replaces the passwd/group lookups with direct text parsers; long engine operations over telnet
need `at`-batch runs (a session hangup kills them) and a command timeout of at least 300 s.

## The vendored engine

`heirloom/` is upstream-derived source (heirloom-pkgtools, aflat HEAD, pkgtools 1.12) under CDDL
1.0. Edit it deliberately, keep every upstream licence header intact, mark each Amix deviation
with an `AMIX PORT:` comment at the site and record it in `heirloom/AMIX-PORT.md`. Files you modify
carry the CDDL "Portions Copyright" line below their CDDL header.

## Building and testing

The host build and every test suite run on a plain Linux host, from `userland/pkgtools`:

```
heirloom/build-host.sh                               # host engine + compat tests; first
bash tools/repo/tests/run-tests.sh                   # bash, not sh
(cd src/apkg          && make test)                  # apkg host suite
(cd src/apkg          && sh tests/nohttp-variant.sh)  # the FILE+RAW, no-sockets build
(cd src/contents-fsck && make test)
sh tools/migrate/tests/run-tests.sh
bash src/conffile/tests/run-tests.sh                 # the conffile class (fakeroot)
bash src/apkg/tests/conffile-e2e.sh                  # apkg's config-file handling (fakeroot)
sh src/apkg/tests/kbootset-consumer.sh               # against amix's kernel/dlm
```

Run them; they are fast and they catch real regressions. The Amix (m68k) targets need the
`m68k-cbm-sysv4` cross toolchain, gcc-cross-amix at amix's `toolchain/gcc-cross-amix.pin`. Set
`GCA` to its `build/` directory, as for the rest of amix; the build scripts source `$GCA/env.sh`
(`AMIX_CROSS_ENV` for the heirloom scripts and `CROSS_ENV` for contents-fsck still name an
`env.sh` directly, and `AMIX_SYSROOT` the populated sysroot). The cdfs package
(`build-packages.sh --cdfs`) reads an amix-cdfs checkout named by `CDFS_REPO`, by default one
beside the amix checkout.

## Licensing boundary

Stock Amix and its SVR4 `pkg` internals are Commodore's. Describe their behaviour, but never commit
Amix source, manuals, binaries, tapes or disk images; refer to factory material by name, checksum
and pointer. The extracted install tape (`hdf/tape21/`) and all disk images are gitignored. New
files of our own are MIT (see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE)).
