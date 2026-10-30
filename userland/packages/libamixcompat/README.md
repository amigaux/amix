# libamixcompat — the recipe

**Package `acompat` 0.1** — the missing-libc shim every other port in this repo links.
First-party C89, BSD-2-Clause, no upstream.

    sh build/pkg/pkgbuild.sh userland/packages/libamixcompat

## Why this exists

`grep -c 'id: *SHIM-' registry/*.yaml` is the argument: 17 of the 23 candidate packages carry a
blocker that this library closes. One shim written once kills the class — that is standing decision
**D10**, and it is why this is the first thing built.

## Scope — measured, not assumed

Every symbol here was chosen because `m68k-cbm-sysv4-nm $SYSROOT/usr/lib/libc.so.1` says it is
absent, and every header because the file does not exist. Reproduce it:

```sh
# from this repository's root; AMIX_CROSS_ENV overrides the sibling default
. "${AMIX_CROSS_ENV:-../gcc-cross-amix/build/env.sh}"
for s in snprintf vsnprintf setenv unsetenv strcasecmp strncasecmp mkstemp usleep gettimeofday; do
    printf '%-14s' "$s"
    m68k-cbm-sysv4-nm "$AMIX_SYSROOT/usr/lib/libc.so.1" | awk -v s="$s" '$NF==s{printf "%s", $(NF-1)}'
    echo
done
```

All nine come back blank. `_abi_gettimeofday` comes back `T`.

| Provided | Because |
|---|---|
| `snprintf` / `vsnprintf` | Absent, and not even *declared* in `stdio.h`. **Long-long capable** — SVR4.0's printf has no `ll` modifier at all, so `%llu` against libc does not print a 64-bit number, it desynchronises the varargs. |
| `setenv` / `unsetenv` | Only `putenv` exists, and it keeps the caller's pointer. There is no SVR4 primitive that *removes* a variable. |
| `strcasecmp` / `strncasecmp` | Absent from libc, present in `libresolv.a`, **declared in no header** — so a program that links `-lresolv` compiles every call against an implicit `int` declaration. |
| `mkstemp` | Only `mktemp` exists, which picks a name and leaves the race open. |
| `usleep` | Only `sleep(3)`. Built on `poll(2)`, not `setitimer`, so it does not collide with the caller's own timers. |
| `gettimeofday` | libc exports `_abi_gettimeofday` instead, and `<rpc/types.h>` hides that behind a `#define`. See below. |
| `<stdint.h>`, `<strings.h>`, `ssize_t` | Do not exist. |

## Three findings this recipe established

**1. `_abi_gettimeofday` takes ONE argument, not two.** Disassembling it out of `libc.so.1` settles
a question no header answers: it reads `%fp@(8)` and never touches `%fp@(12)`, so there is no
timezone parameter underneath. It treats a NULL argument as a successful no-op, reads the clock via
`_abi_hrtcntl(1, 1, 0, &buf)`, and returns 0 or −1. The shim therefore accepts the two-argument BSD
signature every caller writes and **discards `tzp`** — the only honest option, since there is nothing
to fill it from. Details and the disassembly are in [`src/timeofday.c`](src/timeofday.c).

**2. The archive is `libacompat.a`, not `libamixcompat.a`.** The root filesystem is s5 and its
directory entries truncate at 14 bytes. `libamixcompat.a` is 15, so it would install as
`libamixcompat.` and no `-l` flag would ever find it — a package that installs cleanly and is
unusable. Every basename in the prototype is now checked against that limit mechanically by
`build/pkg/common/pkgroll.sh`, so the next recipe cannot rediscover this the hard way.

**3. `-U__STDC__` is not needed here, and the build says so on purpose.** docs/porting.md §2.4 says to
try it before believing a header. This library was built both ways and the objects compared
byte-for-byte: identical, because nothing in this source touches a `__STDC__`-gated declaration
(`struct timeval` is gated on `_POSIX_SOURCE`, not on `__STDC__`). The flag is therefore *not*
applied — a flag that changes nothing leaves the next reader unable to tell which rule the build was
obeying. What the build does obey is the other half of that section: **never** `-ansi`, **never**
`-D_POSIX_SOURCE`, because on this vintage they *remove* API.

## Evidence

Two independent tests, because they prove different things:

- **`tests/host-diff.c`** — builds this exact source on the host and diffs it against glibc's
  `snprintf` over ~5 200 combinations of format, value and buffer size, comparing **both** the bytes
  and the return value. It proves the *algorithm*; it cannot say anything about m68k code
  generation. It runs first in `build.sh` and its failure is fatal, because discovering an algorithm
  bug at the far end of a bench cycle costs an order of magnitude more.
- **`tests/compat-test.c`** — cross-linked against the archive being packaged, **shipped inside the
  package** at `/usr/local/bin/acompat-test`, and run on the box after `pkgadd`. It proves the
  *payload*, on this libc and this code generator. It prints the archive's compiled-in version
  first, so a stale copy on the box cannot pass for a fresh one.

Plus the gates in `build.sh`: no imported assembly, the artifact really is an m68k SVR4 ELF, the
**D4** 68LC060 scan (`objdump -d` shows no `mulu.l`/`muls.l` with a `Dh:Dl` destination), and a
printed list of the executable's undefined symbols so the libc surface it actually depends on is
reviewable before anything is pushed.

`%s` of a NULL pointer is undefined behaviour and the two live traditions differ when a precision
truncates the substitute string: glibc emits nothing, BSD emits the truncation. libacompat follows
BSD (`%.3s` → `"(nu"`), so that case is asserted explicitly rather than diffed. `%p` prints `0x0`
for NULL, the SVR4/BSD spelling, not glibc's `(nil)`.

## Deliberate omissions

- **`%n` is not implemented.** It is the format-string-attack primitive, nothing in this repo's
  consumers needs it, and a shim that quietly provides it hands every consumer a write-anywhere
  gadget. It is treated as an unknown conversion and echoed literally.
- **Float conversions are delegated to libc's `sprintf`**, not reimplemented. Correctly-rounded
  binary-to-decimal is a large subtle job whose only reward here would be output that *disagrees*
  with every other program on the box. Consequence inherited, not introduced: on a part with no
  68881/68882 those conversions die with SIGSYS inside `_doprnt`.
- **`<strings.h>` declares only what this library provides.** `bcopy`/`bzero`/`index`/`rindex`/`ffs`
  live in `/usr/ucblib` and are *not* declared here — turning a clean "undefined symbol" into a
  puzzle would defeat the point of making the libc surface honest.
- **The `getpwnam` family (D3) is not here yet.** It is a different shape of fix — the executable
  must *define* those symbols so its own globals win at static link time — and it belongs with the
  first package that maps uid→name. Recorded in the registry, not silently dropped.
- `inttypes.h`, `stdbool.h`, `wchar.h`, `fnmatch`, `glob`, `random`, `daemon`, `getrusage` and
  `nanosleep` are in the registry's eventual scope and are **not** in 0.1.
