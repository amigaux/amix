# gencat (host)

A `gencat` that runs on the build host and writes message catalogues byte
for byte as the AMIX 2.1c `gencat` does, in both of its formats. For the
default format it also writes the `catfile.m` string file itself, so no
host `mkmsgs` is needed. Formats and source syntax: [FORMAT.md](FORMAT.md).

    cc -O2 -Wall -Wextra -o gencat gencat.c
    ./gencat -m out.cat in.msg        # one file, old "malloc" format
    ./gencat out.cat in.msg           # out.cat + out.cat.m
    ./gencat --dump out.cat           # print every message

Test: `sh tests/run.sh`. The files in `tests/expect/` were written by this
tool. They are the byte reference until they are confirmed against
`gencat` running on AMIX.
