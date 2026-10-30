# Man pages

Every package ships the manual pages of what it installs: upstream's pages for every command and
configuration file, and a page of our own where upstream has none (owner rule, 2026-10-30). This
file is the layout the packages install and the base package's `man` front-end reads; the base
station keeps the same contract in `userland/base/docs/man.md`.

## Layout

| Path | What |
|---|---|
| `/opt/amix/man/<sect>/<name>` | One page: troff source with the `-man` macros, no suffix, not compressed, mode 0644. `<sect>` is the section directory as stock names them (`1`, `3`, `5`, no `man` prefix); upstream's section numbers are kept (`rsyncd.conf` stays in 5). `<name>` is at most 14 bytes, the s5 limit. |
| `/opt/amix/man/<sect>/<alias>` | An alias: one line, `.so /opt/amix/man/<sect>/<target>` (an absolute path). |
| `/opt/amix/man/whatis.d/<PKG>` | The package's whatis fragment, named by its SVR4 instance (at most 9 bytes): one line per page file in the package, aliases included, in stock whatis form, `name(sect)` padded with spaces to column 18 and then `names - description`, sorted. |

The directories `/opt/amix/man`, `/opt/amix/man/<sect>` and `/opt/amix/man/whatis.d` are shared
`d` lines in every package that uses them. No package ships `/opt/amix/man/whatis`, and none ships
anything under the cat tree: the front-end reads `whatis.d/*` itself and keeps its formatted pages
in `/var/opt/amix/catman`, which only the base package creates. The two packages at `/usr/local`
(`acompat`, `patch`) put their pages here too, where `man` finds them. No package depends on the
base package: without the front-end the pages are plain files, readable with
`/usr/ucb/nroff -man <file> | more`.

[`tools/manpages.sh`](../tools/manpages.sh) does it for a recipe: a stage hook stages upstream's
pages the usual way (`$PREFIX/man/man<N>/<name>.<N>`), then

```sh
. "$HERE/../tools/manpages.sh"
amix_man_relayout                     # into /opt/amix/man/<N>/<name>; .so aliases made absolute
amix_man "$HERE/man/tar.1" 1          # a page of our own
amix_man_alias bunzip2 1 bzip2        # an alias
amix_man_whatis                       # whatis.d/<PKG> from each page's NAME section, last
```

and the prototype lists every page, alias and the fragment.

## Why this shape (measured on the stock system, 2026-10-30)

Stock `man` (`/usr/bin/man`, also linked as `catman` and `whatis`) reads ONE source tree,
`$MANPATH` (default `/usr/share/man`), finds a page only through that tree's `whatis` file, at
`<tree>/<section>/<name>`, and keeps formatted pages in ONE `$CATPATH` (default `/usr/catman`).
It has no `-M` and does not split `MANPATH` on colons. Set alone, `MANPATH=/opt/amix/man` makes it
format our pages into the stock `/usr/catman`, where a page of ours named like a stock one (`grep`)
then replaces the stock page for every later `man grep`; with `CATPATH` set too, the stock pages
are unreachable. So the packages lay their pages out the way stock `man` reads a tree, and the
base package's front-end searches `/opt/amix/man` first and hands any other name to the stock
`man` with `MANPATH` and `CATPATH` unset. Formatting is the stock pipeline (`tbl`, `eqn`,
`/usr/ucb/nroff -man -T37`, `col`), so a page uses only requests that 1991 `nroff` knows. The
measurements are in the grimoire (commands-cheatsheet, man pages).

## Pages written here

Upstream ships none for these, so the packages carry their own (in each package's `man/`):

| Package | Pages |
|---|---|
| `tar` | `tar(1)`: GNU tar 1.14 has only a texinfo manual; the page documents 1.14 as built |
| `acompat` | `acompat(3)` (the library, libamixcompat, and every function it provides, each also an alias: `snprintf(3)` … `gettimeofday(3)`), `acompat-test(1)` |
| `zlib` | `zlib-test(1)` (`zlib(3)` is upstream's) |
| `amix-benchmark-gcc14` | `amix-bench-g14(1)` |

`bzip2` adds the aliases upstream's `bzip2(1)` covers but does not install: `bunzip2`, `bzcat`,
`bzip2recover`.
