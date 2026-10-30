/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at src/OPENSOLARIS.LICENSE.
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
 * Copyright 2004 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 */

/* Copyright (c) 1984, 1986, 1987, 1988, 1989 AT&T */
/* All Rights Reserved */

/*	from OpenSolaris "runcmd.c	1.15	06/02/27 SMI"	*/

/*
 * Portions Copyright (c) 2007 Gunnar Ritter, Freiburg i. Br., Germany
 *
 * Sccsid @(#)runcmd.c	1.5 (gritter) 2/26/07
 */

/*LINTLIBRARY*/

#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <strings.h>
#include <signal.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <wait.h>
#include <sys/types.h>
#include <pkglib.h>
#include "pkglocale.h"
#include "pkglibmsgs.h"
#include "libadm.h"

#ifndef _STDARG_H
#include "stdarg.h"
#endif

/*
 * Private definitions
 */

/* Maximum number of arguments to pkg_ExecCmdList */

#define	MAX_EXEC_CMD_ARGS	100

/* Size of buffer increments when reading from pipe */

#define	PIPE_BUFFER_INCREMENT	256

static char	errfile[L_tmpnam+1];

/*
 * This is the "argument array" definition that is returned by e_new_args and is
 * used by e_add_args, e_free_args, etc.
 */

struct _argArray_t {
	long	_aaNumArgs;	/* number of arguments set */
	long	_aaMaxArgs;	/* number of arguments allocated */
	char	**_aaArgs;	/* actual arguments */
};

/*
 * Public Methods
 */


void
rpterr(void)
{
	FILE	*fp;
	int	c;

	if (errfile[0]) {
		if (fp = fopen(errfile, "r")) {
			while ((c = getc(fp)) != EOF)
				putc(c, stderr);
			(void) fclose(fp);
		}
		(void) unlink(errfile);
		errfile[0] = '\0';
	}
}

void
ecleanup(void)
{
	if (errfile[0]) {
		(void) unlink(errfile);
		errfile[0] = 0;
	}
}

/*
 * AMIX PORT: DS_DEBUG tracing (set DS_DEBUG=1 in the environment).
 * Logs every esystem() spawn: the exact command, the stdin fd, its
 * seek offset and a peek at the next bytes (restored afterwards, only
 * when the fd is seekable), the raw and decoded wait status, and the
 * child's captured stderr on failure.
 */
static int
ds_debug_on(void)
{
	static int flag = -1;

	if (flag == -1)
		flag = (getenv("DS_DEBUG") != NULL) ? 1 : 0;
	return (flag);
}

static void
ds_debug_fdpeek(const char *tag, int fd)
{
	long	pos;
	unsigned char	pk[16];
	int	n, i;

	pos = lseek(fd, 0L, SEEK_CUR);
	(void) fprintf(stderr, "DS_DEBUG(%s): fd=%d offset=%ld", tag, fd, pos);
	if (pos != -1L) {
		n = read(fd, (char *)pk, sizeof (pk));
		if (n > 0) {
			(void) fprintf(stderr, " next%d=[", n);
			for (i = 0; i < n; i++)
				(void) fputc((pk[i] >= 32 && pk[i] < 127) ?
				    pk[i] : '.', stderr);
			(void) fprintf(stderr, "] hex=");
			for (i = 0; i < (n > 8 ? 8 : n); i++)
				(void) fprintf(stderr, "%02x", pk[i]);
			(void) lseek(fd, pos, SEEK_SET);
		} else {
			(void) fprintf(stderr, " peekread=%d errno=%d",
			    n, errno);
		}
	}
	(void) fprintf(stderr, "\n");
	(void) fflush(stderr);
}

int
esystem(char *cmd, int ifd, int ofd)
{
	char	template[] = "/var/tmp/esystemXXXXXX";
	char	*perrfile;
	int	status = 0;
	pid_t	pid;

	if (close(mkstemp(template)) < 0) {
		progerr(
		    pkg_gt("unable to create temp error file, errno=%d"),
		    errno);
		return (-1);
	}
	unlink(template);
	perrfile = template;
	(void) strlcpy(errfile, perrfile, sizeof (errfile));

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem): spawn cmd=<%s> ifd=%d ofd=%d\n",
		    cmd, ifd, ofd);
		if (ifd > 0)
			ds_debug_fdpeek("esystem.pre", ifd);
	}

	/*
	 * AMIX PORT: if the invoking process inherited SIGCHLD=SIG_IGN
	 * (auto-reap), OUR waitpid() would fail with ECHILD and every
	 * spawned command would be reported as failed (host-reproduced:
	 * a parent with signal(SIGCHLD, SIG_IGN) exec'ing pkgadd makes
	 * every cpio spawn "fail, exit code -1").  Sanitize before
	 * forking; these tools never rely on SIGCHLD handlers.
	 */
	(void) signal(SIGCHLD, SIG_DFL);

	/* flush standard i/o before creating new process */

	(void) fflush(stderr);
	(void) fflush(stdout);

	/*
	 * create new process to execute command in;
	 * vfork() is being used to avoid duplicating the parents
	 * memory space - this means that the child process may
	 * not modify any of the parents memory including the
	 * standard i/o descriptors - all the child can do is
	 * adjust interrupts and open files as a prelude to a
	 * call to exec().
	 */

	pid = vfork();
	if (pid == 0) {
		/*
		 * this is the child process
		 */
		int	i;

		/* reset any signals to default */

		for (i = 0; i < NSIG; i++) {
			(void) sigset(i, SIG_DFL);
		}

		if (ifd > 0) {
			(void) dup2(ifd, STDIN_FILENO);
		}

		if (ofd >= 0 && ofd != STDOUT_FILENO) {
			(void) dup2(ofd, STDOUT_FILENO);
		}

		i = open(errfile, O_WRONLY|O_CREAT|O_TRUNC, 0666);
		if (i >= 0) {
			dup2(i, STDERR_FILENO);
		}

		/* Close all open files except standard i/o */

		closefrom(3);

		/* execute target executable */

		execl("/bin/sh", "/bin/sh", "-c", cmd, NULL);
		progerr(pkg_gt("exec of <%s> failed, errno=%d"), cmd, errno);
		_exit(99);
	} else if (pid < 0) {
		/* fork failed! */

		logerr(pkg_gt("bad vfork(), errno=%d"), errno);
		return (-1);
	}

	/*
	 * this is the parent process
	 */

	sighold(SIGINT);
	pid = waitpid(pid, &status, 0);
	sigrelse(SIGINT);

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem): waitpid=%ld rawstatus=0x%04x\n",
		    (long)pid, (unsigned)status);
	}

	if (pid < 0) {
		return (-1); /* probably interrupted */
	}

	switch (status & 0177) {
		case 0:
		case 0177:
			status = status >> 8;
			/*FALLTHROUGH*/

		default:
			/* terminated by a signal */
			status = status & 0177;
	}

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem): done cmd=<%s> decoded=%d\n",
		    cmd, status);
		if (ifd > 0)
			ds_debug_fdpeek("esystem.post", ifd);
		if (status != 0) {
			FILE	*efp;
			char	eline[512];

			(void) fprintf(stderr,
			    "DS_DEBUG(esystem): child stderr <%s>:\n",
			    errfile);
			if ((efp = fopen(errfile, "r")) != NULL) {
				while (fgets(eline, sizeof (eline),
				    efp) != NULL)
					(void) fprintf(stderr,
					    "DS_DEBUG(esystem): | %s", eline);
				(void) fclose(efp);
			} else {
				(void) fprintf(stderr,
				    "DS_DEBUG(esystem): | (unreadable, errno=%d)\n",
				    errno);
			}
			(void) fflush(stderr);
		}
	}

	if (status == 0) {
		ecleanup();
	}

	return (status);
}

/*
 * AMIX PORT: esystem_bounded() - like esystem(), but the child's
 * stdin is a PIPE carrying exactly 'nbytes' bytes read from 'ifd'.
 *
 * WHY: the native Amix SVR4.0 cpio does not stop at the first
 * TRAILER!!! record - it keeps consuming CONCATENATED archives until
 * EOF (classic pre-Solaris behavior; on-box verified: the datastream
 * metadata pass left ds_fd at EOF and every subsequent part read
 * failed with "Unexpected end-of-archive").  The heirloom datastream
 * design hands cpio the raw stream fd and relies on Solaris/GNU cpio
 * stopping exactly after the archive it read.  Feeding a bounded
 * window through a pipe removes the reliance on ANY cpio trailer
 * behavior (GNU cpio versions differ here too, so the host build
 * uses this path as well).
 *
 * On return 'ifd' is positioned exactly at the end of the window
 * (even if the child stopped reading early: the remainder is
 * lseek'ed over, with a read()-drain fallback).
 */
int
esystem_bounded(char *cmd, int ifd, long nbytes)
{
	char	template[] = "/var/tmp/esystemXXXXXX";
	char	*perrfile;
	char	iobuf[512];
	int	status = 0;
	pid_t	pid;
	int	pfd[2];
	long	remaining;
	int	rd, wr;
	int	feederr = 0;
	void	(*opipe)(int);

	if (close(mkstemp(template)) < 0) {
		progerr(
		    pkg_gt("unable to create temp error file, errno=%d"),
		    errno);
		return (-1);
	}
	unlink(template);
	perrfile = template;
	(void) strlcpy(errfile, perrfile, sizeof (errfile));

	if (pipe(pfd) != 0) {
		progerr(pkg_gt("unable to create pipe, errno=%d"), errno);
		return (-1);
	}

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem_bounded): spawn cmd=<%s> ifd=%d "
		    "nbytes=%ld\n", cmd, ifd, nbytes);
		ds_debug_fdpeek("esystem_bounded.pre", ifd);
	}

	/*
	 * AMIX PORT: if the invoking process inherited SIGCHLD=SIG_IGN
	 * (auto-reap), OUR waitpid() would fail with ECHILD and every
	 * spawned command would be reported as failed (host-reproduced:
	 * a parent with signal(SIGCHLD, SIG_IGN) exec'ing pkgadd makes
	 * every cpio spawn "fail, exit code -1").  Sanitize before
	 * forking; these tools never rely on SIGCHLD handlers.
	 */
	(void) signal(SIGCHLD, SIG_DFL);

	/* flush standard i/o before creating new process */

	(void) fflush(stderr);
	(void) fflush(stdout);

	pid = vfork();
	if (pid == 0) {
		/*
		 * this is the child process
		 */
		int	i;

		/* reset any signals to default */

		for (i = 0; i < NSIG; i++) {
			(void) sigset(i, SIG_DFL);
		}

		(void) dup2(pfd[0], STDIN_FILENO);

		i = open(errfile, O_WRONLY|O_CREAT|O_TRUNC, 0666);
		if (i >= 0) {
			dup2(i, STDERR_FILENO);
		}

		/* closes both pipe ends and ifd (all fds above 2) */

		closefrom(3);

		/* execute target executable */

		execl("/bin/sh", "/bin/sh", "-c", cmd, NULL);
		progerr(pkg_gt("exec of <%s> failed, errno=%d"), cmd, errno);
		_exit(99);
	} else if (pid < 0) {
		/* fork failed! */

		(void) close(pfd[0]);
		(void) close(pfd[1]);
		logerr(pkg_gt("bad vfork(), errno=%d"), errno);
		return (-1);
	}

	/*
	 * this is the parent process: feed exactly nbytes to the child
	 */

	(void) close(pfd[0]);
	opipe = signal(SIGPIPE, SIG_IGN);

	remaining = nbytes;
	while (remaining > 0) {
		rd = read(ifd, iobuf,
		    (remaining > (long)sizeof (iobuf)) ?
		    (unsigned)sizeof (iobuf) : (unsigned)remaining);
		if (rd <= 0) {
			if (ds_debug_on())
				(void) fprintf(stderr,
				    "DS_DEBUG(esystem_bounded): feed read=%d "
				    "errno=%d remaining=%ld\n",
				    rd, errno, remaining);
			feederr = 1;
			break;
		}
		remaining -= rd;
		wr = write(pfd[1], iobuf, (unsigned)rd);
		if (wr != rd) {
			/*
			 * child stopped reading (e.g. -ict listing done):
			 * skip over the rest of the window so ifd ends up
			 * at the archive boundary.
			 */
			if (ds_debug_on())
				(void) fprintf(stderr,
				    "DS_DEBUG(esystem_bounded): feed "
				    "write=%d of %d errno=%d "
				    "remaining=%ld - skipping ahead\n",
				    wr, rd, errno, remaining);
			if (remaining > 0 &&
			    lseek(ifd, remaining, SEEK_CUR) == -1L) {
				/* unseekable: drain by reading */
				while (remaining > 0) {
					rd = read(ifd, iobuf,
					    (remaining >
					    (long)sizeof (iobuf)) ?
					    (unsigned)sizeof (iobuf) :
					    (unsigned)remaining);
					if (rd <= 0)
						break;
					remaining -= rd;
				}
			} else {
				remaining = 0;
			}
			break;
		}
	}

	(void) close(pfd[1]);
	(void) signal(SIGPIPE, opipe);

	sighold(SIGINT);
	pid = waitpid(pid, &status, 0);
	sigrelse(SIGINT);

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem_bounded): waitpid=%ld "
		    "rawstatus=0x%04x feederr=%d\n",
		    (long)pid, (unsigned)status, feederr);
	}

	if (pid < 0) {
		return (-1); /* probably interrupted */
	}

	switch (status & 0177) {
		case 0:
		case 0177:
			status = status >> 8;
			/*FALLTHROUGH*/

		default:
			/* terminated by a signal */
			status = status & 0177;
	}

	if (status == 0 && feederr != 0) {
		status = -1;
	}

	if (ds_debug_on()) {
		(void) fprintf(stderr,
		    "DS_DEBUG(esystem_bounded): done cmd=<%s> decoded=%d\n",
		    cmd, status);
		ds_debug_fdpeek("esystem_bounded.post", ifd);
		if (status != 0) {
			FILE	*efp;
			char	eline[512];

			(void) fprintf(stderr,
			    "DS_DEBUG(esystem_bounded): child stderr <%s>:\n",
			    errfile);
			if ((efp = fopen(errfile, "r")) != NULL) {
				while (fgets(eline, sizeof (eline),
				    efp) != NULL)
					(void) fprintf(stderr,
					    "DS_DEBUG(esystem_bounded): "
					    "| %s", eline);
				(void) fclose(efp);
			}
			(void) fflush(stderr);
		}
	}

	if (status == 0) {
		ecleanup();
	}

	return (status);
}

FILE *
epopen(char *cmd, char *mode)
{
	char	template[] = "/var/tmp/epXXXXXX";
	char	*buffer, *perrfile;
	FILE	*pp;
	size_t	len;
	size_t	alen;

	if (errfile[0]) {
		/* cleanup previous errfile */
		unlink(errfile);
	}

	if (close(mkstemp(template)) < 0) {
		progerr(
		    pkg_gt("unable to create temp error file, errno=%d"),
		    errno);
		return ((FILE *)0);
	}
	perrfile = template;

	if (strlcpy(errfile, perrfile, sizeof (errfile)) > sizeof (errfile)) {
		progerr(pkg_gt("file name max length %d; name is too long: %s"),
						sizeof (errfile), perrfile);
		return ((FILE *)0);
	}

	len = strlen(cmd)+6+strlen(errfile);
	buffer = (char *)calloc(len, sizeof (char));
	if (buffer == NULL) {
		progerr(pkg_gt("no memory in epopen(), errno=%d"), errno);
		return ((FILE *)0);
	}

	if (strchr(cmd, '|')) {
		alen = snprintf(buffer, len, "(%s) 2>%s", cmd, errfile);
	} else {
		alen = snprintf(buffer, len, "%s 2>%s", cmd, errfile);
	}

	if (alen > len) {
		progerr(pkg_gt("command max length %d; cmd is too long: %s"),
								len, cmd);
		return ((FILE *)0);
	}

	pp = popen(buffer, mode);

	free(buffer);
	return (pp);
}

int
epclose(FILE *pp)
{
	int n;

	n = pclose(pp);
	if (n == 0)
		ecleanup();
	return (n);
}

/*
 * Name:	e_ExecCmdArray
 * Synopsis:	Execute Unix command and return results
 * Description:	Execute a Unix command and return results and status
 * Arguments:
 *		r_status - [RO, *RW] - (int *)
 *			Return (exit) status from Unix command:
 *			== -1 : child terminated with a signal
 *			!= -1 : lower 8-bit value child passed to exit()
 *		r_results - [RO, *RW] - (char **)
 *			Any output generated by the Unix command to stdout
 *			and to stderr
 *			== (char *)NULL if no output generated
 *		a_inputFile - [RO, *RO] - (char *)
 *			Pointer to character string representing file to be
 *			used as "standard input" for the command.
 *			== (char *)NULL to use "/dev/null" as standard input
 *		a_cmd - [RO, *RO] - (char *)
 *			Pointer to character string representing the full path
 *			of the Unix command to execute
 *		char **a_args - [RO, *RO] - (char **)
 *			List of character strings representing the arguments
 *			to be passed to the Unix command. The list must be
 *			terminated with an element that is (char *)NULL
 * Returns:	int
 *			== 0 - Command executed
 *				Look at r_status for results of Unix command
 *			!= 0 - problems executing command
 *				r_status and r_results have no meaning;
 *				r_status will be -1
 *				r_results will be NULL
 * NOTE:    	Any results returned is placed in new storage for the
 *		calling method. The caller must use 'free' to dispose
 *		of the storage once the results are no longer needed.
 * NOTE:	If 0 is returned, 'r_status' must be queried to
 *		determine the results of the Unix command.
 * NOTE:	The system "errno" value from immediately after waitpid() call
 *		is preserved for the calling method to use to determine
 *		the system reason why the operation failed.
 */

int
e_ExecCmdArray(int *r_status, char **r_results,
	char *a_inputFile, char *a_cmd, char **a_args)
{
	char		*buffer;
	int		bufferIndex;
	int		bufferSize;
	int		ipipe[2] = {0, 0};
	pid_t		pid;
	pid_t		resultPid;
	int		status;
	int		lerrno;
	int		stdinfile = -1;

	(void) &buffer;
	(void) &bufferIndex;
	(void) &bufferSize;
	(void) &stdinfile;

	/* reset return results buffer pointer */

	if (r_results != (char **)NULL) {
		*r_results = (char *)NULL;
	}

	*r_status = -1;

	/*
	 * See if command exists
	 */

	if (access(a_cmd, F_OK|X_OK) != 0) {
		return (-1);
	}

	/*
	 * See if input file exists
	 */

	if (a_inputFile != (char *)NULL) {
		stdinfile = open(a_inputFile, O_RDONLY);
	} else {
		stdinfile = open("/dev/null", O_RDONLY); /* stdin = /dev/null */
	}

	if (stdinfile < 0) {
		return (-1);
	}

	/*
	 * Create a pipe to be used to capture the command output
	 */

	if (pipe(ipipe) != 0) {
		(void) close(stdinfile);
		return (-1);
	}


	bufferSize = PIPE_BUFFER_INCREMENT;
	bufferIndex = 0;
	buffer = calloc(1, bufferSize);
	if (buffer == (char *)NULL) {
		(void) close(stdinfile);
		return (-1);
	}

	/*
	 * AMIX PORT: if the invoking process inherited SIGCHLD=SIG_IGN
	 * (auto-reap), OUR waitpid() would fail with ECHILD and every
	 * spawned command would be reported as failed (host-reproduced:
	 * a parent with signal(SIGCHLD, SIG_IGN) exec'ing pkgadd makes
	 * every cpio spawn "fail, exit code -1").  Sanitize before
	 * forking; these tools never rely on SIGCHLD handlers.
	 */
	(void) signal(SIGCHLD, SIG_DFL);

	/* flush standard i/o before creating new process */

	(void) fflush(stderr);
	(void) fflush(stdout);

	/*
	 * create new process to execute command in;
	 * vfork() is being used to avoid duplicating the parents
	 * memory space - this means that the child process may
	 * not modify any of the parents memory including the
	 * standard i/o descriptors - all the child can do is
	 * adjust interrupts and open files as a prelude to a
	 * call to exec().
	 */

	pid = vfork();

	if (pid == 0) {
		/*
		 * This is the forked (child) process ======================
		 */

		int	i;

		/* reset any signals to default */

		for (i = 0; i < NSIG; i++) {
			(void) sigset(i, SIG_DFL);
		}

		/* assign stdin, stdout, stderr as appropriate */

		(void) dup2(stdinfile, STDIN_FILENO);
		(void) close(ipipe[0]);		/* close out pipe reader side */
		(void) dup2(ipipe[1], STDOUT_FILENO);
		(void) dup2(ipipe[1], STDERR_FILENO);

		/* Close all open files except standard i/o */

		closefrom(3);

		/* execute target executable */

		(void) execvp(a_cmd, a_args);
		perror(a_cmd);	/* Emit error msg - ends up in callers buffer */
		_exit(0x00FE);
	}

	/*
	 * This is the forking (parent) process ====================
	 */

	(void) close(stdinfile);
	(void) close(ipipe[1]);		/* Close write side of pipe */

	/*
	 * Spin reading data from the child into the buffer - when the read eofs
	 * the child has exited
	 */

	for (;;) {
		ssize_t	bytesRead;

		/* read as much child data as there is available buffer space */

		bytesRead = read(ipipe[0], buffer + bufferIndex,
						bufferSize - bufferIndex);

		/* break out of read loop if end-of-file encountered */

		if (bytesRead == 0) {
			break;
		}

		/* if error, continue if recoverable, else break out of loop */

		if (bytesRead == -1) {
			/* try again: EAGAIN - insufficient resources */

			if (errno == EAGAIN) {
				continue;
			}

			/* try again: EINTR - interrupted system call */

			if (errno == EINTR) {
				continue;
			}

			/* break out of loop - error not recoverable */
			break;
		}

		/* at least 1 byte read: expand buffer if at end */

		bufferIndex += bytesRead;
		if (bufferIndex >= bufferSize) {
			buffer = realloc(buffer,
					bufferSize += PIPE_BUFFER_INCREMENT);
			(void) memset(buffer + bufferIndex, 0,
				bufferSize - bufferIndex);
		}
	}

	(void) close(ipipe[0]);		/* Close read side of pipe */

	/* Get subprocess exit status */

	for (;;) {
		resultPid = waitpid(pid, &status, 0L);
		lerrno = (resultPid == -1 ? errno : 0);

		/* break loop if child process status reaped */

		if (resultPid != -1) {
			break;
		}

		/* break loop if not interrupted out of waitpid */

		if (errno != EINTR) {
			break;
		}
	}

	/*
	 * If the child process terminated due to a call to exit(), then
	 * set results equal to the 8-bit exit status of the child process;
	 * otherwise, set the exit status to "-1" indicating that the child
	 * exited via a signal.
	 */

	*r_status = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

	/* return appropriate output */

	if (!*buffer) {
		/* No contents in output buffer - discard */
		free(buffer);
	} else if (r_results == (char **)NULL) {
		/* Not requested to return results - discard */
		free(buffer);
	} else {
		/* have output and request to return: pass to calling method */
		*r_results = buffer;
	}

	errno = lerrno;
	return (resultPid == -1 ? -1 : 0);
}

/*
 * Name:	e_ExecCmdList
 * Synopsis:	Execute Unix command and return results
 * Description:	Execute a Unix command and return results and status
 * Arguments:
 *		r_status - [RO, *RW] - (int *)
 *			Return (exit) status from Unix command
 *		r_results - [RO, *RW] - (char **)
 *			Any output generated by the Unix command to stdout
 *			and to stderr
 *			== (char *)NULL if no output generated
 *		a_inputFile - [RO, *RO] - (char *)
 *			Pointer to character string representing file to be
 *			used as "standard input" for the command.
 *			== (char *)NULL to use "/dev/null" as standard input
 *		a_cmd - [RO, *RO] - (char *)
 *			Pointer to character string representing the full path
 *			of the Unix command to execute
 *		... - [RO] (?)
 *			Zero or more arguments to the Unix command
 *			The argument list must be ended with (void *)NULL
 * Returns:	int
 *			== 0 - Command executed
 *				Look at r_status for results of Unix command
 *			!= 0 - problems executing command
 *				r_status and r_results have no meaning
 * NOTE:    	Any results returned is placed in new storage for the
 *		calling method. The caller must use 'free' to dispose
 *		of the storage once the results are no longer needed.
 * NOTE:	If LU_SUCCESS is returned, 'r_status' must be queried to
 *		determine the results of the Unix command.
 */

int
e_ExecCmdList(int *r_status, char **r_results,
	char *a_inputFile, char *a_cmd, ...)
{
	va_list		ap;		/* references variable argument list */
	char		*array[MAX_EXEC_CMD_ARGS+1];
	int		argno = 0;

	/*
	 * Create argument array for exec system call
	 */

	bzero(array, sizeof (array));

	va_start(ap, a_cmd);	/* Begin variable argument processing */

	for (argno = 0; argno < MAX_EXEC_CMD_ARGS; argno++) {
		array[argno] = va_arg(ap, char *);
		if (array[argno] == (char *)NULL) {
			break;
		}
	}

	va_end(ap);
	return (e_ExecCmdArray(r_status, r_results, a_inputFile,
								a_cmd, array));
}

/*
 * Name:	e_new_args
 * Description:	create a new argument array for use in exec() calls
 * Arguments:	initialCount - [RO, *RO] - (int)
 *			Initial number of elements to populate the
 *			argument array with - use best guess
 * Returns:	argArray_t *
 *			Pointer to argument array that can be used in other
 *			functions that accept it as an argument
 *			== (argArray_t *)NULL - error
 * NOTE: you must call e_free_args() when the returned argument array is
 * no longer needed so that all storage used can be freed up.
 */

argArray_t *
e_new_args(int initialCount)
{
	argArray_t	*aa;

	/* allocate new argument array structure */

	aa = (argArray_t *)calloc(1, sizeof (argArray_t));
	if (aa == (argArray_t *)NULL) {
		progerr(ERR_MALLOC, strerror(errno), sizeof (argArray_t),
			"<argArray_t>");
		return ((argArray_t *)NULL);
	}

	/* allocate initial argument array */

	aa->_aaArgs = (char **)calloc(initialCount+1, sizeof (char *));
	if (aa->_aaArgs == (char **)NULL) {
		progerr(ERR_MALLOC, strerror(errno),
			(initialCount+1)*sizeof (char *), "<char **>");
		return ((argArray_t *)NULL);
	}

	/* initialize argument indexes */

	aa->_aaNumArgs = 0;
	aa->_aaMaxArgs = initialCount;

	return (aa);
}

/*
 * Name:	e_add_arg
 * Description:	add new argument to argument array for use in exec() calls
 * Arguments:	a_args - [RO, *RW] - (argArray_t *)
 *			Pointer to argument array (previously allocated via
 *			a call to e_new_args) to add the argument to
 *		a_format - [RO, *RO] - (char *)
 *			Pointer to "printf" style format argument
 *		... - [RO, *RO] - (varies)
 *			Arguments as appropriate for format statement
 * Returns:	boolean_t
 *			B_TRUE - success
 *			B_FALSE - failure
 * Examples:
 * - to add an argument that specifies a file descriptor:
 *	int fd;
 *	e_add_arg(aa, "/proc/self/fd/%d", fd);
 * - to add a flag or other known text:
 *	e_add_arg(aa, "-s")
 * - to add random text:
 *	char *random_text;
 *	e_add_arg(aa, "%s", random_text);
 */

/*PRINTFLIKE2*/
boolean_t
e_add_arg(argArray_t *a_args, char *a_format, ...)
{
	char		*rstr = (char *)NULL;
	char		bfr[MAX_CANON];
	size_t		vres = 0;
	va_list		ap;

	/*
	 * double argument array if array is full
	 */

	if (a_args->_aaNumArgs >= a_args->_aaMaxArgs) {
		int	newMax;
		char	**newArgs;

		newMax = a_args->_aaMaxArgs * 2;
		newArgs = (char **)realloc(a_args->_aaArgs,
			(newMax+1) * sizeof (char *));
		if (newArgs == (char **)NULL) {
			progerr(ERR_MALLOC, strerror(errno),
				((newMax+1) * sizeof (char *)), "<char **>");
			return (B_FALSE);
		}
		a_args->_aaArgs = newArgs;
		a_args->_aaMaxArgs = newMax;
	}

	/* determine size of argument to add to list */

	va_start(ap, a_format);
	vres = vsnprintf(bfr, sizeof (bfr), a_format, ap);
	va_end(ap);

	/* if it fit in the built in buffer, use that */
	if (vres < sizeof (bfr)) {
		/* dup text already generated in bfr */
		rstr = strdup(bfr);
		if (rstr == (char *)NULL) {
			progerr(ERR_MALLOC, strerror(errno), vres+2,
				"<char *>");
			return (B_FALSE);
		}
	} else {
		/* allocate space for argument to add */

		rstr = (char *)malloc(vres+2);
		if (rstr == (char *)NULL) {
			progerr(ERR_MALLOC, strerror(errno), vres+2,
				"<char *>");
			return (B_FALSE);
		}

		/* generate argument to add */

		va_start(ap, a_format);
		vres = vsnprintf(rstr, vres+1, a_format, ap);
		va_end(ap);
	}

	/* add argument to the end of the argument array */

	a_args->_aaArgs[a_args->_aaNumArgs++] = rstr;
	a_args->_aaArgs[a_args->_aaNumArgs] = (char *)NULL;

	return (B_TRUE);
}

/*
 * Name:	e_get_argv
 * Description:	return (char **)argv pointer from argument array
 * Arguments:	a_args - [RO, *RW] - (argArray_t *)
 *			Pointer to argument array (previously allocated via
 *			a call to e_new_args) to return argv pointer for
 * Returns:	char **
 *			Pointer to (char **)argv pointer suitable for use
 *			in an exec*() call
 * NOTE: the actual character array is always terminated with a (char *)NULL
 */

char **
e_get_argv(argArray_t *a_args)
{
	return (a_args->_aaArgs);
}

/*
 * Name:	e_get_argc
 * Description:	return (int) argc count from argument array
 * Arguments:	a_args - [RO, *RW] - (argArray_t *)
 *			Pointer to argument array (previously allocated via
 *			a call to e_new_args) to return argc count for
 * Returns:	int
 *			Count of the number of arguments in the argument array
 *			suitable for use in an exec*() call
 */

int
e_get_argc(argArray_t *a_args)
{
	return (a_args->_aaNumArgs);
}

/*
 * Name:	e_free_args
 * Description:	free all storage contained in an argument array previously
 *		allocated by a call to e_new_args
 * Arguments:	a_args - [RO, *RW] - (argArray_t *)
 *			Pointer to argument array (previously allocated via
 *			a call to e_new_args) to free
 * Returns:	void
 * NOTE:	preserves errno (usually called right after e_execCmd*())
 */

void
e_free_args(argArray_t *a_args)
{
	int	i;
	int	lerrno = errno;

	/* free all arguments in the argument array */

	for (i = (a_args->_aaNumArgs-1); i >= 0; i--) {
		(void) free(a_args->_aaArgs[i]);
		a_args->_aaArgs[i] = (char *)NULL;
	}

	/* free argument array */

	(void) free(a_args->_aaArgs);

	/* free argument array structure */

	(void) free(a_args);

	/* restore errno */

	errno = lerrno;
}
