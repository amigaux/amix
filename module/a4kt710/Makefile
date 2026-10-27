# module/a4kt710/Makefile -- the a4kt710 root-class module: the A4000T onboard
# NCR 53C710 (S5-06), src/a4kt710.c = a4091-wr.c built as its second target.
# Run by module/Makefile once per line with KIT set; objects and the module go
# to the repo's build/<line>, beside the a4091 module.

TOP    := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
MODULE  = a4kt710
OBJS    = a4kt710.o
MODOUT  = $(TOP)/build/$(LINE)
SRC     = $(TOP)/src
ALIEN   = -I$(KIT)/stock/usr/sys/amiga/alien
# k46: the 040/060 board mapping (dev_kvmap NCS, bprobe); k30: sptalloc
LINEFLAGS_k46 = -DA4091_KVA
CFLAGS  = -DA4091_MODULE $(LINEFLAGS_$(LINE)) -fno-common $(ALIEN) -I$(SRC)
vpath %.c $(SRC)
include $(KIT)/mk/module.mk
