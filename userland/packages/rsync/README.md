# rsync — rsync 3.1.3 for Amix

`rsync` under `/opt/amix/bin`, with its man pages (`rsync.1`, `rsyncd.conf.5`). It covers both
roles:
- the client, over a remote shell (`-e`) or to a daemon (`rsync://`);
- the daemon itself (`rsync --daemon`).

The stock system has no rsync.

    sh recipes/common/pkgbuild.sh recipes/rsync      # build + roll (interim driver)
    sh tools/pkg-smoke/prepare.sh recipes/rsync      # stage the on-box acceptance

Package: `rsync`, catalog name `rsync`, category `network`, set `extra`, GPL-3.0-or-later
(COPYING ships in `/opt/amix/doc/rsync`). Built with GCC 14 (`-m68020-60 -mno-strict-align
-O2`).

## Version: 3.1.3

The version is set by interop (registry/rsync.yaml, ROADMAP.md §3):
- rsync ≤ 2.5.7 caps at protocol 30 and has no `--protocol`, so a modern peer cannot talk to
  it at all.
- 2.6.3, the archived Amix build, speaks protocol 29 and builds the whole file list in RAM.
- 3.1.3 speaks protocol 31 and recurses incrementally.
- ≥ 3.2 adds the openssl/xxhash/zstd/lz4 dependency surface.

Source: `https://download.samba.org/pub/rsync/src/rsync-3.1.3.tar.gz`, sha256 `55cc554e…0800c0`.
GPG: good signature from Wayne Davison (DSA key `0048C8B026D4C96F0E589C2F6C859FB14B96A8C5`,
the maintainer).

## Patches

| Patch | Why |
|---|---|
| `01-ftruncate-freesp-tail.patch` | **Found on the box: the stock kernel panics.** `ftruncate` is `fcntl(F_FREESP)`. When it shrinks a file larger than its direct blocks (~96 KiB) to an EOF that is not block-aligned, inside the block holding the old EOF, `ufs_itrunc` → `pvn_vptrunc` zeroes the tail and `bzero` takes a bus error: KERNEL FAULT, box down. Every shrinking `--inplace` update ends in exactly that call. The first bench run died at the smoke's `--inplace` step. Probes (below) set the boundary. `do_ftruncate` now cuts at the 8 KiB block boundary below the new EOF, which leaves no tail to zero, and writes the bytes up to the new EOF back. The `--inplace` file is opened `O_RDWR` so they can be read first. |
| `02-getaddrinfo-numeric-host.patch` | rsync's bundled `getaddrinfo` is used, because the box has none. It passed a numeric host like `192.0.2.1` to `gethostbyname`. AMIX's searches `/etc/hosts` only (truss) and fails on a dotted quad, so `rsync://192.0.2.1/` died with rc 10 while an `/etc/hosts` name worked. A dotted quad is now parsed with `inet_pton` first, as real `getaddrinfo` does. |

**The ftruncate probe**, emulated golden 030, kernel 46759dcc, ufs, `st_blksize` 8192:
- **Panic:** 480017→480000, also after close+sync+reopen; 480017→477000 (same block, other page); 110017→110000.
- **Survive:**
  - 90017→90000 (inside the direct blocks);
  - small files;
  - shrinks into an earlier block (200000→150000, 480017→470000);
  - block-aligned cuts, including 480017→475136 and 110017→106496, the start of the old last block;
  - extensions.

The call path was symbolized by the kerntools station: `fcntl` → `ufs_space` → `ufs_freesp` → `ufs_itrunc` → `pvn_vptrunc` → `bzero`. Evidence: `Amigaux/tmp/2026-10-30-rsync/ftprobe/`.

## Configure (`build.sh`)

- **Bundled zlib and popt** (`--with-included-zlib --with-included-popt`, D8). rsync's zlib is
  its own modified copy, and the compressed stream a peer expects is the one it makes.
  rsync's bundled `getaddrinfo`, `inet_ntop`/`inet_pton` and `snprintf` are used too, because
  the box has none of the first three and configure cannot run the C99 `vsnprintf` test. rsync
  then maps `snprintf`/`vsnprintf` to its own `rsync_*` copies, which never clash with
  libamixc99's.
- **Off:** `--disable-largefile`, `--disable-ipv6` (no IPv6 stack), `--disable-locale`,
  `--disable-iconv[-open]` (no iconv), `--disable-acl-support`, `--disable-xattr-support`.
- **`socketpair` stays off.** libsocket.so exports it, but configure's run test answers
  "cross". rsync then uses `pipe()` for its local child pairs. SVR4 pipes are full-duplex
  STREAMS, and that path is what the bench proved.
- **`ac_cv_func_vfork=no`**: `vfork` is only a static member of `usr/ccs/lib/libc.so` (grimoire).
- **D3**: `amix-pwgr.o` is compiled in `pre_configure` and put in `LIBS`. The binary defines
  `getpwnam/getpwuid/getgrnam/getgrgid` itself (asserted in `stage`). They are used for
  `-o/-g` by name, `--chown`, and the daemon's `uid =`/`gid =`.
- **`MAKE_CFLAGS=-include amix-decls.h -I./zlib -I./popt -DHAVE_CONFIG_H`**:
  - The prototypes cover the socket calls, `select`, the syslog family, `gethostname`, and now
    `seteuid`/`setegid` (the daemon's `setuid` path). The last two come from the static member
    `seteguid.o` of `usr/ccs/lib/libc.so`: trap #0, SYS 141/136.
  - The rest is there because rsync's configure writes its include paths and `-DHAVE_CONFIG_H`
    into CFLAGS itself, and the driver's make CFLAGS replace that.
- **`--with-nobody-group=nobody`** (asserted in `post_configure`): configure reads the build
  host's `/etc/group` for the daemon's default gid. The box has `nobody`/`nobody` (60001) and
  no `nogroup`.
- **Defaults left as upstream:**
  - `--rsh` is `ssh`, which the dropbear port will provide. Until then, give `-e rsh`:
    `/usr/bin/rsh` on the box is the setuid BSD remote shell, not the restricted shell.
  - The daemon's config is `/etc/rsyncd.conf`; nothing is installed there.
  - `--rsync-path` is `rsync`, a name the *remote* side resolves.

## Linkage

`NEEDED`: `libsocket.so`, `libnsl.so`, `/usr/lib/libc.so.1`, the stock networking every bench
and install image carries. `-lsocket -lnsl` come from configure.

## Limits

- **FPU**: the gate counts 528 FPU instructions, none of them a 040/060-only form, so this
  package needs an FPU or the kernel's FPE on an FPU-less 68LC040/LC060.
  - Most sit on reporting paths: `rprint_progress` (`--progress`), `output_summary`
    (`-v`/`--stats` rates), `fmtfp` (`%f`), and libgcc's soft-float/long-double helpers.
  - But the bundled `snprintf`'s `new_chunk` stores a long double 0 on every formatted
    message. So every run touches the FPU, the same class as the coreutils FP-DOPRNT
    constraint. It is recorded, not patched.
- No files over 2 GB, no ACLs or xattrs, no `--iconv`, no IPv6.
- `--inplace` needs read permission on the destination file (it is opened `O_RDWR`, patch 01).
  root always has it.

## Gates (build time)

All of these passed on the 2026-10-30 build:
- strict flags, with `-mno-strict-align` on 64/64 compile lines;
- libacompat not linked;
- prototype == staged tree (14 paths);
- no empty file;
- every undefined symbol defined by its `NEEDED` libraries;
- D3;
- the 060 gate with all three scanners, on the tree and on the datastream: 247 long mul/div,
  none 64-bit, which covers the MD4/MD5 and rolling-checksum code (registry LC060-MUL64);
- no 040/060-only FPU form;
- no ll printf conversion.

## Test result

See `tests/smoke.sh`, run as root on the box. `tests/host.sh` is the host side (bash, on the
bench host), run by `tools/pkg-smoke/host-extra.sh`:
- it starts the host's own rsync 3.4.x (protocol 32) as a daemon on the bench bridge;
- a background peer waits for the box's daemon, pulls from it, pushes to it, and hands the box
  the `sum -r` lists of what it received;
- every verdict is a `RES` line on the box.

The checks:
- **Local:** `-aH` copies with mode, mtime, symlink, hard link, owner and group by name;
  `--chown=bin:sys`; `--numeric-ids`; `-n --itemize-changes`; `--delete --backup`;
  `--exclude`; the quick check versus `--checksum`; a local `--no-whole-file` delta, plus
  `--inplace` and `--partial --sparse`.
- **Remote-shell protocol:** a local "rsh" script runs the far side (`--server`). The checks
  push, pull with `-z`, and send a `-z` delta.
- **Against the host daemon:**
  - the module list;
  - a pull of 1500+ files (with a `ps -el` sample of the processes);
  - a delta pull of a 1 MiB file with 4 KiB changed, so a little-endian sender feeds the
    big-endian receiver's checksums;
  - a `-z` pull;
  - `--protocol=29`;
  - a `-z` push and a delta push.
- **The box's daemon** (port 873, `use chroot = yes`, `uid = root`): the host pulls the box's
  tree and pushes one back, and the `sum -r` lists from both sides must agree.

- **Box's daemon, default uid/gid:** a module with no `uid =`/`gid =` serves a file over
  loopback, as the built-in nobody/nobody.

**Bench, 2026-10-30: PASS.** Run on the emulated golden 030 (rig row E1: A3000, 64 MB,
bench-golden kernel 46759dcc), slot 1, rig-run 20261030-102808. The peer was the host's rsync
3.4.1 (protocol 32).
- **Install and removal:** the pushed files matched MANIFEST.sum. Stock `pkgadd` rc 0 installed
  6 files, `pkgchk` rc 0, smoke 44/44, stock `pkgrm` rc 0, and no contents-database line was
  left.
- **Package:** `rsync-3.1.3-1.pkg`, md5 `192e5bbe0973acfaac248d4dd9ba1669`, 685568 bytes.
- **Binary** (`sum -r` / bytes): rsync 31659/394936.
- **Memory:** during the 1500-file pull, `ps -el` showed SZ 928 and 1070 pages for the two
  receiver processes, about 1.9 and 2.1 MB at 2 KiB pages (registry: observe, not assume).
- **Evidence:** `Amigaux/tmp/2026-10-30-rsync/run4/E1/`.
- **Earlier runs:**
  - run1 panicked the kernel at the `--inplace` step (patch 01; `probe1/` pins the step,
    `ftprobe/` the geometry);
  - run2 passed everything but the host daemon (patch 02; `cprobe/` holds the truss);
  - run3 passed 43/43 before the nobody-group pin and its check.

Not run: real 68030/68060 hardware, an FPU-less part, the 040/060 kernel line, and rsync over
`rsh` to a real remote host.
