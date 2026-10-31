# prngd — prngd 0.9.29 for Amix

`/opt/amix/sbin/prngd` is the pseudo-random number gathering daemon. It speaks the EGD
protocol on a unix socket, so that ssh and TLS software have entropy on a box with no
`/dev/random`. It feeds its pool by sampling the output of system commands. The package also
ships `/opt/amix/bin/prngd-ctl`, upstream's command-line client (`get`, `read`, `readb`,
`pid`), and `/opt/amix/etc/init.d/prngd`, with the pages `prngd(1)` and `prngd-ctl(1)`.

    sh build/pkg/pkgbuild.sh userland/packages/prngd                      # build + roll
    sh userland/packages/tools/pkg-smoke/prepare.sh userland/packages/prngd  # stage the on-box acceptance

Package: `prngd`, catalog name `prngd`, category `system`, set `extra`. Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`) from the plain Makefile (`STYLE=make`).

**Kernel dependency:** prngd in use needs a kernel with the freeq guard (grimoire quirk 92).
Every 1.1 kernel has it; a stock 2.1c kernel without it can panic (below). The package cannot
declare this as a package dependency, since the kernel is not a package on a stock box.

**Licences:**
- prngd's own code is "free, you can do with it whatever you want" (`00README`);
- `bsd-daemon.c` is under the 4-clause UCB licence;
- `tools/prngd-ctl.c` is BSD;
- `sha1.c` (from mhash) is freely distributable.

`doc/prngd/LICENSE` carries those three notices; the binaries contain that code.

## Version: 0.9.29

The last release. An Amix build of it already existed (Michael Parson's archive), so this is a
re-mint. OpenSSH 3.9p1 on Amix is documented working against it. It is the interim entropy
answer until a real `/dev/random`. It is self-contained: its own SHA-1 and pool, no OpenSSL.

Source: `https://downloads.sourceforge.net/project/prngd/prngd/0.9.29/prngd-0.9.29.tar.gz`,
sha256 `e48669c3…25842e7c`. Upstream signs nothing; the hash is pinned at first fetch, and the
tarball's own mtime (13 Jul 2004) matches the release.

## Patches

| Patch | Why |
|---|---|
| `01-config-h-amix.patch` | An `AMIX` block for `config.h` (the cross compiler defines `AMIX`): `snprintf`/`vsnprintf` from libamixc99; no `O_RSYNC`; `int` socket lengths; and the files `seed.c` hashes at startup where Amix keeps them: `/var/adm/wtmpx`, `/var/adm/utmpx`, syslog's `/var/log/notice` (`/etc/syslog.conf`), `/var/cron/log`. It also defines `DONT_CHMOD_SOCKET` (next row). |
| `02-honour-dont-chmod-socket.patch` | **Found on the box.** prngd chmods its socket to 0777. On Amix a bound AF_UNIX socket is a FIFO of mode 000, and a chmod on it makes **every later `connect()` fail with ENOTSOCK** (errno 95, measured with a plain C test). The daemon ran and gathered, but `prngd-ctl` and `prngd --kill` could never reach it. `DONT_CHMOD_SOCKET` exists in `config.h` from the UnixWare 1 port but nothing read it by 0.9.29, so the patch makes `prngd.c` honour it again. |

**Consequence:** the socket keeps the mode `bind()` gave it, `p---------`, whatever the umask
(000, 022 and 077 all tried). That does no harm: Amix does not check those bits on a unix socket,
and a non-root client (uid 2) connects as root does (`tmp/2026-10-30-prngd/unixsock2`). The
`-m/--mode` option has no effect here.

## Build notes

- **Default paths:** `-DCONFIGFILE=/opt/amix/etc/prngd/prngd.conf` and
  `-DRANDSAVENAME=/opt/amix/etc/prngd/prngd-seed` (asserted in `post_build`). The seed is
  runtime state written by the daemon, not payload. `etc/prngd` is mode 0700.
- **`-include amix-decls.h`** declares the socket calls.
- **Linking:** `-lsocket` then `-lnsl`, passed as `LDFLAGS` and `SYSLIBS`, which keeps
  prngd's link order.
- **`prngd-ctl`** is upstream's `tools/prngd-ctl.c`, built by make's built-in rule.
- **Man pages:** upstream's `prngd.man` as `prngd(1)`. Upstream documents `prngd-ctl` only in
  its source, so `man/prngd-ctl.1` is ours. Both are installed as `/opt/amix/man/1/<name>` with
  `whatis.d/prngd` (`docs/man-pages.md`).
- **`prngd.conf`** is written for Amix. Every command exists on a stock install (checked on the
  box): `ps -efl`, `ls -alni` of `/tmp`, `/var/tmp`, `/var/adm` and `/proc`, `netstat -an/-in`,
  `ipcs -a`, `df`, `who -a`, `last`, `w`, `arp -a`, and the tail of cron's log. The rates are
  prngd's conservative SVR4 ones. `sar` is left out; it is not set up on a stock box.
- **No users:** prngd looks up no user or group names.

## Running it

**Always give it a socket.** Older Amix builds were known to core without a socket argument.
This build does not core: with no argument it prints its usage and exits 1 (smoke). The rule
stands anyway.

The package installs and starts nothing: it has no install scripts. To run it at boot, as root:

    ln /opt/amix/etc/init.d/prngd /etc/rc2.d/S74prngd
    ln /opt/amix/etc/init.d/prngd /etc/rc0.d/K74prngd

`init.d/prngd start` creates `/var/run` if it is missing (a stock box has none) and listens on
`/var/run/egd-pool`, the path ssh software expects. `stop` uses `prngd --kill`.

## Limits

- **Entropy quality:** a quiet 1992 box changes little between samples. This is a bridge to a
  real `/dev/random`, not a replacement for one.
- **TCP service** (`tcp/localhost:port`) is in the binary but not tested.
- **FPU:** prngd has 53 FPU instructions (pool accounting), none of them a 040/060-only form.
  It needs an FPU, or the kernel's FPE on an FPU-less part. prngd-ctl has none.

## Gates (build time)

All of these passed:
- strict flags, with `-mno-strict-align` on 16/16 compile lines;
- libacompat not linked;
- prototype == staged tree (23 paths, every basename ≤ 14 bytes);
- every undefined symbol defined by its `NEEDED` (libsocket, libnsl, libc.so.1);
- the 060 gate with all three scanners: prngd 9655 instructions, prngd-ctl 1300, none 64-bit;
- no 040/060-only FPU form;
- no ll printf conversion.

## The stock-kernel panic (quirk 92)

**The package is built and gated. It installs, checks and removes cleanly with stock
`pkgadd`/`pkgchk`/`pkgrm`, and the daemon serves entropy.** But on a kernel without the freeq
guard, using it brings the k30 kernel down (the 2.1c bench image 46759dcc on the emulated 030):

    PANIC: KERNEL FAULT psw=0x2100, pc=0x403C9600, fmt=0x0, vector=0x4 (Illegal Instruction)

**The panic, as the kerntools station symbolized it:**
- The last frame is `ureturn+0x26 → queuerun`: deferred STREAMS work run on the way back to
  user mode.
- `psw=0x2100` is the SR that `queuerun`'s scan-list loop sets right before it calls
  `q->q_qinfo->qi_putp(q, mp)`.
- The PC lies in kernel data, not text, and differed between runs (0x403C3F00, 0x403C9600,
  0x403C0400).
- So a deferred put went through a garbage `qi_putp`: most likely a queue freed and reused while
  its stream was still on the scan list with a message pending.

**When it happens** (rig-runs 20261030-151839, the step-marked run4 and the stress run):

| Load while prngd is still gathering | Result |
|---|---|
| a loop of `prngd-ctl get` | panic, twice |
| 100 × `prngd-ctl read 32 \| wc` | panic |
| 100 × `prngd-ctl get` | survived |
| 100 × `prngd-ctl get \| tr` | survived |

The smoke test reaches the panic too. One run passed every daemon check before the harness
fixes (rig-run 20261030-151422).

**Not reproduced without prngd** (evidence: `Amigaux/tmp/2026-10-30-prngd/repro`):
- a server replying after the AF_UNIX client closed: 4 × 50 rounds, delayed and immediate, one
  write or two;
- a non-blocking select server forking `ps -efl` gatherers while a client did 200 reads.

dropbear reading entropy from `/var/run/egd-pool` would take the same path.

**With the freeq guard (rig-runs 2026-10-31, `Amigaux/tmp/2026-10-31-prngd`).** The run was:
stock `pkgadd`, then `tests/smoke.sh`, then three loads while the daemon was still gathering, then
stock `pkgrm`. The loads:
- A: 150 × `get` against a fresh daemon.
- C: 100 × `read 32 | wc`.
- B: 100 × `get | tr` and 100 × `readb 16`.

| Row | Kernel | Result |
|---|---|---|
| N233y, A3000 16 MB | stock 2.1c with only the freeq guard | PASS: smoke 15/15; A and B `get` at 0 bits, C 0/100, B `readb` 100/100 |
| N232g, Z3660 030+FPU | k30 -63 (eda4dcdf) | PASS: C 99/100, B 100/100 |
| E1, A3000 64 MB | 2.1c bench image 46759dcc | panic in smoke, before the loads (pc=0x403C4F00) |

The E1 panic is consistent with quirk 92 (a heap PC, vector 4), but the stack frames are not
confirmed. The booted BREL has no symbol table, so the backtrace cannot be resolved. The panic
came right after step 1's deliberate no-socket run printed its exit message, at the start of
step 2 (the daemon on its socket and the first `prngd-ctl` calls). `guest.log` was lost when
the network went down, so the exact step is not known.

Caveats:
- E1 has 64 MB and N233y 16 MB, so the guarded row ran on the smaller box.
- The same panic also comes from prngd's fork-failure spin when the swap reservation runs out.
  These loads did not exercise that path.
- On N233y the daemon was still gathering through the loads: `read 32` returned no data, so
  that row is a weaker test than N232g's 99/100. One clean boot says little about a panic that
  comes by chance.
- k46 is not tested.
- A kernel without the guard still panics (the 2.1c bench image above).

**Release:** prngd ships in 1.1 (owner decision, 2026-10-31), with the 1.1 kernels, which all
carry the freeq guard. On a kernel without it, run prngd only at your own risk.
