# Package-manager direction evaluation (Goal #2)

> *Historical — records how the 2026-07-04 direction was chosen. Useful for "why not X?";
> for current state see [../NOTES.md](../NOTES.md).*

**What:** evaluation of every realistic package-management option for Amix — fix/extend the stock
SVR4 `pkg` system vs. adopt an existing open-source manager vs. bespoke — with pros/cons and a
recommendation.
**How:** desk research, 2026-07-04. Seven candidate families, each investigated by downloading and
inspecting actual source (C dialect, dependency lists, LOC), each independently re-verified, plus a
completeness pass. The raw structured digest was kept outside this tree. Builds on the bench findings in
[stock-pkg-system.md](stock-pkg-system.md).
**Confidence:** claims below were source-verified (repos cloned/fetched and grepped) unless marked 🟡.

## Constraints applied

Hard gates (cannot be bought back):

- **Compiler wall:** GCC 2.7.2.3, C89/gnu89 only. **No C++ compiler exists for Amix at all** (cross
  g++ unfinished). This kills C++ code regardless of willingness to port libraries.
- **C99 wall:** porting a big C99 codebase (libarchive ~136k LOC, modern SQLite ~250k LOC) to gnu89
  is a rewrite-scale project, not "adding a lib."
- 68030-class CPU, 16–128 MB RAM; binary footprint and CPU cost matter.
- Bootstrap: the manager must be installable on a virgin Amix box — ideally as one self-contained
  SVR4 datastream `.pkg` via stock `pkgadd`.

Relaxed (per Jussi, 2026-07-04): **required tools/libs may be ported** if they themselves clear the
compiler wall (zlib is C89 — fine; Berkeley DB 1.85 — fine; gzip/tar — fine). **Remote repos must
work over plain HTTP** (no TLS); Amix's native ftp is a bonus transport.

Ground truth from the bench (Session 1): the stock tools are fundamentally sound — the "broken"
reputation traces to a single corrupt factory `contents` record (space in a pathname). Stock
metadata has **no versions and no dependencies**; any dependency graph is authored fresh under
*every* direction. `pkgask`/`removef` are missing from the installed system.

---

## Headline answers

### 1. "Is there fixed source for the System V pkg manager available?" — **YES**

Sun open-sourced the genuine AT&T/Sun SVR4 `pkg` implementation (CDDL) in OpenSolaris. It survives
in two forms:

- **illumos-gate `usr/src/cmd/svr4pkg`** — still present and passively maintained (commits through
  Mar 2024; Peter Tribble is the de-facto maintainer). But the modern lineage routes all
  `contents`-file access through the **`pkgserv` door daemon** (Solaris doors don't exist on Amix),
  plus zones entanglement (libinstzones, 17 files) and the illumos build system. A port means
  un-doing ~17 years of Solaris drift. ~91k LOC. *Verdict: possible; months. Best used as the
  authoritative reference for exact semantics.*
- **Heirloom Packaging Tools** (Gunnar Ritter, 2007 — `heirloom.sourceforge.net`, mirror
  `github.com/aflat/heirloom-pkgtools`) — **the same Sun code, snapshotted before `pkgserv`
  existed** (plain file I/O + lockfile on `/var/sadm/install/contents` — exactly Amix's semantics)
  and **already ported off Solaris** (Linux/HP-UX targets). Includes **`pkgask`** (argv[0] dispatch
  in pkgadd) and **`removef`** (inside installf) — the exact tools Amix is missing. Strict C89 (zero
  `//` comments, zero stdint.h across the tree). SQLite/zones/signing/web already disabled by
  upstream; OpenSSL only needed by the disabled parts (delete them). Needs snprintf-family shims
  (~70 files) + small LFS64/realpath shims. ~158k LOC total, ~100k after trimming; est. 1.5–3 MB of
  m68k binaries. `pkgtrans` shells out to `cpio -oc` — which on Amix **is** the native newc format
  the stock `.pkg` datastreams use. CDDL. Dead upstream (single release 070227).
  *Verdict: **strong candidate**; weeks. It operates on the existing `/var/sadm` in place — zero
  migration.*

Two footnotes: schilytools contains **no** SVR4 pkg implementation (verified — only packaging
metadata for shipping schilytools); and there's a 2,443-line Perl clean-room
`pkgadd/pkgrm/pkginfo` (yannrouillard/svr4pkg, GPL, dead 2013, needs Perl ≥5.10) — useful as a
compact spec reference only.

Caveat that applies to *all* SVR4-lineage code: the whitespace-delimited `contents` parser chokes on
the factory "TrueType Fonts" record exactly like the stock binaries — **the data repair is needed
regardless of tool lineage**.

### 2. apt? — **No, structurally.** apt has been C++ from its first release (apt 0.3.19, year 2000:
48,697 LOC of `.cc`, exactly 0 LOC of `.c`; modern apt is C++23). There is no C-era apt to
excavate, and no C++ compiler for Amix. dpkg 1.4.x (1998) *is* small portable C89 (13k LOC core,
internal tar extractor) — but dpkg has **zero network capability** (that was always apt's job), so
you'd port dpkg and still have to write the entire remote manager. Weak.

### 3. Homebrew? — **No.** Requires Ruby 4.0 (unbuildable here), git, and an HTTPS/TLS-only network
model (GitHub API + ghcr.io). On unsupported platforms it falls back to compiling everything from
source — the worst possible model for a 68030. Non-starter. (Nix/Guix: C++23/Guile 3 + TLS + store
model — non-starters on every axis simultaneously.)

### 4. ipkg/opkg? — **Split verdict.**

- **ipkg 0.99.163** (last C version, 2006, survives on archive.org — verified byte-identical
  download): the sleeper. 18k LOC, effectively C89 (one declaration-after-statement to fix; VLAs are
  a documented gcc 2.7.2 GNU extension), **links against libc only** — bundles its own gunzip,
  tar and ar readers (verified by building it: `ldd` shows libc alone). 144 KB stripped binary,
  designed for 16–32 MB iPAQs. Full remote feeds + **versioned Depends/Conflicts/Provides
  resolution** + upgrade + md5. Needs ~8–10 SVR4 libc shims and an external fetcher. GPL-2, dead
  upstream. *Strong candidate on merits — but it replaces the SVR4 model (parallel dpkg-style
  status DB, `.ipk` not `.pkg`), forking away from the existing AmixBP/amigaunix.com ecosystem.*
- **opkg** (Yocto, v0.10.0 June 2026, alive): hard, unconditional **libarchive** requirement
  (~136k LOC of C99) + CMake ≥3.25. The transitive burden sinks it; everything it adds over ipkg
  isn't worth that. Weak. Signal worth noting: OpenWrt itself abandoned the opkg lineage (25.12
  ships Alpine apk).
- The **`.ipk`/`Packages` index *format*** is stealable without any code: line-oriented RFC-822
  stanzas, parseable with `fgets` in C89, carrying exactly the two things SVR4 metadata lacks
  (versions, deps). A `Packages`-style catalog whose `Filename:` fields point at existing SVR4
  datastream `.pkg` files gives remote fetch over stock `pkgadd` with no format fork.

---

## The full field (all 30+ candidates)

| Candidate | Verdict | License | Language | Hard deps on Amix | Effort |
|---|---|---|---|---|---|
| **Heirloom pkgtools** (Sun SVR4 pkg source) | **strong** | CDDL | C89 | shims only (snprintf etc.) | weeks |
| illumos svr4pkg | possible (as reference) | CDDL | C89-style | doors/zones un-port | months |
| **zap** (Tribblix) — as design template | **strong** (design) | CDDL | ksh93 | ksh93+curl (code unportable) | design: free |
| pkg-get (Blastwave) | strong (design) | permissive (verified in CSW copyright file) | ksh88 | ksh88+nawk+wget | design: free |
| pkgutil (OpenCSW) | possible | GPLv2+ | Perl (≥5.6 per verifier) | Perl + wget | days–weeks *if* Perl works |
| depothelper (HP-UX) | strong (design) | GPLv3 | ksh88, 951 lines | ksh | design: free |
| **ipkg 0.99.163** | **strong** | GPL-2 | C89/gnu89 | libc only + fetcher | weeks |
| opkg (Yocto 2026) | weak | GPL-2 | C, light C99 | **libarchive (C99, 136k LOC)** | months |
| opkg-lede (OpenWrt fork) | non-starter | GPL-2 | C | libubox, Linux-isms | — |
| dpkg 1.4.x (1998) | weak | GPL-2 | C89 (13k core) | GNU tar+gzip; **no network layer at all** | weeks, wrong payoff |
| dpkg modern / apt any / rpm modern | non-starter | GPL | C99+/C++/C++20+Rust | — | — |
| **rpm 2.5.6 / 3.0.6** (1998/2000) | possible | GPL-2 (lib LGPL) | pure C89 | zlib + BDB 1.85 (both C89) | weeks |
| Homebrew / Nix / Guix | non-starter | — | Ruby 4 / C++23 / Guile 3 | TLS everywhere | — |
| **Historical BSD pkg_install** (pkgsrc-2007Q4 / FreeBSD 4.11) | **strong** | BSD | plain C89 (~10–14k LOC) | exec tar+gzip; libnbcompat fills libc gaps | 2–5 weeks |
| Modern pkg_install + pkgin | weak | BSD | C | libarchive + SQLite (C99 wall) | months |
| FreeBSD pkg(8) | non-starter | BSD | C11 | 72k own + **1.36M LOC bundled deps** | — |
| **epkg (Encap)** | **strong** (niche) | NCSA/UIUC | C89, compat layer for 90s Unixes | none (verified zero-dep gnu89 build) | days |
| apk-tools v2/v3 | non-starter | GPL-2 | gnu11 | OpenSSL+zlib, Linux-isms | — |
| xbps / pacman / slapt-get / CRUX pkgutils | non-starter | misc | C99/gnu99/C23/C++ | libarchive/curl/OpenSSL | — |
| Slackware pkgtools / tazpkg | weak (model only) | BSD-ish/GPL | bash / POSIX sh | bash, GNU tar | model: free |
| GNU Stow / graft / CMU Depot | weak/non-starter | GPL | Perl (graft **fails on 5.005** — verified against actual Getopt::Long 2.20) | Perl | — |

Verified upstream-status notes: Tribblix zap HEAD 2026-06-20, Milestone 40 released 2026-06-12 —
the direction-(a) architecture is *actively shipping today*. OpenCSW's mirror still syncs
(MIRROR_LAST_SYNC 2026-07-04) four years after the project went dormant — static-file repos outlive
their maintainers. `libfget` (epkg's FTP module) was recovered by the verifier inside the `fget`
package (FreeBSD distcache, md5-authenticated) — epkg's remote fetch is buildable after all.

## What the precedents prove (Solaris/HP-UX/AIX retro communities)

Every surviving small-community ecosystem converged on the **same architecture**: one maintainer +
a flat, rsync-able static file tree + a plain-text catalog + a **thin client (500–3,000 lines)
wrapping the unmodified native installer**:

- **pkg-get** (2,634 lines ksh) and **pkgutil** (3,165 lines Perl) over Solaris `pkgadd` — the
  OpenCSW 9-field catalog (`name version pkgname filename md5 size deps category`) is the de-facto
  SVR4 repo schema, proven for ~15 years.
- **zap** over illumos `pkgadd` — pipe-delimited catalog (sidesteps exactly the whitespace failure
  class that corrupted Amix's factory DB), overlays for package groups, "the server is just a web
  server and disk space." Actively maintained 2026.
- **depothelper** over HP-UX `swinstall` — the entire remote+deps layer for a whole OS community in
  **951 lines**, transport = the stock `ftp` client. The floor for how small this can be.
- **perzl.org** (AIX) — even simpler: server-side pre-computed dependency-closure scripts; zero
  client logic; survived its maintainer going inactive in 2016, still serving in 2026.
- Failure modes to design against: jagubox (single host, died with its curator), Blastwave
  (governance collapse), encap.org (source nearly lost). Repo must be dumb static files,
  mirrorable, archive.org-backed.

Amix already has the content side: amigaunix.com serves SVR4 datastream `.pkg` files (Parson's
rebuilds, 2020–2022) that install through stock `pkgadd` into `/var/sadm` — a direction-(a) tool
inherits every existing install for free. (AmixBP on SourceForge is dead weight: 5 files, newest
2009, tarballs only.)

## Criteria the evaluation added (completeness critic)

1. **Package production is the scarce resource**, not client features — the build side runs on a
   modern Linux host (gcc-cross-amix; NetBSD still cross-builds 11,449 m68k packages in 2026, so 68k
   at scale is solved), and the catalog generator can be any modern language.
2. **Upgrade semantics**: stock `pkgadd` has no upgrade verb — the client must own version-compare +
   the `pkgrm`/`pkgadd` dance + config preservation; the catalog format must define version ordering.
3. **Trust without TLS**: md5 for integrity vs corruption; if tamper-resistance is ever wanted, an
   Ed25519 signify/minisign-style verifier is small portable C — GPG is not an option.
4. **Bootstrap**: ship the client as one self-contained `.pkg` datastream. This is what demotes
   Perl/ksh clients — a static C89 binary bootstraps trivially; interpreters are an extra port.
   (Counterpoint noted: a one-time pdksh port would unlock all the ksh-based tools — but a 2–3k-line
   C client is less total work than owning a shell port *plus* a script.)
5. **Offline/sneakernet users are first-class**: repo stays human-browsable; client must install
   from a local dir, not only from a URL.
6. **Crash consistency**: `contents` rewrites must stay tmp+rename; back up `contents` before
   mutation; disk-space preflight (datastreams spool through `/var/tmp` — double-space requirement).
7. **Namespace rules**: catalog must partition community packages from Commodore's 31 OS packages so
   "upgrade all" can never clobber the base OS (whose install media are scarce and proprietary).
8. **Total lines owned** is the real cost axis for a dozens-of-users project: bespoke-thin-client
   ≈ 2–3k; ipkg fork ≈ 18k; BSD pkg_install port ≈ 30k incl. compat; Heirloom ≈ 100k; and the WinUAE
   bench is the cheap regression rig for whichever is chosen.

---

## Recommendation

**Direction (a), sharpened: keep the stock SVR4 engine, repair its data, and build a small C89
remote layer on top — with Heirloom as the source-level insurance policy.**

Rationale: the Session-1 finding removed direction (a)'s only real unknown — the stock machinery
*works*. Three independent, production-proven ecosystems (OpenCSW, Tribblix, HP-UX) demonstrate the
exact architecture at 1–3k lines of client logic. It's the only direction with **zero migration**
(Goal #3 evaporates: `/var/sadm` stays the one true DB), full compatibility with the existing
`.pkg` corpus, MIT-licensable fresh code, and the smallest owned-code footprint. Every "port a
manager" alternative buys its dependency resolver at the cost of a parallel DB, an ecosystem
repack, GPL, and 6–15× more code owned.

Phased shape:

- **Phase 0 — repair + guard (days):** fix the corrupt `contents` line; write a small
  `contents`-fsck (detect/repair whitespace-in-pathname and malformed records, backup+rename
  discipline). Immediately makes stock `pkgrm`/`pkginfo -l` work for everyone.
- **Phase 1 — the remote layer (the core build):** a static C89 client (~2–3k LOC) shipped as a
  single `.pkg`: fetch catalog + packages over plain HTTP (tiny built-in HTTP/1.0 GET; FTP via
  native client as fallback), md5 verify, resolve deps recursively from the catalog, drive stock
  `pkgadd -n` with a permissive admin file, implement upgrade via version-compare + `pkgrm`/`pkgadd`.
  Catalog: **pipe-delimited** (zap syntax) with **OpenCSW 9-field semantics** (name, version,
  pkginst, filename, md5, size, deps, category) — versions and deps live in the catalog, not in
  `/var/sadm`, so stock packages need no touch. Server side = static files + a catalog generator on
  the Linux host.
- **Phase 2 — rebuild the missing/fixed stock tools from Heirloom (optional, weeks):**
  cross-compile `removef` + `pkgask` first (the tools Amix lacks), hardened parsers later if wanted.
  This is where "build a new fixed version from source" pays off — selectively, not as a wholesale
  replacement. Keep illumos svr4pkg as the semantics reference.
- **Build pipeline (parallel track):** gcc-cross-amix–based package cross-building on the Linux
  host + `pkgmk`/`pkgtrans` on-box or host-side; author versions/deps for the existing
  amigaunix.com corpus into the first catalog.

**Plan B** (if a modern package *model* is preferred over SVR4 compatibility): port **historical BSD
pkg_install** — pkgsrc-2007Q4 core (the last pre-libarchive vintage, verified) + libnbcompat as the
SVR4 libc shim + FreeBSD 4.11 libfetch for ftp/http (caveat: its `funopen()`/`getaddrinfo()` BSDisms
need shimming — verifier-confirmed). ~30k LOC, BSD-licensed, ranged dewey deps, 2–5 weeks; needs a
one-shot `/var/sadm` importer and repacking of existing packages. Choose this only if ranged version
dependencies and the `.tgz` world are worth forking the ecosystem.

**Plan C** (complement, not competitor): **epkg** for versioned third-party experiments under
`/usr/local/encap` — verified zero-dependency gnu89 build, NCSA license, days of effort. Coexists
with `/var/sadm` rather than replacing it. Nice-to-have later; not the system manager.

Not recommended as primary: ipkg fork (good code, wrong ecosystem — parallel DB + `.ipk` repack +
GPL + dead upstream, when its one unique asset, versioned dep resolution, is ~500 lines to write
fresh against a catalog we control); old rpm (same fork cost, 30–60k LOC owned, PGP2-era trust).

## Sources / evidence

Research run 2026-07-04 (independently re-verified; the full structured digest with per-claim
CONFIRMED/REFUTED verdicts and file:line evidence was kept outside this tree).
Key repos inspected at source level: heirloom-pkgtools (aflat mirror), illumos-gate, tribblix/zap,
bolthole pkg-get 4.2, OpenCSW pkgutil r464, ipkg 0.99.163 (archive.org, built + ldd-verified), opkg
v0.10.0, dpkg 1.4.0.23.2 + apt 0.3.19 (archive.debian.org), rpm 2.5.6/3.0.6 (ftp.rpm.org),
pkgsrc-2007Q3/Q4 + NetBSD 1.6 pkg_install + FreeBSD 4.11 (git mirrors), DanGrayson/epkg (built),
apk-tools, xbps, pacman, slapt-get, CRUX pkgutils, Slackware 15.0 pkgtools, depothelper 2.20,
perzl.org, cdn.netbsd.org m68k package trees, amigaunix.com, AmixBP SourceForge.
