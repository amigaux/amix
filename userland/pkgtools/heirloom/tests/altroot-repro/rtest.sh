#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Wave 1 box phase: does pkgadd -R misbehave, and does <root>/etc/group decide it?
# A = EMPTY altroot  -> clgrnam() fopen fails, returns NULL, dup_gr_ent never runs
# B = SEEDED altroot -> clgrnam() path fully executes (the -R-exclusive code)
LOG=/tmp/rtest.log
: > $LOG
PKG=/tmp/APKG-0.1.pkg
ADM=/tmp/adm
E=/usr/apkg/bin/pkgadd

echo "=== engine ===" >> $LOG
ls -l $E >> $LOG 2>&1

echo "=== A: EMPTY altroot ===" >> $LOG
rm -rf /tmp/rA; mkdir -p /tmp/rA
$E -R /tmp/rA -n -a $ADM -d $PKG APKG >> $LOG 2>&1
echo "A rc=$?" >> $LOG
ls /tmp/rA >> $LOG 2>&1

echo "=== B: SEEDED altroot (etc/passwd + etc/group present) ===" >> $LOG
rm -rf /tmp/rB; mkdir -p /tmp/rB/etc
cp /etc/passwd /tmp/rB/etc/passwd
cp /etc/group  /tmp/rB/etc/group
echo "--- seeded group file (multi-member check) ---" >> $LOG
grep bin /tmp/rB/etc/group >> $LOG 2>&1
$E -R /tmp/rB -n -a $ADM -d $PKG APKG >> $LOG 2>&1
echo "B rc=$?" >> $LOG
ls /tmp/rB >> $LOG 2>&1

echo "=== C: SEEDED + DS_DEBUG ===" >> $LOG
rm -rf /tmp/rC; mkdir -p /tmp/rC/etc
cp /etc/passwd /tmp/rC/etc/passwd
cp /etc/group  /tmp/rC/etc/group
DS_DEBUG=1 $E -R /tmp/rC -n -a $ADM -d $PKG APKG >> $LOG 2>&1
echo "C rc=$?" >> $LOG
echo COMPLETE >> $LOG
