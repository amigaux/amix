# CPython 3.11 AMIX application port

The adapters here are private to the cross-built Python executable. Do not
install their headers into the system include directory. GNU Pth remains the
threading implementation; these files address the older AMIX C interface.

The adapters are Ignacio Soriano's (isoriano1968, amix-userland), MIT:
[LICENSE](LICENSE), "Copyright (c) 2026 isoriano1968". `amix-math.c` derives
some fallbacks from CPython and is under the Python Software Foundation
licence in [LICENSE.PSF](LICENSE.PSF). Each file names its licence in an SPDX
line. The package ships both notices, as `doc/python3/LICENSE.adapters` and
`doc/python3/LICENSE.port`.
