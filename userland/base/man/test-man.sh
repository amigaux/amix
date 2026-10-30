#!/bin/sh
# test-man.sh -- host tests of man.sh against a fake tree, a fake stock man
# and a fake formatter.
#
#   sh userland/base/man/test-man.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-man.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}
refuse() { # refuse <name> <unwanted-substring> <got>
	case "$3" in *"$2"*) bad "$1: unwanted [$2] in [$3]" ;; *) ok ;; esac
}

mkdir -p "$T/man/1" "$T/man/3" "$T/man/5" "$T/man/whatis.d" "$T/cat/1" "$T/cat/3" "$T/bin"
printf '.TH TAR 1\nGNU tar page\n' > "$T/man/1/tar"
printf '.so %s/man/1/bzip2\n' "$T" > "$T/man/1/bzcat"
printf '.TH BZIP2 1\nbzip2 page\n' > "$T/man/1/bzip2"
printf '.so 1/bzip2\n' > "$T/man/1/bunzip2"
printf '.TH ZLIB 3\nzlib page\n' > "$T/man/3/zlib"
printf '.TH RSYNCD.CONF 5\nrsyncd page\n' > "$T/man/5/rsyncd.conf"
printf 'tar(1)           tar - GNU tape archiver\n' > "$T/man/whatis.d/gtar"
printf 'zlib(3)          zlib - compression library\n' > "$T/man/whatis.d/zlib"
# the stock man: report how it was called and with which MANPATH/CATPATH
cat > "$T/bin/stockman" <<'EOF'
#!/bin/sh
echo "STOCK[$*] MANPATH=${MANPATH-unset} CATPATH=${CATPATH-unset}"
case "$*" in *nosuch*) exit 1 ;; esac
exit 0
EOF
# the formatter: tag the text so a cached copy can be told apart
printf '#!/bin/sh\ncat "$@"\n' > "$T/bin/tbl"
printf '#!/bin/sh\necho "FMT $$"; cat\n' > "$T/bin/nroff"
chmod +x "$T/bin/"*

run() {
	env AMIX_MANTREE="$T/man" AMIX_CATTREE="$T/cat" AMIX_STOCKMAN="$T/bin/stockman" \
	    AMIX_NROFF="$T/bin/nroff" AMIX_TBL="$T/bin/tbl" AMIX_EQN=cat PATH="$T/bin:$PATH" PAGER=cat \
	    "$@" 2>&1
}
M="$SH $here/man.sh"

o=$(run $M tar);                expect "ours" "GNU tar page" "$o"; refuse "ours not stock" "STOCK" "$o"
o=$(run $M ls);                 expect "stock fallback" "STOCK[ls]" "$o"
o=$(run $M 1 ls);               expect "stock with section" "STOCK[1 ls]" "$o"
o=$(run $M 3 zlib);             expect "section" "zlib page" "$o"
o=$(run $M 1 zlib);             expect "wrong section -> stock" "STOCK[1 zlib]" "$o"
o=$(run $M rsyncd.conf);        expect "other section in order" "rsyncd page" "$o"
o=$(run $M bzcat);              expect "absolute .so" "bzip2 page" "$o"
o=$(run $M bunzip2);            expect "relative .so" "bzip2 page" "$o"
o=$(run $M tar ls);             expect "two names: ours" "GNU tar page" "$o"; expect "two names: stock" "STOCK[ls]" "$o"
run $M nosuch >/dev/null;       [ $? -ne 0 ] && ok || bad "missing page exit status"
o=$(run $M -k tape);            expect "-k ours" "tar(1)" "$o"; expect "-k stock" "STOCK[-k tape]" "$o"
o=$(run $M -f zlib);            expect "-f ours" "zlib(3)" "$o"; expect "-f stock" "STOCK[-f zlib]" "$o"
o=$(run $M -w x);               expect "unknown option to stock" "STOCK[-w x]" "$o"
o=$(run $M);                    expect "no arguments to stock" "STOCK[]" "$o"
o=$(run env MANPATH=/opt/amix/man CATPATH=/x $M ls)
expect "MANPATH into our tree dropped" "MANPATH=unset CATPATH=unset" "$o"
o=$(run env MANPATH=/usr/share/man $M ls)
expect "other MANPATH kept" "MANPATH=/usr/share/man" "$o"

# the cache: written where writable, reused, refreshed when the source is newer
rm -f "$T/cat/1/tar"
a=$(run $M tar); [ -f "$T/cat/1/tar" ] && ok || bad "cache written"
b=$(run $M tar); [ "$a" = "$b" ] && ok || bad "cache reused: [$a] vs [$b]"
sleep 1; touch "$T/man/1/tar"
c=$(run $M tar); [ "$a" != "$c" ] && ok || bad "cache refreshed after the source changed"
ls "$T/cat/1" | grep -q '^T' && bad "temporary file left in the cache" || ok
# no cache directory for section 5: formatted every time, nothing written
run $M rsyncd.conf >/dev/null; [ ! -e "$T/cat/5" ] && ok || bad "cache made for an absent section"
# a read-only cache directory: formatted, not written
rm -f "$T/cat/3/zlib"; chmod 555 "$T/cat/3"
if [ ! -w "$T/cat/3" ]; then
	o=$(run $M zlib); expect "read-only cache still shows" "zlib page" "$o"
	[ ! -e "$T/cat/3/zlib" ] && ok || bad "read-only cache written"
fi
chmod 755 "$T/cat/3"

# which page for a command: the binary PATH runs decides (owner, 2026-10-30)
mkdir -p "$T/usr/bin" "$T/usr/sbin" "$T/opt/amix/bin" "$T/usr/amix/bin" "$T/man/1m"
for b in usr/bin/tar opt/amix/bin/tar usr/bin/printf opt/amix/bin/bzip2 usr/sbin/dlpi-mac usr/amix/bin/man; do
	printf '#!/bin/sh\n' > "$T/$b"; chmod +x "$T/$b"
done
printf '.TH GREP 1\nGNU grep page\n' > "$T/man/1/zgrepx"
printf '.TH PRINTF 1\nGNU printf page\n' > "$T/man/1/printf"
printf '.TH DLPI-MAC 1M\ndlpi-mac page\n' > "$T/man/1m/dlpi-mac"
printf '.TH MAN 1\nour man page\n' > "$T/man/1/man"
cat > "$T/whatis" <<'EOF2'
zgrepx(1)        zgrepx - search a file for a pattern
ls(1)            ls - list contents of directory
man(1)           man - display reference manual pages
pkgadd(1M)       pkgadd - transfer software package to the system
printf(3S)       printf, fprintf, sprintf - print formatted output
tar(1)           tar - tape file archiver
zlib(3)          zlib - a stock page of the same name, for the test
EOF2
rm -rf "$T/cat/1"/* "$T/cat/3"/*
stockfirst="$T/usr/bin:$T/usr/sbin:$T/usr/amix/bin:$T/opt/amix/bin:/usr/bin:/bin"
oursfirst="$T/usr/amix/bin:$T/opt/amix/bin:$T/usr/bin:$T/usr/sbin:/usr/bin:/bin"
prun() { # prun <PATH> man args...
	p=$1; shift
	env AMIX_MANTREE="$T/man" AMIX_CATTREE="$T/cat" AMIX_STOCKMAN="$T/bin/stockman" \
	    AMIX_NROFF="$T/bin/nroff" AMIX_TBL="$T/bin/tbl" AMIX_EQN=cat PAGER=cat \
	    AMIX_STOCKWHATIS="$T/whatis" AMIX_OURBIN="$T/opt/amix/ $T/usr/amix/" PATH="$p" \
	    $SH "$here/man.sh" "$@" 2>&1
}
o=$(prun "$stockfirst" tar);       expect "stock binary first: stock page" "STOCK[1 tar]" "$o"; refuse "stock binary first: not ours" "GNU tar page" "$o"
o=$(prun "$oursfirst" tar);        expect "our binary first: our page" "GNU tar page" "$o"; refuse "our binary first: not stock" "STOCK" "$o"
o=$(prun "$stockfirst" zgrepx);     expect "no binary on PATH: ours" "GNU grep page" "$o"; refuse "no binary: not stock" "STOCK" "$o"
o=$(prun "$stockfirst" bzip2);     expect "only ours has it" "bzip2 page" "$o"; refuse "only ours: not stock" "STOCK" "$o"
o=$(prun "$stockfirst" dlpi-mac);  expect "stock dir, no stock page: ours" "dlpi-mac page" "$o"
o=$(prun "$stockfirst" ls);        expect "only stock has it" "STOCK[ls]" "$o"
o=$(prun "$stockfirst" man);       expect "the front-end's own page" "our man page" "$o"
o=$(prun "$stockfirst" printf);    expect "stock printf only in 3S: ours" "GNU printf page" "$o"; refuse "3S is not the command's page" "STOCK" "$o"
o=$(prun "$stockfirst" 1 tar);     expect "explicit 1, stock binary" "STOCK[1 tar]" "$o"
o=$(prun "$oursfirst" 1 tar);      expect "explicit 1, our binary" "GNU tar page" "$o"
o=$(prun "$stockfirst" 3 zlib);    expect "not a command: ours" "zlib page" "$o"; refuse "not a command: not stock" "STOCK" "$o"
o=$(prun "$stockfirst" -a tar);    expect "-a: stock" "STOCK[1 tar]" "$o"; expect "-a: ours" "GNU tar page" "$o"
case "$o" in "STOCK"*"GNU tar page"*) ok ;; *) bad "-a: the chosen page first: $o" ;; esac
o=$(prun "$oursfirst" -a tar);     case "$o" in *"GNU tar page"*"STOCK[tar]"*) ok ;; *) bad "-a ours first: $o" ;; esac
o=$(prun "$stockfirst" -a bzip2);  expect "-a, only ours" "bzip2 page" "$o"; refuse "-a, only ours: no stock call" "STOCK" "$o"
o=$(prun "$stockfirst" -a 3 zlib); expect "-a explicit 3: ours" "zlib page" "$o"; expect "-a explicit 3: stock" "STOCK[3 zlib]" "$o"
o=$(prun "$stockfirst" -a ls);     expect "-a, only stock" "STOCK[ls]" "$o"

echo "test-man: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
