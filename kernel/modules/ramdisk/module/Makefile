# ramdisk/module/Makefile -- the ramdisk loadable module, one per kernel line, built with
# the ABI kit of kernel/dlm (the kit's docs/guide.md; contracts C3-6 section 4 and C4-2).  GNU make.
#
#   make -C ramdisk/module        both lines: ramdisk/build/k30/mod.d/ramdisk and
#                                 ramdisk/build/k46/mod.d/ramdisk, each checked by the kit's
#                                 modfix and modcheck.py
#   make -C ramdisk/module k30    one line (or k46)
#   make -C ramdisk/module test   the host test (ramdisk/test/hosttest.sh)
#   make -C ramdisk/module clean
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives build/kit/k30
# and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.  The kit must be of kabi
# k30.1.2 / k46.1.2 or later (iodone and ramdisk_image, C4-3).  The pinned cross tools
# (m68k-cbm-sysv4-*, gcc-cross-amix) and python3 must be on PATH.  The source is
# ramdisk/src/ramdisk.c, which is the module only: the stock `ram` driver is the static form
# it replaces.  Master is generated from keys; it has no $cpu, so the kit gives each line its
# own.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
DLM ?= $(abspath $(TOP)/../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

test:
	sh $(TOP)/ramdisk/test/hosttest.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all test clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = ramdisk
OBJS   = ramdisk.o
MODOUT = $(TOP)/ramdisk/build/$(LINE)
SRC    = $(TOP)/ramdisk/src
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

Master: keys
	{ echo '# generated from keys by module/Makefile'; \
	  echo '$$modtype drv'; \
	  sed -n 's/^\([a-z]*\)=\(.*\)$$/$$\1 \2/p' keys | grep -v '^\$$name '; \
	  echo '$(MODULE) ramdisk'; } > Master

endif
