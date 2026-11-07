# ftpdfix — the stock `in.ftpd` with downloads that arrive whole

`/usr/sbin/in.ftpd` is Amix 2.1's FTP server (4.3BSD-Tahoe's ftpd), which `inetd` starts for each
connection. This package ships that file with 179 bytes changed, in three places, so that the end of
a download is no longer lost. Everything else is the stock file, byte for byte.

| | sha256 | size |
|---|---|---|
| stock, net's `/usr/sbin/in.ftpd` (`system/MANIFEST.sha256`) | `29048aef103a02d5975b1ce4571d770ad88c0cb1b7a5efdc76cd9c6a1bb3940d` | 69760 |
| this package | `fab610e3bea2251ad0e7d58d147ab72b50b11723c43099a3a807cd8ecd1ac6e4` | 69760 |

Package: `ftpdfix`, category `network`, set `base`, essential. Nothing is compiled and no binary is
kept here: `build.sh` takes the stock file from amix-system at its pin, checks it against
`system/MANIFEST.sha256`, checks the bytes it changes, changes them, reads them back, and checks the
result's sha256. The page `ftpdfix(1M)` is shown for `in.ftpd`; the stock `ftpd(1M)` still
describes the commands.

## Licence

The program is Commodore's, AT&T's and Amiga Corporation's (with the Regents of the University of
California's ftpd in it), and is published, like the rest of the Amix system files, under the
approval described in amix-system's README (section "Licensing"): `LicenseRef-Amix-System`. The
changed bytes, the recipe, the page and this README are ours, under MIT (`LICENSE.amix` in
`/opt/amix/doc/ftpdfix`).

## The fault

The system's TCP, on a close without `SO_LINGER`, throws away the data the peer has not yet
acknowledged, and the connection still ends with an orderly FIN. The stock server closes the data
connection of a download right after its last write, so the end of the file was cut off whenever
the client had not acknowledged it yet. The client saw a short file and the server's `226 Transfer
complete`. Measured in emulation, 8 Mbyte passive-mode downloads at an MSS of 1360: 9 of 20 short,
by 608 to 6848 bytes.

In active mode the stock server sets `SO_LINGER` for 60 seconds, so its close waits for the
acknowledgements. That path of the system's TCP is not safe either: when the client sends after the
close, the connection's control block is freed under the waiting server.

## The fix

The server shuts down its own side of the data connection, reads until the client closes its side,
and only then closes. The client's FIN comes after it has read everything, so by then every byte has
been acknowledged and the close throws nothing away. The wait is bounded: four polls of 15 seconds
at most, so a client that never closes is let go after 60 seconds, and the close then behaves as
the stock one. Neither mode sets `SO_LINGER` any more.

The program does not call `shutdown`; libsocket's `shutdown` is an `I_STR` ioctl to the socket
module (`SI_SHUTDOWN`), and the new routine makes that ioctl itself. Every download (`RETR`, `LIST`,
`NLST`) ends in `retrieve`'s one close of the data connection; uploads (`STOR`) read to the end of
file before they close and are unchanged.

## The bytes

Offsets are file offsets; the text's addresses are the offsets plus `0x80000000`.

| Offset | Stock | Fixed | What |
|---|---|---|---|
| `0x2874` | `4eb9 8000 1818` | `4eb9 8000 8106` | In `retrieve`, between the two `sigset(SIGPIPE)` calls: `jsr fclose@plt` becomes `jsr dclose`, with the same argument on the stack. |
| `0x2de6` | `7201 2d41 ffc8` | `defc 0028 602e` | In `dataconn`, active mode: `addaw #40,%sp; bras 0x80002e1a` pops the two `SO_SNDBUF`/`SO_RCVBUF` calls' arguments and skips the `SO_LINGER {1, 60}` `setsockopt`, to the `connect` (whose retry loop branches to the same place). |
| `0x8106` | `_putspent`, 182 of its 422 bytes | `dclose`, 182 bytes | `_putspent` is linked in from libc's shadow-file code, and nothing in the program calls it: its address appears only in `.symtab`, never in `.dynsym`. The rest of its bytes are left as they are and are never reached. |

`dclose`, assembled with the period toolchain's `as` (`&` marks an immediate there, `|` a comment);
its calls go through the program's own PLT entries:

```
dclose:	linkw	%fp,&-284		| -16 strioctl, -20 how, -28 pollfd, -284 buffer
	moveml	%d2-%d3,%sp@-
	movel	%fp@(8),%sp@-
	jsr	0x80001944		| fflush(fp)
	addqw	&4,%sp
	moveal	%fp@(8),%a0
	moveq	&0,%d2
	moveb	%a0@(13),%d2		| fd = fp->_file
	moveq	&1,%d0
	movel	%d0,%fp@(-20)		| how = 1: no more sends
	movel	&0x4966,%fp@(-16)	| ic_cmd = SI_SHUTDOWN
	moveq	&-1,%d0
	movel	%d0,%fp@(-12)		| ic_timout
	moveq	&4,%d0
	movel	%d0,%fp@(-8)		| ic_len
	lea	%fp@(-20),%a0
	movel	%a0,%fp@(-4)		| ic_dp = &how
	pea	%fp@(-16)
	movel	&0x5308,%sp@-		| I_STR
	movel	%d2,%sp@-
	jsr	0x800016c4		| ioctl(fd, I_STR, &strioctl)
	lea	%sp@(12),%sp
	tstl	%d0
	blts	done
	moveq	&3,%d3			| 4 rounds
loop:	movel	%d2,%fp@(-28)		| pollfd.fd
	movel	&0x00010000,%fp@(-24)	| events POLLIN, revents 0
	movel	&15000,%sp@-
	pea	1:w
	pea	%fp@(-28)
	jsr	0x80001c78		| _poll(&pollfd, 1, 15000)
	lea	%sp@(12),%sp
	tstl	%d0
	blts	done
	beqs	next			| 15 s quiet: the next round
	pea	256:w
	pea	%fp@(-284)
	movel	%d2,%sp@-
	jsr	0x800018f4		| read(fd, buffer, 256)
	lea	%sp@(12),%sp
	tstl	%d0
	bles	done			| end of file: the client has had it all
next:	dbf	%d3,loop
done:	movel	%fp@(8),%sp@-
	jsr	0x80001818		| fclose(fp)
	addqw	&4,%sp
	moveml	%sp@+,%d2-%d3
	unlk	%fp
	rts
```

`SIGPIPE` is ignored around the call, as it was around the stock `fclose`, so a client that has gone
does not end the server in the flush.

## What it does not cover

- **The stock `ftp` client**, and any other program that closes a socket right after writing to it,
  can still lose the end of what it sends: the fault is the system's TCP, and this package fixes only
  the server. Uploads to this server are whole, because the server reads to the end of file before
  it closes.
- **A client that never closes** its side of the data connection waits up to 60 seconds before the
  server answers its next command; after that the close drops what that client had not
  acknowledged, as the stock close did.
- **Reinstalling the stock `net` package** puts the stock file back; reinstall this package after it.

## Install, upgrade and removal

Install it with `apkg`: `apkg update`, then `apkg install ftpdfix`. The installer installs it with
the base set. `inetd` starts a new `in.ftpd` for each connection, so the next connection runs the new
file; sessions already open keep the program they started with.

Once installed, the contents file lists `/usr/sbin/in.ftpd` under both `net` and `ftpdfix`, with the
fixed file's size and sum. The package is essential, and `apkg` refuses to remove it; `pkgrm` would
leave the file in place because `net` claims the path too.

## Tests

In emulation, on the 68060 line and the 68030 line, the stock server and this one in the same boot.
8 Mbyte random files, compared whole by sha256 on the host; the MSS of 1360 is set by the host's
socket, as a link with a smaller MTU does:
- 20 passive-mode and 20 active-mode downloads at an MSS of 1360;
- a client that reads a download to its end and never closes its data connection: the server answers
  its next command after about 60 seconds, and a normal client's at once;
- the transfer rates of the two servers.
