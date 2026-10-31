# kernel/conf: the kernel-space catalog's conf

The configuration make dist's `catalogs` step gives `gen-catalog.py`
(userland/pkgtools/tools/repo) for the kernel-space catalog (P-38 S3.3,
S5.1).

| File | What |
|---|---|
| `names.conf` | the catalog name of each kernel-space package whose name is not its pkginst lowercased (`a409130: a4091-k30`): the kernel, loader and module packages, whose pkginst fits the 9 characters stock `pkgadd` keeps |

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
