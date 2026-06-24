# system-fixes

Optional fixes to apply to your own Amix install, shipped as patches against the stock files
(this repo ships no Amix source).

## `bcheckrc.patch` — DNS fast-boot fix

Stock Amix's boot `bcheckrc` can hang for ~180 s when the boot-time `ifconfig` resolves the host's
own name (`uname -n`) before the network route exists. This patch brings the interface up with a
**literal IP** instead, so the boot does not block on name resolution.

Apply it to your own `/etc/bcheckrc` (paths in the diff are relative to `/etc`):

```sh
cd /etc
patch -p0 < /path/to/bcheckrc.patch      # edits /etc/bcheckrc, keeps /etc/bcheckrc.orig
```

Edit the patched-in `ifconfig` line to your box's address. Re-runnable: `patch -N` skips an
already-applied patch.
