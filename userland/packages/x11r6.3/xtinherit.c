/*
 * xtinherit.c -- _XtInherit for programs linked against the shared libXt, the
 * one function of libXtInherit.a (the shared variant).
 *
 * A widget class asks to inherit a method by storing _XtInherit's address in
 * its class record (XtInheritRealize and the rest), and libXt recognises the
 * request by comparing with that address.  A program's code takes the address
 * through its PLT entry, and Amix's runtime linker does not bind the
 * library's own reference to that entry: the two addresses differ and a
 * class defined in the program inherits nothing.  Linked into the program
 * (-Wl,-u,_XtInherit -lXtInherit, ahead of -lXt), this definition is the
 * program's own, ld exports it because libXt.so refers to it, and the runtime
 * linker, which searches the program first, binds libXt and every other
 * library to it: one address everywhere.
 *
 * A stopgap for the stock runtime linker: a runtime linker that honours a
 * program's canonical PLT address, or programs built without one, make it
 * unnecessary.  It does not call Xt (a program linked with it need not use
 * Xt), and it is position-independent, so a shared library it ends up in
 * gets no text relocation.  It is reached only by a class that inherits from
 * a class that defines nothing to inherit, as Xt's own _XtInherit is.
 *
 * MIT licence, see LICENSE in userland/packages.
 */
#include <stdio.h>
#include <stdlib.h>

void _XtInherit(void)
{
	fputs("X Toolkit Error: Unresolved inheritance operation\n", stderr);
	exit(1);
}
