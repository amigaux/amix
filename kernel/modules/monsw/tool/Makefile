# monsw/tool/Makefile -- monswctl, the /dev/monsw tool (/usr/sbin/monswctl, page
# monswctl(1M)): one binary for both kernel lines, a plain SVR4 program.  GNU make.
#
#   make -C monsw/tool            monsw/build/tool/monswctl, cross-compiled with -O, and
#                                 its sha256; the gates: the <sys/monsw.h> the compiler took
#                                 is kernel/modules/include/sys/monsw.h, the result is an
#                                 m68k object that imports ioctl, open and close
#   make -C monsw/tool host       monsw/build/tool-host/monswctl: the host build against
#                                 testdouble.c, with -Wall -pedantic, for the host test
#   make -C monsw/tool test       the host test (monsw/test/tooltest.sh)
#   make -C monsw/tool clean
#
# The pinned cross tools (m68k-cbm-sysv4-*, gcc-cross-amix) must be on PATH; CROSS names
# another prefix, HOSTCC another host compiler.  Two builds are byte-identical.

TOP := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
CROSS ?= m68k-cbm-sysv4-
HOSTCC ?= cc
SRC  = $(TOP)/monsw/tool
HDR  = $(TOP)/include/sys/monsw.h
OUT  = $(TOP)/monsw/build/tool
HOUT = $(TOP)/monsw/build/tool-host
CFLAGS = -O -I$(TOP)/include
HOSTCFLAGS = -O -std=c89 -Wall -pedantic -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE \
	-DMONSW_TESTDOUBLE -I$(TOP)/include

all: $(OUT)/monswctl
	@cd $(TOP)/monsw/build && sha256sum tool/monswctl

$(OUT)/monswctl: $(SRC)/monswctl.c $(HDR)
	@mkdir -p $(OUT)
	@h=$$($(CROSS)gcc $(CFLAGS) -E $(SRC)/monswctl.c | \
		sed -n 's/^# *[0-9][0-9]* "\(.*\/sys\/monsw\.h\)".*/\1/p' | head -1); \
	[ -n "$$h" ] || { echo "monswctl: the preprocessor named no sys/monsw.h" >&2; exit 1; }; \
	cmp -s "$$h" $(HDR) || { echo "monswctl: the compiler took $$h, not $(HDR)" >&2; exit 1; }
	$(CROSS)gcc $(CFLAGS) -o $@.tmp $(SRC)/monswctl.c
	@a=$$($(CROSS)objdump -f $@.tmp | sed -n 's/^architecture: *\([^,]*\).*/\1/p'); \
	case "$$a" in m68k*) ;; *) echo "monswctl: $@ is '$$a', not m68k" >&2; rm -f $@.tmp; exit 1 ;; esac; \
	for s in ioctl open close; do \
		$(CROSS)nm $@.tmp | grep -qE " U _?$$s\$$" || \
			{ echo "monswctl: $@ does not import $$s" >&2; rm -f $@.tmp; exit 1; }; \
	done
	@mv $@.tmp $@

host: $(HOUT)/monswctl

$(HOUT)/monswctl: $(SRC)/monswctl.c $(SRC)/testdouble.c $(HDR)
	@mkdir -p $(HOUT)
	$(HOSTCC) $(HOSTCFLAGS) -o $@ $(SRC)/monswctl.c $(SRC)/testdouble.c

test:
	bash $(TOP)/monsw/test/tooltest.sh

clean:
	rm -rf $(OUT) $(HOUT)

.PHONY: all host test clean
