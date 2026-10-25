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
CSRC    := $(COMMON)/crc32.c $(COMMON)/store.c $(COMMON)/manifest.c
TSRC    := tests/host/t_main.c tests/host/t_crc32.c tests/host/t_store.c \
           tests/host/t_manifest.c

.PHONY: all test tools toolchain-check cross boot1 clean

all: test tools cross boot1

$(B):
	mkdir -p $(B)

$(B)/t_host: $(CSRC) $(TSRC) $(COMMON)/*.h tests/host/t.h | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -I$(COMMON) -o $@ $(CSRC) $(TSRC)

test: $(B)/t_host
	$(B)/t_host

TOOLS := $(B)/bbframe

$(B)/bbframe: tools/bbframe.c | $(B)
	$(HOSTCC) $(HOSTCFLAGS) -o $@ $<

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
CROSSCFLAGS ?= -O2 -m68020 -fno-builtin -Wall
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

clean:
	rm -rf $(B)
