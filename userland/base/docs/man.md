# One `man` for both trees

Amix's stock `man` reads one tree: `MANPATH` is a single directory with a
`whatis` index in it, and formatted pages go to one cache, `CATPATH`, by default
`/usr/catman`. With `MANPATH` aimed at the add-on tree and `CATPATH` unset, it
caches the add-on pages into `/usr/catman`, where a page with a stock name
(a GNU `grep`) then hides the stock one. (The measurements are in the
grimoire's man-page section.) The owner's direction, 2026-10-30: one `man` that
finds both, ours first, never writing into `/usr/catman`, with the stock
`/usr/bin/man` untouched.

## What it is

`man/man.sh`, installed by the base package as `/usr/amix/bin/man`, a Bourne
shell front-end. Its own page is `man/man.1`, installed as
`/opt/amix/man/1/man`, with its index line in `/opt/amix/man/whatis.d/amxbase`.

| Request | What happens |
|---|---|
| `man [sect] name ...` | for each name: `/opt/amix/man/<sect>/<name>` if it exists (without a section, the sections in the order 1, 1m, 8, 2, 3, 4, 5, 6, 7, then any other directory); else the stock `man` with the same section and name |
| `man -k word`, `man -f name` | the matching lines of `/opt/amix/man/whatis.d/*`, then the stock `man`'s own answer |
| no argument, any other option | the stock `man`, unchanged |

- **Formatting** is the stock pipeline, run from the top of the tree:
  `/usr/ucb/tbl | /usr/ucb/eqn | /usr/ucb/nroff -man -T37 | col`, shown
  through `$PAGER` (default `/usr/bin/more`) when the output is a terminal. A page that is only a
  `.so <path>` line formats its target (absolute, or relative to the tree).
- **The cache** is `/var/opt/amix/catman/<sect>/<name>`. A page is cached only
  when its section's cache directory is writable by the caller; the base
  package makes them root-owned, mode 0755, so root fills the cache and other
  users get the page formatted each time. A cached page older than its source
  is formatted again. A shared cache that everyone can write is avoided on
  purpose: anyone could plant a page for everyone else.
- **The stock `man` is protected from our tree.** If `MANPATH` points into
  `/opt/amix`, the front-end drops `MANPATH` and `CATPATH` before it calls the
  stock `man`, so the stock command never caches our pages in `/usr/catman`.

## The layout every package follows (agreed with the packages station)

1. A page is `/opt/amix/man/<sect>/<name>`: the section directory named as the
   stock ones are (`1`, `3`, `5`, no `man` prefix), the page name without a
   suffix, plain uncompressed troff with the `-man` macros, mode 0644, the name
   within 14 bytes.
2. An alias is a one-line file `.so /opt/amix/man/<sect>/<target>`.
3. A package's index is `/opt/amix/man/whatis.d/<pkginst>` (the SVR4 instance
   name, at most 9 characters, so the file name fits 14 bytes): one line per page
   file, aliases included, in the stock `whatis` format, `name(sect)` padded to
   column 18 and then `names - description`; sorted, no blank or comment lines.
4. The packages share `/opt/amix/man`, its section directories and `whatis.d`
   as `d` objects. No package ships `/opt/amix/man/whatis` (nothing assembles
   one; the front-end reads the fragments) or anything under the cache.
5. A package with pages does not depend on the base package: its pages are
   plain files, and without the front-end the stock `man` still shows them
   with `MANPATH=/opt/amix/man`.

## Where it sits on PATH

The stock login `PATH` begins `/usr/local/bin:/usr/bin:...`, and the add-on
userland's `/opt/amix/bin` is appended **last**, by owner rule, so that stock
commands keep precedence. Neither place works for this command: `/usr/bin/man`
is the stock one, and in `/opt/amix/bin` the front-end would never be reached.

So the base package adds one directory, `/usr/amix/bin`, between
`/usr/local/bin` and `/usr/bin`, through its `/etc/profile.d` drop-in (D-N23).
It holds only commands like this one, which answer for our files and pass
everything else to the stock command of the same name. Commands that replace
a stock one outright do not go there. A user's own `/usr/local/bin` still
comes first.
