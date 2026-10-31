# kernel/k30/pkg: the 68030 kernel package

The recipe of the package built from kernel/k30's cut, moved in
from amix-packages' `recipes/` at 450ba6a:

| Recipe | Package | What |
|---|---|---|
| `kernel-k30-m/` | `kern30m` | the module kernel of the 68030 line: `/stand/k30/{unix,kabi,unix.sym}` and the cut's ufs and s5 modules under `/etc/conf/mod.d` (C2-3); rolled by `amix_kpkgroll` |

```sh
sh kernel/k30/pkg/build.sh [kernel-k30-m]
```

rolls it with the harness in `build/pkg` (`common.sh` sources it) into
`$AMIX_BUILD_ROOT/kspace/pkg/` (`out/pkg/kspace/pkg/` by default), logs in
`kspace/log/`, and prints `pkg <file> <sha256>` per datastream: the contract
of make dist's `kspace` step (docs/BUILDING.md). With no cut output it exits
3 and names the step that makes it (`[MISSING]`, make kernel-k30).

The kernel is not built here. The recipe packages the output of the cut
record `cuts/<build id>/cut.sh` (`K30M_SRC`; by default
`kernel/k30/build/cuts/<build id>/`, where make dist's `kernel-k30` step,
`kernel/k30/cuts/build.sh`, writes it) and checks every byte of it against
`pin.sh`:
the brel, its sidecar and `unix.sym`, the ET_REL elf2brel makes the brel
from, and the ufs and s5 modules, which it rebuilds from the cut's carve
sources with the kit of the pinned commit. `elf2brel.py` and the licences of
the code linked in come from amix at the cut's commit, the port's and
paula's licences from those forks at their pinned commits, fetched by hash
(`AMIX_PORT_REPO`/`AMIX_PORT_URL`, `AMIX_PAULA_REPO`/`AMIX_PAULA_URL`). Every
time stamp of the roll is `pin.sh`'s `SOURCE_EPOCH`.

**Versions up to k30.1.3.261031-63 were minted by amix-packages' older
roll.** Rolled here, that version has the same payload, pkginfo, copyright and
pkgmap payload rows, but not the same datastream: the deterministic roll
stamps the control files with the epoch where the older one left the build
time, so it is not shipped from here (one version, one set of bytes).
`kern30m` k30.1.3.261031-64 and later are this roll's own, minted at release
prep.
