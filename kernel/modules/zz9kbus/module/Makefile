# zz9kbus/module/Makefile -- the zz9kbus registry module, one per kernel line, built with
# the ABI kit of kernel/dlm (the kit's docs/guide.md).  GNU make.
#
#   make -C zz9kbus/module        both lines: zz9kbus/build/k30/mod.d/zz9kbus and
#                                 zz9kbus/build/k46/mod.d/zz9kbus, each checked by the kit's
#                                 modfix and modcheck.py
#   make -C zz9kbus/module k30    one line (or k46)
#   make -C zz9kbus/module test   the host test (zz9kbus/test/hosttest.sh)
#   make -C zz9kbus/module clean
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives build/kit/k30
# and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.  The pinned cross tools
# (m68k-cbm-sysv4-*, gcc-cross-amix) and python3 must be on PATH.  zz9kbus.h is
# kernel/modules/include/zz9kbus.h.  Master is generated from keys.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
DLM ?= $(abspath $(TOP)/../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

test:
	sh $(TOP)/zz9kbus/test/hosttest.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all test clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = zz9kbus
OBJS   = zz9kbus.o
MODOUT = $(TOP)/zz9kbus/build/$(LINE)
SRC    = $(TOP)/zz9kbus/src
CFLAGS = -I$(TOP)/include
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

Master: keys
	{ echo '# generated from keys by module/Makefile'; \
	  echo '$$modtype misc'; \
	  sed -n 's/^\([a-z]*\)=\(.*\)$$/$$\1 \2/p' keys | grep -v '^\$$name '; \
	  echo '$(MODULE) zz9kbus'; } > Master

endif
