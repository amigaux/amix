| fpugate030.s -- sendsig's call of fpu_setup, gated on fpu_present (grimoire quirk 74).
|
| Without an FPU (a 68030 with no 68881/68882) the stock kernel's boot probe prints "no fpu detected" and
| leaves fpu_present 0, and the boot carries on -- until the first signal: sendsig calls fpu_setup without
| looking at fpu_present, and fpu_setup's bare FRESTORE is an F-line instruction in supervisor mode on a
| machine with no coprocessor: KERNEL FAULT, vector 0xB.  Of the eleven calls into fpu_save, fpu_restore
| and fpu_setup in the stock kernel, sendsig's is the only one with no gate in front of it (the others test
| fpu_present, or call prhasfp, which returns it).
|
| build-cross-kernel.sh retargets that one relocation -- sendsig's jsr fpu_setup -- to fpu_setup_gated
| (tools/fpugate-sendsig.py; --no-fpu-gate builds without it).  With an FPU it is a tail jump into the same
| body as before; without one it returns at once, so signal delivery sets up no FPU state.  The same gate
| as the 68040/68060 port's fpu_setup_gated (src/fpuinit060.s), without its 68060 branch.

	.text
	.globl	fpu_setup_gated
fpu_setup_gated:
	tstl	fpu_present
	bnes	Lfg_have
	addql	&1,fpg_skip_n		| no FPU: no FRESTORE in supervisor mode
	rts
Lfg_have:
	addql	&1,fpg_pass_n
	jmp	fpu_setup
	.balign	4

	.data
| Counter block.  Read fpg_magic first: if it is not "FPG!" the addresses are stale.
	.globl	fpg_magic
fpg_magic:
	.long	0x46504721		| "FPG!"
| sendsig asked for FPU setup and was refused (no FPU)
	.globl	fpg_skip_n
fpg_skip_n:
	.long	0
| ... and went on to fpu_setup (an FPU is present)
	.globl	fpg_pass_n
fpg_pass_n:
	.long	0
	.balign	4
