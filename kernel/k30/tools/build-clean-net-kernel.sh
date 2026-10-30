#!/bin/sh
# build-clean-net-kernel.sh <driver-subdir> [<driver-subdir>...]   (runs ON the box; pre-POSIX sh, plain grep)
#
# Net-driver D245 clean-gate for a STREAMS driver living in amiga/driver/<dir>/.
#
# ★ THE BAR IS `nm -u`, NOT sum-recurrence (learned the hard way 2026-06-21).
# `relocunix` is just `ln unix relocunix`, gated by the kernel Makefile's OWN test:
#   nm -h -u unix | egrep -v '(etext|edata|end)'   must be EMPTY (no undefined syms).
# So this gate relinks `unix` until it is BOTH:
#   (a) nm-clean  -- no undefined symbols (catches dropped definitions), AND
#   (b) checkunix-clean -- symtab st_shndx intact (catches the D245 symtab shift);
# then `ln unix relocunix`.  (A recurring `sum -r` among clean builds is the gold
# confirmation but is NOT required -- it does not converge on this larger kernel.)
# The OLD sum-recurrence gate was the WRONG bar: it never converged AND a unix can
# pass checkunix while still having undefined symbols (so the Makefile rejects it).
#
# Never deletes the 22 generic SVR4 subsystem exp blobs (os, io, netinet, rpc, vm,
# des, disp, exec, klm, ktli, top-level ml, fs/<bfs..xnamfs>) -- they ship PRE-LINKED
# with NO source on the box and are NOT regenerable.  Only the AMIGA tree + master.d
# + fs/exp(aggregate) + local/exp are re-rolled.
#
# Args: on-box driver subdir name(s) under /usr/sys/amiga/driver, e.g.:
#       sh /tmp/build-clean-net-kernel.sh z3660eth
#   --alien "<obj ...>"  (optional, FIRST arg): for a COMBINED SCSI+net kernel,
#       force the alien SCSI drivers (sd.o + the new driver .o, e.g.
#       "sd.o a4091.o z3660.o") to recompile so the new amiga/alien/sd.c
#       scsicard[] actually links in -- AMIX make's dep-tracking is unreliable
#       (a4091 NOTES s3a).  Omitted -> net-only behaviour, unchanged.
# exit 0 = clean relocunix ready; 1 = could not stabilise / real build error.
set -u
ALIEN_OBJS=""
if [ "${1:-}" = --alien ]; then
	if [ $# -lt 3 ]; then echo "usage: $0 [--alien \"<objs>\"] <driver-subdir>..."; exit 2; fi
	ALIEN_OBJS="$2"; shift; shift
fi
if [ $# -eq 0 ]; then echo "usage: $0 [--alien \"<objs>\"] <driver-subdir>..."; exit 2; fi
DIRS="$*"
MV="KERNEL=unix PLATFORM=amiga MACHINE=reloc CC=cc  CONFIGFILE=/stand/CONFIG"

# checkunix is required (the symtab D245 bar).  /root may not exist on a fresh
# clean image (root home = /), so fall back to /tmp -- and FAIL FAST if absent
# rather than silently treating every build as corrupt and grinding to the cap.
CHK=/root/checkunix
[ -x "$CHK" ] || CHK=/tmp/checkunix
if [ ! -x "$CHK" ]; then
	echo "FAILED: checkunix not found (/root/checkunix or /tmp/checkunix)."
	echo "        compile it on the box:  cc -O -o /tmp/checkunix checkunix.c"
	exit 2
fi

cd /usr/sys || exit 2
rm -f master.d/kernel.o        # force the edited kernel.c to recompile once
# combined SCSI+net: force the new alien sources (sd.c + driver .c) to recompile
# ONCE so the new scsicard[] links in; alien/exp is then re-linked every round.
if [ -n "$ALIEN_OBJS" ]; then ( cd amiga/alien && rm -f exp $ALIEN_OBJS ); fi

# regenerable final-stage products re-rolled EVERY iteration (cheap; never generic)
reroll() {
	rm -f relocunix unix OLDrelocunix amiga/config/unix.o \
	      amiga/exp amiga/driver/exp master.d/exp fs/exp local/exp
	for d in $DIRS; do rm -f "amiga/driver/$d/exp"; done
	# combined SCSI+net: re-link the alien aggregate each round too (fresh ld -r)
	[ -n "$ALIEN_OBJS" ] && rm -f amiga/alien/exp
}
# cached AMIGA sub-exps -- only blown away when "file type unknown" says one is corrupt
reroll_amiga_subs() {
	rm -f amiga/console/exp amiga/ml/exp amiga/kernel/exp \
	      amiga/floppy/exp amiga/alien/exp amiga/driver/aen/exp
}

n=1
while [ $n -le 150 ]; do
	reroll
	make unix $MV > /tmp/bcnk_build.log 2>&1
	if [ ! -f unix ]; then
		# both ld "Unresolved Symbol(s)!" and the lowercase nm-check "unresolved
		# symbols" are retryable D245 corruption, not real build errors.
		if grep -i unresolved /tmp/bcnk_build.log > /dev/null 2>&1; then
			echo "build $n: unresolved (no unix) -- retry"; n=`expr $n + 1`; continue
		fi
		if grep "file type unknown" /tmp/bcnk_build.log > /dev/null 2>&1; then
			echo "build $n: cached amiga sub-exp corrupt (file type unknown) -- regen + retry"
			reroll_amiga_subs; n=`expr $n + 1`; continue
		fi
		tail -20 /tmp/bcnk_build.log
		echo "FAILED: make produced no unix (real build error)"
		exit 1
	fi
	s=`sum -r unix 2>/dev/null | awk '{print $1}'`
	cku=corrupt
	"$CHK" unix > /tmp/bcnk_chk.log 2>&1 && cku=clean
	# Run nm ONLY when checkunix is already clean.  The bar is checkunix-clean
	# AND undef=0, so a checkunix-corrupt build is rejected regardless of nm --
	# and `nm -h -u unix` on this large kernel is the step that trips the WinUAE
	# EMU mmu030 bus-error bug.  Skipping nm on the ~80% corrupt builds cuts that
	# crash exposure ~5x.  undef defaults to 1 (= "assume not clean") when skipped.
	undef=1
	if [ "$cku" = clean ]; then
		undef=`nm -h -u unix 2>/dev/null | egrep -v '(etext|edata|end)' | wc -l`
		undef=`echo $undef`
	fi
	echo "build $n: checkunix=$cku undef=$undef sum=$s"
	if [ "$cku" = clean ] && [ "$undef" -eq 0 ]; then
		rm -f relocunix; ln unix relocunix
		echo "STABLE after $n builds: clean relocunix (undef=0 checkunix-clean sum=$s)"
		exit 0
	fi
	n=`expr $n + 1`
done
echo "FAILED: no nm-clean + checkunix-clean unix in 150 builds"
exit 1
