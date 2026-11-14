# module/Makefile -- the xsurf loadable module, one per kernel line, built
# with the dlm ABI kit.
#
#   make -C module            both lines: build/k30/mod.d/xsurf and
#                             build/k46/mod.d/xsurf, each checked by the
#                             kit's modfix and modcheck.py
#   make -C module k30        one line (or k46)
#   make -C module test       the host tests (module/host/)
#   make -C module clean
#
# DLM is the dlm kit directory, amix's kernel/dlm (`make kit` there gives
# build/kit/k30 and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.
# The pinned cross tools (m68k-cbm-sysv4-*) and python3 must be on PATH.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
DLM ?= $(abspath $(TOP)/../../dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

test:
	sh $(TOP)/module/host/run.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all test clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = xsurf
OBJS   = xsurf.o xs_core.o xs_boards.o
MODOUT = $(TOP)/build/$(LINE)
SRC    = $(TOP)/src
CFLAGS = $(if $(filter k46,$(LINE)),-DXS_K46)
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

endif
