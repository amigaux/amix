# payload/firstboot/ — first-boot identity payload

`src/installer/install.sh` copies this directory into the installed target at
`/var/adm/firstboot/` and drops a `PENDING` marker. On the target's first
multiuser boot, `firstboot.sh` runs once, bakes in the machine identity the
stock interactive first-boot dialog would ask for, then removes the marker.

| file | role |
|------|------|
| `firstboot.sh` | the once-only identity script (pre-POSIX SVR4 sh; runs on the target) |
| `root.shadow` | the root `/etc/shadow` line to install — the bench credential, for bench media only, not a secret |
| `S16firstboot` | the **reference** rc2 hook (the "template"). `install.sh` **writes** this byte-for-byte onto the target as `/etc/rc2.d/S16firstboot`; it is **not** copied from the CD and **not** a package member. `installer-selftest.py` audit J re-runs the driver's `emit_firstboot_hook()` and asserts it reproduces this file (drift-lock). |
| `netset.sh` | the **network installation's second stage** (pre-POSIX SVR4 sh; runs on the target). A netinstall of a set beyond minimal installs the minimal set, the base packages, the kernel set and the boot store, and records the rest of the chosen set as the repository catalog's rows in `/var/adm/firstboot/netset`; `install.sh` copies this script beside it and writes `/etc/rc2.d/S99znetset` (`emit_netset_hook`), which runs it at the end of run level 2 at every boot while the record is there. It installs each recorded package with apkg, one at a time, after checking every row against the repository's catalog; three tries per package, one run at a time (`netset.lock`), a package already installed is skipped; a failure leaves the system bootable and the stage armed; when the set is complete the record becomes `netset.done` and the hook is removed. Audits SN and NR run it and the stage-1 side. |
| `system.setup` | The three-line **entry-point stub** for the first-boot dialog, and the master the driver emits from. Like `S16firstboot` it is **not** copied from the CD: `install.sh` writes it (plain `echo` lines, `emit_system_setup`) into the stock `/usr/amiga/bin/system.setup` slot, `chmod 0755`, **only** when the profile says `FIRSTBOOT_DIALOG=y`. It execs `firstboot.sh --dialog`. Audit Z RUNS the emitter and drift-locks the two byte-for-byte. |

**The dialog itself is `firstboot.sh --dialog`** — the same file as the apply
half, two entry points, one set of `FB_*` variables. That is not tidiness, it is
the install floppy: **the 1991 SVR4 sh materializes every here-doc body into a
file under `/tmp` when it PARSES the script** (proven on the box — a here-doc in
a function that is never called still leaves `/tmp/sh<pid>` behind), and on the
miniroot that `/tmp` is the 880-block floppy with 46 free blocks. The dialog was
briefly a here-doc in the driver, and both the interactive and the unattended
matrix cells died with `Floppy fd0: no space` before the driver printed a line.
`firstboot.sh` is already staged on the medium and already copied to the target,
so carrying the dialog there costs no medium file and no here-doc at all.

## The two tiers

`FIRSTBOOT_DIALOG=n` (the default, and what every tracked profile says) is the
unattended tier: the stock sysinit dialog is disarmed with its own `chmod -x`, and
`firstboot.sh` bakes the profile's `FB_*` keys with nothing asked. `=y` — which
`setup.sh` writes for **every** interactive install — puts our dialog in that slot
instead. The dialog only ever **collects**: it writes its answers into
`firstboot.conf` and performs the live stock actions (`uname -S`, the stock `ksh`
TZ menu, `passwd`/`passwdall`, `amixmkuser`, the A2024 relink). `S16firstboot` →
`firstboot.sh` is the single application path in **both** tiers.

Two consequences worth knowing before editing anything here:

- **`chmod -x` fires only at the clean exit of the dialog's summary loop.** An
  interruption, a power cycle or an EOF leaves the dialog armed and re-runs the
  whole thing next boot; `firstboot.sh` keeps `PENDING` until `DIALOG-DONE`
  exists, so the mechanical steps are applied on every one of those boots and the
  box stays healthy in between.
- **Every temp file here must stay distinct from its target inside 14
  characters.** The target root is s5. `firstboot.conf` is exactly 14, so
  `firstboot.conf.new` *is* `firstboot.conf` — measured on the bench 2026-08-12,
  that cost the whole file (`sed … > tmp` truncated its own input, `mv` finished
  it off). The dialog's temp is `fbconf.new`; audit Z rejects any colliding pair.
- **No `\|` in any `sed` here.** SVR4 `sed` has no alternation and says nothing
  about it: both duplicate guards in `firstboot.sh` were written that way and had
  never once fired (measured, same session). Use two `-e` expressions.

Identity values (nodename, domain, timezone, IP, netmask, interface, …) are
**not** hardcoded here — `install.sh` writes them into
`/var/adm/firstboot/firstboot.conf` from the selected **profile** (`FB_*` keys),
so bench and metal differ by profile, not by editing this payload.

### `firstboot.conf` keys

`FB_NODENAME` · `FB_DOMAIN` · `FB_TZNUM` · **`FB_TZ`** · `FB_IP` · `FB_NETMASK` ·
`FB_ETHER_IF` · **`FB_GATEWAY`** · **`FB_DNS1`** · **`FB_DNS2`** · **`FB_KMAP`** ·
`FB_REPO_HOST` · `FB_REPO_IP` · `FB_ROOTDEV` · `FB_SCSI_ID` · `FB_ROOT_SLICE` ·
`FB_SWAP_SLICE` · **`FB_DIALOG`** · **`FB_ROOT_TELNET`** · **`FB_SYSLOG`** ·
**`FB_NET_CONFIGURED`** · **`FB_TZ_KEEP`** · **`FB_REPO_URL`** · `FB_ZEN_CARDS`. The dialog's additions
(the last six) each default to the behaviour this payload had before the dialog, so an
older `firstboot.conf` produces a byte-identical result:

- **`FB_DIALOG`** — `y` when the install armed the dialog. It is what makes
  `PENDING` conditional: with a dialog armed and no `DIALOG-DONE` marker,
  `firstboot.sh` applies the mechanical keys and **keeps** `PENDING`.
- **`FB_ROOT_TELNET`** (default `y`) — `y` comments `CONSOLE=` in
  `/etc/default/login` (root may telnet in, which is what the driver has always
  done); `n` uncomments it. `CONSOLE=` gates **root** only.
- **`FB_SYSLOG`** (default `y`) — `y` touches nothing (the laid-down unit is
  already enabled); `n` restores the vendor `exit` line **in place**, because
  `/etc/init.d/syslogd` is one inode with three names.
- **`FB_NET_CONFIGURED`** — set only by the dialog. It gates the network
  *extras* (the `rc.inet` default route, the `S99zen` re-point, DNS), so an
  unattended install never grows a step it did not have.
- **`FB_TZ_KEEP`** — set only by the dialog, whose stock zone menu has already
  written `/etc/TIMEZONE` (with the colon, and with the `TZ/localtime` alias).
  `firstboot.sh` then leaves the file alone — which is also what keeps the menu's
  "Other (nonstandard)" POSIX rule string from ever being re-emitted as `TZ=:…`.
- **`FB_ZEN_CARDS`** (2026-09-26) — the address-by-card table, quoted
  `MAC=ADDR=NAME` words plus `default=ADDR`. On a `zen0` flavor `firstboot.sh`
  (section 5d) renders it through `S99zen mkconf` into `/etc/inet/zen.conf` —
  once; an existing table is never overwritten — and S99zen picks zen0's
  address, nodename and hosts own row from it at every boot
  (`docs/address-by-card.md`). Empty = no table, byte-identical to before.
- **`FB_REPO_URL`** — the repository URL. `install.sh` writes `/etc/apkg.conf` on
  the miniroot; `firstboot.sh` re-points the `repo=` line **only** if the dialog
  named a different host, never creating the file.

The **bold** ones below came with the driver plumbing:

- **`FB_TZ`** — the timezone **zone name** (e.g. `US/Eastern`). At first
  `firstboot.sh` wrote the literal `TZ=:US/Eastern` regardless of the profile, so
  every unattended install silently diverged from its own spec. The value is the
  **bare** zone: `firstboot.sh` emits the leading colon itself
  (`echo "TZ=:$FB_TZ"`), because the colon is load-bearing (a colon-less
  `TZ` bus-errors every `ctime(3)` consumer at cold boot) and must never be
  reachable from data. `install.sh` strips a leading colon off the profile value
  for the same reason, and defaults the key to `US/Eastern`.
- **`FB_GATEWAY`** — LAN default route. Consumed by the driver-written
  `/etc/rc2.d/S99zen` laydown (zen0/metal flavors), where it was the hardcoded
  `192.0.2.1`. A `zen0` profile without one fails the install closed.
- **`FB_DNS1` / `FB_DNS2`** — resolver addresses. Recorded by the driver; **applied** by
  `firstboot.sh` as **all five parts or none** (`resolv.conf`, the
  `libsockdns` relink, `netconfig.DNS`, an empty `/etc/domain`, literal-IP boot
  ifconfigs) and only on a literal-IP (`zen0`) flavor. On `aen0` the fifth part
  would mean editing `/etc/inet/network-config` — never — so the dialog refuses
  DNS there out loud rather than half-serving it.
- **`FB_KMAP`** — the keyboard map baked onto the target by `install.sh` (not by
  this payload); recorded here so the installed box can report what it chose.

## What it bakes (and the two hard rules)

nodename · timezone **`FB_TZ`** (index breadcrumb `FB_TZNUM`; `US/Eastern` = 47) ·
root password + `#CONSOLE=` (root telnet) · `/etc/vfstab` for the real
controller/slice · `/dev` regeneration via `/usr/amiga/lib/atdevs`.

- **NEVER touch `/etc/inet/network-config`.** The shipped file plumbs `aen0`
  via `ifconfig aen0 \`uname -n\`` resolving through `/etc/inet/hosts`; editing
  it broke networking on the 2026-07-13 base (hdf/README). We bake ONLY the
  `/etc/inet/hosts` entry (+ pw + CONSOLE).
- **NEVER set the clock forward** — the RTC/`lastchg` aging trap poisons account
  aging with a future date. `firstboot.sh` never sets the clock.

## How it is wired into the target init

`firstboot.sh` is inert unless something invokes it, and the **stock** Amix init
does not: on cold boot #1 the stock sysinit dialog runs instead. `install.sh`'s
arm step closes that gap with two evidence-based moves (both confirmed against an
s5 read of the installed target's `/etc/inittab` + `/etc/sysinit`):

1. **Disarm the stock dialog.** `/etc/sysinit` (a `core` member, run from the
   `S2::sysinit` inittab line at boot, *before* run level 2) runs
   `/usr/amiga/bin/system.setup` **iff it is `-x`** — the interactive first-boot
   dialog (nodename via `/usr/amiga/lib/amixnode`, hosts, passwords, monitor…).
   `system.setup` itself ends with `chmod -x /usr/amiga/bin/system.setup` — its
   own once-only disarm. `install.sh` applies exactly that `chmod -x`
   non-interactively (mode-only; content/cksum untouched), so the dialog never
   appears. This is the single package-file touch of the whole install, it is the
   intended end-state of any configured Amix box, and `altroot-attest` (a pure
   function of the `pkgadd` contents DB) is unaffected by it.
2. **Add the rc2 hook.** `install.sh` writes `S16firstboot` (this dir's template)
   to `/etc/rc2.d/S16firstboot`. `/sbin/rc2` runs each `rc2.d/S*` via
   `/sbin/sh S* start`, and `/etc/inittab` runs `s2:23:wait:/etc/rc2` to
   **completion** before it spawns the `con` console getty — so the hook runs
   `firstboot.sh` (iff `PENDING` exists), which bakes identity and removes
   `PENDING`, all **before** the login prompt. On cold boot #2 `PENDING` is gone,
   so the hook is a no-op and the identity is read from `/etc/nodename` at sysinit.

The SVR4-conventional target locations `firstboot.sh` writes are confirmed on the
box: the nodename store (`/etc/nodename` + `uname -S`), the timezone store
and the numeric index-47 mapping (`/etc/TIMEZONE` + `/etc/tz.index`), `/etc/vfstab`,
the `/etc/inet/hosts` entry, and `/dev` regeneration via `/usr/amiga/lib/atdevs`.

An old `firstboot.conf` (one written before these keys) stays valid: `firstboot.sh`
defaults `FB_TZ` to `US/Eastern`, which is exactly the literal it used to write.
