# boot2's room under its 28 KiB gate (2026-10-26)

- **What:** where boot2's next bytes come from, measured before a change
  needs them. The next ones are the stage-4 RAM-disk member (10 §5.4) and
  any CD-boot fix.
- **The gate:** `b2link` refuses a boot2 whose file, or whose image plus
  bss, exceeds 28 672 bytes. That is the area boot1 loads it into (10 §3,
  S3-15).
- **Class:** host measurement (`make boot2` with gcc-cross-amix, `-O2
  -m68020`), boot2 at amix-dlm 001b04a and after.

## 1. Where it stood, and the free saving taken

| | image | bss | image + bss | left |
|---|---|---|---|---|
| 001b04a (the k30 memory cap) | 27 292 | 1 380 | 28 672 | **0** |
| `ax_ctl_pick` with one scratch (this note's commit) | 27 264 | 892 | 28 156 | **516** |

`ax_ctl_pick` (loader/common/store.c) parsed both control-block copies
into two static 488-byte scratch structures. That was 976 of boot2's
1 380 bytes of bss, which the gate counts. It now parses copy A straight
into the caller's structure, and copy B into a single scratch. The
result is the same. The only difference: the caller's structure is
undefined when neither copy is valid, and every caller (boot2,
amix-cdboot, kbootset, lsstore, the host tests) stops on that. Nothing on
the console changes. `make test` passes, 683 checks.

## 2. Where the rest of boot2 is

| Part | text | rodata | Notes |
|---|---|---|---|
| core.c | 4 654 | 1 182 | selection, loading, hand-off; 43 literals, 1 176 bytes, of which the L-code table `lmsg` is 15 strings, 394 bytes |
| manifest.c | 2 842 | 198 | the GMF1 parser, shared with kbootset |
| inflate.c | 2 836 | 197 | needed: floppy pairs and netinstall deflate their members |
| rel.c | 2 570 | 16 | ET_REL, ET_EXEC, brel |
| main.c | 2 458 | 467 | the store medium, boot1's hand-over, B-codes; 17 literals, 508 bytes |
| bootinfo.c | 1 930 | 48 | bootinfo, RTH1/RTO1, AXL1, bind, the k30 cap |
| store.c | 1 654 | 0 | header, control block, tally |
| con.c | 1 198 | 74 | the console |
| menu.c | 1 136 | 379 | the menu; 22 literals, 402 bytes, two help lines 128 bytes |
| sys.c, select.c, input.c, amiga.s, start.s, crc32.c | 3 928 | 27 | |

`-O1` instead of `-O2` makes boot2 184 bytes larger (image + bss 28 856),
so `-O2` stays. gcc-cross-amix (GCC 2.7.2.3) has no `-Os`.

## 3. The next savings, in the order to take them

| # | Saving | Bytes (measured or estimated) | What the person at the console sees |
|---|---|---|---|
| 1 | `rel.c`'s relocation-note callback (`ax_rel_ex`'s `note`, two call sites) built only for the host tool that uses it (b2link's self-relocation table), not for boot2 | about 40 (estimate) | nothing |
| 2 | a loader-only build of `manifest.c`: records boot2 never reads (such as `created`) skipped by the generic unknown-key path instead of parsed; which records qualify is to be checked against core.c | 200–300 (estimate) | nothing |
| 3 | the L-code table: each `lmsg` text to at most 20 characters after its code (`L5 arena overflow`); 10 §9 holds the full meaning | about 150 | shorter failure lines; the codes stay |
| 4 | the menu's two help lines as one (`digit, Return, s d p, mouse`) | about 70 | a terser menu |
| 5 | the longest messages no spec or row quotes verbatim (after this note: `that disk is not part of this boot set`, `that is volume %u; insert volume %u`) cut to their facts | about 40 | shorter lines |
| 6 | a code-only L table: `amix-boot: L5 (generation 2)`, with 10 §9 as the only decoder | about 340 (instead of 3) | codes without words. Last resort |

Items 1 and 2 cost nothing on the console and come first. Items 3 to 5
change lines that the Bench reads, so each one updates the README rows and
spec lines that quote it, in the same commit. Item 6 is the last resort.

## 4. The two messages shortened in 001b04a

| Old form | New form | Quoted |
|---|---|---|
| `the kernel needs %u bytes, the largest fast memory region has %u` | `the kernel needs %u bytes, the region has %u` | nowhere in amix-dlm |
| `a brel kernel without bss= in its manifest: 512 KiB assumed` | `no bss= for this brel: 512 KiB assumed` | `tests/bench/README.md` S3-43-4, which now gives both forms. The CHANGELOG's 2026-10-25 entry describes the line without quoting it |

Bench evidence recorded before 001b04a (the S3-43 cells' serial logs)
shows the old form. That is history, not a pattern to grep for.

## 5. Stage 4: the two gates, and what root placement costs (S4-10)

**Both gates bind, and the file binds first.** `b2link` refuses a boot2
whose file (image plus its self-relocation table) or whose image plus
bss exceeds 28 672 bytes. At amix-dlm 24e1ae1:

| | bytes | left |
|---|---|---|
| image | 27 264 | |
| self-relocation table | 1 092 | |
| **file** | **28 356** | **316** |
| bss | 892 | |
| image + bss | 28 156 | 516 |

§1's "516 left" is the image + bss gate. New code grows the table as
well as the image, so the file's 316 is the figure to plan against.

**Root placement, measured by building it** (the prototype is not
committed; the directory written as C4-4 version 2 §1 lays it out:
counted first, the manifest copy at 32 + 48 × count, each module
16-aligned with its zeroed `bss=` tail, L5 on overflow):

| Variant | file | image + bss | cost (file) | over the file gate |
|---|---|---|---|---|
| boot2 evaluates `match=` (FindConfigDev per `zorro:` key) and the safe set | 29 100 | 28 872 | +744 | 428 |
| boot2 places every root record (safe mode: only the safe set); `match=` left to the core | 28 804 | 28 584 | +448 | 132 |

Reading `bss=` costs nothing: the manifest parser already reads it for
the kernel record. Marking the safe set with a `safe=1` attribute costs
about 10 bytes in the parser, against the root-record parsing that §2's
rule would need. A motherboard root's `root sd … mobo` record carries no
controller id, so boot2 could not tell the A3000 WD, Gayle and the
53C710 apart without it.

With the second variant, §3's items 1 and 2 (about 240–340 bytes, no
change on the console) cover S4-10. S4-11's RAM-disk placement is not
measured yet; §3's items 3–5 (about 260 bytes) are the budget for it.

**§3's items 1 and 2, taken (2026-10-26).** Nothing changes on the
console:

| Step | file | image + bss | left (file) |
|---|---|---|---|
| before (24e1ae1) | 28 356 | 28 156 | 316 |
| item 1: `rel.c`'s notes only under `AX_RELNOTE` (b2link) | 28 218 | 28 020 | 454 |
| item 2: the loader build of `manifest.c` (`AX_LOADER`) skips `boards`, `cpu`, `created`, `param` | 28 042 | 27 852 | 630 |

Item 1 gave 138 bytes, not the estimated 40. Item 2 gave 176. With S4-10's
measured +448, 182 bytes of file stay for S4-11, before items 3–5.
