# The Amix ABI kit

Everything an Amix kernel module needs to be built for one kernel line
(`k30` or `k46`): the headers, the list of kernel names a module may use
(DDI v1), the registries, the module tools, a make fragment and a sample
module. No Amix installation is needed beside it; the cross compiler is
the pinned gcc-cross-amix (`m68k-cbm-sysv4-*` on `PATH`).

The kit is a host-side artefact: `tools/modfix` is a Linux x86-64
executable and the compilers are cross compilers. Nothing in it runs on
Amix. The `.pkg` that carries it is only a distribution container: fetch
it with `apkg download`, or unpack it with `pkgtrans` on the host.

Build a module:

```
cd sample/hello && make            # gives build/<line>/mod.d/hello
```

and for your own module, a `Makefile` with `KIT`, `MODULE`, `OBJS` and
`include $(KIT)/mk/module.mk`, and a `Master` beside it
(`docs/guide.md`).

| Path | Content |
|---|---|
| `kit.conf` | the line, its kabi tag, the compiler pin, the CPU flag, the amix-dlm commit (`KIT_REV`); on k46 the port commit of the page headers (`PORT_REV`); the repository and commit `sys/monsw.h` came from (`MONSW_REV`) |
| `abi.txt` | the line's fingerprint text (C3-3 §4): `abi=` is its SHA-256. It covers the DDI's **data** names with their sizes and the structure layouts the core reads in a module, not the function names: a function added to `ddi.list` (its line gives the kabi minor it entered, `root_defer func 1`) leaves `abi.txt` as it is. A module that calls it needs a kernel of that minor, which the kabi rule checks (C3-1 §3), and every listed name is defined in the kernel, which the post-link gate checks (C3-2) |
| `include/sys/` | `mod.h`, `moddefs.h` (the wrapper macros), `ksym.h`, `amixddi.h` (DDI v1); `monsw.h`, the monitor switch's interface |
| `sysroot/`, `stock/` | the stock Amix 2.1 kernel headers (see `NOTICE`) |
| `ddi.list`, `core.list` | the names a module may import, per tier (C3-2) |
| `registry/` | the character and block majors, the motherboard probes |
| `tools/` | `mkmod`, `modfix`, `modcheck.py` (the checker) |
| `mk/module.mk` | the make fragment |
| `sample/hello/` | the sample module |
| `docs/` | `ddi.md` (the DDI contracts), `guide.md` (writing a module), `contracts/C3-1.md`, `C3-2.md`, `C3-6.md` |

**Minors.** k30.1.0 / k46.1.0 is stage 3's DDI. 1.1 is closed: it is
what the minted kernels kern46m -71 and kern30m -10 export (`sd_register`
on both lines, `root_defer` on k46). 1.2 holds the rest of stage 4's
names (`iodone`, `ramdisk_image`, `vfs_register`, `root_defer` on k30,
and the DMA calls of C4-5 when they come). A module carries the kit's
minor and loads on a kernel of that minor or later.

Every name in the kit is at most 14 bytes, so it unpacks on an s5
filesystem too.

The interface headers of generic modules (amix-modules: today
`sys/monsw.h`) ship with the kit, so a module that calls another module
builds against the kit alone. Each header is versioned with its module's
release; a kit carries the version current when it was built.

In amix-dlm this directory holds the kit's sources; `make kit` builds the
kits for both lines into `build/kit/`.
