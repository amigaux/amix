# contents-fsck — SVR4 contents(4) DB checker/repairer (amix-packagemanager)
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Targets:
#   host   (default) build ./contents-fsck with the host gcc, strict C89
#   amix   cross-build ./contents-fsck.amix for Amix (m68k SVR4)
#          (sources CROSS_ENV, default $(GCA)/env.sh -- gcc-cross-amix at
#           amix's toolchain/gcc-cross-amix.pin -- if it is not on PATH)
#   test   run the test suite (builds host first)
#   kat    build + mechanically verify the known-answer branch/switch
#          battery for the cross pipeline (tests/kat-branch.c)
#   clean
#
# The amix binary is built with a SELF-CONTAINED pipeline (no dependence on
# the shared amix-gcc-wrapper.sh):
#   gcc.real -S  ->  tools/asmfix.pl  ->  as -m68020  ->  static ld
# asmfix.pl carries the wrapper's asm fixups PLUS the .swbeg jump-table fix
# (see tools/asmfix.pl and tools/wrapper-swbeg.patch): GNU as emits 0 bytes
# for the SGS ".swbeg" directive that gcc's switch dispatch assumes is 4
# bytes, so without the fix every switch case is entered 4 bytes late on
# stale condition codes.
#
# The link is STATIC against the image's own /usr/ccs/lib/libc.a
# (+ crt1/crti/crtn).  Dynamic linking of GNU-ld-built binaries against the
# 1991 SVR4.0 runtime linker is unproven: GNU ld emits R_68K_COPY
# relocations for __ctype/__iob — a pattern no native Amix binary uses —
# plus a GNU-format PLT the AT&T rtld never saw.  Static linking removes
# the runtime linker from the picture entirely.

HOST_CC       = gcc
HOST_CFLAGS   = -std=c89 -pedantic -Wall -Wextra -O2

CROSS_GCCREAL = m68k-cbm-sysv4-gcc.real
CROSS_AS      = m68k-cbm-sysv4-as
CROSS_LD      = m68k-cbm-sysv4-ld
CROSS_CFLAGS  = -O
CROSS_ENV    ?= $(if $(GCA),$(GCA)/env.sh)
CROSS_SYSROOT = $(HOME)/opt/amix-cross/m68k-cbm-sysv4/sysroot
CROSS_CRTDIR  = $(CROSS_SYSROOT)/usr/ccs/lib

SRC = contents-fsck.c

all: host

host: contents-fsck

contents-fsck: $(SRC)
	$(HOST_CC) $(HOST_CFLAGS) -o $@ $(SRC)

amix: contents-fsck.amix

contents-fsck.amix: $(SRC) tools/asmfix.pl
	@( command -v $(CROSS_GCCREAL) >/dev/null 2>&1 || \
	    { [ -n "$(CROSS_ENV)" ] && [ -r "$(CROSS_ENV)" ] || \
	      { echo "no cross toolchain: set GCA to the build/ directory of" \
	        "gcc-cross-amix at toolchain/gcc-cross-amix.pin, or CROSS_ENV" \
	        "to its env.sh" >&2; exit 1; }; \
	      echo "sourcing $(CROSS_ENV)"; . $(CROSS_ENV); }; \
	  set -e; \
	  $(CROSS_GCCREAL) -S $(CROSS_CFLAGS) \
		-I$(CROSS_SYSROOT)/usr/include \
		-o contents-fsck.amix.s $(SRC); \
	  perl tools/asmfix.pl contents-fsck.amix.s; \
	  $(CROSS_AS) -m68020 -o contents-fsck.amix.o contents-fsck.amix.s; \
	  $(CROSS_LD) -o $@ \
		$(CROSS_CRTDIR)/crt1.o $(CROSS_CRTDIR)/crti.o \
		contents-fsck.amix.o \
		$(CROSS_CRTDIR)/libc.a \
		$(CROSS_CRTDIR)/crtn.o )
	@rm -f contents-fsck.amix.o contents-fsck.amix.s
	file $@

test: host
	sh tests/run-tests.sh

kat:
	sh tests/kat-verify.sh

clean:
	rm -f contents-fsck contents-fsck.amix contents-fsck.amix.o
	rm -f contents-fsck.amix.s
	rm -rf tests/out

.PHONY: all host amix test kat clean
