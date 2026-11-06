| segvnprot030.s -- segvn_faultpage refuses the accesses that would otherwise restart for ever
| (tools/segvnprot-retarget.py).
|
| Stock segvn_faultpage reads the per-page protection and computes which bit the fault type needs, then goes on to the
| fault body without testing it, and segvn_fault itself rejects only a write under F_PROT on a segment that is readable
| and not writable, with no per-page protections.  So a user access to a PROT_NONE segment or page, a write to a page made read-only by
| mprotect or a mapping with neither read nor write, or a read of a write-only private page, reloads nothing useful,
| as_fault returns 0, and the instruction restarts into the same fault for ever.  When the kernel's own copy faults that
| way it spins in kernel mode and the machine stops.  And F_SOFTLOCK on such a page gives /proc a page it should not see:
| a read of a PROT_NONE page returns whatever vtop finds, and a write to a read-only shared file reaches the page cache
| when prusrio could not raise the protection.  This wrapper, which the one call in segvn_fault reaches instead of the
| stock body, returns FC_PROT for:
|
|   no access at all, except mlock's F_SOFTLOCK with S_OTHER, which takes the page without touching it;
|   a write to a page without write, under F_PROT or F_SOFTLOCK.
|
| A read of a write-only page gains read permission here and goes on (a fetch arrives as S_READ, so execute counts as
| read already).  It is from then on a read-write page, which the stock body serves with no new case.  The 68030 has no
| write-only page: a resident read-write translation never faults on a read, so refusing the read when the page has to be
| brought in would make a program work until memory gets tight.  POSIX allows PROT_WRITE to imply read, and mmap has
| already required a readable file.  segvn_data's prot or the vpage is one byte, set by one instruction, on a kernel
| with one processor.
|
| A write under F_INVAL goes on: it loads the page read-only and comes back as F_PROT.  That is on purpose: the 68030
| defines the SSW's read/write bit for data cycles, so a fetch may be reported as a write, and an F_PROT never is a fetch.
|
| What this does not change.  Stock's own steps before the refusal stay: a write under F_INVAL still copies a private page, and on a shared file
| still allocates a hole and updates its times, and a refused write first has segvn_fault allocate the anon array.
| A raw write from a write-only buffer is refused by useracc, which checks the stored protection without a fault, until a
| read fault has added read here; a raw read into one works.
| /proc tests the first page of a write it raises protection for, so a write from a writable page into a read-only one is
| refused at that page, after a partial write.
|
| Arguments, read from the stock function: 1 seg (seg->s_data at +28), 5 vpage, 8 fault type, 9 rw.  struct segvn_data:
| pageprot +2, prot +3.  struct vpage: vp_prot is the top nibble of its first byte.  PROT_READ 1, PROT_WRITE 2, PROT_EXEC
| 4; S_OTHER 0, S_READ 1, S_WRITE 2; F_INVAL 0, F_PROT 1, F_SOFTLOCK 2; FC_PROT 4.  No frame, so the stock function finds its arguments and return address
| as they were.  Called from process context; %d0, %d1 and %a0 are scratch.
|
| MIT licence, see LICENSE in kernel/k30.

	.text
	.globl	segvn_faultpage_prot
segvn_faultpage_prot:
	moveal	%sp@(4),%a0		| seg
	moveal	%a0@(28),%a0		| its segvn_data
	tstb	%a0@(2)			| per-page protections?
	bnes	Lpage
	moveb	%a0@(3),%d0		| no: the segment's
	bras	Lprot
Lpage:
	moveal	%sp@(20),%a0		| vpage
	movel	%a0,%d0
	beqs	Lpass			| none: the stock body decides
	moveb	%a0@,%d0
	lsrb	&4,%d0			| vp_prot
Lprot:
	movel	%sp@(36),%d1		| rw
	andib	&7,%d0
	bnes	Lsome
	tstl	%d1			| no access at all: only S_OTHER,
	bnes	Ldeny
	moveq	&2,%d1			| under F_SOFTLOCK, goes on
	cmpl	%sp@(32),%d1
	bnes	Ldeny
	bras	Lpass
Lsome:
	cmpil	&1,%d1
	bnes	Lnread
	andib	&5,%d0			| S_READ: read or execute
	bnes	Lpass
	moveal	%sp@(4),%a0		| write only: it may read from now on
	moveal	%a0@(28),%a0
	tstb	%a0@(2)
	bnes	Lvpr
	orib	&1,%a0@(3)		| PROT_READ, in the segment's prot
	bras	Lpass
Lvpr:
	moveal	%sp@(20),%a0
	orib	&16,%a0@		| PROT_READ, in the top nibble of the vpage
	bras	Lpass
Lnread:
	cmpil	&2,%d1
	bnes	Lpass			| S_OTHER
	btst	&1,%d0
	bnes	Lpass			| S_WRITE allowed: copy on write, as stock
	tstl	%sp@(32)
	beqs	Lpass			| F_INVAL: comes back as F_PROT
Ldeny:
	addql	&1,segvn_prot_n
	moveq	&4,%d0			| FC_PROT
	rts
Lpass:
	moveal	segvn_prot_stock,%a0
	jmp	%a0@

	.data
	.align	4
	.globl	segvn_prot_n
segvn_prot_n:
	.long	0			| accesses refused
	.globl	segvn_prot_stock
segvn_prot_stock:
	.long	segvn_faultpage_prot	| retargeted to the stock segvn_faultpage after the link
