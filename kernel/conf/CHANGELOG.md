# Changelog

## 2026-10-31 — the kernel-space catalog's names.conf (854f971)

The 23 pkginst → catalog-name mappings of the kernel-space catalog (loader, kernels, module packages) move in from
amix-packages, where its round trip wrote them into each staging root; byte-identical to candidate f25448c8's and the
record fff860dc's. make dist's catalogs step passes the file to gen-catalog as the kspace conf. It must not overlap
userland/pkgtools' names.conf.
