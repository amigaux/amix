# Changelog

## 2026-10-30 — the packaging harness in the amix layout (5f48444)

build/pkg/common (moved in with the packages, 5649328) finds itself through AMIX_PKG_COMMON and builds into out/pkg.
The gate060, gate-gcc14 and onever selftests moved to build/pkg/tests and take the tree from layout.sh; `make -C build
selftests` runs them in the CI kit job (onever skips without the kspace catalog of record; gate-gcc14 skips because the
container's gcc14 is not the pinned prefix). The build container gains cpio. diffutils rolls from the amix layout with
sum -r identical to its recorded build.

## 2026-10-30 — build/pkg ready for the packages move-in (d9aa6fd)

pkgbuild.sh defaults to build/pkg/common; layout.sh gives the harness the tree: toolchains by GCA/G14 (the harness's
gcc14 pin must equal toolchain/gcc14-cross-amix.pin), pkgtools' host pkgmk/pkgtrans and scan060.py, kernel/dlm and
kernel/modules in-tree, output in out/pkg; an AMIX_PKG_COMMON naming amix-packages' recipes/common still works as it
is. New: styles/hooks.sh; source in the tree (src/, or SRCPKG's src/) when URL/SHA256 are unset; `pkgmeta index` writes
INDEX.md, never a README; index and fragments --check; check-packages in CI. VENDOR stays amix-packages. test-pkgmeta
59/59, test-pkgbuild 39/39; diffutils, coreutils and bzip2 build identically through the new driver.

## 2026-10-30 — build/pkg: the packaging framework (12153bd)

pkgbuild.sh builds and rolls a package from its package directory in two styles (styles/configure.sh,
styles/make.sh). pkgmeta checks package.sh and generates pkginfo, the catalog v1 line, the names/cats/deps/sets.conf
lines and the packages index, and holds the one-version-per-name guard over recipes, catalogs and staged packages.
pkginfo and catalog lines equal the interim driver's byte for byte for diffutils, bzip2 and coreutils. Host test
`make -C build test` (36/36), run in CI.
