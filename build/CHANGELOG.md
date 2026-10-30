# Changelog

## 2026-10-30 — build/pkg: the packaging framework (12153bd)

pkgbuild.sh builds and rolls a package from its package directory in two styles (styles/configure.sh,
styles/make.sh). pkgmeta checks package.sh and generates pkginfo, the catalog v1 line, the names/cats/deps/sets.conf
lines and the packages index, and holds the one-version-per-name guard over recipes, catalogs and staged packages.
pkginfo and catalog lines equal the interim driver's byte for byte for diffutils, bzip2 and coreutils. Host test
`make -C build test` (36/36), run in CI.
