# module.mk -- build an Amix kernel module with the ABI kit
# (docs/contracts/C3-1-module-object.md, C3-6 in amix-dlm).
#
# In the module's own Makefile:
#
#	KIT    = /path/to/kit-k46		# a built kit, one per line
#	MODULE = hello				# the module's name = its file name
#	OBJS   = hello.o			# compiled from the .c beside the Makefile
#					# (the %.o rule looks nowhere else)
#	DEPS   = ../monsw/build/mod.d/monsw	# the modules named in depend: build
#					# them first; without them modfix
#					# stops at "undefined: <their name>"
#	include $(KIT)/mk/module.mk
#
# and a Master file beside it (the .moddata keys and the definition line,
# see the kit's sample/hello/Master and docs/writing-a-module.md).  A
# Master without a $cpu line gets the line's (kit.conf DEFCPU: 68030 on
# k30, 68040 on k46), or MODCPU if set, so one Master serves both lines.
# Optional: EXTRA (objects linked in as they are, a font for example:
# $(KIT)/stock/usr/sys/amiga/console/sunfont.o), LOCALIZE (globals made
# local after the link, so the module neither exports nor shadows them:
# builtinfont with that font), CFLAGS (added to the kit's), Space.c and
# Mtune (as mkmod takes them).  LOCALIZE needs a newer objcopy than the
# pinned binutils 2.8.1 has (LOCALIZE_OBJCOPY, default m68k-elf-objcopy, as
# gcc14-cross-amix provides); only symbol bindings change, and the pinned
# ld links its output; gcc14-cross-amix has it in build/prefix/bin, which is
# not on PATH by default: put it there or set LOCALIZE_OBJCOPY to its path.
#
# `make` gives build/mod.d/$(MODULE): compiled by the pinned
# gcc-cross-amix against the kit's headers only, linked, .moddata written
# by mkmod, checked by modfix and modcheck.py.  The cross tools
# (m68k-cbm-sysv4-*) must be on PATH.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.

include $(KIT)/kit.conf

# what the kernel build uses (gcc-cross-amix AMIX_KERNEL_CFLAGS), with the
# kit's headers in place of an Amix tree; the gcc wrapper puts
# $(AMIX_SYSROOT)/usr/include first and does the 060-safe rewrite
export AMIX_SYSROOT := $(KIT)/sysroot
KIT_CC     = m68k-cbm-sysv4-gcc
KIT_CFLAGS = -O -traditional -fno-builtin -Dinline=__inline__ -Dvolatile=__volatile__ \
	-Dconst=__const__ $(CPUFLAG) -D_KERNEL -DSVR40 -DSVR4 -I$(KIT)/include \
	-I$(KIT)/stock/usr/include -I$(KIT)/stock/usr/sys -I$(KIT)/stock/usr/sys/amiga/inc
MODOUT    ?= build
MODCPU    ?= $(DEFCPU)
LOCALIZE_OBJCOPY ?= m68k-elf-objcopy

all: $(MODOUT)/mod.d/$(MODULE)

%.o: %.c
	$(KIT_CC) $(KIT_CFLAGS) $(CFLAGS) -c $< -o $@

$(MODOUT)/mod.d/$(MODULE): $(OBJS) $(EXTRA) Master $(DEPS)
	rm -rf $(MODOUT)/src && mkdir -p $(MODOUT)/src
	m68k-cbm-sysv4-ld -r -o $(MODOUT)/src/Driver.o $(OBJS) $(EXTRA)
	$(if $(LOCALIZE),$(LOCALIZE_OBJCOPY) $(foreach s,$(LOCALIZE),--localize-symbol=$(s)) \
		$(MODOUT)/src/Driver.o)
	cp Master $(MODOUT)/src/
	grep -q '^\$$cpu' Master || sed -i '1a $$cpu $(MODCPU)' $(MODOUT)/src/Master
	for f in Space.c Mtune; do [ ! -f $$f ] || cp $$f $(MODOUT)/src/; done
	MKMOD_CC="$(KIT_CC) $(KIT_CFLAGS)" DLM_TOOLS=$(KIT)/tools sh $(KIT)/tools/mkmod \
		-K $(KABI) -P $(PIN) -e $(KIT)/exports $(foreach d,$(DEPS),-d $(d)) \
		-o $(MODOUT) $(MODOUT)/src
	python3 $(KIT)/tools/modcheck.py -k $(KIT) $(foreach d,$(DEPS),-d $(d)) $@

clean:
	rm -rf $(MODOUT) $(OBJS)

.PHONY: all clean
