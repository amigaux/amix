# random/module/Makefile -- the random loadable module, one per kernel line, built with
# the ABI kit of kernel/dlm (the kit's docs/guide.md; contract C3-6 section 4).  GNU make.
#
#   make -C random/module        both lines: random/build/k30/mod.d/random and
#                                random/build/k46/mod.d/random, each checked by the kit's
#                                modfix and modcheck.py
#   make -C random/module k30    one line (or k46)
#   make -C random/module test   the host test (random/test/hosttest.sh)
#   make -C random/module clean
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives build/kit/k30
# and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.  The kit's registry must give
# c 48 to random (dlm a8719fb).  The pinned cross tools (m68k-cbm-sysv4-*, gcc-cross-amix)
# and python3 must be on PATH.  The source is random/src/random.c, the module only: there is
# no static form.  Master is generated from keys; it has no $cpu, so the kit gives each line
# its own.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
DLM ?= $(abspath $(TOP)/../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

test:
	sh $(TOP)/random/test/hosttest.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all test clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = random
OBJS   = random.o
MODOUT = $(TOP)/random/build/$(LINE)
SRC    = $(TOP)/random/src
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

Master: keys
	{ echo '# generated from keys by module/Makefile'; \
	  echo '$$modtype drv'; \
	  sed -n 's/^\([a-z]*\)=\(.*\)$$/$$\1 \2/p' keys | grep -v '^\$$name '; \
	  echo '$(MODULE) random'; } > Master

endif
