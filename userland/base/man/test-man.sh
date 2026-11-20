#!/bin/sh
# test-man.sh -- host tests of man.sh against a fake tree, a fake stock man
# and a fake formatter.
#
#   sh userland/base/man/test-man.sh [shell]     (default sh)
#
# TEST_MANSH=<file> runs the same tests against another man.sh (an older
# one, to show what changed).
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
MS=${TEST_MANSH:-$here/man.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-man.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
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
M="$SH $MS"

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
rm -f "${T:?}/cat/1/tar"
a=$(run $M tar); [ -f "$T/cat/1/tar" ] && ok || bad "cache written"
b=$(run $M tar); [ "$a" = "$b" ] && ok || bad "cache reused: [$a] vs [$b]"
sleep 1; touch "$T/man/1/tar"
c=$(run $M tar); [ "$a" != "$c" ] && ok || bad "cache refreshed after the source changed"
ls "$T/cat/1" | grep -q '^T' && bad "temporary file left in the cache" || ok
# no cache directory for section 5: formatted every time, nothing written
run $M rsyncd.conf >/dev/null; [ ! -e "$T/cat/5" ] && ok || bad "cache made for an absent section"
# a read-only cache directory: formatted, not written
rm -f "${T:?}/cat/3/zlib"; chmod 555 "$T/cat/3"
if [ ! -w "$T/cat/3" ]; then
	o=$(run $M zlib); expect "read-only cache still shows" "zlib page" "$o"
	[ ! -e "$T/cat/3/zlib" ] && ok || bad "read-only cache written"
fi
chmod 755 "$T/cat/3"

# which page for a command: the binary PATH runs decides
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
rm -rf "${T:?}/cat/1"/* "${T:?}/cat/3"/*
stockfirst="$T/usr/bin:$T/usr/sbin:$T/usr/amix/bin:$T/opt/amix/bin:/usr/bin:/bin"
oursfirst="$T/usr/amix/bin:$T/opt/amix/bin:$T/usr/bin:$T/usr/sbin:/usr/bin:/bin"
prun() { # prun <PATH> man args...
	p=$1; shift
	env AMIX_MANTREE="$T/man" AMIX_CATTREE="$T/cat" AMIX_STOCKMAN="$T/bin/stockman" \
	    AMIX_NROFF="$T/bin/nroff" AMIX_TBL="$T/bin/tbl" AMIX_EQN=cat PAGER=cat \
	    AMIX_STOCKWHATIS="$T/whatis" AMIX_OURBIN="$T/opt/amix/ $T/usr/amix/" PATH="$p" \
	    $SH "$MS" "$@" 2>&1
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

# a stock binary a package replaced (replaces.d): the package's page for it
mkdir -p "$T/man/replaces.d"
printf '.TH TAR 1\nHeirloom tar page\n' > "$T/man/1/heirloom-tar"
printf '# the stock tar, replaced\n%s/usr/bin/tar 1 heirloom-tar\n%s/usr/bin/nosuchbin 1 nosuchpage\n' "$T" "$T" > "$T/man/replaces.d/hltar"
rm -rf "${T:?}/cat/1"/*
o=$(prun "$stockfirst" tar);       expect "replaced: its page" "Heirloom tar page" "$o"; refuse "replaced: not stock" "STOCK" "$o"; refuse "replaced: not GNU" "GNU tar page" "$o"
o=$(prun "$oursfirst" tar);        expect "PATH runs ours first: our page" "GNU tar page" "$o"; refuse "PATH runs ours: not the replacement" "Heirloom" "$o"
o=$(prun "$stockfirst" 1 tar);     expect "replaced, explicit 1" "Heirloom tar page" "$o"
o=$(prun "$stockfirst" 3 tar);     expect "replaced, other section: stock" "STOCK[3 tar]" "$o"; refuse "other section: not the replacement" "Heirloom" "$o"
o=$(prun "$stockfirst" -a tar);    case "$o" in *"Heirloom tar page"*"STOCK[1 tar]"*) ok ;; *) bad "-a replaced: its page, then stock: $o" ;; esac
o=$(prun "$stockfirst" heirloom-tar); expect "the page by its own name" "Heirloom tar page" "$o"
[ -f "$T/cat/1/heirloom-tar" ] && ok || bad "replaced: cached under the page's name"
o=$(prun "$oursfirst" tar)
grep -q 'GNU tar page' "$T/cat/1/tar" 2>/dev/null && ! grep -q Heirloom "$T/cat/1/tar" && ok || bad "the other page cached apart: $(cat "$T/cat/1/tar" 2>&1)"
grep -q Heirloom "$T/cat/1/heirloom-tar" && ok || bad "the replacement's cache kept apart"
o=$(prun "$stockfirst" hltar);     expect "replaces.d is not a section" "STOCK[hltar]" "$o"
o=$(prun "$stockfirst" replaces.d hltar); refuse "replaces.d is not a section argument" "Heirloom" "$o"; expect "replaces.d as a name" "STOCK[replaces.d]" "$o"
rm -f "${T:?}/man/1/heirloom-tar"
o=$(prun "$stockfirst" tar);       expect "replacement page missing: as before" "STOCK[1 tar]" "$o"

# a colon-separated MANPATH (a CDE session's /usr/dt/man:/usr/share/man).
# This stock man reads one tree as the real one does: <MANPATH>/whatis,
# else "egrep: can't open"; STOCKDEF when MANPATH is unset.
mkdir -p "$T/dt/man3" "$T/share" "$T/local"
printf 'ls(1)            ls, lc - list contents of directory\ntar(1)           tar - tape file archiver\nrcp(3)           rcp - a section 3 page\n' > "$T/share/whatis"
printf 'ls(1)            ls - the local tree page\nlocalcmd(1)      localcmd - only here\nrcp(1)           rcp - local copy, section 1\n' > "$T/local/whatis"
cat > "$T/bin/stockone" <<'EOF3'
#!/bin/sh
mp=${MANPATH:-$STOCKDEF}
echo "STOCK[$*] MANPATH=${MANPATH-unset} CATPATH=${CATPATH-unset}"
[ -r "$mp/whatis" ] || { echo "egrep: can't open $mp/whatis"; exit 2; }
for a; do n=$a; done
case "${1:-}" in -k|-f) grep -i "$n" "$mp/whatis"; exit ;; esac
if grep "^$n(" "$mp/whatis" > /dev/null; then echo "PAGE $mp $n"; else echo "No manual entry for $n."; exit 1; fi
EOF3
chmod +x "$T/bin/stockone"
lrun() { # lrun <PATH> <MANPATH|-unset-> man args...
	p=$1; mp=$2; shift 2
	if [ "$mp" = -unset- ]; then u="-u MANPATH"; mp=; else u=; fi
	env $u ${mp:+MANPATH="$mp"} STOCKDEF="$T/share" AMIX_MANTREE="$T/man" AMIX_CATTREE="$T/cat" \
	    AMIX_STOCKMAN="$T/bin/stockone" AMIX_NROFF="$T/bin/nroff" AMIX_TBL="$T/bin/tbl" AMIX_EQN=cat \
	    PAGER=cat AMIX_STOCKWHATIS="$T/share/whatis" AMIX_OURBIN="$T/opt/amix/ $T/usr/amix/" PATH="$p" \
	    $SH "$MS" "$@" 2>&1
}
cde="$T/dt:$T/share"
# unset and one directory: as before
o=$(lrun "$stockfirst" -unset- ls);       expect "unset: the stock tree" "PAGE $T/share ls" "$o"; expect "unset: MANPATH unset" "MANPATH=unset" "$o"
o=$(lrun "$stockfirst" "$T/share" ls);    expect "one dir: passed as it is" "STOCK[ls] MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "$T/dt" ls);       expect "one dir without index: the stock man's own answer" "can't open $T/dt/whatis" "$o"
# a list: each tree alone, in order
o=$(lrun "$stockfirst" "$cde" ls);        expect "list: the tree with the name" "STOCK[ls] MANPATH=$T/share" "$o"; expect "list: its page" "PAGE $T/share ls" "$o"; refuse "list: never the whole list" "can't open" "$o"
o=$(lrun "$stockfirst" "$cde" 1 ls);      expect "list, section 1" "STOCK[1 ls] MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "$T/local:$T/share" ls); expect "list: the first tree that has it" "PAGE $T/local ls" "$o"
o=$(lrun "$stockfirst" "$T/share:$T/local" ls); expect "list: order kept" "PAGE $T/share ls" "$o"
o=$(lrun "$stockfirst" "$T/share:$T/local" localcmd); expect "list: a later tree" "PAGE $T/local localcmd" "$o"
o=$(lrun "$stockfirst" "$T/share:$T/local" 1 rcp); expect "list: the tree with that section" "PAGE $T/local rcp" "$o"
o=$(lrun "$stockfirst" "$T/local:$T/share" 3 rcp); expect "list: the section 3 tree" "PAGE $T/share rcp" "$o"
o=$(lrun "$stockfirst" "$cde" nosuch);    expect "list: none has it" "No manual entry for nosuch." "$o"; expect "list: none: the first tree with an index" "MANPATH=$T/share" "$o"
lrun "$stockfirst" "$cde" nosuch > /dev/null; [ $? -ne 0 ] && ok || bad "list: none has it: exit status"
o=$(lrun "$stockfirst" "$T/dt:" ls);      expect "list without an index: the first tree's answer" "can't open $T/dt/whatis" "$o"
o=$(lrun "$stockfirst" "$cde" -k list);   expect "list -k: the tree with an index" "STOCK[-k list] MANPATH=$T/share" "$o"; refuse "list -k: never the whole list" "can't open" "$o"
o=$(lrun "$stockfirst" "$T/share:$T/local" -k list); expect "list -k: each tree" "MANPATH=$T/local" "$o"; expect "list -k: each tree, first" "MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "$cde" -w x);      expect "list, unknown option: one tree" "STOCK[-w x] MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "$cde");           expect "list, no argument: one tree" "STOCK[] MANPATH=$T/share" "$o"
# our tree in a list is dropped, CATPATH with it; our pages are found as now
o=$(lrun "$stockfirst" "$T/man:$cde" ls); expect "list with our tree: dropped" "STOCK[ls] MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "/opt/amix/man:$T/share" ls); expect "list with /opt/amix: dropped" "STOCK[ls] MANPATH=$T/share" "$o"
o=$(CATPATH=/x; export CATPATH; lrun "$stockfirst" "/opt/amix/man:$T/share" ls); expect "list with our tree: CATPATH dropped" "CATPATH=unset" "$o"
o=$(CATPATH=/x; export CATPATH; lrun "$stockfirst" "$cde" ls); expect "list without our tree: CATPATH kept" "CATPATH=/x" "$o"
o=$(lrun "$stockfirst" "/opt/amix/man:$T/man" ls); expect "list of our tree only: the stock default" "STOCK[ls] MANPATH=unset" "$o"
o=$(lrun "$stockfirst" "$cde" bzip2);     expect "list: our page as before" "bzip2 page" "$o"; refuse "list: our page, no stock call" "STOCK" "$o"
# which page for a command: the list's indexes stand for the stock index
o=$(lrun "$stockfirst" "$cde" tar);       expect "list: stock binary, stock tree has it" "STOCK[1 tar] MANPATH=$T/share" "$o"
o=$(lrun "$stockfirst" "$T/dt:$T/local" tar); expect "list without the stock tree: ours" "GNU tar page" "$o"; refuse "list without the stock tree: no stock call" "STOCK" "$o"
o=$(lrun "$stockfirst" "$cde" -a tar);    expect "list -a: stock from its tree" "STOCK[1 tar] MANPATH=$T/share" "$o"; expect "list -a: ours" "GNU tar page" "$o"

echo "test-man: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
