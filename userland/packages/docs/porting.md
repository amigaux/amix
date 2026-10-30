# PORTING.md — what porting modern software to Amix actually takes

The standing guide every port recipe in this repo inherits. It exists to answer one question
before anybody writes a recipe: *why can't we just fetch this from the net and build it?*

**Citation policy.** Every hard claim carries a source. Sibling-repo citations are
workspace-relative (`../gcc-cross-amix/Makefile:589`). Claims proved by running the toolchain on
this machine are marked **[measured]** with the command that proves them. Claims the family has
not established are marked **UNVERIFIED** and must not be repeated as fact.

**What a `../…` citation is, and is not.** `../<repo>/…` names a **sibling Amix repository**
checked out beside this one — `../gcc-cross-amix`, `../amix-packagemanager`, `../grimoire-amix`,
`../amix-kerntools`, `../amix-040-060-port` (see github.com/jusii; not all of them are public yet) —
and `../tmp/<date>-<topic>/…` names one of the **maintainer's dated research notes, which are not in
version control**. A citation here is a **provenance record, not a followable link**: it says where a claim was measured, precisely enough
for a maintainer to re-derive it, not that a reader can click through to it. Stripping them would
make a measured claim indistinguishable from a repeated one, which is the one discipline this guide
exists to enforce — so the highest-value claims carry their measurement *inline* as well as cited.

Two citation hazards worth knowing:

- **`grimoire-amix/llms-full.txt` is stale** — generated 2026-07-31, while `docs/` has later
  commits carrying exactly the FP and load-average material. Where the two differ, cite
  `../grimoire-amix/docs/...`.
- `$SYSROOT` means the cross toolchain's AMIX sysroot
  (`~/opt/amix-cross/m68k-cbm-sysv4/sysroot`), a copy of a **licensed** AMIX installation, never
  committed anywhere (`../gcc-cross-amix/README.md:19-34`). Those citations are reproducible by
  anyone with their own sysroot.

---

## 1. The target, honestly

| Fact | Value | Source |
|---|---|---|
| OS | Amiga Unix (Amix) 2.1 / 2.1c — AT&T **SVR4.0**, 1992 | `../amix-packagemanager/docs/design.md:4-5`; stock kernel dated `Mar 20 1992` (`../tmp/2026-08-27-metal-opportunistic/RESULTS.md:28`) |
| CPU (stock) | **68020 or 68030 with a real MMU**. Stock Amix has **no 68040/68060 support** | `../grimoire-amix/llms-full.txt:162` |
| FPU (stock) | **68881 or 68882 mandatory — there is no soft-float build** | `../grimoire-amix/llms-full.txt:207`, `:1019`, `:4463` |
| RAM (stock) | **Retracted 2026-09-15: the old "4–16 MB Fast RAM, >16 MB mis-maps the SCSI drive" claim had no first-party observation anywhere in the family.** The real limit is **describable RAM**, which fails silently rather than corrupting disk — **≈64 MB on the stock 030 kernel** (the bench golden runs 64 MB daily; the owner runs the stock 030 line at ≥80 MB), **≈128 MB on the 040/060 kernels** on real silicon | `llms-full.txt:162` (retracted); `../amix-kerntools/docs/ram-limits-reconciliation.md` |
| RAM (family rigs) | Both configs are measured working points, not the ceiling: 16 MB proven for early packaging work; the bench golden runs 64 MB daily; 128 MB proven on the Z3660 metal rig under the 040/060 kernel | `../amix-packagemanager/NOTES.md`; `../tmp/2026-08-27-cputest-amix-research/B-amix-feasibility.md:361-362`; `../amix-kerntools/docs/ram-limits-reconciliation.md` |
| Disk | **~44 MB free** on the metal box's root (`31420 used / 44419 avail` KB) | `B-amix-feasibility.md:358-359` |
| Binaries | **ELF 32-bit MSB, Motorola m68k, version 1 (SYSV), dynamically linked** | `../gcc-cross-amix/README.md:104-108` |
| Clock tick | `HZ` = **60** | `../amix-kerntools/tools/amix-bench/build-fieldkit.sh:41-44` |
| Page size | **Measured 2048** on the stock 2.1 kernel; 040/060 kernels expected 4096. **Never hard-code it.** | `../amix-kerntools/CHANGELOG.md` (2026-08-27 amix-bench entry) |
| Root filesystem | **s5** — directory entries truncate to **14 bytes** | `../amix-packagemanager/NOTES.md:92-95` |
| System date | **Capped at 1999** by a kernel Y2K limitation | `llms-full.txt:4735` |

The metal box this family now runs (A4000 + Z3660, socketed **MC68LC060 rev 4, no FPU** —
`../tmp/2026-08-28-fpe-r13-metal/RESULTS.md:4`) is *outside* the stock envelope on both CPU and
FPU. It works because of the 040/060 port lane's own kernel work. **A port must not assume that
kernel**: target stock Amix unless a recipe says otherwise.

### On-box compilers — there are two, and neither is modern

The box carries the stock AT&T **SGS `cc`** *and* **GCC 2.7.2.3 for Amix**, distributed as an
installable package (`llms-full.txt:6877`, `:7446`). The boot lane additionally found a
Commodore-patched **`GNU GCC version 1.40.5 (68k, SGS/AT&T syntax)`** at `/usr/public/bin/gcc` —
*"a Commodore-patched gcc 1.40 that exists nowhere else"*
(`../amix-kerntools/docs/boot2-040.md:70-72`).

**Cross-build everything host-side.** The on-box compilers matter for two reasons only: some
things can *only* be built on the box (Amix's `boot2` is compiled `-fpcrel`, an SGS-only option
our cross gcc rejects — `../amix-kerntools/docs/boot2-040.md:66-67`), and their existence is why
the target's headers are written for a K&R compiler, which is §2.4's trap.

### ★ The FPU is not optional, and the failure is disguised

Stock Amix **requires** a 68881/68882. On a part without one, the F-line trap's stock mapping is
**`SIGSYS`** — *"Bad System Call - core dumped"*, exit 140 — **not** SIGILL or SIGFPE. And the
blast radius is far wider than programs that compute with floats:

> *"libc's `_doprnt` carries FP instructions on its `%e`/`%f`/`%g` conversion paths, so **any
> program that prints a float dies inside libc** — `df -k` and `uptime` die in the print call, not
> in their own arithmetic."*
> (`../grimoire-amix/docs/how-it-works/quirks.md:193-199`)

`awk` is unconditionally in that set: it holds every number as a C `double`, so
`awk 'BEGIN{print 1+1}'` dies too (`quirks.md:206-208`). The triage rule is
*"program dies with SIGSYS in a print call" means FP-in-libc, not a syscall bug* —
ask "does it print a float?" first (`quirks.md:201-202`).

**Porting consequences.** (a) Anything grepping for illegal-instruction traps misses every one of
these. (b) A tool that merely *formats* a number inherits an FPU dependency it never asked for.
(c) On the 040/060 lane's FPE kernel, FP is emulated and correct — the family proved IEEE-754
behaviour and exact `%e/%f/%g` conversion at every magnitude including subnormals
(`../tmp/2026-08-27-fpe-workload/RESULTS.md:198-212`) — but it is *slow*, and that kernel is not
what a stock box runs.

---

## 2. Toolchain constraints

The cross toolchain is `m68k-cbm-sysv4`: **gcc 2.7.2.3** and **binutils 2.8.1**
(`../gcc-cross-amix/README.md:114-122`, `llms-full.txt:7474`). Those versions are not nostalgia —
they are the last that target this ABI. Everything below follows from that pairing.

### 2.1 Language level: C89, and not all of it

**[measured]** `m68k-cbm-sysv4-gcc -m68020 -c` on one-line probes per feature:

| Feature | Accepted? |
|---|---|
| `//` line comments | **yes** (gcc 2.7 extension) |
| `long long` | **yes** — libgcc supplies `__udivdi3`/`__umoddi3`/`__lshrdi3` (`../gcc-cross-amix/Makefile:468-469`) |
| Designated initializers (`.a = 1`) | **yes** |
| `inline` | yes, but kernel-style builds pass `-Dinline=__inline__` (`../gcc-cross-amix/README.md:210-214`) |
| **Declarations after statements** | **NO** — `parse error` |
| **`for (int i = 0; ...)`** | **NO** — `parse error` |

**C99 is out**, and the two C99-isms in almost every modern codebase — a declaration after a
statement, and a loop-scoped index — are hard parse errors. There is no `-std=c99` to reach for.

**C++ is not available at all**: *"C++ / g++: not complete yet"*
(`../gcc-cross-amix/README.md:16`; `llms-full.txt:7369`). A C++ tool is out of scope today.

The house rule for portable target code, and why it goes further than C89:

> *"C89, on purpose: no //-comments, no declarations after statements, no `long long`, no variadic
> macros. The cross compiler is gcc 2.7.2.3 and the field target may be an even older vendor cc."*
> (`../amix-kerntools/tools/amix-bench/src/bench-compat.h:50-52`)

Code that must also build with the *on-box* compiler is written in **K&R**, not just C89 — see
`bench-compat.h:111-122`, whose functions carry K&R parameter lists.

### 2.2 ★ The wrapper is the compiler — bypass it and you get wrong code

`m68k-cbm-sysv4-gcc` is **not** the compiler. It is a shell script
(`../gcc-cross-amix/amix-gcc-wrapper.sh`) that runs the real `gcc.real -S`, **post-processes the
assembly** through `fix_asm`, and only then assembles (`amix-gcc-wrapper.sh:187-200`). gcc 2.7.2.3
emits **SGS** syntax; GNU as 2.8.1 reads a different dialect. `fix_asm` bridges them, repairing
six miscompiles:

| Fixup | What breaks without it | Cite |
|---|---|---|
| `.swbeg` → `.long` | GNU as emits 0 bytes; every `switch` case entered **4 bytes late** | `amix-gcc-wrapper.sh:25-34` |
| `tdivs.l`/`tdivu.l` → `divsl.l`/`divul.l` | Every **variable-divisor `/` and `%`** returns garbage (`351 % 151` → `-2147408448`) | `amix-gcc-wrapper.sh:36-55` |
| `fsgldiv.s`/`fsglmul.s` → `.x` | Any `float` multiply or divide **fails to assemble** | `amix-gcc-wrapper.sh:57-87` |
| Bit-field `{#0:#32}` → `{&0:&32}` | `#` is a *comment* introducer; the instruction silently vanishes | `amix-gcc-wrapper.sh:89-127` |
| **`cmp`/`fcmp` operand swap** | see below | `amix-gcc-wrapper.sh:131-184` |

**The `fcmp` defect is the one every port inherits.** `config/m68k/sgs.h` defines `SGS_CMP_ORDER`,
so gcc prints compare operands reversed from what GNU as expects. Two failure shapes, and **one is
silent**:

- FP register vs **memory** — rejected outright: ``Error: operands mismatch -- statement `fcmp.d %fp0,16(%fp)' ignored``. Loud.
- FP register vs **FP register** — still *valid syntax*, so it assembles to a **different
  encoding** (`fcmp.x %fp2,%fp0` = `f200 0838`; `fcmp.x %fp0,%fp2` = `f200 0138`). `FCMP` computes
  destination minus source, so **every `a > b` between two doubles answers `b > a`**, with no
  diagnostic anywhere. (`../gcc-cross-amix/Makefile:589-604`)

This shipped. `iobench` reported `kb_s=0.0 ops_s=0.0 us_per_op=0.0` beside a perfectly correct
`ticks=712 real=11.867`, because its `secs > 0.0` **guard** evaluated as `0.0 > secs` and was false
for every possible run (`../amix-kerntools/CHANGELOG.md:455-461`). The arithmetic was right all
along.

**Current state — verify, don't trust either repo's prose.** The wrapper *has since been fixed*
and `make test-fcmp` gates it (`../gcc-cross-amix/Makefile:620-658`). **[measured]** compiling
`int rr_d(double a,double b){double x=a*b,y=a+b;return x>y;}` at `-O` through the wrapper:

```
f200 0523   fmulx %fp1,%fp2
f200 0138   fcmpx %fp0,%fp2      <- destination IS the fmul result: correct order
f22e 5438   fcmpd %fp@(16),%fp0  <- memory form assembles: the loud shape is fixed too
```

But `../amix-kerntools/tools/amix-bench/build-fieldkit.sh:85-96` still carries a **no-`fcmp` build
gate** written when the wrapper swapped only `cmp.b/w/l`, and still applies `-Dfloat=double` as an
`fsgldiv` workaround (`:51-68`, `:138`). Belt-and-braces, not a contradiction — but **the two repos
disagree about what the wrapper can do**. Check the wrapper's actual behaviour.

**The load-bearing consequence:**

> **`fix_asm` only runs when you compile through the wrapper.** `m68k-cbm-sysv4-gcc` passes `-S`
> straight to the real compiler with **no fixups at all** (`amix-gcc-wrapper.sh:234-236`:
> `if test "$has_S" = yes; then exec "$real" ...`).

A build system that compiles to `.s` and assembles separately, that finds `gcc.real`, or that
drives `as` itself, loses every repair above. **[measured]** the same float source through
`gcc.real -S` + `as`:

```
raw.s:14: Error: operands mismatch -- statement `fsglmul.s %fp2,%fp0' ignored
raw.s:16: Error: operands mismatch -- statement `fsgldiv.s %fp1,%fp0' ignored
```

Here it failed loudly. The `fcmp` register/register shape would not have.

**Two more wrapper-era rules:**

- **The D4 gate was itself a victim of this law.** Until 2026-09-26 it grepped `objdump -d`
  for `mulu.l …,%dH:%dL`; binutils 2.8.1 prints `mulul %fp@(12),%d1,%d2`, so it never matched and
  passed everything. It now reads opword + extension word and self-tests (`recipes/README.md`).
- **The family law: verify the *encoding*, never the exit status.** *"the toolchain has a family
  of silent mis-encodes, and the rule that covers all of them is: verify the encoding
  (`objdump -d`), never the exit status"*
  (`../grimoire-amix/docs/drivers/toolchain.md:200-202`). Inline `asm` in a `.c` file is a carrier
  for this: what survives gas's comment scrubber may itself be a valid instruction, assembled with
  **no diagnostic** — `nop #junk here` assembles to a bare `nop`, exit 0 (`toolchain.md:196-199`).
- **Footgun:** *"The wrapper's `-c foo.s` with no `-o` silently destroys the source"*
  (`../grimoire-amix/docs/drivers/toolchain.md`, section heading after line 228).

**Recipe rule:** always build via `CC=m68k-cbm-sysv4-gcc`; never let a Makefile call `$(AS)`
directly or split compile-and-assemble. Old Makefiles hardcode native tool names in recipes —
rewrite them to `$(CC)`/`$(LD)`/`$(AR)` so the toolchain can be injected
(`../gcc-cross-amix/README.md:180-208`).

### ★ 2.2.1 Four more wrapper behaviours, all silent — **[measured]** 2026-08-28 / 2026-08-30

The wrapper hand-rolls its own `ld` command line *and* its own include path, and that has
consequences no ordinary `gcc` driver has. The first three were hit building the first two recipes;
the fourth by `gzip` in BATCH-1.

| # | Behaviour | What it looks like |
|---|---|---|
| 1 | **`-E` was not implemented.** It fell through the arg parser's catch-all into the *ld-flag* bucket, so the wrapper **linked** instead of preprocessing — exit 0, linker complaint on stderr, nothing on stdout. **FIXED 2026-08-29** (`gcc-cross-amix` 3c2d272) — `-E` is now dispatched to the real compiler with the wrapper's own target include path, exactly as `-S` was already dispatched. Row kept for history: this defect is the reason `recipes/common/amix-cpp` exists (`recipes/README.md`) | autoconf silently falls back to `/lib/cpp`, the **host's** preprocessor, and every header test then probes the host (§4.1 trap A) — the historical failure mode, before the fix above |
| 2 | **An archive named on the command line lands BEFORE the objects.** `foo.a` is collected into `objects[]` while parsing; objects compiled from `.c` sources are then *appended*. So `gcc prog.c libfoo.a` links as `libfoo.a prog.o` | single-pass `ld` extracts no members; every symbol in the archive comes back `undefined reference`. Use `-L`/`-l`, which the wrapper places *after* the objects |
| 3 | **Any explicit `-l` suppresses the implicit libc.** The default `libs=(c)` applies only when *no* `-l` was given at all | `-lacompat` alone drops libc entirely, and the first casualties are `crt1.o`'s own `atexit`/`exit`/`_environ`/`__fpstart` — which reads as a broken toolchain rather than a missing flag. **Always end the library list with `-lc`**, including in a configure-filled `LIBS=` |
| 4 | **★ The sysroot include dir is hard-coded at the FRONT of every compile.** `common_cflags=(-I"$sysroot/usr/include")` (`amix-gcc-wrapper.sh:13`) is passed *before* `"$@"` on the real compiler's command line (`:231`), so a package's own `-I` can never shadow a system header | **gnulib header replacement silently does nothing.** gzip 1.3.12 ships `lib/fcntl.h` and `lib/time.h` — gnulib wrappers meant to reach the compiler through the package's `-I./lib` and supply `O_BINARY=0`, `O_NOFOLLOW=0` and `struct timespec`. They are dead here: `<fcntl.h>` and `<time.h>` resolve to the 1992 SVR4 headers, the package sees a pure SVR4 libc, and nothing warns (`recipes/gzip/README.md:29-46`, `recipes/gzip/build.sh:28-39`) |

Numbers 2 and 3 are the ones a Makefile will walk into on its own, since `LIBS=-lfoo` and
`$(OBJS) $(LIBS)` are how every autoconf build links. All four are `gcc-cross-amix` items.

> **★ Number 4 is the one to plan around, because it is not a one-package accident.** Every
> gnulib-carrying package replaces headers exactly the way gzip does, so every one of them loses
> the replacement here. gzip's answer was to fill the four gaps directly in its own `gzip.h`
> (`patches/01-gzip-svr4-compat.patch`) and one more in `lib/utimens.h` (`patches/02`), rather than
> fight the include order. **`coreutils`, `diffutils` and `tar` are predicted to hit the same wall**
> — check what a package expects gnulib to shadow *before* estimating it, and expect the symptom to
> be a missing macro or an incomplete struct rather than a missing file.

### ★ 2.2.2 Imported assembly is banned — how BATCH-1 applied it

§2.2's family law has a blunt packaging corollary: **a package's own hand-written assembly does not
ship.** In SGS syntax `&` is the immediate prefix and `#` *starts a comment*, so what survives the
assembler's comment scrubber is often still a **valid instruction** — `nop #junk here` assembles to
a bare `nop`, exit 0. There is no failing test to notice. The blocker id is `SGS-ASM`, and it is on
five registry entries.

Both BATCH-1 packages that offered an asm fast path had it turned off, and in both the recipe
**asserts the disable landed** rather than trusting the flag:

- **gzip 1.3.12** — the longest-match inner loop has an assembler implementation (`match.S`). The
  recipe seeds `gzip_cv_assembler=no` to force the C path and asserts the generated `config.h`
  carries no `ASMV` (`recipes/gzip/README.md:20-25`, `recipes/gzip/build.sh:23-26`).
- **zlib 1.2.13** — all bundled `contrib/` match/inflate assembler paths stay off. At this version
  the only assembler is x86-64 and the default build never reaches it, which is one more reason
  1.2.13 was the version chosen (`recipes/zlib/README.md:19-24`).

**Recipe rule:** if a package offers an asm path, disable it — then *assert* the disable in the
generated config or the object list. A configure flag that was silently ignored looks exactly like
one that worked, and `gates.sh`'s no-imported-assembly check is the backstop, not the plan.

### 2.3 FP-sensitive code: `-O0` or disassemble

gcc constant-folds floating point at any optimisation level. On 2026-08-27 a metal FP probe built
at `-O` reported *"NO TRAP: c = inf"* from a divide by zero — the disassembly contained two
`fmovel`s and **no `fdiv` at all**. The "no trap" was the compiler's answer, not the silicon's
(`../amix-kerntools/tools/amix-bench/build-fieldkit.sh:71-82`; restated as a family quirk at
`../grimoire-amix/docs/how-it-works/quirks.md:52`).

The established defence is two independent guards: build `-O0`, **and** disassemble the shipped
binary and refuse it if it lacks a floor of FP instructions (`build-fieldkit.sh:140-152`).

### 2.4 ★ `-U__STDC__` — the header gate

**131 headers in the sysroot gate on `__STDC__`** **[measured]**
(`grep -rl __STDC__ $SYSROOT/usr/include/{*.h,sys/*.h} | wc -l`). SVR4 headers show a *different
API* to a K&R compiler than to an ANSI one, and gcc defines `__STDC__` as 1 — so by default you
get the ANSI view, which on this vintage is the **smaller** one.

`$SYSROOT/usr/include/sys/signal.h:71` guards `struct sigaction` itself:

```c
#if (__STDC__ - 0 == 0) || defined(_POSIX_SOURCE)
...
struct sigaction {
```

and `signal.h:25` guards the function declarations the same way. **[measured]**:

| Compilation mode | `struct sigaction sa; sizeof(sa)` |
|---|---|
| default (`__STDC__` = 1) | **`sizeof applied to an incomplete type`** — the struct does not exist |
| `-U__STDC__` | compiles clean |

`SA_SIGINFO` sits behind the stricter `(__STDC__ - 0 == 0) && !defined(_POSIX_SOURCE)`
(`sys/signal.h:87`, `:94`) — *"the flag is visible to the K&R / non-`__STDC__` compilation mode and
hidden under strict-ANSI or POSIX. That is the `__STDC__` header gate: the on-box 1991 `cc` gets it
for free; a cross build must not define `_POSIX_SOURCE` and must not compile as strict ANSI"*
(`../tmp/2026-08-27-cputest-amix-research/B-amix-feasibility.md:286-290`).

**Recipe rule:** if a port needs POSIX-era signal handling, `mmap`, or anything a configure script
reports "missing", try `-U__STDC__` **before** concluding the facility is absent. Conversely never
add `-D_POSIX_SOURCE` or `-ansi` reflexively — on this target they *remove* API.

### ★ 2.4.1 The gate has THREE keys, and they are not interchangeable

**[measured]** 2026-08-28, while building the `patch` recipe — the first port to actually hit this.
The guard is `#if __STDC__ == 0 || defined(_POSIX_SOURCE) || defined(_XOPEN_SOURCE)`, so there are
three ways to open it, and each opens and closes a *different* set of doors. Six one-file probes
compiled `-m68020 -O -Wall` against the sysroot:

| feature | default | `-U__STDC__` | `-D_POSIX_SOURCE` | `-D_XOPEN_SOURCE` |
|---|---|---|---|---|
| `fdopen` `popen` `pclose` `fileno` `system` (`stdio.h:207`) | implicit decl | ok | **ok** | ok |
| `struct sigaction` + `sigset_t` + prototypes | **parse error** | struct only, protos implicit | **ok** | **parse error** |
| `SA_SIGINFO` | hidden | ok | hidden | parse error |
| `struct timeval` | ok | ok | hidden | ok |
| ANSI `va_start` — **gcc's own `stdarg.h`** | ok | **broken: K&R form** | ok | ok |
| `<signal.h>` compiles at all | ok | ok | ok | **parse error** |

Three consequences, none of them previously written down:

- **`-U__STDC__` is not a free switch.** It flips *gcc 2.7's own* `<stdarg.h>` to the K&R
  `va_start(ap)` form, so every ANSI variadic function in the package stops compiling with
  `macro 'va_start' used with too many (2) args`. It also re-hides some function prototypes it
  appears to expose (`tolower`, `_filbuf`/`_flsbuf` become implicit). Per-file flags do not always
  rescue this: patch's `util.c` needs `struct sigaction` **and** five variadic functions in the
  *same* translation unit.
- **`-D_XOPEN_SOURCE` is never the answer here** — it makes `<signal.h>` itself fail to parse.
- **`-D_POSIX_SOURCE` is sometimes exactly right**, despite the blanket warning above. It is the
  only key that opens both the stdio and the sigaction doors while leaving ANSI varargs intact. It
  costs `SA_SIGINFO` and `struct timeval`, so it is correct only for a package that uses neither —
  which `patch` does not. **The warning stands as a default; it is not a law.** Measure the package
  against this table rather than reaching for a flag.

The honest rule that replaces "use `-U__STDC__`": *identify which hidden declarations the package
actually needs, then pick the key whose closed doors it does not walk through.* All four columns
are one `grep` and one compile away.

> **Not in grimoire.** The `__STDC__` gate is unpublished — the grimoire sweep found zero hits for
> `__STDC__`, `sigaction` or `SA_SIGINFO` corpus-wide. The evidence above is this repo's
> measurement plus the cputest round. A `/amix-brief` opportunity, and §2.4.1's three-key matrix
> is the part most worth publishing.

### 2.5 Building shared libraries

If a port ships a library (see §3.4 on ncurses), the SVR4 link rules bite:

- **Both `-G` and the `-h` SONAME are required**: `ld -G -h libXt.so.6.0 -o libXt.so.6.0 <objects>`
  (`../grimoire-amix/docs/drivers/case-studies/x11r63-zz9000.md:139`).
- **Link order is left-to-right and strict** — each `.sa` immediately after its `-l`, providers
  after (`x11r63-zz9000.md:148`).
- **Stub archives** (`libXt.sa`) are ordinary `ar` archives containing exactly `sharedlib.o`
  (`x11r63-zz9000.md:145-146`).

---

## 3. The OS-surface gap

### 3.1 What libc actually exports

**[measured]** against `$SYSROOT/usr/lib/libc.so.1` (`m68k-cbm-sysv4-nm`, whole-name matches):

| Present in shared libc | **Absent** from shared libc |
|---|---|
| `sprintf` `strdup` `memmove` `strerror` `atof` `strtod` `sysconf` `mmap` `poll` `sigaction` `sigemptyset` `putenv` `waitpid` `times` `popen` `opendir` | **`snprintf`** **`vsnprintf`** `getpagesize` `gettimeofday` `strcasecmp` `realpath` `vfork` `getrusage` `nlist` |

**`snprintf` does not exist** — not in `libc.so.1`, and not even *declared* in
`$SYSROOT/usr/include/stdio.h` **[measured]**. This is the single most common porting blocker,
because modern C uses it everywhere and gcc 2.7.2.3 will happily compile a call to an **implicitly
declared** function.

> **★ The implicit-declaration trap.** In K&R C an undeclared function is assumed to return `int`.
> A real probe in this family passed a `double` through an undeclared `atof` and silently got the
> wrong value: *"`fptrans` did not honour `argv[2]` — `atof` was not declared, so the input was 3.0
> rather than the 0.5 passed … an undeclared-`atof` bug is exactly the kind of thing that silently
> invalidates a probe"* (`../tmp/2026-08-27-fpe-workload/RESULTS.md:454-458`).
> Build with `-Wall` and treat every implicit-declaration warning as an error.

Some symbols exist only in a **static** archive — a trap when a build probes the shared library.
**[measured]**: `gettimeofday` is in `libc.a` but not `libc.so.1`; `strcasecmp` in
`libsocket.a`/`libresolv.a`; `nlist` in `libelf.a`. **`environ` belongs to this family too** and is
the one that bites first: `libc.so.1` exports **only `_environ`** (`B`), while `libc.a` carries
`_environ` (`D`) *and* a weak `environ` (`W`), and **no header declares either**. So the universal
`extern char **environ;` compiles, links against the static libc, and fails at link time against
the shared one — which is what an Amix program actually links (`libamixcompat` build, 2026-08-28).

The fix that works is the platform's own idiom rather than an invention: `#define environ _environ`
— exactly what `<rpc/types.h>:82` already does for `gettimeofday`. A macro rewrites the consumer's
own declaration *and* its uses. Defining a separate `environ` **variable** in a shim would link
just as cleanly and be silently wrong, because `putenv` updates `_environ` and the copy goes stale
on the first change. `libamixcompat`'s header carries the macro.

Maths is static-only: *"Amix's SHARED libc has
none of them: they live in the static `/usr/ccs/lib/libm.a` … So the link order is `whetstone.o,
libm.a, libc.so.1, libc.a`"* (`../amix-kerntools/tools/amix-bench/build-fieldkit.sh:109-116`).
Sockets need `-lsocket -lnsl` (`../amix-packagemanager/docs/design.md:4-5`).

**★ Some functions exist only as `static` wrappers IN THE HEADERS — a link probe calls them
absent.** **[measured 2026-09-26]** `<sys/stat.h>` defines `stat`, `lstat`, `fstat` and `mknod` as
`static` functions around `_xstat`/`_lxstat`/`_fxstat`/`_xmknod`; `libc.so.1` exports only the
underscored names. autoconf's `AC_CHECK_FUNCS(lstat)` links against a prototype-less `char
lstat();` and fails, so tar's `config.h` said no `lstat` and tar did `#define lstat stat` —
archiving what every symlink points at, silently. Seed `ac_cv_func_lstat=yes` and assert it
(`recipes/tar/build.sh`). The opposite lie is common too: `valloc` and `_sys_siglist` are
*declared* by the headers but not exported by `libc.so.1`, so a declaration probe says yes and the
link fails (`recipes/tar`, `recipes/make`).

**★ `getpwnam()` crashes on first call in the stock shared libc.** Explicitly framed as a porting
hazard: the first `getpwnam()` of a process crashes inside libc's passwd-record handling, while
`getgrnam` survives. Interposition was ruled out (libc calls internal helpers via non-preemptible
`bsrl`). The working sidestep is to **link statically** and let the executable *define*
`getpwnam`/`getpwuid`/`getgrnam`/`getgrgid` as small `/etc/passwd` parsers — an executable's own
globals win at static link time (`../grimoire-amix/docs/drivers/toolchain.md:262`;
`llms-full.txt:7583`). **Any tool that maps uid→name — `ls -l`, `ps`, a top-class monitor — hits
this.**

**D3 is proven** (`recipes/tar`, 2026-09-26): `recipes/common/amix-pwgr.c` defines the four
lookups, linked as a plain object into a still-**dynamic** executable; the build asserts via `nm`
that they are `T`, never `U`.

Also absent from the box: **`md5` and `cksum`** (`../grimoire-amix/docs/drivers/z3660-scsi-driver.md:336-337`).

> **Not in grimoire.** There is no published inventory of Amix libc exports. The table above is
> this repo's measurement.

### 3.2 `/proc` is ioctl-based, not text files

The big architectural one. On SVR4, `/proc/<pid>` is a **single file you `open()` and drive with
`ioctl()`** — there is no `/proc/<pid>/stat`, no `/proc/meminfo`, nothing to parse.
`$SYSROOT/usr/include/sys/procfs.h` says so at `:23` (*"ioctl codes and system call interfaces for
/proc"*), then defines 37 `PIOC*` codes **[measured]**:

```c
#define PIOC        ('q'<<8)
#define PIOCSTATUS  (PIOC|1)   /* get process status */
#define PIOCPSINFO  (PIOC|30)  /* get ps(1) information */
#define PIOCNMAP    (PIOC|31)  /* get number of memory mappings */
#define PIOCMAP     (PIOC|32)  /* get memory map information */
#define PIOCCRED    (PIOC|34)  /* get process credentials */
```
(`sys/procfs.h:26-63`; `prstatus_t` at `:71`, `prpsinfo_t` at `:121` with `pr_fname[16]`, `pr_psargs`)

**Consequence: `htop` as written is unportable.** Its whole data layer reads Linux `/proc` text
files. A top-class monitor for Amix is a **rewrite** against `PIOCPSINFO`, not a port — and it also
inherits the `getpwnam` hazard (§3.1) and the kernel-stats trap (§3.3). Budget it that way, and
prefer writing a small native tool over patching a large foreign one.

> **Not in grimoire.** No published statement that SVR4 `/proc` is ioctl-driven. Beware: the
> `PIOC*` hits in the corpus are a **parallel-port driver's private ioctls**
> (`llms-full.txt:6506-6508`), unrelated to procfs.

### 3.3 ★ Kernel statistics: the `nlist`/COMMON trap

Anything reporting load average, free memory or uptime reads kernel symbols. On Amix that path is
booby-trapped three ways.

**Trap 1 — `nlist(3)` returns an alignment, not an address, and reports success.**

> *"`avenrun` … is a C tentative definition — an ELF `SHN_COMMON` symbol — and `/stand/unix` is an
> `ET_REL` relocatable object, so the symbol **has no address in the file**: `nlist(3)` returns
> *success* with the symbol's **alignment** (4) as its value, and the reader prints whatever
> pointer-shaped memory lives at address 4 on that boot."*
> (`../grimoire-amix/docs/how-it-works/load-averages.md:21-24`)

The boot loader's `elf2brel` conversion allocates COMMON at boot and **discards the symbol
tables**, so the placement exists only in the loaded image
(`../grimoire-amix/docs/drivers/kernel-reverse-engineering.md:163-165`).

**Ten-second test:** *"`nm` shows `COMMON` in the section column; `nlist` returns `n_scnum = -14`;
the value is an implausibly small, suspiciously round number. If a 'kernel address' comes back as a
single-digit number, it is an alignment — nothing lives at 4."*
(`kernel-reverse-engineering.md:167-169`)

This is why the box's `uptime` is broken. *"A flat `0.00` is not an idle machine; it is the same
defect wearing a more convincing disguise"* (`load-averages.md:9-12`). Measured against the true
`avenrun`, the kernel's load rose **0.07 → 0.11 and decayed to 0.02** while `uptime` printed one
frozen `0.00, 0.00, 0.00` (`../tmp/2026-08-27-metal-opportunistic/RESULTS.md:203-210`).

**Trap 2 — `/stand/unix` LIES when the running kernel came off a raw slice.** The documented
`adb -k /stand/unix /dev/mem` workaround (`load-averages.md:47`) carries two conditions: the
namelist must be *the kernel actually running*, and when the running kernel exists in **no file**,
`adb -k` fails *silently* with plausible zeros (`load-averages.md:50-53`). Confirmed on metal:
*"returning plausible zeros rather than an error — the same trap class as the defect it is meant to
diagnose"* (`RESULTS.md:238-253`). The method that works is replaying the loader's COMMON
allocation host-side (`RESULTS.md:255-266`).

**Trap 3 — even a correct read is off by one.** The kernel's runnable count *"omits the state
meaning 'currently executing on a processor'"* — on a uniprocessor, exactly one process whenever
the machine is busy. Measured: 1 spinner → **0.00**, 2 → **1.00**, 3 → **1.99**
(`load-averages.md:33-37`). The averaging math itself is textbook (`load-averages.md:40-42`).

**Recipe rule:** a tool reading kernel state must not trust `nlist()`. Classify the symbol first
(`nm` — COMMON or defined); COMMON → read the running image; defined → `nm` value **+ load base**
(`0x08000000` on the A4000 + Z3660) (`kernel-reverse-engineering.md:195-198`;
`llms-full.txt:6232`). Treat this as a **design constraint on what the tool can honestly report**,
not a bug to patch late. `crash(1M)` is not an alternative — it fails `process slot out of bounds`
(`load-averages.md:56`).

### 3.4 Curses: SVR4 curses/terminfo, and there is no ncurses

**[measured]** in the sysroot: `curses.h` and `term.h` are present; `initscr`/`setupterm`/`tputs`
resolve from **`/usr/ccs/lib/libcurses.a`** (also `libform.a`, `libmenu.a`, `libpanel.a`);
`libtermcap.a` and `libtermlib.a` exist; `term.h` is terminfo-based. **No file matching
`*ncurses*` exists anywhere in the sysroot.** `libcurses` is a **static archive only** — there is
no `libcurses.so`.

Two routes for screen-oriented tools:

1. Link against **SVR4 curses** — free, but many modern programs use ncurses-only APIs (wide-char
   `cchar_t`, `NCURSES_VERSION` feature tests, mouse support, `use_default_colors`).
2. **Port ncurses first** and make it a dependency package (see §2.5 for the shared-library rules).

A **dependency-ordering** decision for the campaign plan, not an individual recipe. Which route a
given tool needs is **UNVERIFIED** until someone tries.

**★ Route 1 is now proven for a termcap-style client — `less` 704, 2026-08-30.** less builds
`-DUSE_TERMCAP` and links **`-lcurses` alone**; on SVR4 the termcap `tgetent` reads the *terminfo*
database, so nothing else is needed (D2). Two measured details a screen-oriented recipe will meet:

- The reason to leave the default *terminfo* path is a **header collision**, not a missing library.
  `<term.h>`'s `TERMINAL` struct has a `struct termio` field that stays **incomplete**, because less
  includes `<termios.h>` for `tcgetattr`, which defines `VINTR`, which makes `<curses.h>` skip its
  own `<termio.h>` include. The termcap path never includes `<term.h>` at all.
- `libcurses.a` lives in **`/usr/ccs/lib`**, not the wrapper's default `/usr/lib`, so the link needs
  `-L<sysroot>/usr/ccs/lib` — and, per §2.2.1 number 3, an explicit `-lc` after it.

(`recipes/less/README.md:24-35`, `recipes/less/build.sh:21-32`.) Still **UNVERIFIED**: real screen
handling — less paints with termcap escapes and never calls `initscr`/`newwin` — and ncurses itself,
which nothing here has built.

One console constraint that bites TUIs and automation alike: **the console tty truncates canonical
input at ~256 characters**, silently (`llms-full.txt:2785`).

> **Not in grimoire.** Zero hits for `curses`, `ncurses`, `terminfo`, `termcap`. The sysroot
> measurement above is the only evidence.

### 3.5 Float parsing drifts at large exponents

`printf` is correct; **`atof`/`strtod` is not.** Measured on the box against correctly-rounded host
values (`../tmp/2026-08-27-fpe-workload/RESULTS.md:216-238`):

```
1e0 … 1e50    ALL EXACT
1e60  +1 ulp     1e150 +2 ulp     1e250 +4 ulp     1e300 +4 ulp
DBL_MAX  1.7976931348623157e+308  ->  atof gives ~1.7976931e+38   (catastrophically wrong)
min subnormal                     ->  flushed to zero
parser is not idempotent: 1e300 -> +4 ulp -> reprint -> +3 more ulp
```

Diagnosed as an **algorithm** limit (building `10^k` by repeated multiplication instead of
correctly-rounded scaling), not an arithmetic fault (`RESULTS.md:240-242`).

**Status: UNRESOLVED attribution.** *"The `atof` drift may well be stock Amix libc and predates the
lane entirely"* — the discriminator is running the same probe under a real-FPU rig with the same
`libc.so.1`, which has not been done (`RESULTS.md:253-257`, `:441`). Not published in grimoire.

**Recipe rule:** any tool parsing floating-point text — a calculator, a spreadsheet, a config
parser, a JSON reader — is **exact below 1e50 and unreliable above it**. Say so in the package
description. If exactness matters at extreme exponents, ship your own parser.

### 3.6 ★ Shell: the 1992 pre-POSIX Bourne sh

Any script in a package — a wrapper, an install script, a driver — runs under `/bin/sh`, which
**predates POSIX** (`llms-full.txt:2772`). The interactive default is `ksh`, but *"build and install
scripts that run under `/sbin/sh` or `/bin/sh` must stay pre-POSIX"* (`llms-full.txt:2777`). If a
tool insists on a POSIX shell, run it under `ksh` explicitly (`llms-full.txt:7416`).

**Syntax:**

| Rule | Source |
|---|---|
| **No `$(...)`** — use backticks | `llms-full.txt:2773-2775` |
| **`expr`, not `$(( ))`**; **no `local`**; **no arrays**; **no `printf(1)`** | `../amix-kerntools/docs/amix-allsoak.md:73-75` |
| **No `grep -q`** — redirect to `/dev/null`, test `$?` | `llms-full.txt:2775` |

**Semantics — the subtle ones that produce wrong results, not errors:**

| Trap | Source |
|---|---|
| **`while read … done < FILE` runs in a SUBSHELL** — a counter incremented in the loop reverts at `done`. Write per-iteration state to a temp file. | `llms-full.txt:2781` |
| **Empty `` set -- `cmd` `` is a no-op** — if the command prints nothing, `$#` keeps its *previous* value instead of going to 0. Guard with `[ -s file ]`. | `llms-full.txt:2782` |
| **`mkdir -p` is not idempotent** — rc=2 "File exists" on an existing leaf. Guard with `[ -d dir ] \|\| mkdir -p dir`. | `llms-full.txt:2783` |
| **`wc -c` left-pads**, so a raw `wc -c` in a numeric test fails. | `llms-full.txt:2784` |
| **A command string ending in a bare `&`** arrives over the telnet transport as `&;` — a syntax error that costs three logins and silently never starts the job. | `../amix-kerntools/CHANGELOG.md` (2026-08-27 transport-guard entry) |

**The toolbox is thin.** An install miniroot ships **no `basename`, `sed`, `touch`, `date` or
`wc`**. Portable substitutes: `expr` for path/field work, `: > file` for `touch`,
`set …/*; echo $#` to count matches (`llms-full.txt:2787`).

**UNVERIFIED:** SVR4 package **install scripts** (preinstall/postinstall/request/class-action) have
never actually been run on Amix — the packagemanager repo still tags that path **BENCH** (unrun),
and no package the family ships contains one
(`../amix-packagemanager/docs/heirloom-pkgtools-dive.md:140`, `:157-158`). A recipe needing an
install script is doing something nobody here has proved works. **Prefer packages that are pure
file payloads.**

### 3.7 Environment traps that break unrelated programs

- **A colon-less `TZ` kills every `tzset()` caller.** `TZ=US/Eastern` without a leading colon makes
  every SVR4 program calling `localtime()`/`tzset()` die with `User BUS ERROR` — the crash set is
  exactly the localtime callers: `date`, `who -r`, `cron`, `ls -l` (`llms-full.txt:2791`).
- **Three diagnostic tools lie on a healthy box**: `netstat -a` prints `corrupt control block
  chain`; `sar -v` fails `sadc: Not enough space`; `ipcs -a` fails `read error`. Don't chase any of
  them (`llms-full.txt:2402`).

### ★ 3.8 Pattern matching: no POSIX `regcomp` — `regcmp`/libgen is the substitute

**[MEASURED]** there is **no POSIX `regcomp`/`regexec` on this box at all** (`ROADMAP.md` D8;
blocker id `REGEX-NONE`, on four registry entries). What exists is two older interfaces:

| Interface | Where | Shape |
|---|---|---|
| SVR4 `regexp.h` | `<regexp.h>`, macro-based | `compile`/`step`/`advance` — the V7 lineage |
| `regcmp`/`regex` | **`libgen.a` under `/usr/ccs/lib`**, declared in `<libgen.h>` | compile a pattern to a buffer, then match against it |

Two routes, and BATCH-1 proved both:

1. **Bundle a regex** — the safe default, and the reason `grep` **2.5.1a** is the chosen version:
   it carries its own `regex.c`. The trap `REGEX-NONE` names is that a *compile-test* for a system
   regex succeeds under gcc 2.7's implicit declarations even when the symbol is absent (§3.1), so a
   configure run can cheerfully "find" a regex that does not exist. `recipes/grep` passes
   `--with-included-regex` and then **asserts** via `config.status` that `regex.o` really entered
   `LIBOBJS` (`recipes/grep/README.md:25-33`).
2. **Use `regcmp`, where the program already has a backend for it** — `less` 704 does. Its configure
   selects the regcmp backend (`HAVE_REGCMP=1`, which less reports as *"V8 regular expressions"* in
   `--version`), and the recipe gates on the configure log saying so rather than on an exit status
   (`recipes/less/build.sh:122-129`). Two costs, both measured: `libgen.a` is in `/usr/ccs/lib` so
   the link needs `-L<sysroot>/usr/ccs/lib` (and a trailing `-lc`, §2.2.1); and SVR4's `regcmp` is
   **variadic**, while less shipped a stale fixed-arg prototype for it — the reason
   `regcmp(pattern, 0)` failed with *"too many arguments"* and the reason
   `recipes/less/patches/02-pattern-libgen.patch` exists (`recipes/less/README.md:44-46`).

**Recipe rule:** prefer a bundled regex, and assert it was actually compiled in. Reach for `regcmp`
only when the program already supports it, and take the prototypes from `<libgen.h>` rather than
from whatever the package guessed a decade ago.

---

## 4. Version selection — the latest release is usually the wrong one

The load-bearing strategic insight, and a direct consequence of §2 and §3.

**Prefer the oldest version carrying the features you actually want.** Mid-1990s releases were
contemporaneous with SVR4: they are written in C89 or K&R, they carry `#ifdef SVR4` / `#ifdef sun`
/ `#ifdef __svr4__` branches *that were tested against systems like this one*, they assume
`libcurses` rather than ncurses, and they do not call `snprintf`. A 2020s release of the same tool
has had every one of those accommodations deleted as dead weight.

Where an era-appropriate **SVR4 port already exists** (a `sysv4` branch, an old `Makefile.svr4`, a
package from a 1990s Solaris/SVR4 archive), that is worth more than any amount of patching.

**★ A worked case — zlib, and a feature that disappears without a macro.** zlib **≥ 1.3.2 silently
stubs `gzprintf()`** unless the build defines `-DZLIB_INSECURE`: the call still links, still
returns, and writes nothing. That is why this repo ships **1.2.13** — a compression library that
quietly produces no output is precisely the failure class this campaign exists to avoid — and the
older release is also integer-only and carries no gnulib (`recipes/zlib/README.md:19-24`).

Choosing the old version is only half of it; its **build system** has to be watched too. zlib's
hand-written `./configure` probes `vs[n]printf` by linking with `$CC $CFLAGS` alone, never threading
`LDFLAGS`/`LIBS`, so it cannot see `libamixcompat`, concludes the function is absent, and bakes
`-DNO_vsnprintf -DNO_snprintf` into the Makefile — which switches `gzprintf()` to the **unbounded**
`vsprintf`/`sprintf` path. The recipe therefore runs configure only for what it does right (generate
`zconf.h`, report the platform), compiles the fixed object list itself with no `NO_*` macro, and
**asserts via `nm`** that `libz.a` really references `vsnprintf`/`snprintf` — checking the artifact,
not the configure log (`recipes/zlib/README.md:26-47`). Two lessons generalise: a `NO_*`/`HAVE_*`
macro can silently *remove* a feature rather than fail, and a probe that does not thread the
recipe's own `LDFLAGS` cannot see the shim every package here links.

The corollary is *not* that autotools are unusable — check before assuming:

- **The triplet is recognised.** **[measured]** both a modern `config.sub` (automake 1.18) and the
  1990s `config.sub` shipped inside `gcc-2.7.2.3` canonicalize `m68k-cbm-sysv4` to itself; a
  garbage triplet is rejected (`Invalid configuration 'zzz-nope-nope'`). A
  `--host=m68k-cbm-sysv4` cross-configure is **not** blocked at the triplet.
- **What *is* blocked:** `configure` cannot run **on the box** (§3.6 shell limits), and its
  run-tests cannot execute anyway — wrong architecture. So configure runs **host-side as a
  cross-configure**, and every `AC_TRY_RUN`-class test must be answered with a **cache variable**
  (`ac_cv_*=...`) supplied by the recipe. Those cached answers are part of the recipe and must be
  justified in a comment: a wrong one is a silent miscompile.
- **Autoconf assumptions about libc will lie** in the other direction too: a feature test that
  *compiles* a call to `snprintf` succeeds under gcc 2.7's implicit declarations while the symbol
  does not exist (§3.1). **Prefer link-tests over compile-tests**, and check the resulting
  `config.h` against the measured symbol list rather than trusting it.

### ★ 4.1 What a real cross-`configure` actually did — GNU patch 2.5.9, 2026-08-28

This section used to end "**UNVERIFIED:** no port in this repo has yet been driven through a real
cross-`configure`." One has now (`recipes/patch`). The good news first: **the route is far less
hostile than the constraints suggested.** patch's autoconf-2.57 `configure` has seven `AC_TRY_RUN`
sites and *every one already carries a cross-compilation fallback*; exactly one of those defaults
was wrong. The tarball ships no `config.sub` at all, so the triplet never came up.

Three things bit, and none of them was the thing this section predicted.

**★ Trap A — `$CC -E` silently becomes the BUILD HOST's preprocessor.** `m68k-cbm-sysv4-gcc` has
no `-E` case: the wrapper's catch-all treats an unrecognised dash-argument as an `ld` flag, so
`-E` makes it **link** the file, exit 0, and print nothing on stdout. Autoconf's *"checking how to
run the C preprocessor"* rejects that and walks down its candidate list to **`/lib/cpp`**. From
then on every `AC_CHECK_HEADER` *presence* test reads the host's `/usr/include`, and autoconf 2.5x
resolves a presence/usability disagreement by **trusting the preprocessor**:

```
checking wchar.h usability... no
checking wchar.h presence... yes
configure: WARNING: wchar.h: present but cannot be compiled
configure: WARNING: wchar.h: proceeding with the preprocessor's result
checking for wchar.h... yes
```

`config.h` then declared `HAVE_WCHAR_H 1` for a header Amix does not have. This one failed loudly
(`quotearg.c: wchar.h: No such file or directory`) — but the same mechanism sets `HAVE_*` for
anything that merely *looks* present on a modern Linux host, and most of those fail quietly. **Any
cross-`configure` here must pass an explicit `CPP`** (`recipes/common/amix-cpp`), and should assert
a few known-absent `HAVE_*` afterwards so a regression stops the build. Fixing `-E` in the wrapper
was a `gcc-cross-amix` item.

**★ FIXED 2026-08-29** (`gcc-cross-amix` 3c2d272): `-E` is now dispatched to the real cross
compiler with the wrapper's own target include path, so `$CC -E` preprocesses correctly and
autoconf no longer falls back to the host's `/lib/cpp`. This trap is now historical — it is kept
here, in full, because it is the reason `recipes/common/amix-cpp` exists (`recipes/README.md`).
`amix-cpp` is not deleted or made a no-op by the fix: it calls `gcc.real -E` directly with the
sysroot include path added by hand (`recipes/common/amix-cpp`), which is exactly what the wrapper
now does internally — so it still works, unchanged, and existing recipes keep passing it as `CPP`.
There is no reason to touch a build that already works. A *new* recipe may pass `$CC` directly as
`CPP` instead, now that the wrapper handles `-E` itself.

**★ Trap B — the `__STDC__` gate, which no cached variable can answer.** See §2.4.1: the package
needed `fdopen`/`popen`/`pclose`/`fileno` *and* `struct sigaction`, and the flag §2.4 recommends
(`-U__STDC__`) broke gcc's own `stdarg.h`. This is a *compile-flag* decision, not a configure
answer, and it has to be made before configure runs so that `config.h` and the build agree.

**★ Trap C — `AC_PATH_PROG` probes the build host.** `checking for ed` found the Linux box's
`/usr/bin/ed` and compiled that path into the binary. It happened to be right. Pass such paths
explicitly (`ed_PROGRAM=/usr/bin/ed`) rather than letting them be right by coincidence.

**On cached answers, the discipline that emerged:** seed the ones that are *wrong*, and record the
ones you deliberately did **not** seed, with the reason. For patch that was one seed
(`ac_cv_func_closedir_void=no` — `dirent.h:39` declares `int closedir(DIR *)`), two refusals
(`ac_cv_func_malloc_0_nonnull` and its realloc twin: the cross default `no` installs a `rpl_malloc`
wrapper that is correct whichever way SVR4.0 behaves, so the conservative default is also the right
answer), and one non-issue worth writing down because it looks like a seed is needed
(`ac_cv_header_stdc` — its cross branch is a no-op `:`, so the compile-test result survives).

---

## 5. Why there is no automated fetch-and-build pipeline

Everything above is the argument. A naive "fetch the tarball, `./configure && make`, wrap the
result" pipeline cannot work here because:

1. **The compiler is a shell script.** Correctness depends on `fix_asm` post-processing every `.s`
   file; any path that reaches `gcc.real`, splits `-S` from assembly, or calls `as` itself silently
   loses six miscompile repairs — one of which reverses floating-point comparisons with no
   diagnostic (§2.2).
2. **The language level rejects modern source outright** (§2.1), and **C++ is unavailable**.
3. **The libc is missing functions every modern program calls**, and the compiler will not tell you
   — it compiles an implicit declaration and hands you the wrong value (§3.1).
4. **The header API depends on a preprocessor flag.** Whether `sigaction` exists depends on
   `-U__STDC__`; a feature test gets the *wrong* answer by default (§2.4).
5. **Whole categories of tool need a rewrite, not a port** — anything reading `/proc` or kernel
   statistics (§3.2, §3.3).
6. **Even a correct binary can die on a formatting call** — FP in `_doprnt` on an FPU-less part
   (§1).
7. **Packaging is not generic.** A `.pkg` needs an authored `pkginfo` (`ARCH=Amiga`, **PKG name
   ≤ 9 characters** or stock `pkgadd` *silently drops the package*) and an authored `prototype`
   that cannot represent a path containing a space, `=` or `$`
   (`../amix-packagemanager/NOTES.md`;
   `../amix-packagemanager/docs/s5-14char-collisions.md:274-278`). And **`pkgproto` silently omits
   symlinks** from generated prototypes (`llms-full.txt:7611`).
8. **The target filesystem truncates filenames to 14 bytes**, so two files in one directory sharing
   a 14-byte prefix cannot coexist — only a human can resolve that
   (`../amix-packagemanager/NOTES.md:92-95`; `docs/s5-14char-collisions.md:219-220`).

**Therefore: every port is a hand-crafted recipe.** Per this repo's conventions (`CONTRIBUTING.md`): a
per-tool subdirectory holding source provenance, patches, a build script, and
`pkginfo`/`prototype` — with **fetch-at-build against a pinned checksum**, never a vendored source
tree in git.

### What *can* be automated

The recipe is hand-written; everything consuming it should be mechanical.

- **Checksum-verified fetch** — pinned sha256, verified *before* extraction (the 040-060 lane's
  `tools/netbsd-pin.sh` is the pattern to imitate).
- **The per-recipe build harness** — one entry point setting `CC=m68k-cbm-sysv4-gcc`, the standard
  flags and the sysroot, so no recipe re-derives them and none can accidentally bypass the wrapper.
- **Build-time correctness gates** — the family's strongest idea: *disassemble the shipped binary
  and refuse it* if it violates a known-defect invariant. Precedents: `build-fieldkit.sh`'s `fcmp`
  count and FP-instruction floor (`build-fieldkit.sh:281-322`), and `gcc-cross-amix`'s five
  `make test-*` gates, each checking **object code**, not that the file compiled.
- **`.pkg` rolling** — host-side Heirloom `pkgmk` + `pkgtrans`, both proven to run on Linux
  (`../amix-packagemanager/docs/design.md:178`), plus the structural checks that already exist: the
  PKG-name length gate and the `070701`-at-offset-512 magic check
  (`../amix-packagemanager/tools/repo/build-packages.sh`).
- **Bench smoke** — push over FTP, `pkgadd`, run, `pkgrm`.

> Automate the **recipe**. Never automate the **porting**.

---

## 6. Porting checklist — the per-tool triage

Walk this before committing to a tool. A "yes" in the middle column is a cost, not a blocker;
several together mean *pick a different version* or *write a native tool instead*.

| # | Question | Why it matters |
|---|---|---|
| 1 | **Language level?** C99? **C++?** | C99 declarations/loop-vars are parse errors; **C++ is unavailable** (§2.1). |
| 2 | **Floating point?** Any FP comparison; any FP whose execution is load-bearing? | `fcmp` reversal (§2.2), constant-folding (§2.3). Gate the build by disassembly. |
| 3 | **Does it print a float?** | On an FPU-less part that alone is fatal — SIGSYS inside `_doprnt` (§1). |
| 4 | **`snprintf` and friends?** `grep` the source against §3.1's absent list. | Each absent symbol is a shim you write and carry as a patch. Check for implicit declarations. |
| 5 | **Does it resolve usernames?** `getpwnam`/`getpwuid` | First call crashes in the stock shared libc; static-link sidestep required (§3.1). |
| 6 | **Curses / screen?** | SVR4 curses only, static-only, no ncurses (§3.4). May require porting ncurses **first**. |
| 7 | **`/proc` or kernel statistics?** | Rewrite against `PIOC*` ioctls; `nlist()` is untrustworthy and the count is off by one (§3.2, §3.3). |
| 8 | **Float parsing?** `atof`/`strtod` on user input? | Exact below 1e50, drifting above, DBL_MAX catastrophically wrong (§3.5). Document the limit. |
| 9 | **Shell scripts in the package?** | Pre-POSIX sh (§3.6). Install scripts are an **unproven** path — prefer pure file payloads. |
| 10 | **Size on target?** | **~44 MB free root** (§1) is the binding disk constraint; RAM is generous on the guests this family actually runs — **64 MB on the stock 030 bench golden, 128 MB on 040/060 metal** (§1; the old 16 MB RAM ceiling is retracted) — so budget disk, not RAM, unless targeting a minimally-configured low-RAM stock box (courtesy figure **8 MB**). Budget **~1.10×** the payload byte sum for s5 on-disk footprint (`../amix-packagemanager/NOTES.md:240-241`). |
| 11 | **Filenames?** Two files in one directory sharing a 14-byte prefix? Any path with a space, `=` or `$`? Any symlinks? | s5 truncation, `prototype` grammar, and `pkgproto`'s silent symlink omission (§5.7, §5.8). |
| 12 | **License text included?** | GPL/BSD upstream is fine to build and distribute; **each package carries its own license text** (`CONTRIBUTING.md`). Nothing SVR4-derived is ever committed here. |
| 13 | **Dependency packages?** | Dependencies are **catalog-level**, not `depend(4)` files — authored host-side in `deps.conf`, resolved recursively by `apkg` (`../amix-packagemanager/NOTES.md:372-374`). Order the campaign provider-before-consumer. |
| 14 | **PKG name ≤ 9 chars? `ARCH=Amiga`?** | Longer names are **silently dropped** by stock `pkgadd`; `ARCH=m68k` is wrong (`../amix-packagemanager/docs/kernel-packages.md:147-149`). |

---

## 7. Testing route

**Bench first, then metal.** The golden 68030 box under Amiberry is the cheap, reproducible
environment; the A4000 + Z3660 metal box is the verdict. Never debug a new port on metal.

### Transfer laws

- **FTP is the bridge, not NFS.** *"Amix 2.1 (SVR4.0) is an NFSv2-only NFS client and the host's
  kernel nfsd can't serve NFSv2, so we move files over the box's ftpd instead"*
  (`../grimoire-amix/tools/host-net/amixsync.py:4-6`).
- **FTP is asymmetric.** PUT is reliable; **GET is unreliable above ~1 KB**
  (`llms-full.txt:9368`; `../grimoire-amix/docs/drivers/z3660-scsi-driver.md:337`). Sustained
  throughput ~185 KiB/s (`llms-full.txt:9435`).
- **The 1991 ftpd has no `SIZE`** (predates RFC 3659), which once made a truncation gate *silently
  vacuous* — FTP pulls that dropped bytes were accepted as complete
  (`../grimoire-amix/tools/host-net/amixsync.py:83-86`). Verify transfers by content, not by size
  reported over FTP — and remember the box has no `md5`/`cksum` (§3.1).
- **`/tmp` is wiped on reboot** — stage nothing there that must survive one.
- Packages reach the box over **FTP** for the bootstrap, then over **plain HTTP/1.0 GET** via
  `apkg` from `http://pkg.amigaux.org/` (catalog at `/catalog`, packages
  under `/pkgs/<set>/…` — grouped by **provenance** (`stock`/`base`/`test`/`extra`), not by
  `cats.conf` category; this repo's own packages land under `/pkgs/extra/…`, matching the `extra`
  set in `sets.conf`) — the on-box client has no TLS, so this stays plain HTTP with an
  explicit `Host` header, never HTTPS (`../amix-packagemanager/docs/design.md:103-105`,
  `requirements.md:23-26`; repo history: `CHANGELOG.md`; publish record:
  `../amix-packagemanager/NOTES.md` 2026-09-15).

### ★ The throttle law — this shapes every test harness

SVR4 `inetd` has an anti-looping throttle, characterised by reading the constants out of the
shipped binary (`llms-full.txt:1507-1509`):

| Constant | Value | Meaning |
|---|---|---|
| `TOOMANY` | **40** invocations | trip threshold, counted **per service** |
| `CNT_INTVL` | **60 s** | the counting window |
| `RETRYTIME` | **600 s** | the `alarm()` that re-enables the service |

Diagnosis: *"If telnet answers `Connection refused` while FTP still answers, ICMP is alive, and the
console shows an undisturbed `login:`, the box is fine — SVR4 `inetd` has disabled that one service
because something opened 40 connections to it inside 60 seconds"* (`llms-full.txt:1491-1493`).

The operational rules:

- **It applies to `ftp` as well as `telnet`** — both are `nowait`
  (`../amix-kerntools/tools/amixsync.py:148-162`). But the counters are **independent per service**:
  tripping ftp leaves telnet open, and vice versa (`llms-full.txt:1556-1557`) — so you can still
  pull evidence off the box over FTP while telnet is locked out (`llms-full.txt:1560`).
- **There is no config knob.** The `inetd.conf` wait field is parsed as a boolean, so the 4.4BSD
  `nowait.<max>` syntax is **silently ignored** (tested: `nowait.100` + SIGHUP was accepted and
  still tripped) (`llms-full.txt:2523-2524`, `:1545`).
- **inetd counts LOGINS, not commands** (`../amix-kerntools/tools/amixrun.py:213`). Hold one
  session open for a batch (`llms-full.txt:2528-2529`).
- **Push a directory in one run** — a per-file push loop self-destructs at 40 files
  (`../tmp/2026-08-27-cputest-amix-research/B-amix-feasibility.md:355-357`).
- **A retry is a fresh login** — a harness that quietly retries burns the budget three times as
  fast, which is exactly how a past bench run exhausted it.
- **Design against 40**: *"40 is the floor and the only safe number to design against — never
  calibrate a guard against an observed refusal index"* (`llms-full.txt:1528-1529`).

Blowing the budget costs **ten minutes** of lockout per service. Design for it up front.

### The smoke loop

Push over FTP → `pkgadd` → run the tool → `pkgrm` → confirm `/var/sadm` is clean. `pkgadd` inserts
each object into `/var/sadm/install/contents` in sorted position and creates
`/var/sadm/pkg/<PKG>/{pkginfo,install,save}`
(`../amix-packagemanager/docs/stock-pkg-system.md:111-114`).

Two caveats:

- **Test fresh install; treat upgrade as unproven.** Re-install/upgrade of a file whose basename is
  ≥ 14 characters was broken in the deployed engine and is fixed only in source, not in any
  deployed `/usr/apkg` (`../amix-packagemanager/NOTES.md:99-102`, `:126-129`).
- **`pkgadd -R` needs a real `/` line in `/etc/mnttab`.** `libinst`'s `get_mntinfo()` sorts the
  mount table by mount-point-name length and asserts the shortest entry is exactly `/`. A normally
  booted box always lists `/`, so this never fires there — but in a **minimal installer
  environment** it picks `/cdrom` as "root" and aborts with `identified </cdrom> as root file
  system instead of </>`, installing nothing (`llms-full.txt:2052`).
- **★ Stock `pkgadd` corrupts a RELATIVE symlink target.** **[measured]** 2026-08-28, same `.pkg`,
  same admin file, same box, only the engine differing:

  | engine | resulting link |
  |---|---|
  | stock `/usr/sbin/pkgadd` | `/usr/bin/patch -> /../local/bin/patch` — **dangling** |
  | heirloom `/usr/apkg/bin/pkgadd` | `/usr/bin/patch -> ../local/bin/patch` — correct |

  The pkgmap line was byte-identical in both runs (`s none /usr/bin/patch=../local/bin/patch`), so
  it is an **engine** defect: stock `pkgadd` prepends the install root to a relative target. It
  reports *"Installation was successful"* either way; `/../local/bin/patch` is simply a path that
  cannot exist. **Author symlink targets as absolute** unless the package is heirloom-only — a
  package from this repo must survive a bare box. The cost is `pkgadd -R` correctness, and stock
  `core` itself uses absolute targets (`s none /usr/bin/uname=/sbin/uname`).

### The smoke loop, as it was actually run (2026-08-28)

The first end-to-end run of this loop is `recipes/libamixcompat` + `recipes/patch`. What it took,
so the next one is cheaper:

- **A non-interactive `admin` file is required.** `pkgadd -n` alone aborts on the first question,
  and a package declaring a directory another package owns (`/usr/local`, owned by `core`) raises
  the conflict prompt. The working set is `conflict=nocheck  setuid=nocheck  action=nocheck
  idepend=nocheck  rdepend=nocheck  partial=nocheck  runlevel=nocheck  instance=overwrite
  space=quit  basedir=default`, written to a file on the box and passed as `-a`.
- **Shared directory ownership is fine and is recorded.** After both installs the contents DB reads
  `/usr/local d none 0755 root sys core acompat patch` — three owners, exactly as SVR4 intends.
- **`pkgchk <PKG>` is the cheapest independent verification** — it re-checks every installed object
  against the DB (mode, owner, size, checksum) and returns 0. Run it after every install.
- **`sum -r` is the only digest the box has** (no `md5`, no `cksum`), so print it host-side at build
  time for anything you will later want to prove is byte-identical on the box. It matched exactly
  for every artifact in this run, through `pkgmk` → `pkgtrans` → FTP → `pkgadd`.
- **Command lines over the telnet transport cap at 237 bytes** of command (SVR4 `MAX_CANON` is 256
  and the harness adds a completion marker). Past that the box answers *nothing* and the session
  wedges. Split, or push a script and run it — `amixrun.py` refuses host-side and says so.

---

## 8. What this guide does not know

Recorded so the next author does not mistake silence for safety.

**Six ports have now been completed** — `libamixcompat` and `patch` (2026-08-28), then `zlib`,
`gzip`, `grep` and `less` (BATCH-1, 2026-08-30). Every one was built, packaged, installed with the
**stock** `pkgadd` on the emulated golden 030, exercised, and verified with `pkgchk`. The removal
path was exercised too: `libamixcompat`, `patch`, `gzip` and `grep` were `pkgrm`'d clean, and
`zlib` and `less` stayed installed and survived those removals beside them.

- ~~No port has been completed yet.~~ **Six are.** What actually bit is folded into §2.2.1 (now
  *four* silent wrapper behaviours — the fourth is the sysroot include order that kills gnulib
  header replacement), §2.2.2 (imported assembly, disabled and asserted), §2.4.1 (the `__STDC__`
  gate has three keys), §3.1 (`environ` is a fourth "static-only" symbol), §3.4 (termcap over
  terminfo, and `/usr/ccs/lib`), §3.8 (pattern matching with no POSIX regex), §4 (the zlib
  `gzprintf` case), §4.1 (the cross-`configure` post-mortem) and §7 (stock `pkgadd`'s
  relative-symlink defect, and the smoke loop as run). **None of the things this guide predicted
  would be hardest actually were** — the killers were a preprocessor fallback, a header gate with
  more keys than documented, a packaging-engine bug, and an include-ordering rule inside the
  wrapper.
- ~~Cross-`configure` is untried.~~ **Run four times, green four times** (§4.1) — `patch`, `gzip`,
  `grep` and `less` all cross-configured, and zlib's hand-written `configure` ran too (§4). Six of
  patch's seven `AC_TRY_RUN` sites needed no seeding at all.
- ~~ncurses on Amix is untried, so the whole curses question is open.~~ **Half-answered**: the
  SVR4-curses route works for a *termcap* client — `less` links `-lcurses` and paints correctly
  (§3.4). Screen handling proper (`initscr`/`newwin`) and ncurses itself are still untried.

Still open:

- **Nothing has been run on metal.** All six packages are bench-proven only, on the emulated
  golden 030.
- **s5 name truncation was never exercised.** The bench golden's root is **UFS**, so the 14-byte
  dirent limit that shaped `libacompat.a`'s name and `pkgroll.sh`'s gate did not come into play on
  the box. The defence is by construction, not by test.
- **No FPU-less part was tested.** The float-conversion path passed because the rig has a 68882.
- **Upgrade/re-install is still unproven** — nothing has yet been installed over an earlier version
  of itself; every install so far went onto a box that did not already carry the package.
- **ncurses on Amix is untried** (§3.4), and so is any program that actually draws with curses
  rather than with termcap escapes.
- **SVR4 install scripts under the 1992 sh are untried** (§3.6) — all six packages are deliberately
  pure file payloads (D9), so the question is still open.
- **Nothing is `published`.** Six `.pkg` datastreams exist and install from a local file; none has
  been put in the catalog, so the remote-fetch half of the pipeline is unexercised from this side.
- **The `atof` drift's attribution is unresolved** — stock libc or FPE, nobody knows (§3.5).
- **`BASEDIR` / relocatable (`reloc/`) packages are unproven on Amix**; every package the family
  ships uses absolute paths. `depend(4)` and `copyright` files are unused here — those formats exist
  only in the vendored upstream man pages. No `.pkg` size limit, path-length limit (beyond the
  ~110-char `-R` prefix) or per-package object limit is recorded.
- **`mmap(MAP_FIXED)` exists** in the headers (`$SYSROOT/usr/include/sys/mman.h:62`, `:104`) but
  whether a fixed mapping at a chosen address succeeds is untested
  (`../tmp/2026-08-27-cputest-amix-research/B-amix-feasibility.md:332-336`).
- **Four topics in this guide have no grimoire coverage at all** — the `__STDC__` header gate, the
  SVR4 `/proc` ioctl model, the curses/terminfo situation, and any inventory of Amix libc exports.
  Their evidence is this repo's own measurement. Publishing them via `/amix-brief` would be a net
  gain to the family.
