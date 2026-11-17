# Changelog

## 2026-11-17 — module-floor-base in kbootset.conf (072be71b)

kbootset.conf: module-floor-base 1.1.0.261114-45, the kbootset 1.1.1 ships (C2-2 v8). The xsurf rows lose kbootset= when the catalog is regenerated; no package changes.

## 2026-11-15 — kbootset.conf: the floor of the published xsurf 1.0.0-3 (adeb1136, a90f0afa)

kbootset.conf names the kbootset floor of the published xsurf-k30/-k46 1.0.0-3 (1.1.0.261114-45), which predate APKG_KBOOTSET; the header and the README name module packages.

## 2026-11-15 — catalog names for va2000 (51663042)

names.conf names va200030/46 (va2000-k30/-k46).

## 2026-11-14 — catalog names for xsurf and buddha (1760165f)

names.conf names buddha30/46 (buddha-k30/-k46) and xsurf30/46 (xsurf-k30/-k46).

## 2026-11-02 — kbootset floor 1.1.0.261102-35 (3cc63c4)

The kbootset floor of kernel-k30-m -68 and kernel-k46-m -56 and -57 is 1.1.0.261102-35: -34 gives card 1's controller key for card 2's disks (c10–c17), and installing to an IDE disk on card 2 needs the fix. The packages are unchanged; only the catalog's kbootset= key moves.

## 2026-11-01 — kbootset.conf (690f468, 609ad20)

The kbootset floor 1.1.0.261101-34 for kernel-k30-m -68 and kernel-k46-m -56 and -57, whose sidecars predate kbootset-min=.

## 2026-11-01

- Catalog names zz9kbus-k30/-k46 and zz9ksvc-k30/-k46 (262b717).

## 2026-10-31 — names.conf: random30 → random-k30, random46 → random-k46 (2dd65c3)

The catalog names of the random module's packages (kernel/modules/random/pkg).

## 2026-10-31 — the kernel-space catalog's names.conf (854f971)

The 23 pkginst → catalog-name mappings of the kernel-space catalog (loader, kernels, module packages) move in from
amix-packages, where its round trip wrote them into each staging root; byte-identical to candidate f25448c8's and the
record fff860dc's. make dist's catalogs step passes the file to gen-catalog as the kspace conf. It must not overlap
userland/pkgtools' names.conf.
