# amix-dlm -- loader, module core, kbootset, ABI kit.
#
#   make test             host unit tests (system C compiler)
#   make tools            host tools (mkstore, lsstore, bbframe)
#   make toolchain-check  the pinned cross toolchain is present (toolchain.pin)
#   make cross            cross-compile the shared loader code; 68060 scan gate
#   make boot1            assemble boot1 and apply the 1 KB size gate
#   make box              kbootset and modadmin for the box: GCC 14, static (D-3 §9)
#   make all              all of the above
#   make kit              the ABI kit for both lines into build/kit/ (S3-10)
#   make kit-test         the kit: build, the sample, the checker's refusals
#
# The cross toolchain is gcc-cross-amix; source its build/env.sh first, or
# set CROSS to the tool prefix (default m68k-cbm-sysv4- on PATH).  Userland
# for the box (kbootset) is built with gcc14-cross-amix: G14 names its
# build directory (default: the sibling checkout).

HOSTCC     ?= cc
HOSTCFLAGS ?= -std=c89 -pedantic -Wall -Wextra -Werror -O2
CROSS      ?= m68k-cbm-sysv4-
G14        ?= ../gcc14-cross-amix/build
B          := build

COMMON  := loader/common
CSRC    := $(COMMON)/crc32.c $(COMMON)/store.c $(COMMON)/manifest.c \
           $(COMMON)/inflate.c $(COMMON)/select.c $(COMMON)/rel.c \
           $(COMMON)/bootinfo.c
# common code that boot2 does not link (CSRC goes into boot2 whole)
XSRC    := $(COMMON)/sha256.c
# kbootset's core (userland: host and box)
KSRC    := kbootset/ks.c kbootset/kbuild.c kbootset/kbox.c kbootset/kmod.c kbootset/kreg.c \
           kbootset/knl.c kbootset/kdeflate.c
TSRC    := tests/host/t_main.c tests/host/t_crc32.c tests/host/t_store.c \
           tests/host/t_manifest.c tests/host/t_inflate.c \
           tests/host/t_select.c tests/host/t_rel.c \
           tests/host/t_bootinfo.c tests/host/t_sha256.c tests/host/t_kbootset.c \
           tests/host/t_deflate.c tests/host/t_kmod.c

TOOLS   := $(B)/bbframe $(B)/mkstore $(B)/lsstore $(B)/b2link $(B)/kbootset

.PHONY: all test tools toolchain-check cross boot1 boot2 cdboot axtime box hashbench core b2test kit kit-test clean

all: test tools cross boot1 boot2 cdboot axtime box b2test

$(B):
	mkdir -p $(B)

$(B)/t_host: $(CSRC) $(XSRC) $(KSRC) $(TSRC) $(COMMON)/*.h kbootset/*.h tests/host/t.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -Ikbootset -o $@ $(CSRC) $(XSRC) $(KSRC) $(TSRC) -lz

$(B)/axinflate: tests/host/axinflate.c $(COMMON)/inflate.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/axinflate.c $(COMMON)/inflate.c

$(B)/axrel: tests/host/axrel.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/axrel.c $(COMMON)/rel.c

$(B)/nlmake: tests/host/nlmake.c kbootset/knl.c $(COMMON)/rel.c $(COMMON)/*.h kbootset/knl.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -Ikbootset -o $@ tests/host/nlmake.c kbootset/knl.c $(COMMON)/rel.c

# Optional real inputs (not in this repository):
#   AX_FLOPPIES  boot floppy images, for inflate-kernels.sh
#   AX_KERNELS   ET_REL kernels and AX_ELF2BREL (elf2brel.py), for rel-kernels.sh
test: $(B)/t_host $(TOOLS) $(B)/axinflate $(B)/axrel $(B)/b2medium $(B)/axsim $(B)/nlmake $(B)/kbootset-nz
	$(B)/t_host
	B=$(B) sh tests/host/store-roundtrip.sh
	B=$(B) sh tests/host/kbuild.sh
	B=$(B) sh tests/host/kimports.sh
	B=$(B) sh tests/host/kbox.sh
	B=$(B) sh tests/host/namelist.sh
	B=$(B) sh tests/host/knamelist.sh
	B=$(B) sh tests/host/prfcheck.sh
	sh tests/host/upstream.sh
	B=$(B) sh tests/host/libmod.sh
	sh tools/mkkreg.sh | cmp -s - kbootset/kreg.c || \
		{ echo "kbootset/kreg.c differs from abi/registry/majors: sh tools/mkkreg.sh > kbootset/kreg.c"; false; }
	B=$(B) AX_FLOPPIES="$(AX_FLOPPIES)" sh tests/host/inflate-kernels.sh
	B=$(B) AX_KERNELS="$(AX_KERNELS)" AX_ELF2BREL="$(AX_ELF2BREL)" sh tests/host/rel-kernels.sh

$(B)/bbframe: tools/bbframe.c | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -o $@ $<

$(B)/mkstore: tools/mkstore.c $(CSRC) $(XSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tools/mkstore.c $(CSRC) $(XSRC) -lz

$(B)/lsstore: tools/lsstore.c $(CSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tools/lsstore.c $(CSRC)

$(B)/axsim: tests/host/axsim.c $(CSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/axsim.c $(CSRC)

# boot2's store medium on the host, against a simulated drive and person
$(B)/b2medium: tests/host/b2medium.c loader/boot2/main.c $(CSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -no-pie \
		-I$(COMMON) -Iloader/boot2 -o $@ tests/host/b2medium.c $(CSRC)

# kbootset as the box builds it, on the host: no zlib, so its own deflate
# (kdeflate.c) and no media builds -- kbuild.sh's --spec z=deflate case
$(B)/kbootset-nz: kbootset/kbootset.c $(KSRC) $(CSRC) $(XSRC) $(COMMON)/*.h kbootset/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -Ikbootset -o $@ kbootset/kbootset.c $(KSRC) $(CSRC) $(XSRC)

# kbootset on the host: zlib for media that deflate, and mkstore's engine
# (kbootset/kmedia.c) for the floppy pair and the CD tree; the box build is
# `make box`
$(B)/kbootset: kbootset/kbootset.c kbootset/kmedia.c tools/mkstore.c $(KSRC) $(CSRC) $(XSRC) $(COMMON)/*.h kbootset/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -DKS_ZLIB -DKS_MEDIA -I$(COMMON) -Ikbootset -o $@ kbootset/kbootset.c \
		kbootset/kmedia.c $(KSRC) $(CSRC) $(XSRC) -lz

$(B)/b2link: tools/b2link.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -DAX_RELNOTE -I$(COMMON) -o $@ tools/b2link.c $(COMMON)/rel.c

$(B)/b2check: tests/host/b2check.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/b2check.c $(COMMON)/rel.c

tools: $(TOOLS)

# The compiler is a wrapper script, so its version is read from the .ident
# line of a compiled empty unit rather than from --version.
toolchain-check: | $(B)
	@echo 'int ax_tc;' > $(B)/tc.c; \
	v=`$(CROSS)gcc -S -o - $(B)/tc.c 2>/dev/null | sed -n 's/.*GCC: (GNU) \([0-9.]*\).*/\1/p'`; \
	want=`awk '$$1=="gcc"{print $$2}' toolchain.pin`; \
	[ "$$v" = "$$want" ] || { echo "toolchain-check: $(CROSS)gcc is '$$v', pin wants $$want" >&2; exit 1; }; \
	bu=`awk '$$1=="binutils"{print $$2}' toolchain.pin`; \
	$(CROSS)as --version 2>/dev/null | grep -q "GNU assembler $$bu" || { echo "toolchain-check: $(CROSS)as is not binutils $$bu" >&2; exit 1; }; \
	$(CROSS)ld --version 2>/dev/null | grep -q "GNU ld $$bu" || { echo "toolchain-check: $(CROSS)ld is not binutils $$bu" >&2; exit 1; }; \
	echo "toolchain-check: ok (gcc $$v, binutils $$bu)"

# Loader code is plain ANSI C89 (not -traditional) for the 68020 and up; every
# object must pass the toolchain's 68060 instruction scanner.
CROSSCFLAGS ?= -O2 -m68020 -fno-builtin -fomit-frame-pointer -Wall
COBJ := $(patsubst $(COMMON)/%.c,$(B)/cross/%.o,$(CSRC))

$(B)/cross/%.o: $(COMMON)/%.c $(COMMON)/*.h
	@mkdir -p $(B)/cross
	$(CROSS)gcc $(CROSSCFLAGS) -DAX_LOADER -I$(COMMON) -c -o $@ $<

cross: toolchain-check $(COBJ)
	$(CROSS)scan060 $(COBJ)

# boot1: position-independent code with no relocations, framed as a bootblock;
# bbframe fails the build if the code exceeds the 1008 bytes the 1 KB strap
# read leaves after the framing.
$(B)/boot1.o: loader/boot1/boot1.s | $(B)
	$(CROSS)as -o $@ $<

$(B)/boot1.bin: $(B)/boot1.o
	@if $(CROSS)objdump -r $< | grep -q '^[0-9a-f]\{8\} '; then \
		echo "boot1: GATE: relocations present; boot1 must be position-independent" >&2; \
		$(CROSS)objdump -r $< >&2; exit 1; fi
	$(CROSS)objcopy -O binary $< $@

$(B)/boot1.img: $(B)/boot1.bin $(B)/bbframe
	$(B)/bbframe $< $@
	$(B)/bbframe -c $@

boot1: toolchain-check $(B)/boot1.img

# boot2: start.s first (its header must be the first bytes), then the rest;
# ld -r, then b2link binds it at 0, appends the self-relocation table and
# applies the 28 KiB size gate.
B2LIB  := loader/boot2/core.c loader/boot2/sys.c loader/boot2/con.c \
          loader/boot2/input.c loader/boot2/menu.c
B2C    := loader/boot2/main.c $(B2LIB)
B2OBJ  := $(B)/cross/start.o $(B)/cross/amiga.o \
          $(patsubst loader/boot2/%.c,$(B)/cross/b2_%.o,$(B2C)) $(COBJ)

$(B)/cross/amiga.o: loader/boot2/amiga.s
	@mkdir -p $(B)/cross
	$(CROSS)as -m68030 -o $@ $<

$(B)/cross/b2_%.o: loader/boot2/%.c loader/boot2/*.h $(COMMON)/*.h
	@mkdir -p $(B)/cross
	$(CROSS)gcc $(CROSSCFLAGS) -fomit-frame-pointer -I$(COMMON) -c -o $@ $<

$(B)/boot2.r.o: $(B2OBJ)
	$(CROSS)ld -r -o $@ $(B2OBJ)

$(B)/boot2.bin: $(B)/boot2.r.o $(B)/b2link
	$(CROSS)scan060 $(B2OBJ)
	$(B)/b2link $< $@

boot2: toolchain-check $(B)/boot2.bin

# amix-cdboot: boot2's core with the CD entry (adstart.s first, then
# cdmain.c), written as an AmigaDOS load file; hunkcheck proves its
# RELOC32 table reproduces the relocator's binding.
CDOBJ  := $(B)/cross/adstart.o $(B)/cross/amiga.o $(B)/cross/b2_cdmain.o \
          $(patsubst loader/boot2/%.c,$(B)/cross/b2_%.o,$(B2LIB)) $(COBJ)

$(B)/cross/adstart.o: loader/boot2/adstart.s
	@mkdir -p $(B)/cross
	$(CROSS)as -o $@ $<

$(B)/cdboot.r.o: $(CDOBJ)
	$(CROSS)ld -r -o $@ $(CDOBJ)

$(B)/hunkcheck: tests/host/hunkcheck.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/hunkcheck.c $(COMMON)/rel.c

$(B)/amix-cdboot: $(B)/cdboot.r.o $(B)/b2link $(B)/hunkcheck
	$(CROSS)scan060 $(CDOBJ)
	$(B)/b2link -h $< $@
	$(B)/hunkcheck $< $@ 0x00200000
	$(B)/hunkcheck $< $@ 0x0812f3a0

cdboot: toolchain-check $(B)/amix-cdboot

# kbootset for the box (docs/plan/stage-2.md S2-07): GCC 14, statically
# linked by hand, since the driver's specs always link dynamically; the
# objects and archives are the driver's own, plus values-Xa.o for
# _lib_version.  The GCC 14 runtime's snprintf (libamixc99) saves and
# restores FPU registers, so kbootset executes FPU instructions; on an
# FPU-less 68LC040/68LC060 the kernel's FPU emulation (in the floor, D-3
# §4) takes them.  The sources also compile with gcc-cross-amix (GCC
# 2.7.2.3) as a C89 check; that build is not shipped.
G14CC   := $(G14)/prefix/bin/m68k-elf-gcc
G14LD   := $(G14)/prefix/bin/m68k-elf-ld
G14LIB  := $(G14)/prefix/lib/gcc/m68k-elf/14.2.0
G14SR   := $(G14)/sysroot
G14CFLAGS := -std=gnu89 -O2 -Wall -Wextra -Werror -D__svr4__ -DSVR4 -Dunix -D__unix__ -DKS_SYNC
KBSRC   := kbootset/kbootset.c $(KSRC) $(CSRC) $(XSRC)
KBOBJ   := $(patsubst %.c,$(B)/box/%.o,$(notdir $(KBSRC)))

$(B)/box/%.o: kbootset/%.c kbootset/*.h $(COMMON)/*.h
	@mkdir -p $(B)/box
	$(G14CC) $(G14CFLAGS) -I$(COMMON) -Ikbootset -c -o $@ $<

$(B)/box/%.o: $(COMMON)/%.c $(COMMON)/*.h
	@mkdir -p $(B)/box
	$(G14CC) $(G14CFLAGS) -I$(COMMON) -c -o $@ $<

$(B)/box/kbootset: $(KBOBJ)
	@test -x $(G14CC) || { echo "box: no gcc14-cross-amix at $(G14) (set G14)" >&2; exit 1; }
	$(G14LD) --sysroot=$(G14SR) -static -Ttext-segment=0x80000000 --build-id=none -o $@ \
		$(G14SR)/usr/ccs/lib/crt1.o $(G14SR)/usr/ccs/lib/crti.o $(G14SR)/usr/ccs/lib/values-Xa.o \
		$(G14LIB)/crtbegin.o $(G14)/prefix/m68k-elf/lib/amix_init.o $(KBOBJ) \
		-L$(G14LIB) -L$(G14)/prefix/m68k-elf/lib -L$(G14SR)/usr/ccs/lib -lgcc -lamixc99 -lc -lgcc \
		$(G14LIB)/crtend.o $(G14SR)/usr/ccs/lib/crtn.o
	python3 -I $(G14)/../tools/check-68060-safe.py --68881 $@
	$(G14)/prefix/bin/m68k-elf-size $@

$(B)/box/c89-check: $(KBSRC) kbootset/*.h $(COMMON)/*.h
	@mkdir -p $(B)/box/c89
	for f in $(KBSRC); do $(CROSS)gcc $(CROSSCFLAGS) -DKS_SYNC -I$(COMMON) -Ikbootset \
		-c -o $(B)/box/c89/$$(basename $$f .c).o $$f || exit 1; done
	touch $@

# modadmin for the box (S3-11): the core's own modadmin.c (core/series
# applied), its six system calls through the stock syscall() (modtools/)
$(B)/box/core/modadmin.c: core/upstream/modadmin.c core/series core/patches/*.patch
	sh tools/stagecore.sh $(B)/box/core

$(B)/box/modadmin.o: $(B)/box/core/modadmin.c
	$(G14CC) $(G14CFLAGS) -I$(B)/box/core/include -c -o $@ $<

$(B)/box/libmod.o: modtools/libmod.c
	@mkdir -p $(B)/box
	$(G14CC) $(G14CFLAGS) -c -o $@ $<

$(B)/box/modadmin: $(B)/box/modadmin.o $(B)/box/libmod.o
	$(G14LD) --sysroot=$(G14SR) -static -Ttext-segment=0x80000000 --build-id=none -o $@ \
		$(G14SR)/usr/ccs/lib/crt1.o $(G14SR)/usr/ccs/lib/crti.o $(G14SR)/usr/ccs/lib/values-Xa.o \
		$(G14LIB)/crtbegin.o $(G14)/prefix/m68k-elf/lib/amix_init.o $^ \
		-L$(G14LIB) -L$(G14)/prefix/m68k-elf/lib -L$(G14SR)/usr/ccs/lib -lgcc -lamixc99 -lc -lgcc \
		$(G14LIB)/crtend.o $(G14SR)/usr/ccs/lib/crtn.o
	python3 -I $(G14)/../tools/check-68060-safe.py --68881 $@
	$(G14)/prefix/bin/m68k-elf-size $@

box: toolchain-check $(B)/box/kbootset $(B)/box/c89-check $(B)/box/modadmin

# hashbench (M-GEN2's finding): the loader's SHA-256 and CRC-32 over a buffer
# in memory, once as GCC 14 builds them for kbootset and once as
# gcc-cross-amix builds them for the loader; both are Amix programs
HBG14 := $(B)/box/hashbench.o $(B)/box/sha256.o $(B)/box/crc32.o
$(B)/box/hashbench.o: tools/measure/hashbench.c $(COMMON)/*.h
	@mkdir -p $(B)/box
	$(G14CC) $(G14CFLAGS) -I$(COMMON) -c -o $@ $<

$(B)/box/hashbench: $(HBG14)
	$(G14LD) --sysroot=$(G14SR) -static -Ttext-segment=0x80000000 --build-id=none -o $@ \
		$(G14SR)/usr/ccs/lib/crt1.o $(G14SR)/usr/ccs/lib/crti.o $(G14SR)/usr/ccs/lib/values-Xa.o \
		$(G14LIB)/crtbegin.o $(G14)/prefix/m68k-elf/lib/amix_init.o $(HBG14) \
		-L$(G14LIB) -L$(G14)/prefix/m68k-elf/lib -L$(G14SR)/usr/ccs/lib -lgcc -lamixc99 -lc -lgcc \
		$(G14LIB)/crtend.o $(G14SR)/usr/ccs/lib/crtn.o
	python3 -I $(G14)/../tools/check-68060-safe.py --68881 $@

$(B)/hb27/hashbench: tools/measure/hashbench.c $(COMMON)/sha256.c $(COMMON)/crc32.c $(COMMON)/*.h
	@mkdir -p $(B)/hb27
	$(CROSS)gcc $(CROSSCFLAGS) -I$(COMMON) -o $@ tools/measure/hashbench.c $(COMMON)/sha256.c $(COMMON)/crc32.c

# the same GCC 14 program at other optimisation levels, to see whether the
# level is the remedy
HBOPTS := O1 O3 Os
$(B)/hb14-%/hashbench: tools/measure/hashbench.c $(COMMON)/sha256.c $(COMMON)/crc32.c $(COMMON)/*.h
	@mkdir -p $(B)/hb14-$*
	for f in tools/measure/hashbench.c $(COMMON)/sha256.c $(COMMON)/crc32.c; do \
		$(G14CC) $(filter-out -O2,$(G14CFLAGS)) -$* -I$(COMMON) -c -o $(B)/hb14-$*/$$(basename $$f .c).o $$f || exit 1; done
	$(G14LD) --sysroot=$(G14SR) -static -Ttext-segment=0x80000000 --build-id=none -o $@ \
		$(G14SR)/usr/ccs/lib/crt1.o $(G14SR)/usr/ccs/lib/crti.o $(G14SR)/usr/ccs/lib/values-Xa.o \
		$(G14LIB)/crtbegin.o $(G14)/prefix/m68k-elf/lib/amix_init.o \
		$(B)/hb14-$*/hashbench.o $(B)/hb14-$*/sha256.o $(B)/hb14-$*/crc32.o \
		-L$(G14LIB) -L$(G14)/prefix/m68k-elf/lib -L$(G14SR)/usr/ccs/lib -lgcc -lamixc99 -lc -lgcc \
		$(G14LIB)/crtend.o $(G14SR)/usr/ccs/lib/crtn.o
	python3 -I $(G14)/../tools/check-68060-safe.py --68881 $@

# M-CORE1: the module core (core/upstream + core/series) built with the
# pinned toolchains, upstream's host tests run against the kernels of record
# (amix-kerntools); not part of `test`, which needs no sibling repository
core: toolchain-check
	B=$(B) sh tests/core/run.sh

# the ABI kit (abi/, docs/spec/20-module-format-and-abi.md section 5): one
# per line, with the stock headers of the pinned sysroot (never tracked)
kit: toolchain-check
	sh tools/mkkit.sh k30 $(B)/kit/k30
	sh tools/mkkit.sh k46 $(B)/kit/k46

kit-test: toolchain-check
	B=$(B) sh tests/kit/run.sh

hashbench: toolchain-check $(B)/box/hashbench $(B)/hb27/hashbench $(foreach o,$(HBOPTS),$(B)/hb14-$(o)/hashbench)

# axtime (M-LD7/M-LD8): an AmigaDOS program over the loader's own CRC-32,
# inflate and the SHA-256 boot2 does not link; same entry and writer as
# amix-cdboot
XOBJ   := $(patsubst $(COMMON)/%.c,$(B)/cross/%.o,$(XSRC))
ATOBJ  := $(B)/cross/adstart.o $(B)/cross/amiga.o $(B)/cross/axtime.o \
          $(B)/cross/b2_sys.o $(B)/cross/crc32.o $(B)/cross/inflate.o $(XOBJ)

$(B)/cross/axtime.o: tools/measure/axtime.c loader/boot2/*.h $(COMMON)/*.h
	@mkdir -p $(B)/cross
	$(CROSS)gcc $(CROSSCFLAGS) -Iloader/boot2 -I$(COMMON) -c -o $@ $<

$(B)/axtime.r.o: $(ATOBJ)
	$(CROSS)ld -r -o $@ $(ATOBJ)

$(B)/axtime: $(B)/axtime.r.o $(B)/b2link $(B)/hunkcheck
	$(CROSS)scan060 $(ATOBJ)
	$(B)/b2link -h $< $@
	$(B)/hunkcheck $< $@ 0x00200000

# the same program with its hunk in chip memory, as boot2 runs behind boot1
$(B)/axtime-chip: $(B)/axtime.r.o $(B)/b2link $(B)/hunkcheck
	$(B)/b2link -h -c $< $@
	$(B)/hunkcheck $< $@ 0x00200000

axtime: toolchain-check $(B)/axtime $(B)/axtime-chip

# The boot2 build path end to end with a stand-in boot2: cross-compile, ld -r
# with start.s first, b2link, then b2check proves the table reproduces the
# relocator's binding at two load addresses.
$(B)/cross/start.o: loader/boot2/start.s
	@mkdir -p $(B)/cross
	$(CROSS)as -o $@ $<

$(B)/cross/b2test.o: tests/cross/b2test.c
	@mkdir -p $(B)/cross
	$(CROSS)gcc $(CROSSCFLAGS) -c -o $@ $<

$(B)/b2test.r.o: $(B)/cross/start.o $(B)/cross/b2test.o
	$(CROSS)ld -r -o $@ $(B)/cross/start.o $(B)/cross/b2test.o

b2test: toolchain-check $(B)/b2test.r.o $(B)/b2link $(B)/b2check $(B)/boot2.bin
	$(B)/b2link $(B)/b2test.r.o $(B)/b2test.bin
	$(B)/b2check $(B)/b2test.r.o $(B)/b2test.bin 0x00200a00
	$(B)/b2check $(B)/b2test.r.o $(B)/b2test.bin 0x07ff1234
	$(B)/b2check $(B)/boot2.r.o $(B)/boot2.bin 0x00200a00
	$(B)/b2check $(B)/boot2.r.o $(B)/boot2.bin 0x07ff1234

clean:
	rm -rf $(B)
