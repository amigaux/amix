# contents-fsck

Standalone checker/repairer for the SVR4 `/var/sadm/install/contents` database
(the master installed-object DB the stock `pkgadd`/`pkgrm`/`pkginfo` tools
parse). Written for Amiga Unix (Amix) 2.1c, whose **factory DB ships corrupt**:
the X11R5 package installed a file literally named `TrueType Fonts`, and since
`contents(4)` is whitespace-delimited with no quoting, that single record makes
every stock tool that fully parses the DB abort with
`ERROR: bad read of contents file ... problem=unknown ftype` — killing `pkgrm`
and `pkginfo -l` out of the box. The record also carries a duplicated trailing
`X11R5 X11R5` package field. See `docs/stock-pkg-system.md` §3/§6.

Single C89 source file, libc only — no heirloom/pkglib dependency. Builds
identically on a Linux host and on the m68k SVR4 cross toolchain.

## Usage

```
contents-fsck <file>                    report mode (default)
contents-fsck -r [-s] [-b] [-o out] <file>   repair mode
```

**Report mode** prints totals (records per ftype, comment lines) and findings
with line numbers:

- `[unparseable]` — records no split can parse; includes the *reason* the best
  ftype candidate failed (e.g. `mode is not octal`)
- `[spaced-path]` — records recovered only via the tolerant re-join rule
  (pathnames with embedded spaces); the full recovered path is printed
- `[dup-pkg]` — duplicated identical trailing package fields
- `[sort-order]` — pathnames out of sorted order
- `[eq-hazard]` — `=` inside a non-`s`/`l` pathname (stock tools silently
  mis-split such a record at the `=`)
- `[long-line]` — lines over 4096 bytes

Exit status: **0** clean, **1** findings, **2** I/O or usage error.

**Repair mode** (`-r`) writes `<file>.fixed` in the same directory (tmp file +
rename; the input is *never* modified). Repairs performed:

- duplicated identical trailing pkg fields are deduped (first occurrence kept)
- inter-field whitespace is normalized to single spaces
- comment/directive lines (starting `#`, `:` or whitespace) are preserved
  verbatim, in place
- record order is kept — sort violations are reported, never reordered
- unparseable records are preserved verbatim (the tool never destroys data it
  does not understand)

Spaced-pathname records are **kept** by default (re-emitted verbatim-
equivalent; our patched tools tolerate them and the file on disk is real).
With `-s` they are **dropped** and the affected on-disk pathnames are printed
prominently so the files can be renamed first — use this for pure-stock-tool
systems. `-b` copies the input to `<file>.bak` before anything else;
`-o <out>` overrides the output path.

Typical Amix factory repair:

```
# contents-fsck /var/sadm/install/contents            (see what's wrong)
# contents-fsck -r -b /var/sadm/install/contents      (write .fixed + .bak)
# cp /var/sadm/install/contents.fixed /var/sadm/install/contents
```

## The grammar checked

New-style (path-first) `contents(4)` records, per ftype:

| ftype | fields after the pathname |
|-------|---------------------------|
| `f` `v` `e` | `ftype class mode owner group size cksum modtime pkg...` |
| `d` `x` `p` | `ftype class mode owner group pkg...` |
| `c` `b` | `ftype class major minor mode owner group pkg...` |
| `s` `l` | (pathname is `path=target`) `ftype class pkg...` |
| `?` | `ftype class pkg...` |

Mode is octal; size/cksum/modtime/major/minor are decimal. Multiple trailing
pkg fields = the path is shared by several packages. Tolerated extensions
seen in the wild: `?` as an unknown numeric value (the factory Amix DB has 42
such lines, e.g. `/dev/console c none ? ? 0620 root tty core`), Solaris status
prefixes `-+*~!%` on pkg fields, and `pkg\` / `pkg:class` suffixes.

**Tolerant re-join rule** (replicates the validated heirloom `srchcfile.c`
patch, `research/heirloom/contents-harness/`): the pathname is extended token
by token; a split is accepted at the leftmost token that is a single valid
ftype character `[?fvelspcbdx]` followed by whitespace *and* whose remaining
fields validate per-ftype. That recovers `.../MacFS/TrueType Fonts f none
0444 x sys ...` with the correct spaced pathname. The per-ftype validation is
what makes the rule safe: a path token that merely *looks* like an ftype char
(e.g. a file named `b`) produces a field tail that fails validation, so the
scan keeps extending.

**Sort-order key**: the **pathname** — for `s`/`l` records the on-disk first
token is `path=linktarget`, so the key is that token truncated at the first
`=`. `pkgadd`/`amixpkg` keep the DB in sorted *pathname* order, and comparing
the whole token instead spuriously flags every `s`/`l` entry whose path is a
prefix of the next entry's: the symlink `/etc/cron=/usr/sbin/cron` against a
following `/etc/cron.d` (`=` 0x3D sorts after `.` 0x2E, even though the
pathname `/etc/cron` correctly precedes `/etc/cron.d`). Real disorder is
still reported.

Deliberate decisions:

- records not beginning with `/` (old-style entries) are reported as
  unparseable and preserved verbatim, never rewritten
- "duplicated" pkg fields means *identical tokens*: `~PKGA PKGA` is two
  distinct references (different status), not a duplicate
- lines longer than 4096 bytes are a finding and pass through unmodified
- `-s`/`-b`/`-o` require `-r` (usage error otherwise)

## Building

```
make            # host build: gcc -std=c89 -pedantic -Wall -Wextra
make amix       # cross build for Amix (sources gcc-cross-amix/build/env.sh
                #   automatically if the toolchain is not on PATH)
make test       # run the test suite
make kat        # build + verify the known-answer branch/switch battery
```

The amix build is a **self-contained pipeline** — `gcc.real -S` →
`tools/asmfix.pl` → `as -m68020` → static `ld` — independent of the shared
`amix-gcc-wrapper.sh`.

**The `.swbeg` jump-table bug (the load-bearing fixup).** gcc 2.7.2.3 emits
every `switch` dispatch as `mov.w .LDnn(%pc,%a0.l*2),%d0` + `jmp
6(%pc,%d0.w)` + `.swbeg &N` + the offset table. The hard-coded displacement
`6` assumes the SGS assembler's `.swbeg` directive occupies **4 bytes**; GNU
as 2.8.1 parses it but emits **zero** bytes, so every switch case is entered
4 bytes late — its first instruction(s) skipped, the following conditional
branch running on stale flags from the switch range check. On the real Amix
machine this made `validate_rest()` report "too few fields" for nearly every
record (`n < 5` "firing" at n=5, the s-case strchr called with garbage args)
while the same source was perfect on the host. `tools/asmfix.pl` replaces
`.swbeg &N` with a 4-byte `.long N` filler, restoring the layout gcc
assumed; `tools/wrapper-swbeg.patch` carries the same fix as a patch for the
shared wrapper — **every cross-built userspace binary containing a `switch`
needs it** (apkg, the heirloom engine). Verified by disassembly: table-fetch
base == jump base (equal only with the filler), and every ftype case
dispatches to its first instruction (`moveq #7` for f/v/e, `moveq #4` for
d/x/p, `moveq #6` for c/b, `pea 61` for s/l).

`make kat` builds `tests/kat-branch.c` — a known-answer battery covering
`< <= == != >= >` over signed/unsigned/immediate/memory/pointer operands
plus sparse and dense switches (including the exact `sw('d',5)` shape that
failed on the guest) — runs it on the host for C-level ground truth, and
mechanically checks the dispatch invariant on the cross disassembly.
`tests/kat-branch.amix` (static) gives machine ground truth on the guest:
run it there, exit 0 = all pass.

**The link is static** against the image's own `/usr/ccs/lib/libc.a`
(+ `crt1/crti/crtn`). Don't switch back to dynamic linking casually: a
GNU-ld-built dynamic binary asks the 1991 SVR4.0 runtime linker to process
`R_68K_COPY` relocations for `__ctype`/`__iob` — a pattern no native Amix
binary uses (they carry those objects link-time-initialized in `.data`) —
plus a GNU-format PLT the AT&T rtld never saw. The static binary owns a
fully initialized `__ctype` table and stdio state, every libc call resolved
at link time.

Setting `CFSCK_DEBUG=1` prints tokenizer and `validate_rest` diagnostics
for the first 5 lines (used to isolate the `.swbeg` bug on the guest). When
checking exit status on the guest, don't pipe the command into
`tail`/`grep` — `$?` would be the pipe's exit, not the tool's.

## Tests

`tests/run-tests.sh` runs self-contained synthetic cases (spaced pathnames,
duplicate pkg fields incl. the `lp lp lp` owner/group false-positive trap,
`s`/`l` records, `=`-hazards, `c`/`b` devices with `?` major/minor, status
prefixes, sort violations, malformed fields, comment preservation, >4096-byte
lines, whitespace normalization, `-b`/`-o`/usage errors) and prints PASS/FAIL
per case. Set `CONTENTS_FACTORY=/path/to/contents.factory` to also run the
validation against the real 28,646-line Amix factory DB (kept out of the repo
— licensing boundary).

## License

MIT (`SPDX-License-Identifier: MIT`), Copyright (c) 2026 Jussi Alanärä — the
full text is in the header of `contents-fsck.c` and in the repository root
[`LICENSE`](../../LICENSE).
