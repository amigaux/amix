# Changelog

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
