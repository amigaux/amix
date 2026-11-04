# Changelog

## 2026-11-04 — kern46m k46.1.4.261103-62.1 (63cbd04)

The same cut 68060-261103-62 and objects, the copyright file reworded; the recipe ships a corrected copy of the FPE notice, third-party notices unchanged; build.sh accepts a re-mint version.

## 2026-11-03 — cut 68060-261103-62 is the k46 cut of record; kern46m -62 (ef09519, 189a68b)

port.pin moves to d8c7548 (core at amix 46ef7d1). The kernel keeps the kernel-memory readers' names (inode, ifreelist, ufs_inode, inodeNINODE, ifreeh; inode a read-only empty table while no s5 is loaded), so sar, sadc and timex -s work; kbootset 1.1.0.261103-37 or later is required. kern46m k46.1.4.261103-62: unix bc8e779f, kabi a2c4ec02, ufs.mod 18032738; abi 18c0a1c9 as -61. crash and adb -k still read the 68030 page-table format and are not yet supported on this kernel.

## 2026-11-03 — cut 68060-261103-61 is the k46 cut of record; kern46m -61 (3c69659, 7d7f32c)

port.pin moves to 105f682. On a 68040 the pending write-backs of a user fault that ends in a signal are kept and replayed when its handler returns, so a store such as sh's heap growth is no longer lost; the kernel-side break growth that desynchronised libc's break is gone. kern46m k46.1.4.261103-61: unix 4d23c99b, kabi 9ec2577b, ufs.mod e4787089; abi 18c0a1c9 as -60. make dist reproduces the cut from GitHub.

## 2026-11-03 — cut 68060-261102-60 is the k46 cut of record; kern46m -60 (2f624a6, 564cafd, 7774038)

port.pin moves to 4c363c3. Cut 68060-261102-60 carries the port's -58 and -59 (trap diagnostics off the trap path, core 0052, the investigation instruments out, kbootset-min -35) plus sdqueue at IPL 2 (the a3091 first-use hang), the A1200 as motherboard id 2, the CACR/Ramsey boot dump only with btrace_on, and cputype from the loader's AXL1 record so a 68040 boots the k46 kernel. unix 7f217425, kabi 679b705c, ufs.mod 88034650; abi 18c0a1c9 unchanged. kernel-k46-m k46.1.4.261102-60. The cut hook now checks the pinned fork commit out before running the fork's own tools.

## 2026-11-01 — cut 68060-261101-57; kern46m -57 (d80d396, 1821aee)

kernel-k46-m k46.1.4.261101-57: cut 68060-261101-57 (port 5d6f586), -56 with idle ticks counted as idle (the idle override's own waitloc), so an idle machine's time shows as idle in sysinfo, sar and the process times. unix 7370eec3, kabi d21c9154; kit, kabi k46.1.4 and abi 18c0a1c9 unchanged; no module package changes. kern46m 53aae7e2.

## 2026-11-01 — cut 68060-261101-56 is the k46 cut of record; kern46m -56 (65b7f49, b79f9e6, dcbe60b)

port.pin moves to 7af6b2d. Cut 68060-261101-56 on gcc-cross-amix 33ebadc with module core 0051: ITT0/DTT0 supervisor-only (user code can no longer reach physical memory below 1 GiB), no legacy 030 segment tables in user address spaces, swapadd fails with ENOMEM instead of sleeping, soft data and vmem limits unlimited. unix 8ef91062, kabi 712b3d0e, ufs.mod 384ef7c9, abi 18c0a1c9 unchanged. kern46m -56 (0c63b229) needs kbootset -34 or later and the module packages built on the same kit; kernel-k46-m reads pin= from the cut's dlm toolchain.pin.

## 2026-10-31 — cut 68060-261031-55 is the k46 cut of record; kern46m -55 (dcc3b68)

cuts/CURRENT moves to 68060-261031-55: the port's cut at eae06ae with amix 3c3e353's module core and kit. Core 0048
loads a demand-class filesystem module at its first mount; 0049 makes a first-use load never wait for memory. kabi
k46.1.4; abi 18c0a1c9 unchanged. kern46m k46.1.4.261031-55 = 5a29a4de, 2 550 784 B, still asking for kbootset -30;
host and container rolls are byte-identical.

## 2026-10-31 — port.pin moves to 392a44e (e97ac8e)

392a44e carries the records of cuts 68060-261031-54 and -55; -55's record reproduces its seven sums (unix a31055d9)
on the host and in the build container. cuts/CURRENT still names -53, whose record is unchanged.

## 2026-10-31 — port.pin moves to b0f1d86 (f028e9e)

The -53 record at b0f1d86 differs from 727cbe7's in comments and notes only; its seven sums and kern46m -53 are
unchanged.

## 2026-10-31 — the kern46m recipe, its README and the cut hook state facts without internal ids (87bf2c5, e900c1c)

kern46m -53's description text changed (unminted; payload identical).

## 2026-10-31 — cut 68060-261031-53 is the k46 cut of record; kern46m -53 (0560124)

port.pin moves to 727cbe7 and cuts/CURRENT to 68060-261031-53: the port's cut with gcc14's binutils 2.43.1 and amix
b391504's module core and kit, whose registry carries c 48 random. kabi k46.1.3 and abi 18c0a1c9 unchanged; unix
affe663a. cuts/build.sh reproduces its seven sums from the public port, on the host and in the build container.
kern46m k46.1.3.261031-53 (unminted) packages it and asks for kbootset -30 or later; -52 stays the metal record.

## 2026-10-31 — cuts/build.sh, make dist's kernel-k46 hook (598c4ed)

Rebuilds the port fork's cut of record named in cuts/CURRENT, as the fork has it at port.pin: the fork and paula in
cache repos, NetBSD syssrc through toolchain/fetch-distfile, toolchain/m68k-gnu-bin first on PATH; in the container
gcc-cross-amix is fetched as a git repo at its pin for the port's wrapper check. kern46m reads its output by default.
CURRENT names -52, which needs binutils 2.46; the port's -53 (gcc14 binutils, c 48 random) replaces it.

## 2026-10-31 — pkg/build.sh passes a recipe's exit 3 through (f9f59db)

kern46m exits 3 with a [MISSING] line naming make kernel-k46 when K46M_SRC is unset or holds no cut; with
the cut, the bytes are unchanged.

## 2026-10-31 — pkg/: the kern46m recipe moves in (b7f0715)

The kern46m recipe (kernel-k46-m) moves in from amix-packages 450ba6a, the twin of kernel/k30/pkg.
K46M_SRC names the port's cut output. Re-rolled, kern46m k46.1.3.261031-52 matches the minted one but for the control
stamps. Two runs byte-identical.

## 2026-10-31 — the pin moves to our fork's k46-module 0d37eb1 (5910d09)

port.pin moves from d0e8857 to amigaux/amix-040-060-port k46-module 0d37eb1, the sources of cut
68060-261031-52 with the quirk 90/91/92 fixes. The README says the port is built from our fork: we fix it there, the
build pins it, and changes go to Antti's repository as pull requests when we choose to. The k30 kit is byte-identical;
the k46 kit differs only in its PORT_REV and NOTICE lines; kit-test 0 failed.
