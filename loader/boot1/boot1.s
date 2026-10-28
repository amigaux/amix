# boot1.s -- the Amix first-stage loader (docs/spec/10-boot-loader.md §3.1).
#
# The Kickstart strap reads the first 1 KB of the boot partition (or floppy)
# and jumps to offset 12 with a1 = an open IOStdReq on the boot device.
# This file is the code from offset 12 on; tools/bbframe.c adds the bootblock
# framing ("DOS\0", checksum, 0x370, the SuperKickstart trailer) and refuses
# code longer than 1008 bytes.  The code is position-independent and carries
# no relocations (the build checks both).
#
# What it does:
#   (1) returns into the strap if an A3000 SuperKickstart wants the OS choice;
#      else takes its buffer where the partition's DosEnvec lets the device
#      transfer (de_BufMemType, de_Mask, as FFS reads them), else in chip
#   (2) reads bytes 0..2047 of the partition, takes the valid store header
#      (AXS1 at 0x400 / 0x600) with the newer sequence number
#   (3) loader trial: counts the new boot2's start in the tally block, or
#      takes the secondary boot2 if the new one already had its start
#   (4) reads the chosen boot2 (2048-byte units), checks its CRC-32, falls back
#      to the other copy, and calls it
#   (5) on failure: a line on the serial port, then stops (waits for ever).
#       Returning failure to the strap does not make Kickstart try the next
#       boot node: it raises AN_BootError and resets (M-LD3, measured on the
#       Z3660 ROM chain 2026-10-25), and a reset loop can leave a real 68060
#       dead until a power cycle
#
# Interface to boot2 (jsr to its first byte):
#   a1 IOStdReq   a0 the chosen store header (512 bytes)   a6 ExecBase
#   d0 partition start (bytes)   d1 choice: bit 0 = copy taken (1 = secondary),
#   bit 8 = taken after a CRC failure (B2), bit 9 = taken by the loader-trial
#   rule (B4)   d2 the memory block holding boot2 (BUFSZ bytes, see (1))
# If boot2 returns, boot1 says so and stops.
#
# Assembler: binutils 2.8.1 for m68k-cbm-sysv4 (SVR4 syntax: & immediate,
# % register).  68000-compatible instructions only.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.

	.set	BUFSZ, 2048 + 512 + 28672	# sector buffer, header copy, boot2
	.set	B2MAX, 28672
	.set	HDRCPY, 2048
	.set	B2AREA, 2560

	.set	LVO_ALLOCMEM, -198
	.set	LVO_FREEMEM, -210
	.set	LVO_CLOSELIB, -414
	.set	LVO_DOIO, -456
	.set	LVO_TYPEOFMEM, -534
	.set	LVO_OPENLIB, -552
	.set	LVO_CACHECLEARU, -636

	.set	IO_COMMAND, 28
	.set	IO_LENGTH, 36
	.set	IO_DATA, 40
	.set	IO_OFFSET, 44
	.set	CMD_READ, 2
	.set	CMD_WRITE, 3

	.set	SAVED, 44		# bytes pushed by the entry movem

	.text
	.globl	boot1
boot1:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.l	(4).w,%a6
	move.l	%a1,%a5
# pre-2.0 straps do not set io_Offset
	cmp.w	&36,(20,%a6)
	bcc.b	offok
	clr.l	(IO_OFFSET,%a5)
offok:	move.l	(IO_OFFSET,%a5),%d7

# (1) the buffer's memory as FFS chooses it (spec 10 §3.1): the first
#    boot node whose start and device name are this partition's gives
#    de_BufMemType (MEMF_PUBLIC when 0) and de_Mask.  Without one, or
#    with a table too short for de_Mask, chip memory.
	moveq	&2,%d5			# MEMF_CHIP
	moveq	&-1,%d4			# the Mask
	lea	(expname,%pc),%a1
	moveq	&0,%d0
	jsr	(LVO_OPENLIB,%a6)
	tst.l	%d0
	beq.w	alloc
	move.l	%d0,%a2
	lea	(74,%a2),%a4		# eb_MountList
	bra.b	walk

# vet: d0 = a pointer from a boot node; a3 = it, Z set when it is not in RAM
vet:	move.l	%d0,%a3
	move.l	%d0,%a1
	jsr	(LVO_TYPEOFMEM,%a6)
	tst.l	%d0
	rts

walk:	move.l	(%a4),%a4
	tst.l	(%a4)
	beq.b	walked
	move.l	(16,%a4),%d0		# bn_DeviceNode
	bsr.b	vet
	beq.b	walk
	move.l	(28,%a3),%d0		# dn_Startup: the FileSysStartupMsg
	lsl.l	&2,%d0
	bsr.b	vet
	beq.b	walk
	move.l	(4,%a3),%a0		# fssm_Device, a BSTR whose length
	add.l	%a0,%a0			# may count a NUL (spec 10 §2.1): its
	add.l	%a0,%a0			# text starts with io_Device's name
	tst.b	(%a0)+
	move.l	(20,%a5),%a1
	move.l	(10,%a1),%a1
nmchar:	move.b	(%a1)+,%d0
	beq.b	nmend
	cmp.b	(%a0)+,%d0
	bne.b	walk
	bra.b	nmchar
nmend:
	move.l	(8,%a3),%d0		# fssm_Environ: the DosEnvec
	lsl.l	&2,%d0
	bsr.b	vet
	beq.b	walk
	move.w	(14,%a3),%d0		# the start: de_Surfaces *
	mulu.w	(22,%a3),%d0		# de_BlocksPerTrack (each below
	move.w	(36,%a3),%d2		# 65536) * de_LowCyl * 512 bytes
	mulu.w	%d0,%d2
	mulu.w	(38,%a3),%d0
	swap	%d2
	clr.w	%d2
	add.l	%d2,%d0
	moveq	&9,%d1
	lsl.l	%d1,%d0
	cmp.l	%d7,%d0
	bne.b	walk
	moveq	&14,%d0			# de_TableSize reaches de_Mask?
	cmp.l	(%a3),%d0
	bhi.b	walked
	moveq	&1,%d5			# de_BufMemType, MEMF_PUBLIC
	or.l	(48,%a3),%d5		# when 0
	move.l	(56,%a3),%d4		# de_Mask
walked:
# A3000 SuperKickstart: when expansion.library's flags ask for the
# operating-system choice, step the strap's return address past its boot
# call so Kickstart continues, and return 0.
	move.l	%a2,%a1
	move.b	(34,%a1),%d2
	jsr	(LVO_CLOSELIB,%a6)
	and.b	&0x30,%d2
	beq.b	alloc
	add.l	&14,(SAVED,%sp)
	moveq	&0,%d0
	bra.w	ret

# the block of that memory, cleared; chip when its end lies beyond the
# Mask (AllocMem's 8-byte alignment meets the Mask's low bits; any memory
# serves a Mask of -1, so the chip try is the last one)
alloc:	move.l	&BUFSZ,%d6
amem:	move.l	%d6,%d0
	move.l	%d5,%d1
	bset	&16,%d1			# MEMF_CLEAR
	jsr	(LVO_ALLOCMEM,%a6)
	move.l	%d0,%a4
	tst.l	%d0
	beq.b	inchip
	add.l	%d6,%d0
	cmp.l	%d4,%d0
	bls.b	memok
	move.l	%a4,%a1
	move.l	%d6,%d0
	jsr	(LVO_FREEMEM,%a6)
inchip:	moveq	&2,%d5
	not.l	%d4
	beq.w	failmem
	moveq	&-1,%d4
	bra.b	amem
memok:	lea	(HDRCPY,%a4),%a3
	lea	(B2AREA,%a4),%a2

# (2) the store header
	moveq	&0,%d0
	move.l	%a4,%a0
	move.l	&2048,%d1
	bsr.w	rd
	bne.w	failb1
	lea	(0x400,%a4),%a0
	bsr.w	hdrok
	seq	%d4
	lea	(0x600,%a4),%a0
	bsr.w	hdrok
	seq	%d5
	tst.b	%d4
	beq.b	tryb
	tst.b	%d5
	beq.b	usea
	move.l	(0x608,%a4),%d0
	sub.l	(0x408,%a4),%d0
	bgt.b	useb
usea:	lea	(0x400,%a4),%a0
	bra.b	copyhdr
tryb:	tst.b	%d5
	beq.w	failb1
useb:	lea	(0x600,%a4),%a0
copyhdr:
	move.l	%a3,%a1
	move.w	&127,%d0
cploop:	move.l	(%a0)+,(%a1)+
	dbra	%d0,cploop

# (3) loader trial (header flag 0x8, never on a read-only medium, flag 0x2)
	moveq	&0,%d6
	move.l	(16,%a3),%d0
	btst	&3,%d0
	beq.w	notrial
	btst	&1,%d0
	bne.w	notrial
	move.l	(68,%a3),%d0
	move.l	%a4,%a0
	move.l	&2048,%d1
	bsr.w	rd
	bne.b	wrtally
	cmp.l	&0x41585431,(%a4)	# "AXT1"
	bne.b	wrtally
	move.l	%a4,%a0
	move.l	&2044,%d0
	bsr.w	crc
	cmp.l	(2044,%a4),%d0
	bne.b	wrtally
	move.l	(4,%a4),%d0
	cmp.l	(8,%a3),%d0		# refers to this header?
	bne.b	wrtally
	tst.l	(8,%a4)
	beq.b	wrtally
	move.l	&0x201,%d6		# already started once: secondary (B4)
	bra.b	notrial
wrtally:
	move.l	%a4,%a0
	move.w	&511,%d0
clrloop:
	clr.l	(%a0)+
	dbra	%d0,clrloop
	move.l	&0x41585431,(%a4)
	move.l	(8,%a3),(4,%a4)
	moveq	&1,%d0
	move.l	%d0,(8,%a4)
	move.l	%a4,%a0
	move.l	&2044,%d0
	bsr.w	crc
	move.l	%d0,(2044,%a4)
	move.l	(68,%a3),%d0
	move.l	%a4,%a0
	move.l	&2048,%d1
	moveq	&CMD_WRITE,%d2
	bsr.w	io
	beq.b	notrial
	move.l	&0x201,%d6		# cannot record the start: secondary (B4)
notrial:

# (4) boot2: the chosen copy, else the other one
	bsr.w	ld2
	beq.b	go
	eor.w	&1,%d6
	or.w	&0x100,%d6
	bsr.w	ld2
	bne.w	failb3
go:	cmp.w	&37,(20,%a6)
	bcs.b	nocache
	jsr	(LVO_CACHECLEARU,%a6)
nocache:
	move.l	%a5,%a1
	move.l	%a3,%a0
	move.l	%d7,%d0
	move.l	%d6,%d1
	move.l	%a4,%d2
	jsr	(%a2)
	lea	(msgret,%pc),%a0	# boot2 gave up
	bra.b	failp

failb1:	lea	(msgb1,%pc),%a0
	bra.b	failp
failb3:	lea	(msgb3,%pc),%a0
	bra.b	failp
failmem:
	lea	(msgmem,%pc),%a0
failp:	move.l	%a0,-(%sp)
	lea	(msgpfx,%pc),%a0
	bsr.b	puts
	move.l	(%sp)+,%a0
	bsr.b	puts
	lea	(msgpfx,%pc),%a0
	bsr.b	puts
	lea	(msgstop,%pc),%a0
	bsr.b	puts
stop:	bra.b	stop			# interrupts stay on; a reset is the user's

ret:	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

# puts: a0 = NUL-terminated string to the serial port, 8N1 at about 9600
# baud (period 370 suits both PAL and NTSC clocks within 1 %).
puts:	move.w	&370,0xdff032		# SERPER
putc:	moveq	&0,%d0
	move.b	(%a0)+,%d0
	beq.b	putsend
	or.w	&0x100,%d0		# stop bit
tbe:	btst	&5,0xdff018		# SERDATR TBE (bit 13 of the word)
	beq.b	tbe
	move.w	%d0,0xdff030		# SERDAT
	bra.b	putc
putsend:
	rts

# ld2: read and check boot2 copy (d6 & 1); Z set when good.
ld2:	move.l	%d6,%d0
	and.w	&1,%d0
	lsl.w	&4,%d0
	lea	(28,%a3,%d0.w),%a1
	move.l	(4,%a1),%d1
	beq.b	ld2bad
	cmp.l	&B2MAX,%d1
	bhi.b	ld2bad
	move.l	%a1,-(%sp)
	add.l	&2047,%d1
	and.l	&0xFFFFF800,%d1
	move.l	(%a1),%d0
	move.l	%a2,%a0
	bsr.b	rd
	move.l	(%sp)+,%a1
	bne.b	ld2bad
	move.l	%a1,-(%sp)
	move.l	%a2,%a0
	move.l	(4,%a1),%d0
	bsr.b	crc
	move.l	(%sp)+,%a1
	cmp.l	(8,%a1),%d0
	rts
ld2bad:	moveq	&1,%d0
	rts

# hdrok: a0 = a store header copy; Z set when valid (magic, version 1,
# a primary boot2 of sane length, CRC-32 of bytes 0..507).
hdrok:	cmp.l	&0x41585331,(%a0)	# "AXS1"
	bne.b	hdrbad
	cmp.w	&1,(4,%a0)
	bne.b	hdrbad
	move.l	(32,%a0),%d0
	beq.b	hdrbad
	cmp.l	&B2MAX,%d0
	bhi.b	hdrbad
	move.l	%a0,-(%sp)
	move.l	&508,%d0
	bsr.b	crc
	move.l	(%sp)+,%a0
	cmp.l	(508,%a0),%d0
	rts
hdrbad:	moveq	&1,%d0
	rts

# rd / io: d0 = offset in the partition, d1 = length, a0 = buffer,
# (io: d2 = command).  Z set when io_Error is 0.
rd:	moveq	&CMD_READ,%d2
io:	move.w	%d2,(IO_COMMAND,%a5)
	move.l	%d1,(IO_LENGTH,%a5)
	move.l	%a0,(IO_DATA,%a5)
	add.l	%d7,%d0
	move.l	%d0,(IO_OFFSET,%a5)
	move.l	%a5,%a1
	jsr	(LVO_DOIO,%a6)
	tst.b	%d0
	rts

# crc: CRC-32 (reflected, 0xEDB88320) of d0 bytes at a0; result in d0.
# Uses d1-d3.
crc:	move.l	%d0,%d1
	moveq	&-1,%d0
	move.l	&0xEDB88320,%d3
	bra.b	crcnext
crcbyte:
	move.b	(%a0)+,%d2
	eor.b	%d2,%d0
	moveq	&7,%d2
crcbit:	lsr.l	&1,%d0
	bcc.b	crcnox
	eor.l	%d3,%d0
crcnox:	dbra	%d2,crcbit
crcnext:
	subq.l	&1,%d1
	bcc.b	crcbyte
	not.l	%d0
	rts

expname:
	.ascii	"expansion.library\0"
msgpfx:	.ascii	"\r\namix-boot1: \0"
msgb1:	.ascii	"B1 no valid store header\0"
msgb3:	.ascii	"B3 no valid boot2\0"
msgmem:	.ascii	"no memory\0"
msgret:	.ascii	"boot2 gave up\0"
msgstop:
	.ascii	"stopped. Reset; both mouse buttons at reset: Kickstart menu\r\n\0"
	.even
