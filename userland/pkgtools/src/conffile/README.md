# conffile: config files that keep the administrator's edits

`i.conffile` and `r.conffile` are the class action scripts of class `conffile`, the one shared
pair every Amix package with an edit-in-place config file carries (P-36 §1.2, decisions D-N1 to
D-N6). The administrator's view is [`conffile.5`](conffile.5); this file is the contract for
packagers and for `build/pkg`.

## Using them in a package

- Each conffile is `e conffile <abs path> <mode> <owner> <group>` in the prototype, with an
  absolute path under `/etc` or `/var`. A relocatable (BASEDIR-relative) path is not supported.
- The prototype carries `i i.conffile=<this dir>/i.conffile` and `i r.conffile=<this dir>/r.conffile`,
  and pkginfo says `CLASSES=none conffile`.
- One conffile has one owning package: no other package may ship the same path.
- Nothing else: the scripts take `$PKGINST` and `$PKG_INSTALL_ROOT` from the engine.

`build/pkg`'s pkgroll does this from `CONFFILES=` in `package.sh`; APKG (`tools/repo/build-packages.sh`)
does it by hand for `/etc/apkg.conf` and `/var/apkg/admin`. The paths
`userland/pkgtools/src/conffile/{i,r}.conffile` are a stable public surface.

## What they do

`i.conffile`, per `src dst` pair, with the baseline (the default last shipped) at
`$PKG_INSTALL_ROOT/var/sadm/conffiles/$PKGINST/<path>`:

| On disk | Action | Message |
|---|---|---|
| no file, no baseline (first install) | install the default | none |
| equal to the new default | (nothing to copy) | none |
| equal to the baseline (unedited) | install the new default | none |
| differs from both (edited, or written by someone else) | keep it; new default to `<path>.new`; add `<pkginst> <path>` to `/var/sadm/conffiles/PENDING` | `<path>: kept your version; the new default is <path>.new` |
| gone, baseline present (user removed it) | install the new default | `<path>: you had removed it; the package's default is back` |

In every case the new default becomes the baseline, and a file that is no longer pending loses its
stale `.new` and its `PENDING` line.

`r.conffile`, per path: an unedited file is removed with its baseline; an edited one is kept with
its baseline (the config-files state) and pkgrm says so; `.new` and the `PENDING` line go either way;
empty baseline directories are pruned.

Departures from P-36's table, and why:

- **No migration row** (owner D-N13: 1.1 is clean installs only). A file present without a baseline
  is treated as edited, the conservative outcome; on a clean install that is a file the installer
  wrote before the package (D-N24's `removef core` transfer, for instance).
- **No s5 `new/` directory** (D-N3 as amended by D-N13): clean 1.1 installs are UFS.
- **A removed file comes back.** After the class action script the engine verifies every object of
  the class and fails the install, "partially failed", on one that does not exist (heirloom
  `instvol.c`, cverify after the script; the stock pkginstall shares the code). So "do not recreate
  it" cannot be honoured by any script; the default comes back and the message says so. The tests
  show the engine's refusal with a class script that writes nothing.

## Engine facts the scripts rely on (heirloom, read and tested on the host)

- pkgadd passes the pairs on stdin; on the last volume the same call has `$1 = ENDOFCLASS`. `dst`
  carries the install root under `-R`, and `PKG_INSTALL_ROOT` and `PKGINST` are in the environment.
- With `r.conffile` present, pkgrm hands it the class's paths (root-prefixed) and removes none of them
  itself.
- For an `e` object a class action script installed, the contents database records the file on disk
  (APKGENG 1.12.3), so plain `pkgchk` is clean after a keep.
- A directory a kept file leaves non-empty is "not empty", not a failure: heirloom pkgrm now takes
  Linux's `ENOTEMPTY` like SVR4's `EEXIST` (AMIX PORT, 2026-10-30).
- `installf -c conffile <pkginst> <path> e` then `installf -f <pkginst>` re-reads size and checksum
  of a replaced file. Without `-c`, the entry falls back to class `none`. This settles P-36's
  UNVERIFIED item for apkg's `--conf-new`.

**UNVERIFIED on a box:** the stock pkginstall running the scripts, and the stock `/bin/sh`, `mkdir -p`,
`expr` and `test -o` they use (SVR4.0 features; installng's first 1.1-media install is the proof).

## Tests

    bash src/conffile/tests/run-tests.sh

builds toy packages with the host engine and runs the whole table under heirloom `pkgadd -R` and
`pkgrm -R` (fakeroot), plus the `installf -f` re-register. It needs `heirloom/build-host.sh` first;
exit 77 means skipped. The APKG package's own files are covered by T23 in
`tools/repo/tests/run-tests.sh`.
