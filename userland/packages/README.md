# userland/packages

Outside software built from upstream sources, packaged for Amix and shipped in
the userland catalog.

- Flat: one directory per package, named after the package.
- Each package's metadata is its `package.sh`, plain shell `KEY=value` lines.
  The installer set (`SET`) and the category (`CATEGORY`) are fields there,
  not directory levels.
- Where a package carries userland source of our own, it lives in
  `<name>/src/`.
- A package enters this directory only once it builds and is packaged.

Our own kernel-space code is not here: drivers and modules keep their recipe
next to their code under `kernel/`.
