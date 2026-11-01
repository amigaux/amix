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
| key exchange | mlkem768x25519-sha256, curve25519-sha256 (and its @libssh.org name) | diffie-hellman-group14/16 (2048/4096-bit modexp), ecdh-sha2-nistp*, sntrup761x25519 |
| host key, server | ssh-ed25519; rsa-sha2-256 only with an RSA host key (off unless asked for) | ecdsa, ssh-dss, ssh-rsa (SHA-1) |
| host key, client | rsa-sha2-256, then ssh-ed25519 (`patches/03`) | the same |
| user key | ssh-ed25519, rsa-sha2-256 | ecdsa, sk-* (FIDO), ssh-dss, ssh-rsa (SHA-1) |
| cipher | chacha20-poly1305@openssh.com, aes128-ctr | aes256-ctr, aes-gcm, every CBC mode, 3des, none |
| MAC | hmac-sha2-256 (with aes128-ctr) | hmac-sha2-512, hmac-sha1, hmac-sha1-96 |
| compression | none | zlib |

Why this order, from the table below:

- **Key exchange.** Two X25519 operations are the whole cost of
  curve25519-sha256 for each side. ML-KEM-768 adds about 0.1 s to the server
  (one encapsulation) and 0.25 s to the client (key generation and
  decapsulation), 3 to 8 per cent. So the post-quantum hybrid
  mlkem768x25519-sha256 stays first, as upstream has it. It costs about 43 KB
  of the binary. With it, a session recorded today cannot be decrypted later
  by a quantum computer, and OpenSSH 10.1 and later warn about a session
  without it. Diffie-Hellman group14 costs 23 times curve25519 (two 2048-bit
  exponentiations, over a minute on the emulated 68030); the NIST P-256 ECDH
  costs twice curve25519; the client's sntrup761 key generation alone costs
  more than curve25519. All three are compiled out.
- **The server's host key.** The server signs once per connection: 3.2 s for
  ed25519 against 38 s for RSA-2048 and 130 s for RSA-3072 (Dropbear's RSA
  signature does no CRT). So the boot script makes only an ed25519 key. An
  RSA key, for a client without ed25519 (OpenSSH before 6.5, 2014), comes
  only with `dropbear_rsa=yes`.
- **The client's host key.** The client verifies once per connection, and
  verifying is the other way round. rsa-sha2-256 (e = 65537) takes
  0.4–0.9 s; this ed25519 (TweetNaCl's, which does two full scalar
  multiplications) takes 6–11 s. The client's order picks the algorithm, so
  `dbclient` asks a server for its RSA key first (`patches/03`) and uses
  ed25519 when the server has nothing else. Both are secure; RSA-2048 is
  NIST's 112-bit level, allowed through 2030.
- **User keys** follow the same arithmetic. On the box as a server, an
  ed25519 user key costs 8 s to verify and an RSA-3072 one under 1 s. On
  the box as a client, an ed25519 key costs 3 s to sign with and an RSA key
  38 s (2048 bits) to 130 s (3072). So: an ed25519 key for logging in *from* the box, and an RSA
  key is the faster one for logging in *to* it. Both work.
- **Cipher.** chacha20-poly1305 and aes128-ctr with hmac-sha2-256 move bulk
  data at the same rate. For the small packets of an interactive session
  chacha20-poly1305 is twice as fast (one primitive and a cheap MAC, against
  AES plus two SHA-256 compressions per packet). It comes first, with
  aes128-ctr as the fallback for peers without it. hmac-sha2-512 halves the
  rate, AES-GCM (libtomcrypt's table-free GHASH) runs at a tenth of it, and
  aes256-ctr adds cost for no gain at this level. All are compiled out.

### The measurements

`dbbench` (built from Dropbear's own `curve25519.c`, `mlkem768.c`,
`sntrup761.c`, `dh_groups.c` and its bundled libtomcrypt and libtommath, with
a fixed random stream, no `/dev/urandom` needed) times each primitive in CPU
time (`times(2)`, 60 Hz). It ran on two emulated rows, both Amix 1.1:

- **68030** with a 68882 (kernel 68030-261027-20);
- **68LC060** with no FPU (kernel 68060-261028-61).

Both are the Amiberry interpreter at `cpu_speed=max`, not cycle-exact, so the
figures are **relative only**. Compare algorithms on one row, and compare the
two rows only as ratios. A real machine's numbers will come from the metal
boxes. The shipped build is `DROPBEAR_SMALL_CODE` (the "small" columns); the
"fast" columns are the unrolled build.

Time per operation, ms (emulated):

| Operation | 030 small | 030 fast | LC060 small | LC060 fast |
|---|---:|---:|---:|---:|
| X25519 (one scalar multiplication) | 1521 | 1750 | 1458 | 1567 |
| ML-KEM-768 key generation | 111 | 110 | 114 | 94 |
| ML-KEM-768 encapsulation | 104 | 126 | 115 | 103 |
| ML-KEM-768 decapsulation | 131 | 192 | 135 | 105 |
| sntrup761 key generation | 4700 | 4283 | 3950 | 3892 |
| sntrup761 encapsulation | 155 | 134 | 125 | 128 |
| sntrup761 decapsulation | 296 | 258 | 312 | 267 |
| DH group14, one 2048-bit exponentiation | 38467 | 33100 | 31717 | 33567 |
| ECDH P-256 key generation | 3467 | 3833 | 2883 | 2775 |
| ECDH P-256 shared secret | 3217 | 3767 | 2650 | 2444 |
| Ed25519 key generation | 3225 | 3258 | 3317 | 3442 |
| Ed25519 sign | 3242 | 3925 | 3167 | 2658 |
| Ed25519 verify | 8133 | 10667 | 7950 | 5717 |
| RSA-2048 sign (as Dropbear: no CRT) | 38517 | 45383 | 34517 | 70900 |
| RSA-2048 verify | 525 | 410 | 429 | 471 |
| RSA-3072 sign | 130067 | 108900 | 119067 | 106650 |
| RSA-3072 verify | 848 | 869 | 906 | 755 |

One SSH packet's cipher and MAC, KB/s (emulated), for full 16 KB packets and
for 64-byte (keystroke-sized) ones:

| Cipher + MAC | 030 16 KB | 030 64 B | LC060 16 KB | LC060 64 B |
|---|---:|---:|---:|---:|
| chacha20-poly1305@openssh.com | 230 | 142 | 247 | 153 |
| aes128-ctr + hmac-sha2-256 | 226 | 72 | 250 | 75 |
| aes256-ctr + hmac-sha2-256 | 230 | 69 | 237 | 70 |
| aes128-ctr + hmac-sha2-512 | 106 | 15 | 124 | 19 |
| aes128-gcm | 24 | 16 | 23 | 16 |

What one connection costs each side, from the rows above (030 small, emulated
s):

| | key exchange | host key | total |
|---|---:|---:|---:|
| server, mlkem768x25519 + ed25519 | 3.0 + 0.1 | sign 3.2 | 6.4 |
| server, curve25519 + ed25519 | 3.0 | sign 3.2 | 6.3 |
| server, DH group14 + RSA-2048 | 77 | sign 38.5 | 115 |
| client, mlkem768x25519, RSA host key | 3.0 + 0.24 | verify 0.5–0.85 | 3.8–4.1 |
| client, mlkem768x25519, ed25519 host key | 3.0 + 0.24 | verify 8.1 | 11.4 |

Then add the user's authentication: a password costs one DES crypt, and a key
costs what the user-key bullet above says. The end-to-end handshake times
measured from the host are under Acceptance.

`DROPBEAR_SMALL_CODE`: the unrolled build is 17 KB larger and measures no
faster here. The interpreter models no instruction cache, and that cache is
what decides the question on a 68030 (256-byte I-cache) and a 68060 (8 KB).
So the shipped build keeps upstream's small code until the metal boxes say
otherwise.

## Porting

### Build (`build.sh`)

- **One multi-call binary** (`MULTI=1`, `PROGRAMS="dropbear dbclient dropbearkey scp"`).
  The four programs share libtomcrypt, libtommath and the protocol code, so
  one stripped binary of 285 KB (277 KB text, 4 KB data, 9 KB bss) is smaller
  than four; the other names are hard links.
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
  `DROPBEAR_SMALL_CODE` stays on (see the measurements).
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
