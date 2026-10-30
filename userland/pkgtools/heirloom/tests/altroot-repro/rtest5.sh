#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Per-region DS_DEBUG bisection A/B harness (amix-packagemanager).
# Empty alt-root (no etc/group) -> add_cache SIGSEGV unless the named
# region's instrumentation is present.  4 runs per configuration.
E=/usr/apkg/bin/pkgadd; P=/tmp/APKG-0.1.pkg; A=/tmp/adm
LOG=/tmp/rtest5.log; : >$LOG
CORE=var/sadm/install/core
run() {   # $1=label  $2=env-assignment (empty for plain)
  i=1
  while [ $i -le 4 ]; do
    R=/tmp/z_$i; rm -rf $R; mkdir -p $R
    env $2 $E -R $R -n -a $A -d $P APKG >/tmp/zo 2>&1
    rc=$?
    c=`ls -l $R/$CORE 2>/dev/null | awk '{print $5}'`
    echo "$1 run$i rc=$rc core=${c:-none}" >>$LOG
    rm -rf $R
    i=`expr $i + 1`
  done
}
run "plain    " ""
run "DS_DEBUG " "DS_DEBUG=1"
run "DBG_MAIN " "DBG_MAIN=1"
run "DBG_MNT  " "DBG_MNT=1"
run "DBG_LOCK " "DBG_LOCK=1"
run "DBG_MERG " "DBG_MERG=1"
run "DBG_ESYS " "DBG_ESYS=1"
run "DBG_CGR  " "DBG_CGR=1"
run "DBG_DS   " "DBG_DS=1"
echo COMPLETE >>$LOG
