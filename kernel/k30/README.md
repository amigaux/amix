# kernel/k30 — the 68030 Amix kernel build

**Amix** is Commodore's port of AT&T System V Release 4 (SVR4.0) UNIX to the 68030 Amiga
(the A3000UX and A4000). `kernel/k30` is the directory of the
[amix](https://github.com/amigaux/amix) repository that owns *how* a 68030 Amix kernel is built
with drivers in it. It discovers driver checkouts by their `driver.conf`, generates the SCSI
controller-selector wiring, applies each driver's kernel patches, links the kernel, and runs a
clean-gate that defeats an intermittent emulator linker-corruption bug.

What is here today is the **on-box** build: the compile and link run on an Amix machine with its
native toolchain. It came from the former standalone repository `amix-kerntools`, with its history
(the old→new commit map is [`docs/history-map.txt`](docs/history-map.txt)). The host-side cross
build of the 68030 kernel follows here.

It holds **no driver source** (each driver has its own directory or repository) and **no Amix** —
you bring your own licensed Amix 2.1 install. See [`docs/driver-contract.md`](docs/driver-contract.md)
for the driver-author contract and [`REPOS.md`](REPOS.md) for where each driver lives.

## The drivers

`amix-build` combines independent, MIT-licensed drivers into one kernel. They are moving into amix
under `kernel/drivers/`; until each one has moved, it lives in its own repository. `Z3660-amix` is
the firmware/emulator that owns the protocol the Z3660 drivers follow (reference — not built here):

| Driver | What | Kind | Where it lives |
|---|---|---|---|
| `a4091` | Commodore A4091 / A4092 / A4770 (NCR 53C710) | SCSI driver | [`jusii/amix-a4091`](https://github.com/jusii/amix-a4091), moving into amigaux/amix as `kernel/drivers/a4091` |
| `z3660scsi` | Z3660 (PiStorm piscsi mailbox) | SCSI driver | [`jusii/amix-z3660scsi`](https://github.com/jusii/amix-z3660scsi), moving into amigaux/amix as `kernel/drivers/z3660scsi` |
| `z3660net` | Z3660 STREAMS/DLPI ethernet (`z3660eth`) | net driver | [`jusii/amix-z3660net`](https://github.com/jusii/amix-z3660net), moving into amigaux/amix as `kernel/drivers/z3660eth` |
| `Z3660-amix` | Z3660 firmware + emulator — owns the piscsi / ethernet protocol the drivers re-implement against (fork of `shanshe/Z3660`) | firmware | [`jusii/Z3660-amix`](https://github.com/jusii/Z3660-amix), its own repository |

`amix-build` looks for drivers in amix's `kernel/drivers/`. Until they have moved in, clone them
into one folder and point it there with `--drivers` (or `AMIX_DRIVERS`):

```sh
git clone https://github.com/amigaux/amix && cd amix/kernel/k30
mkdir -p ~/amix-drivers && for r in amix-a4091 amix-z3660scsi amix-z3660net; do
  git clone https://github.com/jusii/$r ~/amix-drivers/$r; done
./amix-build --drivers ~/amix-drivers --list
```

## Prerequisites — bring your own Amix

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
./amix-build a4091 z3660scsi z3660net         # assemble a bundle for these three
./amix-build --all                            # every discovered driver
./amix-build                                  # interactive menu (on a TTY)
./amix-build --config drivers.list            # selection from a file (one name per line)
```

It writes `work/bundle/` + `work/amix-kernel-<sel>.tar`. Then either transfer the tar yourself
and run it on the box:

```sh
#   (copy the tar to the box's /tmp, then on the box:)
cd /tmp && tar xf amix-kernel-a4091+z3660scsi+z3660net.tar && sh amix-build/build.sh
```

…or let `amix-build` deploy it (FTP push + telnet launch + poll to done):

```sh
export AMIX_HOST=<box-ip> AMIX_USER=root AMIX_PASS=...
./amix-build a4091 z3660scsi z3660net --push --run --install
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

## No proprietary Amix is shipped — bring your own

This directory contains **only** original MIT tooling and patches. It ships no Commodore/AT&T Amix
source, no proprietary binaries, and no files derived from them — only unified diffs that apply
against the stock files in **your own** licensed Amix 2.1 `/usr/sys` tree. You must supply that
install yourself.

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Jussi Alanärä.
