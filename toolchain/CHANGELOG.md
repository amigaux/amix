# Changelog

## 2026-11-10 — distfiles kept in out/cache; TOOLS names xorriso (971b4f4)

make tools keeps the build images' distfiles (the two base packages, amitools) in out/cache, so a second run doesn't need the Ubuntu snapshot service. The media image's TOOLS begins with xorriso's version line.

## 2026-11-07 — gcc14 tree digest with amix-system debb2e1 (4e73603)

gcc14-cross-amix.tree is d1964ac8, the GCC 14 build with amix-system debb2e1's in.ftpd in its sysroot; CI's image check passes again.

## 2026-11-05 — a frozen image (b62624a, 7bce020, 141c454)

`container-build.sh` exports amix-system at its pin, as it does the toolchains, under a fixed umask, and checks that exported tree; a host's umask and a working copy's empty directories no longer reach the image. The base image's `ca-certificates` and `openssl` are the snapshot's, pinned by sha256 in `base-*.distfile` and installed before apt reads any archive, so the build no longer uses the live archive, and TLS stays verified. `base-*.distfile` joins the image's cache key. `docs/BUILDING.md` says when the image's freeze changed and what that was measured to do.

## 2026-11-05 — image-manifest (535f3f6, eef9048)

New tool `toolchain/image-manifest`, every file of an image. `test-tools` stops if it has no scratch directory.

## 2026-11-05 — amitools falls back to our copy (044f81f)

`amitools.distfile` falls back to a release asset of amigaux/amix-distfiles; the bytes are the same.

## 2026-11-05 — the media image retries the Ubuntu snapshot (9b85218)

As the build image does.

## 2026-11-05 — a media image (55fd20d)

`Containerfile.media` and `container-media.sh` put xorriso and amitools 0.8.1 on top of the build container, in `/opt/amix-media`; the build container is not rebuilt.

## 2026-11-02 — README: SOURCE_DATE_EPOCH stays fixed across pin changes (a7a6ad1)

The build image's SOURCE_DATE_EPOCH is fixed in the Containerfile and kept across toolchain pin changes, so every static archive stays byte-identical where a pin changes nothing.

## 2026-11-01 — gcc-cross-amix pinned at 33ebadc (c9c2cc0)

The as wrapper keeps option values (--defsym, -I, …) with their options, and the image runs the fork's make check after test-hello; gcc is built as i686 host code (gcc-i686-linux-gnu, libc6-dev-i386-cross). Kernel, kit and module bytes are unchanged but for the pin tag gcc-2.7.2.3-33ebadc.

## 2026-11-01 — gcc14-cross-amix pinned at 43825b2 (b368e68, 358d5a2)

- gcc14-cross-amix 43825b2 adds libamixrt.so.1 and runs library constructors after the program's start-up; snprintf/vsnprintf pass a double as two words, so libamixrt.so.1 runs without an FPU. Tree 8efb932a (6011 files). gcc14-pin.sh pins libamixc99.a and the specs anew and adds amix_init.o, amix_initS.o and libamixrt.so.1; the image runs test-amixrt.sh and copies libamixrt.so.1 into the sysroot's usr/lib.

## 2026-11-01 — gcc14-cross-amix pinned at feec32e: gas keeps PIC relocations (c82064e)

feec32e's binutils patch makes gas keep a PIC relocation against an exported symbol, so a library's pointer to its own
exported data binds to the program's copy. Only the assembler changes: the tree digest is 1cd216fd (5976 files);
cc1, libgcc.a, libamixc99.a and the specs are as at f40055b. The image also runs the fork's test-pic-globals.sh.

## 2026-10-31 — gcc14-cross-amix pinned at f40055b: gcc -shared (3162004)

f40055b adds `gcc -shared`, libamixc99's __cxa_finalize for shared libraries, and library constructors run after the
program's start-up. The tree digest is 5a0dbb99 (5967 files); libamixc99.a (1ac4df85) and the specs (3dd30d46)
change, cc1 and libgcc.a do not. The image runs the fork's test-shared.sh and test-compat-host.sh and keeps no test
output. Comments, docs and messages state the technical fact without internal ids (5d2e382).

## 2026-10-31 — the gcc14 sysroot's links into /usr/amiga and /usr/ucblib resolve (857c7cb)

The new toolchain/sysroot-links, run by the Containerfile, makes the sysroot's absolute links whose target is inside
the sysroot relative: usr/lib/libscreen.so, usr/include/amiga, usr/ccs/lib/libdbm.a, usr/ccs/lib/libucb.a,
usr/lib/font. Other absolute links stay. gcc14-cross-amix.tree moves to 4c9e9428 (the sysroot +565 files; the rest
of the tree unchanged). test-tools 18/18.

## 2026-10-31 — the m68k-gnu-bin shim does not reproduce -52's FPSP 040 (369daff)

binutils 2.43.1 relaxes the FPSP 040's stan.s:231 `lea PITBL+0x200,%a1` to PC-relative, two bytes shorter than the
Ubuntu 2.46 that cut 68060-261031-52; the k46 line is re-cut as -53 with the shim. The earlier "byte-identical" note
is withdrawn.

## 2026-10-31 — a .distfile names the original first, our copy second (80d9050)

A .distfile is `<URL> <sha256> [<URL>...]`, every URL https; netbsd-syssrc.distfile names archive.netbsd.org first and
our amix-distfiles copy second. test-tools 14/14.

## 2026-10-31 — fetch-distfile uses the URL when AMIX_DISTFILES lacks the file (b880adb)

toolchain/fetch-distfile follows amix_fetch's rule: a pinned local copy first, else the URL (it used to refuse when
AMIX_DISTFILES lacked the file). test-tools 12/12, now offline.

## 2026-10-31 — gcc14 in the container builds dlm's box binaries byte-identical (38feabe)

toolchain/README.md records that the container's gcc14 builds kernel/dlm's box binaries byte-identical to the
workstation build: kbootset 1511ef9b (-28's) and modadmin 74aa6272 (-9's).

## 2026-10-31 — container-kit.sh prints kernel/dlm's kit.digests (bfcfe76)

container-kit.sh prints kernel/dlm's kit.digests lines instead of computing its own digests; CI's `^kit ` grep is
unchanged.

## 2026-10-31 — the 68040/68060 cut's container inputs (52171b5)

netbsd-syssrc.distfile pins NetBSD 10.1's syssrc.tgz (79497697 B, sha256 76a600e7…) at our copy on
amigaux/amix-distfiles; a distfile pin is `<URL> <sha256>`, named .distfile so the image's cache key does not read it.
fetch-distfile puts the file in out/cache only when its sha256 matches; AMIX_DISTFILES=<dir> is a local override.
m68k-gnu-bin links the m68k-linux-gnu-* tools the port's scripts call to gcc14's m68k-elf-*; the port's
FPSP/ISP objects build byte-identical through it. New host test toolchain/test-tools 12/12 (a CI step).

## 2026-10-30 — apt and cache-restore retries; old images pruned (b352285, de7b1e0)

The image build retries apt against snapshot.ubuntu.com (each file 5 times; an update that skipped an index now
fails and is tried 4 times, 2 minutes apart). CI's kit job tries a failed cache restore once more, and a push that
saves a new image deletes the cached images of every other key; the tests job's apt retries too.

## 2026-10-30 — gcc14 pinned to the build container's build (5bd9c23)

gcc14-cross-amix b51ff39 is pinned to the build container's reproducible build (identity gcc14-cross-amix.tree
3d3ca2fe, the digest of its file list; two no-cache builds identical). Its sysroot moves inside the prefix, so the
toolchain is relocatable; extract-g14.sh copies it to out/toolchain/gcc14-cross-amix on the host and checks every
file. CI checks the image's gcc14 against the pin. Generated code is identical to the old local compiler's; libraries
differ only in debug info and build-path strings.

## 2026-10-30 — CI names the runner's uid in the selftests container (63bb482)

CI's packaging harness selftests run with a passwd and group entry for the runner's uid: pkgtools' removef smoke test
asks `id -un` and failed under the unnamed uid 1001 (run 41091764355).

## 2026-10-30 — CI kit job (5b376ee)

CI fetches amix-system at system/amix-system.pin (62f7132) and checks it against MANIFEST.sha256 and SYMLINKS
(system/fetch-amix-system, system/check-amix-system), builds the toolchain container or loads it from the Actions
cache, then runs make kit, kit-test and both lines of every module in the container (container-kit.sh); kit digests
and module sha256 go to the step summary. Module bytes equal the main checkout's: monsw 1f53a31b/962709ca, ramdisk
5523d853/054467f6. container-build.sh uses check-amix-system. Not required for merges.
