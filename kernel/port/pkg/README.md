# kernel/port/pkg: the 68040/68060 kernel package

The recipe of the package built from the 040/060 port's cut (P-38 S3.3),
moved in from amix-packages' `recipes/` at 450ba6a, beside its twin in
`kernel/k30/pkg`:

| Recipe | Package | What |
|---|---|---|
| `kernel-k46-m/` | `kern46m` | the module kernel of the 68040/68060 line: `/stand/k46/{unix,kabi}` and the cut's ufs module under `/etc/conf/mod.d` (C2-3); rolled by `amix_kpkgroll` |

```sh
K46M_SRC=<the cut's output> sh kernel/port/pkg/build.sh [kernel-k46-m]
```

rolls it with the harness in `build/pkg` (`common.sh` sources it) into
`$AMIX_BUILD_ROOT/kspace/pkg/` (`out/pkg/kspace/pkg/` by default), logs in
`kspace/log/`, and prints `pkg <file> <sha256>` per datastream: the contract
of make dist's `kspace` step (docs/BUILDING.md).

The kernel is not built here. The recipe packages the output of the port's
cut record `cuts/<build id>/cut.sh` (amix-040-060-port at the commit
`kernel/port/port.pin` names or later), which `K46M_SRC` names: the cut has
no home in amix until make dist's `kernel-k46` step (P-38 S2.3) makes it.
Every byte is checked against `pin.sh`: the ET_REL and its sidecar, the
image's build id against the sidecar's and the module's, and the ufs module,
rebuilt from the cut's carve sources with the kit of the pinned commit. The
port's notices come from the cut's copy of the port tree, the other licences
from amix at a commit and from amix-paula by hash (`AMIX_PAULA_REPO`/
`AMIX_PAULA_URL`); the kit's port headers are fetched by hash too
(`AMIX_PORT_REPO`/`AMIX_PORT_URL`). Every time stamp of the roll is
`pin.sh`'s `SOURCE_EPOCH` (P-38 D-b).

**The version here was minted by amix-packages' older roll.** Rolled here,
`kern46m` k46.1.3.261031-52 has the same payload, pkginfo, copyright and
pkgmap payload rows, but not the same datastream: the deterministic roll
stamps the control files with the epoch where the older one left the build
time. So this datastream is not shipped under this version (one version, one
set of bytes); the 1.1 kernel is minted by this roll at a new revision at
release prep (P-38 D-g), when the pins move.
