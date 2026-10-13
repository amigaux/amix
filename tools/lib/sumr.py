# tools/lib/sumr.py -- the BSD 16-bit rotate checksum, i.e. `sum -r`.
#
# This is the checksum the whole Amix family quotes kernels and files by
# ("sum -r <first field>"): amix-kerntools' miniroot-kernels.md, the boot-proof
# notes, this repo's hdf README. It is the algorithm SVR4 `sum` uses with the
# -r flag AND the algorithm GNU coreutils `sum` uses by default / with -r, so a
# manifest generated with this function HOST-side equals what the Amix box
# prints with `sum -r` (proven: docs/install-iso.md E1 -- "SVR4 sum -r counts
# 512-byte blocks vs GNU's 1024, so only the block column differs"; the checksum
# field is identical).
#
# DO NOT CONFUSE THIS WITH bootchain.py svr4_sum().  They are DIFFERENT
# algorithms for DIFFERENT jobs:
#   * svr4_sum()  (bootchain.py) = the struct-infoblock ib_chksum: a plain
#     byte-sum folded to 16 bits.  It stamps IBLK(unix)/IBLK(boot2) on the
#     medium and is what bootchain-verify.py checks.  It is NOT `sum -r`.
#   * bsd_sum_r() (this file)    = the BSD rotate checksum printed by the box's
#     `sum -r`.  It is what the installer's on-target boot-chain verification
#     compares against, because the miniroot has no way to re-run svr4_sum() but
#     a genuine SVR4 `sum -r` is shipped on the CD (see docs/installer.md).
#
# Stdlib-only.  No proprietary bytes.
#
#   r = 0
#   for each byte c:
#       r = (r >> 1) + ((r & 1) << 15)   # 16-bit rotate-right
#       r = (r + c) & 0xffff
#
# This is the classic BSD `sum`/`sum -r` fold; the rotate-in of the low bit is
# what distinguishes it from a plain sum and is load-bearing.


def bsd_sum_r(buf):
    """SVR4/BSD `sum -r` checksum over buf; returns an int in [0, 0xFFFF]."""
    r = 0
    for c in bytearray(buf):
        r = (r >> 1) + ((r & 1) << 15)
        r = (r + c) & 0xffff
    return r


def sumr_str(buf):
    """`sum -r`'s checksum field, zero-padded to 5 digits as the box prints it."""
    return "%05d" % bsd_sum_r(buf)
