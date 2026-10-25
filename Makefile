# amix-dlm -- loader, module core, kbootset, ABI kit.
#
#   make test             host unit tests (system C compiler)
#   make tools            host tools (mkstore, lsstore, bbframe)
#   make toolchain-check  the pinned cross toolchain is present (toolchain.pin)
#   make cross            cross-compile the shared loader code; 68060 scan gate
#   make boot1            assemble boot1 and apply the 1 KB size gate
#   make all              all of the above
#
# The cross toolchain is gcc-cross-amix; source its build/env.sh first, or
# set CROSS to the tool prefix (default m68k-cbm-sysv4- on PATH).

HOSTCC     ?= cc
HOSTCFLAGS ?= -std=c89 -pedantic -Wall -Wextra -Werror -O2
CROSS      ?= m68k-cbm-sysv4-
B          := build

COMMON  := loader/common
CSRC    := $(COMMON)/crc32.c $(COMMON)/store.c $(COMMON)/manifest.c \
           $(COMMON)/inflate.c $(COMMON)/select.c $(COMMON)/rel.c \
           $(COMMON)/bootinfo.c
TSRC    := tests/host/t_main.c tests/host/t_crc32.c tests/host/t_store.c \
           tests/host/t_manifest.c tests/host/t_inflate.c \
           tests/host/t_select.c tests/host/t_rel.c \
           tests/host/t_bootinfo.c

TOOLS   := $(B)/bbframe $(B)/mkstore $(B)/lsstore $(B)/b2link

.PHONY: all test tools toolchain-check cross boot1 boot2 b2test clean

all: test tools cross boot1 boot2 b2test

$(B):
	mkdir -p $(B)

$(B)/t_host: $(CSRC) $(TSRC) $(COMMON)/*.h tests/host/t.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ $(CSRC) $(TSRC) -lz

$(B)/axinflate: tests/host/axinflate.c $(COMMON)/inflate.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/axinflate.c $(COMMON)/inflate.c

$(B)/axrel: tests/host/axrel.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tests/host/axrel.c $(COMMON)/rel.c

# Optional real inputs (not in this repository):
#   AX_FLOPPIES  boot floppy images, for inflate-kernels.sh
#   AX_KERNELS   ET_REL kernels and AX_ELF2BREL (elf2brel.py), for rel-kernels.sh
test: $(B)/t_host $(TOOLS) $(B)/axinflate $(B)/axrel
	$(B)/t_host
	B=$(B) sh tests/host/store-roundtrip.sh
	B=$(B) AX_FLOPPIES="$(AX_FLOPPIES)" sh tests/host/inflate-kernels.sh
	B=$(B) AX_KERNELS="$(AX_KERNELS)" AX_ELF2BREL="$(AX_ELF2BREL)" sh tests/host/rel-kernels.sh

$(B)/bbframe: tools/bbframe.c | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -o $@ $<

$(B)/mkstore: tools/mkstore.c $(CSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tools/mkstore.c $(CSRC) -lz

$(B)/lsstore: tools/lsstore.c $(CSRC) $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tools/lsstore.c $(CSRC)

$(B)/b2link: tools/b2link.c $(COMMON)/rel.c $(COMMON)/*.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ tools/b2link.c $(COMMON)/rel.c

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
	$(CROSS)gcc $(CROSSCFLAGS) -I$(COMMON) -c -o $@ $<

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

b2test: toolchain-check $(B)/b2test.r.o $(B)/b2link $(B)/b2check
	$(B)/b2link $(B)/b2test.r.o $(B)/b2test.bin
	$(B)/b2check $(B)/b2test.r.o $(B)/b2test.bin 0x00200a00
	$(B)/b2check $(B)/b2test.r.o $(B)/b2test.bin 0x07ff1234

clean:
	rm -rf $(B)
