# amix-benchmark — the amix-bench suite

[`src/`](src/) holds the sources of the amix-bench benchmark suite: Dhrystone 2.1, an FP-only loop
and an FP paranoia battery, memory bandwidth, three VM rows and the disk speedtest, with the
`runbench.sh` driver. [`src/README.md`](src/README.md) gives their provenance and licences.

[`amix-benchmark-gcc14`](../amix-benchmark-gcc14/) builds its package from them (`SRCPKG`).

**The period package is not built here.** `amix-benchmark` 1.3 (PKG `amixbench`), built with
gcc 2.7.2.3 and published on pkg.amigaux.org, is built and kept outside amix. The pinned toolchain
reproduces its five benchmark binaries from these sources byte for byte, but the package's payload
also carries details of the machine it was built on, and its binaries ship unstripped, so it cannot
be rebuilt from this directory without changing its bytes. A version's bytes never change, so it
stays as published. The recipe as it stood is in this directory's history (README at 20c8a84).
