# kernel/k30/pkg: the 68030 kernel package

The recipe of the package built from kernel/k30's cut (P-38 S3.3), moved in
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
3 and names the step that makes it (`[MISSING]`, P-38 S2.2).

The kernel is not built here. The recipe packages the output of the cut
record `cuts/<build id>/cut.sh` (`K30M_SRC`; by default the station's copy in
`kernel/k30/build/cuts/`) and checks every byte of it against `pin.sh`:
the brel, its sidecar and `unix.sym`, the ET_REL elf2brel makes the brel
from, and the ufs and s5 modules, which it rebuilds from the cut's carve
sources with the kit of the pinned commit. `elf2brel.py` and the licences of
the code linked in come from amix at the cut's commit, the port's and
paula's licences from those forks at their pinned commits, fetched by hash
(`AMIX_PORT_REPO`/`AMIX_PORT_URL`, `AMIX_PAULA_REPO`/`AMIX_PAULA_URL`). Every
time stamp of the roll is `pin.sh`'s `SOURCE_EPOCH` (P-38 D-b).

**The version here was minted by amix-packages' older roll.** Rolled here,
`kern30m` k30.1.3.261031-63 has the same payload, pkginfo, copyright and
pkgmap payload rows, but not the same datastream: the deterministic roll
stamps the control files with the epoch where the older one left the build
time. So this datastream is not shipped under this version (one version, one
set of bytes); the 1.1 kernel is minted by this roll at a new revision at
release prep (P-38 D-g), when the pins move.
