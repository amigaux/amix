# kernel/conf: the kernel-space catalog's conf

The configuration make dist's `catalogs` step gives `gen-catalog.py`
(userland/pkgtools/tools/repo) for the kernel-space catalog.

| File | What |
|---|---|
| `names.conf` | the catalog name of each kernel-space package whose name is not its pkginst lowercased (`a409130: a4091-k30`): the kernel, loader and module packages, whose pkginst fits the 9 characters stock `pkgadd` keeps |
| `kbootset.conf` | the lowest kbootset version of a published kernel-space package that does not carry it itself: a kernel whose sidecar predates `kbootset-min=` (`kernel-k30-m k30.1.4.261101-68: 1.1.0.261102-35`), a module package whose pkginfo predates `APKG_KBOOTSET` (`xsurf-k30 1.0.0-3: 1.1.0.261114-45`); gen-catalog writes it on the package's row as `kbootset=` (C2-2 v6 §1.2, v7). A package cut since carries its floor and needs no line |

The format is gen-catalog's: `<PKGINST>: <catalog-name>`, one per line,
`#` comments. A package not listed keeps its pkginst lowercased as its
catalog name (`kbootset`, `modtools`, `dlmkit30`).

**No overlap with userland/pkgtools/tools/repo/names.conf.** gen-catalog
reads both layers and neither outranks the other: where both name one
pkginst and the names differ, it writes no catalog (exit status 4, every
conflicting package named). Keep each pkginst in one file only: kernel
space here, the stock and userland packages there.

A new module package adds its two lines (`<x>30: <x>-k30`, `<x>46:
<x>-k46`) here when it is minted. The list was amix-packages'
(`tools/kspace-roundtrip.sh`, which wrote it into its staging roots) until
it moved here.
