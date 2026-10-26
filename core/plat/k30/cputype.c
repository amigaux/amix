/*
 * cputype.c -- the 030 line's cputype for modules (DDI v1,
 * docs/contracts/C3-2-symbols-and-ddi.md): the 68040/68060 kernels define
 * it, the 030 kernels do not.  Weak, so a kernel that defines its own
 * keeps it.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
__asm__(".weak cputype");
long cputype = 30;
