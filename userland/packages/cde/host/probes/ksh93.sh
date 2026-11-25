# ksh93.sh KSH93 STORE SHOPTS -- build dtksh's ksh93 (programs/dtksh/ksh93) for
# Amix with AST's own build, bin/package (README.md, dtksh), into the flat view
# programs/dtksh/Makefile links from: lib/libshell.a, libcmd.a, libast.a,
# libdll.a, src/cmd/ksh93/pmain.o, bin/ksh.
# First package builds AST for the build machine, for the tools it runs
# (mamake, iffe, ...); then, with those first on PATH, for Amix, with pcc as
# the compiler: every feature probe answers as it did on Amix (PCC_ANSWERS),
# replayed (PCC_MODE=replay) or, for a probe the file has no answer to, run on
# a box (record: prund.py at PCC_SOCK).  STORE: pcc's working files.
# SHOPTS: ksh's options, KSH93_SHOPTS of programs/dtksh/Makefile.am, which
# dtksh is compiled with too.  The toolchain's environment (CC, AMIX_CFLAGS,
# AMIX_GCC14_DECLS) is set.  KSH93_KEEPGOING=1: make -k, every error at once.
# MIT licence, see LICENSE in userland/packages.
K=$1 STORE=$2 SHOPTS=$3
here=$(cd "$(dirname "$0")" && pwd)
[ -x "$K/bin/package" ] || { echo "ksh93.sh: no $K/bin/package" >&2; exit 1; }
mkdir -p "$STORE/xbin"
# iffe names its test files from HOSTNAME's first letters: not the build machine's
HOSTNAME=amix; export HOSTNAME
# libast builds as a release, with no commit compiled in, unless its source is a
# git checkout: git is not to find a repository the tree happens to be inside
GIT_CEILING_DIRECTORIES=$(cd "$K/.." && pwd); export GIT_CEILING_DIRECTORIES
echo "$SHOPTS" > "$STORE/shopts"
# 1. AST for the build machine, its own compiler and none of the target's flags
( cd "$K" && env -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS -u LIBS -u HOSTTYPE \
	bin/package make ) > "$STORE/native.log" 2>&1 || {
	tail -20 "$STORE/native.log" >&2; echo "ksh93.sh: the build machine's AST failed" >&2; exit 1; }
nat=$(cd "$K" && env -u CC -u HOSTTYPE bin/package host type)
[ -x "$K/arch/$nat/bin/mamake" ] && [ -x "$K/arch/$nat/bin/iffe" ] || {
	echo "ksh93.sh: no mamake or iffe in $K/arch/$nat/bin" >&2; exit 1; }
# 2. for Amix: package takes its tools from PATH and calls the build machine's
# compiler cc; CC is pcc, so the probes are stubs
printf '#!/bin/sh\nexec gcc "$@"\n' > "$STORE/xbin/cc"
chmod 755 "$STORE/xbin/cc"
PCC_REAL="$CC $AMIX_CFLAGS -include $AMIX_GCC14_DECLS" PCC_DIR=$here PCC_STORE=$STORE
export PCC_REAL PCC_DIR PCC_STORE
: "${PCC_ANSWERS:?}" "${PCC_MODE:=replay}"
export PCC_ANSWERS PCC_MODE
rm -f -- "${STORE:?}/missing" "${STORE:?}/used"
( cd "$K" &&
	PATH=$K/arch/$nat/bin:$K/bin:$STORE/xbin:$here:$PATH CC=pcc HOSTTYPE=amix.m68k &&
	export PATH CC HOSTTYPE && unset IFFEFLAGS &&
	bin/package flat make ${KSH93_KEEPGOING:+-k} HOSTTYPE=amix.m68k CCFLAGS="$SHOPTS" ) > "$STORE/cross.log" 2>&1
rc=$?
if [ -s "$STORE/missing" ]; then
	echo "ksh93.sh: $(sort -u "$STORE/missing" | wc -l) probe runs have no answer (README.md, dtksh: record them):" >&2
	sort -u "$STORE/missing" >&2
	exit 1
fi
grep -q '^make.*exit code\|^mamake.*exit code' "$K/arch/amix.m68k/lib/package/gen/make.out" && rc=1
for f in lib/libshell.a lib/libcmd.a lib/libast.a lib/libdll.a src/cmd/ksh93/pmain.o bin/ksh; do
	[ -f "$K/$f" ] || { echo "ksh93.sh: no $f in the flat view" >&2; rc=1; }
done
[ $rc = 0 ] || { grep -B2 -A6 'error:\|exit code' "$K/arch/amix.m68k/lib/package/gen/make.out" | tail -60 >&2
	echo "ksh93.sh: the build for Amix failed ($STORE/cross.log, arch/amix.m68k/lib/package/gen/make.out)" >&2; exit 1; }
echo "ksh93.sh: ksh93 for Amix built; $(sort -u "$STORE/used" | wc -l) probe runs answered"
