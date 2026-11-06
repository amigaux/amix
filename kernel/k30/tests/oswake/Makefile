# the oversize sleeper row: make KIT=<amix>/kernel/dlm/build/kit/k30 [REQ=20000]
MODULE = oswake
OBJS = oswake.o
CFLAGS = -DOSWAKE_REQ=$(or $(REQ),8800)
include $(KIT)/mk/module.mk
