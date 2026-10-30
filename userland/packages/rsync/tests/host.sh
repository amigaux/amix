#!/bin/bash
#
# host.sh -- the HOST side of rsync's on-box acceptance (tools/pkg-smoke/
# host-extra.sh runs it; bash, on the bench host, never on the box).
#
#     host.sh pre    before the stage is pushed: build the host tree, start a
#                    host rsync daemon on the bench bridge, start the
#                    background peer, print KEY=value lines for the guest
#     host.sh post   after guest.sh: stop the daemon and the peer, print
#                    the peer's log
#
# Env (host-extra.sh): HOSTWORK (scratch for this cell), AMIX_HOST (the
# guest), RIG_GW (the bench bridge, where the host daemon listens), RIG_SLOT.  The modern peer is the host's own rsync (3.4.x,
# protocol 32).  Every verdict is the box's: the peer hands the box what
# it measured (sum -r lists) and smoke.sh compares.

set -u
W=$HOSTWORK
HOSTIP=${RIG_GW:?host.sh: no RIG_GW (the bench bridge address; host-extra.sh sets it)}
PORT=$((8870 + RIG_SLOT))

# "<sum -r> <path>" for every regular file under $1, by path
sums() { ( cd "$1" && find . -type f ! -name done | LC_ALL=C sort | while read -r f; do
	echo "$(sum -r "$f" | awk '{print $1 + 0}') $f"; done ); }

case "$1" in
pre)
	rm -rf "$W"; mkdir -p "$W/mod/src" "$W/mod/up" "$W/tobox"
	python3 -I - "$W/mod/src" <<'EOF'
import os, sys, random
r = random.Random(31)
d = sys.argv[1]
os.makedirs(d + "/sub/deep")
os.makedirs(d + "/many")
# 1 MiB of incompressible-ish bytes: the delta and the rolling checksum
open(d + "/big.bin", "wb").write(bytes(r.getrandbits(8) for _ in range(1 << 20)))
# text that compresses (-z)
with open(d + "/text.txt", "w") as f:
    for i in range(20000):
        f.write("%05d line of text %d\n" % (i, i * 13))
open(d + "/empty", "w").close()
open(d + "/sub/a.txt", "w").write("alpha\n")
open(d + "/sub/deep/b.txt", "w").write("beta\n")
for i in range(1500):
    open(d + "/many/f%04d" % i, "w").write("file %d\n" % i * (i % 7 + 1))
os.symlink("sub/a.txt", d + "/link")
os.chmod(d + "/sub/a.txt", 0o640)
os.utime(d + "/sub/a.txt", (981173106, 981173106))
EOF
	sums "$W/mod/src" > "$W/mod/SUMS"
	cat > "$W/rsyncd.conf" <<EOF
pid file = $W/rsyncd.pid
log file = $W/rsyncd.log
use chroot = no
[pks]
	path = $W/mod
	read only = no
EOF
	# stdin a socket would send rsync --daemon down its inetd path (no detach)
	rsync --daemon --config="$W/rsyncd.conf" --address=$HOSTIP --port=$PORT < /dev/null ||
		{ echo "host.sh: the host rsync daemon did not start" >&2; exit 1; }
	# the peer: waits for the box's daemon (module bd), pulls it, pushes
	# what the box checks (in/ and the sum lists), then the `done' marker
	(
		B=rsync://$AMIX_HOST/bd
		for i in $(seq 1 360); do
			timeout 10 rsync "rsync://$AMIX_HOST/" 2>/dev/null | grep -q '^bd' && break
			sleep 5
		done
		echo "peer: box daemon seen after ~$((i * 5)) s: $(timeout 10 rsync "rsync://$AMIX_HOST/" 2>&1 | tr '\n' ' ')"
		rsync -a --stats "$B/tree/" "$W/frombox/" > "$W/peer-pull.log" 2>&1
		echo "peer: pull from the box daemon rc=$?"
		mkdir -p "$W/tobox/in"
		cp -a "$W/mod/src/." "$W/tobox/in/"
		sums "$W/frombox" > "$W/tobox/hsums.box"
		sums "$W/mod/up" > "$W/tobox/hsums.up"
		cp "$W/peer-pull.log" "$W/tobox/peer-pull.log"
		rsync -rlt --stats "$W/tobox/" "$B/" > "$W/peer-push.log" 2>&1
		echo "peer: push to the box daemon rc=$?"
		echo done > "$W/done"
		rsync -t "$W/done" "$B/done" > /dev/null 2>&1
		echo "peer: marker rc=$?"
	) > "$W/peer.log" 2>&1 &
	echo $! > "$W/peer.pid"
	echo "HOSTIP=$HOSTIP"
	echo "PORT=$PORT"
	;;
post)
	[ -f "$W/rsyncd.pid" ] && kill "$(cat "$W/rsyncd.pid")" 2>/dev/null
	[ -f "$W/peer.pid" ] && kill "$(cat "$W/peer.pid")" 2>/dev/null
	echo "== host peer log"; cat "$W/peer.log" 2>/dev/null
	echo "== host daemon log (tail)"; tail -20 "$W/rsyncd.log" 2>/dev/null
	;;
*)
	echo "usage: host.sh pre|post" >&2; exit 2 ;;
esac
