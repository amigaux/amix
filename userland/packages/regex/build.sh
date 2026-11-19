# build.sh -- regex hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

# the library's four routines, and upstream's regression tester (main, split,
# debug) linked with the same library: never shipped, run on the box
LIBOBJS="regcomp regexec regerror regfree"
TESTOBJS="main split debug"
# upstream's Makefile: "Do not take -DPOSIX_MISTAKE out."
REGEX_DEFS="-I. -DPOSIX_MISTAKE"

build() {
	{
		set -x
		# the forward-reference headers and regex.h, as upstream's Makefile
		# makes them, with its own mkh script
		for c in regcomp regexec regerror regfree engine debug main; do
			sh ./mkh -p "$c.c" > "$c.ih" || exit 1
		done
		sh ./mkh -i _REGEX_H_ regex2.h regcomp.c regerror.c regexec.c regfree.c > regex.h || exit 1
		for o in $LIBOBJS; do
			$CC $REGEX_DEFS $AMIX_CFLAGS -c "$o.c" -o "$o.o" || exit 1
		done
		# the tester calls getopt and exit without <stdlib.h>, as C89
		# allowed; given here, so no source changes
		for o in $TESTOBJS; do
			$CC $REGEX_DEFS -include stdlib.h $AMIX_CFLAGS -c "$o.c" -o "$o.o" || exit 1
		done
		rm -f libregex.a
		$AR rc libregex.a $(for o in $LIBOBJS; do echo "$o.o"; done) || exit 1
		$RANLIB libregex.a || exit 1
		$CC $AMIX_CFLAGS -o re main.o split.o debug.o -L. -lregex || exit 1
	} > "$BUILD/make.log" 2>&1 || { tail -30 "$BUILD/make.log" >&2; echo "[FAIL] build" >&2; exit 1; }
	grep -q '^extern int regcomp(regex_t \*, const char \*, int);$' regex.h || {
		echo "[FAIL] regex.h does not declare regcomp as upstream's mkh writes it" >&2; exit 1; }
	echo "  AR   libregex.a ($LIBOBJS); re, upstream's tester (not shipped)"
}

stage() {
	mkdir -p "$DEST$PREFIX/lib" "$DEST$PREFIX/include" "$DEST$PREFIX/man/man3" \
		"$DEST$PREFIX/man/man7" "$DEST$PREFIX/doc/regex"
	cp libregex.a "$DEST$PREFIX/lib/libregex.a"
	cp regex.h "$DEST$PREFIX/include/regex.h"
	cp regex.3 "$DEST$PREFIX/man/man3/regex.3"
	cp regex.7 "$DEST$PREFIX/man/man7/regex.7"
	for f in COPYRIGHT README WHATSNEW; do
		cp "$f" "$DEST$PREFIX/doc/regex/$f"
	done
	chmod 0644 "$DEST$PREFIX/lib/libregex.a" "$DEST$PREFIX/include/regex.h" \
		"$DEST$PREFIX"/man/man3/* "$DEST$PREFIX"/man/man7/* "$DEST$PREFIX"/doc/regex/*
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	# regex(3) documents all four calls: one page name for each
	for f in regcomp regexec regerror regfree; do
		amix_man_alias "$f" 3 regex
	done
	amix_man_whatis
}
