# gcc14-env.sh -- TOOLCHAIN=gcc14: build a recipe with GCC 14 (gcc14-cross-amix).
#
# Sourced by amix-env.sh only, never by a recipe and never executed.  Owner
# decision D-3 sec 9 (2026-10-25): gcc14-cross-amix is the USERLAND compiler;
# kernel space stays on gcc-cross-amix.  Nothing built through this file is a
# kernel object.  The period toolchain stays the default (TOOLCHAIN unset).
#
# What changes against the period toolchain, and why (evaluation:
# Amix/tmp/2026-10-25-gcc14-eval/EVALUATION.md sec 5):
#
#   compiler   m68k-elf-gcc 14.2.0 + binutils 2.43.1, configured
#              --with-sysroot.  No fix_asm wrapper, no gcc.real, no
#              AMIX_MUL64: the six SGS-assembly repairs do not apply to gas.
#              The specs supply crt1/crti/crtbegin/amix_init, the
#              interpreter /usr/lib/libc.so.1, -Ttext-segment=0x80000000,
#              SysV hash, no RELRO, -malign-int, and
#              -L usr/ccs/lib -L usr/lib -lamixc99 -lc.
#   CPU        -m68020-60 (PHASE2, 2026-10-25): code for the 68020 through
#              the 68060, tuned for the 060.  GCC then never emits the 64-bit
#              MUL.L/DIV.L forms the 68060 removed, and its FPU code is the
#              68881 set.  NOT the toolchain's --with-cpu=68060 default:
#              -mcpu=68060 also emits the 040/060-only FPU forms (fdmove,
#              fdadd, fdmul, fddiv, ...), which a 68881/68882 lacks -- the
#              gcc14 make built that way died with SIGSYS on the 030 golden
#              row (68030 + 68882).  068060-only codegen is never the default;
#              amix_gate_g14_fpu refuses any such form in a payload, whatever
#              the flags.  It is HARD-FLOAT (__HAVE_68881__): any FP
#              instruction needs a 68881/2 or an 040/060 FPU, so a binary that
#              uses floating point does not run on an FPU-less part (68LC040,
#              68LC060) without the kernel's FPE.  The period compiler is
#              hard-float too (-m68020 also defines __HAVE_68881__); what each
#              package actually contains is counted at build time
#              (amix_gate_g14_fpu) and recorded, not assumed.
#   predefines the specs define only amix/__amix/__amix__.  The period
#              compiler's platform set is restored here, exactly:
#              unix __unix __unix__ __svr4__ AMIX __AMIX __AMIX__ m68k __m68k.
#              SVR4 is NOT defined: the period compiler never defined it, and
#              it changes code paths -- make 3.81's getloadavg.c takes the
#              nlist()/kmem load-average route under SVR4 (the NLIST-COMMON
#              trap, PORTING.md 3.3).  A recipe that wants it adds -DSVR4.
#              The predefines live in CC itself so that compiles, links and
#              autoconf's "$CC -E" preprocessor all see the same set.
#   headers    GCC 14's fixincludes rewrote AMIX's `(__STDC__ - 0 == 0)'
#              header gate to `!defined(__STRICT_ANSI__)' (sys/signal.h and
#              others, in include-fixed).  In a gnu17 compile the headers
#              therefore show their FULL view -- sigset_t, sigsetjmp, the
#              POSIX signal API -- which the period compiler (__STDC__ 1) never
#              saw without -D_POSIX_SOURCE; -std=c17 restores the strict view.
#              So configure answers can differ from the period build's: each
#              ported recipe's config.h is diffed against the period one and
#              every drift is pinned or accepted with a reason.
#   C dialect  gnu17.  An implicit function declaration is an ERROR (the
#              specs demote implicit-int only).  The AMIX headers declare
#              none of socket/connect/select/syslog/gethostname: a recipe
#              that calls them includes recipes/common/gcc14/amix-decls.h
#              (-include), it does not pass -Wno-error.
#   configure  autoconf probes of the era call functions they never declare
#              (less's terminal-library test calls tgetent() bare; AMIX has no
#              termcap.h), so under GCC 14 a probe fails on the DECLARATION
#              and configure reports a library missing that is there.  The
#              configure run alone gets AMIX_CONFIGURE_LENIENT, which demotes
#              exactly the GCC 14 errors gcc 2.7 never raised back to
#              warnings, so each probe is decided by the LINKER, as it was on
#              the period toolchain.  The build itself is strict: recipes pass
#              the strict CFLAGS again on the make line, and fail if a
#              -Wno-error reached make.log.  Proof that the probes answered as
#              before is a diff of config.h against the period build.
#   compat     ONE OWNER PER SYMBOL.  libamixc99, the toolchain's runtime,
#              is linked into every binary by the specs and owns snprintf,
#              vsnprintf, amix_snprintf, amix_vsnprintf, usleep, strcasecmp,
#              strncasecmp, strsignal, __cxa_atexit and __cxa_finalize; the
#              fixed headers declare them.  So SHIM-SNPRINTF, SHIM-STRCASECMP
#              and SHIM-USLEEP are the toolchain's under gcc14, and this
#              repo's libacompat (built by the period compiler) is NEVER
#              linked into a gcc14 build -- amix_gate_g14_compat fails a
#              build whose link line names it.  libacompat's
#              remaining members (setenv/unsetenv, mkstemp, its gettimeofday)
#              have no gcc14 owner yet: a recipe needing them is not
#              gcc14-ready.
#   64-bit     libc printf/fprintf/sprintf/vfprintf treat ll as l (the high
#   printf     word prints, every later argument is 4 bytes out of step);
#              only the compat snprintf/vsnprintf are right.  The gate
#              amix_gate_g14_llprintf fails a binary that imports a libc
#              printf-family function AND carries an ll/j/q/L integer
#              conversion, unless the recipe has reviewed it and says why in
#              AMIX_LL_PRINTF_REVIEWED.
#   68060 gate the D4 gate keeps three encoding scanners: the awk one,
#              gcc14-cross-amix/tools/check-68060-safe.py in place of the
#              period toolchain's scan060, and gcc14/scan060-g14.py, which
#              sizes GCC 14's switch tables from their bound checks;
#              amix-packagemanager's scan060.py still runs and every hit it
#              reports must be explained as table data (gates.sh,
#              amix_g14_scan3).  tools/gate-gcc14-selftest.sh proves the
#              gcc14 gates fail when they should.
#   FPU users  amix_gate_g14_fpu refuses the 040/060-only FPU forms and
#              counts the rest per binary.  The toolchain runtime was built
#              --with-cpu=68060, so libgcc (e.g. __floatundidf) and
#              libamixc99 (amix_vsnprintf) carry such forms until it is
#              rebuilt: a binary that links one of those members fails the
#              gate.  libamixc99's vsnprintf also saves %fp2 in its prologue,
#              so any binary that calls snprintf executes an FPU instruction
#              even for integer-only formats.
#   outputs    build/gcc14/<recipe>/ and build/gcc14/pkg/, so a gcc14 build
#              never overwrites a period artifact; the package revision is
#              the recipe's own (a new revision: different bytes).

case "${0##*/}" in
gcc14-env.sh)
	echo "[FAIL] gcc14-env.sh is sourced (by amix-env.sh), not executed" >&2
	exit 1
	;;
esac

AMIX_GCC14_ROOT="${AMIX_GCC14_ROOT:-$AMIX_SIBLINGS/gcc14-cross-amix}"
AMIX_GCC14_PREFIX="${AMIX_GCC14_PREFIX:-$AMIX_GCC14_ROOT/build/prefix}"
TARGET=m68k-elf
_g14_bin="$AMIX_GCC14_PREFIX/bin"
AMIX_GCC14_CC="$_g14_bin/$TARGET-gcc"
AMIX_GCC14_CXX="$_g14_bin/$TARGET-g++"

[ -x "$AMIX_GCC14_CC" ] || {
	echo "[FAIL] TOOLCHAIN=gcc14: $AMIX_GCC14_CC not found" >&2
	echo "       Build ../gcc14-cross-amix (toolchain/build-cross.sh) or set AMIX_GCC14_PREFIX." >&2
	exit 1
}

# The sysroot is the one the compiler was configured with -- asked, not
# assumed, so the headers configure reads are the ones the compiler uses.
AMIX_SYSROOT=$("$AMIX_GCC14_CC" -print-sysroot 2>/dev/null)
[ -n "$AMIX_SYSROOT" ] && [ -d "$AMIX_SYSROOT/usr/include" ] || {
	echo "[FAIL] TOOLCHAIN=gcc14: the compiler's sysroot '$AMIX_SYSROOT' has no usr/include" >&2
	exit 1
}
# GCC's own stdint.h does #include_next of the C library's; AMIX has none, so
# the sysroot must carry compat/include/stdint.h (evaluation deviation 1).
[ -f "$AMIX_SYSROOT/usr/include/stdint.h" ] || {
	echo "[FAIL] TOOLCHAIN=gcc14: $AMIX_SYSROOT/usr/include/stdint.h missing" >&2
	echo "       (gcc14-cross-amix tools/sync-sysroot.sh installs it)" >&2
	exit 1
}
for _g14_o in crt1.o crti.o crtn.o; do
	[ -f "$AMIX_SYSROOT/usr/ccs/lib/$_g14_o" ] || {
		echo "[FAIL] TOOLCHAIN=gcc14: $AMIX_SYSROOT/usr/ccs/lib/$_g14_o missing" >&2
		exit 1
	}
done
[ -f "$("$AMIX_GCC14_CC" -print-file-name=libamixc99.a)" ] || {
	echo "[FAIL] TOOLCHAIN=gcc14: libamixc99.a not installed in the toolchain" >&2
	exit 1
}

AMIX_CHECK060="${AMIX_CHECK060:-$AMIX_GCC14_ROOT/tools/check-68060-safe.py}"
[ -f "$AMIX_CHECK060" ] || {
	echo "[FAIL] TOOLCHAIN=gcc14: $AMIX_CHECK060 not found" >&2
	exit 1
}

AMIX_PREDEFS="${AMIX_PREDEFS:--Dunix -D__unix -D__unix__ -D__svr4__ -DAMIX -D__AMIX -D__AMIX__ -Dm68k -D__m68k}"

export CC="$AMIX_GCC14_CC $AMIX_PREDEFS"
export CXX="$AMIX_GCC14_CXX $AMIX_PREDEFS"
export AR="$_g14_bin/$TARGET-ar"
export RANLIB="$_g14_bin/$TARGET-ranlib"
export LD="$_g14_bin/$TARGET-ld"
export NM="$_g14_bin/$TARGET-nm"
export OBJDUMP="$_g14_bin/$TARGET-objdump"
export STRIP="$_g14_bin/$TARGET-strip"
export READELF="$_g14_bin/$TARGET-readelf"
export AMIX_TARGET="$TARGET"
export AMIX_SYSROOT AMIX_CHECK060 AMIX_PREDEFS AMIX_GCC14_CC AMIX_GCC14_ROOT
# autoconf's CPP: the compiler itself preprocesses correctly here, with the
# same predefines and the same sysroot headers (no host /lib/cpp fallback).
export AMIX_CPP="$CC -E"

# -m68020-60: see the header.  -O2 per the evaluation (-Os where a hot loop
# must fit the 060's 8 KB I-cache).  Never -mno-align-int or
# -fpcc-struct-return (ABI).
AMIX_ARCH_FLAGS="${AMIX_ARCH_FLAGS:--m68020-60}"
AMIX_CFLAGS="${AMIX_CFLAGS:-$AMIX_ARCH_FLAGS -O2 -Wall}"
export AMIX_ARCH_FLAGS AMIX_CFLAGS

# configure only (see the header); never on a make line.
export AMIX_CONFIGURE_LENIENT="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-error=return-mismatch"

# Declarations the AMIX headers lack (socket/select/syslog/gethostname):
# opt-in per recipe with -include "$AMIX_GCC14_DECLS".
export AMIX_GCC14_DECLS="$AMIX_REPO_ROOT/recipes/common/gcc14/amix-decls.h"

export AMIX_BUILD_ROOT="$AMIX_REPO_ROOT/build/gcc14"
unset _g14_bin _g14_o
