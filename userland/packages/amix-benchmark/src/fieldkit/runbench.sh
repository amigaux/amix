#!/bin/sh
# runbench.sh -- the amix-bench standard matrix, run ON the machine under test.
#
# This file is THE definition of the matrix.  The host-side driver
# (tools/amix-bench/bench-drive.sh) does not carry a second copy: it asks this
# script for the matrix with --list and then runs these same rows one at a time
# with --only.  If the two ever disagree, the numbers are not comparable, so
# there is deliberately only one of them.
#
#   sh runbench.sh                         CPU test only (no disk target given)
#   sh runbench.sh --write-target /tmp/bench.dat --create-scratch
#   sh runbench.sh --read-target /dev/rdsk/c6d0s2 --span 8388608
#   sh runbench.sh --list                  print the matrix, run nothing
#   sh runbench.sh --only disk.seq.read.512 --no-header
#   sh runbench.sh --help
#
# ---------------------------------------------------------------------------
# WRITE SAFETY.  There is NO default write target and there never will be.  A
# write row is skipped unless you name a target with --write-target, and iobench
# additionally refuses to write without --allow-write and cannot create a file
# at all -- so a mistyped path fails instead of eating something.  A RAW DISK
# DEVICE as a write target is destroyed by these tests.  Use a scratch disk.
#
# ---------------------------------------------------------------------------
# THE BOX CLOCK IS NOT A TIMESTAMP.  Amix machines in this project run with an
# unset RTC (dates print as 1977/1978), and the clock must never be wound
# forward -- SVR4 password aging latches "last changed" dates from it and a
# future date locks accounts out.  So this script prints the box date only as
# an UNTRUSTED field; the real timestamp comes from whoever ran it (BENCH_DATE,
# or the host driver's own clock).
#
# ---------------------------------------------------------------------------
# PORTABILITY.  Written for the SVR4.0 Bourne shell, which is what Amix 2.1 has:
# no $(...), no $((...)), no [[ ]], no local, no arrays, no printf(1).  Arithmetic
# goes through expr(1).  Tested by tools/amix-bench-selftest.sh, which lints this
# file for every one of those constructs -- it is meant to run unmodified on other
# people's 68030 UNIX machines, several of which are older than bash.

BENCH_FORMAT=1
TOOL_VERSION=1.0

BENCHDIR=`dirname "$0"`
if test -n "$BENCH_DIR"; then BENCHDIR="$BENCH_DIR"; fi

DHRY="$BENCHDIR/dhry"
IOBENCH="$BENCHDIR/iobench"
BUILDINFO="$BENCHDIR/BUILD-INFO"

# ---------------------------------------------------------------------------
# THE OPTIONAL BINARIES.  dhry and iobench are required -- a kit without them is
# a broken kit.  These four are not: a field kit built on somebody else's UNIX
# may have failed to build one (whet in particular needs a libm that Amix's
# SHARED libc does not have), and a kit predating them will not carry them at
# all.  Every row that needs one of these reports status=skipped with the reason
# rather than failing the run, because a real A3000 owner running a kit that
# arrived in the post should get fifteen good rows and a clear note, not an
# error.  The header's tools= line says which were found.
FPBENCH="$BENCHDIR/fpbench"
WHET="$BENCHDIR/whet"
MEMBENCH="$BENCHDIR/membench"
VMBENCH="$BENCHDIR/vmbench"

PROFILE=standard
READ_TARGET=
WRITE_TARGET=
SPAN=
ONLY=
LIST=0
HEADER=1
BODY=1
CREATE_SCRATCH=0
RUN_ID=-
SEED=1
SYNC=0

usage() {
    echo "usage: sh runbench.sh [--read-target PATH] [--write-target PATH]"
    echo "                      [--span BYTES] [--profile standard|long]"
    echo "                      [--create-scratch] [--seed N] [--sync]"
    echo "                      [--run-id TEXT] [--only ID] [--list]"
    echo "                      [--no-header] [--header-only] [--ram-mb N]"
    echo ""
    echo "  --read-target PATH   file or raw device to READ (never written)"
    echo "  --write-target PATH  scratch file or scratch device -- WILL BE OVERWRITTEN"
    echo "  --create-scratch     create the write target with dd if it is absent"
    echo "  --span BYTES         extent to address (required for raw devices)"
    echo "  --profile long       4x the sizes; use this for PSTAT decomposition"
    echo "  --ram-mb N           what the box has, in MB: vmbench refuses a working"
    echo "                       set above it (default: the 16 MB floor -- Amix has"
    echo "                       no sysconf for it; BENCH_RAM_MB in the environment"
    echo "                       is the same knob)"
    echo ""
    echo "  With no target, only the CPU test runs and every disk row is skipped."
}

while test $# -gt 0; do
    # A value-taking option with nothing after it must fail here, not silently
    # set an empty target and then "skip" every row for no stated reason.
    case "$1" in
        --read-target|--write-target|--span|--profile|--run-id|--seed|--only|--ram-mb)
            if test $# -lt 2; then
                echo "runbench: $1 needs a value" >&2; exit 2
            fi ;;
    esac
    case "$1" in
        --read-target)  READ_TARGET="$2"; shift ;;
        --write-target) WRITE_TARGET="$2"; shift ;;
        --span)         SPAN="$2"; shift ;;
        --profile)      PROFILE="$2"; shift ;;
        --run-id)       RUN_ID="$2"; shift ;;
        --seed)         SEED="$2"; shift ;;
        --only)         ONLY="$2"; shift ;;
        --ram-mb)       BENCH_RAM_MB="$2"; export BENCH_RAM_MB; shift ;;
        --sync)         SYNC=1 ;;
        --create-scratch) CREATE_SCRATCH=1 ;;
        --list)         LIST=1 ;;
        --no-header)    HEADER=0 ;;
        --header-only)  BODY=0 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "runbench: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ------------------------------------------------------------- the profile ---
# Two sizes, and only two, so that a "standard" result from any machine is
# comparable with any other.  The profile name is printed in the header, so a
# long-profile run can never be mistaken for a standard one.
#
# SEQ_BYTES is the byte cap for the sequential rows; RAND_OPS is the operation
# cap for the random rows (a random row capped by BYTES would run for an hour at
# 512-byte blocks on a slow disk).  MAX_SECONDS bounds every row regardless --
# this suite runs on other people's hardware.
#
# EVERY ROW HAS A WALL-CLOCK CAP IN BOTH PROFILES.  That is not decoration: the
# fpu, mem and vm rows are new and three of them (fpu.whet, vm.fault, mem.bw)
# have no natural stopping point at all on an unknown machine.  A row without a
# cap on somebody else's hardware is a wedge waiting to be blamed on their
# kernel.
case "$PROFILE" in
    standard)
        SEQ_BYTES=8388608;  RAND_OPS=512;  MAX_SECONDS=60
        FP_TARGET_SECS=12;  FP_MIN_SECS=10;   FP_MAX_SECONDS=60
        WHET_TARGET_SECS=20; WHET_MIN_SECS=8; WHET_MAX_SECONDS=90
        MEM_MAX_SECONDS=45; MEM_SIZES=1024,4096,16384,65536,262144
        MEM_BYTES_PER_SIZE=4194304
        VM_MAX_SECONDS=45;  VM_FORK_OPS=200;  VM_CTX_OPS=2000
        VM_WS_BYTES=4194304
        ;;
    long)
        SEQ_BYTES=33554432; RAND_OPS=2048; MAX_SECONDS=180
        FP_TARGET_SECS=30;  FP_MIN_SECS=20;   FP_MAX_SECONDS=180
        WHET_TARGET_SECS=45; WHET_MIN_SECS=20; WHET_MAX_SECONDS=240
        MEM_MAX_SECONDS=120; MEM_SIZES=1024,4096,16384,65536,262144,1048576
        MEM_BYTES_PER_SIZE=16777216
        VM_MAX_SECONDS=120; VM_FORK_OPS=800;  VM_CTX_OPS=8000
        VM_WS_BYTES=8388608
        ;;
    *) echo "runbench: --profile must be standard or long" >&2; exit 2 ;;
esac

# Dhrystone is calibrated to run for at least this many seconds.  At HZ=60 that
# is 600 clock ticks, so the +-1 tick quantisation is under 0.2%.
DHRY_TARGET_SECS=12
DHRY_MIN_SECS=10
DHRY_PILOT=20000
DHRY_MAX_RUNS=500000000

# ★ HOW LONG THE CPU ROW MAY LEGITIMATELY TAKE.  A host driver runs this row over
# a telnet session with a completion timeout, and that timeout has to be sized
# from the row, not guessed: on 2026-08-17 the default 60 s was shorter than the
# calibration and bench-drive recorded a NO-OUTPUT for a machine that was working
# perfectly.  The row is bounded by the escalation ladder (up to 6 pilot runs,
# and the one that finally clears Dhrystone's 2 s floor can be ~8x the last that
# did not, so ~16 s) plus up to two sized runs of DHRY_TARGET_SECS.  240 s is
# that sum with room to spare.  It is emitted in the header so the driver reads
# it from here rather than restating it -- same rule as the matrix.
DHRY_BUDGET_SECS=240

# ---------------------------------------------------------------------------
# THE FP ROWS' CALIBRATION, AND THE BUDGETS THAT BOUND IT.
#
# fpu.dhry is calibrated exactly the way cpu.dhry is: a short pilot, then a real
# run sized from the pilot's own answer.  The pilot is separately capped
# (FP_PILOT_SECS) so a very slow FP-emulation lane cannot spend the whole row on
# calibration.  FP_MAX_RUNS bounds the escalation: Number_Of_Runs-style counters
# and expr(1) are both 32-bit on the target, so an unbounded ladder would
# eventually overflow and report a confident lie.
FP_PILOT=20000
FP_PILOT_SECS=5
FP_MAX_RUNS=200000000

# ★ THE PILOT LADDER PAYS NO FINGERPRINT (2026-08-28).  Every pilot invocation
# used to run fpbench's determinism check -- two fixed-length reference
# reductions -- before doing any work --max-seconds could stop.  On the metal
# 68LC060 that was 365 s PER INVOCATION and the ladder allows six, so up to
# 2,554 s of pure calibration overhead sat inside a row whose published budget
# was 180 s.  The row could not keep its own promise on the one class of machine
# it exists to measure, and it did not: 2026-08-28 recorded three transport
# attempts, 911 s, and EMPTY output, all three dying inside the second reference
# call.  The pilot needs a RATE, not a fingerprint, so it asks for --no-ref; only
# the sized run takes one, and it is told what it may spend on it.
FP_REF_MAX_SECS=30

# ★ HOW LONG THE fpu.dhry ROW MAY LEGITIMATELY TAKE -- DERIVED, NOT ASSERTED.
# Same rule as DHRY_BUDGET_SECS, and after 2026-08-28 the derivation is written
# out, because the previous number was a guess that the hardware falsified:
#
#   pilot ladder   6 invocations x (probe + FP_PILOT_SECS + one chunk overshoot)
#                  The probe is 64 kernel iterations; the overshoot is one
#                  chunk, and fpbench grows a chunk only from one that finished
#                  under 2 ticks, so after any growth a chunk is under ~8 ticks.
#                  Call it 6 x (1 + 5 + 1) = 42 s.
#   sized run      probe + the fingerprint (bounded by FP_REF_MAX_SECS, and
#                  skipped out loud if the probe says it would exceed it) +
#                  FP_MAX_SECONDS + one chunk = 1 + 30 + 60 + 1 = 92 s.
#   -------------------------------------------------------------------------
#   worst case     134 s, standard profile.  180 s carries the slack.
#
# On the 2026-08-28 metal box specifically -- ~9.1 ms per kernel iteration --
# the pilot ladder breaks on its FIRST invocation (a slow machine resolves a
# rate immediately; the ladder exists for machines too FAST to time), so the
# real cost there is ~6 s of pilot + ~22 s of sized run = under 30 s.
#
# Published so the host driver sizes its transport timeout from HERE and does
# not restate it -- the same rule as the matrix.
case "$PROFILE" in
    standard) FPDHRY_BUDGET_SECS=180; WHET_BUDGET_SECS=150 ;;
    long)     FPDHRY_BUDGET_SECS=420; WHET_BUDGET_SECS=330; FP_REF_MAX_SECS=60 ;;
esac

# ★ WHETSTONE CANNOT BE INTERRUPTED, SO ITS LOOP COUNT IS THE ONLY BRAKE.
# The vendored source takes a loop count and runs it to completion -- there is
# no --max-seconds to give it.  So the ladder starts tiny, escalates by 4, and
# the final sized run is REFUSED if the pilot predicts it would exceed
# WHET_MAX_SECONDS.  Prediction is honest here because whetstone's work is
# exactly linear in LOOP.
WHET_PILOT=100
WHET_PILOT_MIN_SECS=2
WHET_MAX_LOOP=20000000

# ------------------------------------------------------------- the matrix ----
# id : pattern : direction : block size.
#   1 CPU row + 16 disk rows + 3 FP rows + 1 memory row + 3 VM rows = 24.
#
# The pattern field is what the host driver switches on, so a new SUBSYSTEM gets
# a new pattern name rather than being smuggled into an existing one.  dir and
# bs are "-" for every row that has neither, which keeps --list four fields wide
# for all of them.
matrix_rows() {
    echo "cpu.dhry:cpu:-:-"
    for pat in seq rand
    do
        for dir in read write
        do
            for bs in 512 2048 16384 65536
            do
                echo "disk.$pat.$dir.$bs:$pat:$dir:$bs"
            done
        done
    done
    echo "fpu.dhry:fpu:-:-"
    echo "fpu.whet:fpu:-:-"
    echo "fpu.paranoia:fpu:-:-"
    echo "mem.bw:mem:-:-"
    echo "vm.fork:vm:-:-"
    echo "vm.ctx:vm:-:-"
    echo "vm.fault:vm:-:-"
}

if test "$LIST" = 1; then
    matrix_rows | sed 's/:/ /g'
    exit 0
fi

field() { echo "$1" | cut -d: -f"$2"; }

# ------------------------------------------------------------ preflight ------
if test ! -x "$DHRY"; then
    echo "runbench: $DHRY is missing or not executable." >&2
    echo "  The kit ships prebuilt m68k SVR4 binaries.  On a different UNIX," >&2
    echo "  build them from the included sources:  cc -O -DHZ=<your HZ> -o dhry src/dhry.c" >&2
    exit 2
fi
if test ! -x "$IOBENCH"; then
    echo "runbench: $IOBENCH is missing or not executable (see src/iobench.c)." >&2
    exit 2
fi

# The runtime HZ comes from iobench's sysconf; Dhrystone's HZ is compiled in.
# A mismatch does not stop the run -- it makes the Dhrystone number wrong by
# exactly that ratio, so it is announced loudly instead of hidden.
IOINFO=`"$IOBENCH" --info 2>/dev/null`
HZ_RUNTIME=`echo "$IOINFO" | sed -n 's/.*hz=\([0-9][0-9]*\).*/\1/p'`
if test -z "$HZ_RUNTIME"; then HZ_RUNTIME=0; fi
PAGESIZE=`echo "$IOINFO" | sed -n 's/.*pagesize=\([0-9][0-9]*\).*/\1/p'`
if test -z "$PAGESIZE"; then PAGESIZE=unknown; fi
# The RAM ceiling vmbench will refuse a working set above, and where it got it:
# --ram-mb / BENCH_RAM_MB (env), the libc (sysconf), or the 16 MB floor.  16 MB
# is old information on every front (2026-09-15: 040/060 kernels run 128 MB, the
# 030 kernel 88 MB), so a run on a bigger box should be told the size -- the
# header records what it was told.  A malformed value stops the run here, not
# in the middle of the matrix.
RAM_MB=unknown; RAM_SRC=none
if test -x "$VMBENCH"; then
    VMINFO=`"$VMBENCH" --info 2>&1` || {
        echo "runbench: $VMINFO" >&2; exit 2; }
    RAM_MB=`echo "$VMINFO" | sed -n 's/.*ram_mb=\([0-9][0-9]*\).*/\1/p'`
    RAM_SRC=`echo "$VMINFO" | sed -n 's/.*ram_src=\([a-z-]*\).*/\1/p'`
    if test -z "$RAM_MB"; then RAM_MB=unknown; fi
    if test -z "$RAM_SRC"; then RAM_SRC=none; fi
fi
HZ_DHRY=60
if test -f "$BUILDINFO"; then
    v=`sed -n 's/^dhry_hz=\(.*\)$/\1/p' "$BUILDINFO"`
    if test -n "$v"; then HZ_DHRY="$v"; fi
fi

# ------------------------------------------------------- the scratch file ----
if test "$CREATE_SCRATCH" = 1; then
    if test -z "$WRITE_TARGET"; then
        echo "runbench: --create-scratch needs --write-target" >&2; exit 2
    fi
    case "$WRITE_TARGET" in
        /dev/*)
            echo "runbench: REFUSED -- --create-scratch will not dd over a device node" >&2
            echo "  ($WRITE_TARGET).  Point it at a scratch FILE, or pre-create the" >&2
            echo "  device's contents yourself if you really mean a raw disk." >&2
            exit 2 ;;
    esac
    if test -f "$WRITE_TARGET"; then
        echo "runbench: scratch file $WRITE_TARGET already exists, leaving it alone"
    else
        blocks=`expr $SEQ_BYTES / 8192`
        echo "runbench: creating scratch file $WRITE_TARGET ($SEQ_BYTES bytes)"
        dd if=/dev/zero of="$WRITE_TARGET" bs=8192 count=$blocks 2>/dev/null
        if test ! -f "$WRITE_TARGET"; then
            echo "runbench: could not create $WRITE_TARGET" >&2; exit 2
        fi
    fi
fi

# ------------------------------------------------------------- the header ----
emit_header() {
    echo "=== AMIX-BENCH RESULTS format=$BENCH_FORMAT ==="
    echo "tool_version=$TOOL_VERSION"
    echo "run_id=$RUN_ID"
    if test -n "$BENCH_DATE"; then
        echo "date_host=$BENCH_DATE"
    else
        echo "date_host=unset"
    fi
    echo "date_box=`date` (UNTRUSTED -- this machine's RTC is not set and must not be)"
    echo "uname=`uname -a`"
    echo "hz_runtime=$HZ_RUNTIME"
    echo "hz_dhry_build=$HZ_DHRY"
    if test "$HZ_RUNTIME" != "$HZ_DHRY"; then
        echo "hz_warning=dhry was built for HZ=$HZ_DHRY but this machine reports HZ=$HZ_RUNTIME -- the Dhrystone rate is wrong by that ratio; rebuild dhry with -DHZ=$HZ_RUNTIME"
    fi
    echo "mem=`bench_mem`"
    echo "profile=$PROFILE"
    echo "seq_bytes=$SEQ_BYTES"
    echo "rand_ops=$RAND_OPS"
    echo "max_seconds=$MAX_SECONDS"
    echo "dhry_budget_secs=$DHRY_BUDGET_SECS"
    echo "fp_target_secs=$FP_TARGET_SECS"
    echo "fp_max_seconds=$FP_MAX_SECONDS"
    echo "fpdhry_budget_secs=$FPDHRY_BUDGET_SECS"
    echo "fp_ref_max_secs=$FP_REF_MAX_SECS"
    echo "whet_target_secs=$WHET_TARGET_SECS"
    echo "whet_max_seconds=$WHET_MAX_SECONDS"
    echo "whet_budget_secs=$WHET_BUDGET_SECS"
    echo "mem_max_seconds=$MEM_MAX_SECONDS"
    echo "mem_sizes=$MEM_SIZES"
    echo "mem_bytes_per_size=$MEM_BYTES_PER_SIZE"
    echo "vm_max_seconds=$VM_MAX_SECONDS"
    echo "vm_fork_ops=$VM_FORK_OPS"
    echo "vm_ctx_ops=$VM_CTX_OPS"
    echo "vm_ws_bytes=$VM_WS_BYTES"
    echo "ram_mb=$RAM_MB"
    echo "ram_src=$RAM_SRC"
    echo "tools=`bench_tools`"
    echo "pagesize=$PAGESIZE"
    echo "seed=$SEED"
    echo "sync=$SYNC"
    if test -n "$READ_TARGET"; then
        echo "read_target=$READ_TARGET"
    else
        echo "read_target=none (read rows skipped)"
    fi
    if test -n "$WRITE_TARGET"; then
        echo "write_target=$WRITE_TARGET"
    else
        echo "write_target=none (write rows skipped -- there is no default, on purpose)"
    fi
    if test -n "$SPAN"; then echo "span=$SPAN"; else echo "span=auto"; fi
    if test -f "$BUILDINFO"; then
        # Every BUILD-INFO key, prefixed.  No \| alternation: that is a GNU sed
        # extension and this has to run under SVR4 sed.  Line 1 is the format
        # banner, which has no '=' and is dropped.
        sed '1d' "$BUILDINFO" | sed 's/^/build_/'
    else
        echo "build_info=absent"
    fi
    echo "--- results ---"
}

# Which optional binaries this kit actually carries.  Printed in the header so a
# results block with skipped fpu/mem/vm rows says WHY on its own face, without
# anyone having to go and look at the machine it came from.
bench_tools() {
    t=dhry,iobench
    if test -x "$FPBENCH";  then t="$t,fpbench";  fi
    if test -x "$WHET";     then t="$t,whet";     fi
    if test -x "$MEMBENCH"; then t="$t,membench"; fi
    if test -x "$VMBENCH";  then t="$t,vmbench";  fi
    echo "$t"
}

# Best effort only, and never fatal: there is no portable way to ask an SVR4.0
# kernel how much memory it has, so we look where Amix happens to say it.
bench_mem() {
    m=
    if test -x /usr/sbin/dmesg; then
        m=`/usr/sbin/dmesg 2>/dev/null | grep -i 'mem' | tail -1`
    fi
    if test -z "$m"; then
        if test -x /etc/dmesg; then
            m=`/etc/dmesg 2>/dev/null | grep -i 'mem' | tail -1`
        fi
    fi
    if test -z "$m"; then m=unknown; fi
    echo "$m"
}

# ------------------------------------------------------------ the CPU row ----
# Dhrystone reports the rate itself; what this does is CHOOSE THE RUN LENGTH so
# the rate is trustworthy.  The measured window has to be long compared with one
# clock tick, so: a short pilot run, then a real run sized from the pilot's own
# answer.  The measurement is still Dhrystone's own times()-bracketed loop --
# nothing here reaches inside it.
run_dhry() {
    runs=$DHRY_PILOT
    tries=0
    dps=0
    while test $tries -lt 6
    do
        out=`echo $runs | "$DHRY" 2>&1`
        dps=`echo "$out" | sed -n 's/^Dhrystones per Second: *\([0-9][0-9]*\).*/\1/p'`
        if test -z "$dps"; then dps=0; fi
        if test "$dps" -gt 0; then break; fi
        # "Measured time too small" -- the machine is faster than the pilot
        # assumed.  Multiply and try again rather than reporting nothing.
        # DHRY_MAX_RUNS bounds this: Number_Of_Runs is an int inside Dhrystone
        # and expr here is 32-bit on the target, so an unbounded escalation
        # would eventually overflow both and report a confident lie.
        if test "$runs" -ge $DHRY_MAX_RUNS; then break; fi
        runs=`expr $runs \* 8`
        if test "$runs" -gt $DHRY_MAX_RUNS; then runs=$DHRY_MAX_RUNS; fi
        tries=`expr $tries + 1`
    done
    if test "$dps" -le 0; then
        # Dhrystone refuses to report below 2 s of measured time.  Reaching the
        # run cap without getting there means this machine is too fast for a
        # HZ-granularity timer at this benchmark size -- true of any modern
        # host, and not of any 68030.
        echo "TEST cpu.dhry status=failed reason=too-fast-for-hz-timer runs=$runs hz=$HZ_RUNTIME"
        return 1
    fi

    # Size the real run from the pilot, then check the result actually lasted
    # long enough; if the pilot underestimated, one rescaled retry fixes it.
    attempt=0
    while test $attempt -lt 2
    do
        runs=`expr $dps \* $DHRY_TARGET_SECS`
        if test "$runs" -gt $DHRY_MAX_RUNS; then runs=$DHRY_MAX_RUNS; fi
        out=`echo $runs | "$DHRY" 2>&1`
        newdps=`echo "$out" | sed -n 's/^Dhrystones per Second: *\([0-9][0-9]*\).*/\1/p'`
        if test -z "$newdps"; then newdps=0; fi
        if test "$newdps" -le 0; then
            echo "TEST cpu.dhry status=failed reason=no-rate-parsed runs=$runs"
            return 1
        fi
        secs=`expr $runs / $newdps`
        if test "$secs" -ge $DHRY_MIN_SECS; then
            dps=$newdps
            break
        fi
        dps=$newdps
        attempt=`expr $attempt + 1`
    done

    us=`echo "$out" | sed -n 's/^Microseconds for one run through Dhrystone: *\(.*\)$/\1/p' | sed 's/ *$//'`
    reg=without
    if echo "$out" | grep "with 'register'" > /dev/null 2>&1; then reg=with; fi
    # DMIPS = rate / 1757, the VAX-11/780 "1 MIPS" reference.  Integer division
    # in tenths, because this shell has no floating point.
    dmips10=`expr $dps \* 10 / 1757`
    # The calibration targets DHRY_TARGET_SECS and accepts DHRY_MIN_SECS.  If
    # even the run cap could not buy that much measured time, say so on the row
    # rather than presenting a quantisation-dominated rate as a clean one.
    warn=ok
    if test "$secs" -lt $DHRY_MIN_SECS; then warn=short-run; fi
    echo "TEST cpu.dhry status=ok runs=$runs dhrystones_per_sec=$dps us_per_run=$us secs=$secs dmips_x10=$dmips10 register=$reg hz_build=$HZ_DHRY warn=$warn"
    return 0
}

# ----------------------------------------------------------- the disk rows ---
run_disk() {
    # $1 id  $2 pattern  $3 direction  $4 block size
    id="$1"; pat="$2"; dir="$3"; bs="$4"

    target=
    extra=
    if test "$dir" = write; then
        target="$WRITE_TARGET"
        if test -z "$target"; then
            echo "TEST $id status=skipped reason=no-write-target"
            return 0
        fi
        extra="--allow-write"
        if test "$SYNC" = 1; then extra="$extra --sync"; fi
    else
        target="$READ_TARGET"
        if test -z "$target"; then
            # A named write target is a file we are already allowed to touch, so
            # it is a legitimate read target too -- but only if the operator
            # named one.  Nothing is ever read from a path nobody named.
            target="$WRITE_TARGET"
        fi
        if test -z "$target"; then
            echo "TEST $id status=skipped reason=no-read-target"
            return 0
        fi
    fi

    if test "$pat" = rand; then
        cap="--ops $RAND_OPS"
    else
        cap="--bytes $SEQ_BYTES"
    fi
    spanarg=
    if test -n "$SPAN"; then spanarg="--span $SPAN"; fi

    out=`"$IOBENCH" --path "$target" --pattern "$pat" --dir "$dir" --bs "$bs" \
         $cap --max-seconds $MAX_SECONDS --seed $SEED --label "$id" $spanarg $extra </dev/null 2>&1`
    rc=$?
    line=`echo "$out" | grep '^IOBENCH ' | sed 's/^IOBENCH //'`
    if test -z "$line"; then
        why=`echo "$out" | head -2 | tr '\012' ' ' | sed 's/  */ /g'`
        echo "TEST $id status=failed rc=$rc reason=$why"
        return 1
    fi
    echo "TEST $id status=ok $line"
    return 0
}

# ------------------------------------------------- the fpu / mem / vm rows ---
#
# These four binaries all print ONE summary line of their own, already carrying
# status= and every measured field.  Rather than re-deriving the fields here --
# a second place to get them wrong -- the summary is turned into a TEST line
# mechanically: strip the tool's banner word and its label, hoist status= to the
# front, keep everything else verbatim.  Adding a field to a binary therefore
# needs no change here at all.
tool_test_line() {
    # $1 = row id, $2 = the tool's summary line
    tl_id="$1"
    tl_line="$2"
    if test -z "$tl_line"; then
        echo "TEST $tl_id status=failed reason=no-output-from-tool"
        return 1
    fi
    tl_st=`echo "$tl_line" | sed -n 's/.*status=\([a-z][a-z]*\).*/\1/p'`
    if test -z "$tl_st"; then tl_st=failed; fi
    tl_rest=`echo "$tl_line" | sed -e 's/^[A-Z][A-Z]* //' -e 's/label=[^ ]* //' -e 's/status=[a-z][a-z]* //'`
    echo "TEST $tl_id status=$tl_st $tl_rest"
    if test "$tl_st" = ok; then return 0; fi
    if test "$tl_st" = skipped; then return 0; fi
    return 1
}

# Runs per second from a measured (runs, ticks) pair, without either losing the
# answer to integer division or overflowing a 32-bit expr(1).
#
# ★ THE ORDER MATTERS IN BOTH DIRECTIONS, and until 2026-08-28 only one of them
# was guarded.  Dividing first is safe against overflow -- runs can reach 1e8 and
# runs*HZ would wrap -- but it THROWS THE ANSWER AWAY when runs is small, which
# is exactly the case a slow FP-emulation lane produces: 549 runs in 300 ticks
# divides to 1, times HZ=60 gives 60 runs/s against a true 110, and the sized run
# comes out at half its target and warns short-run for no reason.  That case only
# became reachable when the pilot's own deadline started working.  So: multiply
# first while the product provably fits (1e7 * HZ=100 is 1e9, inside a signed
# 32-bit long), divide first above that, where the loss is under 0.1% anyway.
fp_rate_of() {   # fp_rate_of <runs> <ticks> -> runs per second
    if test "$2" -le 0; then echo 0; return 0; fi
    if test "$1" -le 10000000; then
        expr "$1" \* $HZ_RUNTIME / "$2"
    else
        expr "$1" / "$2" \* $HZ_RUNTIME
    fi
}

# ★ fpu.dhry IS NOT cpu.dhry, AND THE TWO NUMBERS MUST NEVER SHARE A COLUMN.
# cpu.dhry runs Dhrystone 2.1, whose measured loop is INTEGER.  fpu.dhry runs a
# loop that is nothing but double-precision arithmetic.  The 2026-08-27 metal
# figure of 70,093.5 d/s described as "the FP-dhrystone row" was the Dhrystone
# binary that CONTAINS floating point -- that is a cpu.dhry number and it
# belongs beside our cpu.dhry numbers, not here.
run_fpdhry() {
    if test ! -x "$FPBENCH"; then
        echo "TEST fpu.dhry status=skipped reason=no-fpbench-in-this-kit"
        return 0
    fi

    # ---- the pilot ladder, same shape as run_dhry's ----------------------
    # ★ --no-ref: a pilot needs a rate, not a fingerprint.  See the budget
    # derivation above -- this is the whole of the 2026-08-28 fpu.dhry defect.
    runs=$FP_PILOT
    tries=0
    rate=0
    while test $tries -lt 6
    do
        out=`"$FPBENCH" --test dhry --runs $runs --max-seconds $FP_PILOT_SECS --no-ref --label fpu.dhry </dev/null 2>&1`
        ticks=`echo "$out" | sed -n 's/.* ticks=\([0-9][0-9]*\) .*/\1/p'`
        did=`echo "$out" | sed -n 's/.* runs=\([0-9][0-9]*\) .*/\1/p'`
        if test -z "$ticks"; then ticks=0; fi
        if test -z "$did"; then did=0; fi
        if test "$ticks" -ge 6 -a "$did" -gt 0; then
            rate=`fp_rate_of $did $ticks`
            if test "$rate" -gt 0; then break; fi
        fi
        if test "$runs" -ge $FP_MAX_RUNS; then break; fi
        runs=`expr $runs \* 8`
        if test "$runs" -gt $FP_MAX_RUNS; then runs=$FP_MAX_RUNS; fi
        tries=`expr $tries + 1`
    done
    if test "$rate" -le 0; then
        echo "TEST fpu.dhry status=failed reason=could-not-calibrate runs=$runs hz=$HZ_RUNTIME"
        return 1
    fi

    # ---- the sized run ---------------------------------------------------
    runs=`expr $rate \* $FP_TARGET_SECS`
    if test "$runs" -gt $FP_MAX_RUNS; then runs=$FP_MAX_RUNS; fi
    if test "$runs" -lt $FP_PILOT; then runs=$FP_PILOT; fi
    out=`"$FPBENCH" --test dhry --runs $runs --max-seconds $FP_MAX_SECONDS \
         --ref-max-seconds $FP_REF_MAX_SECS --label fpu.dhry </dev/null 2>&1`
    line=`echo "$out" | grep '^FPBENCH ' | tail -1`
    ticks=`echo "$line" | sed -n 's/.* ticks=\([0-9][0-9]*\) .*/\1/p'`
    if test -z "$ticks"; then ticks=0; fi
    secs=0
    if test "$HZ_RUNTIME" -gt 0; then secs=`expr $ticks / $HZ_RUNTIME`; fi
    tail_warn=ok
    if test "$secs" -lt $FP_MIN_SECS; then tail_warn=short-run; fi
    tool_test_line fpu.dhry "$line secs=$secs calib_warn=$tail_warn"
    return $?
}

# ★ WHETSTONE'S OWN RATE LINE IS NOT READ.  Its last act is
#     if (KIPS >= 1000.0) print MIPS else print KIPS
# and that is the only floating-point comparison in the vendored file.  On this
# family's cross toolchain a register-to-register fcmp assembles with its
# operands REVERSED, so that branch can pick the wrong unit and be wrong by a
# factor of a thousand while looking entirely plausible.  So the rate is
# recomputed HERE from whetstone's INTEGER line, using whetstone's own published
# formula, KIPS = 100 * LOOP * II / seconds.
run_whet() {
    if test ! -x "$WHET"; then
        echo "TEST fpu.whet status=skipped reason=no-whet-in-this-kit"
        return 0
    fi

    loop=$WHET_PILOT
    tries=0
    rate=0
    dur=0
    while test $tries -lt 8
    do
        out=`"$WHET" $loop </dev/null 2>&1`
        dur=`echo "$out" | sed -n 's/^Loops: *[0-9][0-9]*, Iterations: *[0-9][0-9]*, Duration: *\([0-9][0-9]*\) sec.*/\1/p'`
        if test -z "$dur"; then dur=0; fi
        if test "$dur" -ge $WHET_PILOT_MIN_SECS; then
            rate=`expr $loop / $dur`
            if test "$rate" -gt 0; then break; fi
        fi
        if test "$loop" -ge $WHET_MAX_LOOP; then break; fi
        loop=`expr $loop \* 4`
        if test "$loop" -gt $WHET_MAX_LOOP; then loop=$WHET_MAX_LOOP; fi
        tries=`expr $tries + 1`
    done
    if test "$rate" -le 0; then
        echo "TEST fpu.whet status=failed reason=could-not-calibrate loop=$loop"
        return 1
    fi

    # The prediction is honest: whetstone's work is exactly linear in LOOP.  A
    # sized run that would exceed the row's cap is REFUSED rather than started,
    # because once it is started nothing can stop it.
    loop=`expr $rate \* $WHET_TARGET_SECS`
    if test "$loop" -gt $WHET_MAX_LOOP; then loop=$WHET_MAX_LOOP; fi
    if test "$loop" -lt $WHET_PILOT; then loop=$WHET_PILOT; fi
    predict=`expr $loop / $rate`
    if test "$predict" -gt $WHET_MAX_SECONDS; then
        loop=`expr $rate \* $WHET_MAX_SECONDS`
        predict=$WHET_MAX_SECONDS
    fi

    out=`"$WHET" $loop </dev/null 2>&1`
    ii=`echo "$out" | sed -n 's/^Loops: *[0-9][0-9]*, Iterations: *\([0-9][0-9]*\), Duration: *[0-9][0-9]* sec.*/\1/p'`
    dur=`echo "$out" | sed -n 's/^Loops: *[0-9][0-9]*, Iterations: *[0-9][0-9]*, Duration: *\([0-9][0-9]*\) sec.*/\1/p'`
    if test -z "$ii"; then ii=0; fi
    if test -z "$dur"; then dur=0; fi
    if test "$dur" -le 0; then
        echo "TEST fpu.whet status=failed reason=no-duration loop=$loop predicted_secs=$predict"
        return 1
    fi
    # 100 * LOOP * II / seconds, whetstone's own formula.  Ordered to keep the
    # intermediate inside a 32-bit expr on the target.
    kips=`expr $loop / $dur \* 100 \* $ii`
    mwips_x100=`expr $kips / 10`
    wwarn=ok
    if test "$dur" -lt $WHET_MIN_SECS; then wwarn=coarse-clock; fi
    echo "TEST fpu.whet status=ok loops=$loop iterations=$ii duration_s=$dur kips=$kips mwips_x100=$mwips_x100 predicted_secs=$predict clock=time-1s-granularity warn=$wwarn"
    return 0
}

run_paranoia() {
    if test ! -x "$FPBENCH"; then
        echo "TEST fpu.paranoia status=skipped reason=no-fpbench-in-this-kit"
        return 0
    fi
    out=`"$FPBENCH" --test paranoia --max-seconds $FP_MAX_SECONDS --label fpu.paranoia </dev/null 2>&1`
    # The per-check detail is printed as well as the verdict.  A correctness row
    # that says only "FAIL" sends whoever reads it back to the machine; one that
    # says which check failed, with the wrong bits beside the right ones, does
    # not.  The host driver greps for "^TEST ", so these lines ride along into
    # the raw capture without disturbing it.
    echo "$out" | grep '^FPCHK '
    line=`echo "$out" | grep '^FPBENCH ' | tail -1`
    tool_test_line fpu.paranoia "$line"
    return $?
}

run_mem() {
    if test ! -x "$MEMBENCH"; then
        echo "TEST mem.bw status=skipped reason=no-membench-in-this-kit"
        return 0
    fi
    out=`"$MEMBENCH" --sizes $MEM_SIZES --bytes-per-size $MEM_BYTES_PER_SIZE \
         --max-seconds $MEM_MAX_SECONDS --label mem.bw </dev/null 2>&1`
    echo "$out" | grep '^MEMSWEEP '
    line=`echo "$out" | grep '^MEMBENCH ' | tail -1`
    tool_test_line mem.bw "$line"
    return $?
}

run_vm() {
    # $1 = row id, $2 = vmbench test name
    if test ! -x "$VMBENCH"; then
        echo "TEST $1 status=skipped reason=no-vmbench-in-this-kit"
        return 0
    fi
    case "$2" in
        fork)  vmargs="--ops $VM_FORK_OPS --exec-target $VMBENCH" ;;
        ctx)   vmargs="--ops $VM_CTX_OPS" ;;
        fault) vmargs="--ws $VM_WS_BYTES" ;;
        *)     echo "TEST $1 status=failed reason=unknown-vm-test"; return 1 ;;
    esac
    out=`"$VMBENCH" --test "$2" $vmargs --max-seconds $VM_MAX_SECONDS --label "$1" </dev/null 2>&1`
    line=`echo "$out" | grep '^VMBENCH ' | tail -1`
    tool_test_line "$1" "$line"
    return $?
}

# ------------------------------------------------------------------ drive ----
if test "$HEADER" = 1; then emit_header; fi
if test "$BODY" = 0; then exit 0; fi

# ★ EVERY BENCHMARK CHILD READS FROM /dev/null, NOT FROM THE MATRIX PIPE.
# The drive loop below is `matrix_rows | while read row`, so the loop body's
# stdin IS that pipe.  A benchmark that reads its own stdin -- even a single
# stdio buffer-fill -- would swallow the rows not yet read, and the matrix
# would stop early.  On 2026-09-16 the metal 68LC060 did exactly that: the
# fpu.dhry pilot ladder iterates hardest on a soft-FPU lane, a child there
# drained the pipe, and fpu.whet / fpu.paranoia / mem.bw / the vm rows never
# ran.  cpu.dhry was immune only because it is fed `echo $runs | dhry`.  So
# every child invocation in the run_* functions above takes `</dev/null`:
# none of them is meant to read stdin, and now none of them can reach the
# pipe.  (The host driver's per-row --only path never hit this -- there the
# loop runs a single row and exits.)
matrix_rows | while read row
do
    id=`field "$row" 1`
    pat=`field "$row" 2`
    dir=`field "$row" 3`
    bs=`field "$row" 4`
    if test -n "$ONLY"; then
        if test "$id" != "$ONLY"; then continue; fi
    fi
    case "$pat" in
        cpu) run_dhry ;;
        fpu)
            case "$id" in
                fpu.dhry)     run_fpdhry ;;
                fpu.whet)     run_whet ;;
                fpu.paranoia) run_paranoia ;;
                *) echo "TEST $id status=failed reason=unknown-fpu-row" ;;
            esac ;;
        mem) run_mem ;;
        vm)
            case "$id" in
                vm.fork)  run_vm vm.fork fork ;;
                vm.ctx)   run_vm vm.ctx ctx ;;
                vm.fault) run_vm vm.fault fault ;;
                *) echo "TEST $id status=failed reason=unknown-vm-row" ;;
            esac ;;
        *) run_disk "$id" "$pat" "$dir" "$bs" ;;
    esac
done

if test "$HEADER" = 1; then echo "=== END AMIX-BENCH RESULTS ==="; fi
exit 0
