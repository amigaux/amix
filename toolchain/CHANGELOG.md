# Changelog

## 2026-10-31 — container-kit.sh prints kernel/dlm's kit.digests (bfcfe76)

container-kit.sh prints kernel/dlm's kit.digests lines instead of computing its own digests; CI's `^kit ` grep is
unchanged.

## 2026-10-31 — the 68040/68060 cut's container inputs (52171b5)

netbsd-syssrc.distfile pins NetBSD 10.1's syssrc.tgz (79497697 B, sha256 76a600e7…) at our copy on
amigaux/amix-distfiles; a distfile pin is `<URL> <sha256>`, named .distfile so the image's cache key does not read it.
fetch-distfile puts the file in out/cache only when its sha256 matches; AMIX_DISTFILES=<dir> is a local override.
m68k-gnu-bin links the m68k-linux-gnu-* tools the port's scripts call to gcc14's m68k-elf-* (P-38 S1.4); the port's
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
