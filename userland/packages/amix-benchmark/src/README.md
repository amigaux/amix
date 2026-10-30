# amix-benchmark/src — the amix-bench suite's sources

The benchmark sources of the amix-bench suite, which the `amix-benchmark` (period toolchain) and
`amix-benchmark-gcc14` packages are built from. They came into amix on 2026-10-30 from the
amix-kerntools repository, where the suite was developed: the benchmarks (`*.c`,
`bench-compat.h`, the two Dhrystone texts) as of kerntools commit c25e0e2, and the driver and its
README (`fieldkit/`) as of commit 8e17364 (kit 1.2). The files are byte-identical to those
commits:

```
843e8d68719b5292203ed3ded7b48be66852af6eedbfa617b7668900a752cd18  dhry.c
142fc3d464904aeaf9b82bb3ac79fea2ddfa9859719c168a162ae8ad33b7731b  iobench.c
f0b84cb24d069104204b026e0bbd867084c694cca80bcabc415b853bb078a6d3  fpbench.c
fc7f557bebf124b970ae7a0832af27ec0169f7c72d0ea02d442519b97accf349  membench.c
30c39aa1942d633b886c5905abd802530f0b4f67624d8e8d56ca010f82e7811f  vmbench.c
81d7d1db709cf9502737c38697f8eb3d2b22dcb6f6fc2e9ba7055d1bbfa9f78b  bench-compat.h
924eff3987a44277aba4f2d7e9ffb5dbe5ccd3a9da25d969d02462b451f87b1e  fieldkit/runbench.sh
960f3e9df95ea966fc6ebfda9e25f55e32e230a1ca4b154472643d0da289ddd3  fieldkit/README-FIELD.txt
```

| File | What |
|---|---|
| `dhry.c` | Dhrystone 2.1 (Reinhold P. Weicker / Rick Richardson, 1988, public domain); the netlib texts are `dhry-RATIONALE.txt` and `dhry-README_C.txt` |
| `fpbench.c` | an FP-only loop and an FP paranoia battery |
| `membench.c`, `vmbench.c`, `iobench.c` | memory bandwidth; fork, context switch and page fault; the disk speedtest |
| `bench-compat.h` | the whole OS-dependent surface of the binaries |
| `fieldkit/runbench.sh` | the driver: runs the matrix, prints the results (pre-POSIX Bourne shell) |
| `fieldkit/README-FIELD.txt` | the kit's README, shipped as the packages' `README.txt` |

Whetstone is not here: its binary would statically link the stock SVR4 `libm`, which is not ours to
ship, so both packages report the `fpu.whet` row as skipped.

Licence: our own files are MIT (the directory's `LICENSE`); `dhry.c` and its texts are public
domain.
