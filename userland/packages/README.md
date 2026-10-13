# amix-packages

Modern GNU/BSD tools for **Amiga Unix** (Amix — Commodore's AT&T SVR4.0 for the 68k, 1992),
cross-compiled with the `m68k-cbm-sysv4` toolchain and delivered as **SVR4 `.pkg` datastream
packages** that the stock `pkgadd` on a real Amix box can install.

This repo builds *packages*. It does not build the package *manager* — that is
`amix-packagemanager`, a separate, shipped system (Heirloom pkgtools engine, `/var/sadm`
database, remote `apkg` catalog client) whose `NOTES.md` is the authority on the `.pkg` format, the
catalog and installation semantics.

## Status — nine packages live at pkg.amigaux.org; a 68060 re-mint staged

Nine packages are published in the family catalog at `http://pkg.amigaux.org/` under `pkgs/extra/`
(BATCH-1 on 2026-09-15, `amix-benchmark` on 2026-09-16, BATCH-2 on 2026-09-26). Each was
cross-built, rolled to a `.pkg` datastream and **bench-proven** on the emulated golden 68030:
installed with the **stock** `/usr/sbin/pkgadd`, exercised by the recipe's own `tests/smoke.sh`,
checked with `pkgchk` and removed with `pkgrm`. The on-box `apkg update` → `install` → smoke →
`remove` round trip passed for all of BATCH-1 (2026-09-26, `apkg` 0.2, against a byte-identical
mirror of the live catalog); `less` and `amix-benchmark` also ran on a real 68LC060 against the live
host. Each package's `registry/<name>.yaml` carries its `published:` record (catalog file, md5, size).

| Package | Version | Prefix | Upstream licence | What it adds over stock Amix |
|---|---|---|---|---|
| `acompat` ([libamixcompat](recipes/libamixcompat/)) | 0.1 | `/usr/local` | BSD-2-Clause (first-party) | Shim for the libc symbols and headers SVR4.0 lacks — `snprintf`, `setenv`, `strcasecmp`, `mkstemp`, `usleep`, `<stdint.h>` … |
| [`patch`](recipes/patch/) | 2.5.9 | `/usr/local` | GPL-2.0-or-later | Supersedes the stock Larry Wall patch 12u4 (1990) in `public` |
| [`zlib`](recipes/zlib/) | 1.2.13 | `/opt/amix` | Zlib | The deflate/inflate library (static `libz.a`); stock has none |
| [`gzip`](recipes/gzip/) | 1.3.12 | `/opt/amix` | GPL-2.0-or-later | The first `.gz` on the box; stock has only 1985 LZW `compress` |
| [`grep`](recipes/grep/) | 2.5.1a-2 | `/opt/amix` | GPL-2.0-or-later | `-r`, `-o`, `--color` and a reliable `-E`; stock SVR4 `grep` has none of the first three |
| [`less`](recipes/less/) | 704 | `/opt/amix` | GPL-3.0-or-later OR BSD-2-Clause | Backward scroll and incremental search; stock has only `more`/`pg`/`page` |
| [`tar`](recipes/tar/) (PKG `gtar`) | 1.14 | `/opt/amix` | GPL-2.0-or-later | GNU tar: base-256 sizes and ids, long names, owner names via in-executable parsers |
| [`make`](recipes/make/) | 3.81 | `/opt/amix` | GPL-2.0-or-later | GNU make beside the stock SVR4 `make` |
| [`amix-benchmark`](recipes/amix-benchmark/) (PKG `amixbench`) | 1.3 | `/opt/amix` | own code + Dhrystone | The `amix-bench` CPU/IO benchmark suite |

**68060 re-mint, staged, not published (2026-10-05).** gcc 2.7.2.3 emits a 64-bit `MULU.L` for
every divide or modulo by a constant, which a 68060 does not implement; Amix kills the process.
The D4 gate is now strict (`recipes/common/gates.sh`: any 64-bit multiply/divide, `movep`, `cmp2`,
`chk2` or `cas2` fails the build) and seven add-ons were rebuilt through the fixed toolchain as
package revision `-2`: `acompat` 0.1-2, `zlib` 1.2.13-2, `patch` 2.5.9-2, `gzip` 1.3.12-2,
`less` 704-2, `gtar` 1.14-2, `make` 3.81-2 — 0 sites each. Until they are published, the
revision-1 builds of those seven can be killed on a 68060 where a site is reached; `grep` 2.5.1a-2
and `amix-benchmark` 1.3 are already clean. Each `registry/<name>.yaml` `remint_060:` block holds
the record; the bench smoke and a 68060 run are still owed.

Registry-wide that is 9 `published` of 31 entries; the rest are triage
([`registry/INDEX.md`](registry/INDEX.md)). Publishing to pkg.amigaux.org is a manual maintainer
step.

Most packages install under **`/opt/amix`**, which no stock package owns, so they coexist with stock
Amix instead of replacing it ([`COEXISTENCE.md`](COEXISTENCE.md)). The two Wave-0 packages predate
that policy and are still minted at `/usr/local`.

## Prerequisites

Building a package needs three sibling repositories beside this checkout (or the overrides below),
and **not all of them are public yet**:

| Needed | Where from | Public? | What for |
|---|---|---|---|
| `m68k-cbm-sysv4-gcc`, its sysroot, and `m68k-cbm-sysv4-scan060` | [gcc-cross-amix](https://github.com/jusii/gcc-cross-amix) at or after commit `2ab2b22` (68060 multiply expansion, fix_asm rule 11), built, leaving a `build/env.sh` | Yes, but the published branch does not carry `2ab2b22` yet; without `scan060`, `amix-env.sh` refuses to run | The cross toolchain. **The wrapper *is* the compiler** — see `PORTING.md` §2.2 |
| Heirloom `pkgmk` / `pkgtrans` host build, and `tools/repo/scan060.py` | `amix-packagemanager`, at `heirloom/build-host/bin/` and `tools/repo/` | **Not public yet** — until it is, no `.pkg` can be rolled from public sources | Rolling a staged tree into a `.pkg` datastream; the third 68060 scanner in the D4 gate |
| The amix-bench fieldkit (`amix-benchmark` only) | `amix-kerntools`, `tools/amix-bench/fieldkit` | **Not public yet** (the public [amix-kerntools](https://github.com/jusii/amix-kerntools) has no `tools/amix-bench`) | The verbatim, sha256-pinned binaries the `amix-benchmark` recipe packages |

Host tools: a POSIX shell, `python3`, `curl` or `wget`, `sha256sum`; `m68k-linux-gnu-objdump`
(recommended — the toolchain's `scan060` decodes with it); and, for `tools/qemu060/` only,
`qemu-m68k` with `m68k-linux-gnu-gcc` and `m68k-linux-gnu-objcopy`.

`recipes/common/amix-env.sh` expects `../gcc-cross-amix` and `../amix-packagemanager` (and
`../amix-kerntools` for `amix-benchmark`) **beside this checkout**. Override with
`AMIX_CROSS_ENV`, `AMIX_PKGMGR`, or `AMIX_REPO_ROOT` if your layout differs; a missing sibling fails
loudly with the path it looked for.

Sources are **never vendored**. Each recipe's `pin.sh` carries one upstream URL and one sha256, and
`fetch.sh` verifies the digest *before* extracting.

## Building a package

```sh
sh recipes/grep/build.sh          # fetch (checksum-verified) -> patch -> cross-build -> gate -> .pkg
ls build/pkg/grep-2.5.1a-2.pkg    # the datastream; build/ is gitignored
```

Every recipe ends in object-code gates rather than an exit status — an m68k SVR4 ELF check, the
undefined-symbol listing, a no-imported-assembly check, and the **D4** `objdump -d` gate for the
68060 `mulu.l`/`muls.l` hazard. On this toolchain a clean exit proves nothing; see `PORTING.md` §2.2.

## Installing on an Amix box

The easy way is `apkg install <name>` from the catalog at `http://pkg.amigaux.org/` (see
`amix-packagemanager`). By hand: transfer the `.pkg` (FTP in **binary** mode), then, as root:

```sh
pkgadd -n -a ./admin -d ./grep-2.5.1a-2.pkg grep
pkgchk grep                       # re-checks every object against the DB; returns 0
/opt/amix/bin/grep --version
pkgrm grep                        # cleanly reverses the install
```

The `admin` file is what makes it non-interactive — `pkgadd -n` alone aborts on the first question.
`PORTING.md` §7 gives the working set of admin settings, and the whole smoke loop as it was actually
run.

**`/opt/amix/bin` is not on the stock Amix PATH**, so add it yourself — after `/usr/local/bin`, ahead
of `/usr/bin`, so your own builds still win and stock scripts that hard-code `/usr/bin/grep` keep
stock behaviour:

```sh
PATH=/usr/local/bin:/opt/amix/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:/usr/public/bin:/usr/hosts
export PATH
```

No package here edits `/etc/profile` or symlinks into a stock directory. The reasoning, and the
`pkgadd` conflict behaviour behind it, is in [`COEXISTENCE.md`](COEXISTENCE.md) §2–§4.

## The documents

| File | What it is |
|---|---|
| [`ROADMAP.md`](ROADMAP.md) | The plan — three jobs, Waves 0–4, the standing decisions D1–D11, the cross-repo items X1–X6 |
| [`PORTING.md`](PORTING.md) | The constraints every recipe inherits, probe-verified against the real toolchain: the wrapper traps, the `__STDC__` header gate, the libc gap, the packaging rules |
| [`COEXISTENCE.md`](COEXISTENCE.md) | How these packages sit beside stock Amix — the `/opt/amix` prefix, the never-overwrite rule, PATH precedence, and the stock-userland audit |
| [`BATCH-1.md`](BATCH-1.md) | How the first batches were chosen and published, and the staged 68060 re-mint |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Recipe layout, the rules every recipe follows, and how publishing works |
| [`CHANGELOG.md`](CHANGELOG.md) | What landed, when, and what it cost |
| [`registry/`](registry/) | One YAML per candidate package — the machine-readable half of the roadmap, projecting into the packagemanager's catalog format ([INDEX](registry/INDEX.md)) |
| [`recipes/`](recipes/) | One directory per port, plus the shared build harness in [`recipes/common/`](recipes/common/) |

**On citations.** `../<repo>/…` citations name sibling Amix repositories (see
[github.com/jusii](https://github.com/jusii)). `../tmp/<date>-<topic>/` citations are the
maintainer's dated research notes, which are not in version control. They record where a claim was
measured, not a link you can follow. Commit hashes cited before 2026-10-13 refer to the pre-public
development history.

## Licensing

- **Upstream packages** keep their own licences — the table above lists each. Every package ships
  its upstream licence text: `/opt/amix/doc/<tool>/COPYING` or `.../LICENSE` (and
  `/usr/local/doc/<tool>/` for the two Wave-0 packages). Nothing SVR4-derived is committed here, and
  no upstream source tree is vendored — recipes fetch at build time against a pinned sha256.
- **`recipes/libamixcompat`** is first-party and BSD-2-Clause; its text is
  [`recipes/libamixcompat/LICENSE`](recipes/libamixcompat/LICENSE).
- **The rest of this repo** — the other recipes, the shared harness, `tools/`, the registry and the
  documentation — is **MIT**, copyright 2026 Jussi Alanärä ([`LICENSE`](LICENSE)). That covers this
  repository's own files only: the MIT grant does **not** extend to any packaged upstream program,
  its source or the binaries built from it (each keeps its own licence, which travels in the
  package — the licence text under `<prefix>/doc/<tool>/` and the `pkginfo`/`PROVENANCE` record —
  and is listed per package as `license.spdx` in `registry/<name>.yaml`), nor to the
  `recipes/*/patches/` diffs, which are offered under the licence of the program each one modifies.
- **Stock Amix objects.** Built binaries link the stock Amix startup objects and the box's shared
  `libc.so.1`; on 2026-09-23 Amiga Corporation approved distributing the Commodore Amiga binaries
  this project builds on. Trademark and attribution notes: [`NOTICE`](NOTICE).
