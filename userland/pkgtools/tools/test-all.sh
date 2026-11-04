#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# test-all.sh -- `make test`: every pkgtools suite, in one run.
#
#   sh tools/test-all.sh            (or: make -C userland/pkgtools test)
#   PKGTOOLS_REQUIRE="objdump fakeroot compress engine" sh tools/test-all.sh
#
# Builds the host engine (heirloom/build-host.sh), then runs the apkg suite
# (which builds the host apkg), its kbootset-consumer, conffile-e2e and
# nohttp-variant runs, the conffile, contents-fsck and migrate suites and the
# repo tools.  Each suite's summary line is printed, and so is every check it
# skipped, so a skip shows in the log instead of passing in silence; a suite
# that exits 77 skipped itself whole and is listed so.  The first red suite
# stops the run, its log's tail printed; exit 1.
#
# PKGTOOLS_REQUIRE names host tools a run must have (CI installs them).  Each
# one is checked before anything runs, and a skip its absence would cause is
# a failure, not a skip:
#   objdump   m68k-linux-gnu-objdump, -as and -ld (scan060's T22 fixtures,
#             assemble-release's T34 ELFs)
#   fakeroot  fakeroot (the heirloom pkgadd installs under -R)
#   compress  compress(1) (real LZW .Z streams instead of gzip ones)
#   engine    the host pkgmk/pkgtrans this run builds
# Skips that need inputs only a workstation has (a published tree, old
# staging dirs, stock media) stay skips.
set -u

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here" || exit 2
L=$(mktemp -d "${TMPDIR:-/tmp}/pkgtools-test.XXXXXX") || exit 2
trap 'rm -rf "${L:?}"' EXIT

require=${PKGTOOLS_REQUIRE:-}
for r in $require; do
	case $r in
	objdump|fakeroot|compress|engine) ;;
	*) echo "test-all: PKGTOOLS_REQUIRE: unknown tool '$r' (objdump fakeroot compress engine)" >&2
	   exit 2 ;;
	esac
done
wants() { case " $require " in *" $1 "*) return 0 ;; esac; return 1; }
need() {        # need <token> <command>...: a required tool that is not here
	tok=$1; shift
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || {
			echo "test-all: FAIL -- PKGTOOLS_REQUIRE names $tok, and $c is not on PATH" >&2
			exit 1; }
	done
}
wants objdump && need objdump m68k-linux-gnu-objdump m68k-linux-gnu-as m68k-linux-gnu-ld
wants fakeroot && need fakeroot fakeroot
wants compress && need compress compress

echo "== host engine: heirloom/build-host.sh"
if ! (cd heirloom && ./build-host.sh) > "$L/build-host.log" 2>&1; then
	tail -30 "$L/build-host.log"
	echo "test-all: FAIL -- heirloom/build-host.sh" >&2
	exit 1
fi
if wants engine; then
	for t in pkgmk pkgtrans pkgadd; do
		[ -x "heirloom/build-host/bin/$t" ] || {
			echo "test-all: FAIL -- PKGTOOLS_REQUIRE names engine, and heirloom/build-host/bin/$t was not built" >&2
			exit 1; }
	done
fi

# the skips a required tool's absence would cause (their exact wording)
forbidden() {
	wants objdump && printf '%s\n' 'no m68k-linux-gnu-'
	wants fakeroot && printf '%s\n' '(no fakeroot)' 'fakeroot or python3 missing' 'or fakeroot missing'
	wants compress && printf '%s\n' 'compress(1) not on host'
	wants engine && printf '%s\n' 'host pkgmk/pkgtrans missing' 'host pkgmk missing' \
		'host pkgmk absent' 'no host pkgmk/pkgtrans'
	return 0
}

n=0 nskip=0 nsuite_skip=0
run() {         # run <name> <command>...
	name=$1; shift
	log="$L/$name.log"
	"$@" > "$log" 2>&1
	rc=$?
	grep -E 'passed|PASS \(' "$log" | tail -1 | sed "s/^/== $name: /"
	grep -E '^ *(skip-|SKIP:)|substituting gzip' "$log" | sed 's/^ */   /' > "$L/skips"
	cat "$L/skips"
	nskip=$((nskip + $(wc -l < "$L/skips")))
	# exit 77: the suite skipped itself whole (its SKIP: line says why)
	if [ "$rc" -eq 77 ]; then
		echo "== $name: SKIPPED (exit 77)"
	elif [ "$rc" -ne 0 ]; then
		tail -30 "$log"
		echo "test-all: FAIL -- $name (exit $rc)" >&2
		exit 1
	fi
	forbidden > "$L/forbidden"
	if [ -s "$L/forbidden" ] && grep -F -f "$L/forbidden" "$L/skips" > "$L/hit"; then
		sed 's/^/   /' "$L/hit"
		echo "test-all: FAIL -- $name skipped checks PKGTOOLS_REQUIRE='$require' forbids" >&2
		exit 1
	fi
	[ "$rc" -eq 77 ] && nsuite_skip=$((nsuite_skip + 1)) || n=$((n + 1))
}

run apkg make -C src/apkg test
run apkg-kbootset-consumer sh src/apkg/tests/kbootset-consumer.sh
run apkg-conffile-e2e sh src/apkg/tests/conffile-e2e.sh
run apkg-nohttp-variant sh src/apkg/tests/nohttp-variant.sh
run conffile sh src/conffile/tests/run-tests.sh
run contents-fsck sh src/contents-fsck/tests/run-tests.sh
run migrate sh tools/migrate/tests/run-tests.sh
run repo-tools bash tools/repo/tests/run-tests.sh

echo "pkgtools tests: $n suites passed, $nsuite_skip skipped whole, $nskip skip line(s)${require:+, PKGTOOLS_REQUIRE='$require'}"
