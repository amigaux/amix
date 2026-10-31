# Makefile: make dist at the top of the checkout. Every target is build/'s
# (build/Makefile, build/dist.sh, docs/BUILDING.md); this file only hands it on.
#
# MIT licence, see LICENSE at the top of the repository.
#
#     make dist SYSTEM=<amix-system checkout>
#     make kit | kernel-k30 | kernel-k46 | modules | drivers | kspace | userland
#     make catalogs | media | lock | tools | recipes/<name> | drivers/<name>

STEPS = dist tools kit kernel-k30 kernel-k46 modules drivers kspace userland catalogs media lock

.PHONY: $(STEPS)

$(STEPS):
	$(MAKE) -C build $@

recipes/% drivers/%:
	$(MAKE) -C build $@
