/*
 * monswctl.c -- the /dev/monsw box tool (P-8): read and set the monitor-switch
 * configuration, switch the screen, hold the switch on RTG for a command.
 *
 *   monswctl [-d dev] get           the struct monsw_info fields, one per line
 *   monswctl [-d dev] status        one line: value, its meaning, source, state
 *   monswctl [-d dev] set <value>   MONSWIOC_SETCFG; root only; -1 unsets
 *   monswctl [-d dev] rtg [cmd...]  switch to RTG, run cmd (else wait for EOF),
 *                                   back to native however that ends
 *   monswctl [-d dev] native        switch to native video
 *
 * The value is the Z3660 firmware's monitor_switch bit sum (sys/monsw.h):
 * 1 CTS, 2 SEL, 16 CTS level flag, 32 SEL level flag; the owner's boxes use 34.
 * Decimal or 0x-hex; any other bit is refused here before the kernel sees it.
 *
 * RTG is held only while the device is open: the kernel returns the switch to
 * native on the last close, so `rtg` keeps the descriptor for the command's
 * lifetime (or, without a command, until stdin ends or a signal kills it).
 * The X servers do not use this device -- they ask their own RTG device
 * (SVGAIOCSetMonitorSwitch), and a line-switched card's driver calls monsw_set().
 *
 * Plain C89 with prototypes; gcc 2.7.2.3 (m68k-cbm-sysv4) and any host cc.  Built by
 * monsw/tool/Makefile against kernel/modules/include/sys/monsw.h; installed as
 * /usr/sbin/monswctl by the monsw package; page monswctl(1M).
 * Exit: 0 done, 1 the device or the kernel refused, 2 usage.
 *
 * MONSW_TESTDOUBLE: the host selftest compiles the same source against a test
 * double for open/ioctl/close (testdouble.c) so the argument handling and the
 * call sequence are proved without a box.  The production build calls libc.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/monsw.h>

#define MONSWCTL_VERSION "1.0"
#define MONSW_DEV "/dev/monsw"

#ifdef MONSW_TESTDOUBLE
extern int td_open(const char *, int);
extern int td_ioctl(int, int, long);
extern int td_close(int);
#define MONSW_OPEN(p)       td_open(p, O_RDWR)
#define MONSW_IOCTL(f, r, a) td_ioctl(f, r, (long)(a))
#define MONSW_CLOSE(f)      td_close(f)
#else
#define MONSW_OPEN(p)       open(p, O_RDWR)
#define MONSW_IOCTL(f, r, a) ioctl(f, r, a)
#define MONSW_CLOSE(f)      close(f)
#endif

static const char *prog = "monswctl";

static void
usage(void)
{
	fprintf(stderr,
	    "usage: %s [-d dev] get | status | set <value> | rtg [cmd ...] | native\n"
	    "  value: bit sum of 1 CTS, 2 SEL, 16 CTS-low=RTG, 32 SEL-low=RTG (-1 unsets)\n"
	    "  dev defaults to %s (c 52 0)\n", prog, MONSW_DEV);
}

/* The value's meaning, in the header's words. */
static void
describe(int cfg, char *buf)
{
	if (cfg == 0) {
		strcpy(buf, "no line");
		return;
	}
	buf[0] = '\0';
	if (cfg & MONSW_CTS) {
		strcat(buf, "CTS ");
		strcat(buf, (cfg & MONSW_CTSLVL) ? "low=RTG" : "high=RTG");
	}
	if (cfg & MONSW_SEL) {
		if (buf[0])
			strcat(buf, ", ");
		strcat(buf, "SEL ");
		strcat(buf, (cfg & MONSW_SELLVL) ? "low=RTG" : "high=RTG");
	}
	if ((cfg & MONSW_VALID) != cfg)
		strcat(buf, ", invalid bits");
}

static const char *
source_name(int src)
{
	switch (src) {
	case MONSW_SRC_NONE:  return "none";
	case MONSW_SRC_SEED:  return "seed";
	case MONSW_SRC_SET:   return "set";
	case MONSW_SRC_PATCH: return "patched";
	}
	return "?";
}

static const char *
state_name(int st)
{
	switch (st) {
	case 1:  return "rtg";
	case 0:  return "native";
	case -1: return "none";
	}
	return "?";
}

/*
 * Parse a configuration value: decimal or 0x-hex, -1 allowed when unset_ok.
 * Returns 0 on success with *out set, -1 on a value this tool will not send.
 */
static int
parse_value(const char *s, int unset_ok, int *out)
{
	char *end;
	long v;

	if (s == NULL || *s == '\0')
		return -1;
	errno = 0;
	v = strtol(s, &end, 0);
	if (errno != 0 || *end != '\0' || end == s)
		return -1;
	if (v == -1 && unset_ok) {
		*out = -1;
		return 0;
	}
	if (v < 0 || v > MONSW_VALID || (v & ~MONSW_VALID))
		return -1;
	*out = (int)v;
	return 0;
}

static int
open_dev(const char *dev)
{
	int fd, e;

	fd = MONSW_OPEN(dev);
	if (fd >= 0)
		return fd;
	e = errno;
	if (e == ENOENT)
		fprintf(stderr, "%s: %s: no such node (mknod %s c 52 0)\n", prog, dev, dev);
	else if (e == ENXIO || e == ENODEV)
		fprintf(stderr, "%s: %s: no driver behind the node (a kernel without monsw?)\n",
		    prog, dev);
	else
		fprintf(stderr, "%s: %s: %s\n", prog, dev, strerror(e));
	return -1;
}

static int
do_getcfg(int fd, struct monsw_info *mi)
{
	memset(mi, 0, sizeof *mi);
	if (MONSW_IOCTL(fd, MONSWIOC_GETCFG, mi) < 0) {
		fprintf(stderr, "%s: GETCFG: %s\n", prog, strerror(errno));
		return -1;
	}
	return 0;
}

static int
cmd_get(int fd)
{
	struct monsw_info mi;
	char what[64];

	if (do_getcfg(fd, &mi) < 0)
		return 1;
	describe(mi.mi_config, what);
	printf("config=%d (%s)\n", mi.mi_config, what);
	printf("source=%d (%s)\n", mi.mi_source, source_name(mi.mi_source));
	printf("state=%d (%s)\n", mi.mi_state, state_name(mi.mi_state));
	printf("holder=%d\n", mi.mi_holder);
	printf("ncards=%d\n", mi.mi_ncards);
	return 0;
}

static int
cmd_status(int fd)
{
	struct monsw_info mi;
	char what[64];

	if (do_getcfg(fd, &mi) < 0)
		return 1;
	describe(mi.mi_config, what);
	printf("monsw: value %d (%s) from %s; state %s; holder %s; %d card%s\n",
	    mi.mi_config, what, source_name(mi.mi_source), state_name(mi.mi_state),
	    mi.mi_holder ? "yes" : "no", mi.mi_ncards, mi.mi_ncards == 1 ? "" : "s");
	return 0;
}

static int
cmd_set(int fd, int value)
{
	int e;

	if (MONSW_IOCTL(fd, MONSWIOC_SETCFG, value) < 0) {
		e = errno;
		if (e == EBUSY)
			fprintf(stderr, "%s: SETCFG refused: the value is patched into the kernel\n", prog);
		else if (e == EPERM || e == EACCES)
			fprintf(stderr, "%s: SETCFG refused: root only\n", prog);
		else if (e == EINVAL)
			fprintf(stderr, "%s: SETCFG refused: the kernel does not take %d\n", prog, value);
		else
			fprintf(stderr, "%s: SETCFG: %s\n", prog, strerror(e));
		return 1;
	}
	return 0;
}

static int
cmd_native(int fd)
{
	if (MONSW_IOCTL(fd, MONSWIOC_NATIVE, 0) < 0) {
		fprintf(stderr, "%s: NATIVE: %s\n", prog, strerror(errno));
		return 1;
	}
	return 0;
}

/*
 * RTG for the length of a command, or of stdin.  The explicit NATIVE at the end
 * is for the reader; the close would do it too, and does when we are killed.
 */
static int
cmd_rtg(int fd, char **argv)
{
	int st = 0, rc = 0, c;
	pid_t pid, w;

	if (MONSW_IOCTL(fd, MONSWIOC_RTG, 0) < 0) {
		fprintf(stderr, "%s: RTG: %s\n", prog, strerror(errno));
		return 1;
	}
	if (argv[0] != NULL) {
		pid = fork();
		if (pid < 0) {
			fprintf(stderr, "%s: fork: %s\n", prog, strerror(errno));
			rc = 1;
		} else if (pid == 0) {
			execvp(argv[0], argv);
			fprintf(stderr, "%s: %s: %s\n", prog, argv[0], strerror(errno));
			_exit(127);
		} else {
			do {
				w = wait(&st);
			} while (w != pid && !(w < 0 && errno != EINTR));
			if (w < 0)
				rc = 1;
			else if ((st & 0xff) != 0)
				rc = 128 + (st & 0x7f);		/* killed by a signal */
			else
				rc = (st >> 8) & 0xff;
		}
	} else {
		fprintf(stderr, "%s: RTG until end of input (^D) or a signal\n", prog);
		while ((c = getchar()) != EOF)
			;
	}
	if (cmd_native(fd) != 0 && rc == 0)
		rc = 1;
	return rc;
}

int
main(int argc, char **argv)
{
	const char *dev = MONSW_DEV;
	const char *cmd;
	int fd, rc, value = 0, i = 1;

	if (argc > 1 && strcmp(argv[1], "-d") == 0) {
		if (argc < 3) {
			usage();
			return 2;
		}
		dev = argv[2];
		i = 3;
	} else if (argc > 1 && strncmp(argv[1], "-d", 2) == 0) {
		dev = argv[1] + 2;
		i = 2;
	} else if (argc > 1 && (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0)) {
		usage();
		return 0;
	}
	if (i >= argc) {
		usage();
		return 2;
	}
	cmd = argv[i];
	if (strcmp(cmd, "set") == 0) {
		if (i + 2 != argc) {
			usage();
			return 2;
		}
		if (parse_value(argv[i + 1], 1, &value) < 0) {
			fprintf(stderr, "%s: '%s' is not a monitor-switch value (bits 1 2 16 32, or -1)\n",
			    prog, argv[i + 1]);
			return 2;
		}
	} else if (strcmp(cmd, "get") == 0 || strcmp(cmd, "status") == 0 ||
	    strcmp(cmd, "native") == 0) {
		if (i + 1 != argc) {
			usage();
			return 2;
		}
	} else if (strcmp(cmd, "rtg") != 0) {
		usage();
		return 2;
	}

	fd = open_dev(dev);
	if (fd < 0)
		return 1;
	if (strcmp(cmd, "get") == 0)
		rc = cmd_get(fd);
	else if (strcmp(cmd, "status") == 0)
		rc = cmd_status(fd);
	else if (strcmp(cmd, "set") == 0)
		rc = cmd_set(fd, value);
	else if (strcmp(cmd, "native") == 0)
		rc = cmd_native(fd);
	else
		rc = cmd_rtg(fd, argv + i + 1);
	MONSW_CLOSE(fd);
	return rc;
}
