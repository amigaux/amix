# C2-3 — kernel and loader package layout, the kabi sidecar, version 6

- **Status:** agreed 2026-10-25 (orchestrator), version 1; version 2 (2026-10-26): `ldrinfo`'s keys, and the catalog entries of the loader and kbootset packages (§3, §4); version 3 (2026-10-26): where `/dev/kinfo` comes from (§1); version 4 (2026-10-26): `bss=` for a brel kernel, and the sidecar describes the form shipped (§2, §5); version 5: the module kernel's keys `ident=`, `arena=`, `ksym=`, `abi=` (C3-3 §3); version 6 (2026-10-26): `unix.sym` and `sym=`, the symbols of a kernel that ships without them (§1, §2.1). Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/40-generations-and-composer.md` §2.2, §3.1 (gates 2, 3, 4, 7, 10), `20-module-format-and-abi.md` §3 (kabi)
- **Produced by:** amix-packages, from kernels built in amix-kerntools (030 families) and amix-040-060-port (040/060 families), and from the loader built in amix-dlm (S2-12)
- **Read by:** `kbootset build`, apkg 0.3 pre-flight, the installer

## 1. Kernel package (role `kernel`)

| Path | Content |
|---|---|
| `/stand/k30/unix` or `/stand/k46/unix` | the kernel in a form the loader takes (`brel` or ET_REL), uncompressed |
| `/stand/k30/kabi` or `/stand/k46/kabi` | the sidecar (§2) |
| `/stand/k30/unix.sym` | the kernel's symbols (§2.1), for a kernel shipped without a symbol table: every `brel`. An ET_REL kernel carries its own and needs none |

The kernel package does not carry `/dev/kinfo`. A device node is not a
pure file (the kernel-space packaging rule allows only plain files and
directories, and no scripts). The node is made:
- by the installer and the upgrade install, on the target:
  `/dev/kinfo`, character device 53, 0, mode 0444, owner root, group sys
  (C2-1 §1);
- by kbootset, on the running box, when it finds the node missing
  (C2-4 §2).

During stages 2 and 3 there is one kernel package per static family. Each
family installs on its line's path, so a box carries the family it was
installed with. From stage 4 there is one kernel per line.

## 2. The sidecar: one `key=value` per line

```
kabi=static                  k46.1.0 from stage 3; "static" on a stage-2 static kernel
family=KD060-A               the static family; "generic" for the module kernel
line=k46
pin=gcc-2.7.2.3-8949028      the compiler pin (20 §3.2)
build=68060-261021-NN        the build id: the kernel's buildid string (uname -m, kinfo C2-1)
size=1459584                 of unix, in the form shipped
sha256=<64 hex>              of unix, in the form shipped
bss=283445                   bytes past the image to the kernel's end (bss and COMMON); required for a brel
loader-min=1                 the lowest loader version that boots it
root=zorro:0202:54           built-in root controllers (match keys, comma-separated); static kernels only
rootfs=ufs                   built-in root filesystems; static kernels only
arena=0x001f2000 0x00080000  offset and capacity; absent on a static kernel
sym=unix.sym 412345 <64 hex> the symbols file beside unix: name, size, SHA-256 (version 6; every brel)
```

What the gates read:
- gate 2 (kabi): `kabi`, `pin`;
- gate 3 (closure): `root` and `rootfs` on a static kernel (its
  controllers are built in);
- gate 4 (arena): `arena`;
- gate 7: `loader-min`;
- gate 10 (line): `line`.

Unknown keys are ignored.

**The form shipped.** The kernel build writes the sidecar for the form it
ships:
- `size=` and `sha256=` are of that file;
- for a `brel` (the stage-2 static packages), `bss=` is taken from the
  ELF before conversion: the `end` symbol minus the end of text, rodata
  and data. A `brel` carries no bss size and no symbol table, so the
  sidecar is the only place it can come from.

kbootset refuses a `brel` kernel whose sidecar has no `bss=` (gate 2),
counts the bss in gate 6, and writes it on the manifest's kernel record
(`10-boot-loader.md` §5.1).

### 2.1 `unix.sym`

The booted kernel's namelist (40 §4.2) needs every symbol's address. A
`brel` has no symbol table, and the layout that places its COMMON
symbols is the converter's. So the kernel build ships the symbols beside
it:
- an ELF32 big-endian m68k file (any `e_type`) with a `.symtab` and its
  string table. Section contents are not needed (`NOBITS` will do);
- every symbol that names an address is defined in a section and its
  `st_value` is that address **with the kernel bound at 0** (as in an
  executable; in an ET_REL file, relative to a section whose `sh_addr` is
  its offset), in the form shipped: text, rodata and data as the `brel`'s
  image lays them, bss and COMMON past it as the converter placed them
  (`end` = the image size + `bss=`). `SHN_ABS` is a constant and is not
  moved, except `etext`, `edata` and `end`, which are addresses whatever
  their section;
- a namelist kbootset makes at bind 0 has this form (`tests/host/nlmake`),
  and for the 1.1 kernels the loader's layout of the ELF before conversion
  is the `brel`'s (S3-B5: K030-U's 78 block names agree);
- the same names, kinds (`STT_FUNC`, `STT_OBJECT`, …) and sizes as the
  ELF before conversion.

**The build's check:** every name in the kernel's symbol block
(`dlm_ksym`, C3-2), looked up with the `brel` bound at 0 (`ksymgate.py
--extract`), has the value `unix.sym` gives it; and `unix.sym`'s `end` is
the image size plus `bss=`.

`sym=` names the file, which lies beside `unix`, with its size and
SHA-256. The package's apkg record lists it like every file, so gate 1
covers it. kbootset uses it only for the namelist; a kernel without it
boots as before, with no namelist.

## 3. Loader package (role `loader`)

| Path | Content |
|---|---|
| `/stand/loader/boot1` | the framed bootblock, 1024 bytes |
| `/stand/loader/boot2` | boot2 as written behind boot1 |
| `/stand/loader/ldrinfo` | one `key=value` per line: `version=<n>`, `line=any`, `boot1-sha256=`, `boot2-size=`, `boot2-sha256=` |

- Installing the loader package changes nothing on the boot store.
  `kbootset loader-install` writes it, and only when asked (40 §3).
- The catalog entry (C2-2 §1.1) takes `line=any` and `loader=` from
  `ldrinfo`'s `line=` and `version=`. A loader entry has no `kabi=` or
  `pin=`.

## 4. kbootset package

`/sbin/kbootset` is statically linked, built with GCC 14 (D-3 §9), and
part of the base set. It is a userland package, not kernel space: it is
listed among the catalog's ordinary entries, with no kpkg entry and no
apkg kernel-space record.

It executes FPU instructions: the GCC 14 runtime's `snprintf` saves and
restores FPU registers. On a 68LC040 or 68LC060 without an FPU, the
kernel's FPU emulation, which is in the static floor (D-3 §4), takes
them. A kernel without that emulation cannot run kbootset.

## 5. Settled at agreement

- The paths and the sidecar keys are as above.
- The static families' `root` match keys are the module `match=` keys
  (10 §5.1).
- The kernel build writes the sidecar, and packaging copies it verbatim.
- Version 4: the sidecar describes the form shipped. When the build ships
  a `brel`, it writes `size=`, `sha256=` and `bss=` of that `brel`, and
  packaging still copies the sidecar verbatim.
- Version 6 (2026-10-26, from S3-B5): a `brel` kernel ships `unix.sym`
  and its sidecar says `sym=` (amix-kerntools makes both; amix-packages
  installs the file). An ET_REL kernel's sidecar may say `sym=` too, and
  then kbootset reads that file instead of the kernel.
