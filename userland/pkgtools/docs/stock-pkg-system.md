# The stock SVR4 `pkg` system on Amix — investigation findings

> *Reference map of the **stock** Amix packaging system (confidence-tagged). It describes the
> factory system as Commodore shipped it — not this repo's tooling, which is
> [design.md](design.md).*

**What:** end-to-end map of Amiga Unix's stock packaging (SVR4 `pkg*` tooling + `/var/sadm`).
**Where:** reproduced firsthand on a **clean Amix 2.1c** image (`Amix_UAE_clean.hdf`) under WinUAE,
`uname -a` = `UNIX_System_V localhost 4.0 2.1c 0800430 Amiga (Unlimited) m68k`, driven headless over
telnet/ftp. Raw command logs were kept outside this tree.

**Confidence:** ✅ reproduced firsthand on this image · 🟡 community-reported · 🔴 unverified.
Tags follow grimoire policy and are **never upgraded** downstream.

> **Licensing:** this describes *behaviour and on-disk data layout* observed at runtime. It contains
> **no** proprietary source, manuals, or media. The stock `pkg*` binaries and `/var/sadm` data remain
> proprietary — refer by name, never vendor them.

---

## 1. Tooling inventory ✅

Installed pkg binaries (all stamped `Nov 22 1992`; `pkgadd`/`pkgrm`/`installf` are `r-x------` root-only):

| Binary | Path | Binary | Path |
|--------|------|--------|------|
| `pkginfo` | `/usr/bin` | `pkgadd` | `/usr/sbin` |
| `pkgmk` | `/usr/bin` | `pkgrm` | `/usr/sbin` |
| `pkgproto` | `/usr/bin` | `pkgchk` | `/usr/sbin` |
| `pkgparam` | `/usr/bin` | `installf` | `/usr/sbin` |
| `pkgtrans` | `/usr/bin` | | |

**Absent from the installed system** ✅ (explicit `No such file or directory`): `pkgask`, `removef`,
and **`amixpkg`**. `amixpkg` is the Amix/OA&M install-media front-end — present on the boot/root
media, not on the installed system (see §8). `installf` exists without its partner `removef`.

No `pkg*` **man pages** are installed — the man tree is Amiga-reorganised (`man1A`, `man1X`, `man3A`,
`man5A`, `man6`…; no `man1m`/`man4`). So command semantics here are grounded in **reproduced
behaviour**, not on-box `man`.

---

## 2. `/var/sadm` — the installed-product database ✅

```
/var/sadm/
├── bkup -> /usr/adm/bkup                 symlink
├── install/
│   ├── admin/default                     admin(4) install policy (§5)
│   └── contents                          MASTER installed-object DB (§3) — 28,645 lines, ~2.3 MB
│                                          mode rw-rw-rw-  ⚠ world-writable
└── pkg/<PKG>/                            one dir per installed package (31 present)
    ├── pkginfo                           per-pkg metadata (rw-rw-rw-)
    ├── install/                          install-time scripts — EMPTY on every stock pkg (§7)
    └── save/                             files saved for removal/rollback
```

- **31 package dirs**; `pkginfo` (the command) lists **27** — `bnu`, `nsu`, `face`, `intf_install`
  are recorded but not surfaced by `pkginfo -x`. All carry `ARCH=Amiga`, `CATEGORY=system`, and
  **no `VERSION`** field. ✅
- Per-package `pkginfo` body (installed) e.g. `net`: `PKG`/`NAME`/`CATEGORY=system`/`ARCH=Amiga` plus
  pkgadd-added `PKGINST`, `PKGSAV`, `OAMBASE=/usr/sadm/sysadm`, `CLASSES= none`. ✅
- **There is no per-package `pkgmap`** in the installed DB. The master `contents` file *is* the DB;
  to learn which files a package owns you `grep` the package name in each line's trailing field. ✅

---

## 3. `contents(4)` record grammar ✅ (decoded from live data)

One line per installed pathname; whitespace-delimited; trailing field(s) = owning package(s). By ftype:

| ftype | shape | example |
|-------|-------|---------|
| `f` file | `path f class mode owner group size cksum modtime pkg` | `/usr/bin/ls f none 0555 bin bin 13824 51698 690829200 core` |
| `d` dir | `path d class mode owner group pkg` | `/dev d none 0755 bin bin core` |
| `s` symlink | `path=target s class pkg` | `/bin=/usr/bin s none core` |
| `c`/`b` dev | `path c/b class major minor mode owner group pkg` | `/dev/aen0 c none 18 0 0644 root root core` |

A leading/trailing bookkeeping comment records the last writer, e.g.
`# Last modified by amixpkg for X11r5src package` (see §8) → after a `pkgadd` it becomes
`# Last modified by pkgadd for <PKG> package` + a timestamp line. ✅

---

## 4. Package media format ✅ (built a throwaway `AMIXtst` with `pkgmk`/`pkgtrans`)

**Directory format** (what `pkgmk` emits; `pkgadd -d <dir>` reads it):
```
<PKG>/
├── pkgmap        manifest: ": <nparts> <nblocks>" then "<part> <ftype> <class> <path> <mode> <own> <grp> [size cksum mtime]"
├── pkginfo       the info file (pkgmk adds PSTAMP=<host><YYMMDDhhmmss>, CLASSES=none)
├── root/         payload for ABSOLUTE-path objects
└── reloc/        payload for RELOCATABLE objects
```

**Datastream format** (`pkgtrans` serialises the directory into one `.pkg` file; the form AmixBP /
amigaunix.com distribute 🟡): an ASCII header
```
# PaCkAgE DaTaStReAm
<PKG> <nparts> <nblocks>
# end of header
```
followed by **cpio archive(s) in SVR4 `070701` (portable ASCII / "newc")** carrying
`<PKG>/pkginfo`, `<PKG>/pkgmap`, then the file payload. ✅

---

## 5. Install / remove / query flow ✅

- **admin(4) policy** `/var/sadm/install/admin/default`: `mail=root`, `instance=unique`,
  `basedir=default`, and every check = `ask` (`partial`/`runlevel`/`idepend`/`rdepend`/`space`/
  `setuid`/`conflict`/`action`). A permissive admin (`*=nocheck`, `instance=overwrite`) + `pkgadd -n`
  runs non-interactive for packages with no install scripts and no file another package owns ✅.
- **The stock `pkgadd` asks the conflict and the script questions whatever the admin file says** ✅
  (emulated stock 2.1c, row E1, 2026-10-31, amxbase: files core owns, install scripts). Under `-n`,
  with `conflict=nocheck` and `action=nocheck`, it prints "The following files are already installed
  on the system and are being used by another package:" with an empty list, then "suspended
  (interaction required)", rc 5, nothing installed; the admin file named by full path (`-a
  /tmp/admin`) and by name under `/var/sadm/install/admin` fail alike. Without `-n` it asks "Do you
  want to install these conflicting files" and the super-user scripts question, and a `y` to each
  goes on. Whether it ignores the whole file or only those two keys is open 🟡. So such a package
  installs non-interactively only through APKGENG's pkgadd, or with the answers on stdin.
  `instance=quit` is not ignored: a second VERSION of an installed package under `-n` with it
  stops, rc 5, "Unable to determine whether to overwrite an existing package instance, or add a
  new instance", where the default admin's `instance=unique` would add an instance (run1) 🟡.
- **The stock `pkgrm` does not remove a package that has removal scripts without a person** ✅
  (emulated stock 2.1c, row E1, 2026-10-31, toy packages, evidence
  `tmp/2026-10-31-pkgtools-shared/run{3,4}/rig/E1`). A `postremove` or an `r.<class>` script is
  enough: under `-n` it asks the super-user scripts question and suspends, rc 5, with
  `action=nocheck` and with the default admin alike; with `y` answers on a pipe it asks both
  questions, then "Removal of <pkg> failed. No changes were made to the system.", rc 1, and no
  script ran (scripts mode 0644 or 0755). The same package without scripts removes. So a conffile
  package (its `r.conffile`) comes off a box without APKGENG only by hand at the console (not yet
  tried).
- **Stock 2.1c has no `removef`** ✅ (`/usr/sbin` holds `installf` only; `/usr/sadm/install/bin`
  holds `pkginstall` and `pkgremove`). The bench image's `removef` is APKGENG's,
  `/usr/apkg/bin/removef`.
- **The stock `installf -f` crashes after a re-type** ✅: `installf -c conffile <pkg> <path> e`
  (rc 0) then `installf -f <pkg>` dies, rc 139, and leaves the line as
  `… ? ? ? core:none +<pkg>\`. apkg's `--conf-new` runs the `installf` beside its pkgadd, APKGENG's
  by default.
- **An editable object is recorded as `f` with the package marked `<pkg>\`** ✅: the stock pkgadd
  writes an `e` object of the pkgmap as `/etc/x f conffile 0644 root sys <size> <sum> <mtime>
  amxbase\`, owned or shared (`core:none amxbase\`, the first owner's ftype kept). The `\` is the
  per-package edit flag (heirloom `srchcfile.c` reads `pkg\[:class]` the same way), and `pkgchk`
  skips the contents of a file so flagged.
- **A datastream with normalised headers installs** ✅: build/pkg's `amix_dsroll` stream (newc ino
  renumbered with a hard link kept, uid/gid/dev 0, every mtime and pkgmap's modtime the epoch) of a
  toy with a directory tree and a hard link installs with `/usr/sbin/pkgadd -n`, rc 0, `pkgchk`
  clean, the link intact (2026-10-31, `tmp/2026-10-31-pkgtools-shared/run3`).
- **A `BASEDIR` in pkginfo stops the stock `pkgadd`** ✅ (emulated stock 2.1c, row E1, 2026-10-31;
  toy packages varied one parameter at a time, evidence `tmp/2026-10-30-pkgtools-basedir/rig/E1`).
  `/usr/sbin/pkgadd -n -a <admin> -d <pkg>` of any package whose pkginfo carries `BASEDIR` (`/`,
  `/usr`) ends with "Installation of this package requires a base directory. … suspended
  (interaction required)", rc 5, nothing installed, even when every object path is absolute and
  whatever the admin file says (`basedir=default`, `basedir=/`, no `basedir=` line,
  `instance=unique` all fail the same). Without the line the same package installs. An `i
  copyright` file and a long `DESC` make no difference. The heirloom engine (APKGENG) installs both
  forms the same. So a package meant for a box without APKGENG carries no `BASEDIR`;
  `gen-catalog.py` warns about one.
- **`pkgadd` DB mutation** (captured by `diff`-ing `contents` before/after installing `AMIXtst`,
  which drops `/opt/amixtst` + `/opt/amixtst/hello`): pkgadd **inserts each object line in sorted
  pathname position** (not appended — the `/opt/...` lines landed mid-file), tags the trailing field
  with the package name, creates `/var/sadm/pkg/<PKG>/{pkginfo,install,save}`, installs the payload,
  and rewrites the "Last modified by" marker. ✅
- **`pkginfo` / `pkginfo -l`** project the `contents` DB (`-l net` → 192 pathnames, 35 dirs, 128
  execs, 9 setuid, 6034 blocks). ✅
- **`pkgrm`** parses the *entire* `contents` file up front, then removes payload + `save/` +
  per-pkg dir + the package's `contents` lines. Verified it **cleanly reverses** a `pkgadd` (§6). ✅

---

## 6. ⚠ Critical defect: a space-in-pathname entry corrupts the DB and breaks `pkgrm` ✅

On the stock image, **`pkgrm <anything>` and `pkginfo -l <anything>` abort** with:
```
ERROR: bad read of contents file
    pathname=/usr/x11r5/fonts/server/MacFS/TrueType
    problem=unknown ftype
```
**Root cause** — `contents` line 26966:
```
/usr/x11r5/fonts/server/MacFS/TrueType Fonts f none 0444 x sys 525157 64049 679609720 X11R5 X11R5
```
The X11R5 package shipped a file **named with a space** (`TrueType Fonts`). `contents(4)` is
whitespace-delimited with **no quoting/escaping**, so the parser ends the pathname at the space and
reads `Fonts` as the ftype → "unknown ftype" → every tool that fully parses `contents` aborts. (The
line even ends with a duplicated `X11R5 X11R5`.)

**Proven the entry is the *sole* blocker** ✅: deleting that one line made `pkgrm -n AMIXtst` succeed
(`Removal of <AMIXtst> was successful`) and reverse the install completely — payload, per-pkg dir, and
`contents` entries all gone; `pkginfo -l net` then also worked. This is almost certainly a large part
of why `amixpkg`/`pkgrm` are "widely reported broken" 🟡 on Amix: the factory `contents` DB is
corrupt out of the box, and removal/query are dead until it's repaired.

---

## 7. Dependencies & scripts ✅

- **No stock package ships any install script** — `/var/sadm/pkg/*/install/` is empty on all 31.
  No preinstall/postinstall/request/checkinstall/class-action scripts.
- **No formal dependencies** — no `depend` files; `CLASSES=none`; packages are pure file payloads.
- Only non-`pkginfo` files in the whole DB are saved **sysadm menu-interface `.mi` files** under
  `save/intf_install/` for a few system packages (`bnu`, `lp`, `nsu`, `face`, `sysadm`) — the one
  place a non-`none` class (`intf_install`, tied to `OAMBASE=/usr/sadm/sysadm`) appears.

**Consequence for any new manager / migration:** there is no dependency graph to import — stock
metadata encodes none. Dependencies would have to be authored fresh.

---

## 8. `amixpkg` (install-media front-end) — deferred, not vendored 🟡

`amixpkg` is **not** on the installed system; it lives on the boot/root install media (root.adf) and
is driven by the installer as `amixpkg -i -m -d -r /mnt -y standard` 🟡. That it populated this
system is visible in `contents` (`# Last modified by amixpkg for X11r5src package`). Inspecting its
internals needs the proprietary install media (licensing boundary — **not** extracted here). Its
observable role: an SVR4 installer wrapper that lays down packages and writes `/var/sadm` the same way
`pkgadd` does — and inherits the §6 corruption.

---

## 9. Implications for the direction decision

- **Migration read-surface (Goal #3)** is small and clean: `/var/sadm/pkg/*/pkginfo` (what's
  installed) + `/var/sadm/install/contents` (files→package, with mode/owner/cksum/mtime). A migration
  importer must (a) tolerate the §6 corruption (spaces in pathnames, duplicated pkg fields), and
  (b) expect **no versions and no dependencies** in stock metadata.
- **Improve-stock + remote repos (a)** looks *viable*: the core `pkgadd`/`pkgrm`/`pkginfo` machinery
  is fundamentally sound (proven §5–6); the blocker is a one-off DB corruption a repair/guard fixes.
  A network layer would sit on top of working `pkgadd` and the datastream `.pkg` format (§4), fed by
  the existing 🟡 AmixBP-style archives. Needs `zen0` TCP/IP.
- **Port opkg / pkgsrc-pkgin (b)** or **bespoke (c)** would not inherit a dependency graph anyway
  (§7), so their value is mostly in *adding* dependency resolution + remote repos, at higher toolchain
  cost — weighed against (a) in the direction write-up.

---

## Sources / evidence
- Firsthand, this session, on `Amix_UAE_clean.hdf` (Amix 2.1c) under WinUAE; command transcripts
  (phases A–E) kept outside this tree. ✅
- amigaunix.com `more_software` (pkg build/install flow, `.pkg`/cpio/`tar.zoo` formats) and AmixBP
  (`amixbp.sourceforge.net`, group_id 263433 — backports, stalled 2009). 🟡
- Consistent with grimoire `docs/drivers/toolchain.md` + `sources/research-brief.md` §7/§9 (which
  cover pkg *usage*; this adds the DB internals, format, mutation mechanics, and the §6 defect).
