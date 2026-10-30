#!/bin/sh
#
# smoke.sh -- rsync 3.1.3 acceptance, ON THE BOX, as root.
#
#     sh tests/smoke.sh [bindir]          (default /opt/amix/bin)
#
# Local copies, the remote-shell protocol over a local "rsh", and a modern
# peer: the host's rsync 3.4.x (protocol 32) as a daemon on the bench
# bridge, and the box's own daemon pulled from and pushed to by the host
# (tests/host.sh, run by tools/pkg-smoke/host-extra.sh; tests/host.env gives
# HOSTIP and PORT).  Content is compared by sum -r lists made on the host
# and on the box over the same files, and by cmp where both copies are here.
# 1992 Bourne shell: backticks, expr, no grep -q, no $(...), no `!'.  Result
# lines start with "RES "; the last is "RES smoke PASS" or "RES smoke FAIL <n>".

B=${1:-/opt/amix/bin}
R=$B/rsync
T=`pwd`/tests
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
has() { grep "$2" "$1" > /dev/null 2>&1; }
# eq <what> <got> <want>; an empty <want> is a failure (a missing tree
# would otherwise equal a missing copy)
eq()  { if [ -z "$3" ]; then bad "$1: nothing to compare (got '$2')"
	elif [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got '$2' want '$3'"; fi; }
flat() { tr '\012' ' ' < "$1" | sed 's/ $//'; }
# sums <dir>: "<sum -r> ./<path>" per regular file, by path (host.sh's sums)
sums() { ( cd $1 && find . -type f ! -name done -print | sort | while read f; do
	echo "`sum -r $f | awk '{print $1 + 0}'` $f"; done ); }
# sval <file> <field>: matched/literal bytes from --stats output
sval() { sed -n "s/^$2: \([0-9,.]*\) bytes.*/\1/p" $1 | tr -d ',.'; }
mode() { ls -l $1 | awk '{print $1}'; }
# zap <file> <KiB offset>: 4 KiB of zeros at the offset, same length (dd
# without conv=notrunc, which the 1992 dd may lack)
zap() { dd if=$1 of=zap.1 bs=1024 count=$2 2> /dev/null
	dd if=/dev/zero of=zap.2 bs=1024 count=4 2> /dev/null
	dd if=$1 of=zap.3 bs=1024 skip=`expr $2 + 4` 2> /dev/null
	cat zap.1 zap.2 zap.3 > $1; rm -f zap.1 zap.2 zap.3; }

rm -rf rsmoke; mkdir rsmoke; cd rsmoke || exit 1
$R --version > ver.out 2>&1
sed -n 1p ver.out
has ver.out 'rsync  version 3.1.3  protocol version 31' && ok "version 3.1.3, protocol 31" || bad "version: `sed -n 1p ver.out`"

# probes for the README (not checks)
for p in /usr/bin/rsh /usr/ucb/rsh /usr/bin/remsh /usr/ucb/remsh /usr/bin/rcmd; do
	[ -f $p ] && echo "== probe remote shell: $p `ls -l $p | awk '{print $1, $5}'`"
done
echo "== probe nobody: `grep '^nobody:' /etc/passwd | cut -d: -f1-4` / `egrep '^(nobody|nogroup):' /etc/group | cut -d: -f1-3 | tr '\012' ' '`"

# --- 1. local copies ---------------------------------------------------------
mkdir -p src/sub/deep src/many
awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "%05d line of text %d\n", i, i * 13 }' > src/text.txt
awk 'BEGIN { for (i = 0; i < 300; i++) printf "f%04d\n", i }' | while read f; do echo "$f" > src/many/$f; done
echo alpha > src/sub/a.txt; echo beta > src/sub/deep/b.txt; : > src/empty
chmod 640 src/sub/a.txt; ln -s sub/a.txt src/link; ln src/text.txt src/hard
chown bin src/sub/deep/b.txt; chgrp sys src/sub/deep/b.txt
touch -m 0203040501 src/sub/a.txt
$R -aH src/ dst/ > a.out 2>&1; rc=$?
eq "rsync -aH local (rc $rc)" "`sums dst`" "`sums src`"
eq "-a keeps the mode" "`mode dst/sub/a.txt`" "-rw-r-----"
eq "-a keeps the mtime" "`ls -l dst/sub/a.txt | awk '{print $6, $7, $8}'`" "`ls -l src/sub/a.txt | awk '{print $6, $7, $8}'`"
eq "-a keeps the symlink" "`ls -l dst/link | sed 's/.* -> //'`" "sub/a.txt"
eq "-a keeps owner and group by name (D3)" "`ls -l dst/sub/deep/b.txt | awk '{print $3, $4}'`" "bin sys"
eq "-H keeps the hard link" "`ls -i dst/hard | awk '{print $1}'`" "`ls -i dst/text.txt | awk '{print $1}'`"
eq "the empty file" "`ls -l dst/empty | awk '{print $5}'`" 0
$R -a --chown=bin:sys src/sub/ chown/ > c.out 2>&1
eq "--chown=bin:sys resolves the names (D3)" "`ls -l chown/a.txt | awk '{print $3, $4}'`" "bin sys"
$R -a --numeric-ids src/sub/ num/ > /dev/null 2>&1
eq "--numeric-ids" "`ls -ln num/deep/b.txt | awk '{print $3}'`" "`grep '^bin:' /etc/passwd | cut -d: -f3`"

echo extra > dst/stray; echo changed > src/sub/a.txt
$R -an --delete --itemize-changes src/ dst/ > n.out 2>&1
has n.out 'deleting  *stray' && has n.out 'sub/a.txt' && ok "-n --itemize-changes lists the delete and the change" || bad "-n: `flat n.out`"
eq "-n changed nothing" "`cat dst/sub/a.txt`" alpha
$R -a --delete --backup --suffix=.bak src/ dst/ > d.out 2>&1
[ -f dst/stray ] && bad "--delete left dst/stray" || ok "--delete removes the extraneous file"
eq "--backup keeps the old copy" "`cat dst/sub/a.txt.bak`" alpha
eq "and the new copy arrives" "`cat dst/sub/a.txt`" changed
$R -a --exclude='many/' --exclude='*.txt' src/ ex/ > /dev/null 2>&1
[ -d ex/many ] || [ -f ex/text.txt ] && bad "--exclude: `ls -R ex | tr '\012' ' '`" || ok "--exclude dirs and patterns"
eq "--exclude keeps the rest" "`ls ex/sub`" "deep"
# a same-size, same-mtime change only --checksum sees (whole-file MD5)
echo BETA > dst/sub/deep/b.txt; touch -m 0203040501 src/sub/deep/b.txt dst/sub/deep/b.txt
$R -a src/ dst/ > /dev/null 2>&1
eq "quick check (size+mtime) skips the change" "`cat dst/sub/deep/b.txt`" BETA
$R -ac src/ dst/ > /dev/null 2>&1
eq "--checksum catches it" "`cat dst/sub/deep/b.txt`" beta

# --- 2. the delta algorithm, locally (--no-whole-file) -------------------------
awk 'BEGIN { srand(7); for (i = 0; i < 30000; i++) printf "%08d %d\n", i, int(rand() * 1000000) }' > big
cp big big.old
$R -a big cp.big > /dev/null 2>&1
awk 'NR == 15000 { print "the changed line" } { print }' big > big.new; mv big.new big
$R -a --no-whole-file --stats big cp.big > dl.out 2>&1; rc=$?
m=`sval dl.out 'Matched data'`; l=`sval dl.out 'Literal data'`
cmp big cp.big > /dev/null 2>&1 && [ "${m:-0}" -gt 400000 ] && [ "${l:-999999}" -lt 20000 ] &&
	ok "local delta (rc $rc): matched $m, literal $l, result identical" ||
	bad "local delta rc=$rc matched=$m literal=$l: `flat dl.out`"
$R -a --inplace --no-whole-file big.old cp.big > /dev/null 2>&1
cmp big.old cp.big > /dev/null 2>&1 && ok "--inplace back to the old bytes" || bad "--inplace"
# the stock kernel panics on ftruncate of a file past its direct blocks to a
# non-aligned EOF in its last block (patches/01): 110017 -> 110000 bytes
awk 'BEGIN { for (i = 0; i < 10001; i++) printf "%010d\n", i * 7 }' > f110
dd if=f110 of=g110 bs=110000 count=1 2> /dev/null
cp f110 shrink.110
$R --inplace --no-whole-file g110 shrink.110 > /dev/null 2>&1; rc=$?
eq "--inplace shrink 110011 -> 110000 bytes, past the direct blocks (rc $rc)" "`ls -l shrink.110 | awk '{print $5}'`" 110000
cmp g110 shrink.110 > /dev/null 2>&1 && ok "and the bytes are the new file's" || bad "--inplace shrink content"
$R -a --partial --sparse big sp.big > /dev/null 2>&1
cmp big sp.big > /dev/null 2>&1 && ok "--partial --sparse" || bad "--partial --sparse"

# --- 3. the remote-shell protocol: a local "rsh" runs the far side -------------
cat > lsh <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
chmod 755 lsh
$R -aH -e `pwd`/lsh --rsync-path=$R src/ x:`pwd`/rsh/ > r.out 2>&1; rc=$?
eq "-e push to a --server (rc $rc)" "`sums rsh`" "`sums src`"
$R -az -e `pwd`/lsh --rsync-path=$R x:`pwd`/src/ rshz/ > rz.out 2>&1; rc=$?
eq "-e -z pull from a --sender (rc $rc)" "`sums rshz`" "`sums src`"
$R -az --no-whole-file --stats -e `pwd`/lsh --rsync-path=$R big.old x:`pwd`/rshz/big > rd.out 2>&1
$R -az --no-whole-file --stats -e `pwd`/lsh --rsync-path=$R big x:`pwd`/rshz/big > rd.out 2>&1; rc=$?
m=`sval rd.out 'Matched data'`
cmp big rshz/big > /dev/null 2>&1 && [ "${m:-0}" -gt 400000 ] && ok "-e -z delta (rc $rc): matched $m" ||
	bad "-e -z delta rc=$rc matched=$m: `flat rd.out`"

# --- 4. a modern peer: the host's rsync daemon -----------------------------------
if [ -f $T/host.env ]; then
	. $T/host.env
	H=rsync://$HOSTIP:$PORT/pks
	$R rsync://$HOSTIP:$PORT/ > ls.out 2>&1; rc=$?
	has ls.out '^pks' && ok "list the host daemon's modules (rc $rc)" || bad "module list rc=$rc: `flat ls.out`"
	$R -rlpt --stats $H/src/ pull/ > p.out 2>&1 &
	pid=$!; sleep 4; ps -el > ps.out 2>&1; wait $pid; rc=$?
	echo "== rsync processes during the pull (ps -el, SZ in pages):"; grep rsync ps.out
	$R -rlpt $H/SUMS SUMS > /dev/null 2>&1
	eq "pull 1500+ files from rsync 3.4 (protocol 32 peer) (rc $rc)" "`sums pull`" "`cat SUMS`"
	has p.out 'Number of files' && ok "pull --stats: `grep 'Total bytes received' p.out`" || bad "pull: `flat p.out`"
	eq "-p mode from the host" "`mode pull/sub/a.txt`" "-rw-r-----"
	eq "the symlink from the host" "`ls -l pull/link | sed 's/.* -> //'`" "sub/a.txt"
	# the box receives a delta from a little-endian sender
	cp pull/big.bin want.bin
	zap pull/big.bin 500
	$R -rlpt --stats $H/src/big.bin pull/big.bin > pd.out 2>&1; rc=$?
	m=`sval pd.out 'Matched data'`; l=`sval pd.out 'Literal data'`
	cmp want.bin pull/big.bin > /dev/null 2>&1 && [ "${m:-0}" -gt 1000000 ] && [ "${l:-999999}" -lt 20000 ] &&
		ok "delta pull from the host (rc $rc): matched $m, literal $l" ||
		bad "delta pull rc=$rc matched=$m literal=$l: `flat pd.out`"
	$R -rlptz $H/src/ pullz/ > pz.out 2>&1; rc=$?
	eq "-z pull (bundled zlib against 3.4's) (rc $rc)" "`sums pullz`" "`cat SUMS`"
	$R --protocol=29 -rlpt $H/src/sub/ p29/ > p29.out 2>&1; rc=$?
	eq "--protocol=29 pull (rc $rc)" "`cat p29/a.txt`" alpha
	# push: the box's tree, then a delta of it; the host's sum -r list says
	# what arrived (section 5)
	$R -rlt pull/ up/ > /dev/null 2>&1
	cp src/text.txt up/boxtext.txt
	$R -rltz --stats up/ $H/up/ > u.out 2>&1; rc=$?
	has u.out 'Number of files' && ok "-z push to the host daemon (rc $rc)" || bad "push rc=$rc: `flat u.out`"
	zap up/big.bin 100
	$R -rlt --stats up/big.bin $H/up/big.bin > ud.out 2>&1; rc=$?
	m=`sval ud.out 'Matched data'`; l=`sval ud.out 'Literal data'`
	[ "${m:-0}" -gt 1000000 ] && [ "${l:-999999}" -lt 20000 ] &&
		ok "delta push to the host (rc $rc): matched $m, literal $l" ||
		bad "delta push rc=$rc matched=$m literal=$l: `flat ud.out`"
else
	bad "no tests/host.env: the host side (tests/host.sh) did not run"
fi

# --- 5. the box's daemon: the host pulls from it and pushes to it ---------------
if [ -f $T/host.env ]; then
	mkdir -p bd/tree; $R -a src/ bd/tree/ > /dev/null 2>&1
	cat > rsd.conf <<EOF
pid file = `pwd`/rsd.pid
log file = `pwd`/rsd.log
uid = root
gid = sys
use chroot = yes
[bd]
	path = `pwd`/bd
	read only = no
[nb]
	path = `pwd`/src
EOF
	$R --daemon --config=`pwd`/rsd.conf < /dev/null; rc=$?
	sleep 2
	[ -f rsd.pid ] && ok "rsync --daemon starts on port 873 (rc $rc, pid `cat rsd.pid`)" || bad "daemon rc=$rc: `cat rsd.log 2>/dev/null | tr '\012' ' '`"
	i=0
	while [ ! -f bd/done ] && [ $i -lt 120 ]; do sleep 5; i=`expr $i + 1`; done
	[ -f bd/done ] && ok "the host peer finished (~`expr $i \* 5` s)" || bad "no marker from the host peer after 600 s"
	# [nb] sets no uid/gid: as root the daemon drops to its built-in
	# nobody/nobody (60001 on the box; there is no nogroup)
	$R rsync://127.0.0.1/nb/text.txt nb.txt > nb.out 2>&1; rc=$?
	cmp src/text.txt nb.txt > /dev/null 2>&1 && ok "a module with the default uid/gid (nobody/nobody) serves a file (rc $rc)" ||
		bad "default uid/gid module rc=$rc: `flat nb.out`"
	[ -f rsd.pid ] && kill `cat rsd.pid`
	eq "the host pulled the box's tree from the box daemon" "`cat bd/hsums.box 2>/dev/null`" "`sums bd/tree`"
	eq "the host pushed a tree into the box daemon (chroot)" "`sums bd/in`" "`cat SUMS`"
	eq "what the box pushed arrived on the host" "`cat bd/hsums.up 2>/dev/null`" "`sums up`"
	eq "owner by name through the daemon (uid = root)" "`ls -l bd/in/sub/a.txt | awk '{print $3}'`" root
	echo "== box daemon log"; cat rsd.log
fi

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
