#!/bin/sh
#
# smoke.sh -- Dropbear acceptance, ON THE BOX, as root, with the package
# installed and amix-base's rc.subr present.
#
#     sh tests/smoke.sh
#
# The boot script makes the host key and starts the server; the box's own
# client logs in to a modern OpenSSH on the host (key) and to this server
# (password), and copies with scp both ways.  The host's half (tests/host.sh
# run: OpenSSH's ssh and scp against this server) runs while this script
# waits: it writes tests/ready.box and waits for tests/done.host.
# tests/host.env (from tests/host.sh pre) gives HOSTIP, PORT, HUSER, HDIR,
# HOSTPUB, ROOTPASS and TOBOXSUM.
# 1992 Bourne shell: backticks, expr, no grep -q, no $(...), no `!'.
# Result lines start with "RES "; the last is "RES smoke PASS" or
# "RES smoke FAIL <n>".

B=/opt/amix/bin
D=/opt/amix/sbin/dropbear
K=/etc/dropbear
T=`pwd`/tests
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
has() { grep "$2" "$1" > /dev/null 2>&1; }
sumr() { sum -r $1 | awk '{print $1 + 0}'; }
. $T/host.env

# --- 1. the programs --------------------------------------------------------
$D -V > $T/ver.out 2>&1
has $T/ver.out 'Dropbear v2026.94' && ok "dropbear -V: `cat $T/ver.out`" || bad "dropbear -V: `cat $T/ver.out`"
$B/dbclient -V > $T/ver.out 2>&1
has $T/ver.out 'Dropbear v2026.94' && ok "dbclient -V" || bad "dbclient -V: `cat $T/ver.out`"
for q in kex sig cipher mac; do
	echo "== probe $q: `$D -Q $q 2>&1 | tr '\012' ' '`"
done
$D -Q cipher > $T/q.out 2>&1
if has $T/q.out 'cbc' || has $T/q.out '3des' || has $T/q.out 'aes256'; then
	bad "ciphers offered: `tr '\012' ' ' < $T/q.out`"
else
	ok "ciphers: `tr '\012' ' ' < $T/q.out`"
fi
$D -Q kex > $T/q.out 2>&1
if has $T/q.out 'diffie-hellman' || has $T/q.out 'nistp'; then
	bad "kex offered: `tr '\012' ' ' < $T/q.out`"
else
	ok "kex: `tr '\012' ' ' < $T/q.out`"
fi

# --- 2. O_CREAT|O_EXCL refuses a symbolic link (the build has no O_NOFOLLOW)
rm -f "${T:?}/link" "${T:?}/nothere"
ln -s $T/nothere $T/link
$B/dropbearkey -t ed25519 -f $T/link > /dev/null 2>&1
if [ -f $T/nothere ]; then bad "dropbearkey wrote through a symbolic link"; else ok "dropbearkey refuses a symbolic link"; fi
rm -f "${T:?}/link" "${T:?}/nothere"

# --- 3. the boot script: host key, start ------------------------------------
if [ -c /dev/urandom ]; then ok "/dev/urandom present"; else bad "no /dev/urandom: the random module"; fi
rm -f "${K:?}/host_ed25519" "${K:?}/host_rsa"
t0=`date +%H%M%S`
sh /etc/init.d/dropbear start
t1=`date +%H%M%S`
echo "== probe start (key made, server started) $t0 -> $t1"
if [ -f $K/host_ed25519 ]; then
	ok "host key made: `ls -l $K/host_ed25519 | awk '{print $1, $3, $5}'`"
else
	bad "no host key $K/host_ed25519"
fi
pid=`cat $K/dropbear.pid 2>/dev/null`
if [ -n "$pid" ] && kill -0 $pid 2> /dev/null; then ok "server running, pid $pid"; else bad "server not running"; fi
tail -3 /var/adm/rc.log | sed 's/^/== rc.log /'
has /var/adm/rc.log 'dropbear.*started on port 22' && ok "rc.log: started" || bad "rc.log has no start line"
echo "== probe server ps: `ps -lp $pid | tail -1`"
$B/dropbearkey -y -f $K/host_ed25519 | sed -n 's/^Fingerprint: /== probe host key /p'

# --- 4. the client's key, and the host's key for root ----------------------
rm -f "${T:?}/id_box"
$B/dropbearkey -t ed25519 -f $T/id_box > /dev/null 2>&1
$B/dropbearkey -y -f $T/id_box | grep '^ssh-ed25519 ' > $T/box.pub
has $T/box.pub '^ssh-ed25519 ' && ok "client key made" || bad "client key"
H=`awk -F: '$1 == "root" { print $6 }' /etc/passwd`
[ -d $H/.ssh ] || mkdir $H/.ssh
chmod 700 $H/.ssh
[ -f $H/.ssh/authorized_keys ] && cp $H/.ssh/authorized_keys $T/ak.save
[ -f $H/.ssh/known_hosts ] && cp $H/.ssh/known_hosts $T/kh.save
echo "$HOSTPUB" >> $H/.ssh/authorized_keys
chmod 600 $H/.ssh/authorized_keys

# --- 5. the host's half -------------------------------------------------------
rm -f "${T:?}/done.host"
echo ready > $T/ready.box
n=0
while [ ! -f $T/done.host ] && [ $n -lt 360 ]; do
	sleep 5
	n=`expr $n + 1`
done
if [ -f $T/done.host ]; then ok "host half done: `cat $T/done.host`"; else bad "host half never finished"; fi

# --- 6. this client against the host's OpenSSH (key) ----------------------
U=$HUSER@$HOSTIP
$B/dbclient -y -p $PORT -i $T/id_box $U 'echo dbc-key-ok; uname -s' > $T/c.out 2>&1
has $T/c.out 'dbc-key-ok' && ok "dbclient key login to OpenSSH" || bad "dbclient key login: `tr '\012' ' ' < $T/c.out`"
for c in chacha20-poly1305@openssh.com aes128-ctr; do
	$B/dbclient -p $PORT -i $T/id_box -c $c $U 'echo dbc-c-ok' > $T/c.out 2>&1
	has $T/c.out 'dbc-c-ok' && ok "dbclient cipher $c" || bad "dbclient cipher $c: `tr '\012' ' ' < $T/c.out`"
done
# a refused connection fails at once and says why (patches/04)
NP=`expr $PORT + 100`
$B/dbclient -y -p $NP -i $T/id_box $U true > $T/c.out 2>&1
if has $T/c.out 'Connect failed: Broken [Pp]ipe' || has $T/c.out 'Connect failed: Connection refused'; then
	ok "dbclient to a closed port: `tr '\012' ' ' < $T/c.out`"
else
	bad "dbclient to a closed port: `tr '\012' ' ' < $T/c.out`"
fi
dd if=/dev/zero bs=1024 count=256 2> /dev/null | tr '\000' 'x' > $T/blob
echo tail >> $T/blob
$B/scp -P $PORT -i $T/id_box $T/blob $U:$HDIR/from-box > $T/s.out 2>&1
$B/scp -P $PORT -i $T/id_box $U:$HDIR/from-box $T/back > $T/s2.out 2>&1
if cmp $T/blob $T/back > /dev/null 2>&1; then ok "scp box -> host -> box, `sumr $T/blob`"; else bad "scp round trip: `cat $T/s.out $T/s2.out | tr '\012' ' '`"; fi
$B/scp -P $PORT -i $T/id_box $U:$HDIR/to-box $T/to-box > $T/s.out 2>&1
got=`sumr $T/to-box 2>/dev/null`
[ "$got" = "$TOBOXSUM" ] && ok "scp host -> box, sum $got" || bad "scp host -> box: got '$got' want '$TOBOXSUM' `tr '\012' ' ' < $T/s.out`"

# --- 7. this client against this server (password) ---------------------------
DROPBEAR_PASSWORD=$ROOTPASS $B/dbclient -y -p 22 root@127.0.0.1 'echo dbc-pw-ok' > $T/c.out 2>&1
has $T/c.out 'dbc-pw-ok' && ok "dbclient password login to dropbear" || bad "password login: `tr '\012' ' ' < $T/c.out`"
DROPBEAR_PASSWORD=not-the-password $B/dbclient -T -p 22 -o BatchMode=yes root@127.0.0.1 'echo dbc-bad-ok' > $T/c.out 2>&1
if has $T/c.out 'dbc-bad-ok'; then bad "a wrong password logged in"; else ok "wrong password refused"; fi

# --- 8. stop -----------------------------------------------------------------------
sh /etc/init.d/dropbear stop
sleep 2
if kill -0 $pid 2> /dev/null; then bad "server still running after stop"; else ok "server stopped"; fi
[ -f $K/dropbear.pid ] && bad "pid file left" || ok "pid file removed"

# --- cleanup: root's keys as they were; the host keys go, so pkgrm leaves no
# directory behind (on a real machine they stay)
if [ -f $T/ak.save ]; then cp $T/ak.save $H/.ssh/authorized_keys; else rm -f "${H:?}/.ssh/authorized_keys"; fi
if [ -f $T/kh.save ]; then cp $T/kh.save $H/.ssh/known_hosts; else rm -f "${H:?}/.ssh/known_hosts"; fi
rm -f "${K:?}/host_ed25519" "${K:?}/host_rsa"
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
exit $fails
