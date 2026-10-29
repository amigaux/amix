# system

The Commodore system files the build takes as its one system input. They
live in a separate public repository, `amigaux/amix-system`, and never in this
one; this directory only describes them.

## What amix-system holds

| Path | What |
|------|------|
| `kernels/2.1/unix` | the retail AMIX 2.1 kernel, `stand/unix` as shipped |
| `kernels/2.1c/unix` | an AMIX 2.1c kernel; 2.1c is relinked on the machine at install time, so this is one such link, the one the 68040/68060 port patches |
| `usr/sys` | the relink kit: the top `Makefile`, `master.d` and the pre-linked objects the 68030 kernel is cut from |
| `usr/include` | the system headers |
| `usr/lib`, `usr/ccs` | the libraries, startup objects and the C compilation system |
| `usr/X` | X11: headers, libraries, fonts and clients |
| `floppies/2.1/amix_21_boot.adf` | the retail 2.1 boot floppy: the bootstrap and the installation kernel |
| `floppies/2.1/amix_21_root.adf` | the retail 2.1 root floppy: the miniroot the installer runs from |
| `floppies/2.1/amix_21_patch.adf` | the patch disk: a shell script and a compressed archive of patches that bring an installed 2.1 to 2.1p2a; it holds no kernel, and the 2.1c kernel is relinked on the machine when the patches are applied |

The `usr/` tree is AMIX 2.1c at patch level 2a, as installed, with symbolic
links kept as the installation made them (several point at absolute paths on
the machine). One install-time choice is left out: the timezone link
`usr/lib/locale/TZ/localtime`. It is the sysroot both cross toolchains are
built against; see `toolchain/README.md`.

## The files here

- `MANIFEST.sha256`: the sha256 and path of every regular file in
  amix-system, in `sha256sum` format, sorted by path.
- `SYMLINKS`: every symbolic link in amix-system, as `path -> target`.

Check a checkout of amix-system against them from its top directory:

```sh
sha256sum -c --strict --quiet /path/to/amix/system/MANIFEST.sha256
```

The manifest is regenerated the same way it was made:

```sh
find floppies kernels usr -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
```

## Why the hashes are here

`tools/privacy-check` refuses any file in this repository whose sha256 is in
`MANIFEST.sha256`, under any name and in any directory (an empty file matches
nothing). A Commodore file can therefore only reach the public tree through
amix-system, and a part we rebuild from source here is a new file with a new
hash.
