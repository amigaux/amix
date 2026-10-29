# monsw/module/Makefile -- the monsw loadable module, one per kernel line, built with
# the ABI kit of kernel/dlm (the kit's docs/guide.md; contract C3-6 section 4).  GNU make.
#
#   make -C monsw/module          both lines: monsw/build/k30/mod.d/monsw and
#                                 monsw/build/k46/mod.d/monsw, each checked by the kit's
#                                 modfix and modcheck.py
#   make -C monsw/module k30      one line (or k46)
#   make -C monsw/module static   the static (non-module) object of each line, compiled
#                                 against the kit's headers, and its sha256
#   make -C monsw/module test     the host test (monsw/test/hosttest.sh)
#   make -C monsw/module clean
#   sh monsw/module/static-port.sh [port]   the static object against the port's copy
#
# DLM is the kernel/dlm directory whose kits are built (`make kit` there gives build/kit/k30
# and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.  The pinned cross tools
# (m68k-cbm-sysv4-*, gcc-cross-amix) and python3 must be on PATH.  The source is
# monsw/src/monsw.c compiled with -DMONSW_MODULE; <sys/monsw.h> must be
# kernel/modules/include/sys/monsw.h, which the build checks (the kit carries a copy of it).
# Master is generated from keys; it has no $cpu, so the kit gives each line its own.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
DLM ?= $(abspath $(TOP)/../dlm)
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
	sh $(TOP)/monsw/test/hosttest.sh

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean

.PHONY: all static test clean $(LINES) $(LINES:%=static-%) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = monsw
OBJS   = monsw.o
MODOUT = $(TOP)/monsw/build/$(LINE)
SRC    = $(TOP)/monsw/src
HDR    = $(TOP)/include/sys/monsw.h
CFLAGS = -DMONSW_MODULE -I$(TOP)/include
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

$(MODOUT)/obj/monsw.o: $(HDR) $(MODOUT)/hdr.ok

# The <sys/monsw.h> the compiler takes (the kit's include/ is searched first) must be the one
# in kernel/modules/include: read it back from the preprocessor's line markers and compare.
$(MODOUT)/hdr.ok: $(SRC)/monsw.c $(HDR) $(KIT)/kit.conf
	@mkdir -p $(MODOUT)
	@h=$$($(KIT_CC) $(KIT_CFLAGS) $(CFLAGS) -E $(SRC)/monsw.c | \
		sed -n 's/^# *[0-9][0-9]* "\(.*\/sys\/monsw\.h\)".*/\1/p' | head -1); \
	[ -n "$$h" ] || { echo "monsw: the preprocessor named no sys/monsw.h" >&2; exit 1; }; \
	cmp -s "$$h" $(HDR) || { echo "monsw: $$h is not $(HDR): rebuild the kit (make kit in kernel/dlm)" >&2; exit 1; }; \
	echo "monsw: sys/monsw.h = $$h, equal to include/sys/monsw.h" > $@; cat $@

Master: keys
	{ echo '# generated from keys by module/Makefile'; \
	  echo '$$modtype drv'; \
	  sed -n 's/^\([a-z]*\)=\(.*\)$$/$$\1 \2/p' keys | grep -v '^\$$name '; \
	  echo '$(MODULE) monsw'; } > Master

static: $(MODOUT)/hdr.ok
	$(KIT_CC) $(KIT_CFLAGS) -I$(TOP)/include -c $(SRC)/monsw.c -o $(MODOUT)/monsw-static.o
	cd $(TOP)/monsw/build && sha256sum $(LINE)/monsw-static.o

.PHONY: static

endif
