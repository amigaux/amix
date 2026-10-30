# apkg — remote package client for Amiga Unix (Amix, SVR4.0 m68k)

`apkg` is the small C89 client from [docs/design.md §2](../../docs/design.md):
it fetches SVR4 datastream packages over plain HTTP from a static
repository, verifies them (md5 + size), resolves catalog dependencies,
and drives the local `pkgadd`/`pkgrm` non-interactively.  It reads
installed state straight from the stock `/var/sadm/pkg` database, so it
coexists with the native tools and with the Heirloom engine port.

MIT licensed (see [LICENSE](LICENSE)); `md5.c`/`md5.h` are Colin
Plumb's public-domain MD5 (1993), vendored with the original notice;
`sha256.c`/`sha256.h`/`axtypes.h` are amix-dlm's `loader/common`
SHA-256 (FIPS 180-4, C89, MIT), copied verbatim from amix-dlm `656d155`.

## Verbs and options

```
apkg [-n] [-f] [-v] [-c conffile] <verb> [args]

update                  fetch <repo>/catalog -> /var/apkg/catalog (tmp+rename)
list [installed|all]    catalog entries with installed-version column
search <substr>         case-insensitive match on name|description
info <name>             full catalog entry + installed state
download <name>         fetch <repo>/pkgs/<file> into the cache, md5-verify
install <name>...       resolve deps -> download+verify all -> pkgadd each
upgrade <name>...       catalog newer than installed: ONE pkgadd over each
                        installed instance (instance=overwrite, no pkgrm);
                        several names = one transaction, one kbootset trigger
remove <name>           pkgrm wrapper
recover                 finish an interrupted transaction from /var/apkg/txn
                        (-f: print and discard the journal)
version                 client version

-n dry run   -f force reinstall (NAMED packages only)   -v verbose
-c <conffile>
```

Exit codes: `0` ok · `1` usage/config · `2` network · `3` verify
(md5/sha256/size/catalog, a malformed `APKG_FSTYPE`) · `4` pkgadd/pkgrm/zcat
failure · `5` dependency cycle or missing dependency, a kernel-space
pre-flight refusal, or a UFS-only package on another filesystem · `6`
kbootset could not run or failed (status 1/2; `apkg recover` retries) ·
`7` kbootset refused (status 3/4; the committed generation is unchanged).
See [apkg.1](apkg.1) for the full manual.

## UFS-only packages (`APKG_FSTYPE`)

A package whose pkginfo says `APKG_FSTYPE=ufs` (file names over 14 bytes,
which s5 cuts; P-35 Option C) is refused, exit 5, before any `pkgadd` of the
transaction, when the directory of one of its long names, under the `-R`
target, is on another filesystem type (`statvfs` `f_basetype`; the install
base when it has no long name).  Unmarked packages are not checked.
`fsreq.c`; the interface is `docs/design.md` section 2b.

## Kernel space (0.3)

Kernel, loader and module packages are the kernel-modules campaign's
(amix-dlm, decision D-3).  apkg implements its side of two agreed contracts,
C2-2 version 5 and C2-4 version 2 (2026-10-26): `amix-dlm/docs/contracts/C2-2-kpkg.md` (the catalog block and the
install record) and `C2-4-kbootset-cli.md` (kbootset as a called program).
NOTES.md 2026-10-25 is the record of what was built and how it was tested.

- **Catalog.** A `#ext kpkg 1` … `#end kpkg` block after the ordinary
  entries, one `#kpkg <name> <version> role= line= kabi= pin= size= sha256=
  file=` line per package, optional `#ksig`.  Every line is a comment to a
  0.2.x client, which skips the block whole (tested against the 0.2.3
  source).  Keys per role (C2-2 v3 §1.1): kernel/module need `line=k30|k46`,
  `kabi=`, `pin=`; a loader needs `line=any` and `loader=<n>` and may not
  carry `kabi=`/`pin=`; a missing or excluded key refuses the entry.  The optional keys of C2-2 v2: `pkginst=` (otherwise
  the datastream header names it) and `offset=` (RAW media).
- **Integrity.** SHA-256 + size for kernel space, md5 + size for userland as
  before.  No signature in 1.1 (D-3 §13): the hook in `kspace_verify_hook()`
  records "unverified"; records say `verified no`.
- **Pre-flight** before anything is fetched: module kabi family/major/minor
  and compiler pin against the kernel of its line; a static kernel takes no
  modules; a kernel upgrade may not strand an installed module.
- **One kernel package per line** (C2-2 v5 §2.1, apkg 0.3.1).  Installing a
  kernel when another package's kernel record of the same line exists
  replaces that package in the same journaled transaction: the plan (and
  `-n`) prints `kernel-k46-m replaces kernel-k46-z (KERN46Z): one kernel
  package per line`; pre-flight checks every installed module against the
  new kernel (a static one takes none: "remove the module packages
  first"); then `pkgrm` + record removal of the other (`removed KERN46Z`),
  then the new `pkgadd` + record, one trigger.  A cut between the two is
  finished by `apkg recover`.  Two kernel records of one line, or two
  kernels of one line in one transaction, refuse with exit 5.
- **Pure files** (40 §6): after staging, before the first pkgadd, the
  datastream's pkgmap may hold only `f`/`d` objects of class `none` and no
  install scripts (`i`: pkginfo, depend, copyright), and at least one `f`;
  a module package may also carry its driver's device nodes as `c none`
  entries under `/dev/` (C3-5 v4 §1.2, apkg 0.3.2: `c none /dev/zen0 51 0
  0644 root root`), which pkgadd makes and the contents database records
  (the install record's `file` lines stay plain files); anything else,
  including a `c` in a kernel or loader package, refuses with exit 3.
- **Records.** `/var/apkg/kpkg/<pkginst>` after each pkgadd (C2-2 v4: the file is
  named by `pkginst=`, else the name, so a long name and its `.new` cannot collide
  on an s5 root's 14 characters; the full name is the `name` line), with one
  `file <path> <size> <sha256>` line per plain-file (`f`) object the contents database
  lists for the package, hashed on disk.  kbootset's gate 1 reads them.
- **Trigger.** After a transaction that changed kernel space:
  `kbootset [-R t] --journal J build`, then `… commit`, two calls; the
  statuses 0–4 map to apkg's 0/6/7.  `bootset=manual` in
  `/etc/default/bootset` prints the commands.  `kbootset=` and
  `kbootset_journal=` in apkg.conf move the binary and the journal.
- **Journal.** `/var/apkg/txn` from "all staged and verified" to "done";
  kept only when `apkg recover` has work left (an interruption, a failed
  pkgadd in a kernel-space transaction, an owed trigger).  A pending journal
  blocks the next install/upgrade/remove.

## Building

```
make            # host build (Linux, gcc -std=gnu89) -> ./apkg
make test       # host build + full functional suite (tests/run-tests.sh)

. "$GCA/env.sh"  # gcc-cross-amix at amix's toolchain/gcc-cross-amix.pin
make amix       # cross build -> ./apkg.amix (m68k MSB ELF)
```

The source is strict C89 for gcc 2.7.2.3 / the 1992 Amix libc: no
`//` comments, no declarations after statements, no
`snprintf`/`strdup`/`strcasecmp`/`getopt_long` (local replacements in
`util.c`, hand-rolled option scan in `main.c`).  All `sprintf` calls
write into buffers whose length is pre-computed from the inputs.

### Byte order (md5)

m68k is big-endian: the `amix` target compiles `md5.c` with
`-DHIGHFIRST`, which enables Plumb's `byteReverse()`.  The host target
assumes a little-endian host; building the host tools on a big-endian
machine needs `HOST_ENDIAN_FLAGS=-DHIGHFIRST`.  Digests are verified
against test vectors in the suite.

### Amix link notes (learned against the real sysroot)

* The **shared** `libsocket.so` lacks link closure under GNU ld 2.8.1
  (it references `select`/`syslog`/`seteuid`, which the Amix libc does
  not export), so the Makefile links the **static** `libsocket.a` and
  only pulls the members apkg uses.
* `libsocket.a` still references `syslog()`; `amixcompat.c` (compiled
  into the amix build only) provides a no-op stub.
* **`libnsl.so` has no SONAME.**  The cross-gcc wrapper resolves
  `-lnsl` to an absolute host path and GNU ld records that path as
  `DT_NEEDED`; on the guest the runtime linker then dies at exec
  (`dynamic linker: can't open /home/.../libnsl.so` followed by
  SIGKILL — reproduced on the bench).  The `amix` target therefore
  invokes `m68k-cbm-sysv4-ld` directly with
  `-L<sysroot>/usr/lib -lnsl`, which records a bare `libnsl.so` that
  the guest resolves from its own `/usr/lib`.  `libc.so.1` is immune
  (it has SONAME `/usr/lib/libc.so.1`) and is passed by path.
* `AMIX_SYSROOT` / `AMIX_CRT_DIR` can be overridden from the
  environment to build against another sysroot tree.

## Behaviour details

* **HTTP** (`http.c`): hand-rolled HTTP/1.0 GET over BSD sockets with a
  `Host:` header (the repo host is virtual-hosted — `Host:` is
  load-bearing) and `Connection: close`.  Streams the body to
  `<dest>.part` and renames on success; headers parsed
  case-insensitively; `Content-Length` used for progress and a
  truncation check; follows `redirects=` 301/302 hops; name resolution
  delegated to `dns.c` (below).  Plain `http://` only.  The `alarm()` timeout is an
  **inactivity** timer — re-armed before every blocking call, so each
  arriving chunk resets it — with its own shorter budget for
  resolve+connect, retries with doubling backoff on network failures
  only, and a configurable read buffer and progress interval.  Every
  one of those numbers is an `apkg.conf` key; `http.c` holds no
  constant an operator cannot reach.
* **Catalog v1** (`catalog.c`): first line must be `#apkg-catalog 1`,
  then `name|version|pkginst|filename|md5|size|deps|category|description`
  per line (`deps` = comma-separated names or `none`), plus an
  **optional 10th `offset` field** (a decimal byte offset the RAW
  source uses; a 9-field line leaves it unset and RAW fails closed).
  Parsing is
  defensive — field count, 32-hex md5, numeric size, and a
  `[A-Za-z0-9._+-]` filename whitelist (filenames reach a URL, a
  shell pipeline and cache paths) — and a bad catalog is rejected
  whole.  Filenames may carry **repo subdirectory paths** with `/`
  (the categorized layout: `stock/net-2.1.pkg`, `base/…`, `test/…`),
  but nothing that could escape the `pkgs/` tree: a leading `/`, any
  `.`/`..` component, `//`, or a trailing `/` rejects the catalog.
* **Catalog metadata**: the `category` field `list` and `info` print comes
  from the repository's authored taxonomy
  ([tools/repo/cats.conf](../../tools/repo/cats.conf)), not from the
  package's own `pkginfo` — stock Amix ships every package as
  `CATEGORY=system`, so the catalog is where the thirteen-group vocabulary is
  applied.  A catalog may also carry **extension blocks** after the entry
  lines (`#ext <name> <version>` + `#<name> <key> <value>`); the only one
  minted today is `isize`, the per-package installed size in bytes from
  `gen-catalog.py --isize`.  Blocks are `#` comment lines, so apkg skips them
  (`catalog.c:292`) and needs no change to tolerate one — including an
  extension it has never heard of.  A consumer that *does* read `isize` must
  treat a **missing** line as unknown, never as zero.  Full grammar:
  [docs/design.md §2](../../docs/design.md).
* **Cache layout**: the URL uses the full relative filename
  (`<repo>/pkgs/stock/net-2.1.pkg`) while the cache stays **flat**:
  the cache file is the *basename* of the filename.  Package basenames
  must therefore be **unique repo-wide**, which is naturally true for
  `name-version.pkg` files.
* **sources** (`source.c`): the `repo=` string is classified explicitly
  into HTTP (`http://`), FILE (`file://` or a bare absolute `/path`, e.g.
  a mounted `/cdrom`), or RAW (`raw:<device>`); anything else is a hard
  error.  `src_fetch` pulls the catalog; `src_stage` makes one package
  ready for `pkgadd -d`, driven by read cost — a mounted plain `.pkg` is
  md5-verified **in place** and handed to `pkgadd` directly (no cache
  copy), while a downloaded / `dd`'d / `.Z` datastream is staged into the
  cache.  RAW is a self-describing slice: catalog at offset 0,
  `catalog.md5` at 32768, packages at the offsets the catalog records
  (see `source.h`; laid out by `gen-catalog.py --raw`).
* **install** (`install.c`): DFS dependency resolution with cycle
  detection (exit 5), topological deps-first order; *everything is
  staged and md5-verified before the first `pkgadd` runs*, so a bad
  source cannot leave a half-installed chain; `pkgadd`/`pkgrm` run via
  **fork/execv** (no shell quoting surface, exact argv logging, clean
  exit status) as `pkgadd [-R <target>] -n -a <admin> -d <file>
  <pkginst>` — the `-R` grows in only when `-R <root>` is given
  (`APKG_ROOT` and `-R` are independent: the former relocates the client,
  the latter the install target).  The one `system()` use is the
  documented `.Z` step: `zcat < f.pkg.Z > f.pkg` in the cache.  The child's
  **stdin is `/dev/null`**: the 1991 pkgadd prompts on some error paths even
  under `-n`, and with apkg's stdin inherited a batch/installer run blocked
  there forever (seen on metal, METAL-FIX.3).  Reading EOF makes pkgadd abort
  non-zero instead, so a prompt now surfaces as the ordinary exit **4** with
  the failing package named, never as a hang.
* **the admin file is materialised, never assumed** (`conf_adminfile()` in
  `conf.c`): the APKG package ships `/var/apkg/admin` as an `e` entry, so it
  is package-owned and `pkgrm APKG` **deletes** it (reproduced host-side with
  the heirloom engine: the whole `/var/apkg` went with it).  The old upgrade
  verb did `pkgrm` then `pkgadd -a /var/apkg/admin` and so bricked apkg on
  real hardware — the pkgadd died with *unable to open admin file* and the
  box was left with no apkg.  apkg now (re)creates the file immediately
  before every engine call, and never rewrites one an operator has edited.
* **upgrade removes nothing** (`cmd_upgrade`): a single `pkgadd` over the
  installed instance with a derived `<admin>.overwrite`
  (`instance=overwrite`) — the operator's own keys copied across, only the
  `instance=` line replaced.  Every failure path (fetch, md5, staging,
  pkgadd) therefore leaves the installed package in place.
* **`-f` is scoped to the named packages** (`is_named()`): forcing the whole
  dependency closure meant re-`pkgadd`ing the 2.3 MB engine package on a
  68LC060 — minutes of work before reaching what was asked for.  A *missing*
  dependency is still installed.  And an installed package whose catalog
  version is *newer* is no longer reported as a plain "already installed":
  named → refuse and point at `upgrade`; dependency → report the gap, count
  it satisfied, upgrade nothing.
* **installed state**: `<root>/var/sadm/pkg/<pkginst>/pkginfo` exists →
  installed; its `VERSION=` value is the installed version, shown as
  `(none)` when absent (stock Amix packages), and treated as older than
  any catalog version by `upgrade`.
* **version compare** (`vercmp.c`): split on `.`/`-`; numeric segments
  compare numerically, otherwise `strcmp`; missing segments count as 0.

## Configuration

`/etc/apkg.conf`, `key=value`, `#` comments. Since APKG 0.2.3 the package delivers it as
`e apkgconf`, installed by the class action script `i.apkgconf`: an existing file is kept on
install and upgrade, the shipped default is `/usr/apkg/lib/apkg.conf`, and a key the file does
not name takes its built-in default. A kept file that differs from the default shows in a plain
`pkgchk APKG`, like any edited SVR4 `e` file; `pkgchk -n APKG` is clean (NOTES.md 2026-10-06).

| key      | default                              |
|----------|--------------------------------------|
| repo     | `http://pkg.amigaux.org`             |
| cachedir | `/var/apkg/cache`                    |
| pkgadd   | `/usr/apkg/bin/pkgadd` (runtime fallback `/usr/sbin/pkgadd`) |
| pkgrm    | `/usr/apkg/bin/pkgrm` (fallback `/usr/sbin/pkgrm`)           |
| admin    | `/var/apkg/admin` — created on demand if missing; `upgrade` derives `<admin>.overwrite` from it with `instance=overwrite` |
| timeout  | `300` — seconds of network **silence** tolerated mid-transfer (an inactivity timer, *not* a cap on transfer duration) |
| connect_timeout | `30` — seconds for resolve + TCP connect |
| retries  | `2` — extra attempts after a *network* failure (a non-200 status is never retried) |
| retry_delay | `5` — seconds before the first retry; doubles thereafter |
| progress | `262144` — bytes between progress lines on stderr; `0` silences them, `-v` quarters the interval |
| bufsize  | `8192` — socket read buffer, clamped to 512–262144 |
| redirects | `1` — 301/302 hops followed; `0` follows none |
| rcvbuf   | `0` — **the TCP receive window; 0 = leave the stack alone.** An operator knob (STREAMS `INITQPARMS` as root), *not* a speed fix — see below |
| sndbuf   | `0` — `SO_SNDBUF`; `0` leaves the stack default |
| nameserver | *(empty)* — an IPv4 nameserver for the stub resolver; **repeatable**, tried in order; empty value clears the list. Empty = hosts file only, i.e. what apkg always did |
| dns_timeout | `5` — seconds per DNS query *attempt* |
| dns_retries | `2` — extra attempts per nameserver |

### `dns.c`: a stub resolver, because stock Amix has none

`gethostbyname()` on Amix reads `/etc/inet/hosts` **and nothing else** —
`resolv.conf` is inert, nothing reads it.  The repository is a *name-based
virtual host* (a bare-IP `Host:` is answered 404), so on a stock box "no
resolver" means "no repository" until somebody hand-writes a hosts line.
The Saku demo cards carry exactly such a line.

`dns.c` closes that for **apkg's own lookups and nothing else** — `telnet`,
`ftp` and the rest of the box still read `/etc/inet/hosts`.  Resolution is
three steps, in this order:

1. an IPv4 literal is used as it stands (the SVR4 `gethostbyname` need not
   accept dotted quads);
2. the **host database** via `gethostbyname()` — unchanged behaviour;
3. only if that says nothing, each configured `nameserver`, in order.

Hosts-first is the load-bearing choice: no box that resolves today can
regress when a nameserver is configured, and a line an operator wrote by
hand can never be shadowed by DNS.

It is a stub in the strict sense: one UDP A query per attempt, recursion
requested, no EDNS, no cache beyond the process, no search list, no TCP
fallback, no `resolv.conf`.  It follows a CNAME chain to an A record and
ignores TTLs.  Root is not required.  Defensive by construction: the socket
is `connect()`ed (the kernel drops anything not from the server asked); the
transaction id, QR bit, opcode and the echoed question must all match what
was sent; compression pointers must point **strictly backwards** (which
makes an infinite name impossible); every offset is bounds-checked; an A
record is believed only with class IN and rdlength 4.  Anything else is
discarded and the next attempt/nameserver is tried — never a partial answer.
`-v` reports which of the three steps answered, and which nameserver.

`dns.c` is compiled **only** into the HTTP-capable build; the FILE+RAW
static variant (`-DAPKG_NO_HTTP`) has no sockets at all, and the file
`#ifdef`s itself out entirely so its inclusion in `SRCS` cannot drag the
netconfig closure back in.

### `rcvbuf`: the window is not the lever, and that is measured

Amix's compiled-in 4096-byte receive window looks exactly like the
thing capping a single stream on a bandwidth-delay-bound path
(throughput ≤ window / RTT).  **It is not.**  Two server-side captures
of a real 68LC060 A4000D fetching from `pkg.amigaux.org` over
z3660eth settled it:

1. **`SO_RCVBUF` never reaches this tcp module.**  2026-09-14 23:57
   EEST, `Xcore-2.1.pkg`: apkg asked for 64 KB before `connect()`; the
   box advertised `win 4096` in its SYN and in **all 2999**
   steady-state ACKs, never anything else.  No MSS option in the SYN
   either, so the server sent 536-byte segments (5850 of them); RTT
   43 ms; 53.8 KB/s acked.  The burst structure is the tell:
   7×536+344 = 4096, every burst ending exactly on the window edge.
2. **Raising the window works — and makes it slower.**  2026-09-15,
   round 2: after an `INITQPARMS` of 16384 the box really did advertise
   `win 16384` in the SYN and every steady-state ACK of streams it had
   not yet opened.  Throughput went the wrong way.

| window | WAN throughput | server-side retransmits |
|---|---|---|
| 4096 (stock) | **~54 KB/s** | 64/6305 = 1.0 % |
| 8192 | ~32 KB/s | (loss zone) |
| 16384 | ~36–40 KB/s | 155/4328 = 3.6 %, 101/3525 = 2.9 % |

The binding constraint is an **RX-path loss cliff at ~8 segments in
flight** (~10 KB outstanding): ≤7 segments per burst lose 2–3 %, 8 lose
~60 %, ≥9 lose ~100 %, and every loss costs a server RTO.  The stock
4096 window admits at most 8 segments and therefore sits **exactly at
the loss-free edge** — near-optimal for this driver as it stands.  The
real lever is the RX drop mechanism (the Z3660 firmware discarding its
whole backlog on overflow, `ethernet.c:549-569`, and/or the 16.67 ms
poll quantum), and it lives in the driver and firmware repos.

**So the default is 0 and nothing here should raise it.**  On
z3660eth any window above 4096 is slower until the RX loss is fixed.
`rcvbuf > 0` is an operator knob for exactly the set-measure-revert
workflow that produced the table above.

When it is set, two mechanisms fire.  The one that works is the
privileged STREAMS
**`INITQPARMS`** ioctl (`<net/strioc.h>`, `iqp_type =
IQP_RQ|IQP_HIWAT`) issued with `I_STR` on a TCP stream, which rewrites
the `tcp` module's receive high-water mark.  Two properties of it are
load-bearing and both come from the source, not from guessing:

* **`sockmod` does not swallow it.**  Its write-side `M_IOCTL` switch
  ends in `default: putnext(q, mp)` (USL SVR4.2 `sockmod.c:2412`,
  `:2424-2427`), and the returning `M_IOCACK`/`M_IOCNAK` is passed back
  up the same way (`:487-496`, `:514-523`).  `tcp` then handles it in
  `tcpioctl()` (`tcp_main.c:568-575` → `initqparms()`).  No need to
  open `/dev/tcp` and reimplement `connect()` as a TLI `T_CONN_REQ`.
* **It changes the module's *default*, not this stream's queue.**
  `initqparms()` writes `minfo[i].mi_hiwat` — the `module_info`
  template (`netlib.c:148-179`) — and STREAMS copies that template into
  a queue's `q_hiwat` when the stream is **opened**
  (`strsubr.c:989`); `tcp_output()` then reads the live `q_hiwat` as
  `recvspace` for every segment (`tcp_output.c:141,:207,:404`).  So
  apkg issues it **before** the fetch socket exists, on a throwaway
  stream, once per process — and again on the fetch socket as a
  harmless belt in case the Amix-vintage `initqparms()` writes the live
  queue instead.  **The metal confirmed the template reading**: after
  `INITQPARMS 16384`, streams the box had not yet opened advertised
  16384.  The consequence to know: **every TCP stream opened on the box
  afterwards inherits the new default — box-wide, not apkg-wide, and
  standing until reboot.**  `rcvbuf=0` skips the ioctl entirely.

**Why apkg does not restore it on exit.**  It cannot learn what was
there before.  `INITQPARMS` is set-only (`netlib.c:148-179` has no
get), and `getsockopt(SO_RCVBUF)` cannot stand in for one because
`sockmod` initialises its cached `so->rcvbuf` to **0** at open
(`sockmod.c:264-265`) rather than from the module's hiwat.  The only
value apkg could "restore" is the stock compiled-in 4096 — a number it
never measured on this box, and one that would silently clobber a
deliberate system-wide setting someone else made.  Two more reasons
against: an apkg killed mid-fetch would not restore anyway, so the
guarantee would be false exactly when it mattered; and the knob's real
use is the set-measure-revert workflow, which spans several runs.  So
apkg **sets, and says so at warning level** (not merely under `-v`)
naming the box-wide scope and the way back.  Putting it back is
`rcvbuf=4096` on a root run, or a reboot.

`INITQPARMS` needs root (`drv_priv()` in `initqparms()`); `apkg
install` already runs as root, and a non-root apkg falls back to the
`SO_RCVBUF` request and says so under `-v`.  Its value is also capped
at 65535 because `iqp_value` is a 16-bit field.

All the SVR4 cites above are from the USL SVR4.2 reference tree,
matched to Amix by byte-identical Lachman headers in Amix's own
sysroots — *derived*, not read out of an Amix binary.  The constants
apkg uses are restated in `http.c` under its own names rather than
copied from the proprietary header; `make amix AMIX_CFLAGS='... 
-DAPKG_CHECK_STRIOC'` has the compiler prove the restatement matches
the real `<net/strioc.h>`.  The behaviour itself is **not** derived:
the two captures above are first-party measurements from the metal.

The default is 16384, not the 65535 protocol ceiling (Amix predates
RFC 1323 — no window scaling, so nothing larger is advertisable
anyway).  The binding limit is lower: MSS to a non-local host is
pinned at 536 and the Z3660 firmware RX ring has 32 usable slots, so a
window much past 32 × 536 ≈ 17 KB can put more in flight than the ring
holds — and that firmware **discards its whole queued backlog** rather
than back-pressuring, which TCP sees as a full-window loss and an RTO.
Bigger would be worse.  Raise it only once a capture says larger is
safe.  `sndbuf` has no effect on fetch throughput (apkg sends requests
and receives bodies); it exists so the pair is symmetric rather than a
trap.

The nine fetch keys are an apkg extension and exist because every
number on the fetch path has to be reachable from the config file.
`apkg -v` prints them all back on one `apkg: fetch: …` line, which is
how the test suite pins the defaults.

The local catalog lives in the cache directory's parent
(`/var/apkg/catalog` with the default `cachedir`).

### `APKG_ROOT`

The environment variable `APKG_ROOT` is prepended to every
**compiled-in default** path — `/etc/apkg.conf`, `/var/apkg/*`,
`/var/sadm/pkg`, and the pkgadd/pkgrm defaults + fallbacks.  It exists
so the test suite (and future `-R`-style image installs) can point the
whole client at a fake root.  Values read from a config file are used
literally and never prefixed.

## Tests

`make test` (or `sh tests/run-tests.sh`) runs the functional suite,
strictly on localhost: a fixture repository served by
`python3 -m http.server`, a second tiny server
([tests/redirect-server.py](tests/redirect-server.py)) for the 302
case, a third ([tests/slow-server.py](tests/slow-server.py)) that can
trickle a body out slowly or send headers and then go silent — the two
cases that tell an inactivity timer apart from a whole-transfer cap —
`pkgadd`/`pkgrm` shim scripts that log their argv (plus a failing
variant for the exit-4 path), and a fake `/var/sadm` tree via
`APKG_ROOT`.  Covered: update (with and without `catalog.md5`, bad
header, md5 mismatch, server down), list/search/info, download
(verify pass + corrupted file), install (dep-chain order from the
shim log, already-installed skip, `-f`, `-n`, missing dep, cycle,
unknown name, pkgadd failure), upgrade (newer/equal/VERSION-less/not
installed), remove, `.Z` decompression, the prompting-pkgadd fast-fail
(driven from a never-EOF FIFO under a timeout), catalog extension blocks
(known and unknown), the fetch-path config keys (defaults, every
override, every nonsense value refused, bufsize clamping, an unknown
key warned), retry behaviour (count, backoff, and that a 404 is never
retried), `redirects=0`, the socket-buffer knobs reaching the socket layer (the
`getsockopt` readback reported, including for `rcvbuf=0`, and pinned as
*not* proof TCP honoured it),
the inactivity semantics themselves (a 586 KB transfer that outlives a
2 s timeout while flowing, a stalled one that is killed promptly
and names the bytes it got, and a stalled one that is **retried** —
which is what caught the blocked-SIGALRM defect below), and the stub
resolver, and kernel space (SHA-256 vectors through
[tests/sha256-driver.c](tests/sha256-driver.c), the `#ext kpkg` parser and
its refusals, the 0.2.3 client built from git skipping the block, the
install record byte for byte, pre-flight, the trigger against a kbootset
mock for all five statuses, `-R`/`--journal`/`bootset=manual`/`-n`, a
transaction killed mid-pkgadd and finished by `apkg recover`, four impure
packages refused, the loader role and the C2-2 v3 key refusals, a
15-character name recorded under its 8-character pkginst, a several-name
`upgrade` as one transaction with one trigger, one kernel package per
line, a module's device node laid and kept out of its record, and device
entries refused outside a module package) — **442
assertions**, all required to PASS. A companion suite,
[tests/nohttp-variant.sh](tests/nohttp-variant.sh), builds the `-DAPKG_NO_HTTP` (FILE+RAW-only,
no-sockets) variant and adds **20** more.
[tests/kbootset-consumer.sh](tests/kbootset-consumer.sh) (**12**, not in
the count; reads the dlm kit from `$AMIX_DLM`, default `kernel/dlm` of
the amix checkout this directory is in, and without it says SKIP and exits 77) builds the
real kbootset with the kit's Makefile, has `tools/repo/gen-catalog.py`
describe a kernel package from its own sidecar, and lets apkg install it
and trigger it: gate 1 accepts apkg's record, gate 2 accepts the sidecar's
kabi/pin as they arrive in it, and a hand-written catalog with another kabi maps to exit 7.

The resolver has its own fake nameserver
([tests/fake-dns.py](tests/fake-dns.py)), one scripted behaviour per
instance: a correct answer, a CNAME chain built with compression pointers
and emitted A-record-first, `rcode 3`, a garbage answer section, a datagram
shorter than a DNS header, a correct answer carrying someone else's
transaction id, and one that never replies at all.

It also has its own **driver** ([tests/dns-driver.c](tests/dns-driver.c)),
and that split is not cosmetic.  Step 3 is reached only when the host
database said nothing, and on a test machine that is whatever NSS says —
unscriptable from the suite.  The bench host has a *wildcard* upstream that
answers every name, reserved `.invalid` ones included, so a test assuming
"an invalid name does not resolve" would have exercised nothing while
passing.  The driver calls `apkg_dns_query()` directly, so the fake server
is the only thing that can answer; the *ordering* is proved end-to-end
through apkg with names every machine agrees about, and the end-to-end
DNS-only fetch probes candidate host names with the same `gethostbyname()`
apkg uses and reports a SKIP if none of them genuinely fails.

## Spec deviations / choices of record

* Unknown package names given to `info`/`download` exit 1 (usage),
  while unresolvable names inside `install`/`upgrade` resolution exit
  5 — design.md's "dep cycle/missing" bucket.
* A `zcat` failure surfaces as exit 4 (install-step failure).
* The nine fetch keys in apkg.conf (`timeout`, `connect_timeout`,
  `retries`, `retry_delay`, `progress`, `bufsize`, `redirects`,
  `rcvbuf`, `sndbuf`) and the three resolver keys (`nameserver`,
  `dns_timeout`, `dns_retries`) are an extension.  `timeout` changed meaning on 2026-09-16: it was a 60 s
  **whole-transfer** cap, and is now a 300 s **inactivity** threshold.
  The old semantics killed a healthy 8.2 MB fetch on a real A4000D —
  that path runs ~37 KB/s, so the package needs ~220 s of continuous
  transfer.  The one constant deliberately *not* exposed is `HDRMAX`
  (64 KB): it bounds what a broken server can make the client
  allocate, and no operator has a reason to raise it.
* **`unblock_alarm()` (util.c) is not belt-and-braces.** A signal handler
  runs with its own signal blocked, and the block is lifted by *returning*
  from the handler — which a `longjmp` never does.  Whether `setjmp`/
  `longjmp` restore the mask is a libc-flavour question (`sigsetjmp(env,1)`
  does, `_setjmp` does not), and measured here it does **not**: after the
  first timeout `SIGALRM` stayed blocked, so the next `alarm()` was armed
  and never delivered.  That made `http.c`'s **retry** path hang forever on
  a second stall, with the shipped default `retries=2` — invisible until
  now because the stall test ran at `retries=0` and only ever took the
  first timeout.  `sigsetjmp`/`siglongjmp` were the other candidate; the
  Amix libc exports `sigsetjmp` but **not** `siglongjmp`, while
  `sigprocmask`/`sigemptyset`/`sigaddset` are all there.
* The catalog md5 covers the file **as transported** (the `.Z` file
  for compressed packages).
