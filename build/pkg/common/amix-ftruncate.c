/*
 * amix-ftruncate.c -- an ftruncate that does not panic the stock kernel.
 *
 *     $CC $AMIX_CFLAGS -c recipes/common/amix-ftruncate.c   (put the .o in LIBS)
 *
 * AMIX 2.1c's ftruncate is fcntl(F_FREESP).  Shrinking a file larger than its
 * direct blocks (~96 KiB) to an EOF that is not block aligned, inside the block
 * that holds the old EOF, faults the kernel: ufs_itrunc -> pvn_vptrunc zeroes
 * the tail and bzero takes a bus error (grimoire quirk 90; measured on the
 * emulated golden 030, recipes/rsync/README.md).  Block-aligned cuts are safe.
 *
 * This strong ftruncate overrides the static truncate.o of usr/ccs/lib/libc.so
 * (whose ftruncate is weak) and calls its _ftruncate only with safe lengths:
 * a shrink to an unaligned EOF becomes a cut at the block boundary below it
 * plus a rewrite of the bytes up to the EOF, read back first.  That needs a
 * readable fd; on a write-only one it fails with EBADF rather than risk the
 * kernel.  Extensions and aligned lengths pass straight through.
 *
 * MIT, this repository.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

int _ftruncate(int, off_t);

int ftruncate(int fd, off_t len)
{
	struct stat st;
	off_t blk, base, pos;
	char *tail;
	long n, k, want;
	int ret = -1;

	if (fstat(fd, &st) < 0)
		return -1;
	blk = st.st_blksize > 8192 ? st.st_blksize : 8192;
	if (len % blk == 0 || st.st_size <= len)
		return _ftruncate(fd, len);
	base = len - len % blk;
	want = (long)(len - base);
	if ((tail = malloc(want)) == NULL) {
		errno = ENOMEM;
		return -1;
	}
	if ((pos = lseek(fd, 0, SEEK_CUR)) < 0 || lseek(fd, base, SEEK_SET) != base)
		goto out;
	for (n = 0; n < want; n += k)
		if ((k = read(fd, tail + n, want - n)) <= 0) {
			if (k < 0 && errno == EINTR) { k = 0; continue; }
			if (k == 0) errno = EIO;
			goto out;
		}
	if (_ftruncate(fd, base) < 0 || lseek(fd, base, SEEK_SET) != base)
		goto out;
	for (n = 0; n < want; n += k)
		if ((k = write(fd, tail + n, want - n)) <= 0) {
			if (k < 0 && errno == EINTR) { k = 0; continue; }
			goto out;
		}
	ret = lseek(fd, pos, SEEK_SET) < 0 ? -1 : 0;
out:
	free(tail);
	return ret;
}
