# Changelog

## 2026-11-07 — make tools checks the gcc14 tree digest (03886a3)

make tools checks the build container's GCC 14 against toolchain/gcc14-cross-amix.tree, as CI does, and stops before the media image when the digest differs. A new amix-system pin moves that digest too.

## 2026-11-06 — pkginfo lists the prototype's own classes after conffile (ca687f1)

pkginfo's CLASSES is `none`, then `conffile` when CONFFILES is set, then every other class the prototype names, in the order it first names them, so a device node whose group a conffile creates can be made after that file. The roll accepts classes after `none conffile`. pkgmeta refuses a class name other than 1-12 of a-z and 0-9 starting with a letter, and an object in class conffile that CONFFILES doesn't list.

## 2026-11-06 — kspace stops when a file built beside the packages is missing (9ca599c)

kspace stops with exit 1 when a kernel directory's recipes all roll (exit 0) but leave out a file it must build beside its packages, or leave a symlink there. `kspace_beside` in `build/dist.sh` lists them: kernel/dlm, `amix-cdboot`. An exit 3 stays a gap.

## 2026-11-05 — STOCK_PATCHED (1bbcbb8)

`STOCK_PATCHED` in package.sh, `<path>=<sha256>` words: a stock amix-system file the stage hook patches. The driver checks it against system/MANIFEST.sha256 before the hook and the payload's file against the listed sha256 after it. Needs TOOLCHAIN=period, and nothing may be compiled. Every ELF of the payload must be listed. The listed files are gated (ELF, undefined symbols, 68060) and never stripped. BUILD.txt and the lock carry a `stock` line per STOCK_ETC and STOCK_PATCHED file.

## 2026-11-05 — what make tools needs (77e858e)

`docs/BUILDING.md` says what `make tools` needs: a clone holding the pinned amix-system commit, and https to the Ubuntu snapshot and the toolchains' sources.

## 2026-11-05 — what the proof has shown (b644803)

`docs/BUILDING.md` and `release/README.md` say exactly what the proof has shown, on which machines and commits, and what it hasn't; the claim of the same bytes on every machine is gone.

## 2026-11-05 — a failed download says why and retries; only media may be a gap (f585f48, 6d21a89)

A stock package that can't be downloaded now says why: the fetch's output goes to `out/build/stock-fetch.log` and a failure prints its end. Downloads retry a dropped connection (`--retry-all-errors`); the sha256 still gates the bytes. `dist-proof` allows a gap only in `media`, which isn't in make dist yet; a gap in any other step stops the proof and the summary names its `[MISSING]` line. `dist.yml` prints `df` for both clones' filesystems after the proof, whatever its result. `tools/privacy-allow.txt` no longer exempts `root.shadow` under `media/`; any root hash in the tree is a hit.

## 2026-11-05 — release-check and privacy-check never pass without having looked (50e6735, 120f2b2)

`tools/release-check` no longer passes a 0-byte or truncated image, an empty directory, a file hidden by `.gitignore`, or empty lists, except a declared public rebuild, which says the lists were not used. Its verdict names what it read. `privacy-check` stops when it looked at nothing, and has `--empty-ok`.

## 2026-11-05 — a check that looked at nothing fails (5a0d731, 120f2b2, 4daeb6c, da55dbe)

dist-proof can put its second clone on another filesystem (`ELSEWHERE=`), which exposes directory-order faults; the summary names the machine, each filesystem and any step not compared. An exit 3 with no `[MISSING]` line now fails, and a lock of record works. `dist.yml` prints the runner's CPU, memory and disk, puts the second clone on its own filesystem, and has a `cold_image` input that rebuilds the image and lists every file against the cached one. `mklock`, `check-packages`, `pkgmeta` and the 68060 scan stop when they looked at nothing. A file a recipe builds beside its package reaches `out/<space>/beside/` and gets a `beside` lock line.

## 2026-11-05 — the dist workflow rebuilds as the public would (3e72129)

RELEASE_PUBLIC=1, stock packages from their release assets; its limit for the two runs is 180 minutes.

## 2026-11-05 — make dist runs on past a gap (d94eeb6)

A step's exit 3 no longer stops it: the lock is written and the gaps are named. Each step gets only its own inputs (STOCK had broken kernel-k46). Stock packages are fetched from release assets, the sha256 decides. RELEASE_PUBLIC=1 rebuilds without the private lists, same bytes. The lock records the media tools and the assets' URL file. The top Makefile hands on `apkg` and `release` too.

## 2026-11-04 — kmodpkg's notice headings (408e557)

kmodpkg heads a fork's licence in the copyright file by its component, without the build path.

## 2026-11-04 — What's new: the RAM-disk boot (38cb1f1)

docs: What's new lists the RAM-disk boot beside a software MapROM copy or a reset-proof RAD:.

## 2026-11-04 — release-check reads binaries; CI's merge-base fallback (ddb403c, 62e9598)

tools: release-check searches binary files and package members, images included, for the local patterns, by privacy-check's search and exemptions. ci: a push with no usable previous tip is checked from its merge base with origin/master; the logic moves to tools/ci-privacy-check.

## 2026-11-04 — privacy-check reads binaries (a31b586)

tools: privacy-check searches binary files for the local patterns (also as UTF-16) and refuses compiled Python (*.pyc, __pycache__/) in class 4. The repository's .gitignore now keeps compiled Python out everywhere.

## 2026-11-04 — NOTICES: rdate's acknowledgement (3135981)

release/NOTICES.md adds the acknowledgement rdate's rdate.c and rfc868time.c require ("This product includes software developed by Christos Zoulas.").

## 2026-11-04 — CI's host job checks out the whole history (f502489)

The host job's checkout fetches the whole history, so pkgtools' apkg suite runs its checks of the older client from history too (573 checks, 8 skip lines).

## 2026-11-04 — CI runs the pkgtools tests; NOTICES gains two acknowledgements (2a273e0, 0a0f248)

CI's host job runs `make -C userland/pkgtools test` with the m68k binutils, fakeroot and ncompress installed; PKGTOOLS_REQUIRE makes those tools and the host engine required, so their absence fails the step instead of skipping. docs/ci.md lists the step and the skips that stay. release/NOTICES.md adds the acknowledgements kern46m's floating-point emulation (University of California, Lawrence Berkeley Laboratory) and prngd (University of California, Berkeley and its contributors) require.

## 2026-11-04 — scan060-g14 notes a run without a sysroot (1b58b0f)

scan060-g14.py prints one NOTE when it runs without AMIX_SYSROOT: the known stock data in .text (KNOWN_STOCK_DATA) is then not applied. Its verdicts are unchanged.

## 2026-11-03 — release-check refuses a known-bad module (6b800be)

tools/release-check refuses an artefact carrying a module listed in tools/known-bad-modules.txt: a file or package member whose sha256 is listed, or nine in ten of the module's 512-byte pieces found at any offset in an image, ISO, floppy image or package (each piece found by a 16-byte anchor and confirmed by its sha256, so the list holds no module bytes). The first entry is the z3660scsi build from before its fixed-window gate. A floppy image or a single package is now read as a file instead of refused.

## 2026-11-03 — pkgmeta: a one-level mount point in SYSTEM_PATHS (772f99f)

A one-level SYSTEM_PATHS entry passes only as a mount point: one d line of that path with nothing under it (for the userland cdfs package's /cdrom). A file at the path, anything under it, or a whole top-level tree is still refused.

## 2026-11-02 — release-check's image mode tested on a real ufs (1aba914)

tools/test-release-check reads two ufs disk image fixtures, a clean one and one with a planted shadow hash and private address, fetched as distfiles (amix-distfiles release-check-fixtures-1).

## 2026-11-02 — release step scans with the GCC 14 sysroot; release-allow; gcc14 dcfd12d (c85a9ee, 3709c53, 07db7ea)

- make dist release scans with GCC 14's sysroot, so stock members' tables in .text are data as in the D4 gate.
- release-allow: the NNTP example addresses in pubsrc-2.1 and three 1991 X sources in Xsource-2.1 and X11r5src-2.1.
- gcc14-cross-amix dcfd12d: libamixrt.so.1 installed stripped (22728 bytes); nothing else in the image changes.

## 2026-11-02 — release-check; scan060-g14 section names; make dist apkg and release steps (30317c8, f5cbac3, c4349cb)

- tools/release-check: the content check for published files, moved from the media build: disk images (ufs slices file by file, other slices raw, swap must be zero, no build-box traces), ISOs, and repository trees with each package datastream read member by member; the ROM register and private patterns are given by path.
- scan060-g14 takes each code section's name from objdump -h, so a kernel whose .text has sh_name 0 decodes.
- make dist apkg (APKG and APKGENG into out/apkg) and make dist release (pkgtools' assemble-release into out/release/1.1, checked by release-check); the lock records both.

## 2026-11-02 — scan060-g14 decodes only the executable sections (f07fdb0)

scan060-g14 names each executable section for objdump (-j): with an address range alone, -D also decoded the .debug_* sections at address 0 of an unstripped shared library (libamixrt.so.1) and reported movep.

## 2026-11-02 — the build container carries its pins (3a30b19)

The build container carries the pins it was built from in /opt/amix/PINS; make dist runs toolchain/check-image first and stops on an image built from other pins or without the stamp. A stamped image of 33ebadc/43825b2 has the same TOOLCHAIN.sha256 as the unstamped one.

## 2026-11-02 — scan060-g14 decodes data objects in .text as data (c54a4c7)

scan060-g14 decodes a sized data object in .text (values-Xa.o's _lib_version) as data and runs objdump -D per executable section; under -d the object's hex dump hid the rest of .text and read as instructions.

## 2026-11-02 — make dist lists only tracked module and driver directories (d818fd4)

make dist lists module and driver directories by the files git tracks there (git ls-files). A leftover untracked directory under kernel/drivers or kernel/modules, such as a removed driver's gitignored build output, is no longer a recipe: the kspace step does not name it or exit 3 over it, and the modules step neither builds it nor takes its objects. Rolled bytes are unchanged.

## 2026-11-02 — pkgmeta dirs reads only tracked prototypes (e4aa3cf)

pkgmeta dirs reads only the prototypes git tracks, so make dist's kspace step no longer reads build output (after kernel-k46, kernel/port/build/cuts holds a cut's whole old tree with root bin man directories). In a git checkout dirs lists the tree with git ls-files and refuses when git cannot list it; a tree outside git, such as the tests' temporary trees, is still walked.

## 2026-11-02 — repro-selftest fixture: man directories root sys (122fe12)

The repro-selftest fixture recipe declares /opt/amix/man and /opt/amix/man/1 as 0755 root sys. The shared-directory rule refused the old root bin, and the container selftests failed at pkgbuild.sh.

## 2026-11-02 — MAN_REPLACES (7cf3775)

The package.sh key MAN_REPLACES lists the stock binaries a package replaces as `<binary path> <sect> <page name>` triples. pkgmeta check counts such a binary as documented by its page and refuses malformed entries, a page the prototype lacks, or a missing replaces.d/<PKG>.

## 2026-11-02 — shared directories are 0755 root sys in every prototype (80570cc)

pkgmeta check refuses a recipe whose prototype declares a shared directory (/opt, /opt/amix, /opt/amix/doc, /opt/amix/man and its sections, whatis.d, replaces.d) with other than 0755 root sys. The new pkgmeta dirs applies the same rule to the kernel-space prototypes; check-packages (CI) and make dist's kspace step run it.

## 2026-11-02 — the LLPRINTF gate reads only data sections (2647684)

The LLPRINTF gate reads strings only from an ELF's .rodata* and .data* sections, one section at a time, and reads a file without section headers whole, so code bytes no longer count as format strings (the cfb16 Xzz9000 matched "%Lo" in .text). The gcc14 env exports OBJCOPY.

## 2026-11-01 — FORKPIN sources; @PKG@ and depend in module recipes (67b1827)

pkgbuild builds from a fork a checkout pin names (package.sh FORKPIN: the git archive of its commit, fetched by hash into out/cache/forks/<name>). Module recipes take @PKG@ (the line's instance) in the prototype and KM_FILES, and a depend file as i depend.

## 2026-11-01 — shared-object gates, PREBUILT, the DES tables; fork driver recipes (24a07a6..89c6146)

- pkgbuild refuses a payload whose ELF NEEDs libamixrt.so.1 unless DEPENDS names amixrt. The new package.sh key PREBUILT ships pinned-prefix ELFs (sha-checked, not stripped). A shared object resolves against libc.so.1, the interpreter. The UNDEF gate counts strong undefined references only.
- scan060-g14 knows crypt(3)'s DES tables in .text (libcrypt.a's des_crypt.o, libc's crypt.o) as data by the member's sha256.
- Package recipes for the gayle and cdfs fork drivers under kernel/drivers; cdfs pinned at e63c513.

## 2026-11-01 — kdrv.sh for driver recipes; KM_PKG_VERSION; guarded deletes; What's new (a9ae32e, 1103523, 5b5c455, aa3b502)

build/pkg/common/kdrv.sh is the body of a driver directory's pkg/build.sh: it rolls each recipe for k30 and k46
from the objects make dist's drivers step built, exits 3 with a [MISSING] line for an object not built and 2 for an
unknown name, and runs an optional kdrv_prepare in its own compiler environment. kmodpkg.sh takes KM_PKG_VERSION, a
package-only revision. Every delete on a variable path in build/ and toolchain/ uses ${var:?}. Locks are identical
before and after. docs/WHATS-NEW.md lists new packages and features per release, linked from README.md.

## 2026-11-01 — gates for shared objects and their libraries (bcca619)

scan060-g14.py takes a shared object's function bounds from its STT_FUNC symbols, so a PIC switch's table label no
longer ends a function; executables keep their label bounds. The NEEDED gate checks shared objects too: no
interpreter, a SONAME, the same NEEDED rules; an RPATH may name only the box's own absolute directories under
/opt/amix or /usr; RUNPATH and TEXTREL are refused. pkgbuild's UNDEF gate finds a bare NEEDED through the binary's
DT_RPATH (in the package, then its BUILD_DEPENDS trees, then the sysroot), then in the sysroot's /usr/lib; a NEEDED
found nowhere fails, naming where it looked.

## 2026-10-31 — gcc14-pin.sh at f40055b; make dist's locks re-measured (3162004, 5d2e382, b8e8252)

build/pkg/common/gcc14-pin.sh pins f40055b and its two changed files. dist-proof gives two identical locks; against
the previous lock only the amix commit, the image, the gcc14 pin and the kits' KIT_REV label differ, and of the
packages only amixbch14's BUILD-INFO and PROVENANCE text files (the toolchain line) move. make dist's [MISSING] lines
name the missing input only; the privacy check's class 2 is "local tool files". A top-level CONTRIBUTING.md covers
sending a change, the licence, what never goes in, building and testing, commit messages and bugs.

## 2026-10-31 — make dist builds its own host pkgtools in out/build (781d869)

make dist builds its host pkgmk and pkgtrans in a copy of userland/pkgtools under out/build/pkgtools-host/, never
the checkout's build-host/: build-host.sh bakes its absolute directory into the tools as BINDIR, so tools built in a
checkout on the host named a cpio path the container lacks. A stamp of the copied files' digest skips a rebuild of
the same sources. test-dist 43/43.

## 2026-10-31 — make dist's userland step builds in BUILD_DEPENDS order (e90b0b8)

The new `pkgmeta build-order` lists each recipe after the packages its BUILD_DEPENDS names (a cycle or an unknown
name is refused); `--for` gives one package and what it needs. make dist's userland step and recipes/<name> roll in
that order, so python3 comes after pth and zlib (dist.yml run 41217293592 failed on that). test-pkgmeta 153/153.

## 2026-10-31 — the proof of make dist, run by hand in CI (b43f795)

build/dist-proof WORKDIR [COMMIT] runs make dist twice, from two clean clones at two paths, and compares the locks
(with LOCK=, each is also checked against the lock of record; exit 3 is a known gap). .github/workflows/dist.yml runs
it on workflow_dispatch only (timeouts: job 345 min, image 210, proof 120; image cached under ci.yml's key, which now
covers toolchain/sysroot-links; no registry, no secrets; artifact dist-proof). dist.sh mounts the image's passwd and
group with the caller's uid/gid added, for CI runners. release/README: the lock of record comes when 1.1 is frozen. Local
proof: two identical locks, 93 lines.

## 2026-10-31 — make dist builds kernel-k46; the NEEDED gate takes a path that is its library's SONAME (586d9f1, 118a966)

make dist's kernel-k46 step runs the port's hook kernel/port/cuts/build.sh with GCA, G14 and AMIX_SYSTEM, as
kernel-k30 runs k30's; its `kernel k46` lines go to out/kernels/k46.list and the lock, and a hook that prints none
fails the step. The rehearsal pair reproduces -53's seven sums and rolls kern46m -53 (6384988e), locks identical.
The gcc14 NEEDED gate accepts a DT_NEEDED path when the sysroot library at that path has it as its SONAME
(/usr/lib/libc.so.1; /usr/amiga/lib/libscreen.so as the stock X servers record it); other paths are still refused.

## 2026-10-31 — pkgbuild exports the package epoch for the whole build; two identical rehearsal locks (12c0b43)

pkgbuild.sh works out the package epoch (package.sh SOURCE_EPOCH, else the package directory's last commit) before
configure and exports SOURCE_DATE_EPOCH for the whole build, not only the roll, so GCC's __DATE__/__TIME__ are the
package's own; vim 9.1's version string had made two make dist runs differ. test-pkgbuild 72/72. The rehearsal pair
at 12c0b43 (two clones, different paths) gives byte-identical locks: 81 lines, 20 userland and 8 kspace packages.

## 2026-10-31 — scan060-g14 sizes bfextu and byte-indexed tables (ccbe90a)

A table indexed by `bfextu <ea>,<off>,<w>,%dI` is sized at exactly 2^w entries. A table whose index is provably a
byte or word (an and-mask, or a zero-extended load) and has no compare is sized from its own run of entries, only
when the run ends on a word that cannot be an entry; a NOTE names it as trusted by shape and the D4 gate lists the
NOTEs. A compare's bound is never overridden; two-level dispatches are refused. python3.11: textio.c's table now
sized; _PyBytes_FormatEx's stays UNTRUSTWORTHY. Verdicts on all 120 GCC 14 ELFs unchanged; selftest 21/21.

## 2026-10-31 — kmodpkg: the port commit for the k46 kit; the module's kabi from modcheck (5d283f4)

kmodpkg.sh asks for the kit with the port commit (KM_PORT_COMMIT, else kernel/port/port.pin's hash), so a bare
AMIX_PORT_REPO still gives the k46 kit its include-modelb. The module's kabi is the one modcheck says ok for (the
lowest its imports need, as mkmod tags it), not the kit's KABI: a k30.1.2 module rolls on a k30.1.3 kit and its
.moddata and copyright say k30.1.2. test-kmroot 12/12 (8/12 against the old script).

## 2026-10-31 — the first make dist rehearsal: two identical locks (2234f49, 6f3f516, f86507a, 1781a2c)

Two clean full clones, in the container, at different paths and times, give line-for-line identical locks (the
first such run: kit, kernel-k30, modules, drivers, 12 userland packages, both catalogs). Fixes it needed: the
kspace, userland and recipes steps build the host pkgmk/pkgtrans when a clean clone has none (2234f49); the
build-host-path check passes one-component paths such as /src (f86507a). Also: TOOLCHAIN=none for script-only
packages, where any compile is refused (6f3f516); dlm-src.sh's amix_src_treeish probes kernel/dlm before the root,
since amix has its own top-level Makefile (1781a2c).

## 2026-10-31 — amix-decls.h declares readv, writev, cbrt, copysign, isinf (a651b24); scan060-g14 sizes vim's switch tables (8bfb296)

amix-decls.h declares readv/writev (libc.so.1), cbrt and copysign (libm.a) and makes isinf gcc's builtin, as C99 has it
(isinf is in no AMIX library); what the X11/CDE trial needed for GNU Pth, FFmpeg and vim. The gcc14 060 scanner reads a
bound check before a bias and sizes a constant-index table from its entries (a NOTE names the limit); vim's gate is
CLEAN. gate-gcc14-selftest 20/20.

## 2026-10-31 — the kspace catalog names its packages from kernel/conf (0acf9a5); kernel-k30 runs k30's hook (e39cd58)

The catalogs step passes kernel/conf as the kernel-space catalog's --packages-conf, so a kernel package is catalogued
under its name (zeth46 as z3660eth-k46); a kspace staging dir with packages and no names.conf is refused. make dist's
kernel-k30 step runs `sh kernel/k30/cuts/build.sh` (the cut of record, sums refused if they differ); its `kernel k30
<path> <sha256>` lines go to out/kernels/k30.list and the lock. On the host all seven -63 sums reproduce in 16 s.
test-dist 35/35, test-lock 13/13.

## 2026-10-31 — the original site first, our copy as the fallback (80d9050); a kspace hook's exit 3 (7ce5a35)

amix_fetch tries, in order: the cache, AMIX_DISTFILES, the recipe's URL (the original site), then each fallback; the
sha256 decides every time, and a failed fetch names each source tried. pkgbuild.sh passes our copy as the fallback:
amigaux/amix-distfiles releases/download/<NAME>-<VERSION>/<the URL's file> (2026-10-31). A kernel/<dir>/pkg/
build.sh that exits 3 (an input outside its recipe absent) is recorded as waiting; the kspace step runs the rest and
ends with 3; any other non-zero still fails. test-fetch 12/12, test-dist 31/31.

## 2026-10-31 — KM_ROOT (a7e3dd8); the catalogs step (c8f419a)

amix_kmodpkg reads a recipe's object, VERSION, licences, depend= modules and KM_FILES at $KM_ROOT/<path>: the siblings
by default (amix-packages), the checkout for an in-amix recipe. A refused licence or depend= input now stops the roll
(it ran in a subshell and carried on). make dist's catalogs step calls pkgtools' gen-catalog.py as it is
over out/kspace/pkgs and out/userland/pkgs, with the staging root's confs and each space's own, into
out/{kspace,userland}/{catalog,catalog.md5}; the catalogs carry no time stamp, two runs are identical, and the lock's
catalog line is `catalog <space> md5 <md5> sha256 <sha256>`. test-kmroot 6/6, test-dist 30/30, test-lock 13/13.

## 2026-10-31 — a source from AMIX_DISTFILES (b880adb); kfsmod.sh and kmodpkg.sh take the toolchain from layout.sh (281127d)

amix_fetch reads $AMIX_DISTFILES/<the URL's last component> first and copies it in when it holds the pinned bytes;
other bytes give a warning and the URL is fetched as before; the sha256 stays the pin. Our copies are
amigaux/amix-distfiles release assets (releases/download/<name>-<version>/<file>); make dist passes AMIX_DISTFILES
read-only at /distfiles. test-fetch 7/7, offline. kfsmod.sh's modcheck and rebuild and kmodpkg.sh's modcheck source
layout.sh's AMIX_CROSS_ENV instead of the siblings' gcc-cross-amix (the k30 recipes failed at "modcheck refuses ufs");
test-kfsmod 3/3, including a static check that no common script sources through $AMIX_SIBLINGS.

## 2026-10-31 — a pinned commit is fetched by its full hash only (4952ec6)

git cannot fetch a short hash: make dist refuses a port.pin or fork pin whose commit is not 40 hex digits; the kspace
step pre-fetches port.pin's full commit into out/cache/port-repo; dlm-src.sh's fallback fetches only a full hash and
refuses a short one missing from AMIX_PORT_REPO, keeping the kit's PORT_REV label as given (fixes 38feabe). CI runs z3660eth's host test. test-dlmsrc 8/8, test-dist 26/26.

## 2026-10-31 — make dist's drivers step builds every module on the kit; CI driver host tests (ca08c0e)

The drivers step builds every driver module on both lines against this checkout's kabi 1.3 kit:
kernel/drivers/{a4091,z3660scsi,z3660eth}/module (a4091's also a4kt710) and the forks cdfs, gayle-ide, paula and
z3660rtg, each fetched at its pin by commit into out/cache/forks and built with its own Makefile. Every build starts
clean; z3660rtg links against our own monsw objects, not the retired stand-in. Objects go to out/modules/<line>/<name>
and the lock. Two clean runs give 20 byte-identical objects. CI runs a4091's and z3660scsi's host tests. test-dist 24/24.

## 2026-10-31 — dlm-src.sh takes the toolchain and the port from layout.sh (38feabe)

amix_dlm_build and amix_dlm_kit source layout.sh's AMIX_CROSS_ENV and pass its directory as GCA, instead of reaching
the checkout's siblings (wt/ in a worktree, / in the container). The ABI kit's port is AMIX_PORT_REPO; a recipe's
pinned port commit missing from it is fetched by hash from AMIX_PORT_URL. make dist's kspace step sets both (a cache
repository and port.pin's URL). test-dlmsrc 6/6.

## 2026-10-31 — make dist's kspace step calls each kernel/<dir>/pkg/build.sh (880ede1)

The kspace step runs every kernel/<dir>/pkg/build.sh in provider order (kernel/dlm, kernel/k30, kernel/port, each
kernel/modules/<m>, each kernel/drivers/<d>) with AMIX_BUILD_ROOT=out/build/kspace, copies their .pkg files into
out/kspace/pkgs and runs the one-version guard. A directory without a build.sh is named and the step
exits 3 after running the ones present; a failing build.sh stops it. test-dist 21/21.

## 2026-10-31 — the lock format and make lock (3be5063)

release/README.md specifies `#amix-lock 1`: the head (the amix commit, the epoch rule, a `dirty` line when
tracked files differ, the image); the inputs (every pin, distfile and the system manifest); the outputs (kit.digests,
modules, packages and catalogs per space, media, each by sha256); and the named exceptions. Sections in a fixed order,
lines sorted, one build one lock. build/mklock writes out/lock as dist's last step; `make lock LOCK=<file>` writes
nothing and refuses a build whose lock differs, naming each line. test-lock 12/12.

## 2026-10-31 — make dist exists: the driver, partial targets, docs/BUILDING.md (bfcfe76); static libraries as ar D writes them (56ffa22)

build/dist.sh is the driver, build/Makefile has its targets and the top Makefile only delegates. Steps in
order: kit, kernel-k30, kernel-k46, modules, drivers, kspace, userland, catalogs, media, lock; dist runs them all and
stops at the first that fails or is not there yet (exit 3, naming it). kit, modules and userland build. Each
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

gcc14-env.sh puts -ffile-prefix-map on CC and CXX: the build tree becomes /build, the checkout /src and the
toolchain /gcc14, the build tree's map last. The roll refuses a build-host path in a gcc14 payload; for the period
compiler, which has no such flag and gets fixed paths from make dist's container, it still only reports one.
repro-selftest 7/7.

## 2026-10-31 — the roll refuses a class CLASSES does not list; module node classes (e9f43c6)

The roll refuses, before pkgmk, an object whose class pkginfo's CLASSES does not list (stock pkgadd installs only the
listed classes and skips the rest silently, while pkgmk only warns), and a pkginfo without PSTAMP (pkgmk would write the
build host's name and the date). kpkgroll's pure-files gate takes a module's device node in its module's class (the
mod.d name, amix-dlm C3-5 v18 §1.2), or in none for a package minted before v18. New host test test-classes 13/13.

## 2026-10-31 — the roll's epoch is the package version's own (a73c4c7)

pkgbuild.sh gives the roll package.sh's new optional SOURCE_EPOCH key (seconds; pkgmeta refuses anything
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
key names (a base package's /usr paths). SET gains `base` (every install), written first in sets.conf.
CONFFILES must be under /etc or /var. TOOLCHAIN=period builds through the driver: binutils 2.8.1's nm has no -D for
the stock libc.so.1, which had emptied the undefined-symbol gate and refused every period executable. ESSENTIAL=yes
writes APKG_ESSENTIAL=yes into pkginfo (apkg then refuses removal); any value but yes or no is refused.
test-pkgmeta 118/118, test-pkgbuild 55/55; a period base-style package rolls and installs under heirloom pkgadd -R.

## 2026-10-30 — the man-page warning reads /opt/amix/man/<sect>/<name> (92e2f36)

pkgmeta's man-page warning knows the packages' page layout (userland/packages/docs/man-pages.md): a file under man/
whose parent is a bare section number is a page named by its whole basename, aliases included; the classic
man<sect>/<name>.<sect> form still works. check-packages: 0 warnings over 13 recipes (was 13). test-pkgmeta 96/96.

## 2026-10-30 — the roll makes CONFFILES lines e conffile with their scripts (936af77)

pkgroll's amix_conffiles makes each CONFFILES line of the work prototype `e conffile` and adds
userland/pkgtools' i.conffile and r.conffile beside it as `i` lines, with no host path in the prototype; a path not
rewritten exactly once refuses the roll. Without CONFFILES the bytes are unchanged. New host test test-conffile
14/14; a toy package rolled at -1 and -2 keeps an edited file across pkgadd -R and writes .new.

## 2026-10-30 — CONFFILES, run-level link bands and man-page warnings (318c390)

package.sh may list CONFFILES. pkgmeta check refuses a CONFFILES path that is not an f or e line of
the prototype or is on two of its lines, one under PREFIX or outside /etc and /var or relative, an e object CONFFILES
does not list, one conffile listed by two packages, an object under /etc/rc.d, and a run-level link outside the boot
bands; pkginfo says CLASSES=none conffile for such a package and is unchanged otherwise. pkgmeta check warns about
commands and config files without a man page (5 current packages flagged). test-pkgmeta 93/93.

## 2026-10-30 — the s5 gate marks long-named packages UFS-only (a77c318); interim driver removed (ca7a835)

pkgroll.sh's s5 gate (GATE 3, amix_s5_mark) marks a package with an object basename over 14 bytes UFS-only:
APKG_FSTYPE=ufs goes into its pkginfo and the s5 rule is waived; a malformed APKG_FSTYPE, or one naming s5 when
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
