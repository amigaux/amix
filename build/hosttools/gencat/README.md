# gencat (host)

A `gencat` that runs on the build host and writes message catalogues byte
for byte as the AMIX 2.1c `gencat` does, in both of its formats. For the
default format it also writes the `catfile.m` string file itself, so no
host `mkmsgs` is needed. Formats and source syntax: [FORMAT.md](FORMAT.md).

    cc -O2 -Wall -Wextra -o gencat gencat.c
    ./gencat -m out.cat in.msg        # one file, old "malloc" format
    ./gencat out.cat in.msg           # out.cat + out.cat.m
    ./gencat --dump out.cat           # print every message

Test: `sh tests/run.sh`. The files in `tests/expect/` were written by the
stock `gencat` on AMIX 2.1c (on an emulated machine) from `tests/test.msg`,
and this tool writes the same bytes. Before that run they were this tool's
own output, which differed in one rule: the white space after a message
number (see FORMAT.md, "Message line").
