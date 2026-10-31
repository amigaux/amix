# Changelog

## 2026-10-31 — make dist's kspace step calls each kernel/<dir>/pkg/build.sh (880ede1)

The kspace step runs every kernel/<dir>/pkg/build.sh in provider order (kernel/dlm, kernel/k30, kernel/port, each
kernel/modules/<m>, each kernel/drivers/<d>) with AMIX_BUILD_ROOT=out/build/kspace, copies their .pkg files into
out/kspace/pkgs and runs the one-version guard. A directory without a build.sh is named with its owner and the step
exits 3 after running the ones present; a failing build.sh stops it. test-dist 21/21.

## 2026-10-31 — the lock format and make lock (3be5063)

release/README.md specifies `#amix-lock 1` (P-38 S1.6): the head (the amix commit, the epoch rule, a `dirty` line when
tracked files differ, the image); the inputs (every pin, distfile and the system manifest); the outputs (kit.digests,
modules, packages and catalogs per space, media, each by sha256); and the named exceptions. Sections in a fixed order,
lines sorted, one build one lock. build/mklock writes out/lock as dist's last step; `make lock LOCK=<file>` writes
nothing and refuses a build whose lock differs, naming each line. test-lock 12/12.

## 2026-10-31 — make dist exists: the driver, partial targets, docs/BUILDING.md (bfcfe76); static libraries as ar D writes them (56ffa22)

build/dist.sh is the driver (P-38 S1.5), build/Makefile has its targets and the top Makefile only delegates. Steps in
order: kit, kernel-k30, kernel-k46, modules, drivers, kspace, userland, catalogs, media, lock; dist runs them all and
stops at the first that fails or is not there yet (exit 3, naming its P-38 step). kit, modules and userland build. Each
step runs in the build container as the calling user, the checkout at /src and the system input read-only at /system;
it refuses a missing or mismatched system input and a shallow clone. docs/BUILDING.md describes the steps, out/ and the
reproducibility rules. A payload's static libraries get the member headers `ar D` writes (arnorm.py; dsnorm refuses
otherwise). test-dist 18/18, test-arnorm 6/6.

## 2026-10-31 — the engine normalises the roll; dsnorm.py only checks it (d5c4eb5)

The roll leaves the normalising to pkgtools' pkgmk and pkgtrans (ad02a5a), which write the datastream normalised under
SOURCE_DATE_EPOCH; dsroll.sh no longer touches the payload, control files or spool modes, and common/sortedfind/ is
gone. dsnorm.py is now a check that never writes: it refuses, naming the fault, a datastream that is unsorted, not
newc, with ino out of archive order, uid/gid/dev not 0, an mtime or pkgmap modtime off the epoch, a wrong directory
nlink or a payload mode that differs from pkgmap's. The host-path and CLASSES/PSTAMP gates stay. repro-selftest 7/7.

## 2026-10-31 — gcc14 remaps build paths; a host path in its payload refused (655529c)

gcc14-env.sh puts -ffile-prefix-map on CC and CXX (P-38 S1.3): the build tree becomes /build, the checkout /src and the
toolchain /gcc14, the build tree's map last. The roll refuses a build-host path in a gcc14 payload; for the period
compiler, which has no such flag and gets fixed paths from make dist's container, it still only reports one.
repro-selftest 7/7.

## 2026-10-31 — the roll refuses a class CLASSES does not list; module node classes (e9f43c6)

The roll refuses, before pkgmk, an object whose class pkginfo's CLASSES does not list (stock pkgadd installs only the
listed classes and skips the rest silently, while pkgmk only warns), and a pkginfo without PSTAMP (pkgmk would write the
build host's name and the date). kpkgroll's pure-files gate takes a module's device node in its module's class (the
mod.d name, amix-dlm C3-5 v18 §1.2), or in none for a package minted before v18. New host test test-classes 13/13.

## 2026-10-31 — the roll's epoch is the package version's own (a73c4c7)

P-38 D-b: pkgbuild.sh gives the roll package.sh's new optional SOURCE_EPOCH key (seconds; pkgmeta refuses anything
else); without it, the time of the last commit that changed the package directory; never the environment's
SOURCE_DATE_EPOCH (such as the build container's). Without a key and without a commit, the build is refused.
test-pkgbuild 65/65 with a hostile SOURCE_DATE_EPOCH set; repro-selftest 6/6.

## 2026-10-31 — the package roll is byte-reproducible (01aad1b)

dsroll.sh is the pkgmk/pkgtrans step of both amix_pkgroll and amix_kpkgroll: the staged payload and control files are
set to SOURCE_DATE_EPOCH before pkgmk; dsnorm.py gives every spool object its pkgmap mode and the epoch and sets
pkgmap's modtime column to it; pkgtrans archives in sorted order; each newc header is rewritten in place (ino renumbered
in archive order with hard links kept together, uid/gid/dev 0, mtime the epoch). A control file naming the build tree
is refused. pkgbuild.sh takes SOURCE_DATE_EPOCH as given, else the package directory's last commit time; kmodpkg uses
KM_SOURCE_EPOCH. Two rolls from different paths, times and umasks give identical bytes (repro-selftest.sh, test-dsnorm).

## 2026-10-31 — check-packages covers userland/base/pkg; stock and directory man pages (f5b513b)

pkgmeta check, index and fragments take several packages directories as one catalog: one version guard and one owner
per conffile across them, one INDEX.md and conf/ in the first, other directories' packages linked by relative path.
check-packages checks userland/packages and userland/base/pkg together and skips a missing directory. The man-page
warning counts a directory's page for the files in it and the stock page of a STOCK_ETC file's name (case blind), from
build/pkg/stock-pages (3558 names, made by `pkgmeta stock-pages <whatis>`); it still warns where no page exists.
test-pkgmeta 145/145.

## 2026-10-31 — STOCK_ETC takes stock /etc defaults from amix-system (1608a4a)

A package.sh key STOCK_ETC names stock /etc files by path; after the stage hook the driver copies each from the
amix-system checkout and refuses one whose sha256 is not system/MANIFEST.sha256's or that the stage hook also
staged. pkgmeta check refuses a path not under /etc, not a regular file in the manifest, or not exactly one f or e
prototype line. The bytes never enter amix. The period 68060 datastream gate passes a data-only package.
test-pkgmeta 128/128, test-pkgbuild 61/61; the base package's seven conffiles roll and install equal to amix-system.

## 2026-10-30 — SYSTEM_PATHS, the base set, period builds, ESSENTIAL (ccb02f3, 9dbd943)

pkgmeta check refuses a prototype object outside PREFIX, /opt/amix/man, /etc, /var and the paths a new SYSTEM_PATHS
key names (a base package's /usr paths). SET gains `base` (P-36: every install), written first in sets.conf.
CONFFILES must be under /etc or /var. TOOLCHAIN=period builds through the driver: binutils 2.8.1's nm has no -D for
the stock libc.so.1, which had emptied the undefined-symbol gate and refused every period executable. ESSENTIAL=yes
writes APKG_ESSENTIAL=yes into pkginfo (apkg then refuses removal); any value but yes or no is refused.
test-pkgmeta 118/118, test-pkgbuild 55/55; a period base-style package rolls and installs under heirloom pkgadd -R.

## 2026-10-30 — the man-page warning reads /opt/amix/man/<sect>/<name> (92e2f36)

pkgmeta's man-page warning knows the packages' page layout (userland/packages/docs/man-pages.md): a file under man/
whose parent is a bare section number is a page named by its whole basename, aliases included; the classic
man<sect>/<name>.<sect> form still works. check-packages: 0 warnings over 13 recipes (was 13). test-pkgmeta 96/96.

## 2026-10-30 — the roll makes CONFFILES lines e conffile with their scripts (936af77)

pkgroll's amix_conffiles (P-36 W3, part 2) makes each CONFFILES line of the work prototype `e conffile` and adds
userland/pkgtools' i.conffile and r.conffile beside it as `i` lines, with no host path in the prototype; a path not
rewritten exactly once refuses the roll. Without CONFFILES the bytes are unchanged. New host test test-conffile
14/14; a toy package rolled at -1 and -2 keeps an edited file across pkgadd -R and writes .new.

## 2026-10-30 — CONFFILES, run-level link bands and man-page warnings (318c390)

package.sh may list CONFFILES (P-36 W3, part 1). pkgmeta check refuses a CONFFILES path that is not an f or e line of
the prototype or is on two of its lines, one under PREFIX or outside /etc and /var or relative, an e object CONFFILES
does not list, one conffile listed by two packages, an object under /etc/rc.d, and a run-level link outside the boot
bands; pkginfo says CLASSES=none conffile for such a package and is unchanged otherwise. pkgmeta check warns about
commands and config files without a man page (5 current packages flagged). test-pkgmeta 93/93.

## 2026-10-30 — the s5 gate marks long-named packages UFS-only (a77c318); interim driver removed (ca7a835)

pkgroll.sh's s5 gate (GATE 3, amix_s5_mark) marks a package with an object basename over 14 bytes UFS-only:
APKG_FSTYPE=ufs goes into its pkginfo and the s5 rule is waived (P-35); a malformed APKG_FSTYPE, or one naming s5 when
the package has long names, is refused; packages without long names roll byte-identical. New host test test-s5mark
26/26. The interim driver build/pkg/common/pkgbuild.sh is removed; build/pkg/pkgbuild.sh drives every package.

## 2026-10-30 — gcc14-pin.sh re-pinned to the container build (5bd9c23)

gcc14-pin.sh pins cc1 ff4241a6, libgcc.a bb531a7d, libamixc99.a 78436c8b, specs 0e0d3ff1 (the container build of
b51ff39); G14 defaults to the extracted copy in out/toolchain/gcc14-cross-amix. gate-gcc14-selftest runs in CI without
the skip (PASS 19). Every gcc14 package is re-minted on the new pin before the next publish.

## 2026-10-30 — PROTO skips unlisted parent dirs; optional APKG_DESC (651c753)

pkgbuild.sh's prototype check leaves out staged directories that are only parents of listed paths (/usr and /usr/bin
under PREFIX=/usr/local); staged-only files, links and other directories are still refused, and the ok line names the
skipped parents. package.sh may set APKG_DESC, written to pkginfo after PSTAMP and used as the catalog description;
unset, every pkginfo is unchanged. test-pkgmeta 63/63, test-pkgbuild 44/44.

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
