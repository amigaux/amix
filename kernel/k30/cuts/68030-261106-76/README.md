# Cut 68030-261106-76

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `70e865e`: -75's recipe with two stock defects
fixed, one in /dev/audio and one in TCP's close.

- **/dev/audio answers each request once, and a long write plays once.** In the stock audioioctl the AUDIO_VOLUME
  and AUDIO_PERIOD cases sent their reply and then fell through to the common tail, which sent the same message again
  as M_IOCACK with error 0, so a refused request (the wrong length) reported success. The stock audiointr refilled a
  channel buffer from a message too long for it without moving past what it copied, so the same bytes were copied
  again at every refill. `tools/patch_audio_replies.py`, after amix-paula's three patchers, makes the four breaks
  returns (the two acks set ioc_rval and ioc_error to 0 themselves, as only the tail did) and advances b_rptr in both
  refill places, as postaudio does. It takes only the audio.c those three make (1f43c5ff) and must give 0fc359bd; the
  040/060 line runs the same file byte for byte. On by default from `ce0573f`, `--no-audio-replies` without.
- **A TCP close without SO_LINGER sends its unsent data and the FIN before the stream is freed.** The stock tcpclose
  kept the data only under SO_LINGER with a time; otherwise it dropped what was queued and the FIN followed a prefix.
  `src/tcpclose_lg.c` (the same file on the 040/060 line) gives an endpoint without SO_LINGER SO_LINGER with 60 s and
  calls the stock tcpclose, which then waits until the data and the FIN are acknowledged (at most 60 s, or a signal);
  a program's own SO_LINGER, {1, 0} included, is kept. `tools/tcpclose-retarget.py` makes it the close of TCP's upper
  read queue after the link (one relocation; tcpclose pinned by digest). On by default from `70e865e`,
  `--no-tcp-close-fix` without.

Evidence, in emulation (A3000, 68030, 64 MiB unless said), by the build each row ran on. "The trial" is
68030-261106-97, built from the working tree that became `70e865e`: its unix.sym is this cut's byte for byte and its
audio.c is 0fc359bd.

- This cut, TCP: a guest sending 8 MiB in 8 KiB writes and closing without SO_LINGER, the host reading at full speed:
  0 of 10 short with the guest listening, 0 of 6 connecting, 0 of 10 in.ftpd passive RETR; SO_LINGER 60 0 of 3;
  SO_LINGER {1, 0} reset 3 of 3. Each transfer about 11 s. Three 8 MiB ftp puts and gets over the A2065: 22.4,
  19.6 and 20.8 s, and 7.5 s each, the copies equal, no frame missed or dropped.
- -75, the same TCP cases in one run beside the trial's: 2 of 6 short listening (9368 and 892 bytes) and 2 of 6
  in.ftpd passive RETR short (608 and 892 bytes, "226 Transfer complete"); the trial 0 of 6 and 0 of 6; with the host
  reading at 256 KiB/s none were short on either; ftp puts 21.3, 20.0 and 22.3 s on -75, 22.2, 20.3 and 20.3 s on the
  trial, gets about 7.4 s on both.
- Audio, with Paula's interrupts emulated: this cut answered 100 of 100 wrong-length requests with EINVAL and the
  right-length and transparent forms with 0; -75 answered the wrong-length ones with 0, 100 of 100, and in an
  earlier run its first request had not returned 15 minutes later. A 32 KiB write at period 200 (1.8 s of sound) was still refilling full
  buffers after 30 s on -75 (and after 20 s in a second run) and drained after 1.4 and 1.5 s on this cut in two runs (its last buffer queued); 4 and 12 KiB drained on
  both.
- This cut, -75's rows: `tests/sparsehole` at 16 MiB 0 pages wrong in all four modes; rnd no bad block in 200000
  operations; `tests/wcost`'s 20000 random rewrites 24 and 25 s, 64 MB copied by 8 KiB 46 and 46 s (-75: 24 and 25,
  47 and 46).

Against -75 the shipped files differ in `unix` (audio.o, tcpclose_lg.o, the retarget, the build id) and so `unix.brel`
(1543228 bytes), `unix.sym` and `kabi`; `mod.d/ufs` and `mod.d/s5` differ only in the build id they carry (one byte
each).

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-76` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `70e865e`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `70e865e`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: its three patchers make audio.c 1f43c5ff, which
  `tools/patch_audio_replies.py` makes 0fc359bd).

`unix.brel` is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its symbols, and
`unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this
build. Its sums were reproduced by `cut.sh` on the host with gcc-cross-amix `33ebadc`, and by `../build.sh` on the
host and in the build container (`amix-toolchain:dist`).
