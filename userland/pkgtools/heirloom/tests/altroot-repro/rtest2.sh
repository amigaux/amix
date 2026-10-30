#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Discriminate: does DS_DEBUG change the outcome, or do early runs just fail?
# Alternate instrumented/uninstrumented so order and flag are separable.
LOG=/tmp/rtest2.log
: > $LOG
PKG=/tmp/APKG-0.1.pkg; ADM=/tmp/adm; E=/usr/apkg/bin/pkgadd
n=1
while [ $n -le 8 ]; do
  R=/tmp/rr$n
  rm -rf $R; mkdir -p $R/etc
  cp /etc/passwd $R/etc/passwd; cp /etc/group $R/etc/group
  case $n in
    1|3|5|7) MODE=plain;  $E -R $R -n -a $ADM -d $PKG APKG > /tmp/o$n 2>&1 ;;
    *)       MODE=dsdebug; DS_DEBUG=1 $E -R $R -n -a $ADM -d $PKG APKG > /tmp/o$n 2>&1 ;;
  esac
  RC=$?
  BYTES=`wc -c < /tmp/o$n`
  echo "run $n mode=$MODE rc=$RC outbytes=$BYTES" >> $LOG
  n=`expr $n + 1`
done
echo COMPLETE >> $LOG
