# start.s -- boot2's first bytes: a header, then the start-up stub that
# relocates boot2 for wherever boot1 loaded it, clears its bss and calls C.
# (docs/spec/10-boot-loader.md §3.2; docs/plan/stage-1.md S1-11.)
#
# boot2 is linked at address 0.  tools/b2link.c appends a table of the
# offsets of every 32-bit field holding a 0-based address and patches the
# header below.  The stub adds the load address to each such field, so the
# C code needs no position-independent code generation.
#
# Header (offsets from the first byte):
#   +0 bra.w stub    +4 "AXB2"    +8 table offset (= image size, a count
#   then that many offsets)     +12 bss size    +16 image size
#
# Entry from boot1 (see loader/boot1/boot1.s): a1 IOStdReq, a0 store header,
# d0 partition start, d1 boot1's choice code, d2 the memory block, a6 ExecBase.
# C: long boot2_main(iob, hdr, part, choice, mem, execbase); its return
# value goes back to boot1 in d0.
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
	move.l	%a3,%d5
	move.l	(8,%a3),%d3
	lea	(0,%a3,%d3.l),%a4
	move.l	(%a4)+,%d3		# entries
	bra.b	relnext
relone:	move.l	(%a4)+,%d4
	add.l	%d5,(0,%a3,%d4.l)
relnext:
	subq.l	&1,%d3
	bcc.b	relone

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
	move.l	%a6,-(%sp)
	move.l	%d2,-(%sp)
	move.l	%d1,-(%sp)
	move.l	%d0,-(%sp)
	move.l	%a0,-(%sp)
	move.l	%a1,-(%sp)
	jsr	(boot2_main,%pc)
	lea	(24,%sp),%sp
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts
