/*
 * audioctl2.c -- audioctl.c (the 040/060 line's) one form at a time, each call under alarm(10), progress flushed
 * before each call, so a call that never returns is named.  audioctl2 ITER FORM  (FORM: s = I_STR right length,
 * expect 0; w = I_STR wrong length, expect -1 EINVAL; z = I_STR with ic_len 0 (no data block), expect -1 EINVAL;
 * t = transparent ioctl(fd, cmd, &v), expect 0).  Both requests each round.
 *
 * Form z on a kernel without the audio fix (68030 cut -75 and before, the 040/060 line's -65 and before) panics the
 * kernel at the first call: run it only where the fix is, or as the last thing on a box that may go down.
 *
 * Needs /dev/audio (c 46 0) and Paula's interrupts (in emulation sound_output=interrupts; without them every open
 * fails with EIO).  Build: m68k-cbm-sysv4-gcc -O -m68020 -o audioctl2 audioctl2.c (gcc-cross-amix at its pin).
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stropts.h>

#define AUIOC		('U'<<8)
#define AUDIO_VOLUME	(AUIOC|1)
#define AUDIO_PERIOD	(AUIOC|2)

static void ring(int s) { signal(SIGALRM, ring); }

int main(int ac, char **av)
{
	int iter = ac > 1 ? atoi(av[1]) : 50, fd, i, k, r, v, ok = 0, rc0 = 0, einval = 0, eintr = 0, other = 0;
	char f = ac > 2 ? av[2][0] : 's';
	static const int cmds[2] = { AUDIO_VOLUME, AUDIO_PERIOD }, vals[2] = { 32, 400 };
	struct strioctl s;
	signal(SIGALRM, ring);
	if ((fd = open("/dev/audio", O_WRONLY)) < 0) { perror("open /dev/audio"); return 2; }
	for (i = 0; i < iter; i++)
		for (k = 0; k < 2; k++) {
			v = vals[k];
			if (i < 2) { printf("call %d %c %s\n", i, f, k ? "PERIOD" : "VOLUME"); fflush(stdout); }
			alarm(10); errno = 0;
			if (f == 't') r = ioctl(fd, cmds[k], &v);
			else { s.ic_cmd = cmds[k]; s.ic_timout = 5; s.ic_len = f == 'w' ? 2 : f == 'z' ? 0 : sizeof v; s.ic_dp = (char *)&v; r = ioctl(fd, I_STR, &s); }
			alarm(0);
			if (r == 0) rc0++; else if (errno == EINVAL) einval++; else if (errno == EINTR) { eintr++; printf("call %d %c %d: EINTR (no answer in 10 s)\n", i, f, k); fflush(stdout); if (eintr >= 3) goto out; } else { other++; printf("call %d: errno %d\n", i, errno); }
		}
out:
	ok = f == 'w' || f == 'z' ? einval == 2 * iter : rc0 == 2 * iter;
	printf("RES audioctl2 %c x%d: rc0 %d EINVAL %d EINTR %d other %d -- %s\n", f, iter, rc0, einval, eintr, other, ok ? "ok" : "WRONG");
	close(fd);
	return !ok;
}
