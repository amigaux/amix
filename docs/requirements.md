# Requirements & chosen direction

> *Decided 2026-07-04; **every deliverable below has shipped** and was bench-verified. This
> document is retained as the original requirements record — for current state read
> [../NOTES.md](../NOTES.md) (the authority) and [../CHANGELOG.md](../CHANGELOG.md).*

**Decided 2026-07-04:** Direction **(a) sharpened** — keep the SVR4 `pkg` model and the
live `/var/sadm` DB; adopt **Heirloom pkgtools** (aflat HEAD base) as the fixed/complete engine
with our patch set; build a small **C89 remote catalog client** on top. Evaluation:
[direction-evaluation.md](direction-evaluation.md) · engine dive:
[heirloom-pkgtools-dive.md](heirloom-pkgtools-dive.md).

## Functional requirements (from Jussi, 2026-07-04)

1. **Spaces in names are supported, everywhere.** Files and directories with spaces in their
   pathnames must parse, install, query and remove correctly — i.e. the tolerant-parser approach
   (validated 36-line `srchcfile.c` patch) is the baseline, not an optional repair mode.
2. **`contents-fsck`** — a command that checks and repairs the stock Amix `contents` database,
   which is broken by default on factory installs (space-in-pathname record, duplicated package
   fields, any other malformed records). Report mode + repair mode, backup + tmp/rename discipline.
3. **VERSION-less stock packages must work.** The tools must operate on the 31 factory packages
   that lack `VERSION` (query/list/remove at minimum). Additionally provide a migration tool that
   can **populate VERSION= into the already-installed DB** (`/var/sadm/pkg/*/pkginfo`).
   Future plan: repackage all Amix stock packages with proper version info.
4. **Remote repository support** with the verbs: **update** (fetch catalog), **list** (show
   available/installed packages), **search**, **download**, **install** (fetch + deps + pkgadd).
   - Repo = static file tree served as **`http://pkg.amigaux.org/`** (a plain static docroot,
     published with `tools/repo/publish.sh`). The host is a **name-based virtual host**: the
     hostname form is the only supported repo URL, and a request carrying a bare IP as its
     `Host:` value is answered 404. A box without DNS reaches it by adding
     `52.59.174.203 pkg.amigaux.org` to `/etc/inet/hosts`.
     *(Until 2026-09-14 this was a LAN-only mirror; see NOTES.md 2026-09-15.)*
   - **Plain HTTP is mandatory** (the Amix client speaks HTTP/1.0-1.1 GET); HTTPS maybe later
     (host-side tooling may use it; the on-box client does not require TLS).

## Environment / infrastructure (fixed points)

- **Bench:** a WinUAE guest (`configs/amix-winuae.example.uae` + a clean Amix 2.1c disk image,
  `hdf/Amix_UAE_clean.hdf`, gitignored), reachable over telnet/ftp. Work on copies, never the
  pristine image.
- **Cross toolchain:** [`isoriano1968/gcc-cross-amix`](https://github.com/isoriano1968/gcc-cross-amix)
  (binutils 2.8.1 + GCC 2.7.2.3, target `m68k-cbm-sysv4`); sysroot populated from an Amix 2.1
  system (never committed).
- **File transfer: FTP** — push and pull, both verified byte-clean. This is the working bridge.
  **Guest→NFS-server mounts do NOT work** against a modern NAS (established 2026-07-04, see
  NOTES.md Session 3): the server tested offers NFSv2 **over TCP only** (`rpcinfo` shows no UDP
  `nfs` service) and Amix's 1992 client is UDP-only.

## Deliverables (the plan, and where each one landed)

All six shipped. "Delivered as" names what exists at HEAD; the plan text is unchanged.

| # | Deliverable | Base | Delivered as |
|---|---|---|---|
| 1 | `heirloom/` vendored engine (aflat HEAD) + Amix patch set: tolerant parser, VERSION trio, cpio `-D`×3, trailer decision, buffer-bug hygiene, de-OpenSSL, `mk.config.amix` | research/heirloom/ artifacts | ✅ `heirloom/` — cross-built to m68k SVR4 ELF, eleven bench-verified root causes, apkg's default engine since v1.1 (`heirloom/AMIX-PORT.md`) |
| 2 | `contents-fsck` (report/repair) | dive harness | ✅ `src/contents-fsck/` — dogfooded on the live 28,716-record guest DB; `-s -r` is the canonical post-migration step |
| 3 | VERSION migration tool (populate `VERSION=` into installed DB) | trivial sh/C | ✅ `tools/migrate/amix-sadm-migrate.sh` — executed for real on the guest (27 `VERSION=` appends, 4 `install/` dirs) |
| 4 | Remote client — **`apkg`**: update/list/search/download/install over plain HTTP; pipe-delimited catalog (OpenCSW field semantics); md5 verify; drives `pkgadd -n` with permissive admin file; ships as a single `.pkg` datastream | new C89, ~2–3k LOC | ✅ `src/apkg/` — the name stuck; also `info`/`upgrade`/`remove`, recursive deps, and HTTP/FILE/RAW sources |
| 5 | Host-side repo tools: catalog generator + publisher for the package repo | modern host, any language | ✅ `tools/repo/` — grown well past a generator + publisher; see [design.md §5](design.md) |
| 6 | SVR4 pkg man pages for Amix (from Heirloom `man/`, CDDL) | free win | ✅ shipped inside `APKGENG` under `/usr/apkg/man/{man1,man1m,man5}` |

Bench checklist that gates the engine work: [heirloom-pkgtools-dive.md §Bench checklist](heirloom-pkgtools-dive.md).
