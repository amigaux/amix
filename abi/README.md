# The Amix ABI kit

Everything an Amix kernel module needs to be built for one kernel line
(`k30` or `k46`): the headers, the list of kernel names a module may use
(DDI v1), the registries, the module tools, a make fragment and a sample
module. No Amix installation is needed beside it; the cross compiler is
the pinned gcc-cross-amix (`m68k-cbm-sysv4-*` on `PATH`).

Build a module:

```
cd sample/hello && make            # gives build/mod.d/hello
```

and for your own module, a `Makefile` with `KIT`, `MODULE`, `OBJS` and
`include $(KIT)/mk/module.mk`, and a `Master` beside it
(`docs/writing-a-module.md`).

| Path | Content |
|---|---|
| `kit.conf` | the line, its kabi tag, the compiler pin, the CPU flag |
| `include/sys/` | `mod.h`, `moddefs.h` (the wrapper macros), `ksym.h`, `amixddi.h` (DDI v1) |
| `sysroot/`, `stock/` | the stock Amix 2.1 kernel headers (see `NOTICE`) |
| `ddi.list`, `core.list` | the names a module may import, per tier (C3-2) |
| `registry/` | the character and block majors, the motherboard probes |
| `tools/` | `mkmod`, `modfix`, `modcheck.py` (the checker) |
| `mk/module.mk` | the make fragment |
| `sample/hello/` | the sample module |
| `docs/` | the DDI contracts, the module guide, C3-1, C3-2, C3-6 |

In amix-dlm this directory holds the kit's sources; `make kit` builds the
kits for both lines into `build/kit/`.
