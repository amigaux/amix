# module/Makefile -- the a4091 root-class loadable module (A4091, A4092, A4770),
# one per kernel line, built with amix-dlm's ABI kit (the kit's docs/guide.md;
# contracts C3-1, C4-1, C4-2, C4-5).
#
#   make -C module            both lines, both modules: build/<line>/mod.d/a4091
#                             and build/<line>/mod.d/a4kt710 (module/a4kt710/,
#                             the A4000T onboard 53C710, S5-06), each checked
#                             by the kit's modfix and modcheck.py
#   make -C module k30        one line (or k46)
#   make -C module clean
#
# DLM is the amix-dlm checkout whose kits are built (`make kit` there gives
# build/kit/k30 and build/kit/k46); KIT_k30 / KIT_k46 name a kit directly.
# The pinned cross tools (m68k-cbm-sysv4-*) and python3 must be on PATH.
# The kit's fragment does the rest: objects and the module under
# build/<line> (MODOUT, here the repo's build/), $cpu from the line.
#
# The static objects are not built here: tools/build-a4091-040.sh (040/060)
# and amix-kerntools (030) build them, and -DA4091_MODULE leaves them unchanged.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
DLM ?= $(abspath $(TOP)/../amix-dlm)
LINES = k30 k46
kit = $(or $(KIT_$(1)),$(DLM)/build/kit/$(1))

ifeq ($(KIT),)

all: $(LINES)

$(LINES):
	$(MAKE) KIT=$(call kit,$@)
	$(MAKE) -C a4kt710 KIT=$(call kit,$@)

clean: $(LINES:%=clean-%)

$(LINES:%=clean-%): clean-%:
	$(MAKE) KIT=$(call kit,$*) clean
	$(MAKE) -C a4kt710 KIT=$(call kit,$*) clean

.PHONY: all clean $(LINES) $(LINES:%=clean-%)

else	# one line, the kit's

MODULE = a4091
OBJS   = a4091-wr.o
MODOUT = $(TOP)/build/$(LINE)
SRC    = $(TOP)/src
ALIEN  = -I$(KIT)/stock/usr/sys/amiga/alien
# k46: the 040/060 board mapping (dev_kvmap NCS, bprobe); k30: sptalloc
LINEFLAGS_k46 = -DA4091_KVA
CFLAGS = -DA4091_MODULE $(LINEFLAGS_$(LINE)) -fno-common $(ALIEN) -I$(SRC)
vpath %.c $(SRC)
include $(KIT)/mk/module.mk

# the driver's own header, which the pattern rule does not see
$(MODOUT)/obj/a4091-wr.o: $(SRC)/a4091_dmarec.h

endif
