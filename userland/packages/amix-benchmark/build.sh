# build.sh -- amix-benchmark hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is a copy of src/.

# where the sources came from (src/README.md), recorded in BUILD-INFO and PROVENANCE
AMIXBENCH_SRC_COMMIT=c25e0e2178f6eb1e5dc8a36fd8da6d6c1df6cf51
AMIXBENCH_KIT_COMMIT=8e17364b96a36ee03e9a87fe7fa72dcdb3679eff
AMIXBENCH_KIT_VERSION=1.2

# the flags the reference numbers were measured with; do not tidy them.
# -Dfloat=double is a gcc 2.7.2.3 workaround, -O0 keeps fpbench computing.
DHRY_CFLAGS="-O2 -fno-inline-functions -DHZ=60 -Dfloat=double"
IOBENCH_CFLAGS="-O2 -Wall"
FPBENCH_CFLAGS="-O0 -Wall"
MEMBENCH_CFLAGS="-O2 -Wall"
VMBENCH_CFLAGS="-O2 -Wall"
FP_FLOOR=20
BENCHES="dhry iobench fpbench membench vmbench"

build_one() {	# build_one <name> <cflags>
	echo "$CC $2 -c $1.c -o $1.o" >> "$BUILD/make.log"
	$CC $2 -c "$1.c" -o "$1.o" > "$BUILD/$1.log" 2>&1 &&
		$CC -o "$1" "$1.o" >> "$BUILD/$1.log" 2>&1 || {
			echo "[FAIL] $1 did not build:" >&2; cat "$BUILD/$1.log" >&2; exit 1; }
	cat "$BUILD/$1.log" >> "$BUILD/make.log"
}

build() {
	build_one dhry "$DHRY_CFLAGS"
	build_one iobench "$IOBENCH_CFLAGS"
	build_one fpbench "$FPBENCH_CFLAGS"
	build_one membench "$MEMBENCH_CFLAGS"
	build_one vmbench "$VMBENCH_CFLAGS"
}

post_build() {
	for b in $BENCHES; do
		! grep 'warning:' "$BUILD/$b.log" >/dev/null || {
			echo "[FAIL] $b compiled with warnings" >&2; cat "$BUILD/$b.log" >&2; exit 1; }
	done
	echo "  all five warning-clean"
	# -O0: fpbench must really compute, not fold its constants
	nfp=$("$OBJDUMP" -d fpbench | grep -cE '\bf(add|sub|mul|div)' || true)
	[ "$nfp" -ge "$FP_FLOOR" ] || {
		echo "[FAIL] fpbench has only $nfp FP add/sub/mul/div (floor $FP_FLOOR): constant-folded" >&2; exit 1; }
	echo "  -O0 gate: fpbench contains $nfp FP instructions (floor $FP_FLOOR)"
	# no FP compare in any of them: the sources were written to need none
	for b in $BENCHES; do
		n=$("$OBJDUMP" -d "$b" | grep -c 'fcmp' || true)
		[ "$n" = 0 ] || { echo "[FAIL] $b has $n fcmp" >&2; exit 1; }
	done
	echo "  no fcmp in any binary"
	# the stock SVR4 libm must not ship
	for b in $BENCHES; do
		! "$NM" "$b" | awk '$2 == "T" {print $3}' | grep -xE 'sin|cos|tan|atan|atan2|exp|log|log10|sqrt|matherr' >/dev/null || {
			echo "[FAIL] $b defines libm symbols" >&2; exit 1; }
	done
	echo "  no libm object code in any binary"
	# the driver: the 24-row matrix, and benchmark children cannot drain its row list
	rows=$(sh fieldkit/runbench.sh --list | grep -c .)
	[ "$rows" = 24 ] || { echo "[FAIL] runbench --list gives $rows rows, not 24" >&2; exit 1; }
	grep -E '<[[:space:]]*/dev/null' fieldkit/runbench.sh >/dev/null || {
		echo "[FAIL] runbench.sh has no stdin redirect from /dev/null" >&2; exit 1; }
	echo "  driver: 24 rows, children's stdin from /dev/null"
}

stage() {
	kit="$DEST$PREFIX/lib/amix-bench"
	doc="$DEST$PREFIX/doc/amix-benchmark"
	mkdir -p "$kit" "$DEST$PREFIX/bin" "$doc"
	for b in $BENCHES; do
		cp "$b" "$kit/$b"
		# stripped here, so PROVENANCE carries the shipped sha256s (the
		# driver's strip after stage is then a no-op on these bytes)
		$STRIP "$kit/$b"
	done
	cp fieldkit/runbench.sh "$kit/runbench.sh"
	cp "$HERE/files/amix-bench" "$DEST$PREFIX/bin/amix-bench"
	cp fieldkit/README-FIELD.txt "$doc/README.txt"
	cp "$HERE/../LICENSE" "$doc/LICENSE.amix"
	cp "$HERE/doc/NOTICE" "$doc/NOTICE"
	printf 'int amix_bench_version_probe;\n' > "$BUILD/v.c"
	$CC -S -o "$BUILD/v.s" "$BUILD/v.c"
	cc_version=$(grep -ao 'GCC: ([^)]*)[^"]*' "$BUILD/v.s" | head -1)
	[ -n "$cc_version" ] || { echo "[FAIL] could not read the compiler's .ident" >&2; exit 1; }
	gca=$(echo "$AMIX_GCA_PIN" | cut -c1-7)
	# no host, no date: the results header carries every key of this file
	{
		echo "AMIX-BENCH-BUILD 1"
		echo "tool_version=$AMIXBENCH_KIT_VERSION"
		echo "target=m68k-cbm-sysv4"
		echo "mode=cross"
		echo "cc=m68k-cbm-sysv4-gcc"
		echo "cc_version=$cc_version"
		echo "toolchain=gcc-cross-amix $gca (package $NAME $VERSION-$PKGREV)"
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
		echo "AMIX-BENCHMARK PACKAGE PROVENANCE"
		echo "================================="
		echo "package        : $NAME (SVR4 PKG instance: $PKG)"
		echo "version        : $VERSION-$PKGREV"
		echo "recipe         : amix userland/packages/amix-benchmark"
		echo "compiler       : $cc_version, gcc-cross-amix $gca"
		echo "benchmarks     : amix userland/packages/amix-benchmark/src, as amix-kerntools"
		echo "                 $AMIXBENCH_SRC_COMMIT tools/amix-bench/src"
		echo "driver, README : amix userland/packages/amix-benchmark/src/fieldkit, as"
		echo "                 amix-kerntools $AMIXBENCH_KIT_COMMIT tools/amix-bench/fieldkit"
		echo
		echo "The sources and flags are those of the kit $AMIXBENCH_KIT_VERSION binaries the suite's"
		echo "reference numbers were measured with, and the code they compile to is"
		echo "the same; this toolchain's link adds _lib_version, which moves addresses."
		echo
		echo "whet (Whetstone) is not built: it would statically link the stock SVR4"
		echo "libm.a, which this package does not ship; fpu.whet reports skipped."
		echo
		echo "sha256 of each shipped file:"
		for f in runbench.sh $BENCHES BUILD-INFO; do
			printf '  %-14s %s\n' "$f" "$(sha256sum "$kit/$f" | cut -d' ' -f1)"
		done
	} > "$kit/PROVENANCE"
	chmod 0755 "$DEST$PREFIX/bin/amix-bench" "$kit/runbench.sh"
	for b in $BENCHES; do chmod 0755 "$kit/$b"; done
	chmod 0644 "$kit/BUILD-INFO" "$kit/PROVENANCE" "$doc"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man "$HERE/man/amix-bench.1" 1
	amix_man_whatis
	# nothing shipped names a home directory or this build host
	h=$(hostname 2>/dev/null || uname -n)
	leak=$(find "$DEST" -type f | while read -r f; do
		strings -a "$f" | grep -E "/home/|/Users/|$h" | sed "s|^|${f#$DEST}: |"
	done)
	[ -z "$leak" ] || { echo "[FAIL] a build-host string ships:" >&2; echo "$leak" >&2; exit 1; }
	echo "  HOST ok   no /home/, /Users/ or the build host's name in any staged file"
}
