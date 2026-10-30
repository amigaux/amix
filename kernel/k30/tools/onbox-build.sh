#!/bin/sh
# build.sh -- on-box driver for an amix-build bundle.  Runs ON the Amix box.
#
# This is the self-contained half of amix-build: the host assembled a bundle
# (generated amiga/alien sd.c + Makefile, the selected driver sources, the net
# driver's idempotent patch scripts, the clean-gate, checkunix.c) and a bundle.env
# manifest describing the selection.  Transfer the tar to the box, then:
#
#     cd /tmp && tar xf amix-kernel-<sel>.tar && sh amix-build/build.sh
#
# It integrates the drivers into /usr/sys, runs the D245 clean-gate, optionally
# installs, and reports.  Reuses the proven gate scripts + checkunix untouched.
# Pre-POSIX /bin/sh on AMIX 2.1: backticks (no $( )), no `local`, plain grep/test.
set -u

HERE=`dirname "$0"`
case "$HERE" in /*) ;; *) HERE=`pwd`/"$HERE" ;; esac
[ -f "$HERE/bundle.env" ] || { echo "FAILED: no bundle.env beside build.sh"; exit 2; }
. "$HERE/bundle.env"

SYS=/usr/sys
[ -d "$SYS/amiga/alien" ] || { echo "FAILED: $SYS/amiga/alien missing -- run this on the Amix box"; exit 2; }

echo "amix-build on-box: ${SEL:-?}"

# --- 1. SCSI integration: PATCH the builder's own stock sd.c + Makefile --------
# kerntools ships no Amix source: it patches your stock amiga/alien/sd.c (adds the
# scsicard[] rows + externs + sdcardbase()) and Makefile (OBJ list) in place, then
# drops in the driver sources.  Idempotent (re-runnable).
if [ "${HAS_SCSI:-0}" = 1 ]; then
	echo "  scsi: patch amiga/alien sd.c + Makefile, add driver sources"
	sh "$HERE/alien/patch-sd.sh"            "$SYS/amiga/alien/sd.c"     || exit 1
	sh "$HERE/alien/patch-scsi-makefile.sh" "$SYS/amiga/alien/Makefile" || exit 1
	for f in "$HERE"/alien/*.c; do
		if [ -f "$f" ]; then cp "$f" "$SYS/amiga/alien/`basename \"$f\"`" || exit 1; fi
	done
fi

# --- 2. NET integration: driver subtree + idempotent kernel.c / Makefile patch -
if [ -n "${NET_SUBDIR:-}" ]; then
	echo "  net: install amiga/driver/$NET_SUBDIR + patch kernel.c / driver Makefile"
	mkdir -p "$SYS/amiga/driver/$NET_SUBDIR"
	for f in "$HERE"/driver/"$NET_SUBDIR"/*; do
		if [ -f "$f" ]; then cp "$f" "$SYS/amiga/driver/$NET_SUBDIR/`basename \"$f\"`" || exit 1; fi
	done
	sh "$HERE/scripts/patch-kernel.sh"   || { echo "FAILED: patch-kernel.sh";   exit 1; }
	sh "$HERE/scripts/patch-makefile.sh" || { echo "FAILED: patch-makefile.sh"; exit 1; }
fi

# --- 2b. driver-supplied kernel patches (support.c, dd.c, ...) into stock tree -
# Each driver ships only the substantive shared-kernel-file edits kerntools can't
# generate, as unified diffs against stock Amix.  Apply them to the builder's own
# /usr/sys, then force the patched objects to recompile (Amix make has no dep
# tracking) so the gate links the patched code in.
if [ -n "${KPATCHES:-}" ]; then
	for p in $KPATCHES; do
		echo "  kpatch: $p"
		( cd "$SYS" && patch -p0 -N -s < "$HERE/$p" ) \
			|| { echo "FAILED: kernel patch $p did not apply (not a stock /usr/sys?)"; exit 1; }
	done
	for o in ${KPATCH_OBJS:-}; do
		rm -f "$SYS/$o"
		od=`dirname "$SYS/$o"`; rm -f "$od/exp"
	done
fi

# --- 3. clean-gate (relink under emulation until provably clean) --------------
if [ "${GATE:-1}" = 1 ]; then
	if [ -n "${NET_SUBDIR:-}" ]; then
		# net / combined kernel: the nm-u gate (has a /tmp checkunix fallback)
		if [ ! -x /root/checkunix ] && [ ! -x /tmp/checkunix ]; then
			( cd /tmp && cc -O -o /tmp/checkunix "$HERE/checkunix.c" ) \
				|| { echo "FAILED: could not build checkunix"; exit 2; }
		fi
		if [ -n "${ALIEN_OBJS:-}" ]; then
			echo "  gate: net+scsi  (nm-u, --alien \"$ALIEN_OBJS\" $NET_SUBDIR)"
			sh "$HERE/gate/build-clean-net-kernel.sh" --alien "$ALIEN_OBJS" $NET_SUBDIR || exit 1
		else
			echo "  gate: net  (nm-u, $NET_SUBDIR)"
			sh "$HERE/gate/build-clean-net-kernel.sh" $NET_SUBDIR || exit 1
		fi
	else
		# scsi-only kernel: the sum-recurrence gate (wants /root/checkunix)
		if [ ! -x /root/checkunix ]; then
			mkdir -p /root 2>/dev/null
			( cd /root && cc -O -o /root/checkunix "$HERE/checkunix.c" ) \
				|| { echo "FAILED: could not build /root/checkunix"; exit 2; }
		fi
		echo "  gate: scsi-only  (sum, ${SCSI_SRCLIST:-})"
		sh "$HERE/gate/build-clean-kernel.sh" ${SCSI_SRCLIST:-} || exit 1
	fi
fi

# --- 4. install ---------------------------------------------------------------
if [ "${INSTALL:-0}" = 1 ]; then
	echo "  install: make install + /stand make (bootpart)"
	( cd /usr/sys && make install ) || { echo "FAILED: make install"; exit 1; }
	( cd /stand   && make )         || { echo "FAILED: /stand make"; exit 1; }
	echo "INSTALLED -- new kernel staged (old kept as /stand/OLDunix). Reboot / power-cycle to boot it."
else
	echo "DONE -- clean relocunix in /usr/sys. Install: cd /usr/sys; make install; cd /stand; make"
fi
