# Changelog

## 2026-11-20 — gcc14 pinned to release-1.1 9d13dcd: fold-mem-offsets off (15a66acd)

gcc14-cross-amix release-1.1 9d13dcd: fold-mem-offsets off in the specs (a GCC 14.2 m68k -O2 miscompile: a store one element too far) and the PR 126121 bset/bclr fixes. Tree 78ce903e; cc1, libgcc.a, libamixc99.a, the specs and libamixrt.so.1 (f18b7635) change; the init objects do not.

## 2026-11-20 — gcc14 pin to the fork's next 413f38e: fold-mem-offsets off (73fee0f5)

The specs pass -fno-fold-mem-offsets at every level (GCC 14.2.0's pass dropped an add that a memory-to-memory move's destination still used, so a store went one element too far), and gcc-0003 fixes the pass for -ffold-mem-offsets. gcc14-cross-amix.tree is 5357d750; cc1, libgcc.a, libamixc99.a, the specs and libamixrt.so.1 (f18b7635) change, with libstdc++ and libsupc++; the init objects and binutils stay. The fork's test-wrong-code.sh is in the image. image.ref still names the d0082c9 images until the new pair is published.

## 2026-11-20 — image.ref names the build images published from next (f055fb8c)

dist @sha256:f19db483…, media @sha256:13aad17f… (gcc-cross-amix 33ebadc, gcc14-cross-amix d0082c9, amix-system 988b0f8), published under their pinned tags only (PINNED_ONLY=1), so dist and media stay on master's images; make tools takes them by digest, and they compare equal to the images built here.

## 2026-11-20 — publish-image PINNED_ONLY=1 (ad1411a1)

With PINNED_ONLY=1, publish-image tags and pushes only dist-<pins> and media-<pins> and leaves the floating dist and media tags on the release line's images; any value other than 0 or 1 is refused before the checks. test-tools 73/73.

## 2026-11-20 — image.ref names the build images published from 7df961d1 (528b29a6)

dist @sha256:03a597df…, media @sha256:3fc555dd… (gcc-cross-amix 33ebadc, gcc14-cross-amix c806d49, amix-system 988b0f8); make tools takes them by digest, and they compare equal to the images built here.

## 2026-11-20 — rpcgen.distfile falls back to our copy (d51f29be)

rpcgen.distfile names our copy of rpcsvc-proto 1.4.4 (amigaux/amix-distfiles) as its fallback; test-tools checks, offline, that a failing original falls back to it and that other bytes are refused.

## 2026-11-20 — gcc14 pin to the fork's next d0082c9 on the development line (b059b546)

d0082c9 is next with release-1.1 merged in: library names first in .dynstr on top of the PR 126121 patches. gcc14-cross-amix.tree is 13d30d30; among the pinned files only libamixrt.so.1 changes (0ae586a7, the bytes amixrt 1.0-3 ships), and cc1 stays 13ed718's. Linked programs differ in .dynstr order only; static archives are unchanged. image.ref still names the dcfd12d images.

## 2026-11-19 — ksh in the build container (622777ba)

The build container installs ksh (ksh93u+m 1.0.8) from the pinned snapshot, for CDE's ksh build scripts; TOOLCHAIN.sha256 unchanged.

## 2026-11-19 — autoconf, automake and libtool in the build container (30b47129)

The build container installs autoconf 2.71, automake 1.16.5 and libtool 2.4.7 from the pinned snapshot, for recipes that regenerate their build files (CDE's autogen.sh); exact package versions in docs/build-tools.md, since generated files depend on them. TOOLCHAIN.sha256 unchanged.

## 2026-11-19 — host TI-RPC in the build container (97e5d71f)

The build container installs host TI-RPC (libtirpc-dev, libtirpc3t64 1.3.4) from the pinned snapshot, for the host ToolTalk CDE builds to run tt_type_comp; types.xdr is XDR, so its bytes do not depend on the host. No toolchain bytes change (TOOLCHAIN.sha256 unchanged).

## 2026-11-19 — rpcgen, Tcl and OpenSP in the build container; gcc14 pin to release-1.1 c806d49 (5d2eb1c4, 6aa74d06, e692736a)

rpcgen from rpcsvc-proto 1.4.4 (rpcgen.distfile) in /opt/amix/host/bin; test-rpcgen builds its -b and -5 output for Amix (amix-rpcgen.h, -Wno-unused-variable; no hyper, libnsl has no 64-bit XDR). tcl8.6, tcl8.6-dev and opensp come from the snapshot, for CDE's DocBook chain. gcc14-cross-amix.pin is c806d49 (release-1.1: 1.1 plus library names first in .dynstr), gcc14-cross-amix.tree ceb1ce69; among the pinned files only libamixrt.so.1 changes (0ae586a7). Linked programs differ from 1.1 in .dynstr order only; static archives are unchanged.

## 2026-11-18 — GCC 14 at gcc14-cross-amix 13ed718 on the development line (be9881ed)

The fix for GCC PR target/126121 (a wrong bit when a memory byte's bit is set or cleared with a bit number of 8 or more) and a guard against the bfclr-at-(7 - n) form that fix leaves. Only cc1 changes; the runtime libraries are byte-identical. gcc14-cross-amix.tree is 166b04f8. The image carries the check-bset-mem.py gate. image.ref still names the dcfd12d images until the new pair is published.

## 2026-11-16 — images built on amix-system 988b0f8; gcc-cross-amix's address (ba14fb76, 0ff268f8)

gcc-cross-amix.pin names github.com/amigaux/gcc-cross-amix (commit 33ebadcf unchanged). The GCC 14 sysroot holds the stock usr/sbin/shutdown, so gcc14-cross-amix.tree is 174b16e0. image.ref names the published images built from this: dist @sha256:2df4aad2…, media @sha256:bee8f2d0….

## 2026-11-11 — make tools pulls the published build images (630e5f71)

image.ref names the published build images, ghcr.io/amigaux/amix-toolchain dist @sha256:2fa480cf… and media @sha256:5e063fef…, so make tools pulls and checks them instead of building them; TOOLS_FROM_SOURCE=1 builds them and compares.

## 2026-11-11 — make tools can take the build images ready-built (66798f35)

image.ref names the published images by digest. image-pull pulls them and checks them (check-image, extract-g14.sh --check, container-media.sh --check, new) before tagging, or compares them with images built here. publish-image pushes the checked pair (the linux/amd64 image alone, without the provenance index) and prints image.ref's lines.

## 2026-11-10 — the base packages fall back to our copy on amix-distfiles (73085f7f)

base-ca-certificates.distfile and base-openssl.distfile name a second source, our copy in the amix-distfiles release toolchain-base-20261028 under the upstream file name, so a first make tools gets past a snapshot.ubuntu.com outage; the sha256 decides. test-tools checks that the release's date is the Containerfile's snapshot.

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
