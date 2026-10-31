#!/bin/sh
#
# smoke.sh -- Python 3.11 acceptance, ON THE BOX.
#
#     sh tests/smoke.sh [prefix]          (default /opt/amix)
#
# tests/smoke.py through the python3 wrapper (whatever /dev/urandom does), then
# the wrapper's fallback: with no PYTHONHASHSEED set it must start.  1992 Bourne
# shell.  Result lines start with "RES "; the last is "RES smoke PASS" or
# "RES smoke FAIL <n>".

X=${1:-/opt/amix}
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }

H=`pwd`
rm -rf pysmoke; mkdir pysmoke; cd pysmoke || exit 1
if dd if=/dev/urandom of=/dev/null bs=1 count=1 2>/dev/null; then
	ok "/dev/urandom readable: hash randomisation on"
else
	ok "/dev/urandom not readable: the wrapper uses PYTHONHASHSEED=0"
fi
PYTHONHASHSEED= ; unset PYTHONHASHSEED
$X/bin/python3 -c 'import sys; print(sys.flags.hash_randomization)' > hr.out 2>&1 &&
	ok "python3 starts with no PYTHONHASHSEED (hash_randomization `cat hr.out`)" || bad "python3 did not start: `cat hr.out`"
$X/bin/python3 "$H/tests/smoke.py" > py.out 2>&1; rc=$?
cat py.out
[ $rc -eq 0 ] && ok "smoke.py rc 0" || bad "smoke.py rc $rc"

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
