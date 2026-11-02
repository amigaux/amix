#!/bin/bash
#
# host.sh -- the HOST side of Dropbear's on-box acceptance (bash, on the
# bench host, never on the box).
#
#     host.sh pre    start a throwaway OpenSSH sshd on the bench bridge (own
#                    user, own host key, keys only), make the files and the
#                    key the box needs; print KEY=value lines for
#                    tests/host.env
#     host.sh run    when the box's smoke.sh says ready: OpenSSH's ssh and
#                    scp against the box's dropbear (key, password, each
#                    algorithm offered and some refused, scp both ways,
#                    timings); take the box's client key into the sshd's
#                    authorized_keys; tell the box it may go on
#     host.sh post   stop the sshd, print its log
#
# Env: HOSTWORK (scratch for this cell), AMIX_HOST (the box), RIG_GW (the
# bench bridge: the sshd listens there and nowhere else), RIG_SLOT,
# AMIX_PASS (the box's root password), KT (the directory of amixrun.py and
# amixsync.py), W (the box directory smoke.sh runs in).
# Lines starting "RES " are verdicts, "TIMING " measurements (an emulator's
# figures are relative only).

set -u
H=$HOSTWORK
HOSTIP=${RIG_GW:?host.sh: no RIG_GW (the bench bridge address)}
PORT=$((22600 + ${RIG_SLOT:-0}))
SSH="ssh -F /dev/null -o UserKnownHostsFile=$H/known_hosts -o StrictHostKeyChecking=accept-new -o ConnectTimeout=120"
box() { python3 "${KT:?}/amixrun.py" "$@"; }

case "$1" in
pre)
	rm -rf -- "${H:?}"; mkdir -p "$H/up"
	chmod 700 "$H"
	ssh-keygen -q -t ed25519 -N '' -C bench-sshd -f "$H/sshd_key"
	ssh-keygen -q -t ed25519 -N '' -C bench-client -f "$H/client"
	: > "$H/authorized_keys"
	chmod 600 "$H/authorized_keys"
	cat > "$H/sshd_config" <<EOF
ListenAddress $HOSTIP:$PORT
HostKey $H/sshd_key
PidFile $H/sshd.pid
AuthorizedKeysFile $H/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
UsePAM no
StrictModes no
EOF
	/usr/sbin/sshd -f "$H/sshd_config" -E "$H/sshd.log" ||
		{ echo "host.sh: sshd did not start" >&2; exit 1; }
	head -c 300000 /dev/urandom > "$H/up/to-box"
	echo "HOSTIP=$HOSTIP"
	echo "PORT=$PORT"
	echo "HUSER=$(id -un)"
	echo "HDIR=$H/up"
	echo "ROOTPASS=${AMIX_PASS:?}"
	echo "TOBOXSUM=$(sum -r "$H/up/to-box" | awk '{print $1 + 0}')"
	echo "HOSTPUB='$(cat "$H/client.pub")'"
	;;
run)
	B=root@$AMIX_HOST
	K="-i $H/client -o PasswordAuthentication=no -o BatchMode=yes"
	# key login on a pty; who shows the session (utmpx written for it).
	# stdin stays open: at the client's EOF the server closes the pty
	# (upstream), which hangs the command up
	out=$($SSH -tt $K $B 'echo key-ok; tty; who; exec < /dev/tty && echo ctty-ok' 2>&1 < <(sleep 120) | tr -d '\r')
	echo "$out" | sed 's/^/== /'
	echo "$out" | grep -q key-ok && echo "RES ok   OpenSSH key login" || echo "RES FAIL OpenSSH key login"
	echo "$out" | grep -q "^/dev/pts/" && echo "RES ok   the session has a pty" || echo "RES FAIL no pty for the session"
	echo "$out" | grep -q "^root .*pts" && echo "RES ok   who shows the ssh session" || echo "RES FAIL who: no pts session"
	echo "$out" | grep -q "^ctty-ok" && echo "RES ok   the pty is the controlling tty" || echo "RES FAIL no controlling tty"
	# the client's terminal: script(1) gives ssh a pty of 33x99 whose
	# modes (intr ^C, erase DEL) the server must set on the session's
	out=$(script -qec "stty rows 33 cols 99; $SSH -tt $K $B 'stty -a'" /dev/null 2>&1 < <(sleep 120) | tr -d '\r')
	echo "$out" | sed 's/^/== /'
	echo "$out" | grep -q "rows = 33; columns = 99" && echo "RES ok   window size taken" || echo "RES FAIL window size"
	echo "$out" | grep -q "intr = ^c" && echo "RES ok   terminal modes taken" || echo "RES FAIL terminal modes"
	# password login
	out=$(sshpass -p "$AMIX_PASS" $SSH -o PubkeyAuthentication=no -o PreferredAuthentications=password $B 'echo pw-ok' 2>&1)
	echo "$out" | grep -q pw-ok && echo "RES ok   OpenSSH password login" || echo "RES FAIL OpenSSH password login: $out"
	out=$(sshpass -p wrong $SSH -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 $B 'echo bad-ok' 2>&1)
	echo "$out" | grep -q bad-ok && echo "RES FAIL a wrong password logged in" || echo "RES ok   wrong password refused"
	# every pair offered: handshake and 1 MiB each way, timed
	head -c 1048576 /dev/urandom > "$H/mib"
	for kex in mlkem768x25519-sha256 curve25519-sha256; do
		for c in chacha20-poly1305@openssh.com aes128-ctr; do
			o="$K -o KexAlgorithms=$kex -o Ciphers=$c -o MACs=hmac-sha2-256"
			t0=$(date +%s.%N)
			for i in 1 2 3; do $SSH $o $B true > /dev/null 2>&1 || echo "RES FAIL $kex $c handshake $i"; done
			t1=$(date +%s.%N)
			$SSH $o $B 'cat > /usr/tmp/mib' < "$H/mib" 2>/dev/null
			t2=$(date +%s.%N)
			$SSH $o $B 'cat /usr/tmp/mib' > "$H/mib.back" 2>/dev/null
			t3=$(date +%s.%N)
			if cmp -s "$H/mib" "$H/mib.back"; then echo "RES ok   $kex $c"; else echo "RES FAIL $kex $c: 1 MiB round trip"; fi
			echo "TIMING $kex $c handshake3 $(echo "$t1 - $t0" | bc) up1MiB $(echo "$t2 - $t1" | bc) down1MiB $(echo "$t3 - $t2" | bc)"
		done
	done
	$SSH $K $B 'rm -f /usr/tmp/mib' > /dev/null 2>&1
	# what is not offered is refused (a MAC only with a cipher that needs one)
	for o in "-o KexAlgorithms=diffie-hellman-group14-sha256" "-o KexAlgorithms=ecdh-sha2-nistp256" \
	         "-o Ciphers=aes256-ctr" "-o Ciphers=aes128-gcm@openssh.com" "-o Ciphers=aes128-cbc" \
	         "-o Ciphers=aes128-ctr -o MACs=hmac-sha1" "-o HostKeyAlgorithms=ecdsa-sha2-nistp256"; do
		if $SSH $K $o $B true > /dev/null 2>&1; then echo "RES FAIL accepted: $o"; else echo "RES ok   refused: $o"; fi
	done
	# OpenSSH's scp, the original protocol (-O): no SFTP on the box
	head -c 200000 /dev/urandom > "$H/scp-up"
	if scp -O -F /dev/null -o UserKnownHostsFile="$H/known_hosts" $K "$H/scp-up" "$B:/usr/tmp/scp-up" > /dev/null 2>&1 &&
	   scp -O -F /dev/null -o UserKnownHostsFile="$H/known_hosts" $K "$B:/usr/tmp/scp-up" "$H/scp-back" > /dev/null 2>&1 &&
	   cmp -s "$H/scp-up" "$H/scp-back"; then
		echo "RES ok   OpenSSH scp -O both ways"
	else
		echo "RES FAIL OpenSSH scp -O"
	fi
	$SSH $K $B 'rm -f /usr/tmp/scp-up' > /dev/null 2>&1
	# the box's client key, for smoke.sh's half; then let it go on
	box "cat ${W:?}/tests/box.pub" | grep '^ssh-ed25519 ' >> "$H/authorized_keys"
	grep -q '^ssh-ed25519 ' "$H/authorized_keys" && echo "RES ok   box key taken" || echo "RES FAIL no box key"
	box "echo done > $W/tests/done.host"
	;;
post)
	[ -f "$H/sshd.pid" ] && kill "$(cat "$H/sshd.pid")" 2>/dev/null
	[ -f "$H/up/from-box" ] && echo "RES ok   from-box arrived, $(wc -c < "$H/up/from-box") bytes" || echo "RES FAIL no from-box"
	echo "== sshd log"; cat "$H/sshd.log" 2>/dev/null
	;;
*)
	echo "usage: host.sh pre|run|post" >&2; exit 2 ;;
esac
