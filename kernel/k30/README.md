# kernel/k30 — the 68030 Amix kernel build

**Amix** is Commodore's port of AT&T System V Release 4 (SVR4.0) UNIX to the 68030 Amiga
(the A3000UX and A4000). `kernel/k30` is the directory of the
[amix](https://github.com/amigaux/amix) repository that owns *how* a 68030 Amix kernel is built
with drivers in it. It discovers driver checkouts by their `driver.conf`, generates the SCSI
controller-selector wiring, applies each driver's kernel patches, links the kernel, and runs a
clean-gate that defeats an intermittent emulator linker-corruption bug.

There are two ways to build:

- the **host cross build**, `build-cross-kernel.sh`: the whole kernel is linked on a development
  machine with the pinned cross toolchain, against Commodore's relink kit taken from
  `amigaux/amix-system`. No Amiga is involved. This is how the 68030 kernels are cut today (see
  [the host cross build](#the-host-cross-build--build-cross-kernelsh) below).
- the **on-box** build, `amix-build`: the compile and link run on an Amix machine with its native
  toolchain.

The on-box build came from the former standalone repository `amix-kerntools`, with its history
(the old→new commit map is [`docs/history-map.txt`](docs/history-map.txt)).

It holds **no driver source** (each driver has its own directory or repository) and **no Amix** —
you bring your own licensed Amix 2.1 install. See [`docs/driver-contract.md`](docs/driver-contract.md)
for the driver-author contract and [`REPOS.md`](REPOS.md) for where each driver lives.

## The drivers

`amix-build` combines independent, MIT-licensed drivers into one kernel. They live in amix under
`kernel/drivers/`, and each is selected by its directory's name. `Z3660-amix` is
the firmware/emulator that owns the protocol the Z3660 drivers follow (reference — not built here):

| Driver | What | Kind | Where it lives |
|---|---|---|---|
| `a4091` | Commodore A4091 / A4092 / A4770 (NCR 53C710) | SCSI driver | [`kernel/drivers/a4091`](../drivers/a4091) (formerly `jusii/amix-a4091`) |
| `z3660scsi` | Z3660 (PiStorm piscsi mailbox) | SCSI driver | [`kernel/drivers/z3660scsi`](../drivers/z3660scsi) (formerly `jusii/amix-z3660scsi`) |
| `z3660eth` | Z3660 STREAMS/DLPI ethernet | net driver | [`kernel/drivers/z3660eth`](../drivers/z3660eth) (formerly `jusii/amix-z3660net`) |
| `Z3660-amix` | Z3660 firmware + emulator — owns the piscsi / ethernet protocol the drivers re-implement against (fork of `shanshe/Z3660`) | firmware | [`jusii/Z3660-amix`](https://github.com/jusii/Z3660-amix), its own repository |

`amix-build` finds every driver with a `driver.conf` under amix's `kernel/drivers/`; nothing
beside the amix checkout is needed. A driver's name is its directory's name, with a leading `amix-`
dropped. To build from driver checkouts kept elsewhere (a working copy of your own), point it at
their folder with `--drivers` (or `AMIX_DRIVERS`) -- an explicit override that replaces
`kernel/drivers/`:

```sh
git clone https://github.com/amigaux/amix && cd amix/kernel/k30
./amix-build --list                                  # a4091, z3660eth, z3660scsi from kernel/drivers/
./amix-build --drivers ~/amix-drivers --list         # only what is in ~/amix-drivers
```

## The on-box build: prerequisites — bring your own Amix

You need your **own** licensed Amix 2.1 install with its native development system: the
`cc`/`ld`/`make` toolchain and the `/usr/sys` kernel source tree. The kernel compile and link
happen **on the box** with that native toolchain — this path cross-compiles nothing. The
patches in the driver repos apply against your own stock `/usr/sys` files with `patch`.

The Amix box must be reachable over **FTP and telnet** (the harness uses an `ftpd` for the file
bridge — Amix is NFSv2-only — and telnet to run commands). Credentials come from the environment:

```sh
export AMIX_HOST=<box-ip>
export AMIX_USER=root
export AMIX_PASS=...        # your box's root password
```

This works equally on a real A4000+Z3660 and under emulation (WinUAE / Amiberry). The one
difference is the clean-gate (below): real hardware links deterministically and needs no gate;
emulation does.

## Quick build — `amix-build`

`amix-build` is the front door. It **discovers** the driver checkouts, lets you **pick**
which to include, and assembles a self-contained **bundle** (a tar + an on-box `build.sh`) that
integrates the drivers into `/usr/sys`, runs the clean-gate, and optionally installs — all on
the box.

```sh
./amix-build --list                          # what drivers are discoverable
./amix-build a4091 z3660scsi z3660eth         # assemble a bundle for these three
./amix-build --all                            # every discovered driver
./amix-build                                  # interactive menu (on a TTY)
./amix-build --config drivers.list            # selection from a file (one name per line)
```

It writes `work/bundle/` + `work/amix-kernel-<sel>.tar`. Then either transfer the tar yourself
and run it on the box:

```sh
#   (copy the tar to the box's /tmp, then on the box:)
cd /tmp && tar xf amix-kernel-a4091+z3660scsi+z3660eth.tar && sh amix-build/build.sh
```

…or let `amix-build` deploy it (FTP push + telnet launch + poll to done):

```sh
export AMIX_HOST=<box-ip> AMIX_USER=root AMIX_PASS=...
./amix-build a4091 z3660scsi z3660eth --push --run --install
```

Flags: `--drivers <dir>` (where the driver checkouts are; default `kernel/drivers/`),
`--install` (stage + write the boot partition after a clean gate), `--no-gate`,
`--push` / `--run` / `--host <box-ip>`, `--timeout <min>`, `--config <file>`.

## How the bundle + on-box build + clean-gate work

The bundle is portable, so you can transfer it by any means. On the box, `build.sh` (the shipped
copy of `tools/onbox-build.sh`) does the integration that can't be done off-box:

1. **Integrate** the drivers into your `/usr/sys`. For **SCSI** drivers it patches your **own
   stock** `amiga/alien/sd.c` (adds the `scsicard[]` controller-selector rows + externs + a
   `sdcardbase()` helper) and the alien `Makefile` `OBJ` list — generated, idempotent, anchored on
   stock lines, so nothing here ships Amix source. For a **net** driver it wires the driver's
   `streamtab` into `master.d/kernel.c`'s `cdevsw[]` via the driver's own idempotent patch script,
   and builds it in its own `amiga/driver/<subdir>/` subtree. Driver-supplied `kernel-patches/*.patch`
   are applied to your stock files with `patch`.
2. **Clean-gate** the linked kernel (see below).
3. With `--install`: stage the kernel (`/usr/sys: make install`, the old kernel kept as
   `/stand/OLDunix`) and write the boot partition (`/stand: make`). Reboot the box yourself.

Note `SDCARDS=2` (`sd.h`): at most two SCSI controllers register at boot.

### The D245 clean-gate (and when you don't need it)

Under **emulation**, Amix's native `ld` intermittently corrupts the linked kernel image — one
~8 KB block shifted by a few bytes at a random offset (the "D245 boot-breaker"). The clean output
is byte-deterministic; each corruption is unique. **Never `make install` an ungated kernel built
under emulation.**

**The corruption is an emulation artifact.** Real A4000+Z3660 hardware links the kernel
byte-deterministically, while emulators corrupt a large fraction of relinks (and even some plain
copies — it is the emulated block-I/O write path, not `ld`'s compute). **A kernel linked on real
hardware needs no gate**; the gate is the price of building under emulation.

The gate relinks until the image proves clean. Two variants — pick by kernel size:

- `tools/build-clean-kernel.sh` (SCSI kernels): relinks until a `sum -r relocunix` value
  **recurs** (byte-determinism), then confirms the symbol table with `checkunix`.
- `tools/build-clean-net-kernel.sh` (net / **combined** kernels): sum-recurrence does not
  converge on the larger kernel, so the bar is **`nm -h -u unix` empty** (no unresolved symbols,
  minus `etext`/`edata`/`end`) **AND `checkunix`-clean**.

`amix-build` drives the right gate automatically. A **combined** build links the SCSI drivers *and*
the net driver into **one** kernel — the two integrations touch disjoint files (`amiga/alien/*` vs
`master.d/kernel.c` + `amiga/driver/`), so they compose; it uses the net gate.

## The host cross build — `build-cross-kernel.sh`

`build-cross-kernel.sh` links a 68030 Amix kernel entirely on the host, with the
`m68k-cbm-sysv4` cross toolchain (`toolchain/gcc-cross-amix.pin`). It never touches an Amiga.
It cuts the kernel from Commodore's relink kit the way `usr/sys/Makefile` does: the stock
pre-linked objects are relinked as they are, and only the objects a change touches are
compiled fresh (the generated `sd.c`, patched stock sources, the config object, `kinfo030.c`
and the RTH1 half). The result is `unix` (ET_REL) and `unix.brel`, the boot-ready form
`elf2brel` makes, under `work/cross-kernel/usr/sys/` (gitignored).

Its inputs are named by environment variables, so nothing in this directory points at a
particular machine:

| Variable | What |
|---|---|
| `AMIX_SYSTEM` | a checkout of [amigaux/amix-system](https://github.com/amigaux/amix-system) (`system/README.md`): `usr/sys` is the relink kit, and the stock bases the kernel patches apply to (`kernel-patches.conf`) are read from it. Nothing Commodore's is copied here. |
| `GCA` | gcc-cross-amix's `build/` directory; `. "$GCA/env.sh"` puts the cross tools on `PATH` |
| `G14` | gcc14-cross-amix's `build/` (only for the module kernel's splice, which uses its `m68k-elf-*` binutils) |
| `PORT` | a checkout of the 68040/68060 port (`kernel/port/port.pin`), for `--rth1` and the port's opt-in fixes |
| `AMIX_DRIVERS` | only to override: where `kpatch` looks for the driver an `always:` row of `kernel-patches.conf` names when it is not among the driver dirs given (default `kernel/drivers/`) |
| `CDFS` | a built checkout of the cdfs fork [jusii/amix-cdfs](https://github.com/jusii/amix-cdfs) (the pinned commit lives there), for the in-kernel cdfs of `fstypes.conf` (its object is pinned by md5); `--no-fstypes` builds without it |

```sh
. "$GCA/env.sh"
export AMIX_SYSTEM=/path/to/amix-system
./build-cross-kernel.sh --config c6s1unix ../drivers/a4091               # an a4091 kernel, root on c6d0s1
```

The header of `build-cross-kernel.sh` documents every option. The module kernel (`--dlm-core
../dlm`, with `--kinfo`, `--rth1`, `--kabi`, `--carve-fs`) also
needs a built kit in `kernel/dlm` (`make -C ../dlm tools kit`).

### Cuts

A cut of record is a directory `cuts/<build id>/`: its `SHA256SUMS-<build id>` (paths relative to the cut's
`usr/sys`), the `cut.sh` that rebuilds those bytes from an amix commit and named inputs, and a README with the inputs.
The bytes themselves live outside the repository (`build/cuts/`, gitignored). A cut takes the port at the commit in
`kernel/port/port.pin` unless its README names another.

`cuts/CURRENT` names the cut of record make dist builds. `sh cuts/build.sh [OUT]` (make dist's `kernel-k30` hook)
runs that cut's `cut.sh` on this checkout with the port and paula at `kernel/port/port.pin` and
`kernel/drivers/paula/paula.pin` (each fetched by hash), writes its output to `build/cuts/<build id>/` by default,
and fails unless its sums equal the record's; it prints `kernel k30 <path> <sha256>` per file. The cut ships as
the `kern30m` package: `pkg/` holds its recipe, make dist's `kspace` hook (`pkg/README.md`), which reads that
output; `tools/cuts-selftest.sh` checks that the two name the same build and sums.

### Self-tests

```sh
make test
```

runs every host self-test here (`tools/kpatch-selftest.sh`, `tools/fstype-selftest.sh`,
`tools/elf2brel-selftest.py`, and `--selftest` of `relsim.py`, `mksym030.py`, `kinfo-cdevsw.py`,
`kabi-sidecar030.py` and the 040/060 family tools below). Each prints `SELFTEST PASS`. None needs an
Amiga or the cross compiler; a case that needs an input from outside this repository (`AMIX_SYSTEM`,
`CDFS`, a driver checkout, the port checkout, the m68k binutils) skips itself and says so.

## The `driver.conf` contract (brief)

Each driver repo declares its identity in a one-line-per-driver `driver.conf`, and ships only its
own MIT `src/` plus the substantive shared-kernel edits it needs as unified diffs in
`kernel-patches/*.patch`. It never ships the generated `sd.c`/`Makefile` or any full Amix file.
Two dialects:

- **SCSI** — `<product-number> <queue-func> "<name>" <source under src/> [probe=<fn>]`. `amix-build`
  generates the `scsicard[]` rows, externs, `sdcardbase()` helper and the `OBJ` list from these.
- **Net** — `net <subdir> <src> <streamtab> <cdevsw-major> <iface> "<desc>"`. Wired into
  `master.d/kernel.c`'s `cdevsw[]`.

The full, authoritative contract for driver authors is in [`docs/driver-contract.md`](docs/driver-contract.md).

## `tools/`

| tool | what |
|---|---|
| `amix-build` | front door: discover → select → bundle → (optionally) push + run + install |
| `tools/onbox-build.sh` | the on-box half of a bundle (shipped as `build.sh`): integrate → gate → install |
| `tools/amixsync.py` | host↔box file bridge over FTP (push / pull; Amix is NFSv2-only) |
| `tools/amixrun.py` | self-contained telnet command runner (what `amix-build --run` drives the box with) |
| `tools/build-clean-kernel.sh` | on-box SCSI clean-gate: relink until `sum` recurs (args = driver `.c` names) |
| `tools/build-clean-net-kernel.sh` | on-box net/combined clean-gate: relink until `nm -u`-empty + `checkunix`-clean |
| `tools/checkunix.c` | on-box kernel symbol-table / relocation sanity check |
| `tools/relsim.py` | host-side reimplementation of `boot/rel.c` — predicts which COMPLAIN/D245 a kernel image would trip |
| `tools/amishot.sh` | screenshot the running emulator framebuffer via its IPC socket |
| `build-cross-kernel.sh` | host cross build of the 68030 kernel (above); `kernel-patches.conf`, `fstypes.conf` and `templates/` are its inputs |
| `tools/kpatch-lib.sh` | the `kernel-patches.conf` grammar and the conditional/unconditional patch reconciliation |
| `tools/fstype-lib.sh` | the `fstypes.conf` grammar: in-kernel filesystems staged into the link |
| `tools/elf2brel.py` | the ET_REL kernel to the boot-ready brel form (a port of `amiga/boot/elf2brel.c`) |
| `tools/dlm-core-link.sh` | splices kernel/dlm's module core into a linked kernel (the module kernel) |
| `tools/kinfo-cdevsw.py`, `tools/kabi-sidecar030.py`, `tools/mksym030.py` | `/dev/kinfo`'s cdevsw row, the kabi sidecar, `unix.sym` |
| `tools/bootchain-verify.py` | checks a boot partition or floppy image against `contracts/bootchain-v1.json` |
| `tools/emit-family-chains.py` | cuts a 040/060 kernel family's per-(card, unit) chains from its base, with `MANIFEST.json` |
| `tools/kernel-rootdev-stamp.py`, `tools/kernel-cputype-stamp.py` | the by-symbol rootdev/swap and cputype stamps of a 040/060 chain |
| `tools/check-chain-stamp.py`, `tools/rootdev-assert.py` | a chain is its base plus exactly the stamp; a kernel's baked rootdev |
| `tools/kernel-sddevsize-inject.py`, `tools/kernel-support-probe-inject.py` | the 040/060 post-link fixes: sddevsize's default, the W-D7 probe |
| `tools/k0-gates.py` | the K0 family gates over `contracts/kernel-families.json` (scan060, W-D7, root, spl, media, ...) |
| `tools/comaddr.py` | runtime addresses of COMMON kernel symbols, replaying elf2brel's placement |

The 040/060 family tools came from amix-kerntools `989e30b`. `k0-gates.py` finds the port checkout as `$PORT`
(else `amix-040-060-port` beside this tree or beside the amix checkout), the toolchain as `$GCA`, and real-kernel
selftest fixtures under `$K0_FIXTURES` (absent: those cases skip).

## No Commodore files here

This directory contains **only** original MIT tooling and patches. It ships no Commodore/AT&T Amix
source, no binaries, and no files derived from them — only unified diffs that apply against the
stock files: those of the Amix 2.1 install on the box (on-box build), or the `usr/sys` tree of
[amigaux/amix-system](https://github.com/amigaux/amix-system) (cross build).

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Jussi Alanärä.
