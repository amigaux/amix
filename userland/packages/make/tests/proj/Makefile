# GNU make smoke project -- every feature here is one stock SVR4 make lacks.
# Recipes use only tools a stock Amix box has (tr, echo, cat, touch via : >).
VPATH = src
WHO := $(shell echo shell-says-amix)

all: out/a.up out/b.up out/info.txt

# pattern rule; the %.txt prerequisites are found through VPATH
out/%.up: %.txt | out
	tr '[a-z]' '[A-Z]' < $< > $@

# order-only prerequisite: out/ must exist, its mtime never forces a rebuild
out:
	mkdir out

define MKINFO
out/info.txt: | out
	echo $(WHO) > $$@
	echo eval-made-rule >> $$@
endef
$(eval $(MKINFO))

sub:
	$(MAKE) -C sub

hello: hello.c
	cc -o $@ hello.c

clean:
	rm -rf out hello sub/done1 sub/done2

.PHONY: all sub clean
