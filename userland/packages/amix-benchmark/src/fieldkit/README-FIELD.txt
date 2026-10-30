amix-bench field kit 1.0
========================

A small CPU, FPU, memory, VM and disk benchmark for 68030 UNIX machines, meant
to be run on REAL hardware so we have ground truth to compare an emulated 68030
against.

If you have a real Amiga 3000 (or 4000) running Amiga Unix, running this and
sending the output back is exactly the data we are missing.  It takes about ten
minutes and needs no compiler, no network and no root privileges beyond being
able to read the disk you point it at.


WHAT IT MEASURES
----------------

  Dhrystone 2.1     Reinhold Weicker's integer CPU benchmark, unmodified netlib
                    source.  Reported as Dhrystones/second, and as DMIPS
                    (rate / 1757, the VAX-11/780 = 1 MIPS reference).

  Disk, 16 ways     sequential and random, read and write, at block sizes 512,
                    2048, 16384 and 65536 bytes.  Reported as KB/s, operations
                    per second, and microseconds per operation.

  FP throughput     a loop that is nothing but double-precision arithmetic, ten
                    operations per iteration, self-calibrated the way the
                    Dhrystone row is.  This is NOT Dhrystone: Dhrystone's
                    measured loop is integer.

  Whetstone         the classic double-precision FP benchmark, unmodified netlib
                    source.  Its module 8 exercises your machine's transcendental
                    library (sin/cos/log/exp/sqrt), which on some 68k parts is a
                    completely different code path from plain arithmetic.

  FP correctness    a 24-check IEEE-754 battery: divide by zero, NaN
                    propagation, overflow, gradual underflow to a subnormal,
                    round-to-nearest-even at both tie cases, signed zero, the
                    printf %f/%e/%g round trip, and whether FP state survives a
                    signal.  PASS or FAIL -- not a timing.  If your machine
                    FAILS one of these we would very much like to know.

  Memory bandwidth  memcpy and memset swept across block sizes, with every copy
                    checksummed against its source.  The curve across sizes is
                    where your cache boundary shows up.

  Processes and VM  fork+exit and fork+exec rates; a pipe ping-pong (two context
                    switches per round trip); and the first-touch page-fault
                    rate over a small working set.

The 16-cell disk grid is the point.  One `dd` number tells you almost nothing
about a machine's storage: what separates a slow *disk* from a slow *request
path* is how throughput changes with block size, and how far random access
falls below sequential.  A device that does 900 KB/s sequentially at 64 KB but
only 30 KB/s randomly at 512 bytes is telling you its per-request overhead, and
that number is comparable across very different machines.


HOW LONG IT TAKES
-----------------

  CPU test          ~15 seconds (it calibrates itself to a >=10 second run)
  each disk row     up to 60 seconds, usually far less
  FP throughput     ~15 seconds (also self-calibrated)
  Whetstone         ~20 seconds, capped at 90
  FP correctness    a few seconds, plus ~5 for the signal check
  memory / VM rows  under a minute each
  whole run         typically 10-20 minutes

EVERY ROW IS BOUNDED BY A WALL-CLOCK CAP, in both profiles.  No test can run
away on unfamiliar hardware -- that is a property we test for, not a hope.

Two of them deserve a specific word, because they are the ones that could
plausibly disturb your machine:

  * the page-fault row allocates a 4 MB working set (8 MB under --profile long)
    and touches one byte per page.  It DOES NOT try to force paging: a working
    set above what your machine has is REFUSED outright, not clamped.  Amix
    cannot tell the tool its own size, so tell it -- `--ram-mb 128` for a
    128 MB machine (BENCH_RAM_MB in the environment is the same knob); with no
    word from you it assumes the 16 MB floor, the smallest machine this kit
    targets, and the header records which (ram_mb=, ram_src=).  A benchmark
    that pushes somebody else's machine into swap is a wedge, not a
    measurement.
  * the fork row creates 200 short-lived children, one at a time, waiting for
    each.  If fork ever fails it stops immediately rather than retrying.


QUICK START
-----------

Unpack the kit somewhere with a little free space and run:

    sh runbench.sh

With no arguments it runs the CPU, FP, memory and VM tests and SKIPS every disk
test, because it has not been told what disk to touch.  That is deliberate --
see below.  The non-disk rows need no target at all: they exercise the processor,
its FP unit, main memory and the kernel.

To include the disk tests, give it a scratch file:

    sh runbench.sh --write-target /tmp/bench.dat --create-scratch

That creates an 8 MB file, then runs all 16 disk patterns against it (reads and
writes).  Delete the file afterwards.

To measure a raw device instead (see "What you are really measuring"):

    sh runbench.sh --read-target /dev/rdsk/c0d0s2 --span 8388608

Copy the whole block of output -- from `=== AMIX-BENCH RESULTS` to
`=== END AMIX-BENCH RESULTS ===` -- and send it back.


WRITE TESTS NEED AN EXPLICIT TARGET.  ALWAYS.
---------------------------------------------

There is no default write target and there never will be.  A write test
overwrites whatever it is pointed at, and pointed at a raw disk device it
destroys that disk.  So:

  * write rows are SKIPPED unless you pass --write-target;
  * the benchmark program refuses to write without --allow-write, which only
    runbench.sh passes, and only for the path you named;
  * the benchmark program CANNOT CREATE A FILE.  A mistyped path fails with
    "cannot open ... this program never creates files" instead of quietly
    creating something.

Use a scratch file, or a disk you are willing to lose.  Never a raw partition
that holds a filesystem you care about.


WHAT YOU ARE REALLY MEASURING
-----------------------------

  A FILE target measures the filesystem plus the buffer cache plus the disk.  On
  a machine with 16 MB of RAM and an 8 MB test file, a large part of the read
  tests will be served from memory -- and on a 128 MB machine ALL of it will --
  the numbers will be high and they will be real, but they are not disk
  numbers.

  A RAW CHARACTER DEVICE target (/dev/rdsk/...) bypasses the buffer cache and
  measures the driver and the disk.  This is the more interesting number, and it
  is also the one that will destroy data if you write to the wrong node.

Please say which you used; the results block records it either way.


IF THE BINARIES DO NOT RUN
--------------------------

The shipped binaries are m68k SVR4 ELF, dynamically linked against
/usr/lib/libc.so.1 -- built for Amiga Unix 2.1.  On any other 68030 UNIX they
will not execute.  Build from the included sources instead:

    cd src
    sh build-onbox.sh

Then run `sh runbench.sh` as usual.  The sources are C89 with K&R function
definitions, so a vintage vendor `cc` handles them; nothing needs GNU anything.

★ A ROW WHOSE BINARY IS MISSING SKIPS; IT DOES NOT FAIL THE RUN.  The kit does
not ship the Whetstone binary (see LICENCE / PROVENANCE below), so out of the
box the fpu.whet row reports "status=skipped reason=no-whet-in-this-kit".
build-onbox.sh builds it for you if your machine has a math library.  The same
goes for any other binary that will not build here: you get the other rows and a
row that says why, and the header's `tools=` line lists what the kit has.

★ AND ONE FLAG THAT IS NOT A STYLE CHOICE: fpbench is built at -O0 and must stay
that way.  An optimiser is entitled to fold floating-point arithmetic on known
values into its answer, and a "fast" FP result from an optimised build is a
measurement of your compiler.  build-onbox.sh already passes -O0 for that one
file; please do not raise it.

★ One thing to watch: Dhrystone divides by HZ at COMPILE time.  build-onbox.sh
detects your machine's clock rate with getconf and bakes it in.  The shipped
binaries assume HZ=60.  If your machine is not 60 Hz, the shipped `dhry` will
report a rate wrong by exactly that ratio -- runbench.sh detects the mismatch
and prints an `hz_warning=` line, but the fix is to rebuild.


THE DATE IN THE OUTPUT IS PROBABLY WRONG, AND THAT IS FINE
----------------------------------------------------------

Our Amix machines run with an unset real-time clock, so they think it is 1977.
We deliberately never set the clock forward, because SVR4 password aging records
"last changed" from it and a future date can lock accounts out.  The results
block therefore prints the machine's own date marked UNTRUSTED, and takes the
real timestamp from the environment variable BENCH_DATE if you set one:

    BENCH_DATE=2026-08-17 sh runbench.sh ...

If your machine's clock is correct, just mention the date when you send the
results -- do not change anything about how you run it.


WHAT TO SEND BACK
-----------------

The results block already contains `uname -a`, the clock rate, the profile and
the exact compiler flags.  Please add, in the mail:

  * machine model, and how it is expanded (accelerator? which?)
  * 68030 type and clock in MHz; FPU (68881/68882) present?
  * RAM, and how much of it is fast RAM
  * the disk: model, interface (A3000 onboard SCSI? A3091? something else?)
  * OS and version, and the compiler if you rebuilt
  * whether the disk target was a FILE or a RAW DEVICE
  * anything unusual about the run (other load on the machine, etc.)

A run with the machine otherwise idle is worth much more than a fast one.


OPTIONS
-------

  --read-target PATH    file or raw device to read (never written)
  --write-target PATH   scratch file or scratch device -- WILL BE OVERWRITTEN
  --create-scratch      create the write target with dd if it is absent
                        (refused for /dev/* paths)
  --span BYTES          extent to address; required for random patterns on a
                        raw device, which has no size a program can ask for
  --profile standard    the default sizes (8 MB sequential, 512 random ops)
  --profile long        4x sizes -- longer runs, less measurement noise
  --seed N              random-offset seed (default 1).  The same seed gives the
                        same offsets on every machine, so two machines really
                        do run the same access pattern.
  --sync                open writes O_SYNC (refused if your libc has no O_SYNC)
  --list                print the matrix and exit
  --only ID             run one row, e.g. --only disk.rand.read.512 or
                        --only fpu.paranoia
  --run-id TEXT         a label echoed back in the header

  BENCH_DATE=...        stamp a trustworthy date into the header


LICENCE / PROVENANCE
--------------------

  dhry.c                Dhrystone 2.1, Reinhold P. Weicker / Rick Richardson,
                        1988, public domain.  Unmodified apart from removing a
                        redundant K&R `extern int times()` declaration that
                        clashes with <sys/times.h> on an ANSI compiler.  The
                        original netlib documentation ships alongside it as
                        dhry-RATIONALE.txt and dhry-README_C.txt.

  whetstone.c           "C Converted Double Precision Whetstone" version 1.2,
                        Rich Painter / Painter Engineering, 1998, from
                        www.netlib.org/benchmark/whetstone.c.  Its licence grants
                        use, duplication and publication provided the copyright
                        block is kept -- it is, and the file is byte-pristine
                        below the amix provenance header, whose stated sha256 you
                        can verify yourself.

                        ★ THE WHETSTONE BINARY IS NOT IN THIS KIT, ON PURPOSE.
                        Whetstone needs sin/cos/atan/log/exp/sqrt, and Amiga
                        Unix's SHARED libc has none of them -- so a prebuilt
                        binary would have to statically embed pieces of the
                        vendor's libm, which is not ours to redistribute.  Build
                        it yourself with src/build-onbox.sh if you have a
                        compiler and a libm; otherwise that one row skips.

  iobench.c             written for this project.
  fpbench.c             written for this project.
  membench.c            written for this project.
  vmbench.c             written for this project.
