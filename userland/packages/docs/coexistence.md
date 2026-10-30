# Coexistence — how our packages sit beside stock Amix

Amix 2.1 ships a general SVR4 userland. Some of the tools this directory ports already exist on a stock
box at 1980s/1990s versions; most do not. This file is the **standing policy** for how a ported
package coexists with stock — the prefix it installs under, the files it must never touch, how the
newer tool wins for interactive users, and what `pkgadd` actually does when two packages claim one
path. Every recipe inherits it (cited from `ROADMAP.md` **D11**); a recipe that wants to diverge
argues here first, in the commit that changes this file.

`ROADMAP` Dn/Xn and `registry/<name>.yaml` citations name the planning records of the former
amix-packages repository, which stay with the maintainer and are not in amix. Package paths
(`patch/prototype`) are relative to `userland/packages`; `userland/pkgtools/…` and `build/…` paths
are relative to the top of amix.

Confidence tags follow the `ROADMAP.md` legend: **[MEASURED]** by this family on the bench,
**[PROVEN-AMIX]** an artifact ran on Amix, **[UNVERIFIED]** believed with a reason but unchecked,
**[OPEN]** a decision with a named owner. Stock-side facts here are read out of
`userland/pkgtools` — the authority on what stock ships (its `docs/stock-pkg-system.md`, the
repackaged factory catalog, and the install-tape extraction), never re-invented.

---

## 0. The decision, in three lines

1. **Install everything under `/opt/amix`** — one shared `/opt/amix/{bin,lib,man,share}` for the
   whole add-on userland. Cross-configure with `--prefix=/opt/amix`. Never claim a stock-owned path.
2. **PATH becomes `/usr/local/bin:/opt/amix/bin:/usr/bin:/bin`** — the user's own hand-built tools
   in `/usr/local` win first, our packaged tools beat stock next, stock SVR4 is the floor.
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
`/opt/amixtst/...`): a per-package tree fragments the PATH into a dozen `bin` directories and makes
the newer-tool-wins story unmanageable. `--prefix=/opt/amix` for every recipe; `man` pages under
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

## 3. PATH precedence — and the one cost of moving off `/usr/local`

Interactive users get the newer tool through PATH order, not by replacing stock binaries:

```
PATH=/usr/local/bin:/opt/amix/bin:/usr/bin:/bin:...
```

A ported GNU `grep` in `/opt/amix/bin` shadows stock `/usr/bin/grep` for anyone at a shell, while
the user's own `/usr/local` build (if they have one) still overrides both, and **stock system
scripts that hard-code `/usr/bin/grep` keep stock behaviour** — we change what a person sees, never
what a script sees. That last point is the safety of the whole scheme.

**The cost, stated plainly.** `/usr/local/bin` is *already* first on the stock Amix PATH
**[MEASURED]**:

```
PATH=/usr/local/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:
     /usr/public/bin:/usr/hosts
```

`/opt/amix/bin` is **not** on it. So unlike a `/usr/local` install (which needed zero configuration
to win), a `/opt/amix` install **requires `/opt/amix/bin` to be inserted into PATH** — after
`/usr/local/bin`, before `/usr/bin` — before its tools take precedence. This is the deliberate
trade for the clean, user-free `/opt/amix` tree, and the mechanism must be a **documented step**,
not a silent package side effect:

- **Do:** document the one-line PATH addition in each package's description / a README, and prefer a
  future **bootstrap package** that ships a sourceable snippet at `/opt/amix/etc/profile.amix` for
  the user to add to `/etc/profile` or `~/.profile` (`. /opt/amix/etc/profile.amix`).
- **Do not:** have a package edit `/etc/profile`. That file is `core`-owned (never overwrite, §2),
  and SVR4 package install scripts are an **[UNVERIFIED]** path on Amix's 1992 `/bin/sh` (**D9**).
- **Do not:** symlink `/opt/amix/bin/<tool>` from `/usr/bin/<tool>` to force precedence — it
  re-enters `/usr/bin` (§2), and stock `pkgadd` **corrupts a relative symlink target**
  ([MEASURED], `patch/prototype`), so it would also demand absolute-target care for no gain.

**[OPEN — owner: this repo, a maintainer decision]** how `/opt/amix/bin` reaches PATH out of the box (manual
line vs. a bootstrap-package profile snippet vs. left entirely to the user). See §7.

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
| **`port-alongside`** | the default. Newer/absent tool installs to `/opt/amix`, supersedes stock (if any) by PATH. |
| **`skip-stock-adequate`** | stock already does the job and the delta is unwanted — do **not** port; record the reason. |
| **`replace`** | strong-justification only: our file must occupy the stock path (violates §2). No Wave-0/1 tool qualifies, and none is expected to. |

`patch` is the worked example: stock ships Larry Wall `patch` **12u4** (1990) in `/usr/public/bin`
**[PROVEN-AMIX]**, we ship GNU `patch` 2.5.9 to `/opt/amix/bin`, and PATH precedence lets ours win —
`port-alongside`, superseding a 13-year-older tool without touching it.

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
| **diffutils** | **present** | SVR4 `diff`/`diff3`/`sdiff`/`cmp`/`bdiff` at `/usr/bin`; context `-c`; unified `-u` [UNVERIFIED, likely absent — X6] | `core` | GNU diffutils 2.8.1: unified `-u` (every patch here is unified), better diff3 |
| **bzip2** | **absent** | none | — | `.bz2`; needed to open the `.cpio.bz2` Amix software corpus itself |
| **coreutils** | **partial** | SVR4 `ls`/`cp`/`mv`/`cat`/`sort`/… present; **no `md5sum`/`sha1sum`, no `cksum`** (only `sum`) | `core` | GNU coreutils 5.2.1: `md5sum`/`sha1sum` (box has no content checksum at all), GNU flags |
| **rsync** | **absent** | none (post-dates 1992) | — | `rsync` itself; also a candidate FTP replacement for the bench |

**Bonus finding (Wave 2, not audited-for-fields here):** stock `public` also ships a **`bash`**
(297 KB, dated March 1992 — a 1.x), plus `elm`, `gcc` (a 1.x driver), and `gdb` at
`/usr/public/bin`. So the Wave-2 `bash` port is another `port-alongside`-superseding-a-stock-1.x
case, exactly like `patch`.

**Reconciliation note.** The `hdf/tape21/` extraction's `public/bin` shows only ~18 files
(the elm mail suite + bash/gcc/gdb) and does **not** contain `patch`, `gzip`, or `less`; yet
`patch` 12u4 *is* bench-verified present in stock `public` on the golden box
(`registry/patch.yaml`). The tape extraction is therefore **partial** for `public`, so it proves
*presence*, not *absence*, for that package. The audit above leans on the authoritative `core`
manifest (complete) for the base tools and on the bench finding for `patch`; a definitive
`pkginfo -l public` on the golden box is the clean way to close any residual doubt (an X6-class
box one-liner).

---

## 7. Open items for the packagemanager side (X-items)

- **[OPEN — X3-prefix, OVERRIDDEN BY THE BATCH-1 PUBLISH (2026-09-15)]** Confirm **`/opt/amix`** is
  acceptable to `amix-packagemanager` as the amix-packages payload prefix. The `extra` set exists
  for our packages but names no prefix; the engine uses `/usr/apkg`, the user keeps `/usr/local`,
  and `/opt/amix` is the disjoint third tree. Low risk — a natural split — but it is the
  packagemanager's catalog that will carry these packages, so record the blessing. **This item was
  still open when BATCH-1 was published anyway** (2026-09-15): the catalog now
  carries `patch` and `acompat` under `/usr/local` and `zlib`/`gzip`/`grep`/`less` under
  `/opt/amix`, live, with no formal blessing on either. The decision did not get made; it got
  overtaken by a publish. Still open for whatever ships next — and now with a real prefix split
  already live to reconcile against, not just a hypothetical one.
- **[OPEN]** PATH mechanism (§3): is `/opt/amix/bin` put on PATH by a documented manual line, by a
  bootstrap-package `/opt/amix/etc/profile.amix` snippet, or left to the user? Needs a decision
  before the first batch ships so every recipe's description says the same thing. **Also overtaken
  by the 2026-09-15 publish** without being decided.
- **[OPEN — X6]** Box one-liner: **does stock `diff` support `-u`?** Decides how much value
  `diffutils` adds. Batch it into the next bench login.
- **X3 taxonomy — RESOLVED (2026-09-01), both sides.** The packagemanager side declared the
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
- `registry/patch.yaml`, `patch/prototype` — the bench-verified stock `patch` 12u4 finding
  and the stock-`pkgadd` relative-symlink-corruption measurement.
