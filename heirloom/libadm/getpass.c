/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 *
 * Portions Copyright 2026 Jussi Alanärä.  Amix port changes are marked
 * "AMIX PORT" at each site and listed in heirloom/AMIX-PORT.md.
 */
/*
 * Copyright 2006 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 */

/*	from OpenSolaris "getpass.c	1.24	06/04/29 SMI"	*/

/*
 * Portions Copyright (c) 2007 Gunnar Ritter, Freiburg i. Br., Germany
 *
 * Sccsid @(#)getpass.c	1.4 (gritter) 2/25/07
 */

/*	Copyright (c) 1988 AT&T	*/
/*	  All Rights Reserved  	*/


#include <stdio.h>
#include <sys/types.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
/*
 * AMIX PORT: the termio/stropts form below is the native one on SVR4
 * (Amix).  glibc removed <stropts.h> (2.30) and <termio.h> (2.42), so
 * the Linux host build uses POSIX termios instead (from
 * research/heirloom/host-build-fixes.patch, made conditional).
 */
#ifdef	__linux__
#include <termios.h>
#define	GP_GETA(fd, t)	tcgetattr((fd), (t))
#define	GP_SETAF(fd, t)	tcsetattr((fd), TCSAFLUSH, (t))
#define	GP_SETAW(fd, t)	tcsetattr((fd), TCSADRAIN, (t))
#else	/* !__linux__ */
#include <stropts.h>
#include <termio.h>
#define	GP_GETA(fd, t)	ioctl((fd), TCGETA, (t))
#define	GP_SETAF(fd, t)	ioctl((fd), TCSETAF, (t))
#define	GP_SETAW(fd, t)	ioctl((fd), TCSETAW, (t))
#endif	/* __linux__ */

static void catch(int);
static int intrupt;
static char *__getpass(const char *, int);

#define	MAXPASSWD	256	/* max significant characters in password */
#define	SMLPASSWD	8	/* unix standard  characters in password */


char *
getpass(const char *prompt)
{
	return ((char *)__getpass(prompt, SMLPASSWD));
}

char *
getpassphrase(const char *prompt)
{
	return ((char *)__getpass(prompt, MAXPASSWD));
}

static char *
__getpass(const char *prompt, int size)
{
#ifdef	__linux__
	struct termios ttyb;
	tcflag_t flags;
#else
	struct termio ttyb;
	unsigned short flags;
#endif
	char *p;
	int c;
	FILE	*fi;
#ifdef	__sun
	char *pbuf = tsdalloc(_T_GETPASS, MAXPASSWD + 1, NULL);
#else
	char *pbuf = malloc(MAXPASSWD+1);
#endif
	void	(*sig)(int);
#ifdef	__sun
	rmutex_t *lk;
#endif

	if (pbuf == NULL ||
	    (fi = fopen("/dev/tty", "rF")) == NULL)
		return (NULL);
	setbuf(fi, NULL);
	sig = signal(SIGINT, catch);
	intrupt = 0;
	(void) GP_GETA(fileno(fi), &ttyb);
	flags = ttyb.c_lflag;
	ttyb.c_lflag &= ~(ECHO | ECHOE | ECHOK | ECHONL);
	(void) GP_SETAF(fileno(fi), &ttyb);
#ifdef	__sun
	FLOCKFILE(lk, stderr);
#else
	flockfile(stderr);
#endif
	(void) fputs(prompt, stderr);
	p = pbuf;
	while (!intrupt &&
		(c = getc(fi)) != '\n' && c != '\r' && c != EOF) {
		if (p < &pbuf[ size ])
			*p++ = (char)c;
	}
	*p = '\0';
	ttyb.c_lflag = flags;
	(void) GP_SETAW(fileno(fi), &ttyb);
	(void) putc('\n', stderr);
#ifdef	__sun
	FUNLOCKFILE(lk);
#else
	funlockfile(stderr);
#endif
	(void) signal(SIGINT, sig);
	(void) fclose(fi);
	if (intrupt)
		(void) kill(getpid(), SIGINT);
	return (pbuf);
}

/* ARGSUSED */
static void
catch(int x)
{
	intrupt = 1;
}
