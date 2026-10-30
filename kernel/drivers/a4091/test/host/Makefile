# Host tests of the a4091 root-class module form -- the REAL src/a4091-wr.c,
# built with -DA4091_MODULE on host gcc, against mock.c (boards, their pages,
# sd_register, the C4-5 DMA names).  Two binaries, one per line's map arm:
# k30 (sptalloc) and k46 (-DA4091_KVA: dev_kvmap, bprobe).
#
#   make -C test/host check     # build + run both (exit 0 == every case passes)
#   make -C test/host clean
#
# The driver is K&R C: -std=gnu89 -fno-builtin, in a kernel-only include world
# (-Istubs shadows sys/*.h, rico.h, sd.h, the kit's moddefs.h and amixddi.h);
# printf and bcopy are renamed into the mock.  The harness .c files are plain
# host code and do not get -Istubs.

CC     := gcc
CSTD   := -std=gnu89 -fno-builtin
CWARN  := -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function \
          -Wno-parentheses -Wno-int-conversion -Wno-pointer-to-int-cast \
          -Wno-int-to-pointer-cast -Wno-implicit-function-declaration
CFLAGS := $(CSTD) $(CWARN) -O0 -g
BUILD  := build
DRV    := ../../src/a4091-wr.c
DRVF   := -DA4091_MODULE -Istubs -I../../src -Dprintf=mock_printf -Dbcopy=mock_bcopy
STUBS  := $(wildcard stubs/*.h stubs/sys/*.h)

.PHONY: all check clean
A4KTF  := -DA4091_A4KT -D'A4KT_VPOSR()=mock_vposr()'
ARMS   := $(BUILD)/modtest-k30 $(BUILD)/modtest-k46 $(BUILD)/modtest-a4kt-k30 $(BUILD)/modtest-a4kt-k46

all: $(ARMS)

$(BUILD)/drv-k30.o: $(DRV) ../../src/a4091_dmarec.h $(STUBS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(DRVF) -c $(DRV) -o $@

$(BUILD)/drv-k46.o: $(DRV) ../../src/a4091_dmarec.h $(STUBS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(DRVF) -DA4091_KVA -c $(DRV) -o $@

# the a4kt710 target (S5-06): the same source, -DA4091_A4KT, VPOSR from the mock
$(BUILD)/drv-a4kt-k30.o: $(DRV) ../../src/a4091_dmarec.h $(STUBS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(DRVF) $(A4KTF) -c $(DRV) -o $@

$(BUILD)/drv-a4kt-k46.o: $(DRV) ../../src/a4091_dmarec.h $(STUBS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(DRVF) $(A4KTF) -DA4091_KVA -c $(DRV) -o $@

$(BUILD)/test-a4kt-%.o: a4kt_modtest.c mock.h ../../src/a4091_dmarec.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -std=gnu11 -DLINE_NAME='"a4kt-$*"' -c a4kt_modtest.c -o $@

$(BUILD)/modtest-a4kt-%: $(BUILD)/drv-a4kt-%.o $(BUILD)/mock.o $(BUILD)/test-a4kt-%.o
	$(CC) $(CFLAGS) $^ -o $@

$(BUILD)/mock.o: mock.c mock.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -std=gnu11 -c mock.c -o $@

$(BUILD)/test-%.o: a4091_modtest.c mock.h ../../src/a4091_dmarec.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -std=gnu11 -DLINE_NAME='"$*"' -c a4091_modtest.c -o $@

$(BUILD)/modtest-%: $(BUILD)/drv-%.o $(BUILD)/mock.o $(BUILD)/test-%.o
	$(CC) $(CFLAGS) $^ -o $@

check: all
	./$(BUILD)/modtest-k30
	./$(BUILD)/modtest-k46
	./$(BUILD)/modtest-a4kt-k30
	./$(BUILD)/modtest-a4kt-k46

clean:
	rm -rf $(BUILD)
