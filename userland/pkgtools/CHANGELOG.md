## 2026-10-31 — the stock pkgadd and the admin file (d728052)

stock-pkg-system.md and apkg.1 record that the stock pkgadd asks the conflict and script questions under -n whatever
the admin file says (measured on rig E1; whether the whole admin file is ignored stays 🟡).

## 2026-10-31 — i.conffile and the stock mkdir -p (37a2ea7)

The class tests -d before mkdir -p, since the stock 2.1 mkdir -p fails on an existing directory and a second conffile
in one directory failed the install (found by base-e2's amxbase install on E1); stock-pkg-system.md narrows the
non-interactive admin claim to packages with no scripts or conflicting files. conffile 88/0, conffile-e2e 64/0.

## 2026-10-31 — scan060 honours AMIX_PKGTRANS (14464ca)

scan060.py unpacks a datastream with the pkgtrans named by AMIX_PKGTRANS when it is set (as build/pkg does), falling
back to heirloom/build-host/bin/pkgtrans; a set value that is not executable exits 1 naming it. Found by base-e2 while
rolling amix-base. Repo tools 470/0.

## 2026-10-31 — the stock pkgadd refuses BASEDIR; gen-catalog warns (494d477)

On the emulated stock 2.1c, /usr/sbin/pkgadd refuses any package whose pkginfo carries BASEDIR ("requires a base
directory", rc 5), whatever the admin file says; without the line the same package installs, and the heirloom engine
installs both alike (toy packages on row E1). gen-catalog now warns about such a package and says whether it needs
BASEDIR; apkg(1) and docs/stock-pkg-system.md record the fact. Repo tools 466/0.

## 2026-10-31 — the compat passwd fixture is ours (f0817bf)

heirloom/compat/tests/amix-passwd.txt was a box's /etc/passwd (the stock file with box-side edits). It is replaced
by a stock-format fixture of our own with the stock account names and ids and the quirks the parser test reads (user
x at uid 91, eight uid-0 entries, uucp and nuucp sharing uid 5) and no real account; the parser test gains two
checks (21/0). privacy-check --tree HEAD clean. History unchanged.

## 2026-10-31 — the compat group fixture is ours (a87d8cc)

heirloom/compat/tests/amix-group.txt was byte for byte the stock /etc/group, which system/MANIFEST.sha256 now lists,
so privacy-check --tree flagged it. It is replaced by a stock-format fixture of our own with the same group names,
gids and multi-member groups, plus a test group; the pw/gr parser test gains two checks (19/0). History unchanged.

## 2026-10-30 — heirloom: scriptvfy.c is never regenerated (754571c)

CI on 0c537a4 failed linking pkgchk: make's built-in %.c: %.l rule re-ran flex whenever a checkout left scriptvfy.l
a clock tick newer than the committed scanner, dropping its yywrap(). An empty scriptvfy.c rule stops the
regeneration (host and Amix builds) and scriptvfy.l carries yywrap() too. 10/10 builds clean in the CI base image
with the .l forced newer.

## 2026-10-30 — APKG and APKGENG are essential (cd8aa5e)

build-packages.sh marks both packages APKG_ESSENTIAL=yes, as dpkg marks itself: without them the box cannot manage
its packages. apkg refuses to remove or purge itself (exit 5) unless given --force-remove-essential; tested against
the real build-packages mint installed by the host engine (T31). An apkg older than 0.3.4 ignores the mark. Repo
tools 461/0. Not minted.

## 2026-10-30 — the essential-package mark, APKG_ESSENTIAL (75c33d4, 12832c6)

P-36 W2 follow-up. A package whose installed pkginfo says APKG_ESSENTIAL=yes (the base package: its r.conffile
would delete an unedited /etc/inittab) is refused by apkg remove, purge and remove --purge, exit 5, before the
journal or pkgrm; --force-remove-essential overrides, -f does not. list and info show the mark. gen-catalog skips a
package whose value is neither yes nor no. Stock pkgrm ignores the mark. Interface: docs/design.md §2c. apkg 521/0,
conffile e2e 64/0, repo tools 448/0. Not minted.

## 2026-10-30 — compver(5), copyright(5), space(5) (ed99eb4)

Written from the engine source (src/formats, MIT) and shipped by APKGENG 1.12.5 (not minted) beside the other
section-5 package formats.

## 2026-10-30 — apkg decides config files (P-36 W2); man pages (9da25f4, 85d4e09, 2a2a09f, 6dbbdcc)

apkg 0.3.4 (not minted): after each install or upgrade it lists the config files kept beside a new default and decides
them — at a terminal keep/new/diff/later; -y/--conf-keep keep; --conf-new installs the default, saves yours as .old and
records it with `installf -c conffile`; with no terminal and no flag they stay pending. New verbs `conffiles
[list|resolve]`, `purge` and `remove --purge`; removed packages with kept edits show as [config-files]. i.conffile keeps
an edited file silently when the package's default did not change. New pages contents-fsck(1M), amix-sadm-migrate(1M)
and contents(5); APKGENG 1.12.5 ships only its own commands' pages. Tests: conffile e2e 52/0, conffile 86/0, apkg 497/0.

## 2026-10-30 — conffiles (P-36 W1) (035ca80, 632f11b, 7490ff0, ba7ed9a)

src/conffile: i.conffile and r.conffile, the shared class `conffile`. An upgrade keeps an edited config file and
writes the new default to <file>.new, listed in /var/sadm/conffiles/PENDING; baselines are in
/var/sadm/conffiles/<pkginst>/; pkgrm removes unedited files and keeps edited ones. A removed file comes back (the
engine fails on an absent object). APKG 0.3.4 (not minted) puts /etc/apkg.conf and /var/apkg/admin on the class, so an
edited admin file survives `apkg upgrade apkg`, and ships apkg.conf(5), admin(5) and conffile(5). heirloom pkgrm treats
ENOTEMPTY as "not empty". `installf -c conffile` + `installf -f` re-registers a replaced file. Tests: conffile 82/0,
repo tools 445/0.

## 2026-10-30 — two conf layers; fifteen catalog groups (b684e45, c947aef)

gen-catalog.py, sets.py and s5-collision-scan.py read userland/packages/conf (generated by pkgmeta) beside tools/repo's
confs. Neither layer outranks the other: a package they give different names, categories, deps or descriptions stops
the catalog (rc 4, each named); the packages layer may add to `extra` but not to the installer chain. tools/repo drops
its copies of the recipe-built packages' lines. cats.conf declares the fifteen groups; stock emacs moves to editor and
olcore/oldev to x11, catalog field only. Repo tools 430/0.

## 2026-10-30 — APKGENG version 1.12.5 (d373696)

build-packages.sh sets VER_ENG to 1.12.5, for the engine that ships the fnmatch and snprintf notices; 1.12.4 stays
staged with its old payload and is never rebuilt. Not minted.

## 2026-10-30 — docroot, engine notices, shipped version (53911ae, 3f1d1b5, ba1fa53)

NOTES no longer names the package host's docroot path. APKGENG's prototype ships the fnmatch (BSD-3/ISC) and snprintf
notices as /usr/apkg/doc/FNMATCH.LIC and SNPRINTF.LIC (heirloom/LICENSE/); not minted, so the next engine mint (a new
version, not 1.12.4) carries them. README names APKG 0.2.3 as the shipped version. Suites 399/0, 497/0, 38/0, 19/0,
36/0, kbootset 12/0.

## 2026-10-30 — working in its amix home (673a881 … 3f2c2b6)

The sibling-path defaults fit userland/pkgtools: the cross builds source $GCA/env.sh (gcc-cross-amix at
toolchain/gcc-cross-amix.pin; AMIX_CROSS_ENV/CROSS_ENV still override); kbootset-consumer.sh defaults to this
checkout's kernel/dlm; apkg's 0.2.3 test archives cc02d52 from the git toplevel and skips cleanly without history;
build-packages.sh takes KERNTOOLS and CDFS_REPO; the repo tests take AMIX_PACKAGES. "amix-dlm" is cited as kernel/dlm;
the resolver tests use 192.0.2.1-9. README, CONTRIBUTING, LICENSE and NOTICE describe the directory; NOTICE names
fnmatch's holders. Suites 369/0, 497/0, 38/0, 19/0, 36/0, kbootset 12/0; the static set and apkg.amix are
byte-identical to a d7f4871 build.

## 2026-10-30 — moved in from amix-packagemanager

jusii/amix-packagemanager master d7f4871 (52 commits) moved into amix userland/pkgtools by subtree merge with its
hashes kept (no rewrite). privacy-check --all: 0 hits, with one scoped allowlist entry for apkg's made-up resolver-test
nameservers (59cf5af). The pre-publication history stays outside amix.

## 2026-10-30 — the UFS-only package mark, APKG_FSTYPE (f9b20e8, 544b830, eeb9f2f)

P-35 Option C, step 1. A package whose pkginfo says APKG_FSTYPE=ufs may carry file names over 14 bytes; apkg refuses it
on any other filesystem before the first pkgadd (exit 5, one line naming the package, directory and filesystem; a
malformed value exits 3); unmarked packages behave as before. gen-catalog validates the mark and lists marked packages
in a `#ext fstype 1` trailer that every catalog v1 reader skips (apkg 0.1, 0.2.3, 0.3.3 checked). s5-collision-scan
exempts marked packages. Interface: docs/design.md §2b. apkg 497/0, repo tools 409/0. Not minted, not published.

## 2026-10-30 — payload-licence gate: stock libm is recorded, a Kickstart ROM refuses (dccd3b1, e656915)

Per the owner's 2026-10-29 ruling (the permission covers all of Amix incl. its AT&T parts) and 2026-10-30 decision
("Yes, stock libm"), the gate no longer refuses a payload ELF that embeds SVR4 libm; it prints one `embeds` line per
binary so a publish still shows what is inside. A new content test refuses a Kickstart ROM image anywhere in a payload
($1111/$1114 + JMP header, byte-swapped, AMIROMTYPE1; split halves not seen). Repo tools 387/0, apkg 457/0.

## 2026-10-30 — archive category; diffutils, coreutils, bzip2 in the catalog conf (67f7cf6, f272fbe)

cats.conf declares archive (thirteen groups); gzip and tar move from utility to archive, catalog field only, no .pkg
byte moves. diffutils and coreutils file under utility, bzip2 under archive; all three join the extra set (9 → 12).
names.conf maps the PKG instances diffutil and coreutil to their catalog names. Repo tools 377/0. Live at the next publish.

## 2026-10-29 — Tests find the dlm kit in amix; repo-tools suite runs with bash (ada0a0b, 5831103)

kbootset-consumer.sh defaults to amix's kernel/dlm; a missing kit is a loud SKIP (exit 77), no longer a silent pass.
README and CONTRIBUTING run tools/repo/tests/run-tests.sh with bash (375/0).

## 2026-10-26 — APKG 0.3.3 and APKGENG 1.12.4 minted (e98077a, 499f86b) — not published

APKG 0.3.3 = abfaaac's apkg (block nodes in module packages): apkg.amix d45c24c0 (113350 B, reproducible, scan060 CLEAN);
APKG-0.3.3.pkg md5 2237f523 / 198144 B in build/repo-staging-apkg033; suites 457/38/12, repo tools 409/0; upgrade over 0.3.2
keeps the conf. APKGENG 1.12.4 = the removef stdin fix (75be235): installf/removef fdeee971; APKGENG-1.12.4.pkg md5 4433b3a1
/ 2364416 B in build/repo-staging-apkgeng1124; 11 binaries reproducible; pkgadd/pkgrm/pkginstall/pkgremove differ from 1.12.3
only in __assert line numbers (+3, the 2026 header). The static set (0.2.3-era apkg) was not rebuilt. Public catalog still 0.2.3 / 1.12.3.

## 2026-10-26 — kspace: module packages may ship block device nodes in /dev/dsk (C3-5 v8 §1.2) (abfaaac) — not minted

gen-catalog.py and apkg's ds_pure_files accept `b none /dev/dsk/<node> <maj> <min> <mode> <owner> <group>` for role=module,
same wording both sides; `c` unchanged (under /dev/); `b` outside /dev/dsk, kernel/loader device nodes and p/s/l still
refused. Unblocks ramdisk30/46 1.0.0-1. Tests: apkg 457/0 (+15), nohttp 38/0 (+18), tools/repo 409/0 (+9). apkg.amix
reproducible 226678a5 (113350 B), scan060 CLEAN, not deployed; the next APKG mint bumps APKG_VERSION (still 0.3.2).

## 2026-10-26 — heirloom: removef's stdin form strips the newline, removes again (75be235)

`removef PKG -` kept fgets' trailing newline on every line, so nothing matched the contents DB and nothing was removed
(rc 0, silent); each line is now cut to its first whitespace token as installf's stdin form does, blank lines skipped
(AMIX-PORT.md root cause 13). Host regression test heirloom/tests/removef-stdin as build-host.sh step 6; the fixed Amix
installf/removef built (157732 B, fdeee971), not minted — ships with the next APKGENG. Stock Amix ships no removef.
Found, not fixed: a latent upstream use-after-free in removef.c's error paths (a bad path after a good one frees a live
extlist entry) — a follow-up.

## 2026-10-26 — package m4: the stock /usr/ccs/bin/m4 alone, shared with Cdev (b70500c)

New package `m4` (pkginst m4, VERSION 2.1): the stock Amix 2.1 /usr/ccs/bin/m4 alone, from the Cdev tape member, so
syslogd can read /etc/syslog.conf without the 10 MB Cdev set (the 2.1c syslogd pipes its conf through m4 and files nothing
without it). `build-packages.sh --m4` via the new `repackage-stock.py --member`; the pkgmap row is identical to Cdev's field
for field, so the two packages share the file: an identical row is never a conflict (pkgdbmerg's shared/contchg/attrchg,
ckconflct), pkgrm of one owner leaves the file to the other — proven on the host engine in both orders, strict and APKG
admin, with mode/mtime controls. Staged build/repo-staging/stock/m4-2.1.pkg (md5 cf0784f9, 26112 B), not published.
deps.conf `m4: core`; test T27; repo tools 401/0. Open: m4 into sets.conf minimal (base-8 → base-9) is the owner's.

## 2026-10-26 — APKG 0.3.2 minted for the 1.1 media, staged in build/repo-staging-apkg032 (d6ff38f) — NOT published

APKG-0.3.2.pkg sha256 c971c992, md5 9d6de726, 198144 B; apkg.amix c18d6ee2 inside (0.3.2: module packages may carry /dev
device entries). Against 0.3.1 only apkg and apkg.1 changed; all publish-path gates pass; the overwrite install keeps an edited
apkg.conf. The public catalog stays at 0.2.3.

## 2026-10-26 — apkg 0.3.2, gen-catalog: module packages may carry device entries (abd6d3c) — NOT minted

A role=module package may ship `c none /dev/<node> <major> <minor> <mode> <owner> <group>` (C3-5 v4 §1.2; z3660eth's
/dev/zen0 c 51 0): gen-catalog writes its row instead of SKIPping, apkg installs it; kernel and loader packages still refuse
a `c` entry; b, p and every other type refused everywhere; the module record keeps `file` lines for plain files only (pkgadd
makes the node and records it in contents; pkgrm removes it). A latent off-by-one in the contents reader for c/b lines fixed.
apkg 442/0, repo tools 367/0; apkg.amix c18d6ee2 (113230 B).

## 2026-10-26 — APKG 0.3.1 minted for the 1.1 media, staged in build/repo-staging-apkg031 (9c55d35) — NOT published

APKG-0.3.1.pkg sha256 45b809cd, md5 2378f66d, 197120 B; the apkg.amix inside is 87b0c427 (112647 B). Against 0.3.0 only
apkg and apkg.1 changed. All publish-path gates pass; heirloom pkgadd -R overwrite install keeps an edited apkg.conf. The
public catalog stays at 0.2.3 until the owner's go.

## 2026-10-26 — apkg 0.3.1: one kernel package per line; gen-catalog module rows (06b77c4, 07ebd85) — NOT minted

apkg 0.3.1 keeps one kernel package per line (amix-dlm C2-2 v5 §2.1): an install bringing a kernel while another package's
kernel record of the same line exists replaces it in the same journaled transaction — the plan line `<new> replaces <old>
(<PKGINST>): one kernel package per line`, a pre-flight of every installed module record against the new kernel ("…: remove
the module packages first"), pkgrm + record removal of the old before pkgadd + record of the new, one kbootset trigger; two
kernel records of one line, or two kernels in one transaction, refuse with exit 5; `apkg recover` finishes a cut between
removal and pkgadd (journal format unchanged, apkg-txn 3). apkg.amix 87b0c427 (112647 B). gen-catalog writes role=module
rows from the object's .moddata (kabi=/cc=), no depend= — byte-identical to amix-packages' stage-3 catalog. Tests: run-tests
421/0, nohttp 20/0, kbootset-consumer 12/0, repo tools 360/0.

## 2026-10-26 — apkg upgrade with several names; APKG 0.3.0 staged for the 1.1 media (6215017, bb0072d) — NOT published

`apkg upgrade <name>...` takes several names as one transaction: one journal, one kbootset build + commit, so a kernel, the
loader and kbootset upgrade into one generation (stage-2 exit row S2-46); an unknown or not-installed name refuses the whole
call; up-to-date names are left out. APKG 0.3.0 minted by build-packages.sh --apkg for the 1.1 media
(build/repo-staging-apkg030/base/APKG-0.3.0.pkg, 192 000 B, sha256 e6e7b7d5…): STAGED, the public catalog and the publish
line of record still say 0.2.3 — publishing is the owner's decision. APKGENG stays 1.12.3. run-tests 376/0.

## 2026-10-25 (night, 2) — the install record is named by pkginst (C2-2 v4) (3ab2c3f)

/var/apkg/kpkg/<pkginst> (the entry's pkginst=, else its name): an s5 root keeps 14 characters of a file name, so a long
name and its .new could collide and the write-then-rename stopped being atomic; the full name stays in the record's name
line; install, list, info, remove, recover and the pre-flight read records by that file name, remove accepts either.
Journal format apkg-txn 3. run-tests 363/0, consumer 12/0 against kbootset 4caad11, repo tools 341/0.

## 2026-10-25 (night) — kernel-space keys per role (C2-2 v3, C2-3 v2) (88bd8e2, f00b22b)

Kernel and module entries need line=k30|k46, kabi= and pin=; a loader entry needs line=any and loader=<n> and may not
carry kabi=/pin=; the client refuses a missing required key or an excluded one. Records carry kabi/pin for kernel/module
and a `loader <n>` line for the loader. gen-catalog.py puts loader packages in the block from the package's own ldrinfo
(and checks ldrinfo's boot1/boot2 hashes against the packaged files); the kbootset package stays an ordinary entry; module
packages skipped until stage 3. Journal format apkg-txn 2. run-tests 349/0, repo tools 341/0, consumer 12/0.

## 2026-10-25 (late) — apkg 0.3 follow-up after the kbootset author's review (0e6090f..d7e91f0)

apkg cites contracts C2-2/C2-4 v2 (behaviour unchanged). A kernel-space datastream must be pure files (spec 40 §6): the
pkgmap may hold only f and d objects of class none and the i entries pkginfo, depend, copyright; anything else exits 3
before any pkgadd; install records list plain files only. gen-catalog.py writes the `#ext kpkg 1` block (S2-23): a kernel
package goes into it with line=, kabi=, pin= copied verbatim from its own sidecar; a catalog without kernel space is
byte-identical to before; loader and module packages are skipped for now (ldrinfo lacks line/kabi/pin — contract question).
The kbootset consumer test builds kbootset through amix-dlm's Makefile. run-tests 338/0, repo tools 333/0, consumer 12/0.

## 2026-10-25 — apkg 0.3 kernel space (4c30036, 36f5f7e, 46278a0) — built, not minted, not published

The client reads the catalog's `#ext kpkg 1` block (contract C2-2 v1; apkg 0.2.3 proven to skip it unharmed). Kernel-space
datastreams are checked by SHA-256 + size (amix-dlm's loader/common SHA-256, copied verbatim); after each install apkg writes
/var/apkg/kpkg/<name> with one `file <path> <size> <sha256>` line per installed file; a pre-flight checks kabi, compiler pin
and line. After a transaction that changed kernel space apkg calls `kbootset build` then `kbootset commit` (C2-4 v1); exits
6 = kbootset error (journal kept), 7 = kbootset refused (generation unchanged). New journal /var/apkg/txn and `apkg recover`;
config keys kbootset= and kbootset_journal=. Version 0.3.0 in source only (build-packages.sh still mints 0.2.3 — the mint is
the owner's call). Host tests 330/0; consumer test against the real kbootset 10/0; emulator smoke on rig row E1 PASS.

## 2026-10-14 — batch 0 published to pkg.amigaux.org (6724e96, 871d605)

Catalog db94282c5eaae7d8fb0b07230331eacd, 41 entries: the seven add-ons moved -1 → -2 (strict-060 re-mints) and the -1
files were removed from the server (D-2); APKGENG 1.12.0 → 1.12.3, APKG 0.2.2 → 0.2.3 (the 1.0 media versions). Older
APKG/APKGENG files stay served, decatalogued. Proven on a true LC060 cell first (7/7 and the upgrade path).

## 2026-10-13 — initial public release (github.com/jusii/amix-packagemanager)

Published from a fresh root: apkg, the Heirloom-based SVR4 package tools and the repository tooling as they
stood on 2026-10-13. CDDL §3.3 contributor notices in the 43 modified Heirloom files; the publish and test
scripts take their server and paths from the environment; NOTICE and README licensing wording. Hashes cited
in entries below refer to the private development history.

## 2026-10-11 — APKGENG 1.12.3 (89e24b7, f121753)

Record kept e/v files on disk; installf refuses spaces. APKGENG-1.12.3 minted (88a177e5); stock pkgchk/pkginstall
read notes.

## 2026-10-06 — APKG 0.2.3 minted, not published: /etc/apkg.conf kept on upgrade (0d6c1ee, b27fa58)

The pkgmap line becomes `e apkgconf` with a class action script i.apkgconf that installs the default only when the
file is absent; the default also ships as /usr/apkg/lib/apkg.conf (bytes as 0.2.2). APKG-0.2.3.pkg md5
db67f4bacb2a6b20c33a66d70490e154. After a keep, `pkgchk -n` is the clean check. Test T23.

## 2026-10-05 — APKGENG 1.12.2 minted through the refreshed toolchain, not published (119c2db)

The engine is rebuilt through the gcc-cross-amix wrapper (2ab2b22), which now does the 68060 64-bit-multiply
expansion and preserves X; heirloom/amix-cc's own copy of the rewrite is removed (one implementation), its
fail-closed check for leftover 64-bit mul/div stays. build-amix-static.sh gains STATIC_OUT=, so a pinned static
set is never overwritten. APKGENG-1.12.2.pkg md5 f585809421e8cbc2a02ccc7d9ea11ce7. 1.12.1 (19905d2a) is
superseded and was never published. APKG stays 0.2.2 (bytes unchanged).

## 2026-10-05 — installf killed on the 68060: APKGENG 1.12.1 minted, not published (e9c7f37, 32798b6)

On a 68060, `installf -f core` hit vector 61 in libpkg HASH(): the APKGENG-1.12.0 on pkg.amigaux.org is the
2026-07-05 engine (md5 fb2f08f4) with a 64-bit-dividend divs.l. The r3 re-mint (4ba15121) has no such divide but
113 sites of 64-bit-product muls.l/mulu.l, which gcc 2.7.2.3 emits for every divide or modulo by a constant.
heirloom/amix-cc now expands each 64-bit multiply into a 16x16 mulu.w sequence; tools/repo/scan060.py gates the
APKG/APKGENG mints and the static build. APKGENG-1.12.1.pkg md5 19905d2a7066e3e15ed838a9e899a168. Proven under
qemu m68060 and on an emulated LC060 install. Tests: repo tools 276/0, apkg 223/0, nohttp 20/0.

## 2026-10-02 — static apkg rebuilt with the pkg.amigaux.org default; amix-cc fcmp fix (fc39eda)

heirloom/build-amix-static/bin/apkg rebuilt (52632 B, sha256 673daf79): the July binary still carried the
retired LAN-mirror default; the source had been right since dcece20. amix-cc no longer swaps fcmp
operands when the gcc-cross-amix wrapper (8dbc8d7) already does -- the double swap broke the static build and
could have inverted register-to-register float compares. Tests 223/0 + 20/0.

## 2026-09-26 — PUBLISHED batch-2 (grep 2.5.1a-2, tar, make); catalog metadata for it (8577efa, ff341f6)

The amix-packages repo's prepared root was published (~12:20 EEST): served catalog
md5 20308547…, 41 entries (grep line 2.5.1a → 2.5.1a-2; + make 3.81; + tar 1.14, PKG gtar); the old
grep-2.5.1a.pkg stays served but decatalogued. names.conf gains gtar → tar, sets.conf's `extra` gains
tar + make, cats.conf the matching categories (tar utility, make development); the repo-tools suite
is 268/0. Lesson recorded: a curl-mirrored staging root carries fresh mtimes, so rsync would re-send
every unchanged package — align mtimes against the previous publish root before the dry run. Open
item: a bench disk's /var/sadm/install/contents came back garbled after apkg install/remove runs
(evidence kept in amix-packages/build/bench/).

## 2026-09-26 — PUBLISHED to pkg.amigaux.org: the category/description taxonomy, then APKG 0.2.2 (68cdb45)

Two prepared roots were published in order: step 1 cats.conf + descs.conf (served catalog
md5 a6d2d6bf…, 39 entries, no package bytes moved), a gate on the served md5, then step 2 APKG 0.2.2
(catalog md5 282cc289…; base/APKG-0.2.2.pkg 144896 B, md5 feb57752…). APKG-0.2 and 0.1 stay served
but decatalogued; a 0.2 box upgrades with `apkg update; apkg upgrade apkg`. The catalog-regenerate
trap (both older APKGs moved aside) held. NOTES.md carries the run record.

## 2026-09-26 — APKG 0.2.2 minted from master; 0.2.1 retired unpublished (ac24ae6, 2b17018)

Decision: the release is master's whole src/apkg — the canonical pkg.amigaux.org default
(dcece20), the blocked-SIGALRM fix (unblock_alarm) and the stub DNS resolver (eed3210) — as 0.2.2.
The SIGALRM-only 0.2.1 minted on the hotfix branch was never published and its number is retired
(docs/apkg-0.2.1-hotfix.md says so). Deterministic apkg.amix (md5 83fb1920…, 78045 B); suites
223/0, 20/0, 267/0; payload-licence and scan-private gates clean.

## 2026-09-26 — the hotfix line merged; cats.conf staged for the next publish (47a55dd, 4b94b86, 217361d)

apkg-0.2.1-hotfix (4c3bfc3 the blocked-SIGALRM hang fix, 708ae70 the 0.2.1 mint) merged into master;
build-packages.sh stages cats.conf so the taxonomy goes live at the next publish; NOTES records the
prepared cats + stock publish root and that master's "0.2.1" was not the minted one.

## 2026-09-18 — tests pin the compiled-in default repo, which nothing had read (960526f)

Three pins on `DEF_REPO` (`src/apkg/conf.c:92`, `http://pkg.amigaux.org`, canonical since dcece20 on
2026-09-14): a build with no apkg.conf resolves the canonical host, the minted apkg.conf template says the
same, and a wrong value fails both ways. Every functional test had been passing its own `repo=`, so the
default the installer ships was the one thing untested. The install-video medium's grep hit was a
pre-dcece20 gitignored build artifact, not the source. Tests apkg 220 → 223.

## 2026-09-16 — payload-licence-gate: no foreign object code leaves in our builds (3cc7094)

`tools/repo/payload-licence-gate.py` screens payload ELF symbol tables for SVR4 libm markers (matherr /
reduce or ≥ 3 libm names); REFUSE is fatal in `publish.sh` (exit 5, no `--force`). NEEDED is informational
(dynamic linkage redistributes nothing), `stock/` is skipped by provenance and said out loud, a scan that
read no files is an error, and stripped binaries report UNKNOWN = untested (7 of 13). T19 pins the withdrawn
amix-benchmark 1.2 signature without keeping vendor libm as a fixture.

## 2026-09-16 — publish log: APKG 0.2 live; amix-benchmark 1.2 withdrawn, 1.3 published, catalog 38 → 39 (51ed7c2, 031dfd7, 843b664, 0ce7d3e, f638115, e14c709)

APKG 0.2 re-mint published (md5 8289178c…, 133632 B), catalog 395b4fbc → 7b16464b; APKG-0.1.pkg stays on
disk decatalogued and must stay in staging (`--delete-excluded` would remove it). amix-benchmark 1.2 was
staged, gated green and WITHDRAWN unpublished: its `whet` statically embedded the stock `/usr/ccs/lib/libm.a`,
a class `--scan-private` cannot see. 1.3 = 1.2 minus whet (md5 8f055b9d…, 132608 B), published by
hand as a separate step (staging is automated, the publish is not), catalog 7b16464b → f0ed2ca1 (39 entries);
amix-benchmark joins the `extra` set. On-box E2E on the real 68LC060 A4000D: `apkg update` sees 39,
`install amix-benchmark` → pkginst amixbench, 69,953 dhry/s, `remove` clean — the first name/pkginst split
proven client-side. Trap recorded in NOTES: never re-run gen-catalog on a live-pulled staging root
(APKG 0.1 + 0.2 collide on "apkg" and the sort drops the live one).

## 2026-09-15/16 — staging overrides: descs.conf and names.conf, both staged by build-packages.sh (dd42d65, 7a76e67, 85bda14)

`descs.conf` overrides the catalog description column from the staging root, so an operator note no
longer needs a re-mint (refuses `|` and empty; Gate 8 fatal on an entry line > 2046 B, the client's fgets
limit). `names.conf` maps pkginst → catalog name, forced by the 9-character SVR4 PKG ceiling (amixbench →
amix-benchmark; stock pkgadd silently drops longer instances). `build-packages.sh` stages both and T20 pins
the mapping at exactly one entry. Repo tools 226 → 256. The authored apkg-0.1 upgrade warning in descs.conf
is staged, not yet published.

## 2026-09-15 — apkg gets a stub DNS resolver, and a blocked-SIGALRM hang falls out of building it (eed3210)

`src/apkg/dns.c` resolves IPv4 literal → `/etc/inet/hosts` → configured `nameserver=` (empty by default, so
no behaviour change unless configured; hosts first, so a hand-written line is never shadowed); one UDP A
query per attempt, hard reply validation, CNAME by owner name; new apkg.conf keys `nameserver=` (max 8,
`:port`), `dns_timeout=5`, `dns_retries=2`; `-v` prints a `dns:` line. Building it uncovered that
`alarm()`+`longjmp` in http.c left SIGALRM BLOCKED after the first timeout, so with the shipped `retries=2` a
SECOND stalled fetch hung forever — fixed with `unblock_alarm()` (Amix libc has no siglongjmp). The
published APKG 0.2 carries the defect; the fix ships with the next mint. Tests apkg 169 → 220, nohttp
17 → 20.

## 2026-09-16 — the upgrade verb bricked apkg on metal; four defects fixed and APKG 0.2 re-minted (7434a97, 3ec2c80, d73ecbc)

A metal test put APKG 0.2 on the real A4000D and three of the four self-upgrade paths were defective,
one destructively. `apkg upgrade apkg` ran pkgrm then pkgadd; the pkgrm succeeded and the pkgadd died with
"unable to open admin file </var/apkg/admin>", leaving the box with no apkg. The real cause: /var/apkg/admin
is shipped by the APKG package as an `e` entry, so the pkgrm two seconds earlier had DELETED it. Two fixes,
either sufficient alone: `conf_adminfile()` materialises the admin file before every engine call, and
`upgrade` no longer runs pkgrm at all — one pkgadd over the installed instance with a derived
`<admin>.overwrite` (instance=overwrite), so nothing is removed before its replacement exists. `-f` applies
to the packages NAMED, not the closure; an installed package whose catalog version is newer refuses and
points at `apkg upgrade`. The malformed `/usr/bin/apkg -> /../apkg/bin/apkg` was the STOCK 1991 pkgadd
prefixing the basedir onto a relative link; the entry is absolute now and `pkgmap-symlink-gate.py` enforces
it on every mint. APKG 0.2 re-minted in place (never published, version unchanged): md5
8289178ca832f0ea67ecd7445f512978, 133632 B, shipped `/etc/apkg.conf` carries rcvbuf=0. Metal re-run 4/4
(stock pkgadd, symlink, upgrade verb, dead-repo untouched, admin re-created). A box still on 0.1 must migrate
with a download + stock pkgadd — its own `upgrade` bricks it. NOT published. Tests 169 / 17 / 19, 0 failed.

## 2026-09-16 — `rcvbuf` becomes an off-by-default operator knob on the TCP receive window (7bb3084, 7f29e60)

Two metal captures inverted the design. Capture 1: apkg asked for SO_RCVBUF 64 K before connect() and the
box advertised win 4096 in its SYN and in all 2999 steady-state ACKs — the socket option never reaches the
Amix tcp module (sockmod). Capture 2: raising the window with STREAMS INITQPARMS DOES work (16384 on the
wire, on streams opened after the call — it rewrites the tcp module's template, box-wide until reboot) and
makes this driver SLOWER: 4096 ≈ 54 KB/s, 8192 ≈ 32, 16384 ≈ 36–40, retransmits 1.0 % → 3.6 %; the cause
is an RX-path loss cliff at ~8 segments in flight (the Z3660 firmware's one-deep GEM RX descriptor ring).
So `rcvbuf` defaults to 0 — leave the stack alone; `rcvbuf > 0` drives INITQPARMS (root) with SO_RCVBUF as
the non-root fallback, warns at warning level naming the box-wide scope and the way back, and does not
auto-restore (the prior value is unknowable). Review fixes: the two RAM-ceiling mechanisms split in
the maintainer notes, the package-size claim scoped to the add-on set, BATCH-1 entries realigned.

## 2026-09-16 — apkg fetch path: inactivity timeout, and every knob in apkg.conf; APKG 0.2 minted (ebab35d, edf1aff, f16823d, 54a87e9)

The 60 s HTTP timeout was a whole-transfer cap, and it killed a healthy 8.2 MB `apkg install Xcore`
on the real A4000D while smaller packages fetched fine — that path runs ~37 KB/s, so the package is
~220 s of continuously flowing transfer. `alarm()` is now re-armed before every blocking call, so the
timer measures network SILENCE, not duration: a slow but flowing transfer never trips it at any size,
and a silent connection still dies reporting the window and the bytes it received. A regression test
(`src/apkg/tests/slow-server.py`) trickles a package slower than the configured timeout and asserts
the elapsed time really exceeded it; a `/stall/` mode proves a silent peer still dies with no `.part`.

Every remaining constant on the fetch path became an `/etc/apkg.conf` key in the same `key=value`
format: `timeout` (300), `connect_timeout` (30), `retries` (2), `retry_delay` (5, doubling),
`progress` (262144 bytes, 0 silences, -v quarters), `bufsize` (8192), `redirects` (1), `rcvbuf`
(16384), `sndbuf` (0). A non-200 status is never retried; numbers are parsed strictly so a typo
cannot silently mean 0 for the keys where 0 is legal; progress is no longer verbose-only. A drift
guard extracts the `apkg.conf` template out of `build-packages.sh` and asserts its values are the
binary's defaults (the template heredoc is unquoted — no backticks or `$` may appear in it).

`rcvbuf` requests SO_RCVBUF before connect(), but its effect on the stock Amix stack is UNVERIFIED
and documented as such — the STREAMS tcp hiwat is 4096 and sockmod may not propagate the request, so
the getsockopt readback is not proof. Its default is 16384, not the 65535 protocol ceiling: MSS to a
non-local host is pinned at 536 and the Z3660 firmware RX ring has 32 slots, so a window past ~17 KB
overruns a ring that discards its whole backlog rather than back-pressuring. Raise it only once a
wire capture says larger is safe.

APKG minted at 0.2 (`base/APKG-0.2.pkg`, 124416 B, md5 2b6c53c7c29df1d4b79815d56b3a3c70; mints are
not byte-reproducible, the preserved file in `build/repo-staging-apkg02/` is the one to publish).
The catalog cannot hold two versions of one name, so 0.1 leaves the catalog but its file must stay in
staging (publish.sh rsyncs with delete). NOT yet published: the local LAN mirror is stale at 32 entries, so
any publish must stage from the live host. Tests 87 → 142 (`src/apkg`), 197 (`tools/repo`), 36
(`tools/migrate`), 17 (nohttp variant), all 0 failed. Host-side: `Xcore-2.1.pkg` fetched from
pkg.amigaux.org at 11.6 MB/s, md5 matching the catalog — the A4000D failure was purely the client.

## 2026-09-15 — the 16 MB RAM ceiling retracted; the extra set holds BATCH-1 (6fd6461, af89730)

The "16 MB hard Fast-RAM ceiling" rule had no first-party measurement anywhere in the project and is
replaced by what is proven: 16–64 MB on the stock 030 bench line (64 MB the standing daily value),
128 MB on the 040/060 line, measured on real silicon (Total Unix memory 134213632 on the A4000D). The
2026-07-22 investigation stays as a dated historical note — a real measured floor for the apkg
cache-path double-materialization, never a kernel ceiling. The derived "keep packages small" courtesy
becomes a low-RAM (≤16 MB) courtesy, not a rule tooling enforces. `sets.conf`'s `extra` set now names
BATCH-1 (acompat, grep, gzip, less, patch, zlib) and `cats.conf` files their categories, closing the
T15 drift guard; the run-tests.sh pins that held `extra` empty follow the measured membership
(197/197). Metadata only — no published catalog byte moved.

## 2026-08-28 — the taxonomy answer for the third-party userland (amix-packages X3) (fdf299e, 006415c)

Two new category groups, twelve in all: **`utility`** (general-purpose command-line tools — the
category the stock taxonomy never needed, because Commodore bundled the whole general userland
into `core`/`bsd`) and **`editor`** (interactive editors). The line against `text` is subject
matter, not file type: stock `text` is the Documenter's Workbench, so `grep`/`diff`/`less` are
`utility` and `elvis`/`joe` are `editor`; `emacs` stays its own footprint group. `shell`,
`archive` and a `perl` group are deferred with their triggers recorded — adding a group later
costs one line and no re-mint, so the bias is to under-split.

Provenance is a **set**, not a category: the new `extra` set in `sets.conf` is the handle for
the amix-packages add-on userland — declared empty until that repo publishes, off the
minimal ⊂ standard ⊂ full chain, and disjoint from the five locked memberships (`full` stays
the Amix 2.1 distribution plus our three, digest-attested, never widened).

`cats.conf` gained a `@group <token>: <gloss>` declaration statement and `gen-catalog.py` a
`read_cats_conf()`, so the vocabulary is a checkable contract rather than a comment that can rot:
declaring any group closes the set — an override naming an undeclared group is refused
per-package, a pkginfo `CATEGORY` outside the vocabulary warns. Backwards compatible (a staging
`cats.conf` with no `@group` line behaves as before). `tools/repo/tests/run-tests.sh` 177 → 196,
0 failed; `src/apkg` 87/0 unchanged. Host-side only — no package re-minted, no published byte
moved.

## 2026-09-15 — the repository moved to pkg.amigaux.org, and BATCH-1 is published (dcece20, bbcd7a5, 99c07ac)

The package repository moved off a LAN-only mirror to the canonical public host
`http://pkg.amigaux.org/` (a static docroot, rsync as the publishing user, no root). `publish.sh`'s `PUBLISH_DEST`/`PUBLISH_URL` defaults, `src/apkg/conf.c`'s `DEF_REPO`, the
`apkg.conf` template minted by `build-packages.sh`, and every doc that states where the repository lives now
name the new host; two client-contract rules are written down where an implementer meets them — plain HTTP
on port 80 forever (the 1992 client has no TLS), and hostname-only, because the vhost is name-based and a
bare-IP `Host:` is answered 404 (DNS-free path: `52.59.174.203 pkg.amigaux.org` in `/etc/inet/hosts`,
measured 404 vs 200). `apkg.amix` is deliberately **not** rebuilt and APKG **not** re-versioned until after
2026-09-19, so the Saku demo medium's APKG bytes stay valid. Then BATCH-1 from `amix-packages` was published
under `pkgs/extra/` — zlib 1.2.13, gzip 1.3.12, grep 2.5.1a, less 704, patch 2.5.9, acompat 0.1 — taking the
catalog 32 → 38 (md5 `edeba578…` → `395b4fbc…`) with the 32 existing lines byte-identical; host-side
verification complete (private-content scan, publish md5 gate, all six re-fetched over HTTP/1.0 with an
explicit `Host:` header). The on-box `apkg` E2E for the six runs on the real A4000D.


## 2026-09-01 — hygiene, licensing and docs currency before publication (7e77410..3c7fbda)

- Untracked three committed build artifacts (`contents-fsck.amix`, `tests/kat-branch.amix`, …) and
  ignored `kat-branch.amix`; kept the bench credential and lab addresses out of the tree.
- `contents-fsck` docs describe the pathname sort key 7fc7ba5 shipped; the apkg README covers the
  catalog taxonomy, the prompt fast-fail and the 87 tests; tool inventories match `tools/repo` (14
  files); the July investigation-era documents are labelled for an outside reader.
- A root README and LICENSE (the repo had neither); SPDX headers on the files that carried no notice.
- History condensed for the public release on 2026-10-13.


## 2026-08-16 — the P5.4 r4 KERN mint (a46b24f)

- Both private kernel packages re-minted onto the full P5.4 regeneration batch:
  **KERNBENCH 49667-2026.08.16** (sum -r 49667, 1 586 312 B, payload md5 8072e610…;
  bench-smoke 8/8 — a4091 family) and **KERNZ3660 60364-2026.08.16** (60364,
  1 587 524 B, payload md5 23b4b898…; **metal-proven 2026-08-15**: byte-clean
  updbootpart reframe, two cold power-to-network boots, both direct-map flags = 1
  live via adb). 60364 is now the last metal-validated kernel identity.
- r4 is additive, not a retraction: r3 (64049/45833) stays valid-in-place.
- ★ `support-stock` retired from KERNBENCH's KMIX (the r4 bench kernel links the
  probed support.c); an absent group-4 tag asserts nothing — see kerntools §2.
- ★ gate_kernel was fail-closed but not fail-clean — arms copied the source over
  the staged payload BEFORE gating; now: gate the source, copy, re-gate.
- Falsified, not just exercised: wrong-kernel and one-byte-flipped inputs refused;
  publish/catalog gates refuse both r4 packages (rc 3/4, zero files) while the same
  staging without them publishes rc 0. Suites 178/178, 87/87, 19/19.

## 2026-08-14 — the s5-14char arc (brief, cppath fix, scanner)

- docs/s5-14char-collisions.md (d677e85): 5 groups/10 objects (corrects W6's 3); all ten are 1992
  build droppings; pkgadd mkstemp root cause; Option A recommended — then SUPERSEDED by the UFS
  default (full installs whole on ufs; Option A retired, not landed).
- cppath fix (76b7145): pkgadd can now overwrite ≥14-char basenames on s5 (14-byte-capped template,
  same-dir atomic; red/green LD_PRELOAD s5 simulator, 24 checks). Deployment debt: rides the next
  APKGENG mint. License-file rename deliberately deferred (digest blast radius).
- tools/repo/s5-collision-scan.py (a149c2e): the W6 scan mechanized, 7 pinned constants, T17,
  suite 178/178. ab82525 records the arc.
# Changelog

## 2026-09-26 — docs currency: apkg 0.2.2, gates, counts (506b13c)

Maintainer notes/README/design.md/src/apkg/README: apkg 0.2.2 named; the DNS stub resolver and
payload-licence gate appear where a reader looks for how a publish is gated (pointing at NOTES.md);
repo-tools file count 18; test counts 223 / 20 / 268; example uses APKG-0.2.2.pkg.

## 2026-08-11 — W3 package metadata — installed sizes, cats.conf taxonomy, install sets (dd62c40, 0e974a9, daae217)

Host-side only; no package re-minted, every .pkg md5 untouched, and a plain
regeneration of the live repo still reproduces the published catalog
byte-for-byte (md5 edeba578b73fc892f3c8c5ede603aca7).

- **Installed size** — `gen-catalog.py --isize` appends `#ext isize 1` +
  `#isize <name> <bytes>` after the entry lines, summing every sized pkgmap(4)
  object (f/v/e/i). A *comment* block rather than a 10th field: catalog.c takes
  9 fields (or 10 with the RAW offset) and rejects anything else, so a new
  column would brick every deployed apkg; a `#` line has been skipped since
  4992a67, needs no format bump and rides the RAW region and the CD tree for
  free. Opt-in, so nothing downstream moves until a consumer asks. Cross-checked
  against the tape index: byte sums are 0.9224 of the tape's 512-byte-block
  figures; a 1 KB-block + indirect + directory s5 model reproduces the List to
  ~1%. Free-space gates should budget ~1.10×. A package whose pkgmap cannot be
  summed gets NO line — absence means unknown, never zero.
- **cats.conf** — catalog-level taxonomy override (staging-root file, deps.conf
  key rule), ten groups over 30 packages, re-categorising without a re-mint.
- **sets.conf + sets.py** — the five locked install sets (minimal 8 / standard 17
  / full 30 / developer 19 / x11 18), composed as minimal ⊂ standard ⊂ {full,
  developer, x11}; `conf` excluded from developer; no set names a KERN* package.
  A pre-POSIX sh filter loop runs inside the suite as a second implementation
  and matches sets.py on all five sets.
- **docs/design.md §2** now specs the catalog v1 extension-block grammar
  (daae217): the `#`-comment rule, the `#ext <name> <version>` trailer grammar,
  the opt-in `--isize` block, absence-means-unknown-never-zero, the
  payload-sum-vs-s5-footprint ~1.10× budgeting rule, and the one known
  non-conforming consumer (amix-installng isocheck.parse_catalog — must learn
  to skip `#` before the ISO path may pass `--isize`).
- Tests: tools/repo 94 → 161, src/apkg 81 → 87, both 0 failed.

## 2026-08-07 — P5.4 r3: KERN packages re-minted on the stack-sdcom-fixed cdfs; r2 superseded; attribution corrected (2a08cfa, 7960a87, b72bc02)

- **Root-cause correction for the whole P5.4 mint lineage**: the M-RUN4 panics were amix-cdfs's
  stack-allocated sdcom (u-area-window lifetime bug, fixed `9360542`) — present in BOTH cdfs
  lines then; NOT the upstream-sync line (exonerated) and NOT the cross toolchain. §7 and the
  r1 quarantine README carry the corrected story (`b72bc02`).
- **r2 interlude** (`2a08cfa`): 53963/14821 minted from the pinned proven-line cdfs (which
  still carried the latent defect) and the r1 pair quarantined at
  `build/kernel-private/POISONED/*.pkg.POISONED`; r2 subsequently superseded-in-place.
- **r3, the metal-green mint** (`7960a87`): KERNBENCH → `64049-2026.08.07` (sum -r 64049,
  1 585 656 B, bench-smoke 8/8 behind it) and KERNZ3660 → `45833-2026.08.07` (sum -r 45833,
  1 586 680 B; **metal-validated 2026-08-07** — 15/15 cycles + 25/25 rapids, the 00961
  successor, now the golden's running kernel). Publish gate REFUSES both (quoted, rc 3);
  pkgtrans round-trips md5-identical; suite 94/94. July predecessors intact.

## 2026-08-06 — P5.4: re-mint the PRIVATE kernel packages as the Wave-1 successors (6500d7f)

- The P5.4 Wave-1 kernel rebuilds (z3660eth major 48→51 renumber + the aen security patch in
  the link) supersede the W6-P kernel-package identities. KERNBENCH → `45343-2026.08.06`
  (sum -r 45343, 1 585 284 B, md5 e739b9cb…; KMIX GAINS z3660eth:
  a4091,z3660eth,cdfs,a3091-fixed,a2091-fixed,scsi-gsio,support-stock); KERNZ3660 →
  `05929-2026.08.06` (sum -r 05929, 1 586 308 B, md5 e4420789…; KMIX unchanged
  z3660scsi,z3660eth,cdfs). Sources = amix-kerntools work/kernel-packages/p54-bench-cdfs/unix
  and p54-combined/unix (provenance siblings); rootdev/CONFIG/payload shape/private-flag
  mechanics unchanged.
- The W6-P slice-vs-relocunix representation split is DISSOLVED: the P5.4 bench build proved
  /stand/unix == the gated relocunix BYTE-EXACT (sum -r 45343 both, pulled length-gated), so
  both packages now ship the gated ET_REL relocunix bytes verbatim and REV/KSUM_R = the
  relocunix sum -r. docs/kernel-packages.md §7 records the re-mint; §5's KERNBENCH bullet is
  now historical.
- Predecessors superseded, not destroyed: KERNBENCH-45473-2026.07.23.pkg and
  KERNZ3660-00961-2026.07.23.pkg stay in build/kernel-private/kernel/; 00961 remains the last
  METAL-validated kernel until M-RUN4. Neither successor is yet cold-boot- or metal-validated
  (bench-smoke / M-RUN4 follow the wave).
- Proofs: gate_kernel passed both; pkgtrans round-trip md5-identical payloads; boot2 sha256
  f287ff3a… re-verified; pkgmap modes == stock core, class none only; publish gate REFUSES
  both successors (scan-private rc 3, markers BOOT2_SHA/KSUM_R; catalog build rc 3, no
  catalog written). Suite: repo tools 94/94 (T13 included).

## 2026-07-24 — METAL-FIX.3: apkg install fails fast on a hung/prompting pkgadd (79f56f3)

- M-RUN1 froze: a pkgadd error left the console wedged at "No changes were made to the system."
  60s+ and `apkg install`'s rc never propagated, so the driver's `|| die` never fired. Root
  cause (`src/apkg/install.c` run_cmd): pkgadd was forked with apkg's stdin INHERITED; the stock
  1991 pkgadd prompts (conflict/continue) even under -n on error paths, and with a never-fed
  stdin the child blocked forever → waitpid() never returned. The rc decode was already correct
  (WEXITSTATUS + loop-break on nonzero) — the gap was the HANG, not mis-propagation.
- Fix: redirect the child's stdin to /dev/null so any prompt reads EOF and pkgadd ABORTS nonzero
  → reported EX_PKGCMD. stdout/stderr stay attached. Covers the shared install loop
  (HTTP/FILE/RAW) + upgrade + remove. Deliberately the clean stdin-EOF signal, not a watchdog
  timeout (covers pkgadd errors + interactive-prompt hangs; a pkgadd stuck on something OTHER
  than stdin is a different unobserved class). Proven a real guard: the identical FIFO+prompt
  scenario times out rc 124 on a no-fix build, fast-fails rc 4 on the fix.
- Tests 77→81 (prompt-no-hang, names-package, FILE-arm fail, RAW-arm fail; suite runs 0.66s =
  no hang); nohttp 17, contents-fsck 19, mntinfo 5 green. Static apkg rebuilt: 46880 B, sum -r
  37448 (was 46464/40275); other engine binaries byte-size unchanged. installng re-master pulls
  apkg by name (no pinned sum) → picks it up automatically. install.sh's "stops on first
  failure" comment is now TRUE for prompting/hanging pkgadd, not just clean-nonzero.

## 2026-07-23 — METAL-FIX.2b: re-key the W6-P licensing gate to kernel-package markers (4de56d0)

- The W6-P gate (577c65a) keyed on pkgmap PATHNAMES (`/stand/unix`, `/stand/boot2.boot`) —
  but stock `core` ships those members as ORIGINAL Amix content, so the gate condemned every
  regen of the real 32-row catalog, the base-8 `gen-catalog --raw`, and the explicitly-private
  raw-source build (froze the metal retry). Re-keyed the refusal to the robust markers W6-P
  itself mints — pkginfo `KSUM_R`/`BOOT2_SHA`, carried ONLY by KERNBENCH/KERNZ3660 — so kernel
  packages remain fully refused (catalog rc 3, publish rc 4, still no `--force`) while stock
  `/stand` content passes as it always had. No CLI/exit-code changes; only the trigger moved.
- Proofs: real staging regen rc 0, catalog BYTE-IDENTICAL to pre-gate (md5 edeba578…);
  `--raw` incl. core → rc 0 with raw.img; both real kernel packages still refused with the
  marker named; T13 reworked with both directions regression-locked. Suites: repo 94/94,
  apkg 77/77, nohttp 17/17, contents-fsck 19/19, mntinfo 5/5.
- Hygiene rider (landed with this entry): untracked the stale committed
  `tools/repo/__pycache__/gen-catalog.cpython-314.pyc` (gitignore already covers it) — it
  churned as "benign noise" on every tools run.

## 2026-07-23 — Installer-NG METAL-FIX.1: get_mntinfo() survives a MISSING /etc/mnttab (3b9b7a1)

- **Extends the W5.5a sparse-mnttab fix to an ABSENT mount table.** The first metal RAW install
  (A4000+Z3660, 2026-07-23) ran green through seed + `apkg update` + all 8 SRC_RAW package reads,
  then died: `pkgadd: ERROR: unable to open mount table (/etc/mnttab): No such file or directory`
  — the miniroot ships no mnttab, the RAW path's `/etc/mount` writes none, and W5.5a's synthesize
  only ran after a SUCCESSFUL open. (Bench RAW passed only by state contamination: its reused
  root floppy carried an mnttab left by cdfs-helper mounts in earlier CD-arm waves.)
- Fix (`libinst/mntinfo.c`): ENOENT on the mount-table open ⇒ treat as empty ⇒ synthesize the
  `/dev/root / s5 rw 0` root via a shared `synthesize_root()` helper (the two paths cannot
  drift). Every OTHER open error stays FAIL-CLOSED (EACCES fixture proves it). Robustness suite
  5/5 with a load-bearing revert-proof. Suites: repo 87/87, apkg 77/77, nohttp 17/17,
  contents-fsck 19/19.
- Static set: only **pkgchk** (52096, 264524 B) and **pkginstall** (46006, 399900 B) change —
  pkgadd is byte-identical (get_mntinfo lives in the pkginstall CHILD it execs, which is also
  why the field error carries the "pkgadd:" prefix). Re-master consumers pick up exactly those
  two. Outstanding: on-metal re-verification against genuinely fresh media (installng wave);
  the apkg fail-fast hang seen at the metal freeze is a separate open item (METAL-FIX.3).

## 2026-07-23 — Installer-NG W6-P: PRIVATE kernel packages minted + publish licensing gate (577c65a)

- Minted **KERNBENCH** (`/stand/unix` = the W6-U slice-proven bench kernel, sum -r 45473,
  1,252,347 B; a4091+cdfs+a3091-fixed) and **KERNZ3660** (`/stand/unix` = the metal-validated
  00961, 1,585,400 B; z3660scsi+z3660eth+cdfs), both rootdev 0x00480016/c6s1unix, both shipping
  the flags-based `/stand/boot2.boot` (sha256 f287ff3a…, acquired via kerntools boot2-sha-gate;
  the tape's own boot2 is the refused name-based 5ab360b1… and was NOT used). Payload = three
  files class `none` (modes per stock core); NO scripts, NO raw-device writes — rotation and
  the raw UNI\0 reframe belong to installng's updbootpart. pkginfo carries
  ROOTDEV/CONFIG/KSUM_R/BOOT2_SHA/KMIX (pkgparam-readable gates for updbootpart).
- **Kernel packages are PRIVATE-only, mechanically**: they mint into `build/kernel-private/`
  (never the redistributable staging); `gen-catalog.py` REFUSES them from any catalog (rc 3,
  no catalog written) and gains `--scan-private`; `publish.sh` scans and refuses before rsync
  (rc 4, destination untouched; NO --force). Consumption is local `pkgadd -d <file>` only —
  no catalog row, no apkg path, cannot leak off-LAN. Regression-locked as run-tests T13
  (repo suite 73→87).
- Corrections vs the W6-K contract draft (kerntools doc amendment owed): KERNBENCH ships the
  proven-booting slice bytes (45473 — not the 42265 relocunix representation of the same
  kernel), and the mint uses ARCH=Amiga. Suites green: repo 87/87, apkg 77/77, nohttp 17/17,
  contents-fsck 19/19, mntinfo all-pass.

## 2026-07-23 — Installer-NG W6.4a + W6.4c-a: static contents-fsck; apkg on PATH; hygiene (69e0003, b862c75, 1d6bfb8, d5ab424)

- **Static contents-fsck joins the CD engine set** (`69e0003`): build-amix-static.sh emits
  src/contents-fsck as fully static m68k SVR4 (29468 B, sum -r 23366) — ET_EXEC, zero
  PT_INTERP/DT_NEEDED, nm -u empty, no division at all. Purely additive (engine set + apkg
  byte-identical). Installer contract: CHECK-ONLY `contents-fsck <root>/var/sadm/install/contents`;
  exit 0=clean / 1=findings / 2=error — the driver fails closed on any non-zero; `-r` repair
  stays a post-migration tool, never an install step.
- **APKG package puts apkg on the default PATH** (`b862c75`): new pkgmap `s` entry
  `/usr/bin/apkg=../apkg/bin/apkg` (core's own symlink convention; relative target survives
  `pkgadd -R`). Binary byte-unchanged; only the package md5/size move (110080→115200 B); catalog
  regen changes exactly the APKG row. NOTE: the APKG .pkg md5 is MINT-VOLATILE (pkgmk embeds
  editable-member mtimes) — consumers pin filename+size+same-mint catalog, never the pkg md5.
- **Hygiene**: `src/contents-fsck/tests/out/` untracked + gitignored — 61 disposable suite
  outputs no longer churn git status (`1d6bfb8`); build-packages.sh resolves the staging dir to
  an absolute path early — pkgtrans chdir's internally and a relative arg failed with a bare
  errno=2 (`d5ab424`).
- Suites green throughout: apkg 77/77, nohttp 17/17, repo 73/73, contents-fsck 19/19,
  mntinfo 4/4. Live-repo note: the published catalog still lacks the cdfs row and now trails the
  symlink-carrying APKG — the held publish must ship the freshly-regenerated catalog
  (32 rows, same-mint).

## 2026-07-23 — Installer-NG W6.1: mint the cdfs base package (CD-mount userland) (6200312)

- Wave-5 found a fresh base-five install ships NO cdfs userland (`/usr/lib/fs/cdfs` absent), so
  an installed box cannot `mount -F cdfs` a CD even though the cdfs KERNEL side is already in
  the target kernel. Minted the missing userland as OUR package `cdfs` (base/, alongside
  APKG/APKGENG) via a new `build-packages.sh --cdfs` arm (also in `--all`).
- Contents minimal and exact: `/usr/lib/fs/cdfs` (d 0755 bin bin), `/usr/lib/fs/cdfs/mount`
  (f 0755 bin bin) and `/cdrom` (d 0755 bin bin) — modes/owners copied from stock core's
  pkgmap convention, not guessed. Shipped binary = amix-cdfs 8de83cf build/amix/mount: 5026 B,
  sum -r 33315, md5 d20169094f9953a051484781c4e176bd. Gate 1 (single-entry cdfs dir) enforced;
  Gate 3 (lineage ≥ 31e8c3b, the page-crossing-DMA fix) asserted fail-closed at mint time.
- deps.conf: `cdfs → core` (deliberate exception to "core is never a dep" — makes core-first
  explicit for alt-root installs; a no-op on a booted box).
- Host proof: pkgtrans round-trip byte-identical; pkgname gate green (32 pkgs); catalog +
  catalog.md5 regenerated & consistent. Side-catch: the staging catalog had gone STALE vs four
  stock packages rebuilt during W5.x (core/games/lp/text, md5-only deltas) — the regen corrects
  it; any future publish must ship this fresh catalog. apkg 77/77, repo 73/73.

## 2026-07-23 — Installer-NG W5.5a: get_mntinfo() tolerates a sparse mnttab (0d3a21c)

- Root-caused the miniroot base-OS install failure (`pkgadd -R /mnt` "identified `</cdrom>` as
  root file system instead of `</>`", installed nothing) to the miniroot's incomplete
  `/etc/mnttab`: its `/etc/mount` is a bare mount(2) that writes no entry and boot never
  registers `/`, so mnttab held only the cdfs `/cdrom` line and SVR4 `get_mntinfo()` mis-picked
  `/cdrom` as root. Bench-confirmed (A3000+A4091 miniroot, w54c ISO): mnttab before/after the
  target mount held only `/cdrom`; adding a `/` line made the same `pkgadd -R` install core rc=0.
- `heirloom/libinst/mntinfo.c` `get_mntinfo()` now synthesizes the always-mounted `/` root entry
  when the mount table lacks one, instead of aborting with ERR_MNT_NOROOT. Normal SVR4 systems
  always list `/`, so the branch is never entered there — zero behaviour change on real
  hardware. Adds a `$PKG_MNTTAB` test/diagnostic override (unset on the box).
- New `heirloom/tests/mntinfo-robustness/` (4/4): sparse→synthesized, normal→unchanged,
  unreadable→fail-closed, pkgadd-on-missing-datastream→non-zero; validated load-bearing against
  a synthesize-removed rebuild. Static CD engine rebuilt (pkginstall 399676, pkgchk 264308),
  divsll-only clean, host suites green (apkg 77/77, repo 73/73, nohttp 17/17, pw/gr 16/16).
- Exit-status finding: the engine already fails CLOSED (pkginstall/pkgremove quit(99), installf
  exit(1), pkgadd via ckreturn→failflag→exit non-zero; on-box missing-datastream = 99). The one
  fail-open, pkgchk's intentional get_mntinfo swallow, is mooted by this fix.
- Bench-proven downstream (installng W5.4d/e/f): with this engine, all 5 base packages install
  rc=0 from the miniroot and the full zero-touch install reproduces the canonical digest
  `86e1ceb144f1328bf441c5df38fc2798` on a twice-cold-booted target.

## 2026-07-22 — Installer-NG W5.0b follow-up: static apkg (FILE+RAW-only) joins the CD engine set (6553368)

- `heirloom/build-amix-static.sh` now also emits `build-amix-static/bin/apkg` as a fully static
  m68k SVR4 ELF — ET_EXEC, zero PT_INTERP, zero DT_NEEDED, **46464 B**. Resolves the deferred
  AMIX-PORT.md decision to **option 1**: the static apkg drops the HTTP backend (compiled
  `-DAPKG_NO_HTTP`, `http.c` excluded from the link), so the `socket()` → libnsl netconfig(3N)
  dependency is gone and it links fully static against `libc.a` alone — `nm` shows zero
  undefined symbols and no `setnetconfig`/`getnetconfig`/`endnetconfig`/`gethostbyname`/
  `socket`/`http_get` anywhere. Rationale: no static `libnsl.a` exists on Amix 2.1 and the
  install miniroot has no network stack; the **dynamic** apkg keeps full HTTP. (The HTTP
  installer is a declared LATER effort; its path is the netconfig(3N) compat reader —
  "option 2" — recorded in AMIX-PORT.md.)
- Source seam is minimal (`src/apkg/source.c` only): one `#ifdef APKG_NO_HTTP` around the
  `http://` registration — an `http://` repo **fails closed** with a clear message, never
  misclassified — plus guards on the two `SRC_HTTP` switch arms. FILE/RAW behaviour is
  byte-for-byte the shared build's (proven by `cmp` on pkgadd argv and raw-staged bytes).
- New standalone test `src/apkg/tests/nohttp-variant.sh` (17/17): http refusal on every verb +
  FILE/RAW parity vs the shared build. Shared `apkg`/`apkg.amix` md5-identical pre/post.
  Suites: apkg 77/77, repo 73/73; divsll-only clean.
- W5.3's ISO re-master pulls `build-amix-static/bin/{apkg,pkgadd,pkgtrans,pkginfo,pkgchk}` +
  `sadm-helpers/pkginstall`. On-box smoke of the static set owed to W5.4.

## 2026-07-22 — Installer-NG W5.0b: static-link variant for the CD engine set (8be79a0)

- `heirloom/build-amix-static.sh` emits the CD-resident installer subset (pkgadd, pkgtrans,
  pkginfo, pkgchk + the pkginstall sadm helper) as fully static m68k SVR4 ELF — ET_EXEC, zero
  PT_INTERP, zero DT_NEEDED — so it runs on the stock install miniroot, which ships NO
  `libnsl.so` and a divergent `libc.so.1` that, being Amix's embedded-rtld PT_INTERP,
  `LD_LIBRARY_PATH` cannot redirect (E4 probe; proven with a garbage-libc negative control).
  Additive: `build-amix.sh` and its outputs stay byte-identical. Links the shared build's
  objects against the cross sysroot's static `libc.a` + `values-Xt.o`; ZERO C changes. Sizes:
  pkgadd 266024, pkgtrans 171604, pkginfo 209316, pkgchk 264116, pkginstall 399492 B.
- `apkg` deliberately excluded from the static set for now: its SVR4 `socket()` path needs
  libnsl's netconfig(3N) trio and **no static `libnsl.a` exists anywhere in the Amix 2.1
  distribution** (tape, sysroot, golden images — shared-only). Options recorded in
  `heirloom/AMIX-PORT.md`; resolution: the static apkg ships FILE+RAW-only (HTTP stays in the
  dynamic apkg installed systems use — the miniroot has no network stack, so a static HTTP
  path would be dead weight there anyway).
- Suites green: apkg 77/77, repo 73/73; cross-build objdump divsll-only.

## 2026-07-22 — Bench-RAM investigation: the installer fits the 16 MB ceiling (3efa704, docs-only)

- Phase A on the fixed kernel (42265): the **cdfs arm** (verify-in-place, no cache) installs the
  base set at **8 MB**; the **RAW cache arm livelocks an 8 MB box in ~3 min** (network + console
  dead, no panic — swap/anon exhaustion; the double-materialize working set is ~35 MB of
  disk-backed cache plus pkgadd's own TMPDIR spool). At **16 MB** (`a3000mem_size=16`,
  `mbresmem_size=0` — exactly at Amix's hard Fast-RAM kernel ceiling) RAW (~3 min) and HTTP
  (~3.7 min) both pass — peak swap use ~2.7 MB, no leak — all three sources reproducing
  **`86e1ceb144f1328bf441c5df38fc2798`** (4793 objects). SCSI proven clean at exactly 16 MB
  (write+readback and double-read consistency). Bench configs standardized on 16 MB family-wide;
  apkg single-materialize streaming remains optional polish, not required.
- The bench guidance in the maintainer notes corrected accordingly (`3efa704`): the 64 MB (`mbresmem_size=64`)
  recipe is **retired** — 16 MB at the ceiling is the config; >16 MB mis-maps the SCSI disk.

## 2026-07-21 — Installer-NG Wave 3: package SOURCE abstraction, proven 3 sources → 1 digest (c61bdb7, 5fc80e4)

- apkg gains an explicit SOURCE layer (`src/apkg/source.{c,h}`): `repo=` is classified with NO
  heuristics — `http://` → HTTP, `file://` or a bare `/path` (e.g. `/cdrom`) → FILE,
  `raw:<dev>` → RAW, anything else a hard error. `http.c` stays HTTP-only (its `http://`-only
  rejection is now correct). `src_fetch` pulls the catalog; `src_stage` makes one datastream
  pkgadd-ready, md5-verified, driven by read cost — a mounted plain `.pkg` is verified IN PLACE
  and handed to pkgadd directly (no cache copy), a downloaded/dd'd/`.Z` stream is cached. The
  "verify all before mutating anything" pre-pass is unchanged.
- `APKG_ROOT` (client root; compiled-in defaults only) split from a new `-R` target root
  (prefixes `/var/sadm/pkg` only, passes through to `pkgadd -R`); engine argv byte-identical
  when `-R` unset. `catalog.c` gains an optional 10th `offset` field (9-field catalogs
  unchanged; RAW fails closed on an offset-less entry) plus explicit `..`/leading-`/` rejection.
  Removed the stale apkg lock-clear workaround (engine `unlockinst` is fixed).
- `tools/repo`: `gen-catalog.py --raw` (512-aligned offsets + a self-describing `raw.img`);
  `source-acceptance.sh` drives the base-set install through each source into a fresh seeded
  `-R` root + the Wave-2 gate battery.
- **ACCEPTANCE — three sources, one digest.** On the bench (kernel 42265, **64 MB**), the base
  set (core/bsd/net/text/sysadm) installs through the source layer from a mounted **cdfs**, a
  **raw slice** (`raw:/dev/rdsk/c5d0s1`), and **`http://`**, each reproducing the canonical tree
  digest **`86e1ceb144f1328bf441c5df38fc2798`** (4793 objects; gates 13/12/11 + contents-fsck 0
  findings + `pkginfo -R` all five, per source). The 23 MB HTTP download ran with 90/90 host
  pings, 0 % loss.
- **Operational finding — corrected 2026-07-22: it was 8 MB memory pressure; the durable fix is
  16 MB (at the ceiling), not 64.** The RAW "staging read broken (varying md5)" and HTTP "aen0
  drops mid-transfer" seen at 8 MB were memory-exhaustion symptoms of the source layer's
  double-materialize (fetch→cache file plus pkgadd's own TMPDIR spool — a ~35 MB disk-backed
  working set an 8 MB box cannot page; the RAW arm kernel-livelocks an 8 MB box in ~3 min). No
  apkg code change was ever needed. This entry's acceptance ran at 64 MB
  (`a3000mem=16`+`mbresmem=64`) before that was understood; the 2026-07-22 investigation
  re-proved all three arms at **16 MB Fast RAM alone** (`a3000mem_size=16`, `mbresmem_size=0`),
  same digest, SCSI verified clean at exactly 16. The 64 MB/mbresmem recipe is retired. The
  multi-chunk `raw_extract` regression test added then stays (apkg suite 74→**77**; repo 73/73).
  Host cross-build unchanged from c61bdb7 (objdump: `divsll`-only). (`5fc80e4`)

## 2026-07-21 — Installer-NG Wave 2: -R ownership correctness, proven on the box (7331368, cef7fff, 7fc7ba5)

- Base set (core, bsd, net, text, sysadm) installed via `pkgadd -R` into a fresh seeded root
  on the bench box — all five rc=0 (~3.5 min), ownership attested GREEN at euid 0,
  contents-fsck clean (0 findings / 4793 records), `pkginfo -R` lists all five.
  **Canonical tree digest (the Waves 3/5 reference): `86e1ceb144f1328bf441c5df38fc2798`
  (4793 objects, owner/group resolved through the target root's passwd/group).**
- Engine (heirloom):
  - `averify()` under -R now ABORTS the package when an owner/group NAME is unresolvable in
    the target root's name service (was silent reperr+VE_ATTR+continue that `pkgadd -n`
    installs over). Registered fatal hook (`set_ownerfail_hook`); pkginstall wires it to
    `quit(1)`; non-R and other tools unchanged. `guard-fires.sh` proves fatal-on-unresolvable.
  - **CHOWN WAS NEVER APPLIED on Amix** (surfaced by the new euid-0 attest gate):
    `averify()`'s `chown()` sat inside `#ifdef __sun` (bundled with the Solaris pcfs guard),
    so every install left objects owned by the installing uid. Added a non-Solaris chown
    branch + defensive uid/gid default — fixes ownership for -R AND real-system installs.
  - Latent fixes on the same path: `ncgrpw.c` cl* readers copy the fgetgr/fgetpw static into
    caller-owned storage before `fclose` (ASan-clean); `gpkgmap.c getvalmode()` 45-byte stack
    overflow; bounded ownership writers (`libpkg/ainfo.c`) replacing unbounded
    `strcpy`/non-terminating `strncpy`.
  - contents-fsck's sort-order check now keys on the pathname (strips `=linktarget` for s/l),
    killing 10 spurious findings on the base-set DB while still catching real disorder.
- Gates (tools/repo, all fail-closed with demonstrated negative cases): pkgname>9
  hard-refuse in `gen-catalog.py` (7); `altroot_attest.py` canonical digest + euid-gated
  ownership verify, `install_test` INCONCLUSIVE when euid!=0 (11); `content-gate.sh`
  `pkgchk -R -c` per-file cksum (12); `core-first-gate.sh` (13); `altroot-acceptance.sh`
  box battery. m68k engine + contents-fsck rebuilt (objdump: only divsll/divull) and
  deployed to `/usr/apkg` (byte-identical sums verified).
- Operational notes: the box ftpd tail-drops large GETs (~2–3 KB) — pad-and-verify is the
  reliable pull pattern; the one mid-install guest panic-reboot was NOT reproducible.

## 2026-07-21 — MERGPATH_OPT -O0 forcing unwound; engine rebuilt at -O, re-verified on box

- The eight files force-built at -O0 (pkgdbmerg/eptstat/listmgr/putcfile/verify/ncgrpw/nhash/
  compat/snprintf) return to -O: `mk.config.amix` now sets `MERGPATH_OPT=$(CFLAGS)` (mirroring
  mk.config.host:58), and build-amix.sh regenerates the per-directory Makefiles at -O. The -O0
  forcing was a mis-diagnosis — the `pkgadd -R` crash was the toolchain tdivs/tdivu remainder-
  divide defect (nhash.c HASH), opt-level-independent, fixed in gcc-cross-amix 984192a. objdump:
  nhash HASH() emits `divsll %d2,%d0,%d1` (ext word 1800, SIZE=0, remainder in the %d0 return
  reg); whole-engine scan shows zero mis-assembled 64-bit `divsl`/`divul`; snprintf convert()'s
  64-bit `value % base` is a `__umoddi3` libcall (not const-propagation as first hypothesized —
  the mk.config comment records the measured reality). Rebuilt engine deployed to /usr/apkg on
  the bench box (pre-unwind engine backed up to /tmp/apkg-bak-preunwind): plain empty-root
  `pkgadd -R` 4/4 rc=0 zero-core, task0a battery 5/5 rc=0, genuine alt-root install (13 APKG
  contents records, apkg 59202 B). Reconciled the stale docs (AMIX-PORT.md open follow-up #1,
  the eight AMIX PORT build-rule comments in libinst/libpkg/libadm Makefile.mk, the maintainer
  notes' hard-constraint #3) to the resolved tdivs state. (`d9fa7f8`)

## 2026-07-20 — pkgadd -R blocker CLOSED (toolchain modulo fix verified on box)

- The `pkgadd -R <altroot>` SIGSEGV is resolved. The `tdivs/tdivu` remainder-divide fixup
  shipped in the `m68k-cbm-sysv4-gcc` wrapper (gcc-cross-amix `984192a`); the heirloom
  engine was rebuilt with the fixed toolchain and re-deployed to `/usr/apkg` on the bench
  box. objdump: rebuilt `HASH` emits `divsll %fp@(16),%d2,%d1` (ext word `1802`, SIZE=0,
  remainder %d2 preserved); the whole rebuilt engine shows only `divsll`/`divull`, zero
  mis-assembled 64-bit forms. On-box: plain empty-root `pkgadd -R` 4/4 rc=0 zero-core
  (was rc=1 + 1 MB core each run); full task0a battery 5/5 rc=0; DS_DEBUG and seeded-root
  arms rc=0; the alt-root install is genuine (APKG files + 13 contents records under the
  root). The fixed engine is left installed on the box. `AMIX-PORT.md` item 0 → RESOLVED;
  `NOTES.md` Session 6 added. Still owed elsewhere: driver/kernel rebuilds with the fixed
  toolchain, `MERGPATH_OPT` -O0 unwind, and this repo's stale "-R is untrustworthy" lines
  in the maintainer notes / docs/requirements.md / docs/design.md. (`f6ba252`)

## 2026-07-20 — pkgadd -R crash ROOT-CAUSED (toolchain modulo miscompile)

- On-box core dump (adb on unstripped pkginstall) located the alt-root SIGSEGV in
  `libpkg/nhash.c add_cache`: `HASH()`'s `hv % hsz` emits the correct SGS
  `tdivs.l ea,%d2:%d1` (remainder in d2) but GNU as 2.8.1 drops the remainder register,
  assembling `divs.l ea,%d1` (quotient only), so HASH returns garbage → negative bucket
  index → wild store → crash. Third gcc-2.7.2.3/binutils anomaly after `.swbeg` and `fcmp`;
  present at -O0 AND -O, so the `MERGPATH_OPT` -O0 forcing of nhash/ncgrpw/verify never
  could fix it. NOT a pkgtools/clgrnam bug — reproduces on an empty alt-root
  (clgrnam/dup_gr_ent never entered), so the v15–v17 instrumentation chased the wrong
  function; the "silent, no core" lore was wrong too (the 1 MB core lands inside the -R
  root at `<root>/var/sadm/install/core`). Per-region DS_DEBUG bisection independently
  names CGR (cgrnam) as the sole suppressor — bisect and core dump converge. Added
  `heirloom/tests/altroot-repro/` (harnesses + proof + per-region patch). Fix belongs in
  the gcc-cross-amix wrapper (next wave). (`c05cba0`)

## 2026-07-20 (-R averify SIGSEGV: host reproduction ruled out, m68k padding inference retracted)

- **Host-repro harness for the `pkgadd -R` averify SIGSEGV** (`b0bdd4f`):
  `heirloom/tests/host-altroot/` builds an LD_PRELOAD shim of the box's compat passwd/group
  parsers (sliced at build time from the live `compat/amixcompat.c`, so it can never test stale
  code), a throwaway probe package owned only by multi-member groups, and runs `pkgadd -R`
  against both an empty and a seeded fakeroot — self-checking via DS_DEBUG counts that the
  suspect `clgrnam → dup_gr_ent` path actually executed, so "no crash" is non-vacuous. Verdict:
  **not reproducible on host**, ASan/UBSan clean, with the path proven executed — suspicion
  moves to the box (per-region DS_DEBUG bisect queued). Riding along: `SANITIZE=1` host builds
  (`build-host.sh`/`mk.config.host`), a `verify.c` guard refactor enabling the diagnosis-only
  `-DAMIX_NO_ATTR_GUARD` build (default behavior unchanged; NOGUARD never ships), and
  `repackage-stock.py install_test()` now seeds every fakeroot with box `etc/passwd`+`etc/group`
  before `pkgadd -R` — an unseeded root provably skips the suspect path entirely.
- **m68k padding inference measured and retracted** (`8224ab1`): new
  `heirloom/tests/host-altroot/ainfo-layout.sh` compiles a `struct ainfo` probe with the real
  `m68k-cbm-sysv4-gcc` cross compiler and reads `offsetof` values back out of the emitted `.s`
  — MEASURED PAD=2 on both host and target, refuting the previous commit's PAD=0 inference
  ("the host can never reproduce this by construction"); `AMIX-PORT.md` and the harness README
  rewritten to the measured truth. Five latent unbounded-writer defects catalogued while
  tracing (notably `mappath.c:206 mapvar()` — unbounded getenv expansion into `char[65]`,
  unreachable today: 0 of 28,919 stock pkgmap entries are parametric). Box asks reordered:
  "what did the failing `-R` target actually contain" is now top priority — the v15–v17 box
  instrumentation may have targeted a function the box never entered.
