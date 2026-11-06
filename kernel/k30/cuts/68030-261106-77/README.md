# Cut 68030-261106-77

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `d9db6ac`: -75's recipe with three stock defects
of /dev/audio fixed. -76, which was not released, also carried a TCP close linger; it was reverted at `d9db6ac` (see
KNOWN-ISSUES: the defect it aimed at stays open), and its audio patcher is replaced here by a second version.

- **/dev/audio answers each request once, refuses one with no data, and plays a long write once.**
  `tools/patch_audio_replies.py`, run after amix-paula's three patchers, changes eight places of audio.c (five
  fingerprints, three of them found twice):
  - in audioioctl, the AUDIO_VOLUME and AUDIO_PERIOD cases sent their reply and then fell through to the common tail,
    which sent the same message again as M_IOCACK with error 0, so a refused request (the wrong length) reported
    success: the four breaks become returns, and the two acks set ioc_rval and ioc_error to 0 themselves, as only the
    tail did;
  - an I_STR with ic_len 0 reaches the driver with no data block, and the driver called pullupmsg on it before testing
    for one, which panicked the kernel: pullupmsg is now called only when there is a block, and the existing test
    refuses the request with EINVAL;
  - audiointr refilled a channel buffer from a message too long for it without moving past what it copied, so the
    same bytes were copied again at every refill: both refill places advance b_rptr, as postaudio does.
  It takes only the audio.c those three make (1f43c5ff) and must give 3f434f35; its selftest shows each pin and each
  place refusing on its own. The 040/060 line will run the same file byte for byte (its next cut pins it). On by default, `--no-audio-replies`
  without.

Evidence, in emulation (A3000, 68030, 64 MiB, Paula's interrupts emulated), by the build each row ran on.
"The trial" is 68030-261106-98, built from the tree that became `28107ac` (the audio of this cut; the TCP linger was
still in its tree): its audio.c is this cut's, 3f434f35.

- This cut: AUDIO_VOLUME and AUDIO_PERIOD 50 rounds each in four forms, every call under a 10 s alarm: the right
  length 100 of 100 returned 0, the transparent form 100 of 100 0, the wrong length 100 of 100 EINVAL, no data
  (ic_len 0) 100 of 100 EINVAL, and the box went on. A 32 KiB write at period 200 filled the channel's buffers from
  8, 16 and 24 KiB of the write once each (a ramp whose value names the part of the write a buffer holds) and drained
  after 1.4 s, its last buffer queued; 4 and 12 KiB drained after 133 and 533 ms. These single writes go through the
  refill from the message the driver keeps; the other refill place (a queued message that does not fit) is untested:
  32 KiB streamed in 3000- and 5000-byte writes drained with no part loaded twice here and on -75 alike, so that
  test does not show the stock defect.
- -75, the same tests: the wrong length 100 of 100 returned 0 (in two runs); no data panicked the kernel at the first
  request (`PANIC: KERNEL FAULT ... (Bus Error)`, pc in xmsgsize, called from pullupmsg); the 32 KiB write was still
  refilling after 30 s, buffer after buffer filled from the write's second 8 KiB (86 times).
- The trial: the same as this cut (EINVAL 100 of 100 for both refusals; the 32 KiB write from 8, 16 and 24 KiB once
  each, drained after 1.4 s).
- This cut, /dev/audio as amix-base ships it (c 46 0, 0660 root audio) with the paula30 module package installed:
  open, write 4 KiB, close, three times, and 12 KiB; paulatest played 200 ticks at 50 a second and found /dev/audio
  refused (EBUSY) while /dev/paula was open, and /dev/paula was refused (EBUSY) while /dev/audio was; a writer killed
  mid-play was gone at once, and /dev/audio and /dev/paula then opened again.
- This cut, -75's rows: `tests/sparsehole` at 16 MiB 0 pages wrong in all four modes; rnd no bad block in 200000
  operations, twice; `tests/wcost`'s 20000 random rewrites 20 and 21 s, 64 MB copied by 8 KiB 42 and 42 s (-75: 24
  and 25, 47 and 46; the host was less loaded during this cut's run than during -75's). In the first rnd row the guest's shutdown stopped
  after its broadcast, with no `INIT: New run level: 0` in the 3 minutes the rig waited (FAIL halt-banner); the
  rerun halted. The same stall was seen once on cut -73 that day and on rows of -71's builds (KNOWN-ISSUES, "Not
  explained"); no other row of -75, -76 or this cut showed it.
- This cut, three 8 MiB ftp puts and gets over the A2065: 21.0, 20.2 and 21.1 s, and 7.4 s each, the copies equal,
  no frame missed or dropped (-75: 21.3, 20.0 and 22.3 s, and 7.3 to 7.6 s).
- This cut with Paula's interrupts not emulated (`sound_output=none`): opening /dev/audio for writing failed at once
  with EIO, twice (sh: "cannot create"). That is amix-paula's bounded wait for Paula's first interrupt, there since
  kabi 1.3: a Paula that never interrupts fails the open instead of hanging the box.

Against -75 the shipped files differ in `unix` (audio.o and the build id) and so `unix.brel` (1543136 bytes),
`unix.sym` and `kabi`; `mod.d/ufs` and `mod.d/s5` differ only in the build id they carry.

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-77` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `d9db6ac`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `d9db6ac`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: its three patchers make audio.c 1f43c5ff, which
  `tools/patch_audio_replies.py` makes 3f434f35).

`unix.brel` is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its symbols, and
`unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this
build. Its sums were reproduced by `cut.sh` on the host with gcc-cross-amix `33ebadc`, and by `../build.sh` on the
host and in the build container (`amix-toolchain:dist`).
