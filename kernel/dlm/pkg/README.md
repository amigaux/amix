# kernel/dlm/pkg: dlm's kernel-space packages

The recipes of the packages built from kernel/dlm (P-38 S3.3), moved in from
amix-packages' `recipes/` at bea8828:

| Recipe | Packages | What |
|---|---|---|
| `loader-amix/` | `ldramix` | boot1 and boot2 under `/stand/loader` (C2-3 §3); rolled by `amix_kpkgroll` |
| `kbootset/` | `kbootset` | `/sbin/kbootset`, its page and its two boot scripts (C2-3 §4, C2-4 §16) |
| `modtools/` | `modtools` | `/sbin/modadmin` (S3-11) |
| `dlmkit/` | `dlmkit30`, `dlmkit46` | the ABI kit of each line under `/usr/dlm/kit/<line>` (S3-22) |

```sh
sh kernel/dlm/pkg/build.sh [loader-amix|kbootset|modtools|dlmkit]...
```

rolls them with the harness in `build/pkg` (`common.sh` sources it) into
`$AMIX_BUILD_ROOT/kspace/pkg/` (`out/pkg/kspace/pkg/` by default), logs in
`kspace/log/`, and prints `pkg <file> <sha256>` per datastream: the contract
of make dist's `kspace` step.

Each recipe's `pin.sh` names the amix commit it builds from (a `git archive`
of that commit, `build/pkg/common/dlm-src.sh`), the sha256 of every built
file it ships, its version and its `SOURCE_EPOCH`, every time stamp of the
roll (P-38 D-b). A build whose bytes are not the pinned ones fails.

**The versions here were minted by amix-packages' older roll.** Rolled here,
each has the same payload, pkginfo, copyright and pkgmap payload rows, but
not the same datastream: the deterministic roll stamps the control files
with the epoch where the older one left the build time. So these
datastreams are not shipped under these versions (one version, one set of
bytes); the 1.1 set is minted by this roll at new revisions at release prep
(P-38 D-g), when the pins move.
