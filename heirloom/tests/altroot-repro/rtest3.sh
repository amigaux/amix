#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
LOG=/tmp/rtest3.log
: > $LOG
PKG=/tmp/APKG-0.1.pkg; ADM=/tmp/adm; E=/usr/apkg/bin/pkgadd
mk() { rm -rf $1; mkdir -p $1/etc; cp /etc/passwd $1/etc/; cp /etc/group $1/etc/; }

# 1: DS_DEBUG on, output DISCARDED -> is it the code path or the I/O?
mk /tmp/q1; DS_DEBUG=1 $E -R /tmp/q1 -n -a $ADM -d $PKG APKG > /dev/null 2>&1
echo "dsdebug+devnull rc=$?" >> $LOG

# 2: DS_DEBUG set to 0 -- does the mere presence of the var matter?
mk /tmp/q2; DS_DEBUG=0 $E -R /tmp/q2 -n -a $ADM -d $PKG APKG > /dev/null 2>&1
echo "DS_DEBUG=0 rc=$?" >> $LOG

# 3: plain, but capture a core if one drops
mk /tmp/q3; cd /tmp/q3; rm -f core
$E -R /tmp/q3 -n -a $ADM -d $PKG APKG > /tmp/q3out 2>&1
echo "plain rc=$? core=`ls -l core 2>/dev/null | wc -l` outbytes=`wc -c < /tmp/q3out`" >> $LOG

# 4: no -R at all -- does a normal install to / work? (isolates -R itself)
$E -n -a $ADM -d $PKG APKG > /tmp/q4out 2>&1
echo "no-R rc=$? outbytes=`wc -c < /tmp/q4out`" >> $LOG

echo "--- tail of the no-R output ---" >> $LOG
tail -5 /tmp/q4out >> $LOG 2>&1
echo COMPLETE >> $LOG
