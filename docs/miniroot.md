# The install miniroot (Installer-NG Wave 5.2, install script W4)

The **miniroot** is the tiny root filesystem the install kernel mounts to bring
the installer up single-user, mount the install CD, author the target
filesystems, and hand off to the CD-resident package engine. It is built from
the stock Amix 2.1 miniroot plus a handful of additions, and produces the two
packagings the two W5.1 kernels expect.

Since **wave W4** it also carries **our own `/etc/profile`** — the install
script the console login shell sources, and the first thing anybody using this
installer ever sees. See *The install script* below.

## Thin-miniroot decomposition

The install engine — the ~399 KB **static** `pkgadd` and the 27-package catalog —
is **CD-resident, not in the miniroot** (the plan's decomposition). The miniroot
carries only what is needed to boot, mount the CD (cdfs), author/label/fsck the
target s5 filesystems, and shim into the CD engine. That keeps it inside the
880-block (901 120-byte) floppy with room to spare (~43 blocks / ~48 inodes free).

## What is in it — `miniroot/miniroot.proto`

`miniroot/miniroot.proto` is the **authoritative, hand-reviewed manifest**: one
line per object (type, mode, owner, group, source, path). `source` records the
provenance of every entry:

| source | what | how placed |
|--------|------|-----------|
| `stock-miniroot` | 198 objects verbatim from `floppies/orig/amix_21_root.adf` (sh, libc.so.1, the miniroot mount/umount, `mkfs_s5`/`fsck_s5`, mknod/dd/ls/cat/cpio, /dev nodes, …) | the build starts from a **byte copy** of that image, so these are preserved untouched |
| `installng` | `/etc/profile` — **our install script** (`src/miniroot/profile`, W4) | copied in at the stock file's own 0777 root:root, **replacing** the stock 19,351-byte install script. The only stock-sourced object the build overwrites |
| `core-2.1.pkg` | `/etc/passwd`, `/etc/group`, `/usr/lib/fs/s5/labelit` | extracted **byte-identical** from the repackaged `core-2.1.pkg` |
| `amix-cdfs` | `/usr/lib/fs/cdfs/mount` | the amix-cdfs `platform/amix` userland helper |
| `generated` | mount points + tool dirs (`/cdrom`, `/usr/lib/fs`, `/usr/apkg/...`) | `mkdir` during the build |
| `shim` | `/usr/apkg/sadm/install/bin/pkginstall` | a `#!/bin/sh` that exec's the CD engine |

**One `stock-miniroot` exception, opt-in.** With `MINIROOT_FP_PATCH=yes` the
build additionally rewrites `/bin/mkfs_ufs` and `/bin/fsck_ufs` in place inside
that byte copy — BLIZZARD F2-M1, see *The BLIZZARD F2-M1 FP patch* below. The
rewrite is length-preserving, so both files stay `source=stock-miniroot` in
this manifest either way; only their content differs from a genuinely
untouched copy.

## The install script — `/etc/profile` (W4)

On the stock media the interactive installer **is** `/etc/profile` on the root
floppy: init runs a console shell single-user, the shell sources `/etc/profile`,
and that script asks the questions. W4 keeps that shape exactly and replaces the
content. `src/miniroot/profile` (15,998 B, vs the stock script's 19,351 B):

1. **`echo "Amiga UNIX install script"`** — stock's banner, then stock's Ctrl-C
   trap, **installed before the first prompt**. Everything below it is escapable
   to `/bin/sh -i`, which is also the handshake `tools/install-matrix.sh` uses to
   reach a miniroot shell.
2. **The keymap menu** — stock's `/etc/id_kmap` flow, *inlined*, with exactly one
   changed label: entry **11** reads `Suomi / Svenska` (the map is still `s`;
   there is no Finnish keymap in Amix 2.1 and for this era FI == SE). Numbering,
   the `[12]` default, the excluded `usa1` and every other label — Latin-1 bytes
   and all — are stock's. The map is applied live with `/etc/sioc 5 /etc/kmap/$KMAP`
   (`usa` = bare `sioc 5`, i.e. the compiled-in map), then handed on to the rest
   of the chain **twice over**: an exported `$KMAP` and the file `/tmp/kmap`.
   `setup.sh` picks it up as `FB_KMAP`, and the driver bakes stock's one hard
   link `…/kmap/default.kmap` onto the target.
   *Stock's own `/etc/id_kmap` stays on the image byte-untouched* — inlining is
   what keeps the relabel in OUR file instead of in a modified copy of theirs.
3. **`Do you want to install or repair? [install]`** — stock, verbatim, with
   **repair mode restored**: pick a disk, pick the root partition, offer `fsck`,
   then stock's sub-shell with `PATH` reaching into `/mnt`, and `sync`/`umount`/
   `uadmin 2 0` on the way out.
4. **The source auto-probe.** Order is **hardcoded in this script** — it cannot
   come from the medium it is looking for — and it is ordered by *what can be
   tested safely first*:

   | # | candidate | what it is | how it is tested |
   |---|-----------|------------|------------------|
   | 1 | `/dev/dsk/c0d0s4` | the 5-slice self-booting **metal source disk** (slice 4 = payload; the disk this miniroot booted from) | bounded `dd` of block 0 **first**, then mount |
   | 2 | `/dev/dsk/c5d0s1` | the 2-slice **bench RAW source disk** | same |
   | 3 | cdfs `1,3` | A3000+A4091 bench + any A4091-carried drive | one mount attempt |
   | 4 | cdfs `0,2` | the A4000+Z3660 rig (`metal-a4000-z3660.profile`) | one mount attempt |
   | 5 | cdfs `1,2` | a second-HBA drive at unit 2 | one mount attempt |

   A candidate **answers** when, mounted at `/cdrom`, it presents
   `/cdrom/install/bin/setup.sh`. **Content, never a mount return code** — a cdfs
   mount can return 0 and be empty (the stale-mount case the driver already
   models), and a mount over an already-mounted `/cdrom` returns `EBUSY` while
   the source under it is perfectly readable. The **first** candidate that
   answers wins and is **left mounted**; nothing probes past a working source.
   Nothing found ⇒ stock's restart idiom (`Press RETURN to restart the
   installation script. ` + `exit 99`, and init respawns the console shell).

   ★ **One attempt per address — the retry is the operator's RETURN.**
   Bench-measured 2026-08-11: a **second** cdfs mount attempt on a unit that is
   not there **panics the kernel** (`PANIC: KERNEL FAULT … vector=0x2 (Bus
   Error)`, `pc=0x70002E8`), and an absent unit fails with the *same* `errno 5`
   a real media-change unit-attention gives — so the retry that recovers a media
   change is the retry that kills the box, and sh cannot tell the two apart. The
   probe therefore touches each address once per pass, and the media-change
   retry is the restart prompt's own RETURN, which re-probes everything once
   more. A RAW candidate is gated on a bounded `dd` before it is mounted at all,
   which is why the metal source rig never issues a cdfs probe.
5. **`exec sh /cdrom/install/bin/setup.sh`** — no argument: the medium declares
   its own base profile in `/install/profiles/BASE`. From there the interview
   composes `/tmp/answers.profile` and execs the driver with `stdin` from
   `/dev/null` (METAL-FIX.3). The profile never execs the driver itself.

**The space budget.** The floppy is 880 blocks and there is no second one. The
smaller script *frees* space: **42 → 46 free blocks** against the W5.2-era NG
miniroot (stock, with its own bigger script and none of our additions, has 72);
free inodes are unchanged. `build-miniroot.sh` prints the stock→built delta on
every run, so a change that eats the headroom shows up in the build log instead
of at the next `cp: No space`.

**Latin-1, not UTF-8.** The console is 8-bit ISO-8859-1 and the keymap labels
carry `0xE7`/`0xF1`. `src/miniroot/profile` is stored in Latin-1; the builder
refuses to ship it otherwise, and `installer-selftest.py` audit **Y** checks the
encoding and cross-checks every unchanged label against the stock floppy's own
bytes.

**The passwd/group trap.** The stock miniroot ships `/etc/passwd` and `/etc/group`
as mode-0666 stubs. We **replace** them with core's own copies, byte-identical
and at core's declared ownership — `passwd` 0644 `root:root` (SVR4 `sum` 56704),
`group` 0644 **`bin:bin`** (sum 16701). That is what makes account ownership in
the installed system core's, not a silent host-fallback guess.

**Gate 1.** `/usr/lib/fs/cdfs/` holds **exactly one** entry, `mount`, mode 755.
The SVR4 generic `mount -F cdfs` would exec `/usr/lib/fs/cdfs/mount`; keeping that
directory a single clean entry is asserted by the self-test.

## How the CD is mounted in the miniroot — a load-bearing quirk

The miniroot's own `/etc/mount` is the **direct-`mount(2)`** miniroot tool
(`mount spec dir [nflag [fstyp [data]]]`), **not** the generic SVR4 `mount -F`
front-end — it does not exec `/usr/lib/fs/<fstype>/mount`. So the CD is mounted by
invoking the cdfs helper **directly**:

```
/usr/lib/fs/cdfs/mount <card>,<unit> /cdrom
```

cdfs addresses the drive as `<card><sep><unit>` (e.g. `1,3` = SCSI host adapter 1,
target 3) — **not** a `/dev` path; a real CD never traverses `/dev/dsk` on stock
Amix. The **first** mount after a media change returns **errno 5** (unit
attention); mount **again** and it succeeds (the double-mount quirk). `umount`
is the miniroot's own umount (`umount /cdrom`, returns 0).

The miniroot's own `mkfs_s5` / `fsck_s5` / `labelit` are the standalone s5 tools
(the installer calls `/usr/lib/fs/s5/labelit` directly — the miniroot has no
generic `labelit` front-end).

## CD convention W5.3 must match

Static `pkgadd` exec's a compiled-in `/usr/apkg/sadm/install/bin/pkginstall`. The
399 KB static `pkginstall` cannot fit the floppy, so that path is a shim:

```sh
#!/bin/sh
exec /cdrom/install/bin/pkginstall ${1+"$@"}
```

**W5.3's ISO re-master must place the static `pkginstall` at `/install/bin/pkginstall`
on the disc** (mounted at `/cdrom` → `/cdrom/install/bin/pkginstall`).

## The two packagings (one build, two media)

The miniroot filesystem is **medium-agnostic** — its `/dev` already carries the
`c0..c6` disk nodes — so the same 901 120-byte s5 image serves both:

| packaging | image | paired kernel (`../amix-kerntools/docs/miniroot-kernels.md`) | rootdev | gates |
|-----------|-------|-----------|---------|-------|
| **fd0** (bench) | `floppies/build/amix_21_root-ng.adf` (the 880-block s5 = the root ADF) + the boot floppy from `build-universal-bootfloppy.sh` | `fd0unix` (a4091 + cdfs + fixed a3091/a2091 + **probed `support.c`**), `unix.brel` sum-r **09433** (P5.4 r4, 2026-08-16 — note the LEADING ZERO, five digits; superseded: 11879 08-13, 46541 earlier) | `0x00400008` (floppy) | `rootdev-assert --config fd0unix --media floppy --miniroot`; **bench boot-proof** |
| **slice1** (metal) | `work/miniroot/miniroot-slice1-<date>.s5img`, written to an RDB `UNIX_Root` slice (DosType `UNI\1` = 0x554e4901) | `c6s1unix` (z3660scsi + z3660eth + cdfs), sum-r **50544** (P5.4 r4; superseded: 49227 r3, 00961 48-era) | `0x00480016` (C6D0S1) | `rootdev-assert --config c6s1unix --media scsi-slice --miniroot`; fsck-clean (metal boot-proof = Wave 6) |

## Building it — `tools/build-miniroot.sh`

There is no host-side s5 **writer** that can populate files, so the miniroot is
authored **on the golden build box**. `build-miniroot.sh` automates the proven
route: push a byte copy of the stock ADF, dd it onto a scratch RDB slice, fsck it
(the stock fs is marked dirty, so a pre-mount fsck is required before rw-mount is
allowed), mount rw, overlay the additions at the proto's modes/owners, sync,
umount, fsck clean, then extract the 901 120-byte image host-side from the scratch
`.hdf` (verifying the host extraction's checksum equals the on-box image's — never
FTP-GET large images, they tail-drop) and run the conformance self-test.

The scratch disk is provisioned with `mkroot.sh --no-mkfs` and attached to the
emulator at a spare SCSI unit; see the script header for the exact invocation and
the `SCRATCH_HDF` / `SCRATCH_DEV` knobs. A worked W4 invocation:

```sh
tools/mkroot.sh --out work/miniroot/scratch.hdf --size-mb 64 --no-mkfs --scsi-id 5
cp ../amix-kerntools/configs/amix-golden.uae work/miniroot/build-miniroot.uae
cat >> work/miniroot/build-miniroot.uae <<'EOF'
hardfile2=rw,DH1:<abs>/work/miniroot/scratch.hdf,64,1,2,512,0,,scsi5_a3000
uaehf1=hdf,rw,DH1:<abs>/work/miniroot/scratch.hdf,64,1,2,512,0,,scsi5_a3000
EOF
bash "$AMIBERRY_AMIX_SKILL"/scripts/amiberry-amix-up.sh work/miniroot/build-miniroot.uae
SCRATCH_HDF=$PWD/work/miniroot/scratch.hdf bash tools/build-miniroot.sh
```

Two gates worth knowing about:

* **the install script must be Latin-1** (`src/miniroot/profile`) — the builder
  refuses a UTF-8-saved file before it touches the box, because the console is
  ISO-8859-1 and the keymap labels carry `0xE7`/`0xF1`;
* **only the FINAL fsck's verdict counts.** The *pre-mount* fsck legitimately
  prints `*** FILE SYSTEM WAS MODIFIED ***` — that is it setting the dirty stock
  filesystem to `OKAY`, the entire reason it runs — so the old grep over the whole
  overlay log made the build refuse its own step 2 (fixed in W4: the log is cut at
  the final-fsck banner first).

### The BLIZZARD F2-M1 FP patch (`MINIROOT_FP_PATCH`, opt-in)

`build-miniroot.sh` reads one more build-time knob — an environment variable,
**not** a profile key (it is set on the invocation, like `SCRATCH_HDF` above,
not in a `profiles/*.profile` file; see `profiles/README.md`):
`MINIROOT_FP_PATCH=yes` (default `no`, i.e. `no`/`yes` are the only accepted
values, anything else is refused). When set, the stock ADF is work-copied
*before* it is pushed to the box, and
`tools/patch-ufs-fp.py --s5 <copy> /bin/mkfs_ufs /bin/fsck_ufs` rewrites both
binaries' floating-point display expressions as integer arithmetic —
**BLIZZARD F2-M1**, `docs/blizzard-f2m1.md` — because both are otherwise fatal
on an FPU-less 68060: `mkfs_ufs` dies at its geometry banner before writing a
single block, and `fsck_ufs` dies at its summary line, upstream of everything
that marks a repaired filesystem clean.

The patch is length-preserving — `build-miniroot.sh` asserts the patched copy
is still exactly the stock ADF's length before pushing it, and refuses
otherwise — so type/mode/owner/group and `miniroot.proto`'s object census are
unchanged either way; only those two files' *content* differs from a
genuinely untouched stock copy (87 + 211 bytes, `docs/blizzard-f2m1.md` §7's
measured figure).

**Off by default, and not yet wired into any tracked profile or the ISO
build.** The 030 line does not need it. No tracked profile turns it on today
— re-arming it is a build-invocation change, not a profile edit — and the
**installed** tree's own copies (the CD package set staged by
`tools/build-install-iso.sh`) are patched only by hand so far; this wiring
covers the miniroot alone.

### The UFS miniroot — the 040/060 line (`MINIROOT_FSTYPE=ufs`)

The 68040/68060 kernel line runs **4 KiB pages**, under which the s5 filesystem is
structurally broken, so **that line's install miniroot must be UFS** (Berkeley
FFS). `tools/lib/ufs_size.py` settled the media shape: a UFS miniroot carrying the
same install toolchain does **not** fit an 880-block floppy with stock geometry
(~56 KiB over at today's content). So the ufs miniroot normally **rides a raw `UNI\1`
slice** (exactly the source-`.hdf` shape the metal rigs already use). Since P-15 I5
(2026-10-03) there is also a **root floppy** for this line; see *The 040/060 root floppy*
below. There is deliberately **no host-side UFS writer**
(`docs/ufs-target-scoping.md` §3.3); the ufs miniroot is authored on the golden box
with the stock `mkfs_ufs`, exactly as the s5 one is authored with `dd`.

`build-miniroot.sh` grows a `ufs` authoring branch selected by `MINIROOT_FSTYPE=ufs`
(default `s5`). Because you cannot `dd` s5 bytes into a Berkeley filesystem, the ufs
on-box overlay **captures the stock tree and re-lays it**:

1. `dd` the stock s5 miniroot ADF onto the scratch slice, `fsck_s5`, mount it, and
   `find . -depth | cpio -oc` the whole tree (every mode/owner/device/symlink
   preserved) to `/tmp/mr-tree.cpio`; unmount;
2. `mkfs_ufs -o free=2,opt=s <block-node> <slice-512-blocks>` — stock's own options
   and operand semantics (the **block** node, size in 512-blocks; §7.3), default
   geometry;
3. `mount -F ufs`, `cpio -idmu` the tree back in;
4. overlay **the identical additions** (`/etc/profile`, core `passwd`/`group`,
   `/cdrom`, the cdfs mount helper, the s5 `labelit` back-end, the pkginstall shim);
5. `sync`, `umount`, `fsck_ufs`.

**`labelit` is placed, not run.** Stock never *labeled* the miniroot filesystem, and
neither branch runs `labelit` on it — but the s5 `labelit` **back-end binary** is
still copied in (as on s5), because `install.sh` labels an **s5 target** with it and
`miniroot.proto` requires it. "Drop labelit" is `install.sh`'s decision for a **ufs
target root** (a separate, later change), not the removal of the back-end here.

The build then extracts the **whole slice** (not the fixed `FD0_BYTES`) as the ufs
miniroot image, reports its ufs geometry with `tools/lib/ufs.py`, and runs the same
proto conformance self-test — which auto-detects s5 vs ufs from the image's own
superblock, so **one `miniroot.proto` attests both miniroots**.

**On-box mint sequence** (run on the golden box, exactly as the s5
build is run — scoped here, it was NOT run):

```sh
# a LARGER scratch slice than s5 needs (a ufs miniroot is ~0.9-1 MiB; give it room).
# The scratch .hdf's slice 1 must be >= ~1 MiB and a multiple of 512.
tools/mkroot.sh --out work/miniroot/scratch-ufs.hdf --size-mb 64 --no-mkfs --scsi-id 5
cp ../amix-kerntools/configs/amix-golden.uae work/miniroot/build-miniroot.uae
cat >> work/miniroot/build-miniroot.uae <<'EOF'
hardfile2=rw,DH1:<abs>/work/miniroot/scratch-ufs.hdf,64,1,2,512,0,,scsi5_a3000
uaehf1=hdf,rw,DH1:<abs>/work/miniroot/scratch-ufs.hdf,64,1,2,512,0,,scsi5_a3000
EOF
bash "$AMIBERRY_AMIX_SKILL"/scripts/amiberry-amix-up.sh work/miniroot/build-miniroot.uae
MINIROOT_FSTYPE=ufs SCRATCH_HDF=$PWD/work/miniroot/scratch-ufs.hdf bash tools/build-miniroot.sh
# -> work/miniroot/miniroot-slice1-ufs-<date>.ufsimg   (feed to build-raw-source.sh --miniroot)
```

**The `/etc/mnttab` seed (Wave C2, done).** A ufs miniroot means the running
miniroot's own root is ufs, so `install.sh`'s `/etc/mnttab` seed line — which
describes the **running miniroot's** root, not the target's
(`docs/ufs-target-scoping.md` §2.3 trap 1) — must read `ufs` when this miniroot is
the one running. It now does: `install.sh` derives `MINIROOT_FSTYPE` from the new
`INSTALL_CPU` key (030 ⇒ s5, 040/060 ⇒ ufs; default 030 keeps every existing
profile byte-identical) and the seed writes `echo "/dev/root / $MINIROOT_FSTYPE rw
0" > /etc/mnttab`. It is **never** `$TARGET_ROOT_FSTYPE` (the target's fs and the
miniroot's are independent). Nothing is baked into the image — a fresh miniroot
ships no `/etc/mnttab` at all (METAL-FIX.2) and `install.sh` seeds it at install
time. `installer-selftest.py` audit AA6 pins this and fires on both the
target-fs-type and the reverted-to-literal-`s5` wrong "fixes".

### Assembling the 040 source disk (Wave C2)

The 040/060 line's self-booting install disk is authored exactly like the 030 metal
source disk (`tools/build-raw-source.sh --author --bootable`), with the UFS miniroot
on slice 1, the 040 miniroot kernel + `boot2-040` in the slice-3 boot chain, and the
payload/raw slices as today.

**The loader is SELECTED BY NAME, and there is no override anywhere.** boot2-040 was
promoted into kerntools `contracts/bootchain-v1.json` as the proven identity
`good_040` on **2026-08-19** (campaign plan **B2**, after the **B1** metal proof), so
the profile names the *key* and the contract holds the hash:

| where | key | value |
|-------|-----|-------|
| source disk's own slice-3 chain | `SRC_BOOT2_IDENTITY` | `good_040` |
| payload boot slice (`/install/boot/…`, dd'd onto the installed disk) | `BOOTSLICE_BOOT2_IDENTITY` | `good_040` |

Both are needed, because the two gates sit on different media positions and each
pins **one** identity: `tools/write-bootchain.py` frames the source chain,
`tools/build-bootslice.py` lifts the payload slice out of the same donor. Neither
tests set membership — `proven` answers *"does this loader run on metal"*, never
*"may it ship on THIS medium"* (the contract's own `consumer_policy`), so a gate
asked for `good_040` still refuses `good` **by name**, and a profile that names
nothing gets `good`, the 030 line's loader of record. `--allow-unproven-boot2`,
`--expect-boot2-sha` and `--no-boot2-gate` play **no part** in this path.

Artifacts (referenced by path + checksum; proprietary bytes are never copied into
tracked files):

| artifact | path | identity |
|----------|------|----------|
| UFS install miniroot | `work/miniroot/miniroot-slice1-ufs-20260818.ufsimg` | 45,088,768 B, on-box `sum -r` **44716** (== host extraction), proto-conforming |
| 040 miniroot kernel (ET_REL) | `../amix-kerntools/work/040-kernel/260818-02/out/unix-040-miniroot-c0s1` | rootdev `0x00480010`, cputype 40, `sum -r` 23482, sha256 `1b7d45e7…` |
| 040 miniroot kernel (framed brel) | `work/040-src/unix-040-miniroot-c0s1.brel` | 1,332,440 B, `sum -r` **06634** = the profile's `SRC_KERNEL_BREL_SUMR` |
| boot2-040 loader | `../amix-kerntools/work/boot2-040/boot2-040.boot` | 8192 B, sha256 `fd7dacf6…838c` = contract identity **`good_040`** |

> **The miniroot `sum -r` is 44716, not 39937.** 39937 was the *first* mint, which
> died at a `cp` self-copy **before** the proto-conformance gate ran; the re-run that
> fixed the mkfs back-end path and the `0777` root dir produced **44716** and passed
> conformance, overwriting the same filename. Both `ufs-mint.log` and `ufs-mint2.log`
> are in `work/miniroot/` if the two ever need telling apart again.

The command sequence (paths relative to this repo unless noted):

```sh
# 1. Frame the 040 ET_REL kernel to brel. elf2brel.py (Wave A2) statically applies
#    the 040 line's 330 intra-.text PC-relative relocs, so it frames cleanly.
python3 ../amix-kerntools/tools/elf2brel.py \
   ../amix-kerntools/work/040-kernel/260818-02/out/unix-040-miniroot-c0s1 \
   work/040-src/unix-040-miniroot-c0s1.brel
#    -> its `sum -r` must equal the profile's SRC_KERNEL_BREL_SUMR (06634). If it
#    does not, the step-3 slice-3 gate STOPS and prints the real value.

# 2. Prepare the boot donor: install boot2-040 into a golden's UNI\0 boot slice.
#    No --allow-unproven-boot2: good_040 is a contract row since B2.
cp <a golden .hdf carrying a UNI\0 boot slice> \
   work/bootslice-donor/metal-golden-040-boot2040.hdf && chmod u+w "$_"
python3 ../amix-kerntools/tools/bootpart-kernel.py install-boot2 \
   work/bootslice-donor/metal-golden-040-boot2040.hdf \
   ../amix-kerntools/work/boot2-040/boot2-040.boot \
   --expect-sha256 fd7dacf67acccb97f7c0cc0ef37bf62fe4f371dbce6ba5430ee34ebf35ba838c

# 3. Author the 5-slice self-booting 040 source disk (host-side, box down).
#    The UFS miniroot rides slice 1 (UNI\1); boot2-040 + the 040 brel frame slice 3.
#    The profile's SRC_BOOT2_IDENTITY is passed to write-bootchain.py as
#    --boot2-identity and forwarded to the kerntools round-trip gate as --identity,
#    so BOTH gates judge good_040 (a wrong donor boot2 is still caught by name).
tools/build-raw-source.sh --author --bootable \
   --profile metal-a4000-z3660-040 \
   --miniroot work/miniroot/miniroot-slice1-ufs-20260818.ufsimg \
   --kernel   work/040-src/unix-040-miniroot-c0s1.brel \
   --donor    work/bootslice-donor/metal-golden-040-boot2040.hdf \
   --out      work/metal-040-source/metal-040-source-<date>.hdf

# 4. Populate the payload + raw on the box, then bench-BOOT the SOURCE disk to run
#    the 040 installer to a ufs target. (The installed TARGET disk's OWN
#    bootability needs a 68040 TARGET kernel = a KERN040 package -- campaign plan
#    C4, NOT this wave.)
tools/build-raw-source.sh --populate --bootable --out <disk> \
   --src-dev /dev/dsk/cXd0s4 --src-rdev /dev/rdsk/cXd0s4
```

**What the payload boot slice carries today (★C4).** `build-bootslice.py` lifts the
*whole* chain out of the donor, so the 040 medium's payload boot slice — the one
`install.sh` dd's onto the **installed** disk — carries the donor's **030 `c6s1unix`
brel** (`sum -r` 50544). The profile says so (`KERNEL_BREL_SUMR=50544`) because that
key is a **gate**, not a to-be-filled-in placeholder: it is compared against the
kernel actually extracted, so a `00000` there does not defer the question, it stops
the build. The consequence is stated rather than hidden — a full 040 install
currently produces an installed disk whose `/stand` kernel is 030. Re-pinning it to
the 040 target brel is campaign plan **C4** (the KERN040 package). This wave's
deliverable is the SOURCE disk that boots the 040 **installer**.

Three consumer gaps this line closed on the author side: the slice-1 read-back
dispatches s5/ufs on the miniroot's own superblock (`rootfs-type.identify`, never a
flag); `write-bootchain.py` and `build-bootslice.py` both forward their **selected
identity** to the kerntools round-trip gate (`--identity`, else it would reject the
very loader the framing was told to expect); and the selection itself lives in one
shared resolver, `tools/lib/boot2id.py`.

**The `--populate` smoke's `-F ufs` arm (Wave C3, done).** The on-box miniroot
spot-check hardcoded `mount -F s5 -r`, which on this line fails at the *mount*
(`MRMOUNT_FAILED`) — an error that reads as "the image is broken" when the truth is
"the reader was told the wrong filesystem". `build-raw-source.sh` now derives
`MR_FSTYPE` from the same `INSTALL_CPU` key the miniroot glob extension comes from
(030 ⇒ `s5`, 040/060 ⇒ `ufs`), exactly as `install.sh` derives `MINIROOT_FSTYPE`, and
mounts slice 1 with it. One fact, one derivation, no new profile key; the 030 line is
byte-unchanged (`MR_FSTYPE` initialises to `s5`, which is also the pre-`INSTALL_CPU`
floor). The smoke's banner and its verdict both name the type they used, so a future
mismatch is legible in the log rather than inferred.

## Self-test — `run-checks.sh` check 7

`tools/miniroot-selftest.py` reads a built image back and asserts it equals
`miniroot.proto` — every entry present with the right type/mode/owner/group
(devices by major/minor, symlinks by target), and nothing extra outside `/dev`. It
**auto-detects the filesystem** from the image's own superblock
(`rootfs-type.identify`) and walks it with the matching reader — `tools/lib/s5.py`
for an s5 miniroot, `tools/lib/ufs.py` for the 040/060 line's ufs miniroot — so the
same tracked proto attests both (the proto compare is filesystem-agnostic).
`--self-test` (wired into `run-checks.sh` as check 7) validates the tracked proto
against the plan invariants, drives the comparison through crafted violations to
prove each is caught, and proves the s5/ufs reader **dispatch** routes each
superblock to the right reader and fails closed on bytes that are neither; it needs
no media. Point it at a built image with `MINIROOT_IMAGE=<img>` (or `--image`) to add
the conformance half. The UFS reader itself is self-tested separately as **check 7b**
(`tools/lib/ufs.py`), hermetically and — when the golden ufs root is reachable
read-only — against its genuine 1991 file checksums.

The self-test also owns the W4 promise that **exactly one** object changed:
`/etc/profile` must be `source=installng` at the stock file's own `0777 root:root`,
`/etc/id_kmap` must still be `source=stock-miniroot`, the `source` column is a
**closed vocabulary**, and every `installng` entry must have a source file in this
repo. Five crafted violations prove each fires.

## Bench boot-proof

**W5.2 (2026-07-22, the stock install script).** Proven twice (two cold boots) on
the **A3000 + A4091** profile (KS 2.04/ECS, 16 MB, A3000 SCSI = card 0, A4091 =
card 1, install CD at `scsi3_a4091`): the `fd0unix` boot floppy boots and prompts
for the root floppy; the miniroot mounts and the kernel comes up; the stock install
script runs and `Ctrl-C` at its `install or repair?` prompt drops to the miniroot
shell; `/usr/lib/fs/cdfs/mount 1,3 /cdrom` returns **errno 5** first and succeeds on
the retry; `/cdrom` lists the disc and the stock package set counts **27**; `umount
/cdrom` returns 0.

**W4 (2026-08-11, our install script).** The respun miniroot (`sum -r` **62398**)
is boot-proven by the regression matrix itself, which is a stronger claim than the
2026-07-22 hand-run: four full from-scratch installs on fresh media, each **9/9**
(`cd`, `cd-interactive`, `cd-suomi`, `cd-standard`). `cd` and `cd-standard`
exercise the **preserved Ctrl-C trap** (the `mediaboot` gate reaches the miniroot
shell exactly as before — proof that replacing the script did not disturb the
unattended arms); `cd-interactive` and `cd-suomi` drive the **new flow end to end**,
including the source auto-probe finding and mounting the disc for itself after the
harness deliberately unmounts it. See `docs/installer.md` *The miniroot respin*.

The **metal** packaging (the RDB `UNIX_Root` slice-1 image) is byte-identical to the
fd0 one, and the metal source disk still assembles around it — but a metal **boot**
of the W4 miniroot has not happened yet. It is next-metal-session material.

### The 040/060 root floppy (`MINIROOT_MEDIUM=fd0`, P-15 I5)

`MINIROOT_FSTYPE=ufs MINIROOT_MEDIUM=fd0 MINIROOT_FP_PATCH=yes tools/build-miniroot.sh`
builds the UFS miniroot as ONE 880-block floppy, `floppies/build/amix_21_root-ufs060.adf`. It
pairs with kerntools' KD060-FD boot floppy (rootdev FD0P, `/dev/fakeswap`). The stock
`mkfs_ufs` geometry is kept (8 KiB blocks / 1 KiB frags, `-o free=2,opt=s`, size operand 1760).
The fit comes from leaving out what the 040/060 install path never reaches, listed with sizes
and reasons in `miniroot/fd060.omit`:

| omitted | bytes | why the 040/060 path never runs it |
|---|---:|---|
| `/bin/fsck_s5` | 34548 | s5 arms only (the line is ufs-only: setup.sh `ask_fstype` locks it, install.sh refuses s5) |
| `/bin/mkfs_s5` | 12668 | s5 arm only |
| `/usr/lib/fs/s5/labelit` | 13708 | install.sh labels s5 targets only |
| `/bin/mtret` | 16380 | tape installer; no caller |
| `/bin/viper_kludge` | 7336 | tape installer; no caller |
| `/bin/zcat` | 11516 | only for a `.pkg.Z` datastream; no medium carries one |
| **total** | **96156** | |

| budget (880-block floppy = 901120 B) | regular files | fs needed (ufs_size.py) | free |
|---|---:|---:|---:|
| the slice miniroot's content, stock geometry | 61 files, 769155 B | 957440 B | **−56320 B** (does not fit) |
| with the six omitted, stock geometry | 55 files, 672999 B | 856064 B | +45056 B |
| built (on-box `df -k` / fsck) | 226 objects | 880 frags | **63 KB avail, 80 frags free** |

Gates:
- `miniroot-selftest --omit miniroot/fd060.omit` checks that the image equals the proto minus the
  omitted entries, and that the omitted entries are absent.
- installer-selftest audit AT pins every caller of an omitted tool to a ufs-excluded s5 arm, or
  to none.

Proof: install-matrix cell `fd060-cd` (kerntools row N17/N17b), 10/10, 2026-10-03.
- The KD060-FD floppy boots and roots this floppy.
- The CD is read from the Z3660 at 0,2.
- A ufs install of KD060-Z c0-u6 completes, and the system cold-boots twice.
- The installed tree is `minimal` a650dd79, the same tree as the 030 line.

