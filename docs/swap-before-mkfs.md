# Real swap before mkfs (r6e, 2026-10-10)

In r6e (2026-10-10); r6d does not have it. It was parked first as a patch against `69cc46d`.

## The fault

The published A4000/030 config with 16 MB motherboard RAM, the public classic full disc, and a 512 or 1000 MB
empty disk (pubfull-512/1000, 2026-10-09). The install panicked right after `mkfs_ufs` printed its superblock list:

    PANIC: swapinub: segu_fault() failed to swap in the u area

Until section 2c the miniroot's only swap is `/dev/fakeswap` (dummydisk, which discards pages). 2c runs after mkfs
because it logs onto the mounted target. Building a 478 MB or 967 MB ufs root pages at 16 MB, and the page it needs back
is gone. The same configs passed at 100 MB (78 MB root) and at 64 MB RAM (the matrix rigs, and `69cc46d`).

## The change

`install.sh`, author mode, after the RDB read-back and before "Making filesystems":
- `early_target_swap` adds the target's swap slice (`swap -a /dev/dsk/c<ID>d0s<swap> 0 <len>`; the length comes
  from `/etc/rdb -p`, with the planned `$SWAPLEN` as fallback);
- it then deletes `/dev/fakeswap`.
- It uses stock's `set \`swap -l\`` form with no temp files, because nothing is mounted yet.
- It is fail-open, like 2c.

2c is unchanged: it finds the fake already gone, says "swap configuration left alone", and logs `swap -l`, so the
log still shows the real slice in the table. A prebuilt target (mkroot host-side) does not run this block; it never
runs mkfs on the box.

## Test plan

1. Static: `sh -n src/installer/install.sh`; `tools/installer-selftest.py` on the branch has no failure that master
   has not (on 2026-10-10 master's single failure was audit X on SET_REFS, fixed separately).
2. A trial classic full disc from the branch (`build-install-iso.sh`, a new name, never over r6d). The reproducer:
   pubfull at **16 MB** (the A4000/030 config set to 16 MB) with the 512 MB empty, set 2. Pass
   = INSTALL COMPLETE, a login boot, and install.log showing `swap: added ... before mkfs` and 2c's
   "left alone".
3. The same at 1000 MB (967 MB root), only if 2 passes.
4. Regression, matrix cells on trial media built from the branch: cd-public-r6 and cd-ufs-pub-r6 (classic, 100 MB),
   fd-a4091-pub-r6 (16 MB, floppy route), cd-full-pub-r6 (512 MB), and cd1-pub-r6 + cd2-emu-r6 (060 line; 30 MB
   swap floor). Pass = 10/10 with the r6d digests unchanged: the change touches no installed file.
5. Metal only if the owner re-cuts: the A4000D CD rows (M4, M6) as in the r6d METAL-PLAN.
