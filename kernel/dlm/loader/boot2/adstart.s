# adstart.s -- the first bytes of each AmigaDOS program built here:
# amix-cdboot, boot2 as an AmigaDOS program (docs/spec/10-boot-loader.md
# §4.4), and the axtime measurement tool.  AmigaDOS has already loaded and
# relocated the program (tools/b2link.c -h writes an AmigaDOS load file), so
# unlike start.s this stub only clears bss and calls C.
#
# Header (same layout as start.s, filled by b2link):
#   +0 bra.w stub    +4 "AXB2"    +8 table offset (an empty table here)
#   +12 bss size    +16 image size
#
# Entry from the CLI: a0 the argument string, d0 its length.
# C: long ados_main(execbase, args, arglen); its result is the CLI return
# code.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.

	.text
	.globl	ados_start
ados_start:
	bra.w	stub
	.long	0x41584232		# "AXB2"
	.long	0			# table offset   (b2link)
	.long	0			# bss size       (b2link)
	.long	0			# image size     (b2link)
stub:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	lea	(ados_start,%pc),%a3
	move.l	%a0,%a5
	move.l	%d0,%d6
	move.l	(16,%a3),%d3		# bss from the end of the image
	lea	(0,%a3,%d3.l),%a4
	move.l	(12,%a3),%d3
	bra.b	bssnext
bssone:	clr.b	(%a4)+
bssnext:
	subq.l	&1,%d3
	bcc.b	bssone
	move.l	%d6,-(%sp)
	move.l	%a5,-(%sp)
	move.l	(4).w,-(%sp)
	jsr	(ados_main,%pc)
	lea	(12,%sp),%sp
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts
