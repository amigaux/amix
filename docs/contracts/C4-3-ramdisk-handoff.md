# C4-3 — the RAM-disk hand-off, version 1

- **Status:** draft 2026-10-26 (amix-dlm), for the orchestrator's
  agreement. Once agreed, other repositories build against this text, and
  a change is a contract change with a version bump.
- **Implements:** `docs/spec/10-boot-loader.md` §5.4 (the RAM-disk image),
  §6 (the loader record); `30-module-core.md` §3 (`rth1_apply`'s root
  selector), §7 (the RAM disk); `50-media.md` §3–§5 (the media that root
  on it); measurements M-RD1, M-RD2
- **Written by:**
  - `kbootset` (S4-12): the manifest's `ramdisk` record, `root ramdisk`
    and `swap none` on a medium's generation;
  - boot2 and `amix-cdboot` (S4-11): the image placed, `memory[]`
    shortened, the loader record filled;
  - the module core's platform code: the record read (`core/plat/amiga.c`);
  - the kernel's RTH1 half (amix-040-060-port; amix-kerntools on k30):
    the root selector applied.
- **Read by:** the `ramdisk` root-class module (amix-modules, C4-2 §8)

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
- `kbootset` writes these for a medium's generation (`media --cd`,
  `--floppy`, the netinstall form) when given `--ramdisk`. An installed
  disk's generation never roots on a RAM disk.

## 2. What boot2 does

After the kernel is relocated and before the hand-off copy:
1. it decompresses the image (CRC-32 checked, L3 on a mismatch, as any
   member) to **the top of the largest fast-memory region the kernel can
   use**: below 0x40000000, and on k30 within the 64 MiB the kernel can
   describe (`AX_K30_MEMCAP`, S3-43-9). The image starts on a 64 KiB
   boundary;
2. it shortens that region's entry in `bootinfo.memory[]` by the image's
   size rounded up to 64 KiB, so the kernel never uses those pages;
3. it writes the image's **physical address and size** into the loader
   record (`AXL1` offsets 116 and 120);
4. it writes the root selector `ramdisk` (kind 2) and the swap selector
   `none` from the manifest's `root` and `swap` records, and the root
   filesystem type from `rootfs`.

If the region cannot hold the kernel, its arena and the image, boot2
refuses the generation with L4, giving the needed and the available
bytes. The image and the kernel never overlap: the kernel binds at the
region's low end and the image at its top.

## 3. What the kernel does

- **The kernel's memory sizing** honours the shortened `memory[]` entry
  exactly as given (M-RD1): the pages under the image are never on a free
  list.
- **The module core's platform code** reads the address and size from
  `AXL1` with the safe and development-load flags, and keeps them for
  `ramdisk_image` (§4).
- **The RTH1 kernel half** applies the root selector (30 §3, M-RD2):
  - for `ramdisk`, `rootdev` becomes block major 20, minor 0;
  - for `swap none`, no swap device is configured;
  - `rootfstype` is set from the record, so `vfs_mountroot` tries only
    that type.
  - This runs in `rth1_apply`, after `marc_root` has linked the
    `ramdisk` module, which then owns block row 20 (core patch 0031).

On k46 the second stage-4 cut freed `bdevsw` row 20 (Q4-4, S4-21): the
stock `ram` entry is out of the switch. On k30 the stock `ram` is out of
`kernel.c`.

## 4. The `ramdisk` module

`int ramdisk_image(paddr, size)` (`unsigned long *paddr, *size`) is a DDI
name of minor 1 (k30.1.1, k46.1.1), root context. It gives the image's
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
  and `swap none` boots without a swap device (bench).

## 6. Not in this contract

- The media that carry the image (50 §3–§5; S4-50–S4-53).
- How boot2 pays for the placement in bytes (S4-11; the headroom note).
