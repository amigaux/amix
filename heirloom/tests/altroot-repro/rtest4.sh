#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
LOG=/tmp/rtest4.log
: > $LOG
PKG=/tmp/APKG-0.1.pkg; ADM=/tmp/adm; E=/usr/apkg/bin/pkgadd
mk() { rm -rf $1; mkdir -p $1/etc; cp /etc/passwd $1/etc/; cp /etc/group $1/etc/; }

# Does DS_DEBUG=0 actually emit debug output? (presence-check vs value-check)
mk /tmp/p1; DS_DEBUG=0 $E -R /tmp/p1 -n -a $ADM -d $PKG APKG > /tmp/p1o 2>&1
echo "DS_DEBUG=0        rc=$? outbytes=`wc -c < /tmp/p1o`" >> $LOG

# An UNRELATED env var of similar size. If this also fixes it, DS_DEBUG is irrelevant
# and the real variable is the size/layout of the environment block.
mk /tmp/p2; ZZQQ=1 $E -R /tmp/p2 -n -a $ADM -d $PKG APKG > /tmp/p2o 2>&1
echo "ZZQQ=1            rc=$? outbytes=`wc -c < /tmp/p2o`" >> $LOG

# A longer unrelated var
mk /tmp/p3; ZZQQ=111111111111111111111111111111 $E -R /tmp/p3 -n -a $ADM -d $PKG APKG > /tmp/p3o 2>&1
echo "ZZQQ=30chars      rc=$? outbytes=`wc -c < /tmp/p3o`" >> $LOG

# Control: plain again, to confirm it still fails in this same session
mk /tmp/p4; $E -R /tmp/p4 -n -a $ADM -d $PKG APKG > /tmp/p4o 2>&1
echo "plain(control)    rc=$? outbytes=`wc -c < /tmp/p4o`" >> $LOG
echo COMPLETE >> $LOG
