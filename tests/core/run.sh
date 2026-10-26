#!/bin/sh
# run.sh -- M-CORE1 (docs/spec/90-measurements.md): the adopted module
# core's own host tests, built with this repository's toolchains and run
# against our kernels.  The core is core/upstream/, kdedon's MIT DLM core
# at the commit in core/upstream.pin, unmodified, with core/series applied
# to a staged copy; this runner does what its
# build.sh and test/run.sh do, except the two A/UX objects (they need
# upstream's coff2elf and an A/UX tree), and calls its tools and helper
# scripts as they are:
#
#  1. host tools: mkksym, modfix, and the host builds of the loader (reloc)
#     and of the core against simulated kernel services (state);
#  2. the kernel objects (dlm.o) with gcc-cross-amix and AMIX_KERNEL_CFLAGS,
#     no warnings beyond the stock headers' own; the names dlm.o needs that
#     the kernel lacks are listed (a kernel without the core lacks some);
#  3. the user side: libmod.a and modadmin;
#  4. per kernel: the symbol block, the modules (mkmod: dlmdep, dlmtest,
#     dlmtest2 at -O2 -m68040, rall with every relocation type), the
#     relocation oracle (each module relocated by the host loader must be
#     byte-identical to m68k-elf-ld linking it at the same base), the
#     error paths, and the state harness;
#  5. per kernel, the allowlisted block (C3-2, core patch 0005): mkksym -a
#     from the line's abi/ lists, linked into the kernel with stubs for the
#     names whose providers come later (listed), mkksym -f, the post-link
#     gate (tools/ksymgate.py: bound twice by the loader's relocator), and
#     modules resolved against that block as the loader leaves it: the
#     test modules load, a module using a name off the list is ERELOC, and
#     a listed name left undefined fails -f.
#
# usage: sh tests/core/run.sh [KERNEL.elf ...]
#   default: the k46 and k30 kernels of record (amix-kerntools k0-chains)
# Environment: GCA (gcc-cross-amix build dir), G14 (gcc14-cross-amix build
# dir, for the modern m68k-elf binutils the oracle links with), B.
# One PASS/FAIL line per check; exit 1 if any failed.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.  The checks
# follow core/upstream/test/run.sh (MIT, Copyright (c) 2026 kdedon).
set -e

R=$(cd "$(dirname "$0")/../.." && pwd)
U=$R/core/upstream
WS=$(cd "$R/.." && pwd)
GCA=${GCA:-$WS/gcc-cross-amix/build}
G14=${G14:-$WS/gcc14-cross-amix/build}
B=$(mkdir -p "${B:-$R/build}/core" && cd "${B:-$R/build}/core" && pwd)
. "$GCA/env.sh"
PATH="$G14/prefix/bin:$PATH"
export PATH
[ $# -gt 0 ] || set -- "$WS/amix-kerntools/work/k0-chains/KD060-Z/KD060-Z-c0-u6" \
	"$WS/amix-kerntools/work/k0-chains/K030-U/K030-U-c0-u6.etrel"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

# upstream's mkmod sources <tree>/toolchain/src/gcc-cross-amix/build/env.sh
# relative to itself: a staged copy of the core with that path pointing here
S=$B/stage
rm -rf "$S"
mkdir -p "$S/kernel" "$S/toolchain/src/gcc-cross-amix/build"
cp -R "$U" "$S/kernel/dlm"
# the queue (core/series) on the copy: the tests are of the core as shipped
while read p; do
	case "$p" in \#*|"") continue ;; esac
	patch -p1 -s -d "$S/kernel/dlm" < "$R/core/patches/$p" || { echo "FAIL patch $p"; exit 1; }
done < "$R/core/series"
printf '. "%s/env.sh"\nPATH="%s/prefix/bin:$PATH"\nexport PATH\n' "$GCA" "$G14" \
	> "$S/toolchain/src/gcc-cross-amix/build/env.sh"
DLM=$S/kernel/dlm
T=$DLM/test
TB=$B/tools
mkdir -p "$TB" "$B/test-bin" "$B/obj" "$B/target"
${HOSTCC:-cc} -O2 -I"$R/loader/common" -o "$B/test-bin/axrel" "$R/tests/host/axrel.c" \
	"$R/loader/common/rel.c"

# ---- 1. host tools ----
HCC="${HOSTCC:-cc} -std=gnu89 -O -g -Wall -Wno-parentheses -Wno-unused-but-set-variable"
if $HCC -DDLM_TOOL -I"$DLM" -I"$DLM/include" -o "$TB/mkksym" "$DLM/tools/mkksym.c" "$DLM/dlm_sym.c" &&
   $HCC -o "$TB/modfix" "$DLM/tools/modfix.c" &&
   $HCC -DDLM_HOST -I"$DLM" -I"$DLM/include" -o "$B/test-bin/reloc" \
	"$T/reloc.c" "$DLM/dlm_ld.c" "$DLM/dlm_sym.c" &&
   $HCC -DDLM_HOST -I"$DLM" -I"$DLM/include" -o "$B/test-bin/state" \
	"$T/state.c" "$T/hostk.c" "$DLM/dlm_core.c" "$DLM/dlm_ld.c" "$DLM/dlm_sym.c" \
	"$DLM/dlm_slot.c" "$T/hconf.c" > "$B/tools.log" 2>&1; then
	pass "host tools (mkksym, modfix, reloc, state)"
else
	fail "host tools"; cat "$B/tools.log"; exit 1
fi

# ---- 2. kernel objects ----
PIN=gcc-2.7.2.3-8949028	# toolchain.pin
KCC="m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS -Wall -I$DLM/include -I$DLM -DDLM_KABI=\"k46.1.0\" -DDLM_PIN=\"$PIN\""
rm -f "$B/kobj.warn"
for f in dlm_core dlm_ld dlm_sym dlm_slot dlm_str dlmconf; do
	$KCC -c "$DLM/$f.c" -o "$B/obj/$f.o" 2>> "$B/kobj.warn"
done
for f in dlm_cache dlmksym dlm_hooksw; do
	m68k-cbm-sysv4-gcc -c "$DLM/$f.s" -o "$B/obj/$f.o"
done
m68k-cbm-sysv4-ld -r -o "$B/obj/dlm.o" $(for f in dlm_core dlm_ld dlm_sym dlm_slot dlm_str \
	dlmconf dlm_cache dlmksym dlm_hooksw; do echo "$B/obj/$f.o"; done)
if grep -v 'types.h:182\|In file included\|^ *from ' "$B/kobj.warn" | grep . > "$B/kobj.other"; then
	fail "kernel objects: warnings beyond the stock headers'"; cat "$B/kobj.other"
else
	pass "kernel objects: dlm.o $(m68k-elf-size "$B/obj/dlm.o" | awk 'NR==2{print $1 "+" $2 "+" $3}') text+data+bss, no warnings of its own"
fi
m68k-elf-nm -u "$B/obj/dlm.o" | awk '$1=="U"{print $2}' | sort -u > "$B/obj/dlm.undef"

# ---- 3. the user side ----
if for f in modload moduload modpath modstat modadm getksym; do
	m68k-cbm-sysv4-as -o "$B/target/$f.o" "$DLM/libmod/$f.s" || exit 1; done &&
   rm -f "$B/target/libmod.a" &&
   m68k-elf-ar rcs "$B/target/libmod.a" "$B/target"/mod*.o "$B/target/getksym.o" &&
   m68k-cbm-sysv4-gcc -O -I"$DLM/include" -o "$B/target/modadmin" "$DLM/modadmin.c" \
	"$B/target/libmod.a" > "$B/target.log" 2>&1 &&
   m68k-elf-readelf -h "$B/target/modadmin" | grep -q EXEC; then
	pass "user side: libmod.a, modadmin"
else
	fail "user side"; cat "$B/target.log"
fi

# ---- 4. per kernel ----
for IMG; do
	K=$(basename "$IMG")
	W=$B/test/$K
	case "$K" in K030*|*k30*) KABI=k30.1.0 LINE=k30 ;; *) KABI=k46.1.0 LINE=k46 ;; esac
	ORIG=$IMG
	export DLM_KABI=$KABI DLM_PIN=$PIN	# mkmod's -K and -P
	rm -rf "$W"
	mkdir -p "$W"
	echo "== $K"
	# an ET_REL kernel (as shipped) defines stext but not etext/edata/end,
	# which the loader makes when it binds it: bind it here at 0x08000000,
	# where boot2 places the kernel on the Z3660 rows (upstream's tests ran
	# on a linked image too)
	if [ "$(od -An -tx1 -j16 -N2 "$IMG" | tr -d ' ')" = 0001 ]; then
		m68k-elf-ld -N -Ttext=0x08000000 -e 0x08000000 --no-warn-rwx-segments \
			-o "$W/kernel.elf" "$IMG"
		IMG=$W/kernel.elf
	fi
	m68k-elf-nm "$IMG" | awk '{print $NF}' | sort -u > "$W/kernel.names"
	miss=$(grep -vxFf "$W/kernel.names" "$B/obj/dlm.undef" | grep -v '^__amix_' | tr '\n' ' ')
	echo "names dlm.o needs that $K lacks (the core's splice provides or aliases them): ${miss:-none}"

	if "$TB/mkksym" -o "$W/ksym.bin" "$IMG" 2> "$W/ksym.chk"; then
		pass "$K: symbol block built ($(cat "$W/ksym.chk"))"
	else
		fail "$K: mkksym -o: $(cat "$W/ksym.chk")"; continue
	fi
	"$TB/mkksym" -x "$IMG" > "$W/exports"
	symdefs() { awk '{printf " --defsym=%s=%s", $1, $2}' "$1"; }
	# a kernel without the core: its module API at fake addresses, as upstream
	m68k-elf-nm "$B/obj/dlm.o" | awk '$2 ~ /^[TDB]$/ && $3 ~ /^mod_/ {print $3}' |
		awk '{printf "%s 0x%x\n", $1, 0x00d00000 + 16 * NR}' > "$W/dlmk.sym"
	awk '{print $1}' "$W/dlmk.sym" >> "$W/exports"
	KX="-S $W/dlmk.sym"
	KLD=$(symdefs "$W/dlmk.sym")

	CC="m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS -I$DLM/include"
	M=$W/mods
	SRC=$W/src
	mkdir -p "$M" "$SRC"
	mkmod() {
		d=$1; shift
		if DLM_TOOLS="$TB" sh "$DLM/tools/mkmod" "$@" -o "$M" "$d" > "$W/mkmod.log" 2>&1; then
			pass "$K: mkmod $(basename "$d")"
		else
			fail "$K: mkmod $(basename "$d")"; cat "$W/mkmod.log"
		fi
	}
	for m in dlmdep dlmtest dlmtest2 rall; do
		mkdir -p "$SRC/$m"
		cp "$T/mod/$m/"* "$SRC/$m/" 2>/dev/null || true
	done
	$CC -c "$T/mod/dlmdep/dlmdep.c" -o "$SRC/dlmdep/Driver.o"
	$CC -c "$T/mod/dlmtest/dlmtest.c" -o "$SRC/dlmtest/Driver.o"
	$CC -O2 -m68040 -c "$T/mod/dlmtest/dlmtest.c" -o "$SRC/dlmtest2/Driver.o"
	m68k-cbm-sysv4-as -o "$SRC/rall/Driver.o" "$T/mod/rall/rall.s"
	mkmod "$SRC/dlmdep" -e "$W/exports"
	mkmod "$SRC/dlmtest" -e "$W/exports" -d "$M/mod.d/dlmdep"
	mkmod "$SRC/dlmtest2" -e "$W/exports"
	printf 'abs16 0x1234\nabsneg 0xfffffff0\nabs8 0x7f\nabs8u 0xff\nabsm8 0xffffff80\n' > "$W/rall.sym"
	awk '{print $1}' "$W/rall.sym" | cat "$W/exports" - > "$W/rall.exports"
	mkmod "$SRC/rall" -e "$W/rall.exports"

	O=$W/oracle
	mkdir -p "$O"
	oracle() {	# oracle module base [reloc args] -- ld args
		mod=$1 base=$2; shift 2
		ra="$KX" la=
		while [ $# -gt 0 ] && [ "$1" != -- ]; do ra="$ra $1"; shift; done
		[ $# -gt 0 ] && shift
		la="$* $KLD"
		f="$M/mod.d/$mod"
		tag="$mod@$base"
		if ! "$B/test-bin/reloc" -k "$W/ksym.bin" $ra -L "$O/$tag.lay" -b "$base" "$f" > "$O/$tag.log" 2>&1; then
			fail "$K: oracle $tag: loader: $(cat "$O/$tag.log")"; return
		fi
		python3 "$T/oracle.py" script "$f" "$O/$tag.lay" > "$O/$tag.ld"
		m68k-elf-nm "$f" | awk '$2 ~ /^[TDBRAVW]$/ {print $3}' | sort -u > "$O/$tag.own"
		m68k-elf-nm "$IMG" | awk '$2 ~ /^[TDBRAVW]$/ {print $3, $1}' |
			awk 'NR==FNR {own[$1]=1; next} !($1 in own) {printf "\"%s\" = 0x%s;\n", $1, $2}' \
			"$O/$tag.own" - > "$O/$tag.ksyms"
		if ! m68k-elf-ld -e 0 -o "$O/$tag.out" -T "$O/$tag.ld" $la "$f" "$O/$tag.ksyms" > "$O/$tag.ldlog" 2>&1; then
			fail "$K: oracle $tag: m68k-elf-ld: $(head -3 "$O/$tag.ldlog")"; return
		fi
		python3 "$T/oracle.py" commons "$f" "$O/$tag.out" > "$O/$tag.com"
		"$B/test-bin/reloc" -k "$W/ksym.bin" $ra -C "$O/$tag.com" -L "$O/$tag.lay" \
			-o "$O/$tag.img" -b "$base" "$f" > "$O/$tag.log" 2>&1
		nrel=$(m68k-elf-readelf -rW "$f" | grep -c 'R_68K' || true)
		if python3 "$T/oracle.py" compare "$f" "$O/$tag.lay" "$O/$tag.out" "$O/$tag.img" > "$O/$tag.cmp"; then
			pass "$K: oracle $tag: $(wc -c < "$O/$tag.img") bytes identical, $nrel relocations"
		else
			fail "$K: oracle $tag: $(cat "$O/$tag.cmp")"
		fi
	}
	oracle dlmdep 0x00380000
	oracle dlmtest 0x00300000 -D "$M/mod.d/dlmdep@0x00380000" -- --just-symbols="$O/dlmdep@0x00380000.out"
	oracle dlmtest 0x0a123450 -D "$M/mod.d/dlmdep@0x00380000" -- --just-symbols="$O/dlmdep@0x00380000.out"
	oracle dlmtest2 0x00300000 -D "$M/mod.d/dlmdep@0x00380000" -- --just-symbols="$O/dlmdep@0x00380000.out"
	oracle rall 0x00300000 -S "$W/rall.sym" -- $(symdefs "$W/rall.sym")
	oracle rall 0x7ff00000 -S "$W/rall.sym" -- $(symdefs "$W/rall.sym")

	N=$W/neg
	mkdir -p "$N"
	python3 "$T/mkneg.py" "$M/mod.d/rall" "$N" > "$N/list"
	asmneg() {	# asmneg name errno what source
		printf '%s\n\t.data\n\t.globl\t%s_wrapper\n%s_wrapper:\n\t.long\t2,0,0,0,0,0\n' "$4" "$1" "$1" > "$N/$1.s"
		printf '\t.section .moddata,"aw",@progbits\n\t.balign\t4\n\t.long\t%s_wrapper\n' "$1" >> "$N/$1.s"
		printf '\t.byte\t0x4d, 0x44, 0x32, 0\n\t.asciz\t"name=%s"\n\t.asciz\t"kabi=%s"\n\t.asciz\t"cc=%s"\n\t.asciz\t"cpu=68020"\n\t.asciz\t"class=demand"\n\t.byte\t0\n' \
			"$1" "$KABI" "$PIN" >> "$N/$1.s"
		m68k-cbm-sysv4-as -o "$N/$1.o" "$N/$1.s"
		m68k-cbm-sysv4-ld -r -o "$N/$1" "$N/$1.o"
		"$TB/modfix" -p "$1" -m "$1" "$N/$1"
		echo "$N/$1 $2 $3" >> "$N/list"
	}
	asmneg pc16ovf 165 'R_68K_PC16 out of range' '	.text
	bsr.w	printf'
	asmneg pc8ovf 165 'R_68K_PC8 out of range' '	.text
	bsr.b	printf
	nop'
	asmneg r16ovf 165 'R_68K_16 out of range' '	.data
	.word	printf'
	asmneg r8ovf 165 'R_68K_8 out of range' '	.data
	.byte	abs16'
	asmneg undef 165 'undefined symbol' '	.text
	jsr	no_such_symbol'
	while read f want what; do
		got=$("$B/test-bin/reloc" -k "$W/ksym.bin" $KX -S "$W/rall.sym" -b 0x300000 "$f" 2>/dev/null |
			awk '/^ERR/{print $2} /^OK/{print 0}')
		if [ "$got" = "$want" ]; then pass "$K: error path: $what -> $want"
		else fail "$K: error path: $what: got '$got' want $want"; fi
	done < "$N/list"
	cp "$N/relnone" "$M/mod.d/relnone"
	oracle relnone 0x00300000 -S "$W/rall.sym" -- $(symdefs "$W/rall.sym")

	RT=$W/root/etc/conf/mod.d
	mkdir -p "$RT"
	python3 "$T/mkmods.py" "$W/hmods" > "$W/hmods.list"
	while read n s f; do	# f: modfix flags (-1 for the version-1 refusal case)
		m68k-cbm-sysv4-as -o "$W/hmods/$n.o" "$s"
		m68k-cbm-sysv4-ld -r -o "$RT/$n" "$W/hmods/$n.o"
		"$TB/modfix" $f -p "$n" -m "$n" "$RT/$n"
	done < "$W/hmods.list"
	if "$B/test-bin/state" "$W/ksym.bin" "$W/root" > "$W/state.log" 2>&1; then
		pass "$K: state harness: $(tail -1 "$W/state.log")"
	else
		sed 's/^/state: /' "$W/state.log" | grep -v '^state: PASS'
		fail "$K: state harness"
	fi

	# ---- 5. the allowlisted block ----
	A=$W/allow
	mkdir -p "$A"
	L="$R/abi/$LINE/ddi.list"
	LC="$R/abi/$LINE/core.list"
	if "$TB/mkksym" -a "$L" -a "$LC" > "$A/ksym.s" 2> "$A/ksym.log" &&
	   m68k-cbm-sysv4-as -o "$A/ksym.o" "$A/ksym.s"; then
		pass "$K: allowlisted block generated and assembled ($(sed 's/^mkksym: //' "$A/ksym.log"))"
	else
		fail "$K: mkksym -a: $(cat "$A/ksym.log")"; continue
	fi
	# the providers that come with later core patches, or dlm.o itself: stubbed
	m68k-elf-nm "$ORIG" | awk 'NF==3 && $2 ~ /[A-Z]/ {print $3}' | sort -u > "$A/defined"
	awk '!/^#/ && NF {print $1, $2}' "$L" | while read n k; do
		grep -qx "$n" "$A/defined" || echo "$n $k"; done > "$A/stubbed"
	awk '$2=="func" {printf "\t.text\n\t.globl\t%s\n%s:\n\trts\n", $1, $1}
	     $2=="data" {printf "\t.data\n\t.globl\t%s\n%s:\n\t.long\t0\n", $1, $1}' \
		"$A/stubbed" > "$A/stubs.s"
	m68k-cbm-sysv4-as -o "$A/stubs.o" "$A/stubs.s"
	echo "$K: providers to come (stubbed for the gate): $(awk '{printf "%s ", $1}' "$A/stubbed")"
	m68k-cbm-sysv4-ld -r -o "$A/kernel.o" "$ORIG" "$A/ksym.o" "$A/stubs.o"
	if "$TB/mkksym" -f "$A/kernel.o" > "$A/fill.log" 2>&1; then
		pass "$K: mkksym -f: $(sed 's#.*: ##' "$A/fill.log")"
	else
		fail "$K: mkksym -f: $(cat "$A/fill.log")"
	fi
	if python3 "$R/tools/ksymgate.py" "$B/test-bin/axrel" "$A/kernel.o" "$L" "$LC" > "$A/gate.log" 2>&1; then
		pass "$K: post-link gate: $(grep -c '^PASS' "$A/gate.log") checks, bound at 0x00200000 and 0x07f00000"
	else
		grep '^FAIL' "$A/gate.log"; fail "$K: post-link gate"
	fi
	# the gate itself fails on a block that does not match the lists
	printf 'no_such_name func 0\n' > "$A/extra.list"
	if ! python3 "$R/tools/ksymgate.py" "$B/test-bin/axrel" "$A/kernel.o" "$L" "$A/extra.list" \
		> "$A/gate-neg.log" 2>&1 && grep -q '^FAIL.*exactly the' "$A/gate-neg.log"; then
		pass "$K: post-link gate fails when the lists name what the block lacks"
	else
		fail "$K: post-link gate passed a block that does not match the lists"
	fi
	# a listed name left undefined (the last stub dropped): -f refuses it
	head -n -4 "$A/stubs.s" > "$A/stubs-short.s"
	m68k-cbm-sysv4-as -o "$A/stubs-short.o" "$A/stubs-short.s"
	m68k-cbm-sysv4-ld -r -o "$A/kernel-short.o" "$ORIG" "$A/ksym.o" "$A/stubs-short.o"
	if ! "$TB/mkksym" -f "$A/kernel-short.o" > "$A/short.log" 2>&1 &&
	   grep -q "listed but not defined" "$A/short.log"; then
		pass "$K: a listed name left undefined: $(grep -o '[^ ]* is listed but not defined' "$A/short.log" | head -1), refused"
	else
		fail "$K: mkksym -f accepted a missing name"
	fi
	# modules against the block as the loader leaves it at 0x08000000
	python3 "$R/tools/ksymgate.py" --extract "$B/test-bin/axrel" "$A/kernel.o" 0x08000000 "$A/ksym.bin"
	for m in dlmdep dlmtest rall; do
		case $m in
		dlmdep) ra= want=0 ;;
		dlmtest) ra="-D $M/mod.d/dlmdep@0x00380000" want=0 ;;
		rall) ra="-S $W/rall.sym" want=165 ;;	# it uses u, which is off the list
		esac
		got=$("$B/test-bin/reloc" -k "$A/ksym.bin" $ra -b 0x300000 "$M/mod.d/$m" 2>&1 |
			awk '/^ERR/{print $2} /^OK/{print 0}')
		if [ "$got" = "$want" ]; then pass "$K: $m against the allowlisted block -> $want"
		else fail "$K: $m against the allowlisted block: got '$got' want $want"; fi
	done
done

echo "core: $fails failed"
[ $fails -eq 0 ]
