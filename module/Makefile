# module/Makefile -- the z3660eth loadable module, one per kernel line, built
# with amix-dlm's ABI kit (S3-10; the kit's docs/writing-a-module.md).
#
#   make -C module            both lines: build/k30/mod.d/z3660eth and
#                             build/k46/mod.d/z3660eth, each checked by the
#                             kit's modfix and modcheck.py
#   make -C module k30        one line (or k46)
#   make -C module static     the static object of each line compiled against
#                             the kit's headers, and its sha256 (the static
#                             driver must not change: BUILD.md section 9)
#   make -C module clean
#
# DLM is the amix-dlm checkout whose kits are built (`make kit` there gives
# build/kit/k30 and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.
# The pinned cross tools (m68k-cbm-sysv4-*) and python3 must be on PATH.
#
# Each line runs in build/<line>, because a Master and the objects are per
# directory in the kit's fragment and the two lines differ: the object (the
# kit's CPU flag and headers) and the Master's $cpu.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
DLM ?= $(abspath $(TOP)/../amix-dlm)
LINES = k30 k46

ifeq ($(LINE),)

all: $(LINES)

$(LINES):
	mkdir -p $(TOP)/build/$@
	$(MAKE) -C $(TOP)/build/$@ -f $(TOP)/module/Makefile LINE=$@ \
		KIT=$(or $(KIT_$@),$(DLM)/build/kit/$@)

static: $(LINES:%=static-%)

$(LINES:%=static-%): static-%:
	mkdir -p $(TOP)/build/$*
	$(MAKE) -s -C $(TOP)/build/$* -f $(TOP)/module/Makefile LINE=$* \
		KIT=$(or $(KIT_$*),$(DLM)/build/kit/$*) static

clean:
	rm -rf $(LINES:%=$(TOP)/build/%)

.PHONY: all static clean $(LINES) $(LINES:%=static-%)

else	# one line, in build/$(LINE)

MODULE = z3660eth
OBJS   = z3660eth.o
MODOUT = .
SRC    = $(TOP)/src
CFLAGS = -DZ3660ETH_MODULE
include $(KIT)/mk/module.mk

CPU_k30 = 68030
CPU_k46 = 68040

z3660eth.o: $(SRC)/z3660eth.c $(SRC)/z3660eth.h $(SRC)/z3660ethuser.h $(KIT)/kit.conf
	$(KIT_CC) $(KIT_CFLAGS) $(CFLAGS) -c $< -o $@

Master: $(TOP)/module/Master.in $(KIT)/kit.conf
	sed 's/@CPU@/$(CPU_$(LINE))/' $< > $@

static:
	$(KIT_CC) $(KIT_CFLAGS) -c $(SRC)/z3660eth.c -o z3660eth-static.o
	sha256sum z3660eth-static.o | sed 's|  |  $(LINE)/|'

.PHONY: static

endif
