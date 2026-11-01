# heirloom-tar — Heirloom tar as the system's tar

The Heirloom Toolchest's tar, Gunnar Ritter's SVR4-style tar from Unix 32V,
installed as `/usr/sbin/tar` in place of the tar Amix shipped in 1992.
`/etc/tar` stays a symbolic link to it, and it reads the stock
`/etc/default/tar` as it is. Its page is `heirloom-tar(1)`, and `man tar` shows
it once amix-base's `man` reads `replaces.d` (1.0-24).

    sh build/pkg/pkgbuild.sh userland/packages/heirloom-tar      # build + roll (host)
    sh build/dist.sh recipes/heirloom-tar                        # the same, in the build container

Package: `heirtar`, category `archive`, set `base`, essential. Licences: tar.c
is Caldera's 2002 BSD-style licence with the advertising clause ("This product
includes software developed or owned by Caldera International, Inc."); Ritter's
changes and the libcommon files are under his zlib-style licence; `port/` is
MIT. All three texts are in `/opt/amix/doc/heirloom-tar/`. Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`). It depends on nothing.

## Why replace the stock tar

The stock tar (45180 bytes, Feb 20 1992) crashes when root extracts a ustar or
GNU archive whose owner or group name the box lacks. GNU `--numeric-owner`
archives count too, since their names are empty. It prints `problem reading
passwd entry`, then reads the uid through the failed `getpwnam` result and dies
with `SIGSEGV` after the first entry, the top directory (the grimoire's
quirk 96). That covers most
tarballs made on another system. Heirloom tar has no such path: its only name
lookups check for failure.

Measured with the stock tar on four emulated systems (k30 kernels -68 and
-63, k46 kernels -57 and -52), as root:

- An archive whose names are absent here, or empty, kills it with exit 139
  and a core before it writes a single file on three of them. On the k46 -52
  image it extracts, but gives every file to root (0/0).
- It reads no GNU long-name entries and no pax headers. It stops with
  `directory checksum error`, exit 2, after 4 of 9 files. Its `tf` shows the
  `././@LongLink` entry and the name cut at 100 bytes.
- v7 archives and ustar archives with names it knows extract correctly, with
  the names mapped to the local ids.

Heirloom tar extracts all eight forms on all four systems with exit 0 and no
core.

## Version: Heirloom Toolchest 070715

070715 is the toolchest's last release (`tar.sl 1.177`, 4/14/07), from
<https://downloads.sourceforge.net/project/heirloom/heirloom/070715/heirloom-070715.tar.bz2>.
That is 1000080 bytes, sha256 `eb33f70b…a30f`, and its MD5 matches the one
SourceForge publishes. Our copy is the amix-distfiles release `heirloom-070715`.
The tarball holds the whole toolchest; the build compiles only `tar/tar.c` and
the nine libcommon files tar calls.

Why this tar: it is SVR4 tar's own lineage, with the same keys, the same
`/etc/default/tar` and the same habits. It also reads what modern tars write:
GNU long names and large numbers, pax headers, and gzip or bzip2 compressed
archives, which it pipes through `gzip -cd` or `bzip2 -cd` from `PATH`. GNU
tar 1.14 (the `gtar` package) stays as `/opt/amix/bin/tar` for those who want
GNU's options.

## Porting

### Build (`build.sh`, `STYLE=hooks`)

- **The objects:** tar.c and libcommon's `ib_*` line reader (for
  `/etc/default/tar`), `getdir` (SVR4 `getdents`), `asciitype` and `sysv3`.
  Plus `port/amix-compat.c` and the framework's `amix-pwgr.c`, linked
  dynamically against libc and `-lgen` (for `basename`). The binary is 54 KB
  stripped; the stock one is 45 KB.
- **pwgr:** `build/pkg/common/amix-pwgr.c` defines `getpwnam`, `getgrnam`,
  `getpwuid` and `getgrgid` inside the binary. tar never reaches the stock
  shared libc's passwd code, whose first `getpwnam` of a process crashes
  (`userland/packages/docs/porting.md` 3.1).
- **`port/`:**
  - SVR4.0 has no `<inttypes.h>`, `<wchar.h>` or `<alloca.h>`.
    `port/include` supplies them: `<stdint.h>`; `wchar_t` from `<stdlib.h>`
    and a `wint_t`; and GCC's built-in `alloca`.
  - `amix-compat.c` adds `strtoll` and `atoll` (C99 behaviour: base 0 and
    2–36, `ERANGE` on overflow, no signed overflow inside), and `mkstemp`
    (`mktemp(3C)` then `O_CREAT|O_EXCL`, mode 0600, retried on a race).
  - `amix-compat.h` makes `fseeko` `fseek`, since `off_t` is a long and there
    are no large files, and sets `SSIZE_MAX` to `INT_MAX`.
- **The paths compiled in:**
  - `TARDFL=/etc/default/tar`.
  - The `u` key sorts its list with `/sbin/sh -c 'PATH=/usr/bin:/usr/bin:$PATH; sort … | uniq …'`,
    which uses the stock `sort` and `uniq`.
- **Warnings:** tar.c's own `-Wparentheses`, `-Wswitch` and one
  `-Wint-in-bool-context` (`volsize % TBLOCK*j`, upstream's expression, used
  only with `k`) are left as upstream wrote them. GCC 14 reports nothing else.

### Patches

1. `01-amix-no-tape-ioctls.patch`: Amix has no `<sys/mtio.h>` and none of
   SVR4.2MP's tape headers. Like HP-UX and AIX, it gets no tape block-size
   probe: tar seeks with `lseek` and never backspaces a tape by ioctl. Give a
   tape's blocking factor with `b` or in `/etc/default/tar`.
2. `02-owner-names-as-stock.patch`: owners on extraction the way the stock
   tar sets them (below).
3. `03-long-long-formats.patch`: the stock libc's printf family reads `%lld`
   and `%llo` as `%ld` and `%lo`, and its `sscanf` stores 32 bits into a long
   long. Every such conversion now goes through `snprintf`/`vsnprintf`
   (libamixc99, which formats long long). The device numbers are read with
   `strtoll`. Without the patch, the header's size field gets the
   upper half of the 64-bit size, which is 0, so every member is recorded as
   0 bytes long. On the box, the unpatched build wrote `hello` (12 bytes) and
   `d/m6` (600000) as 0 and 0. Such an archive extracts as empty files. The
   stock tar, which keeps sizes in a `long`, writes them correctly. The
   packaging gate's ll-printf check found it (`AMIX_LL_PRINTF_REVIEWED` records the review).

### Owners on extraction

Upstream Heirloom tar always restores the archive's numeric uid and gid and
ignores the names. The stock tar, for a ustar or GNU header, uses the local id
of the user and group names. Ids differ between systems (bin is 1 on Linux and
2 here), so the two disagree on most archives made elsewhere. With patch 02,
root extracting without `o` gets:

| Header | Owner, group |
|---|---|
| v7 (numbers only) | the numbers |
| ustar or GNU, a name that exists here | that name's local id (the stock behaviour) |
| ustar or GNU, a name this system lacks, or an empty name | the numbers (stock crashed here) |

Each name is looked up once per run (a 16-entry cache per kind), because
`getpwnam` reads `/etc/passwd` from the top every time. `tv` listings show the
numbers in the header, as before. Other users, and `o`, get the files as their
own, as with stock.

### Install

The shape was measured with stock `pkgadd` on the 1.1 images, both lines.
The prototype keeps the stock core package's entries exactly:

    /usr/sbin/tar f none 0555 bin bin    (core: f none 0555 bin bin)
    /etc/tar=/usr/sbin/tar s none        (core: s none)

- Install it with `apkg`, which drives the engine's pkgadd. pkgadd lays
  `/usr/sbin/tar` as a new inode. After that, `pkgchk -l` names both `core`
  and `heirtar` for both paths, and core's entry records Heirloom's size and
  sum. Under `-n` the stock pkgadd ignores the admin file and stops at the
  shared path ("suspended (interaction required)"). Without `-n` it asks
  whether to install the conflicting files, so a person has to answer.
- Changing an object's type would leave the old file in place silently, so
  every type is kept.
- **The package is never removed.** It is `ESSENTIAL=yes`, so apkg refuses
  (exit 5). A plain `pkgrm` succeeds, but leaves `/usr/sbin/tar` and
  `/etc/tar` in place, since core still claims them, so the file keeps
  Heirloom's bytes. Only the docs and the man page go. An older apkg without
  the essential check removes it the same way. There is no stock copy to
  restore: amix-system has none.
- The stock `/etc/default/tar` is read as it is. Heirloom reads `archive=` and
  `archive0=`…`archive9=` (device, blocking factor, size in KB, `n` for not a
  tape), the same fields as stock, and `order=` (below). It ignores the
  stock file's `archivef=` line. `tar t7` (`archive7=./tarfile`) reads the
  same 13 entries with both tars.
- The installer and the first-boot payload never call tar (their sources
  have no tar call; the grep of the 1.1 images is under Acceptance).

**Manual page.** The page is `/opt/amix/man/1/heirloom-tar`, because gtar owns
`/opt/amix/man/1/tar`. The file `/opt/amix/man/replaces.d/heirtar`, with the
line `/usr/sbin/tar 1 heirloom-tar`, tells amix-base's `man` (from 1.0-24)
that it is the page of the binary `PATH` runs as `tar`. So `man tar` shows
it, gtar's page when `PATH` runs gtar, and the stock page never for a
replaced binary. The whatis line names both `tar` and `heirloom-tar`.

### Not here

- No `pax` or `cpio` (other Heirloom tools); the system has its own `cpio`.
- No tape block-size probe (patch 01).
- Archives of files over 2 GB: SVR4.0 has no large files.

## Differences from the stock tar

Measured on the box with both tars on the same archives and the same tree.

**Reading.**
- `tf` gives the same names for v7 and ustar archives. For GNU and pax
  archives Heirloom gives the real long names, and stock gives
  `././@LongLink` (or a `PaxHeaders` entry) and the name cut at 100 bytes.
- `tvf` gives the same owners, sizes and times. Heirloom marks directories
  `d` and symbolic links `l` (with size 0), where stock shows `-` for both,
  and the link's target length as its size.
- Extraction: Heirloom prints nothing. Stock warns `file permissions have
  changed` for every regular file it writes, though the modes come out
  right with both.
- Owners as in the table above. Stock crashes or gives root the files where
  Heirloom keeps the numbers.

**Writing** (`tar cf` of one tree, compared field by field). Name, uid, gid,
user and group names, size, mtime, type, link name, `ustar`/`00` magic and
the prefix split of a long name are the same. The differences:
- The mode field holds the permission bits only (`0000644`), as POSIX ustar
  says. Stock adds the file type bits (`0100644`, `0040755`, `0120777`).
- devmajor and devminor hold the device numbers of a device file and 0 for
  anything else. Stock writes the file system's own device (18, 22 here) in
  every header.
- Directories come after their contents (`order=post`, Heirloom's default)
  and are named without a trailing slash. Stock writes `./d/` before the
  files in it. `order=pre` in `/etc/default/tar` gives stock's order.
- An archive in a file is written in records of 16 blocks (the file
  system's 8 KB block) and stock's in records of 20. So the same tree is
  688128 bytes against stock's 696320. `b` sets the record size.
- The header checksum differs only because of the fields above.

Each tar reads the other's archive completely, with every file's sum, mode
and links right.

## Acceptance

**Emulator, 2026-11-01: PASS.** Run on four emulated systems (Amiberry; the
emulator's timings are not the hardware's):

| System | Kernel | Checks |
|---|---|---|
| 68030 development install | k30 68030-261101-68 | 30 ok |
| 68060 development install | k46 68060-261101-57 | 30 ok |
| 1.1 image, 68030, after first boot | k30 68030-261031-63, amix-base 1.0-12 | 31 ok |
| 1.1 image, 68060, after first boot | k46 68060-261031-52, amix-base 1.0-12 | 30 ok |

- **Package:** `heirtar-070715-1.pkg`, 90624 bytes, md5
  `d27bb2c4c504edf01e14794f052d294a`, sha256 `19cac716…85ec`. Two rolls in
  the build container (gcc14 43825b2) are identical, and every gate passes.
  The emulator runs used the roll before the `order=` man page fix
  (md5 `5b731019…2fb2`). Its payload differs only in that page; the tar binary
  is byte for byte the same.
- **Install:** the engine's pkgadd rc 0 and `pkgchk heirtar` rc 0 on all
  four. `/usr/sbin/tar` became 54416 bytes, `sum -r` 37999 (stock: 45180,
  02056). `pkgchk -l` names core and heirtar for `/usr/sbin/tar` and
  `/etc/tar` (the 68060 1.1 image's `pkgchk -l -p` printed nothing at all).
  `type tar` is `/usr/sbin/tar`.
- **Extraction as root:** all eight archives (v7; ustar and GNU, each with
  names present, absent and empty; pax) with exit 0, no core, no message.
  Every file's `sum -r` matches the host, and so do the modes (0600, 0750
  directory), the hard link (2 links), the symbolic link and the owners in
  the table under Owners. `xof` gives root the files, and as user bin `xf`
  gives bin.
- **Listings:** `tf` names every member of every archive. `tvf` as under
  Differences.
- **Writing:** `tar cf` of the tree is read back by Python's `tarfile` with
  every size right. Each tar extracts the other's archive completely.
  `tar t7` reads `archive7=./tarfile` from the stock `/etc/default/tar`.
  The build without patch 03 writes every size as 0.
- **Removal:** on the 1.1 images apkg refuses (exit 5, essential). Then
  `pkgrm` rc 0 leaves `/usr/sbin/tar` with Heirloom's bytes and `/etc/tar`,
  and removes the docs and the man page. The development installs' apkg
  removed it without refusing, with the same result.
- **Man page:** with amix-base 1.0-24 installed, `man tar` and
  `man heirloom-tar` show `HEIRLOOM-TAR(1)`, and `man -f tar` lists both
  heirloom-tar(1) and the stock tar(1).
- **Callers:** on both 1.1 images, a search of every file (text whole,
  binaries through `strings`; /proc, /dev and tmp aside) found no script or
  program that runs tar. The only mentions are the package database, man
  pages and docs, the GNU tar texinfo and find2perl, and gtar and tar
  themselves. The installer and the first-boot payload have no tar call
  either.

Not run: real 68030/68060 hardware, a tape, and the `r`, `u` and `k` keys.

The tests: `tests/make-archives.sh` makes the archives with GNU tar on the
build host (reproducible: fixed seed, names and times). `tests/box.sh` runs on
the box as root and records raw facts. `tests/check.py` judges them on the
host.
