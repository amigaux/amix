/* sysinfo.S -- sysinfo(2) for the shared variant's libraries (ToolTalk and
 * compat's getdomainname call it).  Amix has it only in the static libc.a,
 * whose stub jumps to _cerror with an absolute relocation; this one traps the
 * same way (call 139) and reaches libc.so.1's _cerror through the PLT, as
 * libamixrt's system calls do, so the text needs no relocation.  The static
 * build links libc.a's.  MIT licence, see LICENSE in userland/packages. */
	.text
	.globl	sysinfo
	.type	sysinfo, @function
sysinfo:
	movel	#139, %d0
	trap	#0
	bccs	1f
	jra	_cerror@PLTPC
1:	rts
	.size	sysinfo, .-sysinfo
