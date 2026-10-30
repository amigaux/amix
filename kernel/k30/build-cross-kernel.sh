#!/bin/bash
#
# build-cross-kernel.sh -- HOST-SIDE cross-link of a 68030 Amix kernel.
#
# Proves (or disproves) that an Amix kernel can be relinked ENTIRELY on the host
# cross toolchain (m68k-cbm-sysv4, GNU ld 2.8.1 / gcc 2.7.2.3) into a candidate
# `unix` ELF whose relocations the Amix boot loader (amiga/boot/rel.c ET_REL path)
# will accept -- WITHOUT ever touching an Amix box.  It reconstructs the top-level
#     ld -r -o unix $(OBJS) amiga/config/unix.o
# link exactly as usr/sys/Makefile does, then leaves the ELF for tools/relsim.py to
# judge (loader accepts only R_68K_32 with every section bound).
#
# It then runs tools/elf2brel.py (a faithful port of amiga/boot/elf2brel.c) to emit
# the BOOT-READY kernel `unix.brel` alongside `unix`.  The Amix boot floppy expects
# the kernel in brel form (ET_LOPROC / e_type=0xff00), not raw ET_REL: the on-box
# amiga/boot/Makefile `floppy:` target is `./elf2brel < unix | compress | makeiblk`.
# A raw ET_REL kernel framed onto the floppy D245-Guru's during relocation because
# rel.c's compact-reloc (ET_LOPROC) path never runs for it.  Both artifacts are left
# under $WORK (relsim.py judges `unix`; the floppy is framed from `unix.brel`).
#
# This is a host cross-link, not a gated on-box build.  It does NOT gate and does NOT
# reach the box.  The kernel's config object (root/swap device numbers) is selected
# with --config (default fd0unix -- the install/boot-floppy config: rootdev = FD0P =
# makedevice(16,8) = 0x00400008, no dump device).  An on-box build (amix-build,
# tools/onbox-build.sh) links with the box's native toolchain and goes through the
# on-box clean-gate (tools/build-clean-*.sh) instead.
#
# HOW THE 15 SUBSYSTEM `exp` BLOBS ARE SOURCED (verified against the staged Makefiles):
#   * 11 are staged pre-built binary blobs, used AS-IS (no source ships):
#       ml io os vm exec disp ktli klm rpc des netinet
#   * amiga/exp  -- rebuilt: its six sub-exps (ml console alien driver floppy kernel)
#                   are relinked from staged .o EXCEPT the CHANGED objects in alien.
#   * amiga/alien/exp -- only the objects an on-box build force-rebuilds (sd.o plus
#                   the driver objects, e.g. "sd.o a4091.o z3660.o") are freshly CROSS-
#                   COMPILED: the regenerated sd.o + the new driver objects
#                   (a4091.o, z3660.o).  The UNCHANGED stock alien objects (ct dd
#                   a2090 a2091 a3091 sdpart physdsk scsi) reuse their staged native
#                   .o -- exactly as the box does (some, e.g. a2091.c, reference
#                   Amiga exec headers absent from the cross sysroot anyway).
#   * fs/exp     -- rebuilt: pure ld -r relink of staged fs.exp + the fs sub-exps.
#   * master.d/exp, local/exp -- rebuilt: ld -r relink of their staged .o.
#   * amiga/config/unix.o -- freshly CROSS-COMPILED from amiga/config/$(CONFIG).c
#                   (--config, default fd0unix; compiled into the unix.o link slot).
# So the freshly-compiled code is the driver-carrying objects (sd.o + a4091.o +
# z3660.o) and unix.o; every other object is relinked from native-compiled staged
# .o.  That is what makes the relsim verdict meaningful: it measures whether the
# CROSS compiler's fresh relocations (and the cross ld -r) stay loader-legal.
#
# KERNEL-PATCHES (section 2b): TWO rules, covering two different questions.
#   * the GLOB -- each named driver may carry src/kernel-patches/*.patch, `patch -p0`
#     diffs against the stock /usr/sys tree (e.g. the a4091 driver enlarges the /dev/scsi
#     GSIO bounce buffer in amiga/alien/scsi.c).  These are the CONDITIONAL patches: a
#     driver in the build brings its own, including ones kernel-patches.conf excludes.
#   * kernel-patches.conf's `always:<repo>` rows -- the UNCONDITIONAL patches, which apply
#     to every kernel whether or not <repo> is on the command line (amiga/alien/a3091.c,
#     a2091.c and amiga/kernel/support.c: stock code no driver owns, linked into every
#     kernel, whose patches merely live in the a4091 driver because that is where the
#     work was done).  A glob-only build is blind to them and could ship a kernel without
#     a boot-critical patch and still gate green, so the two are reconciled via
#     tools/kpatch-lib.sh :: kpatch_always_extra, which refuses rather than guess when a
#     globbed copy differs or an `always:` patch is missing.
# Both sets are applied to the WORK copy only, gated
# by a `patch -p0 -F0 --dry-run` that aborts on any reject or fuzz.  Every patched object
# is then FRESHLY cross-compiled from the patched source (alien targets join the section-4
# FRESH_OBJ set; other subdirs' objects are recompiled in section 4b before their exp is
# relinked) so the linked kernel actually carries the patch -- the (subdir,object) pairs
# are derived from each patch's "+++ " target path, nothing is hardcoded.
#
# Usage:
#   ./build-cross-kernel.sh [--config <name>] [--net <net-driver-dir>] [--probe-sole <fn>] <scsi-driver-dir>...
#     --probe-sole <fn>   the driver.conf probe <fn> registers its board only when autocon found no
#                         card (sole controller = card 0); PATCH_DIRS="<repo> ..." adds patch sources
#     --no-scsi-drivers   no driver dir: scsicard[] is sd.c.in's stock rows only (the A3000 WD, A2090, A2091) --
#                         a module kernel whose Zorro/IDE controllers are all modules (kern30m -14). Refused
#                         with a driver dir; without it, a build with none is refused as before
#     --object-absent "<obj> ..."  with --object-baseline: the baseline objects this build does not make,
#                         EXACTLY these (the dropped drivers' amiga/alien objects)
#     --no-fstypes        no in-kernel filesystem from fstypes.conf (no static cdfs: no fs/cdfs/exp, no vfssw row,
#                         stock filesys.o, no libgcc pull) -- a module kernel whose cdfs is a boot module (kern30m -17)
#     --carve-fs ufs,s5   (S5-10, kernel/dlm C4-6 / docs/plan/s4-40-ufs-s5-carve.md) ufs and/or s5 out of the base: their
#                         fs/<fs>/exp leave fs/Makefile OPT_SUBEXP, their vfssw rows leave master.d/filesys.c, s5's
#                         inoinit leaves master.d/kernel.c's init_tbl (both objects recompiled: the object gate must
#                         allow master.d/filesys.o master.d/kernel.o); the stock exps are hashed against the sysroot.
#                         After the link, each carved fs becomes a core-tier module bound to the cut's build id
#                         (kernel/dlm tools/carve.py wrap + the k30 kit's make, which runs modcheck), written to
#                         usr/sys/mod.d/<fs> beside unix.brel. Needs --dlm-core with a built kit/k30 and --kinfo-build.
#     --sd-cards 2|4      (S4-21, kernel/dlm C4-1) 4 = the four-card sd layer: the staged sd.h gets SDCARDS 4
#                         and C4-1's sdcard() (card low bit 3, high bit 7), ct.c's table-index decode
#                         becomes (idx >> 3) & 3, sd.c.in's rank column and ranked insert (rank class,
#                         then base: 1 z3660, 2 zorro, 3 mobo, 4 ide), and every alien object that
#                         includes sd.h is compiled fresh.  2 (the default) is today's kernel, byte for byte.
#     --kabi k30.1.0|k30.1.1|k30.1.2|k30.1.3  (with --dlm) the module kernel's kabi: kinfo's tag, the core's DLM_KABI and
#                         the abi-<kabi>.txt mkabi checks against; k30.1.1 is stage 4's (kernel/dlm core 0031, the
#                         bdevsw layout; k30.1.2 from dlm 42411c4: root_defer, iodone, ramdisk_image,
#                         vfs_register; k30.1.3 from dlm e45b061, C3-2 v2: AllocMem, FreeMem, displaytype and the
#                         audio exclusion pair, so it needs --audio-paula). The block generator, the libgcc
#                         export loop and the core.list gate take only the list lines whose minor is at most the
#                         claim's (C3-2 v2 section 2). Default k30.1.0.
#     --bempty-ram        (S4-21, kernel/dlm core 0031) bdevsw row 20, the stock ramdisk, becomes an empty row (every
#                         routine nodev, nullflag) so a module's registered b: major can fill it.  An exact-line
#                         edit of master.d/kernel.c, which then recompiles.  Off by default.
#   A driver dir is kernel/drivers/<name> (e.g. ../drivers/a4091); a checkout kept elsewhere
#   (a driver not moved into amix yet, e.g. ~/amix-drivers/amix-z3660net) is given by its path:
#   ./build-cross-kernel.sh ../drivers/a4091 ../drivers/z3660scsi          # fd0unix (default)
#   ./build-cross-kernel.sh --config unix ../drivers/a4091 ../drivers/z3660scsi
#   # full metal-bootable combined kernel: SCSI + net + cdfs, root on c6d0s1 --
#   ./build-cross-kernel.sh --net ../drivers/z3660eth --config c6s1unix ../drivers/z3660scsi
#
#   --net <dir>  a STREAMS/DLPI network driver whose driver.conf carries a `net`
#       stanza (e.g. the z3660eth driver).  The host-side counterpart of the on-box net build:
#       stages amiga/driver/<subdir>/, wires cdevsw[<major>].d_str -> &<streamtab> in
#       master.d/kernel.c, and registers <subdir>/exp in amiga/driver/Makefile -- all on
#       the staged COPY, no box.  Omit for a SCSI(+fs)-only kernel.
#
#   --config <name>  which amiga/config/<name>.c becomes the kernel config object:
#       fd0unix  (default) install/boot-floppy: rootdev = FD0P (0x00400008), no dump dev
#       unix                placeholder ROOTDEV/DUMPDEV (the old relocation-spike default)
#       c0s1unix            root on c0d0s1 (SCSI target 0)
#       c6s1unix            root on c6d0s1 (SCSI target 6)
#
# Env overrides (sensible defaults):
#   CONFIG       config object source stem (default fd0unix; --config wins over env)
#   --rth1 <rth1.c>  (D-2) link the RTH1 kernel half: the port's src/rth1.c compiled with the
#                kit's own .c.o rule, gated (imports/exports exact, no COMMON, scan060 CLEAN, and
#                byte-identical with and without the cross wrapper's 64-bit-multiply rewrite), linked
#                into the final ET_REL, and main's jsr vfs_mountroot retargeted to rth1_mountroot by
#                the port's patch_rth1_hook.py (beside rth1.c) before elf2brel; --check re-run after.
#                scan060 is $PORT/test-tools/scan060.py, or without PORT the one in the port checkout
#                rth1.c sits in (<rth1.c dir>/../test-tools).
#   --kinfo <kinfo030.c> --kinfo-build 68030-yymmdd-nn [--kinfo-family NAME]  (C2-1/C2-3, stage 2) link
#                /dev/kinfo: src/kinfo030.c compiled with the kit's .c.o rule and the build id stamped in
#                (-DKINFO_BUILD), gated as rth1.o is (imports/exports exact, no COMMON, scan060 CLEAN,
#                identical with and without the 64-bit-multiply rewrite), linked into the final ET_REL,
#                registered in cdevsw[53] by tools/kinfo-cdevsw.py (row 53 must be free; --check after),
#                and, after elf2brel, the kabi sidecar written next to unix.brel ($BUILD/kabi) by
#                tools/kabi-sidecar030.py for family NAME (default K030-U); --check after.
#                scan060 is $PORT/test-tools/scan060.py: --kinfo needs PORT (a checkout of the port).
#   --dlm | --dlm-core <kernel/dlm dir> [--dlm-stub-providers]  (stage 3, S3-21; needs --kinfo) the module kernel:
#                tools/dlm-core-link.sh runs steps 1-10 of kernel/dlm's docs/plan/stage-3-kernel-brief.md on the
#                linked ET_REL after the kinfo row, before elf2brel, in $WORK/dlm-core: the core staged with its
#                series, mkoffs, mkreg, the core objects and core/plat at kabi k30.1.0, mkident's AXK1 + arena,
#                mkksym -a, the weakening splice, mkksym -f, mkident --fill, ksymgate. Step 8: rth1.c is compiled
#                with -DRTH1_DLM (its own hook calls dlm_marc_post after vfs_mountroot; the --rth1 file must have
#                it) and kinfo with -DKINFO_KABI="k30.1.0" -DKINFO_DLM (its module list). After elf2brel the sidecar is C2-3 version 5 (kabi-sidecar030.py --module).
#                --dlm = --dlm-core ../dlm (kernel/dlm beside kernel/k30). --dlm-stub-providers stubs whatever is still undefined (a DRY RUN:
#                such a kernel must not boot, and gets no sidecar).
#   --audio-paula <amix-paula dir>  (opt-in; required by --kabi k30.1.3) the stock /dev/audio driver made to share
#                Paula with amix-paula's /dev/paula: <dir>/port/src/ patch_audio_safeclose.py (channels freed on
#                close), patch_audio_initwait.py (audioopen's wait for Paula's first interrupt bounded: EIO on
#                timeout, not a spin) and patch_audio_paula.py (the paula_busy / audio_nopen exclusion), in the
#                port's order so both lines compile the same audio.c, applied to the work copy's
#                amiga/driver/audio.c, which section 4b recompiles before section 5 relinks amiga/driver. Each
#                script finds its places by fingerprint and refuses a mismatch.
#   --ttcompat-fix <patch_ttcompat_init.py>  (opt-in) the port's DRIVER-LINE-7 fix: clear the three
#                ttcompat state fields the stock ttcompatopen leaves uninitialised -- a same-length byte patch
#                on the linked ET_REL, located by symbol, after the rth1 hook and before elf2brel; --check after.
#                It changes no object, so --object-baseline is unaffected by it.
#   --tcp-hiwat-fix <patch_tcp_hiwat.py>  (opt-in) the port's DRIVER-LINE-10 fix: TCP's lower read queue
#                mi_hiwat 4096 -> 16384 (tcpm_info[3], one .data longword, located through tcplrinit) -- the
#                030 kit never passes through relink-040-fpe.sh, whose step 8.8 does this for the 060 line.
#                After the ttcompat fix, before elf2brel; --check after; exactly one byte may change.
#   --no-kzero   build WITHOUT the kzero fault catch (on by default; KZERO=0 does the same).  By default
#                src/kzero_nofault.s (grimoire quirk 90; from the port's k46-module b65b43d) joins the final
#                link and the stock kzero -- a second name for bzero, ml/exp .text+0x302 -- is weakened in the
#                work copy's ml/exp (one symbol-table byte), so pvn_vptrunc, rwip, writei, rwvp and spec_write
#                reach a kzero that returns -1 on an unresolvable fault instead of panicking.  A hard check
#                after the link: one strong kzero, not at bzero's stock 0x302, kzr_magic in .data, and exactly
#                the five callers' relocations (fewer by rwip / writei when --carve-fs takes ufs / s5 out;
#                the carved module imports kzero and binds to this one).  --no-kzero is the kernel without
#                it, byte for byte.
#   --no-ufs-tailzero  build WITHOUT the ufs truncation fix (on by default; UFS_TAILZERO=0 does the same).  By default
#                the ufs object the kernel uses -- fs/ufs/exp in the base, or the carved ufs module's object -- is the
#                stock one with ufs_itrunc's reference to pvn_vptrunc renamed to ufs_vptrunz (one .strtab string of
#                the same length) and src/ufs_vptrunz.c linked in (grimoire quirk 91): when a shrink to M cuts into a
#                kept block past the direct blocks it zeroes [M, end of the block) through segkmap and writes it
#                synchronously (SM_WRITE), then calls the stock pvn_vptrunc.
#                A hard check: ufs_vptrunz defined once, qz_magic, ufs_itrunc its only caller and no longer a caller
#                of pvn_vptrunc.  --no-ufs-tailzero is the kernel without it, byte for byte.
#   --no-fpu-gate  build WITHOUT the sendsig FPU gate (on by default; FPU_GATE=0 does the same).  By default
#                src/fpugate030.s (grimoire quirk 74) joins the final link and tools/fpugate-sendsig.py retargets the one
#                relocation of sendsig's jsr fpu_setup to fpu_setup_gated, which returns at once when fpu_present is 0:
#                a 68030 without an FPU then survives its first signal.  --check after the link and after the dlm
#                splice (sendsig its only caller, every other fpu_setup caller untouched).  --no-fpu-gate is the
#                kernel without it, byte for byte.
#   --no-freeq-guard  build WITHOUT the STREAMS freeq guard (on by default; FREEQ_GUARD=0 does the same).  By default
#                src/freeqguard030.c (grimoire quirk 92) joins the final link and tools/freeqguard-retarget.py retargets
#                every relocation naming freeq to freeq_guarded, which takes the pair off the run and scan lists at
#                spl7 before the stock freeq: qattach's undo of a failed open (qdetach clmode 0) no longer leaves a
#                freed queue for queuerun.  --check after the link and after the dlm splice (freeq named only from
#                freeq_guarded; qdetach and strclose among its callers).  --no-freeq-guard is the kernel without it,
#                byte for byte.
#   --object-baseline <file> --object-allow "<obj>..."  after the final link, every built
#                object must have the baseline's sha256 (`sha256  path` lines, paths under usr/sys)
#                EXCEPT exactly the allowed ones, which must differ; an object the baseline does not
#                list fails too (rth1.o and its AMIX_MUL64=keep twin excepted under --rth1). Example:
#                contracts/k030u-r5-objects.sha256 with --object-allow "amiga/alien/a4091.o".
#   AMIX_SYSTEM  a checkout of amigaux/amix-system: its usr/sys is the relink kit, usr/include the headers
#   SYSROOT_SYS  pristine staged /usr/sys  (default $AMIX_SYSTEM/usr/sys; one of the two must be set)
#   CROSS_PREFIX cross-tool prefix         (default m68k-cbm-sysv4-, found on PATH: . "$GCA/env.sh")
#   PORT         a checkout of the 68040/68060 port (kernel/port/port.pin): its test-tools/scan060.py
#   AMIX_DRIVERS where tools/kpatch-lib.sh looks for an `always:` row's driver that is not among the
#                build's dirs (default ../drivers, i.e. kernel/drivers)
#   WORK         gitignored build root     (default kernel/k30/work/cross-kernel)
#
# The pristine staging is treated as READ-ONLY: we build a throwaway COPY under WORK.
#
set -euo pipefail

KT="$(cd "$(dirname "$0")" && pwd)"

SYSROOT_SYS="${SYSROOT_SYS:-${AMIX_SYSTEM:+$AMIX_SYSTEM/usr/sys}}"
CROSS_PREFIX="${CROSS_PREFIX:-m68k-cbm-sysv4-}"
CC="${CROSS_PREFIX}gcc"
LD="${CROSS_PREFIX}ld"
NM="${CROSS_PREFIX}nm"
AS="${CROSS_PREFIX}as"
OBJDUMP="${CROSS_PREFIX}objdump"
WORK="${WORK:-$KT/work/cross-kernel}"
PROBE_SOLE="${PROBE_SOLE:-}"
BUILD="$WORK/usr/sys"
CONFIG="${CONFIG:-fd0unix}"   # amiga/config/<CONFIG>.c -> the unix.o link slot
NET_DIR="${NET_DIR:-}"        # --net <dir>: a STREAMS/DLPI net driver repo (driver.conf net stanza)
RTH1_C="${RTH1_C:-}"          # --rth1 <rth1.c>: the RTH1 kernel half
KINFO_C="${KINFO_C:-}"          # --kinfo <kinfo030.c>: /dev/kinfo (C2-1)
KINFO_BUILD="${KINFO_BUILD:-}"  # --kinfo-build 68030-yymmdd-nn: the build id it carries (and the sidecar's build=)
KINFO_FAMILY="${KINFO_FAMILY:-K030-U}"  # --kinfo-family NAME: the sidecar's family=
DLM_CORE="${DLM_CORE:-}"        # --dlm-core <kernel/dlm dir>: the module core spliced in (stage 3)
DLM_STUB=0                      # --dlm-stub-providers: a dry run with the owed providers stubbed
AUDIO_PAULA="${AUDIO_PAULA:-}"  # --audio-paula <amix-paula dir>: /dev/audio and /dev/paula exclude each other
TTC_FIX="${TTC_FIX:-}"          # --ttcompat-fix <patch_ttcompat_init.py>: the opt-in DRIVER-LINE-7 fix
FPU_GATE="${FPU_GATE:-1}"         # --no-fpu-gate (FPU_GATE=0): sendsig's fpu_setup call ungated, as stock
FREEQ_GUARD="${FREEQ_GUARD:-1}"   # --no-freeq-guard (FREEQ_GUARD=0): freeq unguarded, as stock (quirk 92)
UFS_TAILZERO="${UFS_TAILZERO:-1}"  # --no-ufs-tailzero (UFS_TAILZERO=0): the stock ufs object, no quirk-91 tail zeroing
KZERO="${KZERO:-1}"             # --no-kzero (KZERO=0): no kzero fault catch (src/kzero_nofault.s), the stock kzero = bzero
HIWAT_FIX="${HIWAT_FIX:-}"      # --tcp-hiwat-fix <patch_tcp_hiwat.py>: the opt-in DRIVER-LINE-10 fix
OBJ_BASELINE="${OBJ_BASELINE:-}"  # --object-baseline <sha256 list>: every object must match it ...
OBJ_ALLOW="${OBJ_ALLOW:-}"        # --object-allow "<obj> ...": ... except EXACTLY these (the object gate)
OBJ_ABSENT="${OBJ_ABSENT:-}"      # --object-absent "<obj> ...": the baseline objects not built, EXACTLY these
NO_SCSI_DRV="${NO_SCSI_DRV:-0}"   # --no-scsi-drivers: the stock scsicard[] rows only, no driver dir
CARVE_FS="${CARVE_FS:-}"          # --carve-fs ufs,s5: those filesystems out of the base, built as core-tier modules

# Top usr/sys/Makefile: CFLAGS = -DSYSV -D_KERNEL -I..  (kernel compile flags)
CFLAGS_K="-DSYSV -D_KERNEL -I.."

DIRS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)   CONFIG="${2:?--config needs a value}"; shift 2 ;;
    --probe-sole) PROBE_SOLE="${2:?--probe-sole needs a value}"; shift 2 ;;
    --sd-cards) SD_CARDS="${2:?--sd-cards needs 2 or 4}"; shift 2 ;;
    --kabi)     KABI="${2:?--kabi needs k30.1.0, k30.1.1, k30.1.2 or k30.1.3}"; shift 2 ;;
    --audio-paula) AUDIO_PAULA="${2:?--audio-paula needs the amix-paula directory}"; shift 2 ;;
    --bempty-ram) BEMPTY_RAM=1; shift ;;
    --config=*) CONFIG="${1#--config=}"; shift ;;
    --net)      NET_DIR="${2:?--net needs a value}"; shift 2 ;;
    --net=*)    NET_DIR="${1#--net=}"; shift ;;
    --rth1)     RTH1_C="${2:?--rth1 needs the path of rth1.c}"; shift 2 ;;
    --kinfo)    KINFO_C="${2:?--kinfo needs the path of kinfo030.c}"; shift 2 ;;
    --kinfo-build) KINFO_BUILD="${2:?--kinfo-build needs 68030-yymmdd-nn}"; shift 2 ;;
    --kinfo-family) KINFO_FAMILY="${2:?--kinfo-family needs a name}"; shift 2 ;;
    --dlm-core) DLM_CORE="${2:?--dlm-core needs the kernel/dlm directory}"; shift 2 ;;
    --dlm)      DLM_CORE="$KT/../dlm"; shift ;;
    --dlm-stub-providers) DLM_STUB=1; shift ;;
    --ttcompat-fix) TTC_FIX="${2:?--ttcompat-fix needs the path of patch_ttcompat_init.py}"; shift 2 ;;
    --tcp-hiwat-fix) HIWAT_FIX="${2:?--tcp-hiwat-fix needs the path of patch_tcp_hiwat.py}"; shift 2 ;;
    --object-baseline) OBJ_BASELINE="${2:?--object-baseline needs a sha256 list}"; shift 2 ;;
    --object-allow) OBJ_ALLOW="${2?--object-allow needs a list}"; shift 2 ;;
    --object-absent) OBJ_ABSENT="${2?--object-absent needs a list}"; shift 2 ;;
    --no-scsi-drivers) NO_SCSI_DRV=1; shift ;;
    --no-fstypes) FSTYPES_CONF=/dev/null; shift ;;
    --no-kzero) KZERO=0; shift ;;
    --no-ufs-tailzero) UFS_TAILZERO=0; shift ;;
    --no-fpu-gate) FPU_GATE=0; shift ;;
    --no-freeq-guard) FREEQ_GUARD=0; shift ;;
    --carve-fs) CARVE_FS="${2:?--carve-fs needs ufs,s5 or one of them}"; shift 2 ;;
    --)         shift; while [ "$#" -gt 0 ]; do DIRS+=("$1"); shift; done ;;
    -*)         echo "unknown option: $1" >&2; exit 2 ;;
    *)          DIRS+=("$1"); shift ;;
  esac
done
if [ -n "$CARVE_FS" ]; then
  for f in ${CARVE_FS//,/ }; do case "$f" in ufs|s5) ;; *) echo "--carve-fs: '$f' is not ufs or s5" >&2; exit 2;; esac; done
  [ -n "$DLM_CORE" ] && [ -n "$KINFO_BUILD" ] || { echo "--carve-fs needs --dlm-core and --kinfo-build (the modules bind to the build id)" >&2; exit 2; }
  [ "$DLM_STUB" = 1 ] || [ -f "$DLM_CORE/build/kit/k30/kit.conf" ] || { echo "--carve-fs: no kit at $DLM_CORE/build/kit/k30 (make kit there)" >&2; exit 2; }
  [ -f "$DLM_CORE/tools/carve.py" ] || { echo "--carve-fs: $DLM_CORE has no tools/carve.py (kernel/dlm d6b4381 or later)" >&2; exit 2; }
fi
if [ "$NO_SCSI_DRV" = 1 ]; then
  [ "${#DIRS[@]}" = 0 ] || { echo "--no-scsi-drivers takes no driver dir (given: ${DIRS[*]})" >&2; exit 2; }
else
  [ "${#DIRS[@]}" -ge 1 ] || { echo "usage: $0 [--config <name>] [--net <net-driver-dir>] <scsi-driver-dir>... | --no-scsi-drivers" >&2; exit 2; }
fi
[ -z "$OBJ_ABSENT" ] || [ -n "$OBJ_BASELINE" ] || { echo "--object-absent needs --object-baseline" >&2; exit 2; }
SD_CARDS="${SD_CARDS:-2}"
case "$FPU_GATE" in 0|1) ;; *) echo "FPU_GATE='$FPU_GATE' (want 0 or 1)" >&2; exit 2 ;; esac
case "$FREEQ_GUARD" in 0|1) ;; *) echo "FREEQ_GUARD='$FREEQ_GUARD' (want 0 or 1)" >&2; exit 2 ;; esac
case "$UFS_TAILZERO" in 0|1) ;; *) echo "UFS_TAILZERO='$UFS_TAILZERO' (want 0 or 1)" >&2; exit 2 ;; esac
case "$KZERO" in 0|1) ;; *) echo "KZERO='$KZERO' (want 0 or 1)" >&2; exit 2 ;; esac
case "$SD_CARDS" in 2|4) ;; *) echo "unknown --sd-cards '$SD_CARDS' (want: 2|4)" >&2; exit 2 ;; esac
KABI="${KABI:-k30.1.0}"
case "$KABI" in k30.1.0|k30.1.1|k30.1.2|k30.1.3) ;; *) echo "unknown --kabi '$KABI' (want: k30.1.0|k30.1.1|k30.1.2|k30.1.3)" >&2; exit 2 ;; esac
KABI_MINOR="${KABI##*.}"   # the claim's minor: list lines whose since is above it are not this kernel's (C3-2 v2)
# k30.1.3 lists paula_busy and audio_nopen, which only the patched audio.c defines: refuse the claim without the patch
# here, before a long build, rather than at ksymgate
if [ "$KABI_MINOR" -ge 3 ] && [ -z "$AUDIO_PAULA" ]; then
  echo "--kabi $KABI claims DDI minor 3 (paula_busy, audio_nopen), which needs --audio-paula <amix-paula dir>" >&2; exit 2
fi
if [ -n "$AUDIO_PAULA" ]; then
  for f in patch_audio_safeclose.py patch_audio_initwait.py patch_audio_paula.py; do
    [ -f "$AUDIO_PAULA/port/src/$f" ] || { echo "--audio-paula: no $AUDIO_PAULA/port/src/$f" >&2; exit 2; }
  done
fi
BEMPTY_RAM="${BEMPTY_RAM:-0}"
case "$CONFIG" in
  fd0unix|unix|c0s1unix|c6s1unix) ;;
  *) echo "unknown --config '$CONFIG' (want: fd0unix|unix|c0s1unix|c6s1unix)" >&2; exit 2 ;;
esac
[ -n "$SYSROOT_SYS" ] || { echo "neither SYSROOT_SYS nor AMIX_SYSTEM is set: set AMIX_SYSTEM to a checkout of amigaux/amix-system (its usr/sys is the relink kit), or SYSROOT_SYS to a staged /usr/sys" >&2; exit 2; }
[ -f "$SYSROOT_SYS/Makefile" ] || { echo "staged /usr/sys not found at $SYSROOT_SYS (want \$AMIX_SYSTEM/usr/sys of an amigaux/amix-system checkout, or SYSROOT_SYS)" >&2; exit 2; }
[ -f "$SYSROOT_SYS/../include/sys/sysmacros.h" ] || { echo "sys/sysmacros.h not staged at $SYSROOT_SYS/../include (needed to derive the makedevice layout; without this preflight the run dies silently at the late \$(cd ...) under set -e)" >&2; exit 2; }
[ -f "$SYSROOT_SYS/amiga/config/$CONFIG.c" ] || { echo "config source not staged: amiga/config/$CONFIG.c" >&2; exit 2; }
if [ -n "$NET_DIR" ]; then
  [ -f "$NET_DIR/driver.conf" ] || { echo "--net $NET_DIR has no driver.conf" >&2; exit 2; }
fi
# --kinfo's scan060 gate is the port's: refuse before the long build, not after it
[ -z "$KINFO_C" ] || [ -n "${PORT:-}" ] || { echo "--kinfo needs PORT, a checkout of the 68040/68060 port (kernel/port/port.pin): its test-tools/scan060.py gates kinfo.o" >&2; exit 2; }
for t in "$CC" "$LD" "$NM" "$OBJDUMP"; do command -v "$t" >/dev/null 2>&1 || { echo "cross tool missing: $t (put gcc-cross-amix's tools on PATH with . \"\$GCA/env.sh\", or set CROSS_PREFIX)" >&2; exit 2; }; done
# the toolchain's install root (<root>/bin/m68k-cbm-sysv4-gcc), where section 9 finds the cross libgcc.a:
# from CROSS_PREFIX when it is a path, else from where PATH finds the compiler
case "$CROSS_PREFIX" in
  */*) CROSS_ROOT="$(dirname "$(dirname "$CROSS_PREFIX")")" ;;
  *)   CROSS_ROOT="$(dirname "$(dirname "$(command -v "$CC")")")" ;;
esac

# --- helper: tokens of a make variable (join \-continuations, strip # comments) ---
mkvar() { # mkvar <makefile> <VAR>
  sed -e ':a' -e '/\\$/{N;s/\\\n//;ba}' "$1" \
    | sed 's/#.*//' \
    | awk -v V="$2" '$0 ~ "^[ \t]*"V"[ \t]*=" { sub("^[ \t]*"V"[ \t]*=[ \t]*",""); print; exit }'
}

# --- helper: recompile ONE kernel-patched .o in its own subdir, honoring THAT subdir's
# `.c.o` rule (so e.g. amiga/floppy's -DNODEBUG survives -- we do not hardcode the alien
# flags).  Substitute $(CC)->$CC, $(CFLAGS)->$CFLAGS_K, $<->the patched source, and pin
# the output with -o so the object name is deterministic.
#
# TWO Makefile shapes exist under /usr/sys and both must work:
#   * an EXPLICIT `.c.o:` rule and NO CFLAGS of its own (amiga/kernel, amiga/floppy,
#     amiga/alien).  $(CFLAGS) in that rule comes from the PARENT make, i.e. the top-level
#     usr/sys/Makefile -- which is why it is substituted with $CFLAGS_K.
#   * NO `.c.o:` rule but its OWN CFLAGS (amiga/driver/aen, amiga/console, amiga/driver).
#     make then uses its BUILT-IN suffix rule, `$(CC) -c $(CFLAGS) $<`, with the subdir's
#     own CFLAGS -- so that is what we synthesize.  Undefined make variables referenced by
#     those CFLAGS (aen's `$(KDB)`) expand to nothing, exactly as make expands them. ---
compile_patched_obj() { # compile_patched_obj <subdir-under-BUILD> <src.c> <obj.o> [extra-cflags]
  local sub="$1" src="$2" obj="$3" extra="${4:-}" rule subcflags v
  [ -f "$BUILD/$sub/$src" ] || { echo "patched source missing: $sub/$src" >&2; exit 1; }
  rule="$(awk '/^\.c\.o:/{getline; sub(/^[ \t]+/,""); print; exit}' "$BUILD/$sub/Makefile")"
  if [ -n "$rule" ]; then
    rule="${rule//\$(CC)/$CC}"
    rule="${rule//\$(CFLAGS)/$CFLAGS_K${extra:+ $extra}}"   # optional 4th arg appends CFLAGS (e.g. -D__STDC__=0)
    rule="${rule//\$</$src}"
  else
    subcflags="$(mkvar "$BUILD/$sub/Makefile" CFLAGS)"
    [ -n "$subcflags" ] || { echo "no .c.o rule AND no CFLAGS in $sub/Makefile -- cannot recompile $obj" >&2; exit 1; }
    # expand $(VAR) refs that this Makefile assigns; drop the rest (make expands an
    # unset variable to the empty string -- aen's $(KDB) is exactly that case).
    while [[ "$subcflags" =~ \$\(([A-Za-z_][A-Za-z0-9_]*)\) ]]; do
      v="${BASH_REMATCH[1]}"
      subcflags="${subcflags//\$($v)/$(mkvar "$BUILD/$sub/Makefile" "$v")}"
    done
    rule="$CC -c $subcflags${extra:+ $extra} $src"
  fi
  ( cd "$BUILD/$sub"; rm -f "$obj"; $rule -o "$obj" )   # $rule word-splits into argv
  echo "  recompiled patched $sub/$obj  ($rule -o $obj)"
}

# --- helper: ld -r a subdir's `exp` from a make variable in its own Makefile ---
relink_dir() { # relink_dir <subdir-under-BUILD> <make-var> [extra objs...]
  local sub="$1" var="$2"; shift 2
  local objs; objs="$(mkvar "$BUILD/$sub/Makefile" "$var")"
  ( cd "$BUILD/$sub"; "$LD" -r -o exp $objs "$@" )
  echo "  $sub/exp: $(file "$BUILD/$sub/exp" | sed 's/^[^:]*: //')"
}

# Subdirs whose `exp` section 5 relinks anyway.  A kernel-patched object in ANY OTHER
# subdir must have that subdir's own exp relinked in section 4b -- otherwise the stale
# STAGED exp blob is what gets linked in and the patch silently vanishes from the kernel.
SECTION5_RELINK="amiga/ml amiga/console amiga/driver amiga/floppy amiga/kernel"
# Subdirs section 7 relinks from their staged .o (their Makefiles use OBJS): a patched object there
# (master.d/kernel.c -- the gayle-ide driver's int2_tbl hook) is recompiled in 4b and picked
# up by that relink; 4b must not relink them itself (`OBJ` is empty there: "ld: no input files").
SECTION7_RELINK="fs master.d local"

echo "=================================================================="
echo " build-cross-kernel.sh  (host cross-link spike)"
echo "   sysroot : $SYSROOT_SYS"
echo "   cross   : ${CROSS_PREFIX}{gcc,ld,nm}"
echo "   build   : $BUILD"
echo "   config  : amiga/config/$CONFIG.c -> unix.o"
echo "=================================================================="

# === 1. SCSI codegen ==========================================================
# (parse each driver.conf; one scsicard[] row per product id, but the object/
#  extern/source ONCE per queue base -- A4092/A4770 share a4091queue/a4091-wr.c.)
EXTERNS="" CARDS="" OBJS_DRV="" SRCLIST="" PROBES="" SEEN=""
SRCS=() REMOTES=()
for d in "${DIRS[@]}"; do
  conf="$d/driver.conf"
  [ -f "$conf" ] || { echo "no driver.conf in $d" >&2; exit 2; }
  while read -r pn fn rest; do
    name="${rest#\"}"; name="${name%%\"*}"
    tail="${rest##*\"}"
    src=""; probe=""
    for tok in $tail; do
      case "$tok" in
        probe=*) probe="${tok#probe=}" ;;
        *) [ -z "$src" ] && src="$tok" ;;
      esac
    done
    base="${fn%queue}"
    [ -f "$d/src/$src" ] || { echo "missing $d/src/$src (from $conf)" >&2; exit 2; }
    # C4-1 section 4.2: the row's rank class, by the queue function's driver (four-card form only)
    RK=""
    if [ "$SD_CARDS" = 4 ]; then
      case "$base" in
        z3660) RK=", 1" ;;
        a4091|a2091|a2090) RK=", 2" ;;
        a3091) RK=", 3" ;;
        ide) RK=", 4" ;;
        *) echo "--sd-cards 4: no C4-1 rank class for queue function $fn ($conf)" >&2; exit 2 ;;
      esac
    fi
    CARDS="${CARDS}	${pn}, &${fn}, \"${name}\"${RK},"$'\n'
    case " $SEEN " in
      *" $base "*) echo "      + also $pn \"$name\" -> ${fn} (shares ${base}.o)"; continue ;;
    esac
    SEEN="$SEEN $base"
    EXTERNS="$EXTERNS, ${fn}()"
    OBJS_DRV="$OBJS_DRV ${base}.o"
    SRCLIST="$SRCLIST ${base}.c"
    SRCS+=("$d/src/$src"); REMOTES+=("${base}.c")
    if [ -n "$probe" ]; then
      if [ "${PROBE_SOLE:-}" != "$probe" ]; then
        PROBES="${PROBES}		{ extern int ${probe}(); char *pa; uint pi;"$'\n'
        PROBES="${PROBES}		  for (pi=0; pi<nel( queue); ++pi)"$'\n'
        PROBES="${PROBES}			if (queue[pi].f == &${fn}) break;"$'\n'
        PROBES="${PROBES}		  if (pi == nel( queue) && ${probe}( &pa))"$'\n'
        PROBES="${PROBES}			insert( &${fn}, 0, pa, \"${name}\"${RK}); }"$'\n'
      else
        # --probe-sole <fn>: this board registers ONLY when the autocon loop inserted nothing, i.e. it is
        # the sole controller and therefore card 0 (the K030-IDE rule: the Gayle port never coexists with a
        # Zorro SCSI card in this family; a4091/z3660 configs keep the fallback form above).
        PROBES="${PROBES}		{ extern int ${probe}(); char *pa;"$'\n'
        PROBES="${PROBES}		  if (not queue->f && ${probe}( &pa))"$'\n'
        PROBES="${PROBES}			insert( &${fn}, 0, pa, \"${name}\"${RK}); }	/* sole-controller rule */"$'\n'
        echo "probe ${probe}: sole-controller rule (registers only when autocon found nothing)"
      fi
    fi
    echo "scsi driver: $pn $fn \"$name\"  <- $d/src/$src  (alien ${base}.c)${probe:+  probe=$probe}"
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$conf")
done
[ "${#SRCS[@]}" -ge 1 ] || [ "$NO_SCSI_DRV" = 1 ] || { echo "no SCSI drivers found in: ${DIRS[*]}" >&2; exit 2; }
[ "$NO_SCSI_DRV" = 0 ] || echo "scsi drivers: none (--no-scsi-drivers): scsicard[] = the stock A3000 WD, A2090, A2091 rows"

# === 1b. fstype records -- kernel/k30-side in-kernel filesystem staging config =====
# Parallels the SCSI driver.conf parse (section 1), but the config is kernel/k30-OWNED
# (fstypes.conf), NOT a driver.conf inside the FS provider repo -- amix-cdfs stays
# upstream-clean.  It is a REUSABLE record: a 2nd in-kernel filesystem is a one-line add.
# The grammar + parser live in tools/fstype-lib.sh, the single definition every
# builder sources so they never fork it.  fstype_parse populates
# FS_NAMES/FS_INITS/FS_EXPS/FS_FLAGS + FS_EXTERNS/FS_VFSSW.  Per record, section 7a
# stages the exp + registers it in fs/Makefile OPT_SUBEXP, section 7b injects a vfssw[]
# row + extern into master.d/filesys.c (and recompiles filesys.o), and section 9 pulls
# in the cross libgcc.a for the fs's 64-bit soft-arith helpers.
# shellcheck source=tools/fstype-lib.sh
. "$KT/tools/fstype-lib.sh"
FSTYPES_CONF="${FSTYPES_CONF:-$KT/fstypes.conf}"
fstype_parse "$FSTYPES_CONF" "$KT"
if [ "${#FS_NAMES[@]}" -eq 0 ]; then
  echo "--- no fstype records active ($FSTYPES_CONF) -- kernel built without extra in-kernel filesystems ---"
else
  echo "--- ${#FS_NAMES[@]} fstype record(s) to stage: ${FS_NAMES[*]} ---"
fi

# === 1c. NET driver stanza ========================================================
# A STREAMS/DLPI network driver is NOT a scsicard[] row: it wires into master.d/
# kernel.c's cdevsw[MAJOR].d_str -> &<streamtab>, lives in its own amiga/driver/
# <subdir>/ subtree, and is registered in amiga/driver/Makefile's OBJ list.  The grammar
# is the SAME driver.conf `net` stanza the on-box build (amix-build) parses -- one
# source of truth, so the two paths never diverge on the streamtab symbol / cdevsw major:
#     net  <subdir>  <src>  <streamtab-symbol>  <cdevsw-major>  <iface>  "<desc>"
# On the box, the net driver's own tools/patch-kernel.sh + tools/patch-makefile.sh do the
# two edits with `ed` against the box's absolute /usr/sys/... paths; host-side we replicate the SAME anchored
# edits (extern after `aeninfo`; claim the free `nostr` slot; OBJ entry before `aen/exp`)
# on the staged $BUILD COPY in sections 4c + 7b-net below.  Nothing is hardcoded per
# driver -- all of it derives from the parsed net stanza.
NET_SUBDIR="" NET_SRC="" NET_STREAMTAB="" NET_MAJOR="" NET_IFACE=""
if [ -n "$NET_DIR" ]; then
  read -r nkw NET_SUBDIR NET_SRC NET_STREAMTAB NET_MAJOR NET_IFACE _NET_REST \
      < <(grep -E '^[[:space:]]*net[[:space:]]' "$NET_DIR/driver.conf")
  [ "${nkw:-}" = net ] || { echo "no 'net' stanza in $NET_DIR/driver.conf" >&2; exit 2; }
  [ -n "$NET_SUBDIR" ] && [ -n "$NET_STREAMTAB" ] && [ -n "$NET_MAJOR" ] \
      || { echo "malformed 'net' stanza in $NET_DIR/driver.conf" >&2; exit 2; }
  [ -d "$NET_DIR/src" ] || { echo "--net $NET_DIR has no src/ dir" >&2; exit 2; }
  [ -f "$NET_DIR/src/$NET_SRC" ] || { echo "net driver main source missing: $NET_DIR/src/$NET_SRC" >&2; exit 2; }
  echo "--- net driver: subdir=$NET_SUBDIR src=$NET_SRC streamtab=$NET_STREAMTAB cdevsw-major=$NET_MAJOR iface=$NET_IFACE ---"
else
  echo "--- no --net driver -- kernel built without an in-kernel network driver ---"
fi

mkdir -p "$WORK"
# the module core's sd seam (kernel/dlm core patch 0032, C4-1 section 3): with --sd-cards 4 and a core that defines
# dlm_sd_close, init() takes the core's pending registrations before the probes and closes registration
SDREG=""
# (grep reads the patches itself: `cat | grep -q` under pipefail is false whenever grep exits before cat has written all)
if [ "$SD_CARDS" = 4 ] && [ -n "$DLM_CORE" ] && grep -q -h '^+dlm_sd_close' "$DLM_CORE"/core/patches/*.patch 2>/dev/null; then
  SDREG=1; echo "--- sd: the module core's registrations (dlm_sd_close, core 0032) join init() ---"
fi
EXTERNS="$EXTERNS" CARDS="$CARDS" PROBES="$PROBES" SD4="$([ "$SD_CARDS" = 4 ] && echo 1)" SDREG="$SDREG" awk '
  # the four-card blocks (C4-1): @SD4_BEGIN@..@SD4_END@ only with --sd-cards 4, @SD2_BEGIN@..@SD2_END@
  # only without it, and the @R:n@ rank column of a row only with it -- without it the output is the 1.0 text
  /^@SD4_BEGIN@$/ { skip = !ENVIRON["SD4"]; next }
  /^@SD2_BEGIN@$/ { skip = ENVIRON["SD4"] != ""; next }
  /^@SDREG_BEGIN@$/ { skip = ENVIRON["SDREG"] == ""; next }
  /^@SD[24]_END@$/ || /^@SDREG_END@$/ { skip = 0; next }
  skip { next }
  { while (match($0, /@R:[0-9]@/))
      $0 = substr($0, 1, RSTART - 1) (ENVIRON["SD4"] ? ", " substr($0, RSTART + 3, 1) : "") substr($0, RSTART + RLENGTH) }
  { gsub(/@DRIVER_EXTERNS@/, ENVIRON["EXTERNS"]) }
  /@DRIVER_CARDS@/ { printf "%s", ENVIRON["CARDS"]; next }
  /@DRIVER_PROBES@/ { printf "%s\t}\n", ENVIRON["PROBES"]; next }
  { print }
' "$KT/templates/sd.c.in" > "$WORK/sd.c"
OBJS_DRV="$OBJS_DRV" awk '
  { gsub(/@DRIVER_OBJS@/, ENVIRON["OBJS_DRV"]); print }
' "$KT/templates/alien-Makefile.in" > "$WORK/alien-Makefile"
echo "generated: $WORK/sd.c $WORK/alien-Makefile  (driver OBJ +=$OBJS_DRV)"

# === 2. fresh throwaway COPY of the pristine staged /usr/sys ==================
echo "--- copying pristine sysroot -> $BUILD (pristine staging left byte-for-byte) ---"
# the staged tree can be read-only and cp -a keeps its modes: a leftover copy needs u+w before
# rm can remove it, and the fresh copy needs it because the patches and relinks write into it
chmod -R u+w "$WORK/usr" 2>/dev/null || true
rm -rf "$WORK/usr"
mkdir -p "$WORK/usr"
cp -a "$SYSROOT_SYS" "$WORK/usr/sys"
chmod -R u+w "$BUILD"

# === 2b. apply each driver's kernel-patches to the WORK copy (pristine untouched) =====
# For every <driver-dir>/src/kernel-patches/*.patch (a driver with no kernel-patches dir
# or an empty glob is skipped cleanly -- not an error), gate with `patch -p0 -F0 --dry-run`
# and ABORT LOUDLY on any reject or fuzz (-F0 turns fuzz into a hard reject; no silent -N).
# Then apply for real -- to the throwaway $BUILD tree ONLY; the pristine staging under
# $SYSROOT_SYS is never touched.  Each applied patch's unified-diff "+++ " target path
# tells us which object must be freshly cross-compiled instead of relinked from the stale
# staged .o:  amiga/alien/* joins the section-4 FRESH_OBJ set; any other subdir's object
# is recompiled in section 4b BEFORE that subdir's exp is relinked.  The (subdir,object)
# pairs are DERIVED from the target paths -- nothing about scsi.o / support.o is hardcoded.
PATCH_ALIEN_OBJ=""          # alien objects to add to the section-4 FRESH_OBJ set
PATCHED_OTHER=()            # "subdir|obj|src" triples recompiled in section 4b
PATCHED_OTHER_SEEN=""
PATCH_N=0
# "$KT" leads the list: kernel/k30 ITSELF carries kernel-patches for STOCK drivers that no
# driver owns (amiga/driver/aen/aen.c -- the A2065 driver linked into every kernel).
# It uses the identical src/kernel-patches/*.patch convention, so it is simply always in
# the patch-source list -- the same rule kernel-patches.conf's `k30` repo key
# expresses.  See tools/kpatch-lib.sh :: kpatch_repo_dir.
PATCH_SRC=()
# PATCH_DIRS (env, space-separated): repos whose src/kernel-patches join the glob WITHOUT being in
# the build -- a stock-layer fix another driver carries (the z3660scsi driver's dd.c ordering patch)
# applied to a family that does not link that driver (K030-IDE). Logged per patch.
for d in "$KT" "${DIRS[@]}" ${PATCH_DIRS:-}; do
  pdir="$d/src/kernel-patches"
  [ -d "$pdir" ] || continue                       # driver ships no kernel-patches: skip
  shopt -s nullglob; PATCH_SRC+=( "$pdir"/*.patch ); shopt -u nullglob
done

# --- and the conf's `always:` rows, which the glob above CANNOT see -------------------
# The glob decides the CONDITIONAL patches: a driver dir on the command line brings its
# own, including ones kernel-patches.conf deliberately excludes.  It cannot decide the
# UNCONDITIONAL ones, because an `always:<repo>` row applies to every kernel whether or
# not <repo> is in the build -- and the whole reason that prefix exists is that keying a
# boot-critical patch to a driver repo made it conditional on which UNRELATED driver
# happened to be selected.  Without reading the conf, a cross kernel could ship with
# the RAM-size guess still in amiga/kernel/support.c and still gate green.
#
# kpatch_always_extra reconciles the two rules and is the ONLY new authority here: it
# emits an `always:` patch only when the glob does not already supply it byte-identically,
# refuses when a globbed patch writes the same file with different bytes, and refuses when
# an `always:` patch is missing altogether.  So a build that already passed the owning
# repo (e.g. an install kernel that passes the a4091 driver dir unfiltered) is byte-for-byte
# unchanged, and a build that did not now either carries the patch or does not happen.
# shellcheck source=tools/kpatch-lib.sh
. "$KT/tools/kpatch-lib.sh"
KPATCH_CONF="${KPATCH_CONF:-$KT/kernel-patches.conf}"
# Written to a file rather than read through a pipe/process substitution ON PURPOSE: the
# function's REFUSAL is its exit status, and both of those forms throw it away.
# (PATCH_DIRS too: they are in the glob above, so an always: patch they carry is already supplied)
# shellcheck disable=SC2086
if ! kpatch_always_extra "$KPATCH_CONF" "$KT" "$KT" ${DIRS[@]+"${DIRS[@]}"} ${PATCH_DIRS:-} > "$WORK/always-extra.list"; then
  echo "FATAL: $KPATCH_CONF has 'always:' row(s) this cross build cannot honour -- aborting" >&2
  echo "       (an unconditional kernel patch is never silently skipped; see the lines above)" >&2
  exit 1
fi
ALWAYS_EXTRA=()
mapfile -t ALWAYS_EXTRA < "$WORK/always-extra.list"
if [ "${#ALWAYS_EXTRA[@]}" -ge 1 ]; then
  echo "--- ${#ALWAYS_EXTRA[@]} unconditional patch(es) from $(basename "$KPATCH_CONF") the driver glob does not supply ---"
  printf '      %s\n' "${ALWAYS_EXTRA[@]}"
  PATCH_SRC+=( "${ALWAYS_EXTRA[@]}" )
fi

if [ "${#PATCH_SRC[@]}" -ge 1 ]; then
  for p in "${PATCH_SRC[@]}"; do
    # absolute patch path: the `patch` runs after `cd "$BUILD"`, so a relative "$p"
    # (e.g. ../drivers/a4091/...) would resolve against $BUILD -- pin it now.
    pabs="$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    # every file this patch writes (unified-diff "+++ " lines); skip a /dev/null target
    mapfile -t tgts < <(awk '/^\+\+\+ /{print $2}' "$pabs")
    [ "${#tgts[@]}" -ge 1 ] || { echo "no '+++ ' target in patch: $p" >&2; exit 1; }
    for t in "${tgts[@]}"; do
      [ "$t" = /dev/null ] && continue
      [ -f "$BUILD/$t" ] || { echo "patch target not in tree: $t (from $p)" >&2; exit 1; }
      case "$t" in
        *.c) : ;;
        *) echo "patch $p targets non-.c '$t'; this harness only maps .c->.o (abort)" >&2; exit 1 ;;
      esac
    done
    # dry-run gate FIRST: -F0 makes ANY fuzz a hard failure; abort loudly if unclean
    if ! out="$( cd "$BUILD" && patch -p0 -F0 --dry-run < "$pabs" 2>&1 )"; then
      printf '%s\n' "$out" >&2
      echo "FATAL: $p would not apply cleanly to $BUILD (reject/fuzz) -- aborting" >&2
      exit 1
    fi
    # real apply (still -F0: no fuzz tolerated, no -N skips)
    if ! out="$( cd "$BUILD" && patch -p0 -F0 < "$pabs" 2>&1 )"; then
      printf '%s\n' "$out" >&2
      echo "FATAL: $p failed to apply after a clean dry-run -- aborting" >&2
      exit 1
    fi
    PATCH_N=$((PATCH_N+1))
    echo "kernel-patch applied: $p"
    for t in "${tgts[@]}"; do
      [ "$t" = /dev/null ] && continue
      sub="$(dirname "$t")"; src="$(basename "$t")"; obj="$(basename "${t%.c}").o"
      if [ "$sub" = amiga/alien ]; then
        case " sd.o$OBJS_DRV$PATCH_ALIEN_OBJ " in
          *" $obj "*) : ;;                           # already in the fresh section-4 set
          *) PATCH_ALIEN_OBJ="$PATCH_ALIEN_OBJ $obj" ;;
        esac
        echo "  -> $t : amiga/alien/$obj joins section-4 FRESH_OBJ (fresh cross-compile)"
      else
        case " $PATCHED_OTHER_SEEN " in
          *" $sub/$obj "*) : ;;
          *) PATCHED_OTHER+=("$sub|$obj|$src"); PATCHED_OTHER_SEEN="$PATCHED_OTHER_SEEN $sub/$obj" ;;
        esac
        echo "  -> $t : $sub/$obj recompiled (section 4b) before $sub/exp relink"
      fi
    done
  done
fi
if [ "$PATCH_N" -eq 0 ]; then
  echo "--- no kernel-patches to apply (no <driver>/src/kernel-patches/*.patch, no 'always:' row) ---"
else
  echo "--- applied $PATCH_N kernel-patch(es) to the WORK copy; pristine staging untouched ---"
fi

# === 2b'. --audio-paula: /dev/audio shares Paula with /dev/paula (amix-paula's two fingerprinted source patches) =====
if [ -n "$AUDIO_PAULA" ]; then
  AUD="$BUILD/amiga/driver/audio.c"
  [ -f "$AUD" ] || { echo "--audio-paula: no amiga/driver/audio.c in the work copy" >&2; exit 1; }
  echo "--- audio-paula: $AUDIO_PAULA/port/src/patch_audio_{safeclose,initwait,paula}.py (the port's order) -> amiga/driver/audio.c ---"
  cp "$AUD" "$WORK/audio.c.stock"
  for f in patch_audio_safeclose.py patch_audio_initwait.py patch_audio_paula.py; do
    python3 "$AUDIO_PAULA/port/src/$f" "$AUD" || { echo "FATAL: $f refused audio.c" >&2; exit 1; }; done
  for n in paula_busy audio_nopen; do grep -q "^int[[:space:]][[:space:]]*$n;" "$AUD" \
    || { echo "FATAL: the patched audio.c defines no $n" >&2; exit 1; }; done
  echo "  audio.c: $(sha256sum < "$WORK/audio.c.stock" | cut -c1-16) -> $(sha256sum < "$AUD" | cut -c1-16), +$(( $(wc -l < "$AUD") - $(wc -l < "$WORK/audio.c.stock") )) lines"
  # audio.c's #include "memory.h" is the Amiga one (amiga/inc: MEMF_CHIP, AllocMem); the cross gcc's sysroot include path
  # comes before -I../inc and would hand it libc's <memory.h>. A quoted include looks beside the source first, so the
  # work copy gets amiga/inc/memory.h there (amix-paula's relink-040-audio-paula.sh does the same); only audio.o is rebuilt.
  cp "$BUILD/amiga/inc/memory.h" "$BUILD/amiga/driver/memory.h" || { echo "FATAL: no amiga/inc/memory.h" >&2; exit 1; }
  case " $PATCHED_OTHER_SEEN " in *" amiga/driver/audio.o "*) : ;;
    *) PATCHED_OTHER+=("amiga/driver|audio.o|audio.c"); PATCHED_OTHER_SEEN="$PATCHED_OTHER_SEEN amiga/driver/audio.o" ;; esac
  echo "  -> amiga/driver/audio.o recompiled (section 4b) before section 5 relinks amiga/driver"
fi

# === 2c. --sd-cards 4: the four-card sd layer (S4-21, kernel/dlm C4-1 section 2) ==============
# sd.h is a header, which the patch harness above does not take, so the two stock edits are made
# here, each anchored on the exact stock line and refused when the line is not there exactly once:
#   sd.h  SDCARDS 2 -> 4; sdcard( dev) = card low bit 3 | card high bit 7 (C4-1 section 2.1)
#   ct.c  com.card from a cttab INDEX (dp - cttab[0], 0..31) is (idx >> 3) & 3, not the minor decode
# Every alien object that includes sd.h then compiles fresh, so no stock object keeps a two-card
# table or decode (dd's ddtab, ct's cttab, a2091/a2090/a4091 arrays sized SDCARDS).
stock_edit() { # stock_edit <file> <stock line> <new line>: an exact line that must occur exactly once
  local n
  n="$(grep -cxF -- "$2" "$1")"
  [ "$n" = 1 ] || { echo "FATAL: '$2' occurs $n time(s) in $1, want exactly 1" >&2; exit 1; }
  STOCK="$2" NEW="$3" awk '$0 == ENVIRON["STOCK"] { print ENVIRON["NEW"]; next } { print }' "$1" > "$1.edit" && mv "$1.edit" "$1"
  echo "  $(basename "$1"): $3"
}
if [ "$SD_CARDS" = 4 ]; then
  echo "--- --sd-cards 4: the C4-1 four-card sd layer ---"
  sd4_edit() { stock_edit "$@"; }
  sd4_edit "$BUILD/amiga/alien/sd.h" "#define	SDCARDS	2" "#define	SDCARDS	4"
  sd4_edit "$BUILD/amiga/alien/sd.h" "#define	sdcard( dev)	((dev)>>3 & 01)" \
           "#define	sdcard( dev)	((dev)>>3 & 01 | (dev)>>6 & 02)"
  sd4_edit "$BUILD/amiga/alien/ct.c" "	dp->com.card = sdcard( dp-cttab[0]);" \
           "	dp->com.card = (dp-cttab[0])>>3 & 03;"
  sd4_edit "$BUILD/amiga/alien/ct.c" "	dp->com.unit = sdunit( dp-cttab[sdcard( dp-cttab[0])]);" \
           "	dp->com.unit = sdunit( dp-cttab[(dp-cttab[0])>>3 & 03]);"
  for c in "$BUILD"/amiga/alien/*.c; do
    grep -q '^#include[[:space:]]*"sd\.h"' "$c" || continue
    obj="$(basename "${c%.c}").o"
    case " sd.o$OBJS_DRV$PATCH_ALIEN_OBJ " in
      *" $obj "*) : ;;
      *) PATCH_ALIEN_OBJ="$PATCH_ALIEN_OBJ $obj"; echo "  -> amiga/alien/$obj includes sd.h: joins section-4 FRESH_OBJ" ;;
    esac
  done
fi
if [ "$BEMPTY_RAM" = 1 ]; then
  echo "--- --bempty-ram: bdevsw row 20 (the stock ramdisk) empty for a module's block major (kernel/dlm core 0031) ---"
  stock_edit "$BUILD/master.d/kernel.c" "ramopen, ramclose, ramstrategy, ramprint, ramsize, ND, ND, nullflag, /*20 = ramdisk*/" \
             "ND,ND,ND,ND,ND,ND,ND,nullflag,	/*20: empty (--bempty-ram; a module's b: major fills it)*/"
  case " $PATCHED_OTHER_SEEN " in
    *" master.d/kernel.o "*) : ;;
    *) PATCHED_OTHER+=("master.d|kernel.o|kernel.c"); PATCHED_OTHER_SEEN="$PATCHED_OTHER_SEEN master.d/kernel.o"
       echo "  -> master.d/kernel.c : master.d/kernel.o recompiled (section 4b) before master.d/exp relink" ;;
  esac
fi

ALIEN="$BUILD/amiga/alien"

# === 3. integrate the driver into amiga/alien ================================
cp "$WORK/sd.c"           "$ALIEN/sd.c"           # generated sd.c overwrites stock
cp "$WORK/alien-Makefile" "$ALIEN/Makefile"       # generated OBJ list
for i in "${!SRCS[@]}"; do
  cp "${SRCS[$i]}" "$ALIEN/${REMOTES[$i]}"        # driver source -> canonical alien name
  echo "  driver src: ${SRCS[$i]} -> amiga/alien/${REMOTES[$i]}"
done

# === 4. amiga/alien/exp: cross-compile the CHANGED objects, reuse staged .o ==
# alien Makefile .c.o rule: $(CC) -c -O $(CFLAGS) -I../.. -I../inc  (CFLAGS from top).
# Freshly compile only what an on-box build force-rebuilds -- sd.o + driver objects
# (e.g. "sd.o a4091.o z3660.o"); the stock alien objects keep their
# staged native .o (present from the cp -a of pristine staging).
ALIEN_OBJ="$(mkvar "$ALIEN/Makefile" OBJ)"          # full link list
FRESH_OBJ="sd.o$OBJS_DRV$PATCH_ALIEN_OBJ"           # regenerated sd.o + new drivers + alien kernel-patched objs
echo "--- amiga/alien: cross-compiling$FRESH_OBJ ; reusing staged native .o for the rest ---"

# --- 4-shadow: defeat the cross gcc's quote-include mis-resolution -------------
# gcc 2.7.2.3 resolves a `#include "H"` that is NOT in the compiled file's OWN
# directory against the sysroot /usr/include BEFORE the -I../inc user dir.  So an
# Amiga kernel header under amiga/inc/ whose basename ALSO exists as an AT&T stdlib
# header in the sysroot is silently shadowed by the wrong file -- e.g. a3091.c's
# `#include "memory.h"` picks up /usr/include/memory.h (memccpy protos, no MEMF_CHIP)
# instead of amiga/inc/memory.h, and the compile dies on `MEMF_CHIP undeclared`.
# (rico.h/sd.h dodge this only because they physically sit in amiga/alien/.)  -iquote,
# absolute -I and -include were all tried against this compiler and do NOT fix it.
# Fix: for the span of the fresh-object compiles, drop a copy of every COLLIDING
# amiga/inc header into amiga/alien/ so the current-directory search finds the RIGHT
# (kernel) header first -- exactly the resolution the on-box -I ordering gives, so the
# .o is byte-for-byte the on-box object.  The colliding set is DERIVED at build time
# (amiga/inc basename present in the sysroot /usr/include), never hardcoded to memory.h:
# a newly-added colliding Amiga header is covered with no edit, and a header with no
# sysroot twin is left alone (the -I../inc search already resolves it correctly).
# Removed again after the loop so the throwaway tree is left clean.
SYSROOT_INC="$SYSROOT_SYS/../include"
SHADOW_HDRS=()
for inc in "$BUILD/amiga/inc"/*.h; do
  [ -f "$inc" ] || continue
  h="$(basename "$inc")"
  [ -f "$ALIEN/$h" ] && continue                    # already local: current dir already wins
  [ -f "$SYSROOT_INC/$h" ] || continue              # no sysroot twin: -I../inc resolves it right
  cp "$inc" "$ALIEN/$h"
  SHADOW_HDRS+=("$h")
done
[ "${#SHADOW_HDRS[@]}" -gt 0 ] \
  && echo "  include-shadow guard: staged amiga/inc -> amiga/alien for the compile of: ${SHADOW_HDRS[*]}"

( cd "$ALIEN"
  rm -f $FRESH_OBJ exp                              # no dep tracking: force these fresh
  for o in $FRESH_OBJ; do
    c="${o%.o}.c"
    [ -f "$c" ] || { echo "alien: missing source $c for $o" >&2; exit 2; }
    # -D__STDC__=0 only for a source that includes <sys/user.h> (its MAXSIG/stack_t sit behind
    # `#if (__STDC__ - 0 == 0)`, the same knob 4b/7b apply): stock sdpart.c, first compiled fresh by
    # the sddevsize kernel patch.  Every other alien source compiles exactly as before.
    knob=""; grep -q '"sys/user.h"' "$c" && knob="-D__STDC__=0"
    "$CC" -c -O $CFLAGS_K $knob -I../.. -I../inc "$c" -o "$o"
  done
  for o in $ALIEN_OBJ; do
    [ -f "$o" ] || { echo "alien: missing object $o (neither fresh nor staged)" >&2; exit 2; }
  done
  "$LD" -r -o exp $ALIEN_OBJ
)
# retract the shadow copies: their job (winning the current-dir quote search) is done,
# and leaving stdlib-basename files in amiga/alien/ could confuse a later relink/inspection.
for h in "${SHADOW_HDRS[@]:-}"; do [ -n "$h" ] && rm -f "$ALIEN/$h"; done
echo "  amiga/alien/exp: $(file "$ALIEN/exp" | sed 's/^[^:]*: //')"
echo "  (fresh cross-compiled:$FRESH_OBJ ; staged native: the rest of: $ALIEN_OBJ)"

# === 4b. recompile NON-alien kernel-patched objects from their patched source ========
# alien-targeted patches were folded into FRESH_OBJ and compiled in section 4.  A patch
# under any OTHER subdir (e.g. amiga/kernel/support.c) must have its object rebuilt from
# the PATCHED source HERE -- before section 5's relink_dir picks the object up.  Otherwise
# relink_dir would ld -r the stale staged .o and the patch would silently vanish from the
# linked kernel.  Each object is compiled with its own subdir's .c.o rule (compile_patched_obj).
#
# A patched object in a NESTED subdir (amiga/driver/aen) additionally needs THAT subdir's
# own `exp` relinked here: section 5 relinks amiga/driver from its OBJ list, and that list
# names `aen/exp` -- the staged blob -- not aen.o.  Without this relink the freshly compiled
# aen.o would never reach the kernel and the patch would vanish silently.  Inert for the
# section-5 subdirs themselves (amiga/kernel/support.o etc.), which section 5 handles.
#
# -D__STDC__=0 is passed for every patched object: the cross gcc defines __STDC__=1, but
# this SVR4 header set gates <sys/user.h>'s MAXSIG/stack_t behind `#if (__STDC__ - 0 == 0)`
# (native cc leaves __STDC__ unset), so aen.c will not compile without it.  It is a PROVEN
# no-op for the pre-existing consumer: amiga/kernel/support.c compiles to a byte-identical
# object with and without the knob.  Same knob sections 4c and 7b already apply.
if [ "${#PATCHED_OTHER[@]}" -gt 0 ]; then
  echo "--- recompiling non-alien kernel-patched objects from patched source ---"
  for triple in "${PATCHED_OTHER[@]}"; do
    IFS='|' read -r psub pobj psrc <<<"$triple"
    compile_patched_obj "$psub" "$psrc" "$pobj" "-D__STDC__=0"
    case " $SECTION5_RELINK $SECTION7_RELINK " in
      *" $psub "*) : ;;                              # section 5 or 7 relinks this subdir's exp from the (now patched) .o
      *) echo "  $psub is not relinked by section 5/7 -- relinking $psub/exp from its own OBJ"
         relink_dir "$psub" OBJ ;;
    esac
  done
fi

# === 4c. NET driver: stage subtree, cross-compile <subdir>/exp, patch driver/Makefile ==
# HOST-SIDE equivalent of tools/onbox-build.sh section 2:
# copy the driver's src/ into $BUILD/amiga/driver/<subdir>/, cross-compile its OBJ using
# the driver's OWN Makefile CFLAGS (so -DSVR40/-DSVR4/-I paths never fork from the repo),
# ld -r into <subdir>/exp, then register <subdir>/exp in amiga/driver/Makefile's OBJ list
# -- inserted before the stock `aen/exp` entry (the same anchor the driver's
# tools/patch-makefile.sh uses on-box) so it carries the trailing "\" and aen/exp stays terminal.  This MUST run
# before section 5's `relink_dir amiga/driver OBJ` picks up the (now-extended) OBJ list.
if [ -n "$NET_DIR" ]; then
  NDRV="$BUILD/amiga/driver/$NET_SUBDIR"
  echo "--- net: staging amiga/driver/$NET_SUBDIR from $NET_DIR/src ---"
  mkdir -p "$NDRV"
  shopt -s nullglob
  for f in "$NET_DIR"/src/*.c "$NET_DIR"/src/*.h "$NET_DIR"/src/Makefile; do
    [ -f "$f" ] && cp "$f" "$NDRV/$(basename "$f")"
  done
  shopt -u nullglob
  [ -f "$NDRV/Makefile" ] || { echo "net: $NET_DIR/src/Makefile missing (needed for CFLAGS/OBJ)" >&2; exit 2; }
  NET_CFLAGS="$(mkvar "$NDRV/Makefile" CFLAGS)"
  NET_OBJ="$(mkvar "$NDRV/Makefile" OBJ)"
  [ -n "$NET_OBJ" ] || { echo "net: no OBJ in $NDRV/Makefile" >&2; exit 2; }
  # -D__STDC__=0: cross gcc defines __STDC__=1, but this SVR4 header set gates
  # <sys/user.h>'s MAXSIG/stack_t behind `#if (__STDC__ - 0 == 0)` (native cc leaves
  # __STDC__ unset) and <sys/immu.h> uses `void` prototypes -traditional can't parse.
  # Same knob section 7b applies to filesys.o/kernel.o; matches the native cc that built
  # the staged objects.  The driver's own Makefile omits it because the BOX cc needs no knob.
  echo "  net: cross-compiling $NET_OBJ (CFLAGS from driver Makefile: $NET_CFLAGS; +\ -D__STDC__=0)"
  ( cd "$NDRV"
    rm -f $NET_OBJ exp
    for o in $NET_OBJ; do
      c="${o%.o}.c"
      [ -f "$c" ] || { echo "net: missing source $c for $o" >&2; exit 2; }
      "$CC" -c $NET_CFLAGS -D__STDC__=0 "$c" -o "$o"
    done
    "$LD" -r -o exp $NET_OBJ
  )
  echo "  amiga/driver/$NET_SUBDIR/exp: $(file "$NDRV/exp" | sed 's/^[^:]*: //')"

  # register <subdir>/exp in amiga/driver/Makefile OBJ (before the stock `aen/exp` line;
  # anchor mirrors the driver's tools/patch-makefile.sh) + append the `cd <subdir>; $(MAKE)` build rule.
  DMK="$BUILD/amiga/driver/Makefile"
  if grep -q "$NET_SUBDIR/exp" "$DMK"; then
    echo "  driver/Makefile already lists $NET_SUBDIR/exp (unexpected on a fresh copy) -- skipping"
  else
    NET_SUBDIR="$NET_SUBDIR" awk '
      $0 ~ ("(^|[ \t])" ENVIRON["NET_SUBDIR"] "/exp") { print; next }
      /aen\/exp/ && !done { printf "\t  %s/exp \\\n", ENVIRON["NET_SUBDIR"]; done=1; print; next }
      { print }
      END {
        if (!done) print "DMK_NOANCHOR" > "/dev/stderr"
        printf "\n%s/exp :\n\tcd %s; $(MAKE)\n", ENVIRON["NET_SUBDIR"], ENVIRON["NET_SUBDIR"]
      }
    ' "$DMK" > "$DMK.new" 2> "$WORK/driverMakefile.awkerr" || true
    if grep -q DMK_NOANCHOR "$WORK/driverMakefile.awkerr" 2>/dev/null; then
      echo "FATAL: no 'aen/exp' OBJ anchor in $DMK -- cannot register $NET_SUBDIR/exp" >&2
      exit 1
    fi
    mv "$DMK.new" "$DMK"
    echo "  amiga/driver/Makefile: OBJ += $NET_SUBDIR/exp (before aen/exp) + build rule appended"
  fi
fi

# === 5. relink the UNCHANGED amiga sub-exps from their staged .o =============
# (ml has no C source at all -- its objects are hand assembly; console carries
#  generated keymap/font objects; none of these change for a SCSI driver, so we
#  ld -r their staged .o with the cross ld, faithfully per each subdir Makefile.)
echo "--- relinking unchanged amiga sub-exps from staged .o ---"
relink_dir amiga/ml     OBJS
relink_dir amiga/console OBJ
relink_dir amiga/driver OBJ                        # OBJ includes staged aen/exp
relink_dir amiga/floppy OBJ
relink_dir amiga/kernel OBJ

# === 6. amiga/exp = ld -r of the six sub-exps ===============================
AMIGA_O="$(mkvar "$BUILD/amiga/Makefile" O)"
echo "--- linking amiga/exp <- $AMIGA_O ---"
( cd "$BUILD/amiga"; "$LD" -r -o exp $AMIGA_O )
echo "  amiga/exp: $(file "$BUILD/amiga/exp" | sed 's/^[^:]*: //')"

# === 7. fs/exp, master.d/exp, local/exp -- relink staged blobs/.o ===========
echo "--- relinking fs / master.d / local exps from staged blobs ---"

# --- 7a. stage each fstype's PREBUILT exp into fs/<name>/exp and register it in the
# fs/Makefile OPT_SUBEXP list (copy-not-compile: the exp is the cross-repo contract).
# Every stock fs/<sub>/ is already a prebuilt exp blob, so fs/<name>/exp is the SAME
# shape -- <name> is just the first one sourced from a sibling repo.  The OPT_SUBEXP
# edit adds one `\t\t<name>/exp` line per record (the terminal line carries no trailing
# backslash), so the mkvar in 7c folds them into fs/exp with no further change.
if [ "${#FS_NAMES[@]}" -gt 0 ]; then
  FS_MK_ADD=""; nfs="${#FS_NAMES[@]}"
  for i in "${!FS_NAMES[@]}"; do
    mkdir -p "$BUILD/fs/${FS_NAMES[$i]}"
    cp "${FS_EXPS[$i]}" "$BUILD/fs/${FS_NAMES[$i]}/exp"
    echo "  staged fs/${FS_NAMES[$i]}/exp <- ${FS_EXPS[$i]}  ($(file "$BUILD/fs/${FS_NAMES[$i]}/exp" | sed 's/^[^:]*: //'))"
    if [ "$i" -lt "$((nfs-1))" ]; then
      FS_MK_ADD="${FS_MK_ADD}$(printf '\t\t%s/exp \\\n' "${FS_NAMES[$i]}")"
    else
      FS_MK_ADD="${FS_MK_ADD}$(printf '\t\t%s/exp' "${FS_NAMES[$i]}")"
    fi
  done
  FS_MK_ADD="$FS_MK_ADD" awk '
    /^OPT_SUBEXP[ \t]*=/ { inblk=1 }
    {
      if (inblk && $0 !~ /\\[ \t]*$/) { print $0 " \\"; printf "%s\n", ENVIRON["FS_MK_ADD"]; inblk=0; next }
      print
    }
  ' "$BUILD/fs/Makefile" > "$BUILD/fs/Makefile.new"
  mv "$BUILD/fs/Makefile.new" "$BUILD/fs/Makefile"
  echo "  fs/Makefile OPT_SUBEXP += $(for i in "${!FS_NAMES[@]}"; do printf '%s/exp ' "${FS_NAMES[$i]}"; done)"

  # --- 7b. inject the vfssw[] row(s) + extern(s) into master.d/filesys.c and RECOMPILE
  # filesys.o BEFORE 7c's relink_dir ld -r's it.  This is the silent-vanish trap:
  # editing filesys.c WITHOUT rebuilding the object drops the vfssw row with NO link
  # error.  The recompile needs -D__STDC__=0: this old SVR4 header set gates
  # <sys/signal.h>'s MAXSIG/stack_t behind `#if (__STDC__ - 0 == 0)` (K&R/native cc),
  # while <sys/immu.h> uses `void` prototypes that gcc -traditional cannot parse.
  # -D__STDC__=0 (still non-traditional) satisfies both -- prototypes parse AND MAXSIG is
  # defined -- matching the native Amix cc (which leaves __STDC__ unset) that built the
  # staged filesys.o.  The extern goes just before `struct vfssw vfssw[] = {`; each row
  # goes just before that table's closing `};` (nfstype = sizeof(vfssw)/... recomputes).
  FS_EXTERNS="$FS_EXTERNS" FS_VFSSW="$FS_VFSSW" awk '
    BEGIN { ext=ENVIRON["FS_EXTERNS"]; rows=ENVIRON["FS_VFSSW"] }
    (!extdone && $0 ~ /^struct[ \t]+vfssw[ \t]+vfssw\[\][ \t]*=[ \t]*\{/) {
      printf "%s", ext; extdone=1; invf=1; print; next
    }
    (invf && !rowdone && $0 ~ /^[ \t]*};/) {
      printf "%s", rows; rowdone=1; invf=0; print; next
    }
    { print }
    END {
      if (!extdone) print "FSSW_NOEXT" > "/dev/stderr"
      if (!rowdone) print "FSSW_NOROW" > "/dev/stderr"
    }
  ' "$BUILD/master.d/filesys.c" > "$BUILD/master.d/filesys.c.new" 2> "$WORK/filesys.awkerr" || true
  if grep -q 'FSSW_NOEXT\|FSSW_NOROW' "$WORK/filesys.awkerr" 2>/dev/null; then
    echo "FATAL: could not anchor the vfssw injection in master.d/filesys.c:" >&2
    cat "$WORK/filesys.awkerr" >&2
    exit 1
  fi
  mv "$BUILD/master.d/filesys.c.new" "$BUILD/master.d/filesys.c"
  echo "  master.d/filesys.c: injected vfssw row(s) + extern(s) for: ${FS_NAMES[*]}"
  compile_patched_obj master.d filesys.c filesys.o "-D__STDC__=0"
fi

# --- 7b-net. wire the net driver into master.d/kernel.c cdevsw[] + RECOMPILE kernel.o ==
# HOST-SIDE equivalent of the net driver's tools/patch-kernel.sh: (1) add `extern struct streamtab
# <streamtab>;` right after the stock `extern struct streamtab aeninfo;`, and (2) claim the
# free cdevsw slot tagged /*<major>*/ -- swap its `nostr` for `&<streamtab>` and retag it
# /*<major>=<subdir>*/.  Same silent-vanish trap as filesys.o: editing kernel.c
# WITHOUT rebuilding kernel.o drops the streamtab wiring with NO link error, so we recompile
# kernel.o here (with -D__STDC__=0, as for filesys.o) BEFORE 7c's relink_dir ld -r's it.
if [ -n "$NET_DIR" ]; then
  KC="$BUILD/master.d/kernel.c"
  grep -q "extern struct streamtab aeninfo;" "$KC" \
    || { echo "FATAL: no 'extern struct streamtab aeninfo;' anchor in $KC" >&2; exit 1; }
  # the target slot must currently be the FREE `nostr` row tagged /*<major>*/
  grep -Eq "nostr,nullflag,[[:space:]]*/\*${NET_MAJOR}\*/" "$KC" \
    || { echo "FATAL: cdevsw slot $NET_MAJOR is not the free 'nostr' row in $KC (already claimed?)" >&2; exit 1; }
  NET_STREAMTAB="$NET_STREAMTAB" NET_MAJOR="$NET_MAJOR" NET_SUBDIR="$NET_SUBDIR" awk '
    { line=$0 }
    (!ext && line ~ /extern[ \t]+struct[ \t]+streamtab[ \t]+aeninfo;/) {
      print line
      print "extern struct streamtab " ENVIRON["NET_STREAMTAB"] ";\t/* " ENVIRON["NET_SUBDIR"] ": added by build-cross-kernel.sh */"
      ext=1; next
    }
    (!slot && line ~ ("nostr,nullflag,[ \t]*/\\*" ENVIRON["NET_MAJOR"] "\\*/")) {
      sub(/nostr/, "\\&" ENVIRON["NET_STREAMTAB"], line)
      sub("/\\*" ENVIRON["NET_MAJOR"] "\\*/", "/*" ENVIRON["NET_MAJOR"] "=" ENVIRON["NET_SUBDIR"] "*/", line)
      print line; slot=1; next
    }
    { print }
    END {
      if (!ext)  print "KC_NOEXT"  > "/dev/stderr"
      if (!slot) print "KC_NOSLOT" > "/dev/stderr"
    }
  ' "$KC" > "$KC.new" 2> "$WORK/kernelc.awkerr" || true
  if grep -q 'KC_NOEXT\|KC_NOSLOT' "$WORK/kernelc.awkerr" 2>/dev/null; then
    echo "FATAL: could not anchor the kernel.c net edit:" >&2
    cat "$WORK/kernelc.awkerr" >&2
    exit 1
  fi
  mv "$KC.new" "$KC"
  echo "  master.d/kernel.c: extern $NET_STREAMTAB + cdevsw[$NET_MAJOR].d_str=&$NET_STREAMTAB (/*$NET_MAJOR=$NET_SUBDIR*/)"
  compile_patched_obj master.d kernel.c kernel.o "-D__STDC__=0"
fi

# --- 7b-carve. (S5-10, --carve-fs) ufs and/or s5 out of the base: their exps leave fs/Makefile's OPT_SUBEXP, their
# vfssw rows leave master.d/filesys.c (the table's later indices shift: kernel/dlm's call, C4-6), and s5's inoinit leaves
# master.d/kernel.c's init_tbl (the s5 module calls it before vfs_register). Both objects are recompiled here, for
# the same silent-vanish reason as 7b. The stock exps the modules wrap are the sysroot's, hashed against the tree's.
if [ -n "$CARVE_FS" ]; then
  mkdir -p "$WORK/carve"; : > "$WORK/carve/stock.sha256"
  for f in ${CARVE_FS//,/ }; do
    a="$(sha256sum < "$SYSROOT_SYS/fs/$f/exp" | cut -c1-64)"; b="$(sha256sum < "$BUILD/fs/$f/exp" | cut -c1-64)"
    [ "$a" = "$b" ] || { echo "FATAL: fs/$f/exp in the tree ($b) is not the sysroot's ($a)" >&2; exit 1; }
    echo "$a  fs/$f/exp" >> "$WORK/carve/stock.sha256"
  done
  echo "$(sha256sum < "$SYSROOT_SYS/master.d/filesys.o" | cut -c1-64)  master.d/filesys.o (stock, the vfssw rows' source)" >> "$WORK/carve/stock.sha256"
  python3 - "$BUILD" "$CARVE_FS" <<'PYC' || exit 1
import re, sys
b, carve = sys.argv[1], sys.argv[2].split(",")
def fail(m): sys.exit("FATAL: --carve-fs: " + m)
# fs/Makefile: the OPT_SUBEXP assignment (continuation lines folded) without the carved exps
mk = open(b + "/fs/Makefile").read().split("\n"); out, i, done = [], 0, False
while i < len(mk):
    if not done and re.match(r"OPT_SUBEXP[ \t]*=", mk[i]):
        blk = [mk[i]]
        while blk[-1].rstrip().endswith("\\"):
            i += 1; blk.append(mk[i])
        toks = " ".join(l.rstrip().rstrip("\\") for l in blk).split("=", 1)[1].split()
        keep = [t for t in toks if t not in ["%s/exp" % f for f in carve]]
        if len(keep) != len(toks) - len(carve):
            fail("OPT_SUBEXP %s lacks one of %s" % (toks, carve))
        out.append("OPT_SUBEXP = " + " ".join(keep)); done = True
    else:
        out.append(mk[i])
    i += 1
if not done:
    fail("no OPT_SUBEXP in fs/Makefile")
open(b + "/fs/Makefile", "w").write("\n".join(out))
# master.d/filesys.c: the carved filesystems' vfssw rows, exactly one each
fsc = open(b + "/master.d/filesys.c").read().split("\n")
name = {"s5": "NAMES5", "ufs": "NAMEUFS"}
for f in carve:
    hit = [l for l in fsc if re.match(r"\s*\{\s*%s\s*," % name[f], l)]
    if len(hit) != 1:
        fail("master.d/filesys.c has %d vfssw rows for %s" % (len(hit), name[f]))
    fsc.remove(hit[0])
open(b + "/master.d/filesys.c", "w").write("\n".join(fsc))
# master.d/kernel.c: s5's inoinit leaves init_tbl (the module calls it)
if "s5" in carve:
    kc = open(b + "/master.d/kernel.c").read().split("\n")
    hit = [l for l in kc if l.strip() == "inoinit,"]
    if len(hit) != 1:
        fail("master.d/kernel.c has %d init_tbl inoinit entries" % len(hit))
    kc.remove(hit[0]); open(b + "/master.d/kernel.c", "w").write("\n".join(kc))
print("  carved %s: fs/Makefile OPT_SUBEXP, master.d/filesys.c vfssw rows%s" % (",".join(carve), ", master.d/kernel.c init_tbl inoinit" if "s5" in carve else ""))
PYC
  compile_patched_obj master.d filesys.c filesys.o "-D__STDC__=0"
  case ",$CARVE_FS," in *,s5,*) compile_patched_obj master.d kernel.c kernel.o "-D__STDC__=0" ;; esac
fi

# HARD CHECK (quirk 91): in an object holding the ufs code -- the wrapped ufs object, the base unix, the ufs module --
# ufs_vptrunz is defined once, qz_magic is there, ufs_itrunc is ufs_vptrunz's only caller and no longer calls
# pvn_vptrunc itself, and ufs_vptrunz does.  A lost rename leaves the stock call and quirk 91 in place, silently.
qz_check() {   # qz_check FILE [NM OBJDUMP]: the packaged module needs gcc14's m68k-elf- tools (2.8.1's cannot read it)
  local o="$1" nm="${2:-$NM}" od="${3:-$OBJDUMP}" calls
  [ "$("$nm" "$o" | awk '$3=="ufs_vptrunz" && $2=="T"' | wc -l)" = 1 ] || { echo "[FAIL] ufs-tailzero: $o does not define ufs_vptrunz once" >&2; exit 1; }
  "$nm" "$o" | awk '$3=="qz_magic" && $2=="D" {f=1} END{exit !f}' || { echo "[FAIL] ufs-tailzero: no qz_magic in $o" >&2; exit 1; }
  calls="$("$od" -dr "$o" | awk '/^[0-9a-f]+ <[^>]*>:$/ {fn=substr($2, 2, length($2) - 3)} /R_68K_32[ \t]+(pvn_vptrunc|ufs_vptrunz)$/ {print fn ">" $NF}' | LC_ALL=C sort -u)"
  echo "$calls" | grep -qx 'ufs_itrunc>ufs_vptrunz' || { echo "[FAIL] ufs-tailzero: ufs_itrunc does not call ufs_vptrunz in $o" >&2; exit 1; }
  ! echo "$calls" | grep -qx 'ufs_itrunc>pvn_vptrunc' || { echo "[FAIL] ufs-tailzero: ufs_itrunc still calls pvn_vptrunc in $o" >&2; exit 1; }
  [ "$(echo "$calls" | grep -c '>ufs_vptrunz$')" = 1 ] || { echo "[FAIL] ufs-tailzero: ufs_vptrunz has callers other than ufs_itrunc in $o" >&2; exit 1; }
  echo "$calls" | grep -qx 'ufs_vptrunz>pvn_vptrunc' || { echo "[FAIL] ufs-tailzero: ufs_vptrunz does not call pvn_vptrunc in $o" >&2; exit 1; }
  echo "  [OK] ufs tail zeroing bound in $(basename "$o"): ufs_itrunc -> ufs_vptrunz -> pvn_vptrunc, qz_magic"
}
# --- 7b-qz. (grimoire quirk 91) the ufs object with ufs_itrunc's pvn_vptrunc call wrapped: the stock fs/ufs/exp, its
# reference renamed to ufs_vptrunz (same-length .strtab string), ld -r with src/ufs_vptrunz.c.  A carved ufs module wraps
# this object (step 10's carve); otherwise it replaces the work copy's fs/ufs/exp before 7c relinks fs/exp.
UFS_OBJ="$SYSROOT_SYS/fs/ufs/exp"
if [ "$UFS_TAILZERO" = 1 ]; then
  echo "--- ufs tail zeroing (quirk 91): $KT/src/ufs_vptrunz.c + the stock fs/ufs/exp, pvn_vptrunc -> ufs_vptrunz ---"
  QZ="$WORK/qz"; rm -rf "$QZ"; mkdir -p "$QZ"
  ( cd "$BUILD/fs/ufs"
    "$CC" -c -O $CFLAGS_K -I../.. "$KT/src/ufs_vptrunz.c" -o "$QZ/ufs_vptrunz.o"
    AMIX_MUL64=keep "$CC" -c -O $CFLAGS_K -I../.. "$KT/src/ufs_vptrunz.c" -o "$QZ/ufs_vptrunz-mul64keep.o" )
  cmp -s "$QZ/ufs_vptrunz.o" "$QZ/ufs_vptrunz-mul64keep.o" \
    || { echo "--ufs-tailzero: ufs_vptrunz.o differs with AMIX_MUL64=keep -- the wrapper rewrote a multiply in it" >&2; exit 1; }
  GOT="$("$NM" "$QZ/ufs_vptrunz.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOT" = "kzero pvn_vptrunc segkmap segmap_getmap segmap_release" ] || { echo "--ufs-tailzero: ufs_vptrunz.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$QZ/ufs_vptrunz.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "qz_calls qz_cold qz_kzfail qz_magic qz_puterr qz_tail ufs_vptrunz" ] \
    || { echo "--ufs-tailzero: ufs_vptrunz.o exports '$GOTX'" >&2; exit 1; }
  # its only COMMONs are ufs_inode.h's tentatives, which the stock ufs object carries as COMMON too
  [ "$("$NM" "$QZ/ufs_vptrunz.o" | awk '$2=="C"{print $3}' | LC_ALL=C sort | tr '\n' ' ')" = "inodeNINODE iuniqtime ufs_inode " ] \
    || { echo "--ufs-tailzero: ufs_vptrunz.o has COMMONs other than ufs_inode.h's" >&2; exit 1; }
  cp "$SYSROOT_SYS/fs/ufs/exp" "$QZ/ufs-renamed.exp"; chmod u+w "$QZ/ufs-renamed.exp"
  python3 - "$QZ/ufs-renamed.exp" <<'PYQ' || { echo "--ufs-tailzero: could not rename pvn_vptrunc in the ufs object" >&2; exit 1; }
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 1 and b[5] == 2, 'not ELF32 big-endian'
shoff, = struct.unpack_from('>I', b, 32); shentsize, shnum = struct.unpack_from('>HH', b, 46)
sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
hits = []
for s in sh:
    if s[1] != 2:                      # SHT_SYMTAB: the strings its symbols name
        continue
    stroff = sh[s[6]][4]
    for o in range(s[4], s[4] + s[5], 16):
        name, = struct.unpack_from('>I', b, o)
        if bytes(b[stroff + name:b.index(0, stroff + name)]) == b'pvn_vptrunc':
            hits.append(stroff + name)
assert len(hits) == 1, 'symbols named pvn_vptrunc: %d' % len(hits)
assert b.count(b'pvn_vptrunc') == 1, 'pvn_vptrunc appears elsewhere in the object'
b[hits[0]:hits[0] + 11] = b'ufs_vptrunz'
open(p, 'wb').write(b)
PYQ
  D="$(cmp -l "$SYSROOT_SYS/fs/ufs/exp" "$QZ/ufs-renamed.exp" | wc -l)"
  [ "$D" = 4 ] || { echo "--ufs-tailzero: the rename changed $D bytes (want 4: pvn_vptrunc -> ufs_vptrunz)" >&2; exit 1; }
  "$LD" -r -o "$QZ/ufs.exp" "$QZ/ufs-renamed.exp" "$QZ/ufs_vptrunz.o"
  qz_check "$QZ/ufs.exp"
  UFS_OBJ="$QZ/ufs.exp"
  case ",$CARVE_FS," in
    *,ufs,*) echo "  the carved ufs module wraps $UFS_OBJ" ;;
    *) cp "$UFS_OBJ" "$BUILD/fs/ufs/exp"; echo "  fs/ufs/exp in the work copy replaced by $UFS_OBJ" ;;
  esac
else
  echo "--- ufs tail zeroing: --no-ufs-tailzero -- the stock fs/ufs/exp ---"
fi

# --- 7c. relink fs/exp (now incl. any fs/<name>/exp) + master.d/exp (fresh filesys.o) + local/exp
FS_SUB="$(mkvar "$BUILD/fs/Makefile" OPT_SUBEXP)"   # bfs/exp s5/exp ... rfs/exp [+ <fstype>/exp]
( cd "$BUILD/fs"; "$LD" -r -o exp fs.exp $FS_SUB )
echo "  fs/exp: $(file "$BUILD/fs/exp" | sed 's/^[^:]*: //')"
relink_dir master.d OBJS
relink_dir local    OBJS

# === 8. CROSS-COMPILE the config object: amiga/config/$CONFIG.c -> unix.o =====
# config/Makefile does `include $(CONFIGFILE)` ($(ROOT)/stand/CONFIG) -- not staged --
# and compiles every config .c with a uniform CFLAGS macro set.  Only the default
# `unix.c` actually references those macros; fd0unix/c0s1unix/c6s1unix HARDCODE their
# root+swap via makedevice() and ignore them.  So for the fd0unix default the -D
# values below are inert -- rootdev = FD0P = 0x00400008 comes from fd0unix.c itself,
# and it carries no dumpdev (the 4 zero bytes after rootdev are its empty bo_fstype).
# We still pass the Makefile's macro set for the `unix` fallback, with DUMPDEV pinned
# to 0 (NODEV) to match the install donor.  The selected source compiles into the
# `unix.o` link slot the final ld -r references; config values do NOT change the
# relocation structure relsim analyses.
echo "--- cross-compiling amiga/config/$CONFIG.c -> unix.o ---"
( cd "$BUILD/amiga/config"
  "$CC" -c -DSYSV -D_KERNEL -I../.. \
      -DROOTDEV='makedevice(18,16)' \
      -DSWAPDEV='"/dev/dsk/c0d0s2"' \
      -DNSWAP=20479 \
      -DSWPLO=0 \
      -DDUMPDEV=0 \
      -DCHAR_SPECIAL=0 \
      -DDO_SYSDUMP=0 \
      -DNO_INTERACTIVE=1 \
      "$CONFIG.c" -o unix.o
)
echo "  amiga/config/unix.o (from $CONFIG.c): $(file "$BUILD/amiga/config/unix.o" | sed 's/^[^:]*: //')"

# === 8b. ROOTDEV INVARIANT: read `rootdev` back out of the linked config object and
# assert it is the device the config source declares -- computed from the SAME
# makedevice() bit layout the kernel uses (L_BITSMINOR/L_MAXMIN from sys/sysmacros.h),
# never a hardcoded magic number.  This is the guard against the metal-boot PANIC
# (`s5mountroot VOP_OPEN error 6` / `vfs_mountroot errno 30`) that a WRONG baked-in
# root device causes: c6s1unix MUST yield rootdev = C6D0S1 = makedevice(18,22) =
# 0x00480016 (SCSI target 6, slice 1 = c6d0s1, what the metal Z3660 presents).
#   readback:  objdump -t finds rootdev's (section, offset, size); objdump -s dumps that
#              section; we splice `size` big-endian bytes at `offset` -> the stored dev_t.
#   expected:  parse `dev_t rootdev = <TOKEN>;` in the config .c, resolve TOKEN's
#              `#define TOKEN makedevice(maj,min)`, compute (maj<<L_BITSMINOR)|(min&L_MAXMIN).
# A config whose rootdev is a compile-macro (unix.c's ROOTDEV) is REPORT-ONLY (placeholder).
SYSMACROS="$(cd "$SYSROOT_SYS/../include" 2>/dev/null && pwd)/sys/sysmacros.h"
assert_rootdev() { # assert_rootdev <config-name>
  local cfg="$1"
  local cobj="$BUILD/amiga/config/unix.o"
  local csrc="$BUILD/amiga/config/$cfg.c"
  local lbm lmm tok maj min want line sec off sz got actual amaj amin has_define
  [ -f "$SYSMACROS" ] || { echo "FATAL: sys/sysmacros.h not found at $SYSMACROS (cannot derive makedevice layout)" >&2; exit 1; }
  lbm="$(awk '/^#define[ \t]+L_BITSMINOR/{print $3; exit}' "$SYSMACROS")"
  lmm="$(awk '/^#define[ \t]+L_MAXMIN/{print $3; exit}' "$SYSMACROS")"
  [ -n "$lbm" ] && [ -n "$lmm" ] || { echo "FATAL: could not read L_BITSMINOR/L_MAXMIN from $SYSMACROS" >&2; exit 1; }

  # read the stored dev_t back out of the config object
  line="$("$OBJDUMP" -t "$cobj" | awk '$NF=="rootdev"{print; exit}')"
  [ -n "$line" ] || { echo "FATAL: no 'rootdev' symbol in $cobj" >&2; exit 1; }
  off="$(printf '%s\n' "$line" | awk '{print $1}')"
  sz="$(printf '%s\n' "$line" | awk '{print $(NF-1)}')"
  sec="$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\./){print $i; exit}}')"
  got="$("$OBJDUMP" -s -j "$sec" "$cobj" | python3 -c '
import sys,re
off=int(sys.argv[1],16); n=int(sys.argv[2],16); b={}
for ln in sys.stdin:
    m=re.match(r"\s*([0-9a-fA-F]+)\s+((?:[0-9a-fA-F]{2,8}\s+){1,4})",ln)
    if not m: continue
    a=int(m.group(1),16); i=0
    for w in m.group(2).split():
        w=w if len(w)%2==0 else "0"+w
        for j in range(0,len(w),2): b[a+i]=w[j:j+2]; i+=1
if any(off+k not in b for k in range(n)): sys.exit("readback: missing bytes")
print("".join(b[off+k] for k in range(n)))
' "0x$off" "0x$sz")"
  [ -n "$got" ] || { echo "FATAL: could not read rootdev bytes from $cobj" >&2; exit 1; }
  actual=$((16#$got))
  amaj=$(( (actual >> lbm) & 0xff )); amin=$(( actual & lmm ))
  printf '  rootdev readback: 0x%08x  (major=%d minor=%d)  [%s .%s+0x%s, %s bytes]\n' \
      "$actual" "$amaj" "$amin" "$cfg" "${sec#.}" "$off" "$((16#$sz))"

  # resolve the EXPECTED value from the config source
  tok="$(sed -n 's/.*rootdev[ \t]*=[ \t]*\([A-Za-z0-9_]*\).*/\1/p' "$csrc" | head -1)"
  [ -n "$tok" ] || { echo "FATAL: no 'rootdev =' initializer in $csrc" >&2; exit 1; }
  # Does the SOURCE locally #define this token?  If NOT, the token is an external compile
  # macro (the `unix` placeholder's -DROOTDEV) -- the ONLY case allowed to skip the metal
  # assertion.  If it IS #defined but we cannot parse decimal makedevice() args (hex or
  # symbolic), that is a HARDCODED config with an unverifiable value and must be FATAL.
  has_define=""; grep -qE "^[[:space:]]*#define[[:space:]]+$tok[[:space:]]" "$csrc" && has_define=1
  read -r maj min < <(sed -n "s/.*#define[ \t]\+$tok[ \t]\+makedevice(\([0-9]\+\)[ \t]*,[ \t]*\([0-9]\+\)).*/\1 \2/p" "$csrc" | head -1)
  if [ -z "${maj:-}" ] || [ -z "${min:-}" ]; then
    # Expected value UNRESOLVABLE -- fail CLOSED.  The REPORT-ONLY downgrade is whitelisted
    # to EXACTLY ONE config: the `unix` placeholder, whose rootdev is the -DROOTDEV compile
    # macro (no local #define).  EVERY hardcoded config (c6s1unix/c0s1unix/...) MUST resolve
    # to a concrete value; and a readback that presents a metal SCSI-HD root (major 18) can
    # never be waved through.  So a future non-decimal/symbolic makedevice() initializer
    # FATALs here instead of silently self-disabling the metal-panic guard.
    if [ "$cfg" = "unix" ] && [ -z "$has_define" ] && [ "$amaj" -ne 18 ]; then
      echo "  rootdev: config 'unix' takes rootdev from the -DROOTDEV compile macro ($tok) -- placeholder, REPORT-ONLY (no metal assertion)"
      return 0
    fi
    if [ "$cfg" = "unix" ] && [ -z "$has_define" ]; then
      # the `unix` placeholder resolved to a SCSI-HD major (18) via -DROOTDEV: surface it
      # loudly rather than silently skip -- it is still not asserted, but it is visible.
      echo "  rootdev: config 'unix' (-DROOTDEV compile macro $tok) links to major=$amaj minor=$amin -- placeholder REPORT-ONLY, but note it resolves to a metal SCSI major" >&2
      return 0
    fi
    echo "FATAL: rootdev expected value UNRESOLVABLE for config '$cfg' (token '$tok' is not a decimal makedevice() #define)" >&2
    echo "       readback says major=$amaj minor=$amin -- refusing to downgrade a hardcoded config to REPORT-ONLY;" >&2
    echo "       resolve '$tok' to a decimal makedevice(major,minor) #define, or the metal-panic guard is disarmed." >&2
    exit 1
  fi
  want=$(( (maj << lbm) | (min & lmm) ))
  if [ "$actual" -ne "$want" ]; then
    printf 'FATAL: rootdev MISMATCH -- linked 0x%08x but %s source says %s = makedevice(%d,%d) = 0x%08x\n' \
        "$actual" "$cfg" "$tok" "$maj" "$min" "$want" >&2
    echo "       a metal boot with this kernel would PANIC (s5mountroot VOP_OPEN / vfs_mountroot)." >&2
    exit 1
  fi
  if [ "$maj" -eq 18 ]; then
    # this SVR4 SCSI-disk minor layout: minor = target + slice*16 (c6d0s1 -> 6 + 1*16 = 22)
    printf '  rootdev ASSERT OK: metal SCSI-HD root %s = makedevice(%d,%d) = 0x%08x (c%dd0s%d: target %d slice %d)\n' \
        "$tok" "$maj" "$min" "$want" "$(( min & 0x0f ))" "$(( min >> 4 ))" "$(( min & 0x0f ))" "$(( min >> 4 ))"
  elif [ "$maj" -eq 16 ]; then
    printf '  rootdev ASSERT OK: floppy/install root %s = makedevice(%d,%d) = 0x%08x (non-metal, as expected for %s)\n' \
        "$tok" "$maj" "$min" "$want" "$cfg"
  else
    printf '  rootdev ASSERT OK: %s = makedevice(%d,%d) = 0x%08x (matches source; major %d)\n' \
        "$tok" "$maj" "$min" "$want" "$maj"
  fi
}
assert_rootdev "$CONFIG"

# === 9. final relocatable link: ld -o unix -r $(OBJS) amiga/config/unix.o ====
# OBJS order straight from usr/sys/Makefile (with $(PLATFORM) -> amiga).
TOP_OBJS="$(mkvar "$BUILD/Makefile" OBJS | sed 's/\$(PLATFORM)/amiga/g')"
# When an fstype is staged, the fs's uint64 offset math needs the m68k soft-arith
# helpers (__udivdi3/__umoddi3/__lshrdi3) the stock kernel never pulls -- resolve them
# from the cross libgcc.a.  ld pulls only the needed archive members (even under -r), so
# this adds nothing when the fs does not reference them.
FS_LGCC=""
if [ "${#FS_NAMES[@]}" -gt 0 ]; then
  FS_LGCC="$(ls "$CROSS_ROOT"/lib/gcc-lib/m68k-cbm-sysv4/*/libgcc.a 2>/dev/null | head -1)"
  [ -n "$FS_LGCC" ] && [ -f "$FS_LGCC" ] || { echo "fstype staged but cross libgcc.a not found under $CROSS_ROOT/lib/gcc-lib (need __udivdi3 etc.)" >&2; exit 2; }
  echo "--- fstype present: 64-bit soft-arith resolved from $FS_LGCC ---"
fi
# A module kernel exports libgcc's helpers to its modules (the core's abi/k30 lists name them: __udivdi3 ...): link them
# whether or not an fstype references them (with --no-fstypes nothing in the base does, and ld -r pulls only what is named).
LGCC_U=""
if [ -n "$DLM_CORE" ]; then
  for n in $(awk -v m="$KABI_MINOR" '$1 ~ /^__/ && ($3 == "" || $3 + 0 <= m) {print $1}' "$DLM_CORE/abi/k30/ddi.list" "$DLM_CORE/abi/k30/core.list" 2>/dev/null | sort -u); do LGCC_U="$LGCC_U -u $n"; done
  if [ -n "$LGCC_U" ] && [ -z "$FS_LGCC" ]; then
    FS_LGCC="$(ls "$CROSS_ROOT"/lib/gcc-lib/m68k-cbm-sysv4/*/libgcc.a 2>/dev/null | head -1)"
    [ -n "$FS_LGCC" ] && [ -f "$FS_LGCC" ] || { echo "the module core exports libgcc names ($LGCC_U) but the cross libgcc.a is not found" >&2; exit 2; }
  fi
  [ -z "$LGCC_U" ] || echo "--- module core: libgcc names the kernel exports linked from $FS_LGCC:$LGCC_U ---"
fi
RTH1_OBJ=""
if [ -n "$RTH1_C" ]; then
  # === 8c. the RTH1 kernel half (D-2): compile + gate rth1.o ============================
  RTH1_C="$(cd "$(dirname "$RTH1_C")" && pwd)/$(basename "$RTH1_C")"
  RTH1_DIR="$(dirname "$RTH1_C")"; RTH1_HOOK="$RTH1_DIR/patch_rth1_hook.py"
  # scan060 is the port's test-tools/scan060.py: $PORT's when set, else the port checkout rth1.c sits in
  SCAN060="${PORT:+$PORT/test-tools/scan060.py}"; SCAN060="${SCAN060:-$RTH1_DIR/../test-tools/scan060.py}"
  for f in "$RTH1_C" "$RTH1_HOOK"; do
    [ -f "$f" ] || { echo "--rth1: missing $f" >&2; exit 2; }
  done
  [ -f "$SCAN060" ] || { echo "--rth1: missing $SCAN060 (set PORT to a checkout of the 68040/68060 port, kernel/port/port.pin)" >&2; exit 2; }
  # --dlm: step 8's root hook is rth1.c's own (#ifdef RTH1_DLM: dlm_marc_post once vfs_mountroot returns 0;
  # amix-040-060-port k46-module, ea42b65): an rth1.c without it would build a module kernel that never posts
  [ -z "$DLM_CORE" ] || grep -q 'RTH1_DLM' "$RTH1_C" || { echo "--dlm: $RTH1_C has no RTH1_DLM hook (amix-040-060-port k46-module)" >&2; exit 2; }
  # --sd-cards 4: the port's rth1.c (S4-21, its 42b84a8 on) walks four cards and builds C4-1's root minor and
  # bo_name with -DSDCARDS=4. An older rth1.c has no such form: it is built as it is, and roots on cards 0-1 only
  RTH1_SD4=""
  if [ "$SD_CARDS" = 4 ]; then
    if grep -q '#if SDCARDS > 2' "$RTH1_C"; then RTH1_SD4="-DSDCARDS=4"
    else echo "  WARNING: --sd-cards 4 with a two-card rth1.c ($RTH1_C): a root on card 2 or 3 is not found (the port's S4-21 rth1.c, 42b84a8 on, has the four-card form)"; fi
  fi
  echo "--- rth1: compiling $RTH1_C with the kit's .c.o rule (amiga/alien: -c -O $CFLAGS_K -I../.. -I../inc${RTH1_SD4:+ $RTH1_SD4}) ---"
  ( cd "$BUILD/amiga/alien"
    "$CC" -c -O $CFLAGS_K -I../.. -I../inc ${DLM_CORE:+-DRTH1_DLM} $RTH1_SD4 "$RTH1_C" -o "$BUILD/rth1.o"
    AMIX_MUL64=keep "$CC" -c -O $CFLAGS_K -I../.. -I../inc ${DLM_CORE:+-DRTH1_DLM} $RTH1_SD4 "$RTH1_C" -o "$BUILD/rth1-mul64keep.o" )
  cmp -s "$BUILD/rth1.o" "$BUILD/rth1-mul64keep.o" \
    || { echo "--rth1: rth1.o differs with AMIX_MUL64=keep -- the wrapper rewrote a multiply in it" >&2; exit 1; }
  echo "  rth1.o $(sha256sum "$BUILD/rth1.o" | cut -c1-16) == the AMIX_MUL64=keep build (no 64-bit multiply site)"
  "$OBJDUMP" -h "$BUILD/rth1.o" | awk '$2 ~ /^\.rodata/ {print "  note: rth1.o carries " $2 " (folded by elf2brel)"}'
  GOT="$("$NM" "$BUILD/rth1.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  # the port's rth1.c from f0a6011 on also calls rth1_nomarc() before rth1_apply on a module kernel (S4-23):
  # tools/rth1-nomarc030.s provides it, empty, and step 7h of dlm-core-link.sh retargets it to dlm_marc_root
  NOMARC=""; [ -z "$DLM_CORE" ] || ! echo " $GOT " | grep -q " rth1_nomarc " || NOMARC=1
  # from bb6eaf6 on it also copies the AXL1 record's rootfs name into rootfstype (kernel/dlm C4-3 section 3), bounded
  # by its ROOTFSTYPE_LEN, which must equal rootfstype's size in this base (master.d/kernel.o, char[15] in the stock)
  ROOTFS=""
  if [ -n "$DLM_CORE" ] && echo " $GOT " | grep -q " rootfstype "; then
    RL="$(sed -n 's/^#define[[:space:]]*ROOTFSTYPE_LEN[[:space:]]*\([0-9]*\).*/\1/p' "$RTH1_C" | head -1)"
    KL="$("$OBJDUMP" -t "$BUILD/master.d/kernel.o" | awk '$NF=="rootfstype" && $(NF-2)==".data" {print $(NF-1)}')"
    [ -n "$RL" ] && [ -n "$KL" ] && [ "$RL" = "$((16#$KL))" ] \
      || { echo "--rth1: rth1.c bounds rootfstype at '${RL:-?}' bytes, the base's rootfstype is '${KL:-?}' (hex)" >&2; exit 1; }
    ROOTFS=1; echo "  rth1.o writes rootfstype (the AXL1 rootfs name), bounded at $RL bytes = the base's rootfstype"
  fi
  # from 88dcfc0 on (S5-46, kernel/dlm C4-1 v6 section 5.2) it matches a motherboard record by its id, from sd's name for the
  # card (sd.c.in's sdhardwarename, kinfo's rule): one more import
  SDHW=""; ! echo " $GOT " | grep -q " sdhardwarename " || SDHW=1
  [ "$GOT" = "bootinfo ${DLM_CORE:+dlm_marc_post }printf rootdev ${ROOTFS:+rootfstype }${NOMARC:+rth1_nomarc }sdcardbase ${SDHW:+sdhardwarename }sdopen swapfile vfs_mountroot" ] \
    || { echo "--rth1: rth1.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$BUILD/rth1.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "rth1_apply rth1_mountroot rth1_used rth1_why" ] || { echo "--rth1: rth1.o exports '$GOTX'" >&2; exit 1; }
  [ -z "$("$NM" "$BUILD/rth1.o" | awk '$2=="C"')" ] || { echo "--rth1: rth1.o has COMMON symbols" >&2; exit 1; }
  LC_ALL=C m68k-linux-gnu-objdump -d "$BUILD/rth1.o" > "$BUILD/rth1.lst"
  SCAN="$(python3 "$SCAN060" "$BUILD/rth1.lst")"
  echo "$SCAN" | grep -q 'CLEAN -- no candidate found' || { echo "--rth1: scan060: rth1.o is not CLEAN" >&2; echo "$SCAN" >&2; exit 1; }
  echo "  rth1.o: imports/exports exact, no COMMON, scan060 CLEAN"
  RTH1_OBJ="rth1.o"
  if [ -n "$NOMARC" ]; then
    "$AS" -o "$BUILD/rth1-nomarc.o" "$KT/tools/rth1-nomarc030.s" || { echo "--rth1: rth1-nomarc030.s did not assemble" >&2; exit 1; }
    RTH1_OBJ="rth1.o rth1-nomarc.o"
    echo "  rth1.o calls rth1_nomarc before rth1_apply: tools/rth1-nomarc030.s (empty) joins the link"
  fi
fi
KINFO_OBJ=""
if [ -n "$KINFO_C" ]; then
  # === 8d. /dev/kinfo (C2-1): compile + gate kinfo.o, the build id stamped in ==================
  [[ "$KINFO_BUILD" =~ ^68030-[0-9]{6}-[0-9]{2}$ ]] || { echo "--kinfo: --kinfo-build '$KINFO_BUILD' is not 68030-yymmdd-nn" >&2; exit 2; }
  KINFO_C="$(cd "$(dirname "$KINFO_C")" && pwd)/$(basename "$KINFO_C")"
  [ -n "${PORT:-}" ] || { echo "--kinfo: PORT is not set: kinfo.o is gated by the port's test-tools/scan060.py (set PORT to a checkout of the 68040/68060 port, kernel/port/port.pin)" >&2; exit 2; }
  SCAN060="$PORT/test-tools/scan060.py"
  for f in "$KINFO_C" "$SCAN060"; do
    [ -f "$f" ] || { echo "--kinfo: missing $f" >&2; exit 2; }
  done
  echo "--- kinfo: compiling $KINFO_C (build id $KINFO_BUILD) with the kit's .c.o rule ---"
  ( cd "$BUILD/amiga/alien"
    "$CC" -c -O $CFLAGS_K -I../.. -I../inc "-DKINFO_BUILD=\"$KINFO_BUILD\"" ${DLM_CORE:+"-DKINFO_KABI=\"$KABI\"" -DKINFO_DLM} "$KINFO_C" -o "$BUILD/kinfo.o"
    AMIX_MUL64=keep "$CC" -c -O $CFLAGS_K -I../.. -I../inc "-DKINFO_BUILD=\"$KINFO_BUILD\"" ${DLM_CORE:+"-DKINFO_KABI=\"$KABI\"" -DKINFO_DLM} "$KINFO_C" -o "$BUILD/kinfo-mul64keep.o" )
  cmp -s "$BUILD/kinfo.o" "$BUILD/kinfo-mul64keep.o" \
    || { echo "--kinfo: kinfo.o differs with AMIX_MUL64=keep -- the wrapper rewrote a multiply in it" >&2; exit 1; }
  GOT="$("$NM" "$BUILD/kinfo.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOT" = "VSIZOFMEM bootinfo chipmem ${DLM_CORE:+dlm_kinfo_list }sdcardbase sdhardwarename sdopen stext uiomove" ] \
    || { echo "--kinfo: kinfo.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$BUILD/kinfo.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "kinfo_buildid kinfo_kabi kinfoclose kinfoopen kinforead kinfowrite" ] \
    || { echo "--kinfo: kinfo.o exports '$GOTX'" >&2; exit 1; }
  [ -z "$("$NM" "$BUILD/kinfo.o" | awk '$2=="C"')" ] || { echo "--kinfo: kinfo.o has COMMON symbols" >&2; exit 1; }
  LC_ALL=C m68k-linux-gnu-objdump -d "$BUILD/kinfo.o" > "$BUILD/kinfo.lst"
  SCAN="$(python3 "$SCAN060" "$BUILD/kinfo.lst")"
  echo "$SCAN" | grep -q 'CLEAN -- no candidate found' || { echo "--kinfo: scan060: kinfo.o is not CLEAN" >&2; echo "$SCAN" >&2; exit 1; }
  echo "  kinfo.o $(sha256sum "$BUILD/kinfo.o" | cut -c1-16): imports/exports exact, no COMMON, scan060 CLEAN, == the AMIX_MUL64=keep build"
  KINFO_OBJ="kinfo.o"
fi
KZERO_OBJ=""
if [ "$KZERO" = 1 ]; then
  # === 8e. the kzero fault catch (grimoire quirk 90): src/kzero_nofault.s + the stock kzero weakened ======
  echo "--- kzero: assembling $KT/src/kzero_nofault.s; the stock kzero (= bzero) weakened in ml/exp ---"
  "$AS" -o "$BUILD/kzero_nofault.o" "$KT/src/kzero_nofault.s" || { echo "--kzero: kzero_nofault.s did not assemble" >&2; exit 1; }
  GOT="$("$NM" "$BUILD/kzero_nofault.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOT" = "bzero cmn_err u" ] || { echo "--kzero: kzero_nofault.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$BUILD/kzero_nofault.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "kzero kzr_alien_n kzr_calls kzr_fail_n kzr_last_addr kzr_magic" ] \
    || { echo "--kzero: kzero_nofault.o exports '$GOTX'" >&2; exit 1; }
  # the stock ml/exp defines kzero and bzero at the same .text+0x302: kzero becomes weak, bzero stays as it is
  [ "$("$NM" "$BUILD/ml/exp" | awk '$3=="kzero" || $3=="bzero" {print $1 $2 $3}' | LC_ALL=C sort | tr '\n' ' ')" = "00000302Tbzero 00000302Tkzero " ] \
    || { echo "--kzero: ml/exp does not define kzero and bzero together at 0x302 (not the stock ml/exp)" >&2; exit 1; }
  cp "$BUILD/ml/exp" "$BUILD/ml/exp.pre-kzero"
  python3 - "$BUILD/ml/exp" <<'PYW' || { echo "--kzero: could not weaken kzero in ml/exp" >&2; exit 1; }
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 1 and b[5] == 2, 'not ELF32 big-endian'
shoff, = struct.unpack_from('>I', b, 32); shentsize, shnum = struct.unpack_from('>HH', b, 46)
sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
hits = []
for s in sh:
    if s[1] != 2:                      # SHT_SYMTAB
        continue
    stroff = sh[s[6]][4]
    for o in range(s[4], s[4] + s[5], 16):
        name, = struct.unpack_from('>I', b, o)
        if bytes(b[stroff + name:b.index(0, stroff + name)]) == b'kzero' and b[o + 12] >> 4 == 1:   # STB_GLOBAL
            hits.append(o)
assert len(hits) == 1, 'global kzero symbols: %d' % len(hits)
b[hits[0] + 12] = (2 << 4) | (b[hits[0] + 12] & 15)                                                # STB_WEAK
open(p, 'wb').write(b)
PYW
  D="$(cmp -l "$BUILD/ml/exp.pre-kzero" "$BUILD/ml/exp" | wc -l)"
  [ "$D" = 1 ] || { echo "--kzero: weakening changed $D bytes of ml/exp (want exactly 1)" >&2; exit 1; }
  [ "$("$NM" "$BUILD/ml/exp" | awk '$3=="kzero" || $3=="bzero" {print $1 $2 $3}' | LC_ALL=C sort | tr '\n' ' ')" = "00000302Tbzero 00000302Wkzero " ] \
    || { echo "--kzero: ml/exp after the weakening is not 'bzero T, kzero W' at 0x302" >&2; exit 1; }
  rm -f "$BUILD/ml/exp.pre-kzero"
  echo "  kzero_nofault.o $(sha256sum "$BUILD/kzero_nofault.o" | cut -c1-16): imports/exports exact; ml/exp: kzero weak (1 byte), bzero strong"
  KZERO_OBJ="kzero_nofault.o"
else
  echo "--- kzero: --no-kzero -- the stock kzero (= bzero), no fault catch ---"
fi
FPUG_OBJ=""
if [ "$FPU_GATE" = 1 ]; then
  # === 8f. the sendsig FPU gate (grimoire quirk 74): src/fpugate030.s; the relocation is retargeted after the link ===
  echo "--- fpu gate: assembling $KT/src/fpugate030.s (fpu_setup_gated, for sendsig) ---"
  "$AS" -o "$BUILD/fpugate030.o" "$KT/src/fpugate030.s" || { echo "--fpu-gate: fpugate030.s did not assemble" >&2; exit 1; }
  GOT="$("$NM" "$BUILD/fpugate030.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOT" = "fpu_present fpu_setup" ] || { echo "--fpu-gate: fpugate030.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$BUILD/fpugate030.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "fpg_magic fpg_pass_n fpg_skip_n fpu_setup_gated" ] || { echo "--fpu-gate: fpugate030.o exports '$GOTX'" >&2; exit 1; }
  echo "  fpugate030.o $(sha256sum "$BUILD/fpugate030.o" | cut -c1-16): imports/exports exact"
  FPUG_OBJ="fpugate030.o"
else
  echo "--- fpu gate: --no-fpu-gate -- sendsig calls fpu_setup ungated, as stock ---"
fi
FQG_OBJ=""
if [ "$FREEQ_GUARD" = 1 ]; then
  # === 8g. the STREAMS freeq guard (grimoire quirk 92): src/freeqguard030.c; the relocations are retargeted after the link ===
  echo "--- freeq guard: compiling $KT/src/freeqguard030.c (freeq_guarded) ---"
  ( cd "$BUILD/os" && "$CC" -c -O $CFLAGS_K "$KT/src/freeqguard030.c" -o "$BUILD/freeqguard030.o" ) \
    || { echo "--freeq-guard: freeqguard030.c did not compile" >&2; exit 1; }
  GOT="$("$NM" "$BUILD/freeqguard030.o" | awk '$1=="U"{print $2}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOT" = "freeq qhead qtail scanqhead scanqtail" ] || { echo "--freeq-guard: freeqguard030.o imports '$GOT'" >&2; exit 1; }
  GOTX="$("$NM" "$BUILD/freeqguard030.o" | awk '$2 ~ /^[TDB]$/{print $3}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$GOTX" = "fqg_calls fqg_last fqg_magic fqg_run fqg_scan freeq_guarded" ] \
    || { echo "--freeq-guard: freeqguard030.o exports '$GOTX'" >&2; exit 1; }
  echo "  freeqguard030.o $(sha256sum "$BUILD/freeqguard030.o" | cut -c1-16): imports/exports exact"
  FQG_OBJ="freeqguard030.o"
else
  echo "--- freeq guard: --no-freeq-guard -- freeq unguarded, as stock ---"
fi
echo "--- final link: ld -o unix -r${LGCC_U} $TOP_OBJS amiga/config/unix.o${RTH1_OBJ:+ $RTH1_OBJ}${KINFO_OBJ:+ $KINFO_OBJ}${KZERO_OBJ:+ $KZERO_OBJ}${FPUG_OBJ:+ $FPUG_OBJ}${FQG_OBJ:+ $FQG_OBJ}${FS_LGCC:+ $FS_LGCC} ---"
( cd "$BUILD"; "$LD" -o unix -r $LGCC_U $TOP_OBJS amiga/config/unix.o $RTH1_OBJ $KINFO_OBJ $KZERO_OBJ $FPUG_OBJ $FQG_OBJ $FS_LGCC; chmod +r unix )
# HARD CHECK (kzero): kzero ours, bzero the stock body, every caller through a relocation naming kzero.  The failure
# modes are the quiet ones: a lost weaken leaves kzero = bzero and the quirk-90 panic in place.
kzero_check() {
  local u="$1" want callers kz bz
  kz="$("$NM" "$u" | awk '$3=="kzero" && $2=="T" {print $1}')"
  bz="$("$NM" "$u" | awk '$3=="bzero" && $2=="T" {print $1}')"
  [ "$("$NM" "$u" | awk '$3=="kzero"' | wc -l)" = 1 ] && [ -n "$kz" ] \
    || { echo "[FAIL] kzero: $u does not have exactly one strong kzero" >&2; exit 1; }
  [ "$bz" = 00000302 ] || { echo "[FAIL] kzero: bzero is at '$bz', not the stock 0x302" >&2; exit 1; }
  [ "$kz" != "$bz" ] || { echo "[FAIL] kzero: kzero is still bzero (0x$bz) -- the weaken was lost" >&2; exit 1; }
  "$NM" "$u" | awk '$3=="kzr_magic" && $2=="D" {f=1} END{exit !f}' || { echo "[FAIL] kzero: no kzr_magic in .data" >&2; exit 1; }
  want="pvn_vptrunc rwvp spec_write"
  case ",$CARVE_FS," in *,ufs,*) ;; *) want="$want rwip"; [ "$UFS_TAILZERO" = 1 ] && want="$want ufs_vptrunz";; esac
  case ",$CARVE_FS," in *,s5,*) ;; *) want="$want writei";; esac
  want="$(echo $want | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  callers="$("$OBJDUMP" -dr "$u" | awk '/^[0-9a-f]+ <[^>]*>:$/ {fn=substr($2, 2, length($2) - 3)} /R_68K_32[ \t]+kzero$/ {print fn}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [ "$callers" = "$want" ] || { echo "[FAIL] kzero: relocations naming kzero are in '$callers', want exactly '$want'" >&2; exit 1; }
  echo "  [OK] kzero fault catch bound in $(basename "$u"): kzero @0x$kz, bzero stock @0x302, kzr_magic; callers: $callers"
}
if [ "$KZERO" = 1 ]; then kzero_check "$BUILD/unix"; fi
case ",$CARVE_FS," in *,ufs,*) ;; *) if [ "$UFS_TAILZERO" = 1 ]; then qz_check "$BUILD/unix"; fi ;; esac
if [ "$FPU_GATE" = 1 ]; then
  echo "--- fpu gate: sendsig's jsr fpu_setup -> fpu_setup_gated (tools/fpugate-sendsig.py) ---"
  python3 "$KT/tools/fpugate-sendsig.py" "$BUILD/unix"
  python3 "$KT/tools/fpugate-sendsig.py" --check "$BUILD/unix"
fi
if [ "$FREEQ_GUARD" = 1 ]; then
  echo "--- freeq guard: every freeq relocation -> freeq_guarded (tools/freeqguard-retarget.py) ---"
  python3 "$KT/tools/freeqguard-retarget.py" "$BUILD/unix"
  python3 "$KT/tools/freeqguard-retarget.py" --check "$BUILD/unix"
fi
if [ -n "$OBJ_BASELINE" ]; then
  echo "--- object gate: every object == $OBJ_BASELINE except exactly: ${OBJ_ALLOW:-(none)}; absent exactly: ${OBJ_ABSENT:-(none)} ---"
  python3 - "$BUILD" "$OBJ_BASELINE" "$OBJ_ALLOW" "${RTH1_C:+rth1}" "${KINFO_C:+kinfo}" "$OBJ_ABSENT" "$KZERO_OBJ $FPUG_OBJ $FQG_OBJ" <<'PYG' || exit 1
import hashlib, os, sys
build, base, allow, rth, kinfo = sys.argv[1], sys.argv[2], set(sys.argv[3].split()), sys.argv[4], sys.argv[5]
absent = set(sys.argv[6].split())
kzero = set(sys.argv[7].split())
want = {}
for ln in open(base):
    h, p = ln.split(None, 1); want[p.strip()] = h
got = {}
for d, _, fs in os.walk(build):
    for f in fs:
        if f.endswith('.o'):
            p = os.path.relpath(os.path.join(d, f), build)
            got[p] = hashlib.sha256(open(os.path.join(d, f), 'rb').read()).hexdigest()
extra = set(got) - set(want) - ({'rth1.o', 'rth1-mul64keep.o', 'rth1-nomarc.o'} if rth else set()) \
    - ({'kinfo.o', 'kinfo-mul64keep.o'} if kinfo else set()) - kzero
missing = set(want) - set(got)
differ = {p for p in want if p in got and got[p] != want[p]}
bad = []
if extra: bad.append('objects the baseline does not list: %s' % ' '.join(sorted(extra)))
if missing != absent: bad.append('baseline objects not built %s, absent exactly %s' % (sorted(missing), sorted(absent)))
if differ != allow: bad.append('differing objects %s, allowed exactly %s' % (sorted(differ), sorted(allow)))
for b in bad: print('  [FAIL] object gate: ' + b)
if bad: sys.exit(1)
print('  [OK] %d objects == baseline; exactly %s differ, as allowed%s' % (len(want) - len(differ) - len(missing),
      sorted(differ) or 'none', '; absent exactly %s' % sorted(missing) if missing else ''))
PYG
fi
if [ -n "$RTH1_C" ]; then
  echo "--- rth1: main's jsr vfs_mountroot -> rth1_mountroot ($RTH1_HOOK) ---"
  python3 "$RTH1_HOOK" "$BUILD/unix"
  python3 "$RTH1_HOOK" --check "$BUILD/unix"
fi
if [ -n "$TTC_FIX" ]; then
  [ -f "$TTC_FIX" ] || { echo "--ttcompat-fix: missing $TTC_FIX" >&2; exit 2; }
  echo "--- ttcompat init fix (DRIVER-LINE-7): $TTC_FIX ---"
  cp "$BUILD/unix" "$BUILD/unix.pre-ttcompat"
  python3 "$TTC_FIX" "$BUILD/unix"
  python3 "$TTC_FIX" --check "$BUILD/unix"
  D="$(cmp -l "$BUILD/unix.pre-ttcompat" "$BUILD/unix" | wc -l)"
  [ "$D" -le 64 ] || { echo "--ttcompat-fix: $D bytes changed (more than the 64-byte span)" >&2; exit 1; }
  echo "  bytes changed: $D (inside ttcompatopen)"
fi
if [ -n "$HIWAT_FIX" ]; then
  [ -f "$HIWAT_FIX" ] || { echo "--tcp-hiwat-fix: missing $HIWAT_FIX" >&2; exit 2; }
  echo "--- TCP lower-read hiwat 4096 -> 16384 (DRIVER-LINE-10): $HIWAT_FIX ---"
  cp "$BUILD/unix" "$BUILD/unix.pre-hiwat"
  python3 "$HIWAT_FIX" "$BUILD/unix"
  python3 "$HIWAT_FIX" --check "$BUILD/unix"
  D="$(cmp -l "$BUILD/unix.pre-hiwat" "$BUILD/unix" | wc -l)"
  [ "$D" -eq 1 ] || { echo "--tcp-hiwat-fix: $D bytes changed (want exactly 1, the hiwat word's 0x10 -> 0x40)" >&2; exit 1; }
  echo "  bytes changed: 1 (tcpm_info[3].mi_hiwat)"
fi
if [ -n "$KINFO_C" ]; then
  echo "--- kinfo: cdevsw[53] -> kinfoopen/close/read/write (tools/kinfo-cdevsw.py) ---"
  python3 "$KT/tools/kinfo-cdevsw.py" "$BUILD/unix" 53
  python3 "$KT/tools/kinfo-cdevsw.py" --check "$BUILD/unix" 53
fi
if [ -n "$DLM_CORE" ]; then
  [ -n "$KINFO_C" ] || { echo "--dlm-core needs --kinfo (the module kernel is K030-U with kinfo)" >&2; exit 2; }
  echo "--- dlm core (stage 3, stage-3-kernel-brief.md steps 1-7, 9-10): tools/dlm-core-link.sh$([ "$DLM_STUB" = 1 ] && echo ' (DRY RUN: providers stubbed)') ---"
  cp "$BUILD/unix" "$BUILD/unix.static"
  bash "$KT/tools/dlm-core-link.sh" "$BUILD/unix.static" "$WORK/dlm-core" --dlm "$DLM_CORE" --line k30 --kabi "$KABI" ${RTH1_DIR:+--rth1-dir "$RTH1_DIR"} \
    $([ "$DLM_STUB" = 1 ] && echo --stub-providers) || { echo "--dlm-core: a step FAILed ($WORK/dlm-core/steps.tsv)" >&2; exit 1; }
  cp "$WORK/dlm-core/unix" "$BUILD/unix"
  if [ "$KZERO" = 1 ]; then kzero_check "$BUILD/unix"; fi   # the splice weakens base names the core defines: not kzero
  if [ "$FPU_GATE" = 1 ]; then python3 "$KT/tools/fpugate-sendsig.py" --check "$BUILD/unix"; fi
  if [ "$FREEQ_GUARD" = 1 ]; then python3 "$KT/tools/freeqguard-retarget.py" --check "$BUILD/unix"; fi
  # the sd seam, checked on the objects (a lost seam leaves a root module registered and never taken: S4-73's
  # "RTH1: root c6d0s1 built in (controller not present)"): a four-card base must call a core's dlm_sd_close
  if [ "$SD_CARDS" = 4 ] && "$NM" "$WORK/dlm-core/obj/dlm.o" | awk '$2=="T" && $3=="dlm_sd_close" {f=1} END{exit !f}'; then
    "$NM" "$BUILD/unix.static" | awk '$1=="U" && $2=="dlm_sd_close" {f=1} END{exit !f}' \
      || { echo "--sd-cards 4: the core defines dlm_sd_close but sd.c never calls it (the sd seam is missing)" >&2; exit 1; }
    echo "  sd seam: sd.c calls the core's dlm_sd_close (C4-1 section 3)"
  fi
fi

echo "=================================================================="
echo " candidate ELF: $BUILD/unix"
ls -l "$BUILD/unix"
file "$BUILD/unix"
# GNU nm 2.8.1 has no -h (that is Amix/SysV nm); -u = undefined-only.  The Amix
# link tolerates only etext/edata/end unresolved (the loader/link defines them).
echo "--- $NM -u unix (undefined syms, minus etext/edata/end) ---"
UNDEF="$("$NM" -u "$BUILD/unix" | awk '{print $NF}' | egrep -v '^(etext|edata|end)$' || true)"
if [ -n "$UNDEF" ]; then
  printf '%s\n' "$UNDEF"
  echo "  (^ residual unresolved symbols -- the loader would fault on these)"
else
  echo "  none -- fully resolved (only etext/edata/end, as expected)"
fi

# === 10. elf2brel: ET_REL unix -> boot-ready brel (e_type=0xff00) =============
# tools/elf2brel.py is a faithful port of amiga/boot/elf2brel.c: it fuses .text/
# .rodata/.data/.bss into one contiguous section, folds the .rela.text/.rela.data
# tables into the single compact relocation table rel.c/compactreloc consumes (with
# the nr_offset MSB flagging ABSOLUTE vs text-relative), drops symtab+strtab, and
# stamps e_type=ET_LOPROC (0xff00).  The boot floppy is framed from this brel, NOT
# from the raw ET_REL unix (which would D245-Guru during relocation).  We keep BOTH:
# relsim.py still judges the ET_REL `unix`; the floppy consumes `unix.brel`.
echo "--- elf2brel: $BUILD/unix (ET_REL) -> $BUILD/unix.brel (brel) ---"
python3 "$KT/tools/elf2brel.py" -v "$BUILD/unix" "$BUILD/unix.brel"
BREL_ETYPE="$(od -An -tx1 -j16 -N2 "$BUILD/unix.brel" | tr -d ' ')"
echo "  boot-ready kernel: $BUILD/unix.brel  ($(wc -c < "$BUILD/unix.brel") bytes, e_type=0x$BREL_ETYPE)"
if [ -n "$DLM_CORE" ] && [ "$DLM_STUB" = 1 ]; then
  echo "--- dlm core DRY RUN (providers stubbed): no sidecar ---"
elif [ -n "$DLM_CORE" ]; then
  echo "--- dlm core: the C2-3 version 5 sidecar of unix.brel (kabi-sidecar030.py --module) ---"
  # unix.sym (C2-3 v6 §2.1): kernel/dlm's own nlmake (tests/host/nlmake.c with kbootset's knl.c and the loader's rel.c,
  # the layout the loader gives the brel) when the tree has it, else tools/mksym030.py; either way checked below
  if [ -f "$DLM_CORE/tests/host/nlmake.c" ]; then
    echo "--- dlm core: unix.sym by kernel/dlm's nlmake (the brel's symbols bound at 0, C2-3 v6 §2.1) ---"
    ${HOSTCC:-cc} -std=c89 -pedantic -Wall -Wextra -Werror -O2 -I"$DLM_CORE/loader/common" -I"$DLM_CORE/kbootset" \
      -o "$WORK/dlm-core/nlmake" "$DLM_CORE/tests/host/nlmake.c" "$DLM_CORE/kbootset/knl.c" "$DLM_CORE/loader/common/rel.c" \
      && "$WORK/dlm-core/nlmake" "$BUILD/unix" 0 "$BUILD/unix.sym" || { echo "--dlm: nlmake failed" >&2; exit 1; }
  else
    echo "--- dlm core: unix.sym, the brel's symbols bound at 0 (C2-3 v6 §2.1; tools/mksym030.py) ---"
    python3 "$KT/tools/mksym030.py" "$BUILD/unix" "$BUILD/unix.sym"
  fi
  python3 "$DLM_CORE/tools/ksymgate.py" --extract "$WORK/dlm-core/axrel" "$BUILD/unix" 0 "$WORK/dlm-core/ksym0.bin" \
    && python3 "$KT/tools/mksym030.py" --check "$BUILD/unix" "$BUILD/unix.sym" "$WORK/dlm-core/ksym0.bin" \
    || { echo "--dlm: unix.sym does not agree with dlm_ksym bound at 0" >&2; exit 1; }
  ABI_ARGS=(--sym "$BUILD/unix.sym")   # sym= (C2-3 v6)
  [ "$SD_CARDS" = 4 ] && ABI_ARGS+=(--sdcards 4)   # sdcards=4 (C2-3, the four-card kernel)
  # abi= (C3-3 §4) when the core's mkabi.py produced it in step 9b, recomputed by the sidecar tool
  grep -q '^abi=' "$WORK/dlm-core/abi.txt" 2>/dev/null && ABI_ARGS+=(--abi "$WORK/dlm-core/abi.txt" \
    --mkabi "$DLM_CORE/tools/mkabi.py" "$DLM_CORE/abi/k30/ddi.list" "$WORK/dlm-core/core/dlm_offs.h")
  python3 "$KT/tools/kabi-sidecar030.py" "$BUILD/unix" "$BUILD/unix.brel" --family generic --module "$WORK/dlm-core/ident-fill.txt" "${ABI_ARGS[@]}" -o "$BUILD/kabi"
  python3 "$KT/tools/kabi-sidecar030.py" --check "$BUILD/unix" "$BUILD/unix.brel" "$BUILD/kabi" --module "$WORK/dlm-core/ident-fill.txt" "${ABI_ARGS[@]}"
elif [ -n "$KINFO_C" ]; then
  echo "--- kinfo: the kabi sidecar of unix.brel (C2-3 §2; tools/kabi-sidecar030.py) ---"
  python3 "$KT/tools/kabi-sidecar030.py" "$BUILD/unix" "$BUILD/unix.brel" --family "$KINFO_FAMILY" --sdcards "$SD_CARDS" -o "$BUILD/kabi"
  python3 "$KT/tools/kabi-sidecar030.py" --check "$BUILD/unix" "$BUILD/unix.brel" "$BUILD/kabi" --sdcards "$SD_CARDS"
fi

if [ -n "$CARVE_FS" ] && [ "$DLM_STUB" != 1 ]; then
  # the core tier's names (kernel/dlm abi/k30/core.list) all defined in the cut: the carved modules import them
  echo "--- carve: every abi/k30/core.list name defined in unix (the core tier the modules bind to) ---"
  CL="$DLM_CORE/abi/k30/core.list"
  "$NM" "$BUILD/unix" | awk '$(NF-1) != "U" {print $NF}' | LC_ALL=C sort -u > "$WORK/carve/defined.txt"
  NUNDEF="$(awk -v m="$KABI_MINOR" '!/^#/ && NF && ($3 == "" || $3 + 0 <= m) {print $1}' "$CL" | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$WORK/carve/defined.txt" | tr '\n' ' ')"
  [ -z "$NUNDEF" ] || { echo "FATAL: core.list names not defined in unix: $NUNDEF" >&2; exit 1; }
  echo "  $(awk '!/^#/ && NF' "$CL" | wc -l) core.list names, all defined"
  echo "--- carve: ${CARVE_FS} as core-tier modules bound to $KINFO_BUILD (carve.py wrap + the k30 kit's make + modcheck) ---"
  mkdir -p "$BUILD/mod.d"
  for f in ${CARVE_FS//,/ }; do
    rm -rf "$WORK/carve/$f"
    python3 "$DLM_CORE/tools/carve.py" wrap --fs "$f" --obj "$([ "$f" = ufs ] && echo "$UFS_OBJ" || echo "$SYSROOT_SYS/fs/$f/exp")" --filesys "$SYSROOT_SYS/master.d/filesys.o" \
      --build "$KINFO_BUILD" "$WORK/carve/$f" || { echo "FATAL: carve.py wrap --fs $f failed" >&2; exit 1; }
    make -C "$WORK/carve/$f" KIT="$DLM_CORE/build/kit/k30" > "$WORK/carve/$f.make.log" 2>&1 \
      || { tail -15 "$WORK/carve/$f.make.log" >&2; echo "FATAL: the $f module did not build (or modcheck refused it)" >&2; exit 1; }
    m="$WORK/carve/$f/build/k30/mod.d/$f"
    [ -f "$m" ] || { echo "FATAL: no $m after make" >&2; exit 1; }
    strings -a "$m" | grep -q "$KINFO_BUILD" || { echo "FATAL: the $f module does not carry the build id $KINFO_BUILD" >&2; exit 1; }
    if [ "$f" = ufs ] && [ "$UFS_TAILZERO" = 1 ]; then qz_check "$m" m68k-elf-nm m68k-elf-objdump; fi
    cp "$m" "$BUILD/mod.d/$f"
    echo "  mod.d/$f: $(wc -c < "$m") bytes, sha256 $(sha256sum < "$m" | cut -c1-16), bound to $KINFO_BUILD; $(grep -a -i 'modcheck' "$WORK/carve/$f.make.log" | tail -1)"
  done
  ( cd "$BUILD/mod.d" && sha256sum * > SHA256SUMS )
fi

echo "=================================================================="
echo "GO/NO-GO -- run the loader-faithful reloc simulator:"
echo "    python3 $KT/tools/relsim.py $BUILD/unix"
echo
echo "SCOPE: relsim is a kernel-RECORD oracle (rel.c source semantics vs this kernel's"
echo "       relocation records).  It is NOT a boot oracle -- the loader installed at"
echo "       /stand/boot2.boot is outside its scope, and a foreign boot2 D245s a valid"
echo "       kernel.  Gate the LOADER separately with tools/bootchain-verify.py."
