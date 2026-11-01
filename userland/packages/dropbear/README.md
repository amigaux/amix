# dropbear — Dropbear SSH 2026.94 for Amix

An SSH server and client for Amix 1.1. It is one binary,
`/opt/amix/sbin/dropbear`, which runs as the name it is called by:

- `dropbear`, the server;
- `dbclient`, the client, also installed as `ssh`;
- `dropbearkey`, which makes keys;
- `scp`.

A boot script, `/etc/init.d/dropbear`, starts the server and makes its host
key at the first start. There are man pages for `dropbear(8)`, `dbclient(1)`
(with `ssh(1)` as an alias), `dropbearkey(1)` and `scp(1)`. The stock system
has no SSH.

    sh build/pkg/pkgbuild.sh userland/packages/dropbear      # build + roll (host)
    sh build/dist.sh recipes/dropbear                        # the same, in the build container

Package: `dropbear`, category `network`, set `extra`, MIT. The other licences of
its parts (libtomcrypt and libtommath, public domain; the OpenSSH- and PuTTY-derived
files, BSD/MIT) are in `/opt/amix/doc/dropbear/LICENSE`. It depends on
`amix-base` for `rc.subr`. At run time it needs `/dev/urandom`, the 1.1 random
module. Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`).

## Version: 2026.94

2026.94 is the current release. Upstream keeps a C89 CI job and a small-code
build, and the release has the algorithms a 2026 server expects:
curve25519, ML-KEM, ed25519 and chacha20-poly1305.

Source: `https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2`,
sha256 `e098034a…c41a6b1ae81`, with our copy in amigaux/amix-distfiles
(release `dropbear-2026.94`). The upstream `.asc` is a good signature from the
Dropbear release key `F734 7EF2 EE2E 07A2 6762 8CA9 4493 1494 F29C 6773`.

## Algorithms: lightest by default, never weak

The machines are 68030 to 68060 at 25 to 80 MHz, with no crypto hardware and
16 to 128 MB. Every algorithm the build does not offer is compiled out
(`localoptions.h`), so the binary carries no code that is never used. What is
offered was chosen by measuring each candidate on the box (below):

| Kind | Offered, in order | Out |
|---|---|---|
| key exchange | @KEX_ORDER@ | diffie-hellman-group14/16 (2048/4096-bit modexp), ecdh-sha2-nistp*, sntrup761x25519 |
| host key | ssh-ed25519; rsa-sha2-256 only with an RSA host key (off unless asked for) | ecdsa, ssh-dss, ssh-rsa (SHA-1) |
| user key | ssh-ed25519, rsa-sha2-256 | ecdsa, sk-* (FIDO), ssh-dss, ssh-rsa (SHA-1) |
| cipher | chacha20-poly1305@openssh.com, aes128-ctr | aes256-ctr, aes-gcm, every CBC mode, 3des, none |
| MAC | hmac-sha2-256 (with aes128-ctr) | hmac-sha2-512, hmac-sha1, hmac-sha1-96 |
| compression | none | zlib |

@ALGO_TEXT@

### The measurements

@TABLE@

## Porting

### Build (`build.sh`)

- **One multi-call binary** (`MULTI=1`, `PROGRAMS="dropbear dbclient dropbearkey scp"`).
  The four programs share libtomcrypt, libtommath and the protocol code, so
  one binary of @SIZE@ is smaller than four; the other names are hard links.
  `dropbearconvert` (OpenSSH key import) is not built.
- **libtomcrypt and libtommath are bundled and linked in statically**
  (`--enable-bundled-libtom`). No other program on the box uses them, so a
  shared library would only add a second file and the runtime linker's work.
  libc, libsocket and libnsl are the system's shared ones.
- **Off:** `--disable-harden` (its `-pie` and RELRO do not exist on this
  system), `--disable-zlib`, `--disable-pam`, `--disable-lastlog`,
  `--disable-largefile`.
- **`localoptions.h`** sets the algorithms and the paths
  (`/etc/dropbear/host_ed25519`, `host_rsa`, `dropbear.pid`; every name within
  the 14 bytes an s5 file system keeps), and leaves out X11, agent and
  Unix-socket forwarding, PAM and the askpass helper. Upstream's
  `DROPBEAR_SMALL_CODE` stays on (@SMALLCODE@).
- **`DROPBEAR_SVR_DROP_PRIVS 0`.** Since 2026.89 the server drops to the user
  right after authentication. It keeps a saved utmp group so it can still
  write the login records (`setresgid(-1, -1, utmp)`). SVR4.0 can't set a
  saved group ID by itself, and its libc writes `utmpx` only for root (there
  is no `utmp_update` helper). So the server switches user when it starts
  the session's shell or command, as Dropbear did before 2026.89. The
  session's pty, `utmpx` and `wtmpx` records are written as root, and `who`
  shows the session.
- **`port/amix-compat.h`, `port/amix-compat.c`** (put ahead of every source
  with `-include`, and linked in), for what SVR4.0 spells differently or
  lacks:
  - `struct timespec` is SVR4's `struct timestruc` (same members), and
    `suseconds_t` is `long`;
  - `nanosleep` uses `poll(2)` (at 60 Hz a sleep rounds up to a tick);
  - `vasprintf` uses the toolchain's C99 `vsnprintf`;
  - `utimes` uses `utime(2)`, so file times are whole seconds;
  - `inet_aton` uses `inet_addr`. Dropbear's bundled `getaddrinfo` parses a
    dotted quad with it before trying `gethostbyname`, which on this system
    reads `/etc/hosts` only;
  - `fnmatch` uses libgen's `gmatch(3G)` (`port/include/fnmatch.h`; scp passes
    no flags);
  - `SHUT_RD/WR/RDWR` are 0/1/2, and `IOV_MAX` is 16;
  - `O_NOFOLLOW` is 0. Dropbear passes it only next to `O_CREAT|O_EXCL`,
    which already refuses any existing name, symbolic links included
    (`tests/smoke.sh` checks this on the box).
- **pwgr:** `build/pkg/common/amix-pwgr.c` is linked in, so the binary
  defines `getpwnam/getpwuid/getgrnam/getgrgid` itself. This avoids the
  stock shared libc's first-call `getpwnam` crash. `getspnam` and `crypt`
  are libc's static members (`/etc/shadow`, the system's DES crypt).
- **`-fno-jump-tables` for `cli-runopts.c` and `svr-chansession.c`.** Two of
  their switches compile into dispatch shapes the 68060 gate's table scanner
  cannot size yet. Both are cold paths (option parsing, pty modes).
- **libtommath's include path** is appended to the driver's make `CFLAGS`
  (`override` in its Makefile); the driver's `CFLAGS` would replace it.

### Patches

| Patch | Why |
|---|---|
| `01-atomicio-read.patch` | Amix declares `read(int, void *, unsigned)`, and GCC 14's `size_t` is `unsigned long`: the same width but a different type, so `atomicio(read, …)` is an error. `amix_read` (`port/amix-compat.h`) is `read` cast to the type `atomicio` takes. |
| `02-scp-bwlimit-integer.patch` | `scp -l` parsed with `strtod` and computed in `double`, the only floating point in the program. On a 68LC040/68LC060 every FP instruction traps to the kernel's emulator. The limit is now a whole number of Kbit/s, computed in integers, and the binary carries no FPU instruction at all (checked with objdump). |

### 68LC060 and 68030: the 64-bit arithmetic

curve25519 and ed25519 (TweetNaCl-derived, `curve25519.c`), Poly1305 and ML-KEM
compute with 64-bit integers. GCC 14 with `-m68020-60` never emits the 64-bit
`MUL.L`/`DIV.L` forms a 68060 lacks; the products go through libgcc's
`__muldi3`/`__udivdi3`, which use 32-bit multiplies only. The 68060 gate
proves it for the shipped binary. None of this is floating point, and the
binary has no FPU instruction at all, so the FPU-less 68LC060 runs it without
the kernel's emulator. The known-answer tests (RFC 7748 X25519, RFC 8032
Ed25519, RFC 4231 HMAC-SHA-256, libtomcrypt's ChaCha20, Poly1305, AES and SHA-2
vectors) pass on both rows, and every other primitive's output on fixed
inputs matches the build host's byte for byte (`dbbench`, below). That
includes ML-KEM, sntrup761, RSA, ECDH and DH, which covers the big-endian and
32-bit word paths.

### Install

- **Host keys are made at the first start, never shipped.** The boot script
  runs `dropbearkey -t ed25519` from `/dev/urandom` when
  `/etc/dropbear/host_ed25519` is missing. With `dropbear_rsa=yes` in
  `/etc/rc.conf` it also makes a 3072-bit RSA key, which takes minutes on a
  68030, and passes it with `-r`. The keys are no object of the package, so no
  two machines share one, an update never replaces one, and `pkgrm` leaves
  them (and so `/etc/dropbear`). There are no install scripts.
- **No conffile.** Dropbear has no configuration file. Its settings are
  `dropbear=`, `dropbear_port=`, `dropbear_rsa=` and `dropbear_flags=` in
  `/etc/rc.conf`, which no package owns, so an upgrade never touches them.
  Each is documented in `dropbear(8)`, BOOT SCRIPT.
- **The boot script** follows amix-base's `rc.subr(1M)` convention:
  - `/etc/init.d/dropbear` is the file, linked as `rc2.d/S76dropbear` (after
    the network, S69) and as `K40dropbear` in `rc0.d` and `rc1.d` (before
    syslogd's K50);
  - it is on by default, since installing the package asks for an SSH server;
  - it logs its decisions with `rc_log`;
  - it does not start the server without `/dev/urandom`;
  - the server logs through `syslog(3)` (facility `auth`).
- **inetd instead:** `dropbear(8)` gives the `inetd.conf` line. With it the
  server uses no memory between connections, and each connection pays the
  program's start.

### Not here

- **SFTP.** OpenSSH 9.0 and later copy with SFTP by default; use `scp -O`
  against this system. An SFTP server would be its own port (it would go in
  `/opt/amix/libexec/sftp-server`, the path the server already asks for).
- **OpenSSH-format private keys** for `dbclient`: make keys with
  `dropbearkey` instead.

## Acceptance

@ACCEPT@
