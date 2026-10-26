# module/Makefile -- the z3660eth loadable module, one per kernel line, built
# with amix-dlm's ABI kit (S3-10; the kit's docs/guide.md).
#
#   make -C module            both lines: build/k30/mod.d/z3660eth and
#                             build/k46/mod.d/z3660eth, each checked by the
#                             kit's modfix and modcheck.py
#   make -C module k30        one line (or k46)
#   make -C module static     the static object of each line compiled against
#                             the kit's headers, and its sha256 (the static
#                             driver must not change: BUILD.md section 9)
#   make -C module test       the host test of the _load parameter parser
#   make -C module zs05       both lines and both forms, then the ZS-05 gate
#                             (check-zs05.py: every board register access is
#                             an armed IPL-7 block; NOTES.md "ZS-05")
#   make -C module clean
#
# DLM is the amix-dlm checkout whose kits are built (`make kit` there gives
# build/kit/k30 and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.
# The pinned cross tools (m68k-cbm-sysv4-*) and python3 must be on PATH.
# The kit's fragment does the rest: objects and the module under
# build/<line> (MODOUT, here the repo's build/), $cpu from the line.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
DLM ?= $(abspath $(TOP)/../amix-dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)

static: $(LINES:%=static-%)

$(LINES:%=static-%): static-%:
	$(MAKE) -s KIT=$(call kit,$*) static

test:
	sh $(TOP)/module/test-params.sh

zs05: all static
	for l in $(LINES); do \
	    python3 $(TOP)/module/check-zs05.py module $(TOP)/build/$$l/obj/z3660eth.o && \
	    python3 $(TOP)/module/check-zs05.py static $(TOP)/build/$$l/z3660eth-static.o || exit 1; \
	done

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all static test zs05 clean $(LINES) $(LINES:%=static-%) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = z3660eth
OBJS   = z3660eth.o
MODOUT = $(TOP)/build/$(LINE)
SRC    = $(TOP)/src
CFLAGS = -DZ3660ETH_MODULE
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

$(MODOUT)/obj/z3660eth.o: $(SRC)/z3660eth.h $(SRC)/z3660ethuser.h

static:
	mkdir -p $(MODOUT)
	$(KIT_CC) $(KIT_CFLAGS) -c $(SRC)/z3660eth.c -o $(MODOUT)/z3660eth-static.o
	cd $(TOP)/build && sha256sum $(LINE)/z3660eth-static.o

.PHONY: static

endif
