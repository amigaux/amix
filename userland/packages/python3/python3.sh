#!/bin/sh
# python3 -- start Python 3.11.  CPython seeds its hash randomisation from
# /dev/urandom at startup and stops if it cannot; until the random driver is
# installed, fall back to a fixed seed.  Drop this wrapper once it ships.
if [ -z "$PYTHONHASHSEED" ] && dd if=/dev/urandom of=/dev/null bs=1 count=1 2>/dev/null; then
	:
elif [ -z "$PYTHONHASHSEED" ]; then
	PYTHONHASHSEED=0; export PYTHONHASHSEED
fi
exec /opt/amix/bin/python3.11 "$@"
