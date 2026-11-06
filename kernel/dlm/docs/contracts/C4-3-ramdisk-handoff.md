# C4-3 — the RAM-disk hand-off, version 7

- **Status:** agreed 2026-10-26; in force from commit 4003c9f (2026-10-27),
  which places the image. `ramdisk_image` is minor 2 (k30.1.2,
  k46.1.2). Version 2 (2026-10-27, from a RAM-disk installer boot): what `swap none` asks of
  the kernel's swap configuration (§3); version 3 (2026-10-27, from the
  port): `swap none` is the stock dummy swap device `/dev/fakeswap`, not
  no device (§3); version 4 (2026-10-27, from amix-installng):
  `media --disk --ramdisk` writes the netinstall raw image, and an image
  serves one generation id (§1); version 5 (2026-11-04): the image goes
  as high in the region as is free, below memory AmigaOS keeps at its
  top, and an L4 says which of "too big" and "in use" it was (§2); version 6
  (2026-11-05): on k46 the image stays within 128 MiB of the bind base (§2); version 7
  (2026-11-06): §2 states the placement rule as boot2 has it, always in
  the bind region; no change in behaviour. Other repositories build against
  this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/10-boot-loader.md` §5.4 (the RAM-disk image),
  §6 (the loader record); `30-module-core.md` §3 (`rth1_apply`'s root
  selector), §7 (the RAM disk); `50-media.md` §3–§5 (the media that root
  on it); measurements M-RD1, M-RD2
- **Written by:**
  - `kbootset`: the manifest's `ramdisk` record, `root ramdisk`
    and `swap none` on a medium's generation;
  - boot2 and `amix-cdboot`: the image placed, `memory[]`
    shortened, the loader record filled;
  - the module core's platform code: the record read (`core/plat/amiga.c`);
  - the kernel's RTH1 half (amix-040-060-port; amix-kerntools on k30):
    the root selector applied.
- **Read by:** the `ramdisk` root-class module (kernel/modules, C4-2 §8)

## 1. The manifest

A generation that roots on a RAM disk carries, beside its kernel and
root-class records:

```
ramdisk miniroot <size> at=<off> [stored=<n> z=deflate] crc32=<8 hex>     (a store)
ramdisk miniroot <size> file=<name> [stored=<n> z=deflate] crc32=<8 hex>  (a CD)
root ramdisk
swap none
rootfs <s5 or ufs>
```

- `<size>` is the image's size decompressed; the image is a filesystem of
  the `rootfs` type.
- The generation also carries the `ramdisk` root-class module
  (`match=always`, `majors=b:20`) and is marked `safe=1` with it, since a
  RAM-disk root's controller is the RAM disk (C4-4 version 4 §2).
- `kbootset` writes these for a medium's generation when given
  `--ramdisk`: `media --cd`, `media --floppy`, and `media --disk` for the
  netinstall raw image (C2-4 §13, version 13). An installed disk's
  generation never roots on a RAM disk.
- **An image serves one generation id.** The core loads a boot-class or
  demand-class module only from
  `/stand/gen/<the booted generation's id>/mod/<name>` (core patch 0018,
  C3-5 §3), and the image holds those files under one id. A store that
  holds generations of both lines therefore cannot share one image, and
  a medium for both lines carries one store per line: the netinstall
  raw images, one per line. Letting generations share an image would
  need a change to the core's path rule. No 1.1 medium needs that, so
  it is a decision to take when a two-line raw medium is wanted.

## 2. What boot2 does

After the kernel is relocated and before the hand-off copy:
1. it decompresses the image (CRC-32 checked, L3 on a mismatch, as any
   member) into **the bind region, never another**, below the kernel's
   room: the top is the bind base plus the region's size below
   0x40000000, capped at the line's limit (`AX_K30_MEMCAP`, 64 MiB;
   `AX_K46_MEMCAP`, 128 MiB). On a bind region longer than the limit the
   image sits below the bind base plus the limit, not at the region's
   physical top. `ax_rd_place` takes the image's size below that top,
   rounded down to a 64 KiB boundary, and claims it with AllocAbs while
   AmigaOS still runs; when that place is in use (a software MapROM
   tool's Kickstart copy, a reset-proof RAM disk), it tries each 64 KiB
   boundary below in turn, down to the kernel's end (version 5);
2. once the line's limit has shortened `memory[]`, it ends the entry that
   holds the image at the image's start, so the kernel never uses the
   image's pages, nor anything above them up to the room's top: the gap
   under 64 KiB the alignment leaves, and any memory AmigaOS kept there,
   are lost to the kernel;
3. it writes the image's **physical address and size** into the loader
   record (`AXL1` offsets 116 and 120);
4. it writes the root selector `ramdisk` (kind 2) and the swap selector
   `none` from the manifest's `root` and `swap` records, and the root
   filesystem type from `rootfs`.

If the room between the kernel's end and the top cannot hold the image
at its first 64 KiB-aligned place, boot2 refuses the generation with
L4, giving the needed and the available bytes. When it could, but no
place tried is free, the L4 says `the RAM disk's place is in use`. The
image and the kernel never overlap: the kernel binds at the region's low
end and the image above its end.

## 3. What the kernel does

- **The kernel's memory sizing** honours the shortened `memory[]` entry
  exactly as given (M-RD1): the pages under the image are never on a free
  list.
- **The module core's platform code** reads the address and size from
  `AXL1` with the safe and development-load flags, and keeps them for
  `ramdisk_image` (§4).
- **The RTH1 kernel half** applies the root selector (30 §3, M-RD2):
  - for `ramdisk`, `rootdev` becomes block major 20, minor 0;
  - for `swap none`, the RTH1 half sets `swapfile.bo_name` to
    `"/dev/fakeswap"`: the stock dummy disk, block 19,0 (`dumsize`
    0xffffff, `dumstrategy` fails every I/O, so nothing is ever paged
    there), the device the 1.0 floppy medium swaps on. Its console line
    says `swap /dev/fakeswap`. No swap device at all is not an option:
    without `swapadd`, `anon_resv` refuses every reservation (`ani_max`
    0) and the first fork panics (`newproc - fork failed`, measured
    2026-08-25), and the stock `swapconf` with the default name panics on
    a medium without that disk node (`swapconf lookupname failed -
    error 2`). The installer adds the target disk's swap slice with
    `swap -a` and deletes the fake, as its early and later target-swap
    steps do when `swap -l` shows `/dev/fakeswap`. **The miniroot
    carries the `/dev/fakeswap` node** (the stock miniroot's; both rd1
    images have it);
  - `rootfstype` is set from the record, so `vfs_mountroot` tries only
    that type.
  - This runs in `rth1_apply`, after `marc_root` has linked the
    `ramdisk` module, which then owns block row 20 (core patch 0031).

On k46 the second stage-4 cut freed `bdevsw` row 20: the
stock `ram` entry is out of the switch. On k30 the stock `ram` is out of
`kernel.c`.

## 4. The `ramdisk` module

`int ramdisk_image(paddr, size)` (`unsigned long *paddr, *size`) is a DDI
name of minor 2 (k30.1.2, k46.1.2), root context. It gives the image's
physical address and size from the loader record and returns 0, or
`ENOENT` when the loader placed no image.

The module (C4-2 §8; `match=always`, `majors=b:20`, pinned):
- **unit 0**, when `ramdisk_image` returns 0: presents the image as a
  block device of `size` bytes. It maps the physical address as a board
  window (C3-6 §1: `phystokv` below `VSECT1`, else `sptalloc`; on k46
  `dev_kvmap`). The memory is never allocated or freed by the module: it
  is the loader's, outside the kernel's free lists. It is writable (the
  miniroot needs a writable `/tmp`), and its contents are lost at
  power-off;
- **units 1 and 2**: kmem-backed scratch disks as the stock `ram`'s,
  allocated at first open in requests within U4's limit (256 KiB each,
  C3-6 §1) and freed at last close;
- **`_load`** with no image (an installed disk that composed the module
  for its scratch units): units 1–2 only, and it returns 0;
- **`_halt`:** none (C4-2 §5).

## 5. Measurements

- **M-RD1:** the kernel's memory sizing honours a `memory[]` region
  shortened by the loader; the image's pages are untouched after a full
  boot under load (bench).
- **M-RD2:** the root selector: a RAM-disk root (block major 20) mounts,
  and `swap none` boots on `/dev/fakeswap` to multi-user (bench).

## 6. Not in this contract

- The media that carry the image (50 §3–§5).
- How boot2 pays for the placement in bytes (`docs/measurements/2026-10-26-boot2-headroom.md` §6).
