# module/Makefile -- the z3660scsi root-class loadable module, one per kernel
# line, built with kernel/dlm's ABI kit (the kit's docs/guide.md; contracts
# C3-1, C4-1, C4-2).
#
#   make -C module            both lines: build/k30/mod.d/z3660scsi and
#                             build/k46/mod.d/z3660scsi, each checked by the
#                             kit's modfix and modcheck.py
#   make -C module k30        one line (or k46)
#   make -C module static     the static object of each line compiled against
#                             the kit's headers, and its sha256 (the static
#                             driver must not change: README.md)
#   make -C module clean
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives
# build/kit/k30 and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.
# The pinned cross tools (m68k-cbm-sysv4-*) and python3 must be on PATH.
# The kit's fragment does the rest: objects and the module under
# build/<line> (MODOUT, here kernel/drivers/z3660scsi/build/), $cpu from the line.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
DLM ?= $(abspath $(TOP)/../../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

static: $(LINES:%=static-%)

$(LINES:%=static-%): static-%:
	$(MAKE) -s KIT=$(call kit,$*) static

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all static clean $(LINES) $(LINES:%=static-%) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = z3660scsi
OBJS   = z3660.o
MODOUT = $(TOP)/build/$(LINE)
SRC    = $(TOP)/src
ALIEN  = -I$(KIT)/stock/usr/sys/amiga/alien
CFLAGS = -DZ3660SCSI_MODULE -fno-common $(ALIEN)
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

static:
	mkdir -p $(MODOUT)
	$(KIT_CC) $(KIT_CFLAGS) $(ALIEN) -c $(SRC)/z3660.c -o $(MODOUT)/z3660-static.o
	cd $(TOP)/build && sha256sum $(LINE)/z3660-static.o

.PHONY: static

endif
