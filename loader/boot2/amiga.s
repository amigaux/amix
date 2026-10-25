# amiga.s -- boot2's machine-level pieces (docs/spec/10-boot-loader.md §3.2):
# the library-call glue, the CPU probe, and the hand-off to the kernel.
# Instructions the 1997 assembler may not know are written as .short words,
# each checked against `as -m68030` / the 68040 manual encodings.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.

	.text

# long ax_call(void *base, long lvo, struct ax_regs *r)
#   struct ax_regs { long d0, d1, d2, d3, d4, d5, a0, a1, a2; } -- loaded into
#   those registers, a6 = base, then jsr lvo(a6).  Returns d0.
	.globl	ax_call
ax_call:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.l	(48,%sp),%a6
	move.l	(52,%sp),%d7
	move.l	(56,%sp),%a3
	move.l	(32,%a3),%a2
	movem.l	(%a3),%d0-%d5/%a0-%a1
	jsr	(0,%a6,%d7.l)
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

# long ax_super(void (*func)(), void *arg)
#   exec Supervisor() with a5 = func, a2 = arg; func ends in rte, returns d0.
	.globl	ax_super
ax_super:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.l	(4).w,%a6
	move.l	(48,%sp),%a5
	move.l	(52,%sp),%a2
	jsr	(-30,%a6)
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

# ax_probe: supervisor function for ax_super; returns 30, 40 or 60.
#   With interrupts off, the illegal-instruction vector is pointed at a
#   handler that flags the trap and steps over the 4-byte instruction; then
#   movec PCR (68060 only) and movec URP (68040 and 68060) are tried.
#   A 68020 or 68030 traps on both and reports 30.
	.globl	ax_probe
ax_probe:
	move.w	%sr,-(%sp)
	ori.w	&0x0700,%sr
	.short	0x4e7a,0x8801		# movec %vbr,%a0
	move.l	(0x10,%a0),%a1		# the illegal-instruction vector
	lea	(probetrap,%pc),%a2
	move.l	%a2,(0x10,%a0)
	moveq	&0,%d1
	.short	0x4e7a,0x0808		# movec %pcr,%d0
	tst.l	%d1
	bne.b	not060
	moveq	&60,%d2
	bra.b	probed
not060:	moveq	&0,%d1
	.short	0x4e7a,0x0806		# movec %urp,%d0
	tst.l	%d1
	bne.b	not040
	moveq	&40,%d2
	bra.b	probed
not040:	moveq	&30,%d2
probed:	move.l	%a1,(0x10,%a0)
	move.w	(%sp)+,%sr
	move.l	%d2,%d0
	rte
probetrap:
	moveq	&1,%d1
	addq.l	&4,(2,%sp)
	rte

# ax_handoff .. ax_handoff_end: copied to chip memory and run there through
# ax_super with a2 = struct ax_ci (also in chip memory):
#   +0 stack top  +4 entry  +8 d0 for the kernel  +12 d1 for the kernel
#   +16 tbuf  +20 tvaddr  +24 tsize  +28 rbuf  +32 rvaddr  +36 rsize
#   +40 dbuf  +44 dvaddr  +48 dsize  +52 cpu (30/40/60)  +56 AttnFlags
# Interrupts off, MMU and transparent translation off, a stack in chip
# memory, text/rodata/data moved to their addresses (all three forward when
# the image moves down, all three from the tail when it moves up, so an
# overlapping move is safe), caches pushed, then a jump to the entry with
# d0/d1 set.  Never returns.
	.globl	ax_handoff
	.globl	ax_handoff_end
ax_handoff:
	move.w	&0x2700,%sr
	move.l	(52,%a2),%d7
	cmp.l	&30,%d7
	bne.b	mmu46
	lea	(hzero,%pc),%a0
	.short	0xf010,0x4000		# pmove (%a0),%tc
	lea	(nullrp,%pc),%a0
	.short	0xf010,0x4c00		# pmove (%a0),%crp
	.short	0xf010,0x4800		# pmove (%a0),%srp
	btst	&2,(59,%a2)		# AttnFlags AFB_68030: only it has TT0/TT1
	beq.b	mmudone
	lea	(hzero,%pc),%a0
	.short	0xf010,0x0800		# pmove (%a0),%tt0
	.short	0xf010,0x0c00		# pmove (%a0),%tt1
	bra.b	mmudone
mmu46:	.short	0xf4f8			# cpusha %bc
	moveq	&0,%d0
	.short	0x4e7b,0x0003		# movec %d0,%tc
	.short	0x4e7b,0x0004		# movec %d0,%itt0
	.short	0x4e7b,0x0005		# movec %d0,%itt1
	.short	0x4e7b,0x0006		# movec %d0,%dtt0
	.short	0x4e7b,0x0007		# movec %d0,%dtt1
mmudone:
	move.l	(0,%a2),%sp
	move.l	(16,%a2),%a0
	move.l	(20,%a2),%a1
	cmp.l	%a0,%a1			# tvaddr - tbuf
	bhi.b	moveup
	move.l	(16,%a2),%a0		# down: text, rodata, data, each from the head
	move.l	(20,%a2),%a1
	move.l	(24,%a2),%d0
	bsr.b	fwd
	move.l	(28,%a2),%a0
	move.l	(32,%a2),%a1
	move.l	(36,%a2),%d0
	bsr.b	fwd
	move.l	(40,%a2),%a0
	move.l	(44,%a2),%a1
	move.l	(48,%a2),%d0
	bsr.b	fwd
	bra.b	moved
moveup:	move.l	(40,%a2),%a0		# up: data, rodata, text, each from the tail
	move.l	(44,%a2),%a1
	move.l	(48,%a2),%d0
	bsr.b	bwd
	move.l	(28,%a2),%a0
	move.l	(32,%a2),%a1
	move.l	(36,%a2),%d0
	bsr.b	bwd
	move.l	(16,%a2),%a0
	move.l	(20,%a2),%a1
	move.l	(24,%a2),%d0
	bsr.b	bwd
moved:	cmp.l	&30,%d7
	bne.b	push46
	.short	0x4e7a,0x0002		# movec %cacr,%d0
	or.w	&0x0808,%d0		# clear the instruction and data caches
	.short	0x4e7b,0x0002		# movec %d0,%cacr
	bra.b	jump
push46:	.short	0xf4f8			# cpusha %bc
jump:	move.l	(4,%a2),%a0
	move.l	(8,%a2),%d0
	move.l	(12,%a2),%d1
	jmp	(%a0)

# exactly d0 bytes, a0 -> a1, from the head
fwd:	bra.b	fwdnext
fwdone:	move.b	(%a0)+,(%a1)+
fwdnext:
	subq.l	&1,%d0
	bcc.b	fwdone
	rts
# exactly d0 bytes, a0 -> a1, from the tail
bwd:	add.l	%d0,%a0
	add.l	%d0,%a1
	bra.b	bwdnext
bwdone:	move.b	-(%a0),-(%a1)
bwdnext:
	subq.l	&1,%d0
	bcc.b	bwdone
	rts

nullrp:	.long	0x7fff0001		# a do-nothing root pointer (with hzero)
hzero:	.long	0
ax_handoff_end:
