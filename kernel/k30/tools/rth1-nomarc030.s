| rth1-nomarc030.s -- rth1_nomarc for the k30 module kernel (S4-23 prep; the port's rth1_tail040.s on k46).
| The port's rth1.c (f0a6011 on), built -DRTH1_DLM, calls rth1_nomarc() in rth1_mountroot before rth1_apply.
| It is empty until a core with dlm_marc_root (kernel/dlm core patch 0034, spec 30 sec 3) is linked: then
| dlm-core-link.sh step 7h retargets that one call to dlm_marc_root (the port's patch_dlm_call.py).
	.text
	.globl	rth1_nomarc
rth1_nomarc:
	rts
