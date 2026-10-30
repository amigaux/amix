# build

The build system that turns this tree into kernels, modules, packages and media.

- [pkg/](pkg/): the packaging framework, which builds a package from its
  `package.sh` and generates its pkginfo, catalog line and index.

`make -C build test` runs the framework's host tests.
