# build

The build system that turns this tree into kernels, modules, packages and media.

- [pkg/](pkg/): the packaging framework, which builds a package from its
  `package.sh` and generates its pkginfo, catalog line and index.
- [hosttools/](hosttools/): the host tools whose output Amix reads (gencat,
  bdftopcf, mkfontdir, imake, makedepend, amix-xcpp), built from our pinned
  sources; every recipe takes them in place of the build host's.

`make -C build test` runs the framework's host tests, gencat's among them;
`make -C build selftests` the ones that need the toolchains or a distfile,
`hosttools/tests/test-hosttools` among them.
