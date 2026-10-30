# APKG 0.2.1 — the one-function hotfix, prepared and NOT published

> **Superseded 2026-09-26 — 0.2.1 was minted but NEVER PUBLISHED, and never will be.**
> Decision (2026-09-26): the next APKG release is **0.2.2**, minted from master (the canonical
> `pkg.amigaux.org` default from `dcece20`, this same `unblock_alarm()` fix, and the stub DNS
> resolver from `eed3210`). The 0.2.1 artefact below stays on disk as a record — md5
> `d69db8aaf22b3f4a4d4600f70f09e0f0`, never catalogued, never on the host — and the version
> number 0.2.1 is retired with it: it names *this* tree (`d73ecbc` + one function), so a master
> build must never carry it. Section 5's recipe is **not** to be run; the 0.2.2 publish sequence
> is in `NOTES.md` (2026-09-26, "APKG 0.2.2"). The rest of this document is kept as written,
> because its evidence — the double-stall regression test failing against the shipped 0.2 — is
> what 0.2.2 ships the fix for.

**Status: prepared only. Nothing has been published, no catalog line has moved, no card has been
rewritten, and `master` is untouched.** This branch (`apkg-0.2.1-hotfix`) exists so that *if* the
metal shows the shipped APKG 0.2 hanging on a second stalled fetch, the decision in front of the
maintainer before Saturday 2026-09-19 is a single yes/no over a **one-function** delta — not a release.

Everything below is the recipe for that yes. Read section 6 first if the answer is no.

## 1. What this fixes, and why it might matter on the day

A signal handler runs with its own signal blocked, and that block is lifted by **returning** from
the handler — which a `longjmp` never does. `http.c` has used `alarm()` + `longjmp` for its
inactivity timeout since it was written, and its **retry loop re-arms the same timer**. So with the
shipped default `retries=2`:

* the **first** stall times out correctly, and
* the **second** stall hangs the client with **no timeout at all** — forever.

It stayed invisible because the existing stall test runs at `retries=0` and therefore only ever
takes the first timeout. The failure presents as the healthy state.

That default `retries=2` is what is on the demo cards. A demo that fetches over a link which
stalls twice hangs with no way out but Ctrl-C.

The fix is `unblock_alarm()` (`sigprocmask(SIG_UNBLOCK)` on SIGALRM) in `src/apkg/util.c`, called
at the one `alarm(0)` in `http.c` that is reached by longjmp out of the handler. That is the entire
functional change.

## 2. The base tree is the published 0.2 — proven, not asserted

The branch point is **`d73ecbc`**, and the proof that it is the tree the published
`APKG-0.2.pkg` (md5 `8289178ca832f0ea67ecd7445f512978`) was built from is a rebuild:

```
git switch -c apkg-0.2.1-hotfix d73ecbc
cd src/apkg && rm -rf obj-amix apkg.amix
. <gcc-cross-amix>/build/env.sh && make amix
  -> md5 03cec0f2c7dcee7be57e3d101de93d55, 71229 bytes
```

and the `/usr/apkg/bin/apkg` inside the published package is **the same bytes**:

```
heirloom/build-host/bin/pkgtrans -o build/repo-staging-apkg02/base/APKG-0.2.pkg <dir> all
md5sum <dir>/APKG/root/usr/apkg/bin/apkg
  -> 03cec0f2c7dcee7be57e3d101de93d55, 71229 bytes
```

`d73ecbc` itself is docs-only over `3ec2c80` (the pkgmap-symlink commit), so the source tree is
identical either way. Note that the `.pkg` *datastream* is **not** byte-reproducible (the PSTAMP
and mint-time mtimes move), which is exactly why the package file is preserved rather than rebuilt
— see section 4.

## 3. What is on this branch, and what is deliberately NOT

**On it (commit `4c3bfc3`):**

| file | change |
|---|---|
| `src/apkg/util.c` | `unblock_alarm()`, plus `_POSIX_SOURCE` scoped to this file (Amix's `<sys/signal.h>` hides `sigset_t` behind it) |
| `src/apkg/apkg.h` | the `extern`; `APKG_VERSION` `0.2` → `0.2.1` |
| `src/apkg/http.c` | the one call site, in `http_get()`'s `setjmp` arm |
| `src/apkg/tests/run-tests.sh` | the double-stall regression test |

All ported **verbatim** from master's `eed3210`.

**Deliberately not ported, though they sit in the same master commit or beside it:** the stub DNS
resolver (`dns.c`, the `nameserver=`/`dns_timeout=`/`dns_retries=` config keys, the `apkg.conf`
template lines that document them), `descs.conf`, and every other change on master since the 0.2
mint. Master keeps all of it for the release after 2026-09-19.

`sigsetjmp`/`siglongjmp` was the other candidate fix and stays rejected on evidence: the Amix libc
exports `sigsetjmp` but **not** `siglongjmp`. `sigprocmask`, `sigemptyset` and `sigaddset` are all
real exported symbols, re-confirmed here — all three resolve out of `libc.so.1` in the cross link
(`readelf --dyn-syms`).

## 4. The mint, and the evidence behind it

```
build/repo-staging-apkg021/base/APKG-0.2.1.pkg
  md5  d69db8aaf22b3f4a4d4600f70f09e0f0
  size 133632 bytes
  (md5 sidecar: APKG-0.2.1.pkg.md5; the file is chmod 444 — do not re-mint it)
```

Minted with `bash tools/repo/build-packages.sh --apkg build/repo-staging-apkg021` from this branch.
`build/` is gitignored, so **this file is the artifact and it cannot be reproduced.** A re-mint
would move the md5 quoted here and everywhere downstream.

| check | result |
|---|---|
| `pkgmap-symlink-gate.py` | `link gate OK … (1 link entry checked)` — run by `build_one` at mint time and again standalone |
| shipped `/etc/apkg.conf` vs 0.2's | **byte-identical**, md5 `c80683eeb8665b7410b196716786e3f4`, 4262 B, `rcvbuf=0` at line 73 |
| `/var/apkg/admin` vs 0.2's | byte-identical |
| `contents-fsck`, `amix-sadm-migrate`, `apkg.1` | byte-identical to 0.2's |
| whole payload tree vs 0.2's | **exactly one file differs: `/usr/apkg/bin/apkg`** |
| new binary | md5 `b84b6be1b3531604f45d62fddc95cfde`, 71525 B (+296 over 0.2), `DT_NEEDED` = `libnsl.so` + `/usr/lib/libc.so.1` only |
| `pkginfo` | `VERSION=0.2.1`, everything else unchanged |
| `pkgmap` symlink entry | `s none /usr/bin/apkg=/usr/apkg/bin/apkg` — absolute, as 0.2's re-mint made it |
| host alt-root install (`pkgadd -R`, fakeroot, pre-made `/usr/bin`) | successful; 15 contents records; `/usr/bin/apkg -> /usr/apkg/bin/apkg`; installed binary byte-exact |

Tests on this tree: `src/apkg/tests/run-tests.sh` **172 passed, 0 failed** (0.2: 169 — the three new
ones are the regression test); `src/apkg/tests/nohttp-variant.sh` **17 passed, 0 failed**
(unchanged).

**The regression test earns its place by failing.** Run against the pristine 0.2 sources it reports
`FAIL: the second stall hung: 122s - SIGALRM stayed blocked` and `FAIL: only one attempt timed out`;
against this tree it passes in 4 s. That contrast is the whole test, and it is also independent
evidence that **the shipped 0.2 client really does carry this defect** — host-side, against the
exact tree the published binary came from.

## 5. If the decision is to publish — the exact steps

Nothing here has been run. Each step is one command; none of it is automated on this branch.

**5a. Stage from the LIVE HOST, never from a local tree.** `publish.sh` rsyncs
`--delete --delete-excluded`, so a stale staging root deletes packages off the server.

```
rsync -a <user>@<host>:<docroot>/ build/publish-<date>-apkg021/
cd build/publish-<date>-apkg021 && md5sum -c catalog.md5      # must say: catalog: OK
# and verify every package against its catalog md5+size before adding anything
```

**5b. Add the new package, and move the older `apkg` ones aside for the generate step.** Catalog v1
keys on `name`, so the staging root must hold exactly one package named `apkg` when the catalog is
generated. `APKG-0.1.pkg` and `APKG-0.2.pkg` must be **moved back before the publish**, or
`--delete-excluded` removes them from the server — a box already on 0.1 or 0.2 never re-fetches its
own version, but the URL must keep resolving for a manual recovery fetch.

```
cp build/repo-staging-apkg021/base/APKG-0.2.1.pkg build/publish-<date>-apkg021/base/
cp tools/repo/deps.conf build/publish-<date>-apkg021/          # cats.conf deliberately NOT staged:
                                                               # it would recategorise all 38 lines
mkdir -p /tmp/aside && mv build/publish-<date>-apkg021/base/APKG-0.{1,2}.pkg /tmp/aside/
python3 tools/repo/gen-catalog.py build/publish-<date>-apkg021
mv /tmp/aside/APKG-0.*.pkg build/publish-<date>-apkg021/base/
diff -u <live catalog> build/publish-<date>-apkg021/catalog       # must differ in EXACTLY one line
```

Expected new line:

```
apkg|0.2.1|APKG|base/APKG-0.2.1.pkg|d69db8aaf22b3f4a4d4600f70f09e0f0|133632|apkgeng|application|Remote package client: update/list/search/install over HTTP
```

Catalog entry count stays **38**.

**5c. Dry run, then publish.**

```
PUBLISH_DEST=<user>@<host>:<docroot> tools/repo/publish.sh --dry-run build/publish-<date>-apkg021
                                     # expect 3 files, NO "deleting" line
PUBLISH_DEST=<user>@<host>:<docroot> tools/repo/publish.sh           build/publish-<date>-apkg021
```

**5d. Verify from outside, the way the client fetches** — `curl -0` with an explicit
`Host: pkg.amigaux.org` (the vhost is name-based; a bare-IP `Host:` is a 404): `/catalog`,
`/catalog.md5`, `/pkgs/base/APKG-0.2.1.pkg` (must be 133632 B, md5 `d69db8aaf22b3f4a4d4600f70f09e0f0`),
and `/pkgs/base/APKG-0.2.pkg` + `APKG-0.1.pkg` must still serve 200.

**5e. The upgrade path from a box already on 0.2 is `apkg upgrade apkg`, and it is safe.** The
three-component version orders correctly under the client's own comparator — `apkg_vercmp` gives
`0.2.1 > 0.2 > 0.1` — so a 0.2 box sees the catalog entry as newer and `upgrade` engages rather than
reporting "already installed". It is safe because 0.2 is the version in which `upgrade` stopped
running `pkgrm` first and `conf_adminfile()` began
materialising the admin file. The 0.1 self-brick warning in NOTES applies to boxes still on **0.1**
and is unchanged by this release: those migrate with `apkg download apkg` then a stock
`pkgadd -d … APKG`, or a fresh install.

## 6. Re-carding the Saku demo medium — an installer task, not a step here

The 2026-09-19 demo install medium is built by **`amix-installng`** and carries the *current APKG
package bytes* (NOTES 2026-09-15). Publishing 0.2.1 does **not** change what is on a card already
written. If the cards are to carry the fix as well, that is separate work in
`amix-installng`: rebuild the medium against `APKG-0.2.1.pkg` (md5 `d69db8aaf22b3f4a4d4600f70f09e0f0`)
and rewrite the cards. This repo does not own that step and has not taken it.

**Judgement worth stating:** publishing alone reaches a demo box only if that box fetches the
catalog during the demo. A card that installs its bundled APKG and then does one fetch gets the old
client. If the hang is real and the demo does any fetching over a flaky link, re-carding — not
publishing — is what actually removes the failure mode.

## 7. If the answer is no

Nothing needs undoing. The branch stays where it is, `master` carries the same fix (plus the
resolver) for the release after 2026-09-19, and
`build/repo-staging-apkg021/base/APKG-0.2.1.pkg` is a gitignored local artifact that no one has to
touch. The one thing worth keeping either way is section 4's last paragraph: the shipped 0.2 client
carries the defect, and that is now proven host-side rather than suspected.
