# zz9ksvc/module/Makefile -- the zz9ksvc loadable module, one per kernel line, built with
# the ABI kit of kernel/dlm (the kit's docs/guide.md; contract C3-6 section 4).  GNU make.
#
#   make -C zz9ksvc/module        both lines: zz9ksvc/build/k30/mod.d/zz9ksvc and
#                                 zz9ksvc/build/k46/mod.d/zz9ksvc, each checked by the kit's
#                                 modfix and modcheck.py (zz9kbus is built first: zz9ksvc
#                                 names it in depend)
#   make -C zz9ksvc/module k30    one line (or k46)
#   make -C zz9ksvc/module test   the host test (zz9ksvc/test/hosttest.sh)
#   make -C zz9ksvc/module clean
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives build/kit/k30
# and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.  The kit's registry must give
# c 55 to zz9ksvc.  The pinned cross tools (m68k-cbm-sysv4-*, gcc-cross-amix) and python3
# must be on PATH.  src/wire.c, the only file that includes the SDK headers (sdk/zz9k, C99),
# is compiled without the kit's -traditional and with shim/ for <stdint.h>; the rest with
# the kit's flags.  Master is generated from keys.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
DLM ?= $(abspath $(TOP)/../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) -C $(TOP)/zz9kbus/module KIT_$@=$(call kit,$@) $@
	$(MAKE) KIT=$(call kit,$@)

test:
	sh $(TOP)/zz9ksvc/test/hosttest.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all test clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = zz9ksvc
OBJS   = zz9ksvc.o wire.o
MODOUT = $(TOP)/zz9ksvc/build/$(LINE)
SRC    = $(TOP)/zz9ksvc/src
CFLAGS = -I$(TOP)/include -I$(TOP)/zz9ksvc/include -I$(SRC)
DEPS   = $(TOP)/zz9kbus/build/$(LINE)/mod.d/zz9kbus
ANSI   = $(addprefix $(MODOUT)/obj/,wire.o)
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

$(ANSI): KIT_CFLAGS := -I$(TOP)/zz9ksvc/shim -I$(TOP)/zz9ksvc/sdk $(filter-out -traditional,$(KIT_CFLAGS))

Master: keys
	{ echo '# generated from keys by module/Makefile'; \
	  echo '$$modtype drv'; \
	  sed -n 's/^\([a-z]*\)=\(.*\)$$/$$\1 \2/p' keys | grep -v '^\$$name '; \
	  echo '$(MODULE) zz9ksvc'; } > Master

endif
