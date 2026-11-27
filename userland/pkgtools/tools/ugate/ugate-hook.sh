#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# ugate-hook.sh -- the user-path gate's per-boot host hook: the row runner's --host-extra (kerntools' rig-run calls
# it with RIG_SLOT, RIG_CELL, RIG_BOOT). ugate.sh sets the rest in the environment:
#   UGATE_DIR      this directory            UGATE_URL     the candidate repository as the box reaches it
#   UGATE_ROWDIR   the row's work dir (cmds) UGATE_SESSION none | a name handed to UGATE_SESSION_HOOK
#   UGATE_SLOT_ENV a command that prints AMIX_HOST=<address> for a slot number given as its argument
#   UGATE_AMIXRUN, UGATE_AMIXSYNC  the box-talk tools; AMIX_PASS the box's root password
# Every boot: the booted kernel (uname -a) into boot<N>-uname.txt. Boot 1: push box/ugate-box.sh and the row's
# commands to /var/ugate, start it, wait for READY, pull the results into the cell's ugate/. Boot 2 and later: the
# session check, when the row names one (UGATE_SESSION_HOOK, run with UGATE_SESSION set; its status is this hook's).
set -u
: "${RIG_SLOT:?}" "${RIG_CELL:?}" "${UGATE_DIR:?}" "${UGATE_URL:?}" "${UGATE_ROWDIR:?}" "${UGATE_SLOT_ENV:?}"
B=${RIG_BOOT:-1}; C=$RIG_CELL; BX=/var/ugate
AMIX_HOST=$($UGATE_SLOT_ENV "$RIG_SLOT" | sed -n 's/^AMIX_HOST=//p' | head -1)
[ -n "$AMIX_HOST" ] || { echo "ugate-hook: no AMIX_HOST for slot $RIG_SLOT"; exit 1; }
export AMIX_HOST AMIX_PASS=${AMIX_PASS:?} AMIX_CMD_TIMEOUT=1200
R() { timeout 1300 python3 "${UGATE_AMIXRUN:?}" "$@" 2>&1 | tr -d '\r'; }
P() { timeout 900 python3 "${UGATE_AMIXSYNC:?}" "$@" 2>&1 | tail -1; }
log() { echo "$(date +%T) $*"; }
mkdir -p "$C/ugate"
# uname -a, and the installed kernel package's version (a k30 kernel's uname names no version; after the power
# cycle the installed kernel is the booted one)
R "uname -a; pkginfo -l kern30m kern46m 2>/dev/null | sed -n 's/^ *VERSION: */kernel package /p'" |
	grep -v '^#\|uname -a\|DONE_' | grep . > "$C/ugate/boot$B-uname.txt"
log "boot $B: $(tr '\n' ' ' < "$C/ugate/boot$B-uname.txt")"
if [ "$B" != 1 ]; then
	[ "${UGATE_SESSION:-none}" = none ] && exit 0
	log "session ${UGATE_SESSION}: ${UGATE_SESSION_HOOK:?a row names a session and no UGATE_SESSION_HOOK is set}"
	export UGATE_SESSION
	bash -c "$UGATE_SESSION_HOOK"; rc=$?
	log "session ${UGATE_SESSION} rc=$rc"
	exit $rc
fi
log "push: $(R "rm -rf $BX; mkdir $BX" > /dev/null; P push "$UGATE_DIR/box/ugate-box.sh" $BX/ugate-box.sh; P push "$UGATE_ROWDIR/cmds" $BX/cmds)"
R "cd $BX && (nohup sh ugate-box.sh $UGATE_URL > box.log 2>&1 < /dev/null &); echo started" > /dev/null
j=0; r=
while [ $j -lt "${UGATE_BOX_WAIT:-7200}" ]; do
	r=$(R "cat $BX/READY 2>/dev/null" | grep '^READY' | head -1)
	[ -n "$r" ] && break
	sleep 30; j=$((j + 30))
done
log "box: ${r:-no READY in ${UGATE_BOX_WAIT:-7200} s}"
P pull $BX "$C/ugate" > /dev/null 2>&1	# lands as ugate/ugate (the remote dir's name)
[ -d "$C/ugate/ugate" ] && mv "$C/ugate/ugate" "$C/ugate/box"
log "results: $(tr '\t' ' ' < "$C/ugate/box/results" 2>/dev/null | tr '\n' '|')"
case "$r" in READY*) exit 0;; *) exit 1;; esac
