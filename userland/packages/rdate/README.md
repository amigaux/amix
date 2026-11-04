# rdate — set the clock from a time server

openrdate 1.11, the portable form of OpenBSD's `rdate`, as
`/opt/amix/sbin/rdate`. It asks an SNTP server (`-n`) or an RFC 868 time
server for the time and steps the clock, or slews it with `adjtime`. HTTPS
needs a correct date, and a stock Amix never sets one from its battery
clock (the `setclk` year bug, grimoire quirk 7).

It has no configuration file, no daemon and writes no file. The base
system's `ntpsync(1M)` decides when it runs and against which servers
(`/etc/rc.conf`'s `ntp_servers`, `ntp_timeout`, `ntp_retries`): at boot,
which steps the clock, and every hour with `-a`. The page is `rdate(1M)`.

    sh build/pkg/pkgbuild.sh userland/packages/rdate      # build + roll (host)
    sh build/dist.sh recipes/rdate                        # the same, in the build container

Package: `rdate`, category `network`, set `base` (on every install).
Licences: rdate.c and rfc868time.c are under Christos Zoulas's 4-clause BSD
licence, ntp.c under N. M. Maclaren's and Cambridge's 3-clause one, and our
patch and `port/` are MIT. All three texts are in `/opt/amix/doc/rdate/`.

## Version: 1.11

1.11 (2022) is the newest release of
[openrdate](https://github.com/resurrecting-open-source-projects/openrdate):
the GitHub tag archive, sha256 `931c4ad1…4721`. Only `src/rdate.c`,
`src/ntp.c` and `src/rfc868time.c` are built. `ntpleaps.c` serves `-c`,
which this port drops (below).

## The interface, agreed with base

`rdate [-46anpsuv] [-t sec] [-r n] [-b sec] [-d msec] [-o port] host ...`

- **Every try is bounded.** `-t sec` (default 15) covers the name lookup,
  the connection and the exchange. A host gets `-r n` more tries (default 1)
  before the next one. One host costs at most (n+1)·sec seconds and about one
  more. The defaults are generous on purpose: a busy box lags, so a short bound would
  fail on a loaded machine, and the service runs in the background, so a
  long one costs nothing at boot.
- **Several hosts** are tried in order, with every address of each.
- **Exit codes** name the failure:
  - 0 set (or printed with `-p`);
  - 1 other (refused, no route);
  - 2 usage;
  - 3 host not found;
  - 4 timeout;
  - 5 reply refused (kiss-o'-death, leap indicator 3, inconsistent times);
  - 6 round trip over `-d`;
  - 7 setting the clock failed.

  `ntpsync` reads only 0 against non-zero.
- **Output:** on success, the date unless `-s`. With `-v`, `-p` or `-a`, one
  line `rdate: adjust local clock by -12.482113 seconds (192.0.2.1)`, with
  ` (adjtime)` or ` (instant change)` before the address when `-b` decided.
  `ntpsync`'s parser takes the number after "by" and the last bracket, so
  this wording is an interface. On failure, one stderr line per host that
  gave no time.
- **`-a`** steps a difference over `-b` seconds (default 60 with `-a`) and
  slews a smaller one, so an hourly run never sends the clock backwards
  under cron, and a first sync from 1970 still works.
- **Upstream's `-t`** (maximum round trip in milliseconds) is `-d` here, so
  that `-t` is the timeout. `-c` (leap seconds from
  `/usr/share/zoneinfo/right/UTC`) is gone: Amix has no such file.

## Porting

### Build (`build.sh`)

`STYLE=hooks`: the three sources and `port/amix-rdate.c` are compiled
directly with `-include amix-decls.h -include port/amix-rdate.h` and linked
with `-lsocket -lnsl`. Upstream's autotools require libbsd for
`arc4random`, which the patch no longer calls, and nothing else of what
configure works out is used. `post_build` checks the binary has no FPU
instruction and that it gets `settimeofday`, `adjtime` and `getaddrinfo`.

### Patch

| Patch | Why |
|---|---|
| `01-bounded-tries-integer-sntp.patch` | The interface above: an alarm per try, retries, several hosts, exit codes, the output lines, `-d` for upstream's `-t`, `-a` stepping over `-b`, no `-c`. SNTP in 64-bit fixed point instead of `double`: NTP timestamps stay 32.32 since 1900, and offsets are differences taken modulo 2^64, right within 68 years either way and across NTP's 2036 era change. A clock that booted at 1970 is set in one step. The program has no floating point, so it runs on an FPU-less 68LC040/68LC060 without the kernel's emulator (the Z3660's 68LC060 has none). A stratum 0 (kiss-o'-death) or leap indicator 3 reply is refused, not retried. A reply-less deadline is a timeout (4), not an error (1). The cookie comes from `/dev/urandom`. |

### `port/` (MIT)

- **`amix-rdate.h`:** what the 1992 headers lack:
  - `struct addrinfo` and its `EAI_*` codes;
  - `socklen_t` (SVR4.0 passes lengths as `int`);
  - `PF_INET6` (no IPv6: `-6` fails);
  - `settimeofday`, in libc but declared nowhere;
  - `inet_ntoa`.
- **`amix-rdate.c`:** `getaddrinfo`, `freeaddrinfo` and `gai_strerror` over
  `gethostbyname` and `getservbyname`, IPv4 only.
  - **A dotted quad** is used as it is, with no lookup. The cells run with
    DNS off, and the hosts-only resolver matches no numeric string.
  - **A service** that `/etc/inet/services` lacks falls back to its
    well-known port (ntp 123, time 37).
  - **A name is looked up in a child process.** The DNS resolver behind
    `libsockdns.so` retries an unreachable name server on its own timers and
    ignored rdate's alarm: 185 s under a 5 s bound, measured on both rows.
    The child writes the addresses to a pipe, and when the try's time runs
    out first, it is killed and the try is a timeout. It runs only when an
    alarm is pending, which rdate always arms.

### Setting the clock on Amix

- **Step:** `settimeofday()` is libc's BSD compatibility routine. It checks
  the `timeval` and calls `stime(2)` with the seconds, adding one when
  `tv_usec` is 500000 or more (read from `usr/ccs/lib/libc.so`'s
  `gettimeofday.o`). A step is exact to the second; only root may make it
  (`EPERM`, exit 7).
- **Slew:** `adjtime(2)` is a real system call on these kernels (number 138,
  `adjtime.o`), and it slews fast. To gain 20 s the clock ran about twice as
  fast, and the difference was gone in 12–16 s. To lose 20 s it stood still
  and never ran back: `date` did not go backwards across 24 samples. Hourly
  differences are fractions of a second, so the stand-still is short.
- **`gettimeofday`** goes through `hrtcntl`, to the microsecond.
- **Not done:** the `wtmp` "old time / new time" records `date(1)` writes,
  and the battery clock: `ntpsync` writes that after a sync.

### Names

The resolver is the system's:
- With DNS off (a stock system), only `/etc/hosts` is read, and a pool name
  fails at once with "host not found" (exit 3).
- With DNS on (`libsockdns.so` and `/etc/netconfig.DNS`), names resolve
  through `/etc/resolv.conf`. A dead name server costs one try's bound, not
  minutes.

## Acceptance

**Emulator, 2026-11-04: PASS**, on two emulated A4000s with a Z3660
(Amiberry; timings only compare with each other):

| System | Kernel |
|---|---|
| 1.1 A4000D disk, 68060, after first boot | 68060-261103-62 |
| 1.1 A4000D disk, 68030, after first boot | kern30m 68030-261101-68 |

- **Package:** `rdate-1.11-1.pkg`, rolled in the build container (gcc14
  dcfd12d), every gate passes. The program is 28 KB, has no FPU instruction
  and no 64-bit multiply or divide.
- **Install:** apkg's pkgadd rc 0 on both.
- **A clock in 1970 set right:**
  - `date 1105074470` put both clocks in November 1970;
  - `rdate -n -v -t 15 -o 12310 <host>`, through a relay on the host to
    pool.ntp.org (162.159.200.1), stepped them to 2026: "adjust local clock
    by 1767114613.116709 seconds", exit 0, `date` right afterwards. The
    emulators' network gets no UDP replies from outside, hence the relay.
  - A fake SNTP server on the host did the same, and so did RFC 868 over TCP
    and over UDP (`-p`).
- **Failures, each with one stderr line:**
  - no route (192.0.2.1, `-t 5 -r 1`): exit 4 after 10 s;
  - a name server that never answers: exit 4 after 10 s (185 s before the
    lookup moved into a child), no process left behind;
  - DNS off and a pool name: exit 3 at once;
  - a closed port: exit 4;
  - not root: exit 7, "Not owner";
  - a kiss-o'-death and leap indicator 3: exit 5 (against a fake server on
    the build host).
- **Slewing:** `-a` against a server 20 s ahead slewed ("(adjtime)"), and the
  clock caught up in 12–16 s. Against one 20 s behind, the clock stood still
  and never went backwards.
- **`tests/smoke.sh`:** PASS on both (usage, an SNTP read, the bounds, a name
  that does not resolve, `-6`, a set as root).
- **The fixed-point arithmetic, on the build host:** against a fake server
  49 years ahead and behind, offsets came out to the microsecond (±1546300800.25
  s), across 2036.
