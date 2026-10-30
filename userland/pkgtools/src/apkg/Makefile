# Makefile for apkg - remote package client for Amiga Unix (Amix).
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see LICENSE.
#
# Two build flavours:
#
#   make / make host    native build on the Linux host; this is the
#                       functional-test vehicle (make test).
#   make amix           cross build with m68k-cbm-sysv4-gcc.  Source
#                       the toolchain env first:
#                       . <gcc-cross-amix>/build/env.sh
#
# Byte order: md5.c needs -DHIGHFIRST on big-endian machines.  The
# amix target (m68k = MSB) sets it; the host target assumes a
# little-endian host.  Building the host tools on a big-endian host?
# Add HOST_ENDIAN_FLAGS=-DHIGHFIRST.
#
# sha256.c, sha256.h and axtypes.h are kernel/dlm's loader/common SHA-256
# (FIPS 180-4, C89), copied verbatim from kernel/dlm 656d155 and kept
# byte-identical; update them only by copying again.
#
# Amix link notes (all discovered against the real sysroot + bench):
#   - libsocket.SO lacks link closure under GNU ld 2.8.1 (its internal
#     references to select/syslog/seteuid are not exported by the Amix
#     libc), so we link the STATIC libsocket.a instead and only pull
#     the members we use.
#   - libsocket.a still references syslog(); amixcompat.c stubs it.
#   - libnsl.so has NO SONAME.  The cross-gcc wrapper resolves -lnsl
#     to an absolute host path, and GNU ld then records that path as
#     DT_NEEDED - the Amix runtime linker cannot open it, so the
#     binary dies at exec ("dynamic linker: can't open ... /
#     libnsl.so" + SIGKILL; reproduced on the bench).  The amix link
#     therefore invokes ld DIRECTLY with "-L<sysroot>/usr/lib -lnsl",
#     which makes ld 2.8.1 record a bare "libnsl.so" that the guest
#     resolves from its own /usr/lib.  libc.so.1 is immune (it has
#     SONAME /usr/lib/libc.so.1) and is passed by path.

# One line: heirloom/build-amix-static.sh reads SRCS with awk.
SRCS = main.c util.c conf.c vercmp.c catalog.c md5.c http.c dns.c install.c source.c kspace.c txn.c sha256.c fsreq.c

# ---------------- host ----------------

CC = gcc
CFLAGS = -std=gnu89 -O2 -Wall -Wextra $(HOST_ENDIAN_FLAGS)
HOST_OBJS = $(SRCS:%.c=obj-host/%.o)

# ---------------- amix (cross) ----------------

AMIX_CC = m68k-cbm-sysv4-gcc
AMIX_LD = m68k-cbm-sysv4-ld
AMIX_CFLAGS = -O -DHIGHFIRST
# AMIX_SYSROOT / AMIX_CRT_DIR can come from the environment (the
# cross-gcc wrapper honours them too); default to the sysroot that
# ships with the wrapper.
AMIX_SYSROOT ?= $(shell dirname `command -v $(AMIX_CC)`)/../m68k-cbm-sysv4/sysroot
AMIX_CRT_DIR ?= $(AMIX_SYSROOT)/usr/ccs/lib
AMIX_OBJS = $(SRCS:%.c=obj-amix/%.o) obj-amix/amixcompat.o

# ---------------- targets ----------------

all: host

host: apkg

apkg: $(HOST_OBJS)
	$(CC) $(CFLAGS) -o $@ $(HOST_OBJS)

obj-host/%.o: %.c apkg.h md5.h source.h sha256.h axtypes.h
	@mkdir -p obj-host
	$(CC) $(CFLAGS) -c $< -o $@

amix: apkg.amix

apkg.amix: $(AMIX_OBJS)
	$(AMIX_LD) -o $@ \
	    $(AMIX_CRT_DIR)/crt1.o $(AMIX_CRT_DIR)/crti.o \
	    $(AMIX_OBJS) \
	    $(AMIX_SYSROOT)/usr/lib/libsocket.a \
	    -L$(AMIX_SYSROOT)/usr/lib -lnsl \
	    $(AMIX_SYSROOT)/usr/lib/libc.so.1 \
	    $(AMIX_CRT_DIR)/crtn.o
	@file $@

obj-amix/%.o: %.c apkg.h md5.h source.h sha256.h axtypes.h
	@mkdir -p obj-amix
	$(AMIX_CC) $(AMIX_CFLAGS) -c $< -o $@

test: apkg
	sh tests/run-tests.sh

clean:
	rm -rf obj-host obj-amix apkg apkg.amix

.PHONY: all host amix test clean
