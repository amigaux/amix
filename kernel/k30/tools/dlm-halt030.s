| dlm-halt030.s -- the k30 module kernel's halt-pass shims (S4-21, kernel/dlm core patch 0030).
| tools/patch-dlm-halt030.py retargets mdboot's `jsr haltsys` and `jsr rtnfirm` here: the module halt pass runs,
| then the stock routine is entered with mdboot's own return address and argument (jmp, not jsr).
| dlm_halt clobbers only the scratch registers a call site already gives up.
	.text
	.globl	dlm_halt_haltsys
dlm_halt_haltsys:
	jsr	dlm_halt
	jmp	haltsys
	.globl	dlm_halt_rtnfirm
dlm_halt_rtnfirm:
	jsr	dlm_halt
	jmp	rtnfirm
