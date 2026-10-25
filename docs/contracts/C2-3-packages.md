# C2-3 — kernel and loader package layout, the kabi sidecar (draft)

- **Status:** draft for agreement, 2026-10-26
- **Implements:** `docs/spec/40-generations-and-composer.md` §2.2, §3.1 (gates 2, 3, 4, 7, 10), `20-module-format-and-abi.md` §3 (kabi)
- **Produced by:** amix-packages, from kernels built in amix-kerntools (030 families) and amix-040-060-port (040/060 families), and from the loader built in amix-dlm (S2-12)
- **Read by:** `kbootset build`, apkg 0.3 pre-flight, the installer

## 1. Kernel package (role `kernel`)

| Path | Content |
|---|---|
| `/stand/k30/unix` or `/stand/k46/unix` | the kernel in a form the loader takes (`brel` or ET_REL), uncompressed |
| `/stand/k30/kabi` or `/stand/k46/kabi` | the sidecar (§2) |

During stages 2 and 3 there is one kernel package per static family. Each
family installs on its line's path, so a box carries the family it was
installed with. From stage 4 there is one kernel per line.

## 2. The sidecar: one `key=value` per line

```
kabi=static                  k46.1.0 from stage 3; "static" on a stage-2 static kernel
family=KD060-A               the static family; "generic" for the module kernel
line=k46
pin=gcc-2.7.2.3-8949028      the compiler pin (20 §3.2)
build=68060-260928-52        the build id, as kinfo reports it (C2-1)
size=2074688
sha256=<64 hex>              of unix
loader-min=1                 the lowest loader version that boots it
root=zorro:0202:54           built-in root controllers (match keys, comma-separated); static kernels only
rootfs=ufs                   built-in root filesystems; static kernels only
arena=0x001f2000 0x00080000  offset and capacity; absent on a static kernel
```

What the gates read:
- gate 2 (kabi): `kabi`, `pin`;
- gate 3 (closure): `root` and `rootfs` on a static kernel (its
  controllers are built in);
- gate 4 (arena): `arena`;
- gate 7: `loader-min`;
- gate 10 (line): `line`.

Unknown keys are ignored.

## 3. Loader package (role `loader`)

| Path | Content |
|---|---|
| `/stand/loader/boot1` | the framed bootblock, 1024 bytes |
| `/stand/loader/boot2` | boot2 as written behind boot1 |
| `/stand/loader/ldrinfo` | `version=<n>`, `boot1-sha256=`, `boot2-size=`, `boot2-sha256=` |

Installing the loader package changes nothing on the boot store.
`kbootset loader-install` writes it, and only when asked (40 §3).

## 4. kbootset package

`/sbin/kbootset` is statically linked, built with GCC 14 (D-3 §9), and
part of the base set. It is a userland package, not kernel space.

## 5. To agree

- the paths and the sidecar keys;
- how the static families name their `root` match keys (the same keys as
  the module `match=` attributes, 10 §5.1);
- who writes the sidecar: the kernel build (proposed) or the packaging
  line.
