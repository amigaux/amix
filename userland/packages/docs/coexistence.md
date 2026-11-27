# Coexistence — how our packages sit beside stock Amix

Amix 2.1 ships a general SVR4 userland. Some of the tools this directory ports already exist on a stock
box at 1980s/1990s versions; most do not. This file is the **standing policy** for how a ported
package coexists with stock — the prefix it installs under, the files it must never touch, where
`/opt/amix/bin` sits on PATH and how a user reaches the newer tool, and what `pkgadd` actually does
when two packages claim one path. Every recipe inherits it; a recipe that wants to diverge
argues here first, in the commit that changes this file.

Package paths
(`patch/prototype`) are relative to `userland/packages`; `userland/pkgtools/…` and `build/…` paths
are relative to the top of amix.

Confidence tags: **[MEASURED]** by this family on the bench,
**[PROVEN-AMIX]** an artifact ran on Amix, **[UNVERIFIED]** believed with a reason but unchecked,
**[OPEN]** a decision not yet made. Stock-side facts here are read out of
`userland/pkgtools` — the authority on what stock ships (its `docs/stock-pkg-system.md`, the
repackaged factory catalog, and the install-tape extraction), never re-invented.

---

## 0. The decision, in three lines

1. **Install everything under `/opt/amix`** — one shared `/opt/amix/{bin,lib,man,share}` for the
   whole add-on userland. Cross-configure with `--prefix=/opt/amix`. Never claim a stock-owned path.
2. **`/opt/amix/bin` goes LAST on PATH** — the user's own hand-built tools in `/usr/local` first,
   stock SVR4 next, our packaged tools after it. A name stock also has (`tar`, `grep`, `ls`) runs the
   stock program; ours runs by full path, or for a user who puts `/opt/amix/bin` first.
3. **Port a tool only if the chosen version adds something users want over stock.** Otherwise mark
   it `skip-stock-adequate` and move on.

---

## 1. The prefix is `/opt/amix` — not `/usr/local`

**[MEASURED]** on the repackaged factory `contents` DB, both directories already exist on a stock
root, and both are owned by `core`:

```
/opt        d none 0755 root root core
/usr/local  d none 0755 bin  bin  core     # exists, but ships empty
```

We install under **`/opt/amix`**, and deliberately **do not** use `/usr/local`, for two reasons
that pull the same way:

- **`/opt` is SVR4's own defined home for add-on application packages.** Putting a coherent
  ported-tool distribution under one `/opt/<vendor>` prefix is exactly the established pattern:
  OpenCSW's **`/opt/csw`** and Sun's freeware **`/opt/sfw`** are the prior art. It aligns with the
  packagemanager side's `extra` install-set, which is the named handle for precisely this
  add-on userland (`userland/pkgtools/tools/repo/sets.conf`).
- **`/usr/local` is reserved for the user's own hand-installed, non-packaged binaries.** Mixing
  `pkgadd`-owned files into `/usr/local` would intermingle package-managed and manually-managed
  trees in one directory — the thing that makes `/usr/local` impossible to reason about later.
  Keeping our payload out of it means **`/usr/local` stays package-manager-free and user-owned**,
  while **`/opt/amix` is a 100%-package-owned tree** — clean for `pkgchk`, clean for `pkgrm`,
  nothing in it that a person put there by hand.

**Layout: one shared prefix, not a per-package subtree.** The whole add-on userland shares
`/opt/amix/{bin,lib,man,share}`. We do **not** use `/opt/<pkg>/...` (the SVR4 default for a single
vendor product, and what the packagemanager's throwaway `AMIXtst` test package used —
`/opt/amixtst/...`): a per-package tree fragments the PATH into a dozen `bin` directories, each one a
line to manage. `--prefix=/opt/amix` for every recipe; `man` pages under
`/opt/amix/man` (or `/opt/amix/share/man`), read by adding that dir to `MANPATH`.

**That `/opt` works as a `pkgadd` target is [PROVEN-AMIX]:** the packagemanager side installed and
removed a throwaway package that dropped `/opt/amixtst` cleanly with the stock engine
(`userland/pkgtools/docs/stock-pkg-system.md` §5). `/opt/amix` itself is **unowned by any
stock package** — creating it is ours to do.

**Relationship to the other parallel prefixes.** Three trees stay disjoint on a full box, and that
is the whole point:

| Tree | Owner | What lives there |
|---|---|---|
| `/opt/amix` | **this directory** (`userland/packages`, formerly amix-packages) | the ported GNU/BSD userland |
| `/usr/apkg` | `amix-packagemanager` | the package *system* itself (apkg client + heirloom engine) |
| `/usr/local` | the **user** | hand-built, non-packaged binaries |
| `/usr/bin`, `/sbin`, `/usr/ccs/bin`, `/usr/ucb`, `/usr/public/bin`, … | Commodore (`core`, `public`, …) | stock SVR4 |

---

## 2. Never overwrite a stock-owned file

**The rule:** a recipe's `prototype` must emit **no path outside `/opt/amix`** — with the single
sanctioned exception of *declaring* (never overwriting) a shared parent directory the contents DB
already co-owns (`/opt` itself), exactly as the `patch` recipe declares `/usr/local` today.

This is not a style preference; three concrete failures are avoided:

1. **No `/var/sadm/install/contents` co-ownership with a stock package.** If we wrote, say,
   `/usr/bin/grep`, the contents DB would record that path as owned by both `core` **and** our
   package (`mstat.shared`, `npkgs++` in the engine — see §4).
2. **A stock `pkgrm` can then delete our file.** Removing the stock package that co-owns the path
   takes our binary with it.
3. **We never trip the `pkgadd` conflict machinery at all** (§4) — because nothing we ship lands on
   a path any installed package already claims.

**Stock-owned trees to stay out of** (owner in parentheses, **[MEASURED]** from the factory
manifests): `/usr/bin`, `/sbin`, `/usr/sbin`, `/usr/ccs/bin`, `/usr/ucb`, `/usr/public/bin`, `/etc`,
`/usr/lib`, `/usr/share`, `/usr/amiga/bin` (all `core`, except `/usr/public/bin` shared with
`public`). `/opt/amix` is under none of them.

Under `/opt/amix` this rule is satisfied **by construction** — there is no stock file there to
overwrite — which is the strongest argument for the prefix.

---

## 3. PATH order — `/opt/amix/bin` is last

The stock Amix login PATH **[MEASURED]** begins with `/usr/local/bin` and does not name
`/opt/amix/bin` (root's; other users' stock PATH adds `$HOME/bin` in front and `/usr/games:.` at
the end):

```
PATH=/usr/local/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:
     /usr/public/bin:/usr/hosts
```

On an installed system two `/etc/profile.d` drop-ins change it for login shells
(`/etc/profile` reads `/etc/profile.d/*.sh` in name order; no package edits `/etc/profile`):

- `amix-base.sh` (the base package) puts `/usr/amix/bin` just before `/usr/bin`. That directory holds
  only front-ends that answer for the add-on packages' files and pass everything else to the stock
  command of the same name (`man`; `userland/base/docs/man.md`).
- `opt-amix.sh` (written by the installer's first boot, `media/payload/firstboot/firstboot.sh`)
  appends `/opt/amix/bin` — **last**, so stock tools keep precedence.

The resulting login PATH (root's):

```
PATH=/usr/local/bin:/usr/amix/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:
     /usr/amiga/bin:/usr/public/bin:/usr/hosts:/opt/amix/bin
```

(The X drop-ins append their own directories after it.) What this means for a package here:

- **A tool stock lacks** (`gzip`, `less`, `bzip2`, `rsync`, `md5sum`, `vim`) runs by its name.
- **A tool stock also has** (`tar`, `grep`, `diff`, `make`, `ls`, `cp` …) runs the stock program (or
  the Heirloom one where a package replaced it, such as `/usr/sbin/tar`) under its plain name. Ours
  is reached in one of two ways:
  - by full path: `/opt/amix/bin/tar`, `/opt/amix/bin/grep`;
  - by putting `/opt/amix/bin` first in the user's own PATH, in `~/.profile`:
    `PATH=/opt/amix/bin:$PATH; export PATH`.
- **Stock system scripts** that name `/usr/bin/grep` or rely on the stock PATH keep stock behaviour
  either way.
- `man` follows the binary PATH runs: `man tar` shows the page of the `tar` that runs
  (`userland/base/docs/man.md`).

**What a package does not do:**

- **No package edits `/etc/profile`.** It is amix-base's conffile; a package that needs a PATH
  directory ships an `/etc/profile.d/<name>.sh` drop-in (`profile.d(4)`).
- **No symlink `/usr/bin/<tool>` → `/opt/amix/bin/<tool>`** to take a stock name — it re-enters
  `/usr/bin` (§2), and stock `pkgadd` **corrupts a relative symlink target**
  ([MEASURED], `patch/prototype`). `patch` is the one package that ships a `/usr/bin` symlink; stock
  has no `/usr/bin/patch` (its 1990 one is `/usr/public/bin/patch`), so nothing stock is shadowed
  in `/usr/bin` (§5).

---

## 4. What `pkgadd` really does on a path conflict

Because our policy never claims a stock path, we never reach this code in practice — but the
question "does `pkgadd` refuse / prompt / overwrite?" has a definite answer, read out of the engine
(`userland/pkgtools/heirloom/`) and the stock admin file, and it is *why* the policy is shaped
the way it is.

**Path-conflict handling is governed by the `admin(4)` `conflict` parameter**, resolved at
`heirloom/pkgcmds/pkgadd/check.c:885`:

```c
getyorn(a_msg, a_pkg, ADM(conflict, "nocheck"), ADM(conflict, "quit"), ...)
```

| admin `conflict=` | behaviour when a package claims a path an installed package already owns |
|---|---|
| **`ask`** (the stock default) | `pkgadd` **detects** the overlap, prints the conflicting pathnames, and **prompts** the user (`Do you want to install these conflicting files [y,n,?,q]`). *Yes* installs/overwrites; *No* skips those files; *Quit* aborts. |
| `nocheck` | **silently installs / overwrites**, no prompt. (This is what the family's non-interactive `pkgadd -n` + a permissive admin file does in the bench pipeline.) |
| `quit` | **aborts** the install. |

The **stock factory admin file sets every check — `conflict` included — to `ask`** ([MEASURED]
firsthand, `docs/stock-pkg-system.md` §5). So on a bare stock box, a conflicting install *prompts*;
it does not silently clobber, and it does not hard-refuse.

**On an accepted overwrite, the path becomes co-owned.** The contents-merge records the file as
`shared` between both packages and bumps its owner count (`mstat.shared`, `npkgs` in
`heirloom/libinst/pkgdbmerg.c`) — the same multi-owner grammar visible in the factory DB. That is
the concrete mechanism behind §2's "a stock `pkgrm` can then delete our file": once co-owned,
removing either package can remove the shared file.

**Conclusion:** the safe design is not "answer the prompt carefully" — it is to **install under a
tree no stock package owns**, so the conflict check finds nothing and never fires. `/opt/amix` does
exactly that.

---

## 5. Port a tool only if it adds value over stock

Stock Amix already carries a working general userland. A port earns its place **only** when the
chosen version adds features users actually want over what stock provides. The per-tool verdict is
recorded in each registry entry's `coexistence.verdict` field:

| verdict | meaning |
|---|---|
| **`port-alongside`** | the default. Newer/absent tool installs to `/opt/amix`, beside stock (if any); a stock name keeps running stock (§3). |
| **`skip-stock-adequate`** | stock already does the job and the delta is unwanted — do **not** port; record the reason. |
| **`replace`** | strong-justification only: our file must occupy the stock path (violates §2). No Wave-0/1 tool qualifies, and none is expected to. |

`patch` is the worked example, and an older layout: stock ships Larry Wall `patch` **12u4** (1990) in
`/usr/public/bin` **[PROVEN-AMIX]**; we ship GNU `patch` 2.5.9 at `/usr/local/bin/patch` with a
`/usr/bin/patch` symlink, both ahead of `/usr/public/bin` on PATH, so a plain `patch` runs ours —
`port-alongside`, without touching the 13-year-older tool. The `/opt/amix` packages do not take a
stock name this way (§3).

No Wave-0/1 tool is `skip-stock-adequate`: each either fills a genuine gap (gzip, less, bzip2,
rsync, zlib, md5sum/sha1sum) or adds features stock materially lacks (GNU grep `-r/-o/--color`, GNU
make pattern rules/VPATH, GNU tar base-256/`-z`, unified `diff -u`). The first genuine
`skip-stock-adequate` candidates live in later waves — a tool whose only delta is a feature stock
already has is one we should decline, and this field is where that decision is written down.

---

## 6. The stock-userland audit (Wave 0/1)

**[MEASURED]** against `userland/pkgtools` — the authoritative `core` package manifest (the
complete 28,866-member repackaging), the `hdf/tape21/` tape extraction, and the bench-verified
`patch` finding. `core` is in every install; `public` is in the standard 17-package set.

| Tool | Stock equivalent? | What stock is | Owner | The delta our port adds |
|---|---|---|---|---|
| **zlib** | **absent** | no `libz`/zlib anywhere | — | the compression library itself (first on the platform) |
| **libamixcompat** | **absent** | — (first-party libc shim) | — | libc symbols/headers stock lacks; build-time only |
| **patch** | **present** | Larry Wall `patch` **12u4** (1990) at `/usr/public/bin/patch` [PROVEN-AMIX] | `public` | 13 years of fixes, GNU option set |
| **gzip** | **absent** | BSD/Spencer `compress` **4.0** (LZW, `.Z`) + `pack`/`zcat` — no `.gz` | `core` (compress) | the `.gz`/deflate format itself; better ratio than `.Z` |
| **make** | **present** | AT&T/SVR4 `make` at `/usr/ccs/bin/make` | `core` | GNU make 3.81: pattern rules, VPATH, `$(shell)`/`eval`, order-only prereqs |
| **grep** | **present** | SVR4 `grep` at `/usr/bin/grep`→`/sbin/grep`; `egrep`/`fgrep` separate; no `-r/-o/--color/-P` | `core` | GNU grep 2.5.1a: `-r`, `-o`, `--color`, reliable `-E`, own regex |
| **less** | **absent** | pagers `more`/`pg`/`page` only | `core` (more/pg) | `less` itself: backward scroll, incremental search |
| **tar** | **present** | SVR4 `tar` at `/usr/sbin/tar` (+`/etc/tar`); ustar, no `-z`, no base-256 read | `core` | GNU tar 1.14: base-256 (modern archives), `-z`, long names |
| **diffutils** | **present** | SVR4 `diff`/`diff3`/`sdiff`/`cmp`/`bdiff` at `/usr/bin`; context `-c`; unified `-u` absent [MEASURED: `diff: invalid option -u`] | `core` | GNU diffutils 2.8.1: unified `-u` (every patch here is unified), better diff3 |
| **bzip2** | **absent** | none | — | `.bz2`; needed to open the `.cpio.bz2` Amix software corpus itself |
| **coreutils** | **partial** | SVR4 `ls`/`cp`/`mv`/`cat`/`sort`/… present; **no `md5sum`/`sha1sum`, no `cksum`** (only `sum`) | `core` | GNU coreutils 5.2.1: `md5sum`/`sha1sum` (box has no content checksum at all), GNU flags |
| **rsync** | **absent** | none (post-dates 1992) | — | `rsync` itself; also a candidate FTP replacement for the bench |

**Bonus finding (Wave 2, not audited-for-fields here):** stock `public` also ships a **`bash`**
(297 KB, dated March 1992 — a 1.x), plus `elm`, `gcc` (a 1.x driver), and `gdb` at
`/usr/public/bin`. So the Wave-2 `bash` port is another `port-alongside` beside a stock 1.x; under `/opt/amix`
the stock `bash` keeps the plain name (§3).

**Reconciliation note.** The `hdf/tape21/` extraction's `public/bin` shows only ~18 files
(the elm mail suite + bash/gcc/gdb) and does **not** contain `patch`, `gzip`, or `less`; yet
`patch` 12u4 *is* bench-verified present in stock `public` on the golden box.
The tape extraction is therefore **partial** for `public`, so it proves
*presence*, not *absence*, for that package. The audit above leans on the authoritative `core`
manifest (complete) for the base tools and on the bench finding for `patch`; a definitive
`pkginfo -l public` on the golden box is the clean way to close any residual doubt (a
box one-liner).

---

## 7. Open items for the packagemanager side (X-items)

- **[OPEN — the prefix, OVERRIDDEN BY THE BATCH-1 PUBLISH (2026-09-15)]** Confirm **`/opt/amix`** is
  acceptable to `amix-packagemanager` as the amix-packages payload prefix. The `extra` set exists
  for our packages but names no prefix; the engine uses `/usr/apkg`, the user keeps `/usr/local`,
  and `/opt/amix` is the disjoint third tree. Low risk — a natural split — but it is the
  packagemanager's catalog that will carry these packages, so record the blessing. **This item was
  still open when BATCH-1 was published anyway** (2026-09-15): the catalog now
  carries `patch` and `acompat` under `/usr/local` and `zlib`/`gzip`/`grep`/`less` under
  `/opt/amix`, live, with no formal blessing on either. The decision did not get made; it got
  overtaken by a publish. Still open for whatever ships next — and now with a real prefix split
  already live to reconcile against, not just a hypothetical one.
- **PATH mechanism (§3) — settled.** `/opt/amix/bin` reaches PATH through `/etc/profile.d/opt-amix.sh`,
  written by the installer's first boot, and it goes **last**: stock tools keep their names.
- **[MEASURED]** Box one-liner: **does stock `diff` support `-u`?** No: stock `/usr/bin/diff -u`
  says `diff: invalid option -u`, so `diffutils` adds unified diffs.
- **Category taxonomy — RESOLVED (2026-09-01), both sides.** The packagemanager side declared the
  category vocabulary and the exact 23-package mapping in `tools/repo/cats.conf` (adding `utility`
  and `editor` groups for this repo) and created the `extra` set in `sets.conf`. This repo has now
  reconciled against it: all 23 `registry/*.yaml` carry `category_status: agreed`, and the five
  stale `category:` values were corrected (`diffutils`/`grep`/`less` → `utility`; `elvis`/`joe` →
  `editor`), which also removes the contradiction with the already-minted `grep/pkginfo`
  and `less/pkginfo` (both `CATEGORY=utility`). Nothing further is owed on the taxonomy;
  the **prefix** item above is what is still open.

---

## Sources

- `userland/pkgtools/docs/stock-pkg-system.md` — stock `pkg` behaviour, the admin(4) default
  (`conflict=ask`), the `/opt/amixtst` install proof. [MEASURED, firsthand]
- `userland/pkgtools/heirloom/pkgcmds/pkgadd/check.c`, `libinst/pkgdbmerg.c` — the conflict
  resolution and shared-ownership recording.
- `userland/pkgtools/tools/repo/{cats.conf,sets.conf,deps.conf}` and the repackaged factory
  `catalog` — the stock package roster, the agreed taxonomy, the `extra` set.
- the Amix 2.1 install-tape extraction, kept outside the public tree (partial for
  `public`; complete `core` via the repackaging manifest).
- `patch/prototype` — the bench-verified stock `patch` 12u4 finding
  and the stock-`pkgadd` relative-symlink-corruption measurement.
