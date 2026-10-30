/*
 * ds-repro.c - standalone Amix datastream-reader reproducer.
 *
 * Isolates the on-box failure "process </usr/bin/cpio -ic... -C 512>
 * failed, exit code 1" seen from pkgadd/pkgtrans, in three separately
 * reported experiments:
 *
 *   EXP1 "rawfd": open the datastream, lseek to the first cpio member
 *        (offset 512), spawn "/bin/sh -c 'cpio -ict -C 512 >/dev/null'"
 *        with the file fd dup2()ed to the child's stdin - i.e. a
 *        REGULAR-FILE stdin at a NONZERO OFFSET, exactly what
 *        heirloom's esystem() does and exactly what the successful
 *        manual test (dd skip=1 | cpio: PIPE stdin) does NOT test.
 *
 *   EXP2 "pipe": same cpio command, but stdin is a pipe(); the parent
 *        read()s the file from offset 512 and write()s into the pipe
 *        (in-process replica of the working "dd | cpio" flow), with
 *        every read/write count and errno traced.
 *
 *   EXP3 "heirloom": the exact pkgtrans read-side flow, linked
 *        against the real libpkg: chdir(tmpdir); ds_findpkg(path,
 *        pkg) [runs ds_init: header parse + metadata -icdum extract];
 *        ds_getpkg(path, 1, tmpdir) [runs the part -icdum extract].
 *        Run with DS_DEBUG=1 to get the full libpkg trace (spawn
 *        commands, fd offsets, byte peeks, child stderr on failure).
 *
 * Usage:   ds-repro <datastream> [pkginst] [tmpdir]
 *            pkginst  default DEMOLIB
 *            tmpdir   default /tmp/ds-repro.<pid> (created)
 * Suggest:  DS_DEBUG=1 ds-repro cache/DEMOLIB-1.0.pkg DEMOLIB 2>trace
 *
 * Exit code: bitmask - 1=EXP1 failed, 2=EXP2 failed, 4=EXP3 failed.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä.  A new Amix-port file, not derived from
 * the CDDL heirloom sources -- see heirloom/AMIX-PORT.md, "Licensing".
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <pkglib.h>	/* ds_findpkg, ds_getpkg, ds_close */

#define	BLKSZ	512

#define	TR	(void) fprintf
#define	OUT	stderr

/*
 * Minimal esystem() clone: /bin/sh -c cmd with stdin from 'ifd'.
 * No closefrom, no sigset loop, no errfile - the smallest spawn that
 * matches the heirloom fd-passing geometry.
 */
static int
spawn_stdin(const char *cmd, int ifd)
{
	pid_t	pid;
	int	status;

	(void) fflush(stderr);
	(void) fflush(stdout);
	pid = fork();
	if (pid == 0) {
		if (ifd != 0)
			(void) dup2(ifd, 0);
		(void) execl("/bin/sh", "/bin/sh", "-c", (char *)cmd,
		    (char *)0);
		_exit(99);
	}
	if (pid < 0)
		return (-1);
	if (waitpid(pid, &status, 0) < 0)
		return (-1);
	TR(OUT, "ds-repro:   raw wait status=0x%04x\n", (unsigned)status);
	if ((status & 0177) == 0)
		return ((status >> 8) & 0377);
	return (128 + (status & 0177));
}

/* EXP1: regular-file stdin at offset 512 */
static int
exp_rawfd(const char *path)
{
	int	fd, rc;
	long	pos;
	char	cmd[256];

	TR(OUT, "ds-repro: EXP1 rawfd: file fd at offset %d as cpio stdin\n",
	    BLKSZ);
	if ((fd = open(path, O_RDONLY)) < 0) {
		TR(OUT, "ds-repro: EXP1: open failed errno=%d\n", errno);
		return (1);
	}
	pos = lseek(fd, (long)BLKSZ, SEEK_SET);
	TR(OUT, "ds-repro: EXP1: lseek(512) -> %ld\n", pos);
	(void) sprintf(cmd, "/usr/bin/cpio -ict -C %d > /dev/null", BLKSZ);
	TR(OUT, "ds-repro: EXP1: spawning <%s>\n", cmd);
	rc = spawn_stdin(cmd, fd);
	pos = lseek(fd, 0L, SEEK_CUR);
	TR(OUT, "ds-repro: EXP1: cpio rc=%d, fd offset now %ld\n", rc, pos);
	(void) close(fd);
	return (rc != 0);
}

/* EXP2: pipe-fed stdin (replica of the working dd|cpio) */
static int
exp_pipe(const char *path)
{
	int	fd, rc, pfd[2];
	pid_t	pid;
	int	status;
	long	total = 0;
	int	n, w, nreads = 0;
	char	buf[BLKSZ];
	char	cmd[256];

	TR(OUT, "ds-repro: EXP2 pipe: feed bytes from offset %d via pipe\n",
	    BLKSZ);
	if ((fd = open(path, O_RDONLY)) < 0) {
		TR(OUT, "ds-repro: EXP2: open failed errno=%d\n", errno);
		return (1);
	}
	(void) lseek(fd, (long)BLKSZ, SEEK_SET);
	if (pipe(pfd) != 0) {
		TR(OUT, "ds-repro: EXP2: pipe failed errno=%d\n", errno);
		(void) close(fd);
		return (1);
	}
	(void) sprintf(cmd, "/usr/bin/cpio -ict -C %d > /dev/null", BLKSZ);
	TR(OUT, "ds-repro: EXP2: spawning <%s>\n", cmd);
	(void) fflush(stderr);
	pid = fork();
	if (pid == 0) {
		(void) dup2(pfd[0], 0);
		(void) close(pfd[0]);
		(void) close(pfd[1]);
		(void) close(fd);
		(void) execl("/bin/sh", "/bin/sh", "-c", cmd, (char *)0);
		_exit(99);
	}
	if (pid < 0) {
		TR(OUT, "ds-repro: EXP2: fork failed errno=%d\n", errno);
		return (1);
	}
	(void) close(pfd[0]);
	(void) signal(SIGPIPE, SIG_IGN);
	while ((n = read(fd, buf, BLKSZ)) > 0) {
		nreads++;
		w = write(pfd[1], buf, (unsigned)n);
		if (w != n) {
			TR(OUT, "ds-repro: EXP2: short write %d of %d "
			    "(errno=%d) after %ld bytes - child done?\n",
			    w, n, errno, total);
			break;
		}
		total += n;
	}
	if (n < 0)
		TR(OUT, "ds-repro: EXP2: read errno=%d\n", errno);
	TR(OUT, "ds-repro: EXP2: fed %ld bytes in %d reads\n", total, nreads);
	(void) close(pfd[1]);
	(void) close(fd);
	if (waitpid(pid, &status, 0) < 0) {
		TR(OUT, "ds-repro: EXP2: waitpid errno=%d\n", errno);
		return (1);
	}
	if ((status & 0177) == 0)
		rc = (status >> 8) & 0377;
	else
		rc = 128 + (status & 0177);
	TR(OUT, "ds-repro: EXP2: cpio rc=%d (raw 0x%04x)\n",
	    rc, (unsigned)status);
	return (rc != 0);
}

/* EXP3: exact heirloom/pkgtrans flow through libpkg */
static int
exp_heirloom(const char *path, const char *pkg, const char *tmpdir)
{
	int	nparts, n;
	char	lscmd[512];

	TR(OUT, "ds-repro: EXP3 heirloom: libpkg ds_findpkg/ds_getpkg "
	    "into <%s>\n", tmpdir);
	if (mkdir(tmpdir, 0777) != 0 && errno != EEXIST) {
		TR(OUT, "ds-repro: EXP3: mkdir errno=%d\n", errno);
		return (1);
	}
	if (chdir(tmpdir) != 0) {
		TR(OUT, "ds-repro: EXP3: chdir errno=%d\n", errno);
		return (1);
	}
	nparts = ds_findpkg((char *)path, (char *)pkg);
	TR(OUT, "ds-repro: EXP3: ds_findpkg -> nparts=%d\n", nparts);
	if (nparts < 0)
		return (1);
	n = ds_getpkg((char *)path, 1, (char *)tmpdir);
	TR(OUT, "ds-repro: EXP3: ds_getpkg(part 1) -> %d\n", n);
	(void) ds_close(1);
	if (n != 0)
		return (1);
	TR(OUT, "ds-repro: EXP3: extraction complete; listing:\n");
	(void) sprintf(lscmd, "ls -lR %s 1>&2", tmpdir);
	(void) fflush(stderr);
	(void) system(lscmd);
	return (0);
}

int
main(int argc, char **argv)
{
	const char	*path, *pkg, *tmpdir;
	char	tdbuf[128];
	int	rc = 0;

	if (argc < 2) {
		TR(OUT, "usage: ds-repro <datastream> [pkginst] [tmpdir]\n"
		    "  (run with DS_DEBUG=1 for the full libpkg trace)\n");
		return (64);
	}
	path = argv[1];
	pkg = (argc > 2) ? argv[2] : "DEMOLIB";
	if (argc > 3) {
		tmpdir = argv[3];
	} else {
		(void) sprintf(tdbuf, "/tmp/ds-repro.%ld", (long)getpid());
		tmpdir = tdbuf;
	}

	TR(OUT, "ds-repro: datastream=<%s> pkginst=<%s> DS_DEBUG=%s\n",
	    path, pkg, getenv("DS_DEBUG") ? "on" : "off (set DS_DEBUG=1!)");

	if (exp_rawfd(path))
		rc |= 1;
	if (exp_pipe(path))
		rc |= 2;
	if (exp_heirloom(path, pkg, tmpdir))
		rc |= 4;

	TR(OUT, "ds-repro: RESULT mask=%d (1=rawfd 2=pipe 4=heirloom; "
	    "0=all passed)\n", rc);
	return (rc);
}
