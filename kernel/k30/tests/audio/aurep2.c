/*
 * aurep2.c -- aurep.c (the 040/060 line's) with a ramp that does not repeat within the write and a log of every
 * buffer load:
 * one write() of N bytes, byte i = (i >> 8) & 0x7f, so each 8 KiB chunk starts with its own value (0, 32, 64, 96 for
 * the chunks at 0, 8, 16 and 24 KiB).  audio_channel[4] (48 bytes each) is read through /dev/kmem at ADDR every
 * 50 ms; every change of a buffer's (byte count, first byte) on the attached channel is a load and is printed, with
 * the chunk the first byte names.  A chunk loaded twice is a replay.  aurep2 ADDR(hex) N P T
 *
 * Needs /dev/audio (c 46 0) and Paula's interrupts (in emulation sound_output=interrupts; without them every open
 * fails with EIO).  Build: m68k-cbm-sysv4-gcc -O -m68020 -o aurep2 aurep2.c (gcc-cross-amix at its pin).
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stropts.h>
#include <sys/types.h>
#include <sys/times.h>
#include <poll.h>

#define AUIOC		('U'<<8)
#define AUDIO_PERIOD	(AUIOC|2)
#define CHS 48

static unsigned long g32(unsigned char *p) { return ((unsigned long)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

int main(int ac, char **av)
{
	unsigned long addr; int n, per, t, fd, km, i, polls, drained = -1, loads = 0, repl = 0, seen[128];
	int last_nb[3] = { -1, -1, -1 }, last_fb[3] = { -1, -1, -1 };
	unsigned char ch[4 * CHS], b; char *buf; struct strioctl s; struct tms tm; long t0, now, hz = sysconf(_SC_CLK_TCK);
	if (ac != 5) { fprintf(stderr, "usage: aurep2 ADDR N P T\n"); return 2; }
	addr = strtoul(av[1], 0, 16); n = atoi(av[2]); per = atoi(av[3]); t = atoi(av[4]);
	memset(seen, 0, sizeof seen);
	if ((km = open("/dev/kmem", O_RDONLY)) < 0) { perror("/dev/kmem"); return 2; }
	if ((fd = open("/dev/audio", O_WRONLY)) < 0) { perror("/dev/audio"); return 2; }
	s.ic_cmd = AUDIO_PERIOD; s.ic_timout = 5; s.ic_len = sizeof per; s.ic_dp = (char *)&per;
	if (ioctl(fd, I_STR, &s) < 0) perror("AUDIO_PERIOD");
	buf = malloc(n);
	for (i = 0; i < n; i++) buf[i] = (i >> 8) & 0x7f;
	t0 = times(&tm);
	if (write(fd, buf, n) != n) { perror("write"); return 2; }
	for (polls = 0; polls < t * 20; polls++) {
		int c, att = 0;
		if (lseek(km, addr, 0) == -1 || read(km, ch, sizeof ch) != sizeof ch) { perror("kmem read"); return 2; }
		now = times(&tm);
		for (c = 0; c < 4; c++) {
			unsigned char *p = ch + c * CHS; unsigned long cl = g32(p + 12);
			if (!cl) continue;
			att++;
			for (i = 0; i < 3; i++) {
				int nb = (p[28 + 2 * i] << 8) | p[29 + 2 * i], fb = -1; unsigned long bp = g32(p + 36 + 4 * i);
				if (nb && bp && lseek(km, bp, 0) != -1 && read(km, &b, 1) == 1) fb = b;
				if (nb && (nb != last_nb[i] || fb != last_fb[i])) {
					loads++;
					if (fb >= 0 && fb < 128 && seen[fb]++) repl++;
					if (loads <= 40) printf("  t=%ld ch%d buf%d load: %d bytes, first %d (chunk at %d KiB)%s\n", (now - t0) * 1000 / hz,
					    c, i, nb, fb, fb * 256 / 1024, fb >= 0 && fb < 128 && seen[fb] > 1 ? " AGAIN" : "");
				}
				last_nb[i] = nb; last_fb[i] = fb;
			}
		}
		if (!att && polls > 1) { drained = (now - t0) * 1000 / hz; break; }
		poll((struct pollfd *)0, 0, 50);
	}
	printf("RES aurep2 N %d P %d: expected %ld ms, %s %d ms; %d buffer loads, %d of a chunk already loaded\n", n, per, (long)n * per / 3547L,
	       drained >= 0 ? "drained after" : "NOT DRAINED within", drained >= 0 ? drained : t * 1000, loads, repl);
	close(fd);
	return drained < 0 || repl;
}
