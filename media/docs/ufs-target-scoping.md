# UFS target filesystems — media/tooling scoping report

> **The test bench.** Where this document names `tools/install-matrix.sh`, `mkroot.sh`,
> `build-miniroot.sh`, `build-ramdisk-miniroot.sh`, `build-raw-source.sh`, `miniroot/miniroot.proto`,
> `configs/*.uae`, `profiles/cards`, `cards/`, `floppies/`, `work/…` or a sibling repository (`../amix-*`), it
> names the test bench's tools, configurations and run records. They are not in this repository: the
> bench authors the RAM-disk miniroot, runs the install matrix and keeps the evidence. This repository
> builds the media with `media/build.sh` (`media/README.md`), a step of make dist.

**Status: READ-ONLY INVESTIGATION, nothing implemented.** Scopes what the install
media, the interview/driver and the host-side attestation harness need if the
TARGET root (and/or `/usr`) becomes **ufs** while the miniroot stays **s5**.
Commissioned 2026-08-14 as the media/tooling half of the UFS end-to-end proof
packet; the kernel half (`vfssw` / `ufsmountroot` for the *installed* kernel) is
`amix-kerntools`' and runs in parallel — §7.1 records only what fell out of this
work, and deliberately does not duplicate it.

The plan doc (`../docs/installer-ux-rework-plan.md` §2.6, decision §8.1) suppresses
the stock s5/ufs question "while the chain is s5-only" and calls the UFS proof
*unscheduled*, with an own packet covering "mkfs_ufs authoring, boot chain,
digest". This report is what that packet needs to know before it is written.

---

## 0. Executive summary

**The media side is almost entirely already built.** Every finding below points the
same way: the 1991 tooling for ufs is present, complete, and byte-identical to
stock in both the miniroot and the installed system; our install kernel already
carries a live `ufs` VFS; and the canonical attestation digest is *filesystem-type
independent by construction*. The expensive-sounding item in the dispatch — a
host-side `ufs.py` — turns out **not to be on the critical path at all**, because
the harness never reads the target filesystem host-side in the first place.

| Question | Answer | Cost |
|---|---|---|
| 1. Miniroot has `mkfs_ufs`/`fsck_ufs`? | **Yes — already in `miniroot.proto`, byte-identical to stock, all libc symbols resolve** | **zero** |
| 2. Interview/driver deltas | ~6 driver edits, ~40 interview lines, 1 first-boot line | small, well-bounded |
| 3. Host-side `ufs.py` reader | **Not needed for attestation** (premise inverted — see §3). A working reader spike is ~100 lines | ½ day *if* wanted |
| 3b. Host-side ufs **writer** (`mkfs`) | Needed **only** for `mkroot.sh` prebuilt mode. 600–900 lines, real risk | **avoid — use author mode** |
| 4. Digest re-attestation | **None for existing sets** — a ufs run must reproduce the *same* digest | zero (it is a gate, not a rebase) |
| 5. Bench matrix | 1 new cell (`cd-ufs`, author mode); `cd-full-ufs` later | 1 rig-free cell |

**The single load-bearing decision** is §5.1: a UFS target rides **author mode**
(the box's own `mkfs_ufs`), not prebuilt mode. That one choice deletes the only
genuinely expensive work item in the whole packet.

**The strongest single piece of evidence** is that we already own two working
Amix boxes with ufs roots — `amix-images/masters/amix-{z3660,uaebase}-golden-2026-07-11.hdf`
both carry a **UFS1 big-endian root produced by the stock installer's ufs branch**
(§1.4). They boot, they are the daily build boxes, and their `/etc/vfstab` says
`/dev/dsk/c6d0s1  /dev/rdsk/c6d0s1  /  ufs  1  no  -`.

---

## 1. Miniroot tooling (question 1)

### 1.1 Both binaries are in OUR miniroot, byte-identical to stock

`miniroot/miniroot.proto` already carries them as `stock-miniroot` entries — they
have been there since the proto was first written, because the build starts from a
byte copy of `floppies/orig/amix_21_root.adf` and the proto preserves them:

```
f 0777 root root stock-miniroot /bin/fsck_ufs
f 0777 root root stock-miniroot /bin/mkfs_ufs
```

Extracted from our built miniroot (`work/miniroot/miniroot-fd0-20260811.s5img`)
with `tools/lib/s5.py`, and independently from the stock root floppy:

| path | ino | size | md5 (ours) | md5 (stock ADF) |
|---|--:|--:|---|---|
| `/bin/mkfs_ufs` | 15 | 19,664 | `eb278b2fe1a14d564c6752d9551cb439` | **identical** |
| `/bin/fsck_ufs` | 27 | 45,548 | `aa870bc2f9b47a6455b6a0d5d17056bc` | **identical** |
| `/bin/mkfs_s5` | 16 | 12,668 | `7abfe8869de2ba7edec0f04b4f9fd84a` | — |
| `/bin/fsck_s5` | 28 | 34,548 | `af45eef85db487310d2240f81227298d` | — |

Both are `ELF 32-bit MSB executable, Motorola m68k, 68020, SVR4, dynamically
linked, interpreter /usr/lib/libc.so.1, stripped`.

**They cost nothing to keep and nothing to enable — they are already shipping.**
The relevant floppy budget figure is that our miniroot has only **46 free 1 KB
blocks** (`s_tfree=46`, `s_tinode=48`), so this mattering is not hypothetical:
if these two had *not* already been on the medium, 65 KB of new binaries would
not have fitted, and the whole packet would have been blocked on the floppy.

### 1.2 Runnability — every undefined symbol resolves against the miniroot's own libc

Neither binary needs anything the miniroot lacks. `DT_NEEDED` is
`/usr/lib/libc.so.1` **only** (same as `mkfs_s5`), and that library is a proto
member (`/usr/lib/libc.so.1`, 206,796 bytes, md5 `59da18b4192ed71ae1167f1a9b87c53d`).
All 24 of `mkfs_ufs`'s and all 47 of `fsck_ufs`'s undefined symbols are exported
by that exact library — checked symbol by symbol, zero misses.

Two consequences worth recording:

- `fsck_ufs` calls **`getpwuid`**, so it touches the name service. `/etc/passwd`
  is a proto member (placed from `core-2.1.pkg`, not the stock 0666 stub), so
  this resolves. It also calls **`ctime`**, which means `tzset` — the known
  `TZ=:US/Eastern` colon trap (the "getpwnam cascade") is in the blast
  radius of any `fsck_ufs` output line, though only cosmetically.
- `mkfs_ufs` needs no name service at all.

### 1.3 Stock's `mkfs_ufs` invocation — the root.adf script's ufs branch, verbatim

The stock install script is `/etc/profile` on the root floppy (19,351 bytes, md5
`97f800ec7bcd627bfed2322fdc19f86b`) — the file our `src/miniroot/profile`
replaces. Its ufs anatomy is four pieces:

**(a) The one option constant, at the top of the file:**

```sh
UFS_OPT="-o free=2,opt=s"	#options for mkfs_ufs
```

**(b) The root fs-type menu, gated on `OLD_BOOT`:**

```sh
if [ "$OLD_BOOT" = "0" ]
then
	...
	echo "    s5:  Traditional UNIX file system"
	echo "   ufs:  Berkeley file system"
	readask "What file system type is the root partition? [s5] "
	case $ask in
	"")    ANS="s5" ;;
	"s5")  ANS="s5" ;;
	"ufs") ANS="ufs"; ROOT_OPT="$UFS_OPT" ;;
	"*")   echo "Available file system types are s5 and ufs."
	esac
	ROOT_FSYS="$ANS"
else
	ROOT_FSYS="s5"		# Johann ROM can only boot s5 filesystem
fi
```

★ **This is the whole basis of the "stock forces s5" story, and it is an
`OLD_BOOT`-only force.** We have refused the OLD_BOOT class outright for a long time
(`install.sh` warns "this machine is the OLD_BOOT class … the disk will NOT
BOOT. Use the original Amiga UNIX 2.1 distribution media for this machine"), so
the branch that forces s5 is one we never take. The dispatch's framing is
confirmed exactly by the source.

**(c) The actual authoring calls** (note: **`mkfs` runs against the BLOCK node**
`$UPART=/dev/dsk/cXd0sN`, and there is **no `labelit` anywhere in the stock
script**):

```sh
mkfs_${ROOT_FSYS} $ROOT_OPT $UPART $ROOTLEN >/dev/null || { ...restart; }
/etc/mount $UPART /mnt 0 ${ROOT_FSYS} 2>/dev/null || { ...restart; }
```

so for a ufs root, stock's literal invocation is

```
mkfs_ufs -o free=2,opt=s /dev/dsk/c6d0s1 <ROOTLEN>
```

with **`ROOTLEN` in 512-byte blocks** (`MB * 2048`, straight from `/etc/rdb -p`)
— the same unit our `install.sh` already passes to `mkfs_s5`, and the same
operand semantics. **No geometry arguments are passed**; `mkfs_ufs` uses its own
defaults. Its usage string confirms the full grammar:

```
ufs usage: mkfs [-F FSType] [-V] [-m] [-o options] special size
[ nsect ntrak bsize fragsize cgsize free rps nbpi opt apc gap ]
```

**(d) The `Extra` partition already had its own per-partition s5/ufs menu**
(default `s5`, `EXTRA_OPT="$UFS_OPT"`) — so a per-target-fs choice is not an
invention, it is stock behaviour we have not yet re-implemented.

Two more stock facts that bear on our driver:

- `fsck_${ROOT_FSYS} -y $UPART` appears **only in `repairdisk()`** — stock does
  **not** fsck between `mkfs` and `mount`. Our `install.sh` added that pre-mount
  `fsck_s5`; it parameterises the same way.
- The `ufs` 2% superuser reserve is accounted for **before package selection**:

  ```sh
  if [ $ROOT_FSYS = "ufs" ] ; then
  	MARGIN=`expr $ROOTLEN '/' 50`
  	AVAILABLE=`expr $ROOTLEN '-' $MARGIN`
  else
  	AVAILABLE=$ROOTLEN
  fi
  ```

### 1.4 ★ What stock's ufs branch actually produced — read off a real disk

`amix-images/masters/amix-z3660-golden-2026-07-11.hdf` slice 1 (`UNIX_Root`,
`UNI\1`, 594,542,592 bytes) is a **UFS1 big-endian** filesystem, `fs_magic
0x00011954` at superblock offset `8192 + 0x55c`. Decoded:

| field | value | reads back as |
|---|--:|---|
| `fs_bsize` / `fs_fsize` / `fs_frag` | 8192 / 1024 / 8 | 8 KB blocks, 1 KB fragments |
| `fs_minfree` | **2** | ← `-o free=2` |
| `fs_optim` | **1** (`FS_OPTSPACE`) | ← `-o opt=s` |
| `fs_ncg` / `fs_cpg` / `fs_ipg` / `fs_fpg` | 448 / 16 / 512 / 1296 | 229,376 inodes total |
| `fs_nsect` / `fs_ntrak` / `fs_spc` | 18 / 9 / 162 | mkfs defaults (no geometry args) |
| `fs_nindir` / `fs_inopb` | 2048 / 64 | 128-byte inodes |
| `fs_size` | 580,608 frags | ×1024 = **exactly the slice size** |
| `fs_postblformat` | −1 (`FS_42POSTBLFMT`) | the original static-rotational format |
| `fs_fsmnt` | `/` | mounted as root |

**`fs_minfree=2` and `fs_optim=SPACE` are a direct fingerprint of `-o free=2,opt=s`,
and `fs_size × fs_fsize` matching the slice byte-for-byte confirms the
512-block size operand is right.** This disk is stock's ufs branch, executed in
1991-era anger, preserved.

Its `/etc/vfstab` (extracted, §3.2) is:

```
/dev/dsk/c6d0s1	/dev/rdsk/c6d0s1	/	ufs	1	no	-
proc		proc			/proc	proc	1	no	-
fd		fd			/dev/fd	fd	1	no	-
```

and `/etc/motd` says `System V Release 4.0  Amiga Version 2.1p2a`. By contrast
`amix-z3660-metal-golden-2026-07-21.hdf` — the disk **our** installer produced —
is **s5** (`s_type=2`, `s_fsize=80896`). The two paths are directly comparable.

### 1.5 The installed system already ships the complete ufs back-end

From `core-2.1.pkg`'s pkgmap — the ufs suite is **larger** than the s5 one
(21 entries vs 12), and the four that matter are all present:

| path | mode | size |
|---|---|--:|
| `/usr/lib/fs/ufs/mkfs` | 0555 bin bin | 20,092 |
| `/usr/lib/fs/ufs/fsck` | 0555 bin bin | 111,580 |
| `/usr/lib/fs/ufs/mount` | 0555 bin bin | 18,328 |
| `/usr/lib/fs/ufs/labelit` | 0555 bin bin | 5,400 |

plus `clri df edquota ff fsdb fstyp ncheck quot quota quotacheck quotaoff
repquota tunefs ufsdump ufsrestore volcopy` (and `quotaon`, which is a link
record rather than a file entry). The generic front-ends
`/usr/sbin/{fsck,mkfs,mount,umount,df,fstyp,mountall}` and `/usr/sbin/bcheckrc`
are core members too. **Nothing has to be added to the installed system.**

### 1.6 ★ Our install kernel already has a live `ufs` VFS

`work/install-kernel-fd0unix/usr/sys/master.d/filesys.c` (the staged
`vfssw[]` our install kernel is linked from):

```c
struct vfssw vfssw[] = {
	{ "BADVFS",	0,		&vfs_strayops,	0},
	{ NAMES5,	s5init,		0,	0},
	{ NAMEUFS,	ufsinit,	0,	0},      /* <-- index 2, stock */
	...
	{ "cdfs", cdfsinit, 0, 0 },
	};
```

and `work/install-kernel-fd0unix/usr/sys/fs/ufs/exp` (77,344 bytes) is linked in.
The `fstypes.conf` machinery only ever *appends* rows (cdfs); the stock rows are
untouched. And the miniroot's `/etc/mount` is a thin `mount(2)` wrapper —
`Usage: %s spec dir [mflag [fstyp [data]]]` — with **no hardcoded type table**;
it passes the `fstyp` string straight to the kernel.

**So `/etc/mount /dev/dsk/c6d0s1 /mnt 0 ufs` on the miniroot is expected to work
today, with no install-kernel change.**

---

## 2. Interview and driver deltas (question 2)

### 2.1 The complete edit list

| # | file | change | size |
|---|---|---|--:|
| D1 | `src/installer/install.sh` | `mkfs_s5` → `mkfs_${FSYS}` + `$FSYS_OPT` (`-o free=2,opt=s` for ufs) | 1 line + 1 const |
| D2 | `src/installer/install.sh` | `fsck_s5` → `fsck_${FSYS}` (pre-mount check) | 1 line |
| D3 | `src/installer/install.sh` | `/etc/mount "$ROOT_BLK" "$TARGET" 0 s5` → `… 0 ${FSYS}` | 1 line |
| D4 | `src/installer/install.sh` | `labelit` — branch or drop (see §2.2) | 1–3 lines |
| D5 | `src/installer/install.sh` | emit `FB_ROOT_FSTYPE` into the first-boot key block | 1 line |
| D6 | `payload/firstboot/firstboot.sh` | vfstab column 4 `s5` → `$FB_ROOT_FSTYPE` | 1 line |
| D7 | `src/installer/setup.sh` | un-suppress the stock s5/ufs menu; default → `ufs` | ~40 lines |
| D8 | `src/installer/setup.sh` | `check_space` — subtract the 2% ufs reserve | ~4 lines |
| D9 | `profiles/*.profile` | new key `TARGET_ROOT_FSTYPE` (+ `profiles/README.md`) | data |

### 2.2 `labelit` — the one place the miniroot is genuinely s5-only

Our `install.sh` runs, after `mkfs_s5`:

```sh
run /usr/lib/fs/s5/labelit "$ROOT_RAW" root ROOT
```

`/usr/lib/fs/s5/labelit` is a proto member placed from `core-2.1.pkg` (0555 bin
bin). **There is no `/usr/lib/fs/ufs/labelit` on the miniroot.** Two options:

- **(a) Drop the labelit step for ufs.** Defensible and cheap: **stock never ran
  `labelit` at all**, on either filesystem (§1.3), and the s5 call is our own
  addition. Cost: zero bytes.
- **(b) Add `/usr/lib/fs/ufs/labelit` to the proto** — 5,400 bytes, which does
  fit the 46 KB of free floppy space, but eats 12% of it for a step stock
  considered unnecessary.

**Recommendation: (a).** Keep the s5 labelit call on the s5 path (no regression,
no digest movement) and simply do not label a ufs root. Revisit only if
something downstream is found to read the ufs volume label.

### 2.3 ★ Two things that must NOT change (both are traps)

1. **`echo "/dev/root / s5 rw 0" > /etc/mnttab`** (install.sh §4 seed). This
   describes the **running miniroot's own root**, which stays s5 — it exists so
   the static `pkgadd`'s `get_mntinfo()` can `open()` a table at all
   (a fresh miniroot ships no `/etc/mnttab` and a metal run froze exactly there).
   Parameterising it by the *target* fs type would be wrong. It must stay `s5`.
2. **The swap and boot slices are raw and stay raw.** Verified on both sides:
   - swap: `/bin/swap -a "$SWAP_BLK" 0 "$SWAPBLKS"` — a block device handed to
     the kernel's swap layer, no filesystem, no `mkfs`. Stock does the identical
     thing (`swap -a $SPART 0 $SWAPLEN`; `swap -d /dev/fakeswap 0`).
   - boot: `dd if="$BSIMG" of="$BOOT_RAW" bs=512` — a pre-assembled
     `boot1|IBLK|boot2|IBLK|unix` chain at a fixed offset map (`DOS\0 @0`,
     `IBLK @0x400`, `IBLK @0x2600`, `ELF @0x2800`), built and gated host-side by
     `tools/build-bootslice.py`. **The ROM and `boot1` read the boot slice as raw
     sectors; no filesystem is involved anywhere in the boot chain.** The RDB
     DosType stamps (`UNI\0` boot / `UNI\1` root / `resv` swap) are likewise
     fs-independent — the golden ufs disk carries exactly the same three.

   **Confirmed: the root fs choice does not touch swap or boot.**

### 2.4 First boot needs exactly one field changed

`payload/firstboot/firstboot.sh` §4 hardcodes the type:

```sh
echo "$ROOT_BLK	$ROOT_RAW	/	s5	1	yes	-"
echo "$SWAP_BLK	-	-	swap	-	no	-"
```

Everything downstream of that field is already type-generic. `/usr/sbin/bcheckrc`
(extracted from the golden ufs root) resolves the root type from the *kernel*
and falls back to vfstab, then dispatches through the generic front-end:

```sh
set `/sbin/df -n /` > /dev/null
if [ "$3" = "" ] ; then fstyp="" ; else fstyp="-F $3" ; fi
/sbin/fsck $fstyp -m ${rootfs}  >/dev/null 2>&1
...
	/sbin/fsck $fstyp -y ${rrootfs}
```

`/sbin/fsck -F ufs` execs `/usr/lib/fs/ufs/fsck`, which core ships (§1.5). So
**boot-time fsck and mount need no change beyond the vfstab field** — this is
already proven daily by the two golden ufs boxes.

Note the `fsckdev` column is the **char** node (`/dev/rdsk/…`) while column 1 is
the **block** node — already correct in our writer, and it matters more on ufs
than s5 because `fsck_ufs` is the one that actually gets exercised at boot.

### 2.5 The interview

`setup.sh`'s header already documents the question as deliberately deferred:

> `* root fs type  -- SUPPRESSED while the chain is s5-only (stock idiom: never
> show a locked question).`

Un-suppressing is a stock-verbatim menu (§1.3b) placed after the size questions,
writing `TARGET_ROOT_FSTYPE` into `/tmp/answers.profile`. Three constraints:

- **Pre-POSIX sh rules apply**: backticks not `$(…)`, `expr` not `$((…))`, case
  globs for y/n, and **never `: > file` inside a loop**, which
  this menu is (it lives inside the `Do you wish to change any of these?`
  re-ask loop). `tools/installer-selftest.py` audits A/B/G/H/I/T cover it.
- **The tool allowlist is derived from `miniroot.proto`**
  (`load_proto_tools()`), so `mkfs_ufs` and `fsck_ufs` are *already* allowlisted
  the moment the driver names them. No selftest change needed.
- **Default flip**: stock's default is `[s5]`. The user decision is ufs-by-default,
  so the prompt becomes `… ? [ufs] ` with `s5` still typeable. This is the one
  deliberate divergence from stock verbatim and should be recorded as such (the
  same class as the "Suomi / Svenska" relabel).

---

## 3. Host-side attestation (question 3)

### 3.1 ★ The premise is inverted: the harness does not read the target filesystem at all

The dispatch says "today the harness reads s5 images host-side (`tools/lib/s5.py`
— inode walk, digest)". **It does not.** `s5.py` has five consumers and none of
them is the attestation:

| consumer | what it does with s5.py |
|---|---|
| `tools/mkroot.sh` | **MINTS** an empty s5 root host-side (prebuilt targets) |
| `tools/build-miniroot.sh` | builds the miniroot floppy image |
| `tools/miniroot-selftest.py` | reads the built **miniroot** back and diffs vs `miniroot.proto` |
| `tools/build-raw-source.sh` | mints the s5 **payload slice** on the source `.hdf` |
| `tools/mkroot-selftest.py` | drives the gates |

The canonical digest comes from `install-matrix.sh`'s `g_digest()`, which pulls
**three files off the running installed box over FTP** —
`/var/sadm/install/contents`, `/etc/passwd`, `/etc/group` — and hands them to
`../amix-packagemanager/tools/repo/altroot_attest.py`. That tool's record is

```
path \0 ftype \0 mode \0 uid \0 gid \0 size \0 linktarget \0 rdev \n
```

sorted bytewise and md5'd. **Not one field comes from the filesystem.** The
"on-box digest via the installed system" that the dispatch offers as an
*alternative* is already the *status quo*, and it is deliberate — its docstring
says the digest "is identical whether computed on the host from a repackage
manifest or on the box's own contents DB".

**Consequence: a UFS target requires no attestation-reader work whatsoever.**

### 3.2 A `ufs.py` reader, honestly scoped — the spike already works

Because "what would it cost" deserves a measurement rather than an estimate, a
read-only UFS1 reader was written and run against the golden. It is **102 lines**
of stdlib Python and it needed the superblock, the cylinder-group address macros
(`cgstart`/`cgimin`/`itod`/`itog`), the 128-byte dinode, fragment-aware block
reads, three levels of indirection, and the 4.2 `direct` record
(`d_ino:4, d_reclen:2, d_namlen:2, name`).

Measured on `amix-z3660-golden-2026-07-11.hdf`:

```
fs: bsize=8192 fsize=1024 frag=8 ncg=448 ipg=512 fpg=1296 nindir=2048 inopb=64
objects=29055  files=26041 dirs=1906 symlinks=268 other=840
longest basename: 25
```

full-tree walk in **0.10 s / 38 MB RSS**.

**Byte-correctness was then proven, not asserted.** The SVR4 pkgmap checksum
algorithm was first pinned independently (32-bit byte sum folded end-around to
16 bits — confirmed against three known values cited in `miniroot.proto`:
`/etc/passwd` 56704, `/etc/group` 16701, `/usr/lib/fs/s5/labelit` 4234). Then
every regular-file entry in `core-2.1.pkg`'s pkgmap was looked up in the golden
ufs tree and checksummed through the reader:

```
pkgmap regular-file entries: 763
same-size files: sum MATCH=726  sum MISMATCH=3
different size (patched content): 34 ; not present on disk: 0
  MISMATCH /etc/nodename        (10 B)   -- the box's own hostname
  MISMATCH /etc/saf/tcp/_pmtab  (534 B)  -- port-monitor table, rewritten at runtime
  MISMATCH /stand/boot2.boot    (8192 B) -- the flags-based loader swap (our own pipeline does this)
```

**726 of 729 same-size files reproduce their 1991 checksum exactly**, and all
three misses are files that are *supposed* to differ. Indirect blocks and
fragments are therefore correct, not merely plausible.

**Verdict: a `ufs.py` reader is ~½ day of work and low risk** — but it is a
*nice-to-have*, not a blocker. Reasonable uses: a host-side read-back gate for an
author-mode ufs root (the analogue of what `mkroot.sh` does for s5), and
post-mortem inspection of a captured target. It is **not** needed for the digest.

There is also a zero-code fallback the grimoire records: Linux can loop-mount
this filesystem read-only
(`mount -t ufs -o ro,loop,offset=…,ufstype=sun`). Untested here (it needs root)
and it introduces a host-kernel dependency the rest of the toolchain
deliberately avoids, so the 102-line reader is the better answer if a reader is
wanted at all.

### 3.3 ★ The expensive direction is the WRITER, and it is avoidable

The real host-side asymmetry is this: `mkroot.sh` **mints** the target root, and
nine of the ten runnable matrix cells use that prebuilt path
(`INSTALL_TARGET_PREBUILT=1`) precisely because it is the low-risk one — only
`cd-author` sets `PREBUILT=0`. A prebuilt **ufs** target would need a
host-side UFS1 `mkfs` — cylinder groups, per-cg inode and block bitmaps, the
`csum` summary blocks, the `FS_42POSTBLFMT` static rotational tables, four
superblock backups per group, free-block accounting, `lost+found`
preallocation. Realistically **600–900 lines with genuine correctness risk**,
against a 20 KB C program we already have.

**Do not write it.** `mkfs_ufs` runs on the box, and **author mode already
exists and is green** (`cd-author`, green since 2026-07-31 after its three
shipped defects were fixed). See §5.1.

*(If a pinned-rig shortcut is ever wanted: author a ufs root once on-box, snapshot
the empty filesystem host-side, and reuse it as a fixed-size template. Cheap
trick, only valid for rigs whose slice geometry is pinned — which the bench
profiles are.)*

---

## 4. Digest baselines (question 4)

### 4.1 No re-attestation. A ufs run must reproduce the SAME digest.

The digest is a pure function of `(contents DB, target /etc/passwd, /etc/group)`
(§3.1). The contents DB records what `pkgadd` was *told* to install — path, mode,
owner, group, size, cksum, all sourced from the package's pkgmap, none of it from
the filesystem. Therefore:

> **For every set that installs cleanly on s5 today, a ufs install must produce
> the byte-identical digest. A difference is a bug, not a new baseline.**

That makes the UFS lane's acceptance criterion unusually strong and unusually
cheap: it reuses `SET_REFS` unchanged.

| set | current reference | under ufs |
|---|---|---|
| `minimal` | `e483b0cb25dfaf4087b1f783335d520d` / 4859 | must match exactly |
| `standard` | `4ad8e17b69b32208c9fffa600596a428` / 11012 | must match exactly |
| `developer` | `ebd61ce15699fbb34cf0f6a2d0a07024` / 11497 | must match exactly |
| `x11` | `5439f78fc1caf4da46af82db360f5d13` / 11546 | must match exactly |
| `full` | `-` (unattested) | **first-ever attestation** |

**No new `SET_REFS` namespace keyed by filesystem is needed**, and s5-legacy
attestation coexists trivially — the same row serves both, which is the point.

### 4.2 ★ What UFS actually fixes — measured per set

An independent scan of the stock pkgmaps (symlink `path=target` records handled)
reproduces `amix-packagemanager/docs/s5-14char-collisions.md`'s authoritative
figures exactly — **5 collision groups, 10 objects** — which is a useful
cross-check on both counts:

Counts are over the **stock** packages of each set only (our own `cdfs`,
`APKGENG`, `APKG` add 66 objects to every set and no long names — hence
`minimal` reads 4,793 here against `SET_REFS`' 4,859, which is exactly
`BASE5_OBJECTS` vs `CANON_OBJECTS`; the agreement is a useful cross-check on the
scan):

| set (stock pkgs) | objects | basenames > 14 chars | collision groups | colliding objects |
|---|--:|--:|--:|--:|
| `minimal` | 4,793 | **0** | 0 | 0 |
| `standard` | 10,946 | **7** | 0 | 0 |
| `developer` | 11,431 | **7** | 0 | 0 |
| `x11` | 11,480 | **12** | 0 | 0 |
| `full` | 28,643 | **144** | **5** | **10** |

Two findings fall out:

1. **`minimal` is clean** — today's base-5 attestation is not hiding anything, and
   its digest is true of the disk.
2. **`standard`, `developer` and `x11` are not.** Each already writes 7–12 files
   under **silently truncated** names on s5, and the digest is *blind* to it
   (it attests the declared path, not the realised one). Switching those sets to
   ufs does not move the digest — it makes the digest **true of the disk for the
   first time**. That is a quiet correctness win that costs nothing.
3. **`full` is the one the ceiling actually blocks**, and UFS lifts *both* s5
   limits at once: no 14-char truncation, and no 65,535-inode ceiling (the golden
   ufs root has 229,376 inodes across 448 cylinder groups; a 400 MB ufs target at
   the default `nbpi=2048` gets ~200,000, against `full`'s ~29,000 objects).

   ★ **This is a real decision input for `amix-packagemanager`:** the pending
   Option A in `docs/s5-14char-collisions.md` (drop 5 objects, re-mint two
   packages, attest `full` at 28,704) exists **only** to work around s5. On ufs,
   `full` installs whole and attests at its natural object count. The two efforts
   should be sequenced deliberately rather than both landed.

---

## 5. The bench matrix (question 5)

### 5.1 ★ The load-bearing decision: a ufs lane rides AUTHOR mode

Prebuilt mode needs a host-side ufs writer (§3.3). Author mode does not — it runs
the box's own `/etc/rdb` + `mkfs_ufs`. `cd-author` already proves the author path
end-to-end on the canonical rig and reaches the same digest as the prebuilt
cells. **So the ufs lane is `cd-author` with two words changed.**

### 5.2 Cells to add

| cell | rig | target build | proves |
|---|---|---|---|
| `cd-ufs` | A3000+A4091, `bench-a3000-a4091` (100 MB) | **AUTHOR**, `mkfs_ufs -o free=2,opt=s` | the whole lane: ufs authoring → mount → pkgadd → boot → **`minimal` digest `e483b0cb…` unchanged** |
| `cd-ufs-standard` | same | AUTHOR | `standard` digest unchanged **and** the 7 long basenames land untruncated |
| `cd-full-ufs` | `bench-a3000-a4091-big` (400 MB) | AUTHOR | `full` installs whole — first-ever attestation |

`cd-ufs` is the packet's tracer bullet; the other two are follow-ons.

### 5.3 Rig implications — essentially none

- **No new rig, no new `.uae`, no hardware.** Same A3000+A4091 config, same disk
  sizes, same CD.
- **`g_workset` needs no branch.** It calls `mkroot.sh` unconditionally ("fresh
  target disk … s5 root") for *every* cell including `cd-author` — the author
  path then re-creates the RDB with `/etc/rdb -c` and lays its own filesystem
  over slice 1. A ufs cell inherits that unchanged: `mkfs_ufs` simply overwrites
  the s5 root `mkroot.sh` minted. The only cell field to set is `PREBUILT=0`
  (plus the new fs key), exactly as `cd-author` does.
- **`g_bootchain` is unaffected** — it reads the raw boot slice with the box down
  (§2.3).
- **`g_digest` is unaffected** — FTP + contents DB (§3.1).
- **Runtime**: `mkfs_ufs` on a 400 MB slice writes 448+ cylinder groups and will
  be slower than `mkfs_s5`; stock's own script printed *"Making filesystems.
  This will take a few minutes."* immediately before it (a string our driver
  already emits verbatim). **Check the cell's go-marker budget** — the 300 s
  budget is what failed the ddsize wedge, and a slow-but-healthy `mkfs_ufs` on
  the big target must not be mistaken for a hang.

---

## 6. Costed step plan (miniroot → interview → matrix → attestation)

| step | work | cost | gate |
|---|---|--:|---|
| **S0** | *(parallel, kerntools)* target-kernel ufs root. See §7.1 — evidence already strong. | — | not ours |
| **S1 — miniroot** | **Nothing to build.** Write down §1.1–1.2 as a proto comment so the next reader does not re-derive it; decide labelit (§2.2, recommend drop). | **~0** | `run-checks.sh` check 7 still green |
| **S2 — driver** | D1–D6: parameterise `mkfs`/`fsck`/`mount`/labelit, emit + consume `FB_ROOT_FSTYPE`. Guard the two traps in §2.3. | **~½ day** | `run-checks.sh` check 8 (audits A/B/G/O) |
| **S3 — interview** | D7–D9: un-suppress the stock menu, default `ufs`, `TARGET_ROOT_FSTYPE` key, 2% reserve in `check_space`. | **~½ day** | check 8 + a dry `sh -n` |
| **S4 — matrix** | Add `cd-ufs` (author). Branch `g_workset`. Re-check the go-marker budget. | **~½ day** | cell definition + selftest audit X |
| **S5 — the run** | Drive `cd-ufs`. **Acceptance = `minimal` digest `e483b0cb…` / 4859 objects, unchanged.** | **1 bench cycle** | `g_digest` + `g_bootchain` + 2 cold boots |
| **S6 — widen** | `cd-ufs-standard`; then `cd-full-ufs` for the first `full` attestation. | 2 bench cycles | as above |
| **S7 — optional** | `tools/lib/ufs.py` reader (~102-line spike exists, §3.2) as an author-mode read-back gate. | **~½ day** | new self-test vs the golden |
| **~S8** | Host-side ufs **writer** for prebuilt mode. | 600–900 lines | **not recommended** |

Steps S1–S4 are host-side and can all land together before any bench time is
spent. The critical path to "UFS proven end-to-end" is **S2+S3+S4 (~1.5 days) plus
one bench cycle**.

---

## 7. Open risks

### 7.1 Kernel-side — kerntools' packet, but the evidence is already favourable

Not our call and **not to be duplicated**, but two facts surfaced here that the
parallel investigation should have:

- **Two golden images boot a ufs root today** (§1.4). Whatever the mechanism, it
  demonstrably works on the emulated bench and is the daily build box.
- The grimoire records the mechanism (`docs/drivers/kernel-build.md`):
  `rootfstype` is the empty string in every kernel in this family, so
  `vfs_mountroot` **iterates `vfssw[1 .. nfstype-1]`** and stops at the first row
  that returns 0. `s5` is row 1 and `ufs` is row 2 — so a ufs root is found on the
  second try, automatically, with no per-kernel configuration. This is consistent
  with the goldens booting.

**Risk if wrong**: the whole packet stalls at S5. **Mitigation**: S1–S4 are cheap
and reversible; do not spend bench time before kerntools reports.

### 7.2 Author mode is the less-travelled path

Author mode had **three shipped defects** when `cd-author` first ran it
(2026-07-30: `rdb -c` needs `-d`, `-p` takes a partition *number*, and the
`mkfs` size operand is 512-blocks not 1 KB blocks). It is green now, but a ufs
lane inherits whatever else is latent there. **Mitigation**: run `cd-author`
(s5) immediately before `cd-ufs` in the same session, so a failure is
attributable to the fs change rather than to the path.

### 7.3 `mkfs_ufs` has never been executed in this project

Every claim in §1 is static: file identity, ELF headers, symbol resolution, the
stock script's call site, and a superblock read off a disk *someone else's*
`mkfs_ufs` wrote in 1991. **We have never run the binary.** Specific unknowns:

- Its `"%s is not special device, can't mkfs"` check — stock passes the **block**
  node, our s5 path passes the **raw** node (`ROOT_RAW`). Pick stock's (block)
  for ufs unless proven otherwise.
- Its `"%s is mounted, can't mkfs"` check — the mechanism is not evident from its
  strings or its (syscall-only) symbol set. Our `/etc/mnttab` write happens in
  the seed phase, *after* mkfs, so the ordering is already safe — **do not
  reorder it** (the same class of ordering trap as the `swap -a` step).
- Default geometry on a slice size we have never fed it. §1.4 shows what the
  defaults produced on a 567 MB slice; a 100 MB bench slice is untested.

### 7.4 `full` on ufs is two projects meeting

§4.2 item 3: attesting `full` on ufs and landing `s5-14char-collisions.md`'s
Option A are **alternative** solutions to the same problem, and doing both
produces a `full` that is neither the natural set nor the documented one.
**Sequence deliberately with `amix-packagemanager`; do not let both land.**

### 7.5 Smaller ones

- **`fsck_ufs` + `TZ`**: it calls `ctime`, so its output can hit the `TZ=:US/Eastern`
  colon trap. Cosmetic, but a garbled boot-time fsck line is exactly the sort of
  thing that gets misread as corruption.
- **The 2% reserve** (§2.2/D8): forgetting it makes `check_space` optimistic by
  2% of the root on ufs, i.e. a `standard` install that just fits on s5 could
  overrun. Stock got this right; we should too.
- **`lost+found`**: the plan (§1) records that installed targets have none and
  that fsck repair depends on it — which sits oddly beside the fact that both
  `s5.py`'s minter and the on-box `mkfs_s5` do create one, so the plan's finding
  needs re-reading before it is acted on. `mkfs_ufs` also creates its own
  (`lost+found` is a literal in the binary, and the golden ufs root has one), so
  whatever the s5 situation turns out to be, **author-mode ufs is unlikely to
  make it worse** — confirm during S5 rather than assuming either way.
- **Grimoire has stale contradictions** on this exact topic; see §8.

---

## 8. Grimoire corrections surfaced (proposed, not written)

`grimoire-amix/docs/how-it-works/filesystems-and-disks.md` contradicts itself and
contradicts a correction already made elsewhere in the same corpus:

- **line 9** (frontmatter summary): "UFS … recommended, and what the install
  scripts actually default to ✅" — **wrong**, and contradicted by the CORRECTION
  block at line 82 of the same file. The default is `[s5]`; `ufs` must be typed.
- **line 98**: "UFS is also what the miniroot itself uses — the root floppy *is* a
  UFS filesystem ✅" — **wrong**. `docs/boot-disks/anatomy-root-adf.md` already
  carries the 2026-07-05 correction: the miniroot is **s5** (magic `0xfd187e20` at
  `0x3f8`); the UFS magic `0x00011954` appears in that image only *inside* the
  `mkfs_ufs`/`fsck_ufs` ELF binaries. This report re-confirms both halves
  independently (§1.1, §1.4). The plan doc already lists this at §1 as a doc
  error to fix; it is still live in this file.
- **`docs/boot-disks/anatomy-root-adf.md` line 26/38** still *headlines* "No
  bootblock — the body is a UFS filesystem" above its own correction.

Additions worth publishing (all ✅, evidence in §1.4/§3.2 of this file): the
golden's decoded superblock as the fingerprint of `-o free=2,opt=s`; that the
stock s5 force is `OLD_BOOT`-only; and that the SVR4 pkgmap checksum is a folded
32-bit byte sum (pinned against three known values).

---

## 9. Method — how to reproduce every figure here

Everything below is host-side, read-only, stdlib Python, no box and no
proprietary bytes committed.

1. **Miniroot extraction** — `tools/lib/s5.py` (`read_inode`/`read_dir`) plus a
   ~60-line direct+single+double-indirect file reader and a path walker. Run
   against `work/miniroot/miniroot-fd0-20260811.s5img` and
   `floppies/orig/amix_21_root.adf`; compare md5s.
2. **ELF facts** — `file(1)`, `readelf -h/-d/--syms` on the extracted binaries.
   Symbol coverage: extract `/usr/lib/libc.so.1` the same way and set-difference
   the `UND` symbols against its defined ones. (Note this 1990-era SVR4 library
   has **no `.dynsym`** — it uses `.hash` + `.symtab`, so `readelf --dyn-syms`
   returns nothing and `--syms` is required.)
3. **Stock install script** — extract `/etc/profile` (ino 166, 19,351 bytes, md5
   `97f800ec7bcd627bfed2322fdc19f86b`) from `floppies/orig/amix_21_root.adf`.
4. **RDB + fs-type probe** — `tools/lib/rdb.py` `read_rdb()` → `(rdsk, [Slice])`;
   per slice check s5 magic at `+512+504` and UFS magic at `+8192+1372`.
5. **UFS superblock decode / tree walk / checksum verification** — the 102-line
   spike described in §3.2, against
   `amix-images/masters/amix-z3660-golden-2026-07-11.hdf` at offset 65536.
6. **pkgmap parsing** — the SVR4 datastream carries its pkgmap as plain text;
   `^1 ([a-z]) \S+ (/\S+) (\d+) (\S+) (\S+) (\d+) (\d+) (\d+)$` per line, and
   **`s`/`l` records encode `path=target`** so the path must be split on `=`
   before any basename analysis (getting this wrong undercounts collision groups
   4 and 5 — it is exactly the trap that made an earlier installng scan report 3
   groups instead of 5).
7. **pkgmap checksum** — 32-bit byte sum folded end-around to 16 bits. Pin it
   against `miniroot.proto`'s three cited values before trusting it.

---

*Report produced 2026-08-14. No file outside `docs/` was touched; nothing was
built, run on a box, or deployed.*
