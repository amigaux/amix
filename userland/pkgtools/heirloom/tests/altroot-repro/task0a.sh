#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
E=/usr/apkg/bin/pkgadd; P=/tmp/APKG-0.1.pkg; A=/tmp/adm
LOG=/tmp/t0a.log; : >$LOG
CORE=var/sadm/install/core

# 1 empty root, plain  (expect SIGSEGV/core, rc!=0)
rm -rf /tmp/e1; mkdir -p /tmp/e1
$E -R /tmp/e1 -n -a $A -d $P APKG >/tmp/e1o 2>&1
echo "empty-plain    rc=$? bytes=`wc -c </tmp/e1o` core=`ls -l /tmp/e1/$CORE 2>/dev/null|awk '{print $5}'`" >>$LOG

# 2 empty root, DS_DEBUG=1 (expect suppressed rc=0, no core)
rm -rf /tmp/e2; mkdir -p /tmp/e2
DS_DEBUG=1 $E -R /tmp/e2 -n -a $A -d $P APKG >/tmp/e2o 2>&1
echo "empty-dsdebug1 rc=$? bytes=`wc -c </tmp/e2o` core=`ls -l /tmp/e2/$CORE 2>/dev/null|awk '{print $5}'`" >>$LOG

# 3 empty root, DS_DEBUG=0 (presence check)
rm -rf /tmp/e3; mkdir -p /tmp/e3
DS_DEBUG=0 $E -R /tmp/e3 -n -a $A -d $P APKG >/tmp/e3o 2>&1
echo "empty-dsdebug0 rc=$? bytes=`wc -c </tmp/e3o` core=`ls -l /tmp/e3/$CORE 2>/dev/null|awk '{print $5}'`" >>$LOG

# 4 empty root, ZZQQ=1 (unrelated env: code-path vs env-block-layout)
rm -rf /tmp/e4; mkdir -p /tmp/e4
ZZQQ=1 $E -R /tmp/e4 -n -a $A -d $P APKG >/tmp/e4o 2>&1
echo "empty-ZZQQ1    rc=$? bytes=`wc -c </tmp/e4o` core=`ls -l /tmp/e4/$CORE 2>/dev/null|awk '{print $5}'`" >>$LOG

# 5 no -R (install to /, expect rc=0)
$E -n -a $A -d $P APKG >/tmp/e5o 2>&1
echo "no-R           rc=$? bytes=`wc -c </tmp/e5o`" >>$LOG
echo COMPLETE >>$LOG
