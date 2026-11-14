# media — the Amix installer media

The installer of an Amix release and the tools that master its media:

| Medium | What it is |
|---|---|
| `amix-<v>-install.iso` | the install CD for every target, both kernel lines (68030; 68040/68060): it boots the installer into a RAM disk and carries the stock set, the base packages and the kernel-space packages. Targets: the Z3660 SCSI, an A4091 or A4092, the A3000's and the A4000T's SCSI, the A4000's or A1200's IDE port, a Buddha's or Catweasel Z-II's IDE ports (the new controllers tested in emulation only) |
| `amix-<v>-netinstall.iso` | the network installer: the same boot, with the packages read over the network from the package repository |
| `amix-<v>-boot-k30-1.adf`, `-2.adf` | the floppy pair that boots the installer on a 68030 machine without a bootable CD drive |
| `amix-<v>-boot-k46-1.adf`, `-2.adf` | the same for the 68040/68060 line |
| `amix-<v>-boot-z3660.hdf` | the same boot as an AmigaOS disk, for a Z3660 without a floppy drive |

Amix is Commodore's 1991 SVR4/68k Unix for the Amiga. The installer (`src/installer/setup.sh`, the
interview; `install.sh` and `l11.sh`, the driver) lays a release down on a fresh disk from the
universal profiles in `profiles/`, and the first-boot payload (`payload/firstboot/`) finishes the
machine's identity on its first boot. `docs/installer.md` has the driver step by step.

## Building

The media are a step of `make dist` (docs/BUILDING.md at the top of the repository): its `media`
step runs `media/build.sh` in the media container (`toolchain/Containerfile.media`), after the steps
whose outputs it reads. By hand, in that container or on a host with the same tools
(`media/TOOLS`):

```sh
AMIX_TOP=$PWD AMIX_SYSTEM=<amix-system> GCA=<gcc-cross-amix>/build RELEASE_PUBLIC=1 sh media/build.sh
```

### The interface

`media/build.sh` takes no arguments. It reads only these:

| Input | From |
|---|---|
| `out/kspace/catalog`, `catalog.md5`, `pkgs/*.pkg`, `beside/amix-cdboot` | make dist's `kspace` step: the kernel-space packages and the CD boot program |
| `out/release/<v>/catalog`, `pkgs/*.pkg`, `pkgs/stock/*.pkg` | make dist's `release` step: the release tree (exactly one `<v>`); the base packages' rows and datastreams, and the stock set the CD carries |
| `out/apkg/APKG-*.pkg`, `APKGENG-*.pkg` | make dist's `apkg` step |
| `$AMIX_SYSTEM/usr/sbin/syslogd` | the amix-system checkout: the 2.1c daemon, held to its sha256 |
| `$GCA/env.sh` | gcc-cross-amix (`toolchain/gcc-cross-amix.pin`): zenmac and setclk, the static package engine, the apkg clients |
| `kernel/dlm`, `userland/pkgtools` at the checkout's `HEAD` | `git archive`, built under `out/build/media`: the host kbootset, mkstore and lsstore, the disc's static pkgadd, pkgtrans, pkginfo, pkgchk, contents-fsck, pkginstall and apkg, the host pkgtrans and apkg, the netinstall image's HTTP apkg |
| `media/inputs/ramdisk-*.distfile` | the four RAM-disk images, by sha256 (below), through `toolchain/fetch-distfile`: `out/cache`, `AMIX_DISTFILES`, then the URL |
| `ROM_MANIFEST`, `PRIVACY_PATTERNS` | the content check's ROM register and private names, never in this repository; or `RELEASE_PUBLIC=1`, its public tests only |

It writes `out/media/`: the seven media, `SHA256SUMS` and `MEDIA.txt` (the inputs by sha256, every
medium's size and sha256, the tool versions). Scratch, logs, the master stage and
`RELEASE-CHECK.txt` go to `out/build/media/`, temporary files too (`TMPDIR`). Nothing outside the
checkout is read but the inputs above. Exit 0: built and clean; 1: failed; 3: an input missing,
named on a `[MISSING] media:` line (make dist goes on and names the gap at the end).

For development on a host whose gcc-cross-amix is not the pin's (its zenmac and setclk are other bytes),
`MEDIA_PAYLOAD=<dir>` takes those two from a directory instead; they are held to the same sha256 pins, and
`INPUTS` and `MEDIA.txt` say so (`payload-from-elsewhere`). make dist never sets it.

`conf/base-packages.conf` names the userland packages the install CD carries beside the stock set,
and the sets that take them.

### The RAM-disk images

The installer runs from a RAM disk: a small s5 (68030) or ufs (68040/68060) filesystem holding the
stock miniroot, its patched `init`, the profile script, `modadmin`, `kbootset` and the boot- and
demand-class modules of its generation (the netinstall image also the network userland and a
trimmed `/install`). No host tool writes those filesystems, so the images are authored on an Amix
system by the test bench, and the media take them as pinned inputs: `media/inputs/ramdisk-*.distfile`
(the URL and the sha256), the same form as the toolchain's distfiles. `build-ramdisk-cd.sh` checks
each image against the generation it composes from `out/kspace` (every boot- and demand-class
module, byte for byte); a kernel-space change that moves one of them stops the build with exit 3
until new images are made and pinned.

### Reproducibility

Every date on the media is `SOURCE_DATE_EPOCH`, else the commit time of `HEAD`; the locale and the
zone are fixed. The same inputs give the same bytes. Built from the 1.1 inputs (make dist at the
1.1 commit, the 1.1 images, `SOURCE_DATE_EPOCH` of that commit), six media are byte-identical to the
published 1.1 files; the install CD differs in one file, `/install/l11/INPUTS`, the record of its
inputs, which names make dist's outputs where the 1.1 record named the earlier builder's. With
that file's 1.1 text the same tree masters to the published bytes.

Tool versions move bytes: the ISOs name xorriso's version in their Preparer field (1.1: xorriso
1.5.6), the Z3660 boot disk is laid out by amitools (1.1: 0.8.1), and zenmac and setclk are held to
the sha256 that gcc-cross-amix at its pin produces.

## Checks

```sh
python3 media/tests/installer-selftest.py       # the installer, payload and media tools; no box, no media
python3 media/tools/iso-selftest.py
bash media/tools/build-release-media.sh --selftest
```

Each medium also passes amix's `tools/release-check` (no Kickstart or board ROM, no known-bad
module, no private address, name or secret), `tools/medium-address-check.sh`,
`tools/public-text-check.py` and `tools/sidecar-path-check.sh` as it is built.

The installs themselves are tested on an emulator matrix and on real machines by a separate test
bench, which runs these media and the checks that need its own files (the miniroot it authors,
its machine profiles and reference installs).

## Licensing

The tooling, documentation and configuration here are MIT-licensed (`LICENSE` at the top of the
repository); `NOTICE` has the trademark wording and the third-party material.

On 2026-09-23 Amiga Corporation approved distributing the Commodore Amiga binaries this project
builds on. The media carry Commodore's stock packages and files from make dist's release tree and
the amix-system checkout; none of them is committed here, and the stock setclk source is read
from its package at build time, never committed.

## More

- `CHANGELOG.md`: what each release's media contain.
- `docs/releases/1.1.md`: the 1.1 release record.
- `docs/installer.md`: the installer driver, step by step.
- `docs/install-iso.md`, `docs/miniroot.md`: the install CD and the RAM-disk miniroot.
- `docs/blizzard-fp.md`: the FP-free ufs tools for FPU-less 68060 boards.
- `docs/address-by-card.md`: one image for several Z3660 machines (`zen0`'s address by the card's MAC).
- `HISTORY-MAP.txt`: the commit ids this history had before it moved into amix.
