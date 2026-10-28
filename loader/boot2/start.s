# start.s -- boot2's first bytes: a header, then the start-up stub that
# moves boot2 into fast memory when the machine has any, relocates it for
# where it then lies, clears its bss and calls C.
# (docs/spec/10-boot-loader.md §3.2; docs/plan/stage-1.md S1-11.)
#
# boot1 loads boot2 into chip memory (the strap's device reads by DMA).
# Run from there, its code competes with the display for the chip bus:
# inflate 7 times and CRC-32 25 times slower than from fast memory on a
# 25 MHz 68030 (M-LD8, 2026-10-26).  So the stub copies the image and its
# table into a MEMF_FAST block first; without fast memory it stays in chip.
#
# boot2 is linked at address 0.  tools/b2link.c appends a table of the
# offsets of every 32-bit field holding a 0-based address and patches the
# header below.  The table is a 32-bit count of the bytes that follow,
# then the fields in ascending order, a byte each: half the distance from
# the previous one, or 0 and a 16-bit offset (the image is under 32 KiB).
# The stub adds the load address to each such field, so the C code needs
# no position-independent code generation.
#
# Header (offsets from the first byte):
#   +0 bra.w stub    +4 "AXB2"    +8 table offset (= image size)
#   +12 bss size    +16 image size
#
# Entry from boot1 (see loader/boot1/boot1.s): a1 IOStdReq, a0 store header,
# d0 partition start, d1 boot1's choice code, d2 the memory block, a6 ExecBase.
# C: long boot2_main(iob, hdr, part, choice, mem, execbase, infast); infast
# is 1 when boot2 runs from fast memory; its return value goes back to
# boot1 in d0.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.

	.text
	.globl	boot2_start
boot2_start:
	bra.w	stub
	.long	0x41584232		# "AXB2"
	.long	0			# table offset   (b2link)
	.long	0			# bss size       (b2link)
	.long	0			# image size     (b2link)
stub:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	lea	(boot2_start,%pc),%a3
	move.l	%a3,%d6			# where boot1 loaded it
	moveq	&0,%d7			# infast
	move.l	(8,%a3),%d3		# image + table bytes
	add.l	(0,%a3,%d3.l),%d3
	addq.l	&4,%d3
	move.l	(16,%a3),%d4		# image + bss bytes
	add.l	(12,%a3),%d4
	cmp.l	%d3,%d4
	bcc.b	big
	move.l	%d3,%d4
big:	movem.l	%d0-%d2/%a0-%a1,-(%sp)
	move.l	%d4,%d0
	moveq	&4,%d1			# MEMF_FAST
	jsr	(-198,%a6)		# AllocMem
	move.l	%d0,%a2
	movem.l	(%sp)+,%d0-%d2/%a0-%a1
	move.l	%a2,%d4
	beq.b	inplace
	addq.l	&3,%d3			# copy image and table, in longwords
	lsr.l	&2,%d3
	move.l	%a3,%a4
	bra.b	cpnext
cpone:	move.l	(%a4)+,(%a2)+
cpnext:	subq.l	&1,%d3
	bcc.b	cpone
	move.l	%d4,%a3
	moveq	&1,%d7
inplace:
	move.l	%a3,%d5
	move.l	(8,%a3),%d3
	lea	(0,%a3,%d3.l),%a4
	move.l	(%a4)+,%d3		# table bytes
	lea	(0,%a4,%d3.l),%a5	# its end
	moveq	&0,%d4			# the field's offset, below 32768
	bra.b	relnext
relone:	moveq	&0,%d3
	move.b	(%a4)+,%d3
	beq.b	relabs
	add.l	%d3,%d4			# half the distance
	add.l	%d3,%d4
	bra.b	reladd
relabs:	move.b	(%a4)+,%d4		# 0: the offset itself
	lsl.w	&8,%d4
	move.b	(%a4)+,%d4
reladd:	add.l	%d5,(0,%a3,%d4.l)
relnext:
	cmp.l	%a5,%a4
	bcs.b	relone

	move.l	(16,%a3),%d3		# bss from the end of the image
	lea	(0,%a3,%d3.l),%a4
	move.l	(12,%a3),%d3
	bra.b	bssnext
bssone:	clr.b	(%a4)+
bssnext:
	subq.l	&1,%d3
	bcc.b	bssone

	cmp.w	&37,(20,%a6)		# the code was just modified
	bcs.b	nocache
	movem.l	%d0-%d1/%a0-%a1,-(%sp)
	jsr	(-636,%a6)		# CacheClearU
	movem.l	(%sp)+,%d0-%d1/%a0-%a1
nocache:
	move.l	%d7,-(%sp)
	move.l	%a6,-(%sp)
	move.l	%d2,-(%sp)
	move.l	%d1,-(%sp)
	move.l	%d0,-(%sp)
	move.l	%a0,-(%sp)
	move.l	%a1,-(%sp)
	lea	(boot2_main,%pc),%a2	# boot2_main in the copy that was relocated
	sub.l	%d6,%a2
	add.l	%a3,%a2
	jsr	(%a2)
	lea	(28,%sp),%sp
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts
