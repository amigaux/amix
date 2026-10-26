# Changelog

## Unreleased

## 2026-10-26 — C3-6 v4 §1.3: the interrupt level each driver entry runs at (d7af4b8, 937a373, 32ca41f)

_load/_unload of a boot- or demand-class module: level 0; a character d_open: the opener's level (spec_open writes no SR);
a STREAMS open: level 4 under the stock qattach (SR 0x2400; the trampoline leaves it), so a level-2 self-test half needs
one-tick timeout/sleep rounds (z3660eth 1.0.0-3's way) or runs at _load; root class at marc_root: level 7 with the clock
stopped (U1), no self-test there — attach, test and enable at a later process-context point, polled until then (the
gayle-ide module form's stage-4 case). Core patch 0028: the fact in dlm_str_open's comment (dlm.o b808cb52 unchanged).
The guide (§4) notes it, and that a driver without a read entry answers ENODEV, as monsw does.

## 2026-10-26 — Exit ledger: S3-44-1 and -2 PASS; -3 open (93c5e2d)

N86/N87: software interrupts reach both chains at once (0 spins), the level-6 claimer and counter counts are equal; a full
level-6 chain refuses the ninth handler with 168 and z3660eth falls back to polled; monsw's open is silent and loads it, a
read gives ENODEV by design. S3-44-3 open: the likely cause (kernel of record) is that a STREAMS open runs at IPL 4, so
z3660eth's software self-test can take the level-6 half but its level-2 half stays pending until the open returns —
z3660net's to fix; `intrl2=0` with intr=6 is the cheap confirmation.

## 2026-10-26 — Exit ledger: CD cell k46 PASS; K030-UZ and N84 (f25775f)

S3-31 part 3 k46 PASS (N85c); part 3 closed on both lines. S3-46's k30 instrument K030-UZ (a measurement kernel, retiring in
stage 4 with the root-class z3660scsi) recorded; its piscsi root proven on the emulator (N84). S3-44, S3-45, S3-46 remain.

## 2026-10-26 — S3-31 part 3, k30: PASS; the installed disk keeps boot priority 2 (73f218f, f6c770b)

The CD-booted, disk-rooted cell passes on k30 (N83c): amix-cdboot's line, the kernel at 0x04000000, the root record,
multi-user from the disk, the read-only-medium lines, the store byte-identical. An installed disk keeps boot priority 2;
the disc's node only ties it and the disk wins the tie, so a disc left in the drive never takes over a box. The CD is chosen
in the Kickstart early-startup menu or by lowering the disk's priority below 2 (stage-3-cd-boot.md §5, spec 50 §4 Rescue).

## 2026-10-26 — S3-44 rows, ledger gates restated, CD gate 3, namelist 0644, C3-5 v5, modcheck warning (f7eff90..5491d61)

S3-44's bench rows (README S3-44; probes t44intr and t44fill): the chains on the kernels of record, a full chain with
z3660eth's polled fallback ("zen: level-6 attach failed (errno 168); polled"), z3660eth 1.0.0-2 with intr=6 — no z3660net
build owed. Exit ledger: S3-27 done (monsw30/46 1.0.0-1 from amix-modules c0386d9); S3-31's box run done (installng's media
of record); S3-44/S3-45/S3-46 gates restated (none owner-gated); S3-46's k30 row on a bench variant kernel, the 1.1 record =
stage 4's root-class z3660scsi. kbootset: on `media --cd`/`--floppy` gate 3 checks only the root controller and filesystem
(C2-4 v11 §13, spec 40 §3.1; a --bootdev is noted and unused); `namelist` writes /stand/unix 0644 whatever the umask; box
kbootset d44f6a32 (→ kbootset -15). Spec 80: OQ-80.1 (030 metal), OQ-80.5 (an A4091 root on an 030 Z3660 needs a bounce or a
motherboard bind). C3-5 v5 §1.3: no rc script trusts a pid from an earlier boot (the stock syslogd case, zero margin).
modcheck warns when a demand-class load's working set passes 160 KiB (kit-test 64/64). monsw's ENODEV is the read (no
d_read: nodev), not the open — one Bench check confirms.

## 2026-10-26 — U2 answered; the process-context total (0bacad5, 52b903c)

N81 (k46 at 128 MB) / N82 (k30 at 64 MB): in process context after multi-user a module gets 320 KiB (320–383) resp.
640 KiB (640–703) of KVA in total with KM_NOSLEEP. Spec 30 §8: the working set of a load from a file (file buffer rounded
to a power of two, tables, image, module table — all at once, all KM_SLEEP; monsw ~15 KB, z3660eth ~57 KB, z3660rtg ~67 KB,
a cdfs-sized module ~232 KB, a module at the limit > 512 KiB) stays well under k46's total; C3-1's 256 KiB is a ceiling,
not a budget; larger modules are boot or root class (arena: no kmem for file or image). Spec 90 U2 answered. Exit ledger:
the S3-43 rows of record (N65–N76) and U2.

## 2026-10-26 — README: the stale syslog.pid as the conslogging 0 cause (340cfcb)

"conslogging 0 and no syslogd in ps" names its likely cause: the stock /etc/init.d/syslogd trusts a stale /etc/syslog.pid,
and the dlm sysinit line plus S01kbnamelist shift the early pids onto a live process (both together, 6/6 on the k46
vehicle; the installer's unit is fixed in amix-installng). No shipped script runs -K. No repair recipe: unverified.

## 2026-10-26 — Exit ledger: core patch 0027 rides the stage-4 kernel cut (ada916c)

The kernels of record keep dlm_maximage 2 MiB; the kit's modcheck guards every module meanwhile; a stage-3 re-cut would
force a third remaster of the media of record.

## 2026-10-26 — C3-1 v4: a module's image at most 256 KiB, its file under 256 KiB (07689e6, 1082c0c, 2ee5916)

From U4: the core's own KM_SLEEP allocations grow with the module (ten call sites, C3-1 §6: lf_hashload's buffer ×2,
ld_sh, ld_secoff, ld_syms, ld_str, ld_ls, oh.b, ld_tab, m_alloc), so a module much over 256 KiB would hang modload as
u4big did. The file limit comes beside the image limit because lf_hashload reads the whole file into one buffer doubled
up to dlm_maximage (cdfs: 97 611-byte file for a 69 080-byte image). §6 records the way past the limit (pieced KM_NOSLEEP),
not planned work. The kit's modcheck refuses a larger module at build time. Core patch 0027: dlm_maximage 256 KiB at the
next kernel cut, an oversized file is ENOLOAD "its file is over the limit" (before, a silent ENOMEM); dlm.o 77f1ef80 →
b808cb52; the kernels of record keep 2 MiB until then. kit-test: five edited-module refusal cases never ran (edit() wrote
into unmade directories and skipped without a failure) — revived, 62/62 both lines; printf for the \0 text. Module guide
§6 "Size and memory". Kit at KIT_REV 2ee5916 = the HEAD for dlmkit -4. Producers today: 18.8 / 30.8 / 5.2 / 97.6 KB files.

## 2026-10-26 — U4 answered; kmem requests at most 256 KiB; kit.conf fix (fca6140, 6c3b581, 134731f)

U4 (N79 k46 at 128 MB, N80 k30 at 64 MB): after multi-user one kmem request gives 256 KiB on k46 and 512 KiB on k30
(the fixed 4 MiB kernel map shared with page[] and the u-areas; page[] grows with RAM), and a KM_SLEEP request above
that never returns. Spec 30 §8 and C3-6 §1: a module's requests are at most 256 KiB each, KM_SLEEP only up to that,
every KM_NOSLEEP checked, larger buffers from pieces; root-class _load at boot keeps U1's rule. U2's probe takes 64 KiB
chunks (k46 fc7d439c, k30 34c32892) and runs in a boot of its own. README: -L's conslogging word tells the vehicle from
the kernel. mkkit: MONSW_REV is `repo@commit` (a space broke every `. kit.conf`; kits from 6492c3b..c6c9d02 affected,
the staged dlmkit -3 at c6ad5bd is not). kit-test 50/50.

## 2026-10-26 — README S3-41: U2/U4 need a generation with the arena (4041e80)

The S3-41 U2/U4 generation must carry the arena (l14.spec's form with the kernel's own arena and ident, or build's):
development load widens what may load but does not replace the manifest, so a noarena generation refuses every load
("no booted manifest, so no module loads this boot"). `modadmin -K` first on a box without a console logger.

## 2026-10-26 — modadmin -K keeps kernel messages in putbuf too (662de06)

Core patch 0026: `modadmin -K` (root) sets prt_where's PRW_BUF bit through the namelist and /dev/kmem, so every kernel,
core and module message is also kept in putbuf on a box with no console logger. Background: after boot printf stores into
putbuf only through the console logger (consbuf → log driver → logcons); the k46 vehicle has none registered (conslogging
0), so its run-time lines went to the console VT and were kept nowhere — the k46 S3-43 gap, a vehicle difference, not the
port kernel. README: when -K is needed, once per boot after S01kbnamelist, the console keeps every line, the 2000-byte ring
wraps (read `-L | tail` after each action), a line can appear twice more on a box with a logger. dlm.o unchanged; box
modadmin 0518fb28. Rides the next modtools mint.

## 2026-10-26 — spec 10 §7.3: a one-shot request boots the default (8e0b17a)

A one-shot request takes its boot ahead of a pending trial, and devload and safe requests boot the default generation,
never the trial (select.c's design: a diagnostic boot of the known-good default must not spend a new generation's one
attempt); a loader on trial also boots the default and consumes the request. Mark a new generation good before
`kbootset next devload`. README U2/U4 sequencing (the Bench's two void S3-41 tries).

## 2026-10-26 — U1 answered: root-class context at boot (806768d, b2930e4)

N77 (k46 5c4fad37) / N78 (k30 ce689ab4): at dmainit and at the rth1_mountroot hook both lines run at priority 7 (sr 0x2704
and 0x2700 are the same state, the low nibble is condition codes) with the clock stopped, so KM_SLEEP, sleeping and
timeouts are unsafe there; KM_NOSLEEP gives 1 MiB on both lines (k30 refuses 2 MiB at 64 MB; k46 gives 2 MiB at 128 MB).
Spec 30 §3 (after freeze): a root-class _load allocates KM_NOSLEEP only, at most 1 MiB per request, each checked; more comes
in pieces or later from process context. Spec 90's U1 row answered, exit ledger §4 filled, docs/measurements/2026-10-26-u1.md.
README U2/U4: `kbootset next devload` only once the installed loader is accepted (a loader on trial boots the default
generation and spends the one-shot).

## 2026-10-26 — modadmin -L prints the message buffer's words first (d834597)

Core patch 0025: `modadmin -L` starts with one line of the ring's words (putbufsz, putbufwpos, putbufrpos, conslogging,
prt_where), each read by lseek on /dev/kmem (a `dd skip` into kmem reads its way there from 0 and hangs the box). The ring
is printed from the byte after putbufwpos (the stock printf stores after a pre-increment; before, the newest byte came
first), text only: the log driver's logcons copies strlog data blocks with their header bytes into putbuf, and a cmn_err
line enters twice (xprintf and the log copy). dlm.o unchanged; box modadmin eeea43b3. Written for the k46 run-time-line gap
(S3-43): the code and initial data of the five putbuf functions are byte-identical on k46 and k30, so the words decide it.

## 2026-10-26 — boot2 gets 516 bytes of headroom back (aad576f, ea90332)

ax_ctl_pick parses the control block's copy A into the caller's structure and keeps one 488-byte scratch instead of two
(boot2's bss 1380 → 892; the struct is undefined on AX_ENONE and every caller stops there). boot2 28356 B, 344b8e07, 516 B
under the 28 KiB gate; nothing on the console changes. docs/measurements/2026-10-26-boot2-headroom.md records the per-part
sizes, the ranked next savings (free ones first) and every quote of the two messages shortened in 001b04a. Not packaged:
loader-amix -6 waits for the next loader change with a reason of its own.

## 2026-10-26 — boot2: a k30 kernel gets at most 64 MiB of fast memory; Z3 RAM is never kernel memory (001b04a, b7a1148)

ax_memcap caps the fast region holding a k30 bind address at base + 64 MiB in bootinfo.memory[] and empties a region touching
it from below (the stock support.c joins touching regions into the main store; over ~64 MB the 2 KiB-page kernel never starts
— N70, N75); the L4 fit check uses the capped room; k46 untouched. Spec 10 §3 and 40 gate 6: either line's kernel uses its
bind region only, so Zorro III RAM is never kernel memory. README: S3-43-8's kinfo expectation, new S3-43-9 (k30 in a 128 MB
bank), S3-43-7 and U2 in the CPU board's bank. boot2 28 392 B (6147ab3b) fills its gate exactly — 0 bytes left: the next
loader change must give bytes back first. 683 host checks; amix-cdboot rebuilt from the same core.

## 2026-10-26 — C3-5 §1.3 the 2.1 sh's while-read and probe facts; kit NOTICE from MONSW_REV (32587ae, c6c9d02)

A while-read loop strips trailing blanks on the 1991 sh, so it is never a byte-exact copy (cat or dd and a size check are);
installng's probe list of what the 2.1 sh does with redirections is recorded. The kit NOTICE names sys/monsw.h's origin from
MONSW_REV (amix-modules c0386d9, MIT); kit rebuilt at c6c9d02.

## 2026-10-26 — C3-5 §1.3 the script rule as enforced; C2-2 §2; kit.conf MONSW_REV (6492c3b, dc54ff4)

C3-5 §1.3 states the package-script rule as amix-packages' gate enforces it (sh builtins plus mv, cat, ls, dd, expr behind
test -x, refusing without; read only in a child with one redirection; the forbidden constructs; cat/dd copy, a size check
before every mv; proven on the 2.1 sh). C2-2 §2: a module record has a file line per plain file (the object and its modreg.d
file), none for the device node. kit.conf records MONSW_REV (the repository and commit of sys/monsw.h); the kit is rebuilt at
dc54ff4 with monsw.h from amix-modules b954ce9 (KIT_REV dc54ff4, PORT_REV ebe8dfd).

## 2026-10-26 — kbootset -14 deflates on the box; modadmin -L reads the kernel's message buffer; README fixes (9f175bf..7e731f9)

kbootset -14: its own raw deflate (kdeflate.c: fixed Huffman, LZ77 with hash chains, one byte of lazy matching) where zlib is
absent, so `--spec z=deflate` stores the member deflated on the box (-58: 2 431 362 → 834 032 B; K030-U 1 715 944 → 636 890;
both inflate through the loader's inflate; before, the null hook stored raw silently and gate 5 refused). Core patch 0024
(user side only, dlm.o unchanged): `modadmin -L` prints the kernel's message buffer (putbuf/putbufsz/putbufwpos through
/stand/unix and /dev/kmem, oldest first) — the read path for run-time lines of record, which the console does not show after
boot. README: where each line of record is read; S3-43-4's spec line takes bss= and z=deflate. mkkit takes sys/monsw.h from
amix-modules/include/sys/. 677 host checks; box kbootset 9acb9add, modadmin 7329e183.

## 2026-10-26 — monsw's home is amix-modules; kbootset -13: a boot from a read-only medium (e319d85..b6b4b87)

monsw lives in amix-modules (plan S3-27, Q3-2 settled; C3-6 §4; the kit ships include/sys/monsw.h — interface headers of
generic modules ship with the kit, versioned with their module; registry: b 20 ramdisk's home is amix-modules). kbootset -13:
on a boot from a read-only medium (AXL1 flag 0x08 — the CD, the floppy pair — with no boot node) mark-good marks nothing,
retry does nothing, status says the medium booted and marks none of the store's generations as booted, and the namelist comes
from the line's installed kernel when its build id is kinfo's (else "no namelist: booted from a read-only medium whose kernel
… is not the one installed here", exit 3). C2-4 v10 §13; 10 §6 names the AXL1 flag bits. Plan S3-31 and the exit ledger
carry part 3 as decided. Box kbootset e56172b6; KIT_REV=b6b4b87 (PORT_REV ebe8dfd).

## 2026-10-26 — C3-5 §1.3 the 2.1 sh's read; C2-2 §2 device nodes; the CD boot tree recipe (9000802, 42dd80d)

C3-5 §1.3: never re-read a file through `exec <file` — the 1991 sh's read keeps its buffer across the redirection and
continues where the previous read stopped (modtools -3 wiped /etc/inittab that way); one redirection per pass; scripts are
proven on the 2.1 sh. C2-2 §2: a module package's device node gets no `file` line in the record. docs/plan/stage-3-cd-boot.md:
the CD boot tree recipe per line (`kbootset media --cd`, `mkstore -C TREE -x amix-cdboot`, Startup-Sequence → SYS:BOOT/
amix-cdboot), what is unproven (the whole CD path has never run on any box), the emulator needs (an A4091 ROM with the
ODFileSystem profile), and the first cell: a disk-rooted generation booted from the CD; the installer CD (RAM-disk root) waits
for stage 4's ramdisk module.

## 2026-10-26 — boot2 binds the kernel only below 0x40000000; ledger and README updates (92d2924..d51fb2c)

A kernel bound in Zorro III expansion memory never starts (S3-43-7, N69/N70): the kernels identity-map the low 1 GiB and keep
syssegs and the sptalloc arena at virtual 0x40040000–0x40440000, so text at 0x40000000 is unmapped or overlapped once
translation is on. boot2 clips every region at AX_IDMAP_TOP = 0x40000000 (the stock bind.c had no such limit); with no fast
memory below it: "no fast memory below 0x40000000 to run the kernel in", L4, the next generation. Loader version stays 2
(manifest untouched); boot2 28 136 B (e36c1c55), 236 B under the gate; amix-cdboot rebuilt from the same core.c. Spec 10 §3
states the rule; 40 gate 6 is an estimate counting all fast memory, L4 is the binding check. README S3-43-8 is the row.
Exit ledger §2: all twelve B rows pass; README carries the sweep's three deviations. make test 671 checks.

## 2026-10-26 — S3-41 recipes (U1 by -DDLM_U1, U2/U4 probes); core patch 0023; the stage-3 exit ledger (1ca60a0..377866f)

U1 (the process-0 load context) is measured by a -DDLM_U1 build of each kernel of record: core patch 0023 prints at the end
of dlm_init and at the hook the SR, u_procp, whether the clock ticks, and five KM_NOSLEEP allocations up to 2 MiB; without
the flag dlm.o is byte-identical. U2 and U4 by the probe modules u2kva and u4big (tests/bench/s3-41/mkprobes.sh, built with
the kit, development load at 128 MB). 90 names the recipes; U15 stands answered. docs/plan/stage-3-exit.md: the bytes of
record per line and every row's result; plan Q3-2 records monsw, z3660rtg's dependency and the metal rows as open.

## 2026-10-26 — C2-2 §2.1 as apkg 0.3.1; C3-5 §1.2 device nodes; the S3-43 hand-over (47941d0, 568b9ac, cb64436)

C2-2 §2.1 follows apkg 0.3.1 (`apkg recover` finishes a cut; the readings confirmed). C3-5 §1.2: a driver module's package
ships the device nodes of its majors as pkgmap device entries (z3660eth /dev/zen0 c 51 0), no script; S99zen does the network
plumbing. tests/bench/s3-43/handover.sh writes one line's inputs for the acceptance sweep: the module set (tree/, s43/), the
checker's and host loader's verdicts, l14.spec, l5.img sized to the vehicle's boot slice (gen 1 good + gen 2 on trial with a
64-byte arena), SHA256SUMS; L5's line of record is "the arena needs 337 bytes, it has 64" on k46 and 367 on k30.

## 2026-10-26 — C2-2 v5 one kernel package per line; the stage-3 mint's package conventions (0d49ddd, 2a9cd81)

C2-2 v5 §2.1: installing a kernel package replaces the line's other kernel package in the same transaction (pre-flight of
every installed module record against the new kernel; pkgrm and record of the old one before pkgadd and record of the new;
one trigger; recover finishes a cut; two existing records of one line refuse) — apkg 0.3.1. Conventions: a kernel catalog
row carries line/kabi/pin from the sidecar and kbootset reads the rest from the installed sidecar; a module row takes
kabi/pin from .moddata and has no depend= (gate 3 enforces dependencies); file= under base/; module packages CATEGORY
system with mod.d/modreg.d files and modes as minted, modreg.local.d never shipped; K030-U's version is k30.1.0.261026-01;
an ET_REL kernel needs no bss= or sym=.

## 2026-10-26 — kbootset reads unix.sym as ET_EXEC by section name; L5 as L2; C2-3 kernel names (9763024, bb088bb)

kbootset reads unix.sym as an ET_EXEC whose st_value is the address with the kernel bound at 0 (no section base added) and
tells its NOBITS sections apart by name — before, every NOBITS section counted as bss and rodata/data read as 0 (the symbol
values were right; the k30 layout check compares only text). s3-standin.sh carries the sidecar's sym= file and record line.
Spec 10 §9: L5 is handled as L2. C2-3 v6: the unix.sym form (ET_EXEC, st_value = value at bind 0, section symbols move by
the bind, SHN_ABS constant but etext/edata/end); module kernel packages kernel-k46-m/kern46m and kernel-k30-m/kern30m,
version <kabi>.<yymmdd>-<nn> from the build id. The k30 S3-43 set rebuilt from the s3-21e .etrel. Box kbootset cd02b817.

## 2026-10-26 — S01kbnamelist; C3-5 module/VERSION; the S3-43 recipes and the rule-breaking module set (e024b55, 8be28b8)

C2-4 §12: the early rc2 script is S01kbnamelist (rc2 runs S* in byte order; S02PRESERVE would sort before S02kbnamelist).
C3-5 §1.1: a module repo records its package version in module/VERSION (z3660eth 1.0.0-1, z3660rtg 1.1.0-1). The S3-B5
z3660eth hashes are final (kit e84878e). tests/bench/s3-43: mkset.sh builds the module set with the line's kit — stand-ins
monsw and z3660rtg, t43boot/t43leak/t43fail/t43rel, t43ext, and ten rule-breakers each refused for exactly its rule (the six
load-time ones with C3-1 §4's errnos through the staged host loader); boot2.sh writes the L14 spec and an L5 store image;
oracle.sh compares t43rel's bytes in box memory with the host loader's image; README rows S3-43-1..7.

## 2026-10-26 — kbootset -12: the booted kernel's namelist; C3-5 v4; the shipping kit (cf49440..e84878e)

`kbootset namelist` writes /stand/unix, the booted kernel's namelist, as an ELF32 ET_EXEC whose symbols carry this boot's
addresses: kinfo v2 and v3 read, refusal on a layout mismatch against kinfo's bootdata (status 3 with the reason, the file
untouched), written as a new file renamed into place (a hard-linked 2.1_unix survives), run from mark-good on every boot and
from /etc/rc2.d/S02kbnamelist; status reports current, stale, missing or none. Verified against the kernels' own symbol
blocks at two binds on both lines; the k30 brel through unix.sym (`nlmake <etrel> 0 unix.sym`). C3-5 v4: module package
names (<name>-<line>, pkginst zeth30/zeth46, zrtg30/46, monsw30/46; the module's own version), package scripts use sh
builtins plus mv only. C2-4 v9: S02kbnamelist after S01MOUNTFSYS; §11 no copy step on the box. C3-3 §4: abi= required only
with arena=. C2-1 table fixed. Box kbootset 4a09a6dd. Kits rebuilt clean: KIT_REV=e84878e, PORT_REV=617c64e.

## 2026-10-26 — the booted kernel's namelist: C2-1 v3, C2-3 v6, 40 §4.2, C2-4 v9 §12; C3-6 v3; kit names (d9558a6..41a382d)

The stock netstat, ifconfig and crash nlist /stand/unix, which on a 1.1 disk is a hard link to the stock 2.1 kernel. C2-1 v3:
kinfo carries the loader's bootdata block at 536 (40 bytes, bootinfo 0x650–0x677 verbatim), the module count moves to 576 and
the list to 580 (length ≤ 1604); flag 0x8 when bootdata's text vaddr differs from stext; readers accept v2 and v3. C2-3 v6: a
brel ships /stand/k30/unix.sym (ELF32 .symtab/.strtab, values bound at 0) with a sidecar `sym=` line. 40 §4.2 / C2-4 v9 §12:
`kbootset namelist` writes an ELF32 ET_EXEC namelist (symbols at bind + layout offset) as a new file renamed onto /stand/unix
when the content differs; mark-good writes it on every boot and an early rc2 call too; retry writes none (the root is not yet
repaired); the installer removes the stock /stand/unix and /unix and installs the rc2 call. C3-6 v3: _unload always exists and
runs on a failed load. Kit: every name within 14 bytes (abi.txt, docs/guide.md, C3-n.md), mkkit refuses longer; PORT_REV on
k46; the S3-22 row fixed (/usr/dlm/kit/<line>/, version scheme, extra/development, host-side container). kit-test 50/50.

## 2026-10-26 — core patches 0021–0022; the audit's non-kernel follow-ups (0481f30..2168509)

Patch 0022: a driver loaded at boot or by modload registers its own registry majors at install (dlm_sreg for d_str,
dlm_creg otherwise) — the first module boot's error 22; a demand-class STREAMS driver gets a console refusal (error 168).
The harness now builds dlm_str.c and dlm_ddi.c with host stand-ins and covers the boot-class character and STREAMS drivers,
the demand STREAMS refusal, the ifstats backstop with the module's link first/middle/last after a failed _load and a
forgetful _unload, and "_load attached but the linkage failed". Patch 0021: harness cases for the audit's untested branches.
Kit: modcheck checks drv_cmajor and COMMONs. make test checks libmod.c's syscall numbers against the core. Records: U16,
M-ABI2 with the block, M-CORE1 through 0021. Harness 191/191 both kernels; make core 124/124.

## 2026-10-26 — the final cut's base: kbootset gate 6 ET_REL bss; make core guards (6b2d669, f5ce731)

kbootset's memory gate counts an ET_REL kernel's bss (its NOBITS sections and COMMONs, aligned as rel.c lays them out) as
well as a brel's bss= (the re-cut KD060-Z: 284 172 B). make core fails when an allowlisted name has no provider and checks
core/plat's warnings; make test checks core/upstream/ against core/upstream.sha256 (48 files). core/series 0001–0020 as at
314c2aa. make core 124/124; 665 host checks. Box kbootset 013fe25f (-11), modadmin a206874d (modtools); KIT_REV=f5ce731.

## 2026-10-26 — core patch 0020: registration backstop; C3-1 §4 refusals (314c2aa)

After every _unload and after a failed _load, any interrupt handler, network interface or console hook still pointing into the
module is removed and named on the console. A section type outside the list and an image over the limit are ENOLOAD; each
refusal prints one line naming the module and the rule; parameter defaults must be in C3-1 §3's forms; .moddata word 0 must
be a single R_68K_32 with addend 0. The real modules are unaffected. Harness 175/175 both kernels; make core 123/123; 665 host
checks. Audit items §1.3 and §1.5 — the audit's kernel items are complete.

## 2026-10-26 — core patch 0019: code pointers in kernel text or the image; registry majors (dafa9c0)

A switch entry or STREAMS routine must be 0, kernel text [stext, etext) or the module's own image (kernel data and the arena
refused); a qinit's module_info and module_stat must be in the image; every character major a module registers or installs
at must be registered to it in the major registry (ECONFIG; a row held by another module is ECONFIG, C3-1 §4). The real
modules are unaffected (own-image routines, majors 51/49/52 registered to their names). Harness 169/169 both kernels; make
core 119/119; 665 host checks. Audit items §1.2 and §1.4.

## 2026-10-26 — core patch 0018: development load as C3-4 says; paths under /stand/gen (b633b3a)

With no booted manifest nothing loads, even under development load; under development load a manifest member loads from
its path= without the SHA-256 check and says so on the console; a member whose path= is not /stand/gen/<booted id>/mod/<name>
is refused. The state harness boots an empty generation at startup instead of relying on the removed behaviour. Harness
166/166 both kernels; make core 119/119; 665 host checks. Audit items §1.1 and §1.6.

## 2026-10-26 — stage-3 audit of the rows reported done; 30 §3 root-class context (f98c1ac, 4fea711)

Audit (docs/plan/stage-3-audit-2026-10-26.md): of 14 rows reported done, 7 are done (S3-01, 02, 04, 08, 09, 11, 15) and
7 half (S3-03 errnos/console lines/param forms; S3-05 drv_cmajor unchecked; S3-06 range checks not implemented, registrations
untracked; S3-07 devload vs C3-4; S3-10 no sample driver; S3-16 gate 6 misses ET_REL bss; S3-40 records). Seven kernel fixes
proposed for the final cut (patches 0018–0020). 30 §3: the sysinit path is boot class only; root-class modules load from the
arena in marc_root (no file I/O, floor init_tbl rules), U1 measures that context before stage 4 relies on it.

## 2026-10-26 — core patch 0017: boot-class modules load from the first sysinit entry (cf762a3..bcd6f0d)

S3-B5's panic (N50): the kernel's hook after vfs_mountroot read the module file in process 0 at IPL 7, where the file system
cannot bring a page in — U15's question, answered. Boot-class modules now load from /etc/inittab's first sysinit line via
`modadmin -B` (modadm MOD_C_POST, root only, once a boot; a second call is EBUSY); the hook loads nothing while interrupts
are masked and says so. C3-5 v3, spec 30 §3, U15 in 90, brief step 8, C2-4 §11. Harness 162/162 both kernels; 665 host
checks; box modadmin a206874d. The media need /sbin/modadmin and `dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1`.

## 2026-10-26 — core patch 0016: pin by default (31e5676)

The module core pins modules by default, as C3-1 §2 says: a module that does not declare unload=allowed is refused by
moduload with EBUSY (moduload(0) leaves it) and modstat reports it locked. Before this the key was parsed but not enforced,
so any idle module could be unloaded — S3-06 had been counted done with only its range-check half in place. State harness
160/160 both kernels; make core 119/119; 665 host checks. Not in the kernels re-cut on e86c9c4.

## 2026-10-26 — k46.1.0 fingerprint rewritten from the re-cut; abi= required at gate 2; C3-3 v4 (3ee2fe4, a28d5ab)

k46.1.0's reference is rewritten once from the re-cut KD060-Z: cputype's size went 0 → 4 and nothing else moved; it now
equals k30's (abi=7a90c7d9…). kbootset refuses a module kernel whose sidecar has no abi= (gate 2); s3-standin.sh requires
the key. C3-3 v4: abi= required, the k46.1.0 reference closed, equal fingerprints across lines expected (the kabi tag tells
the lines apart). Both re-cut kernels compose through the new gate. 665 host checks; make core 119/119; KIT_REV=a28d5ab.
Box kbootset 45909ae5.

## 2026-10-26 — modadmin for the box (S3-11); C2-4 version 8 (55722ef, cdf29fd)

The core's modadmin built with GCC 14, static like kbootset, its six system calls through the stock syscall(); core patch
0015 adds -k (a symbol's address: the kernel's exported names, then each loaded module's globals), -a (the symbol at an
address) and -p/-w (read or write longs at a symbol through /dev/kmem), so a module's tunables and counters are reached by
name. Box modadmin d94e5228 (68060-safe). C2-4 v8: module members in build, commit, media -R and status. New bench row S3-B6.

## 2026-10-26 — kbootset media composes the installed modules; kit LOCALIZE check (a64aee1, d6985be)

`kbootset media` (disk, floppy pair, CD) composes the installed module packages into the medium's pristine generation as
`build` does (gates 1–3, the parameters), writes the module and param records into the spec and copies the objects to the
root tree's /stand/gen/1/mod/ — S3-31's input. The kit's make fragment refuses LOCALIZE up front when its objcopy is missing,
naming the tool and the gcc14-cross-amix path. 665 host checks; kit-test 35/35; box kbootset 305345a3; KIT_REV=d6985be.

## 2026-10-26 — the kernel fingerprint abi= (C3-3 version 3) (9a45f1b, bd65e6b)

The text: sorted lines `data <name> <st_size>` for each DDI data name plus `offs <NAME> <value>` from the probe's dlm_offs.h;
abi= is its SHA-256, in the sidecar only. tools/mkabi.py checks a kernel against abi/<line>/abi-<kabi>.txt, naming what moved
and the tag change it needs (brief step 9; it writes the sidecar's abi= at step 11). References from the cut kernels: k46.1.0
04b52092…, k30.1.0 7a90c7d9… (10 data lines, 19 offsets). The kit ships mkabi.py, the reference, the probe and mkoffs;
kbootset refuses a malformed abi= at gate 2. make core 119/119, kit-test 33/33, 665 host checks. KIT_REV=bd65e6b.

## 2026-10-26 — kbootset composes module members (S3-16); bench row S3-B5 (a71a875, 2410287)

`build` takes every module object under /etc/conf/mod.d (unless modreg disables it) through gates 1–3 (record; kabi
family/major/minor, compiler pin, core-tier build, parameters normalized to C3-1 §3; match= on boot class, registered
majors= on demand class, depend closure, no root class), copies them to /stand/gen/<id>/mod/ and writes module and param
records in depend order; `commit` re-verifies; `status` marks members loaded or not from kinfo. 665 host checks; host
rehearsal with the real z3660eth members on both cut kernels. S3-B5 = the first module generation (z3660eth alone),
tests/bench/s3-modpkg.sh. Box kbootset 8cb4c157. Owed: media builds composing modules (S3-31's pristine generation).

## 2026-10-26 — kit: per-line MODOUT and objects, COMMON warning by prefix, clean guard (d197198)

A build's objects and module live under build/<line> and rebuild when the kit changes, so one module directory builds for
both kits; the COMMON warning names only symbols outside the module's own names; clean refuses MODOUT=.; modcheck names a
missing scan060/objdump in one line. C3-6 §2: z3660eth's _load may return ENOMEM, if_detach only with an _unload. kit-test
31/31; kits rebuilt, KIT_REV=d197198.

## 2026-10-26 — kernel printf formats %d %x %s only; kit fixes (2c62201, c722e41)

The module core prints only the formats the 1992 kernel printf has: the arena line reads "modules from generation N's manifest"
again (patch 0009 %ld → %d with a cast; patch 0006 %c → %s). tools/prfcheck.py in make test and make core refuses any other
conversion in kernel-side code; make core 115/115. Kit: a Master without $cpu gets the line's default (DEFCPU, MODCPU
override); a kit built from uncommitted inputs labels itself -dirty; the guide covers DEPS and the modfix message,
LOCALIZE_OBJCOPY, the "amiga/console/…" include form and where the %.o rule looks. Kits rebuilt: KIT_REV=c722e41.

## 2026-10-26 — the ABI kit (S3-10) (8c9172d, 418ead5)

`make kit` builds a kit per line: the module core's headers, sys/amixddi.h (DDI v1; the stock sysroot already has a sys/ddi.h
with the same guard), the stock headers from the pinned sysroot (k46 with the port's 4 KiB immu.h/param.h), a linkable stock
Sun font built at kit time by tools/sunfont.py (font bytes in .data, not .text), mkmod (core patch 0014), modfix, modcheck.py,
mk/module.mk, sample/hello, ddi.md and writing-a-module.md. modcheck scans a PROGBITS copy (binutils 2.8.1 cannot read a
type-13 .moddata) and fails an empty scan; DDI_CPUTYPE reads cputype as the long it is. `make kit-test` 29/29, the sample
loads against both module kernels' symbol blocks. Nothing stock is tracked. Owed: the probe module and the abi= fingerprint.

## 2026-10-26 — C3-6 v2 takes z3660eth's findings; C3-1/C3-5 v2 param value forms; 10 §7.2 L9; 40 gate 5 (609ccc7, ce94b5c)

C3-6: the STREAMS row is zeros except d_str; z3660eth_int6/int2 are the handlers, attached at first open after the software
EXTER self-test (INTREQ 0xa000); param intrl2; ZZ_CONFIG_DISABLE acknowledges and masks; the kit's k46 immu.h/param.h are the
port's 4 KiB forms. C3-1/C3-5 v2: every param value is normalized (bool exactly 0 or 1; kbootset accepts 0/1, yes/no,
true/false, on/off and refuses the rest at gate 2 — lands with S3-16). Spec 10 §7.2: a trial refused before it starts (L9,
like L1/L2/L3/L6/L14) spends its attempt. Spec 40 gate 5: a 4 MiB store holds a module generation only beside a deflated
generation 1. Bench rows: RECNAME in s3-standin.sh, arena line before the symbol count, the rc2 hook's line is the one of
record, S3-B4 checked through kinfo offset 84.

## 2026-10-26 — C3-6 version 2: the console hook's cp is the console (3d809d7)

A hook takes only writes where cp->screen == displayedscreen (C3-2's row and patch 0011's comment say the same); _halt is
void; z3660rtg's _unload calls monsw_unregister, the module is built without ZZ9K_NO_BUILTINFONT with builtinfont made local,
ENABLE equals REDIRECT and the hook takes VT writes by design, params blit:bool:1 and maxarea:int; a weak undefined symbol is
allowed (§1.6).

## 2026-10-26 — C3-6: what a driver changes to become a module (e511cdf..4834304)

C3-6 agreed, version 1: the wrapper and _load/_unload/_halt; majors from .moddata; intr_attach with polled as the default and
the level-6 rule (no spl masks level 6, so a level-6 handler acknowledges, masks and flags, and calls no DDI function; the
work runs at level 4 or below); cons_hook_set; device windows without a DMA interface; allowlisted symbols only; the kit.
Checklists for z3660eth (boot, unload=never, if_attach, param intr), z3660rtg (demand, depend=monsw, cons_hook with the
displayedscreen check, one module with a run-time probe, unload=allowed) and monsw (demand, unload=never, param config).
Brief step 8 names KINFO_DLM. Plan rows S3-25/S3-26 follow DDI v1 without dma_*.

## 2026-10-26 — C3-3 v2; brief and C2-1 take the cut findings; stage-3 boot rows (7ee4c59..edd9599)

C3-3 version 2: a stage-3 module kernel writes root=/rootfs=, and the first root-class module in a generation is the stage-4
trigger for gate 3. The kernel brief takes the S3-20/S3-21 findings: post-link steps after the last size-changing step,
RTH1_DLM, the splice derived from the core's own definitions, the layout rule (.text, .rodata, .data, no padding), addresses
only from nm. C2-1 caps the module list at 32 and says when it is fresh. 40's gate 5 notes the module kernel's store size
(4 MiB holds one static plus one module generation). New bench rows S3-B1–B4 and tests/bench/s3-standin.sh, rehearsed on the
host with both cut kernels bound by the loader's relocator at two addresses.

## 2026-10-26 — Loader version 2; kbootset sidecar v5 (9febccf..124b86c)

boot2 checks a module kernel's identity record (AXK1) against the manifest (L14 on a mismatch) and fills the arena's AXA1
directory and manifest copy; L5 gives the bytes needed and available. The "amix-boot: " prefix is printed in one place
(con_say), saving 308 B: image 27020 + table 1080, bss 1380, 272 B under the 28 KiB gate. b2check 538 relocations at two
binds. kbootset reads sidecar v5 (ident=; arena=/ident=/loader-min=2 together), writes the manifest's arena and ident records,
gate 4 checks the manifest copy fits the arena; loader version 2 is the default of kbootset and mkstore (store.h). 665 host
checks. Spec change after freeze: 10 gains the ident record and L14 (C3-3).

## 2026-10-26 — §1 of the kernel brief complete: core/plat, mkident, patch 0013, M-REG1 fix, dry-run answers (771fe15..db0abef)

core/plat (amiga.c: AXL1 safe/devload, build id, board matcher; per-line line.c: k46 buildid, k30 kinfo_buildid and cputype),
host-tested. tools/mkident.py (AXK1 and the arena: --asm/--fill/--check). Core patch 0013: 4-byte symbol block, strong hooksw,
no weak plat_dmainit default, dlm_kinfo_list() for kinfo's module list. M-REG1 counts a cdevsw row filled at boot (major 51 is
z3660eth's at run time on the static Z families; record corrected). The gate rehearses the brief's whole step 7 on both
kernels: nothing stubbed, no weak symbol, 12/12 at both binds; `make core` 114/114. The brief answers the port's dry run
(§3a): 4-byte alignment, .rodata fold, chain order, kinfo kabi and module list.

## 2026-10-26 — DDI v1 decisions applied; module core patch 0012: intr_attach (2cb274e, 1257dd9)

DDI v1 (C3-2, abi lists 80/78 names, review draft, brief): dma_alloc/free/prepare/complete removed (stage-4 design with the
port; the port's dma_prepare/complete stay kernel-internal); displayedscreen added (data, read-only); spl5–7 raise to level 4
only, so no spl masks level 6 and an INT6 driver masks at its board. Patch 0012: intr_attach/intr_detach — a level-2 chain
walk in int2_tbl's last handler slot calls the displaced handler first; a level-6 chain sits behind a wrapper at the stock
aciabintr (weakened, __amix_aciabintr; p6int is its only caller); every handler is called every time, claims counted; chains
change at IPL 7. Harness 154/154; gate 12/12 with intr_* linked for real.

## 2026-10-26 — module core patch 0011: the DDI providers spl, if_attach, cons_hook; C3-5 agreed (887981b..cde866e)

spl0–7/splx as functions identical to <sys/inline.h> (spl5–7 raise to level 4 under FAST_INTERRUPTS, so no spl masks INT6);
if_attach/if_detach on the stock ifstats list at IPL 7; cons_hook_set/clear through a wrapper at the stock scrcon_put (both
VT writes and the printf funnel), which the kernel build weakens and keeps as __amix_scrcon_put. With these linked for real
the ksym gate is 12/12 on both kernels. C3-5 agreed, version 1. Kernel brief: the scrcon_put splice, libgcc.a and
devkvmap040.o on k46, cputype from core/plat on k30.

## 2026-10-26 — module core patch 0010: marc_post; contract C3-5; the S3-20/S3-21 kernel brief (1038d5f..23d0bc1)

dlm_marc_post() registers the demand-class majors from the booted manifest, then loads the boot-class records in manifest
order unless match= names no board here (the platform's matcher), one console line each; in safe mode nothing loads and every
other load is refused; a member's param records reach its _load as one string. Contract C3-5, the module package and the
manifest's module record (agreed on the report: match=/majors=/depend=/tier=+build= copied verbatim from .moddata, gate 3
refusals, no GMF1 or loader-min change, order and reporting through kinfo). docs/plan/stage-3-kernel-brief.md: the 11 build
steps, the providers per kernel and the acceptance for the first module kernels. Harness 146/146 both lines.

## 2026-10-26 — module core patch 0009: manifest-only loading and development load (9d1528b)

Every load (modload, dependency, dlm_loadname, first open) resolves a module only as a member of the manifest the loader
booted: the bytes come from its path=, read once, checked against its sha256=, and that copy is what loads; anything else is
EPERM with a console line. The manifest is the loader's verbatim copy in the arena, found through AXK1 and checked at dmainit
(C3-4); with no valid arena no module loads that boot. The development-load flag (from AXL1) lets an off-manifest module load
and says so each time. New dlm_arena.c; sha256.o and crc32.o from loader/common in the core. 104/104, harness 140/140.

## 2026-10-26 — module core patches 0006–0008: major registry, fmodsw kept whole, measured layouts (27b471e..95657b0)

DDI v1 review draft gains the module-interface row (as C3-2; still unsent). Patch 0006: a module's majors= must be registered
to it (abi/registry/majors: c 49 z3660rtg, c 51 z3660eth, c 52 monsw, c 53 kinfo, b 20 ramdisk; tools/mkreg; ECONFIG
otherwise). Patch 0007: fmodsw keeps every stock row, never truncates (more than the table holds panics at dmainit; not
host-testable, read-verified). Patch 0008: the structure layouts the core reads are measured by the kernel's compiler from the
kernel's headers (dlmoffs.c, tools/mkoffs); all 19 equal upstream's values on the 2.1 sysroot. `make core` 104/104, harness
129/129, both lines.

## 2026-10-26 — module core patch 0005: the allowlisted symbol block (C3-2); DDI v1 lists; the gate (a0fb839, f7b5596)

Kernel symbol block version 2, generated before the final link from the allowlist (mkksym -a) with the values as relocations
bound by the loader; mkksym -f fills sizes; st_other is the tier, core-tier names resolve only for core-tier modules;
dlm_init checks the block against dlm_ksym_space. abi/k46 and abi/k30 ddi.list (DDI v1: 83 / 79 names) and core.list.
tools/ksymgate.py binds the kernel twice with the loader's own relocator and checks every name (12/12 both binds).
C3-2 correction: the module interface (mod_*ops, mod_hold, mod_rele; provider the core) belongs to DDI v1. `make core`
103/103 both lines; dlm.o data 165 KB → 1.9 KB.

## 2026-10-26 — module core patches 0002–0004: platform split, .moddata v2 (C3-1), ENOLOAD (58b42fb..dbc3d74)

Patch 0002 takes ashnazag's guest registrations out of dlm_init (30 §2 patch 1); plat_dmainit is the platform's place.
Patch 0003 brings .moddata version 2 and wrapper revision 2: every C3-1 key checked, the module checked against the kernel
(name, kabi family/major/minor, compiler pin, core-tier build id), root class refused until the arena path; mkmod writes v2,
modfix checks it; dlmconf.c takes DLM_KABI/DLM_PIN from the kernel build. Patch 0004: non-module files are refused with
ENOLOAD (C3-1 §4). M-CORE1 87/87 on both lines; state harness 124/124; dlm.o text 28 268 B.

## 2026-10-26 — stage 3 begins: the module core imported, patch 0001, M-CORE1 (becf104..9626629)

core/: kdedon's MIT DLM core (ashnazag kernel/dlm at b736c59) imported unmodified with upstream's LICENSE, the base of the
patch queue; patch 0001 makes the trampolines' hold volatile across longjmp (GCC 15 -O kept it in a register; GCC 2.7.2.3 did
not). M-CORE1 closed on both lines: `make core` runs upstream's host tests on our toolchains against KD060-Z and K030-U, 87
checks pass (mkmod 4/4, oracle 7/7 byte-identical, error paths 29/29, state harness 105/105 per kernel).

## 2026-10-26 — stage 2's exit met on the emulator; C2-4 v7: commit no-op and `commit --again` (db91add..f43fe08)

S2-46 passes on k30 (row N45, the installer's v10 disk): stage 2's exit gate is met on the emulator on both lines; the metal
rows S1-26, S1-27 and S2-47 stay open for the owner's bench time. kbootset commit writes nothing when the built generation
equals the default (compared through the loader's parser: members by size and SHA-256, the facts, the parameters) and says
"the default generation M already has these members; nothing to commit"; `commit --again` commits it all the same (a repair,
a row). C2-4 version 7; apkg needs no change. Bench recipes use `commit --again` where a row needs an equal generation.
Box kbootset a2970b2000e6c505.

## 2026-10-26 — M-GEN5 closed on both lines; M-GEN3 N=7 on k30; ledger k30 cells (44f7c49, f486028)

k30 row N43: the unit-5 trial panics at mountroot (errno 30 = EROFS, the last vfssw row's errno; k46 reports 89) and L8 falls
back to the pristine generation, end state exact. M-GEN3's N=7 cell passes on k30 (N44: the trial boots through the fsck
reboot, the rc2 hook marks it good). Ledger: k30 lifecycle and power-cut cells; S2-46 k30 waits for the installer's v10 disk
(kbootset and loader-amix as packages); the `-f install` variant is supporting evidence only.

## 2026-10-26 — sha256.c reverted: the restructured round is slower on the 030 (fb77acd, 16f2bde)

Hashbench run 2 on the cycle-exact 25 MHz 68030: the restructured round ran at 237 KiB/s with GCC 2.7.2.3 (was 534) and 176
with GCC 14 -O2 (was 270); host instruction counts did not predict the 68030. Reverted to the shifting round; GCC 14's factor
of two on it stands as accepted cost; any later attempt is designed against the bench, hashbench per candidate first. The
no-kinfo fixes stay.

## 2026-10-26 — ledger k46 complete; SHA-256 restructured; kbootset without kinfo; C2-4 §9; k30 recipes (8b42bcc..6c69125)

Exit ledger: M-UPG1 k46 passed, the k46 column complete. Hashbench run 1: GCC 14's SHA-256 at half GCC 2.7.2.3's rate on
the 030 (codegen, not I/O). sha256.c restructured: the full schedule first, eight renamed rounds per pass, nothing shifted —
42–45 instructions per round instead of 102 under both compilers; correct against hashlib. kbootset without kinfo: retry
exits 0 quietly (C2-4 §7), mark-good refuses with status 3 and names --booted. C2-4 §9: the end-of-rc2 mark-good hook. Bench
recipes for the k30 line (S2-46, S2-41 with K030-IDE as the bad trial, one S2-42 cell); they need an l11-k30 disk whose
pristine kernel is kernel-k30-u. hashbench tool untouched; hashbench re-run pending.

## 2026-10-26 — C3-1..C3-4 agreed; S3-40 host half; DDI v1 for review (a1c7678..de519de)

C3-1..C3-4 agreed (version 1). S3-40 host half over the ten kernels of record: one k46 ABI for 68040 and 68060 (the two
kernels differ in one byte, OQ-20.2 closed), every registry value confirmed (sysent 142 with 64–69 free, cdevsw 70 rows,
majors 51 and 53 free everywhere), the switch tables movable (U5), elf2brel carries the symbol block (M-ABI2), arena
capacity 0x60000 on both lines (M-MOD1; a module kernel is 384 KiB larger raw, a 64 MiB store still holds ~28). 20 §2 gains
tier and build; major 53 confirmed free. docs/abi/ddi-v1-review.md: the stage-3 export list, self-contained, for the
collaborator's review.

## 2026-10-26 — M-GEN2 record; stage-3 answers; contract drafts C3-1..C3-4 (b5570bc..a71d221)

M-GEN2 bench half: a k30 commit 16.7 s (median; 11.2 s CPU) and check 16.0 s on the cycle-exact 25 MHz 68030; the GCC 14 box
binary hashes at about a third of the loader's C rate (cause unmeasured, queued). s2-standin.sh takes a brel's bss. 80 §2:
intr_attach is built in stage 3 and reused by stage 4 (spec change after freeze). Stage-3 plan: Q3-1/Q3-4 settled, monsw
planned in amix-z3660rtg until P-8 (c). Contract drafts for agreement: C3-1 module object and .moddata v2 (MD2), C3-2 the
allowlisted symbol block generated before the final link with loader-relocated addresses + DDI v1, C3-3 the AXK1 identity
record and sidecar v5 (loader code L14), C3-4 the AXA1 arena directory and manifest copy.

## 2026-10-26 — stage-3 plan: the module core (aca2460; ledger 737df5a, db58c28)

docs/plan/stage-3.md: work breakdown for the module core as a patch queue on kdedon's MIT core b736c59, the ABI kit, module
kernels with the arena and the allowlisted symbol block, the composer and loader side (AXA1 + the manifest copy),
z3660eth/z3660rtg/monsw as the first copied modules, the measurements, and interface drafts C3-1 to C3-6. Exit ledger: the
installer's citations; M-UPG1 k30 cites the upgbox first boot, k46 open.

## 2026-10-26 — stage-2 bench records and the exit ledger (deea18c..eb8f006)

S2-46 record: a box upgraded and rolled back with apkg alone (k46); the first run's journal failure kept as the finding
behind d64bad7. M-GEN5 closed on the bench for k46: a trial that cannot mount its root panics and reboots by itself and the
loader falls back to the good default (L8) on the same boot; recipe matched to the machine. M-GEN2 bench recipe (timed
commits per line). Stage-2 plan §4: the exit ledger — one line per 80 §2 emulator item with k46/k30 columns and the record
for each, including apkg's SHA-256 refusal row (altered byte and altered catalog hash both refused, rc 3, nothing written).

## 2026-10-26 — kbootset makes the journal's directories (S2-46); M-GEN5 recipe (cb82bff..d64bad7)

kbootset makes the journal's missing directories (0755) whenever it writes the journal, named with --journal (apkg's form)
or default — the exit row's trigger failed with "cannot write the journal" on a box that had never run kbootset (C2-4 §2
wording, no version bump). M-GEN5 recipe: `mark-bad 2` before the bad trial on a 4 MiB vehicle (collect frees nothing of
the kept set); spec change after freeze 40 §2.1: boot slices under the 64 MiB store boot but do not hold the kept set.

## 2026-10-26 — kbootset create zeroes and refuses; status prints the set id (C2-4 v6) (29e2c9f, 8ccee80)

`create` refuses a slice that already holds a boot store or a DOS bootblock (status 3) and with --force zeroes the first
64 KiB first, so nothing of an earlier chain survives; `media --disk` takes --force too. `status` prints `store-id: <8 hex>`
(the header's set id, as /etc/default/bootset records it) so the installer need not recompute it. 660 host checks.

## 2026-10-26 — kbootset retry: the fsck-repair reboot does not spend a trial (8f50dad..d5d4203; also 9632232, 42e9fb1, 4cae4f2)

M-GEN3 on the rig: every power-cut point (before steps 1, 2, 4, 5, 7) leaves a booting generation. Finding at the cut after
the commit point: the stock /sbin/bcheckrc always reboots after a root fsck repair, and that reboot spent the trial's single
try-once attempt. Fix (spec change after freeze 10 §7; C2-4 v5 §7): bcheckrc calls `kbootset retry` before each uadmin that
follows a root repair; if the booted generation is the trial on its attempt, the attempt is given back (at most twice per
trial, counted in the generation's flags), so a root that never stays clean still ends in L8 after three tries; retry writes
only the control block. Loader unchanged. Also: vehicles carry a brel's bss=; mkstore stores raw when deflate does not help;
make box checks for 040/060-only FPU forms; kbootset executes FPU instructions (FPE in the floor). 658 host checks.

## 2026-10-26 — a brel kernel's bss; contracts C2-3 v4, C2-2 v4; the exit row (84315bb..bf7f93f)

The brel format has no bss (elf2brel writes text+rodata+data and relocations only), so boot2's room check undercounted a
brel kernel by 270–345 KB. Fix: the manifest's kernel record carries bss= for a brel (spec change after freeze 10 §5.1);
boot2 adds it before the room check (512 KiB assumed with a printed line when absent); kbootset reads bss= from the sidecar,
refuses a brel without it (gate 2), counts it in gate 6 and writes it on the manifest. boot2's self-relocation table moved to
16-bit offsets (27 434 B, 1 238 B margin; b2check on the real boot2 at two bases in every make all). C2-3 v4: the kernel
build writes the sidecar for the form it ships (size/sha256 of that file, bss= from the ELF); C2-2 v4: the install record
file is /var/apkg/kpkg/<pkginst> (s5 14-char names). S2-46 exit row written with the S2-12 packages. 640 host checks.

## 2026-10-26 — /dev/kinfo: made by the installer, and by kbootset when missing (fb9c1ce..a96427d)

M-GEN3 power-cut rows in the rig's cut shape (holds before steps 1, 2, 4, 5, 7); kbootset creates /var/kbootset for its
default journal. C2-3 v3 §1: the kernel package does not carry /dev/kinfo (a device node is not a pure file); the installer
and the upgrade install make it (c 53 0, 0444, root:sys). C2-4 v4 §2: on the running box kbootset makes /dev/kinfo when it
is missing and says so; when it cannot, the facts come from /etc/default/bootset and the options. Box build uses mknod with
makedevice(53, 0).

## 2026-10-26 — stage-2 records and row recipes (64a9881, 47abc38)

M-GEN1 (stage 2): a static generation is 1.26–1.27 MB (k30 brel), 1.93–2.08 MB (k46 ET_REL) or 1.41–1.52 MB (k46 brel)
raw plus one manifest extent; a 64 MiB store holds ≥ 32, the 1.0 10 MiB slice five ET_REL k46 generations. M-GEN4: kbootset
one GCC 14 static binary for both lines, 119 388 B stripped. M-SIG2 bench half: SHA-256 540 KiB/s on the 25 MHz 030 model,
kbootset check of a k46 generation about 3.8 s. tests/bench/s2-standin.sh: a stand-in kernel package + apkg record until
S2-12. README "Stage 2": the M-GEN5 lifecycle row (seven boots), the M-GEN3 power-cut rows (hold at steps 1, 2, 4, 5, 7) and
the exit row (apkg upgrade → trigger → power-cycle → mark-good → rollback).

## 2026-10-26 — kbootset on the running box (S2-06); C2-4 v3 (efb7629, c7b7319)

Without --image/--dev kbootset reads /dev/kinfo (C2-1 v2, checked), finds the boot store (bootset's store= when the slice
still carries store-id=; else the loader record's boot device through kinfo's card table, the disk's RDB and the partition at
AXL1's start; else a scan of every disk for exactly one UNI\0 store), gate 9 (two UNI\0 slices on the boot disk) and gate 8
(no or several candidates), writes store=/store-id= back, takes the box facts from options, then kinfo, then bootset; the
journal defaults to <root>/var/kbootset/journal; mark-good defaults --booted to AXL1's generation. C2-4 v3: §2 the box
form, §6 /etc/default/bootset. tests/host/kbox.sh on a real RDB image with synthesized kinfo records, checked field by field
against the port's real record. 109 680 B text.

## 2026-10-26 — chip-only refusal; contracts C2-2/C2-4 v2; M-LD5 and M-LD8 closed (cba01a4..9b87bef)

boot2 never binds the kernel in chip memory: no fast region, or a kernel larger than the largest one, is L4 with a line
saying which; the control blocks move into the work area (spec change after freeze 10 §3.2). C2-2 v2: optional pkginst=
and offset=. C2-4 v2: bootset= read from <target>/etc/default/bootset (absent = auto, unknown = manual); the box form and
default journal pending S2-06. kbootset gate 1 ignores apkg's <name>.new temporaries and refuses a path named by two records
(apkg 0.3 review). M-LD5 bench half closed 24/24; M-LD8 closed: inflate 5.5/7.6 s from fast RAM, a deflated floppy reaches
the kernel prompt in 18 s against the LZW loader's 31 s. 629 host checks; boot2 28 164 B.

## 2026-10-26 — boot2 runs from fast memory; metal recipes (042a408..50bed35)

boot2's start-up stub copies image + relocation table into a MEMF_FAST block and relocates there; a chip-only machine runs
in place and says so once on serial. Device reads stay in the chip bounce buffer; members are read, inflated, checked and
relocated from fast code (M-LD8: chip-RAM execution cost 7× on inflate, 25× on CRC-32). Spec change after freeze 10 §3.2.
Vehicle scripts fix SOURCE_DATE_EPOCH so bench and metal run the same bytes; tests/bench/README.md "Metal" lists the
S1-26/S1-27 rows; m-ld1.sh adds the M-LD3 vehicle (only boot2 damaged → B3, stop). boot2 27 716 B (560 B under the gate).

## 2026-10-26 — kbootset check and media builds (S2-05, S2-04) (a3a6795, 25b8b60)

kbootset check re-reads every member in the store (inflated where deflated) against the manifest's CRC-32 and SHA-256,
the boot/demand files under the root, and the default generation against the installed kernel package; never writes,
exits 1 on a problem (C2-5's second reader). status notes a pending trial, the next-boot request and low free space.
kbootset media builds a new medium's pristine generation from the packages under -R with every gate run: --disk (raw,
own core), --floppy (pair, deflated) and --cd (tree, raw) through mkstore's engine compiled into the host kbootset, so
media and the test tool share one writer. mkstore writes sha256= on every member. Box binary has no media code.

## 2026-10-26 — kbootset build and the gates (S2-03); M-LD4 bench half (654a324, 831975e)

kbootset build composes the next generation into /stand/gen/<id>/ from the kernel package (C2-3 sidecar) and apkg's
records (C2-2), running gates 1 hash, 2 kabi/pin, 3 closure (a static kernel's built-in root controllers and filesystems
against the boot/root controllers and root fs), 6 memory, 7 loader version and 10 line; commit re-runs the gates on the
files as they are and refuses a stale build. Every refusal exits 4, names the gate and leaves the store byte-identical
(tests/host/kbuild.sh provokes each). Box build 103 004 B stripped. Gates 8/9 come with kinfo (S2-06); root-class modules
are stage 3. M-LD4 bench half closed: the loader's writes read back 12/12 on A3000 WD, Gayle, A4091 030 and 060.

## 2026-10-26 — kbootset box build with GCC 14 (S2-07); contracts agreed v1 (37ec6be..5eae3e6)

Contracts C2-1 to C2-5 agreed (version 1, settlements recorded). Spec change after freeze: rollback reaches the pristine
generation when there is no older good one; OQ-40.5 closed by C2-5. `make box` builds kbootset for the box with GCC 14,
statically linked by hand (the driver's specs ignore -static), 70 496 B stripped, one binary for both lines, 68060-checked,
FPU-free on its paths, plus a C89 compile check on gcc-cross-amix. tests/bench/kbootset-smoke{,-host}.sh: the box/host
smoke run (identical stores and output prove the box binary computes what the host does). Emulator run pending.

## 2026-10-26 — kbootset host core and state machine; contracts C2-1..C2-5 (3afa802..3c159ba)

kbootset over any byte device (kbootset/ks.c): create, commit (pristine first, then trial), mark-good (also a loader on
trial), rollback (down to pristine), next, mark-bad, collect, loader-install; every write read back; the kept-set rule;
gate 5 (store space) writes nothing; journal recovery. Command line (kbootset/kbootset.c) on images and raw slices, exit
codes 0–4, commit step markers and KBOOTSET_HOLD for power-cut rows (every single or torn write survives: the store still
boots by the loader's own rules). The control block records the last generation id issued (spec change 10 §4.2).
docs/contracts/: C2-1 kinfo record, C2-2 kpkg catalog block and install record, C2-3 kernel/loader package layout and kabi
sidecar, C2-4 kbootset as a called program, C2-5 checksum contract v2 — agreed by the orchestrator 2026-10-25 evening.
624 host checks. boot2 27 540 B.

## 2026-10-26 — table-driven inflate; raw where there is room; no SHA-256 in the loader (cd56b88, eaba2d1)

M-LD7 bench half closed: the loader checks CRC-32 only (SHA-256 costs 2.3–3.75 s per kernel on a 25 MHz 68030). M-LD8:
the bit-at-a-time inflate (45–53 KiB/s on the 030, ~290 instructions per literal) is replaced by a table-driven decoder
(9-bit lookup, ~35 instructions per literal; 3.0× on the host, estimated 6–10× on the 030; 3 000 zlib streams and both 1.0
floppy kernels inflate identical). axtime-chip times code in chip RAM as boot2 runs. Spec changes after freeze: 10 §5.1 no
SHA-256 in the loader; 10 §5.5 and 40 §3.2 members raw in disk stores and on the CD, deflated only where a generation must
fit (floppy pair, netinstall); 10 §4.4 the ROM CD filesystem facts; 80 §7 the media-track rows gate the media, not stage 2.
boot2 27 528 B (752 B under the gate).

## 2026-10-25 — L11 disk change fixed; reproducible stores; stage-2 plan (c0c8f93..62a6b66)

boot2's L11 volume change waits for trackdisk's change counter (or a key), clears the track buffer before re-reading, keeps
the motor off while waiting and says each refusal once per disk change (rig rows N25b/N26b: the old code re-read the cached
track of volume 1 three times a second). mkstore honours SOURCE_DATE_EPOCH (byte-identical rebuilds) and writes
BOOT/amix-cdboot mode 0755. docs/plan/stage-2.md: the work breakdown for lifecycle and rollback on static kernels, with the
five cross-repo interfaces C2-1..C2-5. boot2 26 788 B.

## 2026-10-25 — axtime and the bench inputs for M-LD4/M-LD5 (656d155, 72c9fc4)

SHA-256 in loader/common (FIPS 180-4 vectors; not linked into boot2). axtime, an AmigaDOS tool, times the loader's
CRC-32, SHA-256 and inflate with the E-clock (M-LD7/M-LD8 via tools/measure/m-ld7.sh). mkstore -T (loader trial) and -n
(one-shot request); lsstore shows tally and attempts; axsim replays the loader's write rules over boots. tests/bench/ holds
the row builders, schedules and expected results for M-LD4, M-LD5 and the DF0 pair (S1-21, S1-22, S1-27). The AmigaDOS
entry stub adstart.s is shared by amix-cdboot and axtime. 518 host checks; boot2 unchanged.

## 2026-10-25 — amix-cdboot (S1-C2) and the floppy pair (S1-24) (42476b7..12c70f5)

boot2 split into a shared core plus media (store, CD). amix-cdboot: boot2 as an AmigaDOS load file (b2link -h) reading
/BOOT/K30|K46 through dos.library; manifest file= members; mkstore -C / lsstore -C write and verify the CD tree. Floppy
pairs: an extent may continue on the next volume and the manifest sits ahead of its members, so a pair boots with one disk
change (the deflated miniroot is larger than one volume); M-FP1 (static) and M-NET1d closed: k30 fits with 14.8 %, k46
with 11.8 % (trimmed engine). Spec changes after freeze: 10 §4.3 and §4.4. 313 host checks; boot2 26 556 B. The bench rows
N19–N26 need a re-run on this boot2 before stage exit.

## 2026-10-25 — S1-19 defects: AGA display state at hand-off, boot device name (301b836, 3b404c7)

boot2 restores the display state the 1992 console expects before it starts the kernel: a null copper list and FMODE,
BPLCON3, BPLCON4 at their power-on values (the AGA console garbling on rig row N21: the stock console programs only
OCS/ECS registers and the loader's Intuition screen had left AGA fetch modes behind). The loader banner prints the boot
device's name instead of an io_Unit pointer and the loader record's unit is the real unit. mkstore gains -c serial|screen|both
and -m <tenths>. boot2 26 008 B. Confirmation run on the rig pending.

## 2026-10-25 — spec changes after freeze for D-3 §10–13 (0acd5c6..5d2bcd6)

§10 the CD boots boot2 as an AmigaDOS program (amix-cdboot; manifest file= members; needs a boot ROM with a CD filesystem);
§11 one compacted disk numbering on both lines; §12 deviation DV-1 approved (below 5 % margin → form B); §13 signing out of 1.1:
60 rewritten as integrity, signing and publishing (1.1 = per-package hash; an optional #ksig catalog line, an apkg verify step
recording "unverified", a verified= field and a future require-signature policy keep the hook). boot2's development-load message
matches the spec (boot2 25 852 B). Fact recorded: today's catalog carries MD5 + size; SHA-256 entries are new in apkg 0.3.

## 2026-10-25 — boot1 stops on failure (3081ee1)

boot1 stops with a message on the serial port instead of returning failure to the strap: on the Z3660 boot ROM chain a
failure return raised AN_BootError and reset the machine about every 14 s, and a reset loop can leave a real 68060 dead until
a power cycle (M-LD3 bench half, from the S1-16 run). Spec change after freeze: 10 §3.1 step 6, failure rows B1/B3, the menu's
r key; OQ-10.1 narrowed to the other boot ROMs. boot1 884 of 1008 bytes. Also d1782bd: assembler comments no longer read as
line markers (binaries unchanged).

## 2026-10-25 — loader stage 1, items S1-07..S1-15 (c4893cf..fd64097)

Raw deflate decoder; generation selection (try-once, one-shot requests, fallback order); kernel relocator for ET_REL, brel and
ET_EXEC with the stock binding rules, bounds-checked; bootinfo, RTH1/RTO1 and AXL1 builders; boot2 linked at 0 and
self-relocating (b2link); boot2 itself (CPU probe, store reads through a chip bounce buffer, manifest, inflate, relocation,
bootinfo with the RTH1 boot-node walk, 68030 and 68040/060 hand-off); menu with rollback key, safe-mode and development-load
toggles, screen and serial console, keyboard, mouse and serial input; multi-volume floppy stores; mkstore stores members
deflated and builds packed floppy pairs. boot2 25 824 B + 2 336 bss of 28 672. 308 host checks; the real 1.0 floppy kernels
inflate byte-identical; the relocator matches kerntools' elf2brel on three real kernels. Nothing has run on an Amiga yet.

## 2026-10-25 — stage 1 plan and the first loader code (f4081f5..b029dbe)

Stage 1 plan (docs/plan/stage-1.md: 28 items plus 3 that wait for the CD fork, each with owner repo, evidence class, what
it blocks and an estimate). Toolchain pin with a presence check (gcc-cross-amix 8949028: GCC 2.7.2.3, binutils 2.8.1);
shared C89 store-format, CRC-32 and GMF1 manifest code with 94 host checks; boot1 in position-independent assembly,
784 of 1008 bytes, under a build gate on size and relocations, framed so the stock 1992 bootblock also passes the gate;
mkstore/lsstore host tools with a store round-trip test. Spec change after freeze: boot1 reports failures on the serial
port only (screen output needs graphics.library, which does not fit in 1 KB). boot1 not yet run on any Amiga (S1-19).

## 2026-10-25 — M-NET1a/b measured; S0 frozen (4d9c5e6..2506516)

Netinstall miniroot (installer + network userland + HTTP apkg): 2 562 866 B (k30) / 2 468 595 B (k46) raw, 959 940 B /
924 595 B deflated with the unused engine tools dropped; with a deflated kernel a floppy pair keeps 16.1 % / 13.0 % margin,
so netinstall form A (floppy pair) is chosen. Record in docs/measurements/, script tools/measure/m-net1.py. S0 freeze
condition met; the specification is frozen at this commit (orchestrator, 2026-10-25).

## 2026-10-25 — S0 revised after review T-52 (f4d1b1f..026215c)

CD boot written as two options for the owner (RDB-style disc, or a loader started from the disc's AmigaDOS startup);
boot1 counts loader-trial attempts in a tally block; the loader record gains root and swap selectors (RAM-disk root on
block major 20, replacing stock ram.c); the kernel loads only modules of the booted manifest, a development override is
printed at boot; the core tier exports bdevsw/vfssw/nfstype; Z3660 keys corrected to 144b:01; four-card minor encoding and
the drivers to rebuild listed, board sets of record and the card-number gate defined; our line rebuilds the 040/060 base
without ufs/s5; the ABI kit publishes the stock headers (built from the pinned sysroot, never tracked); S0 freezes on
M-NET1a/b, deviation DV-1 recorded.

## 2026-10-25 — bootstrap and the S0 specification (ce351f8..5cd25a7)

Repository bootstrapped (MIT licence, README, docs layout). S0 specification for Amix 1.1 loadable kernel modules in
docs/spec/: our own boot loader (boot1/boot2, boot store, ISO9660, generation manifest, module arena, menu, rollback,
safe mode, try-once), .moddata v2 and the kabi rule with the pinned kernel-space toolchain, the ashnazag DLM core as a
patch queue, the four-controller sd contract, filesystems as modules, generations and kbootset, the 1.1 disk layout and
the upgrade install, media (disk/SD, floppy pair on both lines, bootable CD, netinstall, tape, emulation), signing, the
static floor, the proof stages and the measurement list.
