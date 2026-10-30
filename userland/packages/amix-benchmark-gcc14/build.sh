# build.sh -- amix-benchmark-gcc14 hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is a copy of
# ../amix-benchmark/src (SRCPKG).

# where the sources came from (amix-benchmark/src/README.md), recorded in
# BUILD-INFO and PROVENANCE
AMIXBENCH_SRC_COMMIT=c25e0e2178f6eb1e5dc8a36fd8da6d6c1df6cf51
AMIXBENCH_KIT_COMMIT=8e17364b96a36ee03e9a87fe7fa72dcdb3679eff
# payload mtimes: the kit 1.2 date, as in the period package
AMIXBENCH_SOURCE_EPOCH=1789516800

DHRY_CFLAGS="$AMIX_ARCH_FLAGS -std=gnu89 -O2 -fno-inline -DHZ=60 -Dfloat=double"
IOBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
FPBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O0 -Wall"
MEMBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
VMBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
FP_FLOOR=20
BENCHES="dhry iobench fpbench membench vmbench"

build_one() {	# build_one <name> <cflags>
	echo "$CC $2 -c $1.c -o $1.o" >> "$BUILD/make.log"
	$CC $2 -c "$1.c" -o "$1.o" > "$BUILD/$1.log" 2>&1 &&
		$CC $2 -o "$1" "$1.o" >> "$BUILD/$1.log" 2>&1 || {
			echo "[FAIL] $1 did not build:" >&2; cat "$BUILD/$1.log" >&2; exit 1; }
	# dhry.c is Weicker's, kept as published: its diagnostics stay in
	# dhry.log and post_build accepts exactly one kind; ours go to the gates
	[ "$1" = dhry ] || cat "$BUILD/$1.log" >> "$BUILD/make.log"
}

build() {
	build_one dhry "$DHRY_CFLAGS"
	build_one iobench "$IOBENCH_CFLAGS"
	build_one fpbench "$FPBENCH_CFLAGS"
	build_one membench "$MEMBENCH_CFLAGS"
	build_one vmbench "$VMBENCH_CFLAGS"
}

post_build() {
	# dhry.c, as published, declares `char *malloc ()' and calls strcpy
	# without <string.h>: GCC 14 warns that both mismatch its built-ins and
	# uses the built-ins (the right ones).  Anything else in dhry.log fails.
	other=$(grep 'warning:\|error:' "$BUILD/dhry.log" |
		grep -v "conflicting types for built-in function 'malloc'.*\[-Wbuiltin-declaration-mismatch\]" |
		grep -v "incompatible implicit declaration of built-in function 'strcpy' \[-Wbuiltin-declaration-mismatch\]" || true)
	[ -z "$other" ] || { echo "[FAIL] dhry.c diagnostics beyond the built-in malloc/strcpy:" >&2
		echo "$other" >&2; exit 1; }
	echo "  dhry: $(grep -c 'warning:' "$BUILD/dhry.log") built-in malloc/strcpy warning(s), as published; nothing else"
	# ours must be warning-clean
	for b in iobench fpbench membench vmbench; do
		! grep 'warning:' "$BUILD/$b.log" >/dev/null || {
			echo "[FAIL] $b compiled with warnings" >&2; cat "$BUILD/$b.log" >&2; exit 1; }
	done
	echo "  iobench, fpbench, membench, vmbench warning-clean"
	# -O0: fpbench must really compute, not fold its constants
	nfp=$("$OBJDUMP" -d fpbench | grep -cE '\bf(add|sub|mul|div)' || true)
	[ "$nfp" -ge "$FP_FLOOR" ] || {
		echo "[FAIL] fpbench has only $nfp FP add/sub/mul/div (floor $FP_FLOOR): constant-folded" >&2; exit 1; }
	echo "  -O0 gate: fpbench contains $nfp FP instructions (floor $FP_FLOOR)"
	# the stock SVR4 libm must not ship
	for b in $BENCHES; do
		! "$NM" "$b" | awk '$2 == "T" {print $3}' | grep -xE 'sin|cos|tan|atan|atan2|exp|log|log10|sqrt|matherr' >/dev/null || {
			echo "[FAIL] $b defines libm symbols" >&2; exit 1; }
	done
	echo "  no libm object code in any binary"
}

stage() {
	kit="$DEST$PREFIX/lib/amix-bench-g14"
	mkdir -p "$kit" "$DEST$PREFIX/bin" "$DEST$PREFIX/doc/amix-bench-g14"
	for b in $BENCHES; do
		cp "$b" "$kit/$b"
		# stripped here, so PROVENANCE carries the shipped sha256s (the
		# driver's strip after stage is then a no-op on these bytes)
		$STRIP "$kit/$b"
	done
	cp fieldkit/runbench.sh "$kit/runbench.sh"
	cp "$HERE/files/amix-bench-g14" "$DEST$PREFIX/bin/amix-bench-g14"
	cp fieldkit/README-FIELD.txt "$DEST$PREFIX/doc/amix-bench-g14/README.txt"
	printf 'int amix_bench_version_probe;\n' > "$BUILD/v.c"
	$CC -S -o "$BUILD/v.s" "$BUILD/v.c"
	cc_version=$(grep -ao 'GCC: ([^)]*)[^"]*' "$BUILD/v.s" | head -1)
	[ -n "$cc_version" ] || { echo "[FAIL] could not read the compiler's .ident" >&2; exit 1; }
	g14=$(echo "$AMIX_GCC14_COMMIT" | cut -c1-7)
	bench_version=$(sed -n 's/^#define BENCH_VERSION "\(.*\)"/\1/p' bench-compat.h | head -1)
	{
		echo "AMIX-BENCH-BUILD 1"
		echo "tool_version=$bench_version"
		echo "target=m68k-cbm-sysv4"
		echo "mode=cross"
		echo "cc=m68k-elf-gcc"
		echo "cc_version=$cc_version"
		echo "toolchain=gcc14-cross-amix $g14 (package $NAME $VERSION-$PKGREV)"
		echo "dhry_cflags=$DHRY_CFLAGS"
		echo "iobench_cflags=$IOBENCH_CFLAGS"
		echo "fpbench_cflags=$FPBENCH_CFLAGS"
		echo "membench_cflags=$MEMBENCH_CFLAGS"
		echo "vmbench_cflags=$VMBENCH_CFLAGS"
		echo "whet=not-built"
		echo "dhry_hz=60"
		for b in $BENCHES; do echo "${b}_sha256=$(sha256sum "$b.c" | cut -d' ' -f1)"; done
		echo "sources=amix-kerntools $AMIXBENCH_SRC_COMMIT"
	} > "$kit/BUILD-INFO"
	{
		echo "AMIX-BENCHMARK-GCC14 PACKAGE PROVENANCE"
		echo "======================================="
		echo "package        : $NAME (SVR4 PKG instance: $PKG)"
		echo "version        : $VERSION-$PKGREV"
		echo "recipe         : amix-packages recipes/amix-benchmark-gcc14"
		echo "compiler       : $cc_version, gcc14-cross-amix $g14"
		echo "benchmarks     : amix-kerntools $AMIXBENCH_SRC_COMMIT tools/amix-bench/src"
		echo "                 (the sources amix-benchmark's gcc 2.7.2.3 binaries were"
		echo "                 built from; their sha256s match that kit's BUILD-INFO)"
		echo "driver, README : amix-kerntools $AMIXBENCH_KIT_COMMIT tools/amix-bench/fieldkit"
		echo "                 (byte-identical to the files amix-benchmark ships)"
		echo
		echo "The two packages differ only in the compiler.  Each results header"
		echo "carries the BUILD-INFO keys, so build_cc_version names it."
		echo
		echo "whet (Whetstone) is not built: it would statically link the stock SVR4"
		echo "libm.a, which this repository does not ship; fpu.whet reports skipped."
		echo
		echo "sha256 of each shipped file:"
		for f in runbench.sh $BENCHES BUILD-INFO; do
			printf '  %-14s %s\n' "$f" "$(sha256sum "$kit/$f" | cut -d' ' -f1)"
		done
	} > "$kit/PROVENANCE"
	chmod 0755 "$DEST$PREFIX/bin/amix-bench-g14" "$kit/runbench.sh"
	for b in $BENCHES; do chmod 0755 "$kit/$b"; done
	chmod 0644 "$kit/BUILD-INFO" "$kit/PROVENANCE" "$DEST$PREFIX/doc/amix-bench-g14/README.txt"
	find "$DEST" -exec touch -h -d "@$AMIXBENCH_SOURCE_EPOCH" {} +
}
