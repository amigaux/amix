# userland/base: the packages

Two packages come out of this directory: the **base** package (boot helpers,
the network set-up, the base config files) and **`dhcp-client`**. This page
says what goes in which, why the line is drawn there, and the contract between
them. Names and decisions are those of P-36 (decided 2026-10-30); where this
page proposes something P-36 left open, it says so.

## The two packages

| | base | dhcp-client |
|---|---|---|
| Catalog name | `amix-base` (owner, 2026-10-30; P-36 §2.2's working name was `amix-rc`, before D-N24 added the config files) | `dhcp-client` (D-N18) |
| pkginst (≤ 9 characters) | `amxbase` | `dhcpc` (D-N18) |
| Licence | MIT | MIT |
| Toolchain | period (gcc-cross-amix) for `dlpi-mac`; the rest is Bourne sh | period, for `dhcpc` |
| Depends on | nothing but the stock system | `amix-base` (it calls the base package's hook) |
| Installed by | every install | every install; a static-only machine may remove it |

### What `amix-base` holds

- **Code, replaced freely on update** (`f` objects): `/usr/lib/amix/rc.subr`;
  the network start script, one file under four names, recorded as stock
  `core` records it: the `f` object is `/etc/rc2.d/S69inet`, and
  `/etc/init.d/inetinit` and the two `K69inet` are `l` objects linked to it
  (any other shape is an "object type change" that stock `pkgadd` ignores,
  keeping the old script); `/usr/sbin/ifup`, `ifdown`,
  `dlpi-mac`; `/usr/lib/inet/ifup.subr` and `dhcpc-hook`; the swap step; the `man` front-end
  `/usr/amix/bin/man` (`man.md`); the pages `man(1)`, `rc.subr(1M)`,
  `dlpi-mac(1M)`, `rc.conf(4)` and `interfaces(4)` under `/opt/amix/man`, with
  their index fragment `/opt/amix/man/whatis.d/amxbase`; the shared `/opt/amix/man`
  directories and the cache directories `/var/opt/amix/catman/<sect>` (`d`).
- **Vendor data** (`f`): `/etc/inet/link.d/aen`, the stock A2065's entry.
  Every other network driver ships its own `link.d` entry in its own package.
- **Conffiles** (`e`, the shared keep-your-edits scripts): the two legacy
  hooks `/etc/inet/network-config` and `/etc/inet/rc.inet`, and the base config
  files that move here from `core` (D-N24; the list is in `plan.md`).
- **Not in any package**, written by the installer and edited by the
  administrator: `/etc/rc.conf`, `/etc/inet/interfaces`. Generated at run time:
  `/etc/resolv.conf`.

### What `dhcp-client` holds

- `/usr/sbin/dhcpc` (`f`), and the directory `/var/inet/dhcpc` (`d`).
- No config file. Everything it needs comes from `/etc/inet/interfaces`
  through `ifup` and from its own command line.

## Why the line is drawn here

- **The hook belongs to the base package.** A DHCP lease and a static line
  must be applied by the same lines of code (P-36 §4.4 rule 9), and that code
  is `ifup`'s. So `dhcpc` only talks DHCP and calls the hook; it never edits a
  system file. Putting the hook in `dhcp-client` would give the two paths two
  copies of the apply logic.
- **The dependency runs one way.** `dhcp-client` needs `amix-base`;
  `amix-base` does not need `dhcp-client`. When a line says `dhcp` and
  `/usr/sbin/dhcpc` is missing, `ifup` logs it and treats the line as if no
  server answered: the line's static address if it has one, else the
  interface stays down (D-N16).
- **Different change rates.** The client is the one piece with a protocol
  state machine and a daemon; it will be revised on its own schedule (S1, then
  S3's RELEASE and ARP check) without re-rolling the package that owns
  `/etc/inittab`.
- **D-N18 already fixed the client's names and its place in `/usr/sbin`.**

## The contract between them (frozen in T-55, 2026-10-30)

### `dhcpc` command line

    dhcpc [-b secs] <if>     get a lease, apply it through the hook, keep it
    dhcpc -x <if>            send RELEASE, apply "RELEASE", end the daemon
    dhcpc -q <if>            print the lease; exit 0 when bound

- With `-b`, the first lease is waited for in the foreground for at most
  `secs` seconds. Exit 0: bound and applied, the daemon now holds the lease.
  Exit 2: no lease yet; the daemon keeps trying in the background, and `ifup`
  applies the line's static fallback. Exit 1: cannot run (the node does not
  answer DLPI, or a daemon already holds the interface).
- The node is found the way `ifup` finds it (`link.d`); `dhcpc` takes the
  interface name only.
- One daemon per interface. Files: `/var/inet/dhcpc/<if>.lease` (one
  `key=value` per line, the same keys as the hook's environment),
  `/var/inet/dhcpc/<if>.pid`. Log: `/var/adm/dhcpc.log`.

### The hook

    /usr/lib/inet/dhcpc-hook <if> <reason>

| Reason | When | What the hook does |
|---|---|---|
| `BOUND` | a new lease (INIT, or INIT-REBOOT with the last address) | apply address, mask, route, hosts line, DNS; replaces a static fallback if one is up |
| `RENEW`, `REBIND` | the lease was extended | apply again only what changed (DNS servers, router) |
| `EXPIRE` | the lease ended without renewal, or a NAK | take the address and route off; re-apply the line's static fallback if it has one |
| `RELEASE` | `dhcpc -x` (from `ifdown`) | take the address and route off |

Environment: `DHCP_IF`, `DHCP_ADDR`, `DHCP_MASK`, `DHCP_ROUTER` (the first
router), `DHCP_DNS` (space-separated), `DHCP_HOSTNAME` (option 12; applied only
under `hostname dhcp`, D-N11), `DHCP_SERVER`, `DHCP_LEASE`, `DHCP_T1`,
`DHCP_T2`, `DHCP_OLD_ADDR` (the address before this event, when it changed).
`resolv.conf` gets nameservers only, merged with the static `dns` line unless
it says `dns static` (D-N12).

### What the probe added to the contract

From the S0 measurements (`dhcp-probe.md`):

- INIT, SELECTING and REQUESTING go over DLPI; RENEW and REBIND over a UDP
  socket bound to port 68, as planned. Both worked on the A2065.
- REBIND's broadcast leaves the socket as the subnet's directed broadcast
  (`x.y.z.255`), not `255.255.255.255`: the 1991 IP rewrites it. Servers on the
  same segment receive it; a relay agent is not reached. Acceptable for 1.0.
- The client sends **no client identifier (option 61)** in 1.0, and keys
  itself by `chaddr` only. The emulator translates `chaddr` between the
  guest-side and the host-side MAC but not option 61, and the guest-side MAC
  is probably the same on every emulated A2065, so a client identifier could
  make every emulated machine one client to a server. (Open for S1 if a real
  network needs it.)

## What the base package asks of the other work items

- **Packaging harness (W3).** A package whose files are under `/etc`, `/usr`
  and `/var` with no `/opt/amix` prefix; `TOOLCHAIN=period`; the `CONFFILES`
  gate's "not under `PREFIX`" rule restated as "under `/etc` or `/var`". The
  set: P-36 says set `base`, but the harness knows `minimal`, `standard`,
  `full`, `developer`, `x11` and `extra`; both packages belong in every
  install, so `minimal` unless a `base` set is added.
- **The shared conffile script (W1).** `/etc/nodename`, `/etc/inet/hosts` and
  `/etc/TIMEZONE` differ from the shipped default on every installed system.
  The §1.2 table writes `<file>.new` and a PENDING line whenever the file
  differs from both the baseline and the new default, so every update of the
  base package would flag them even when the default did not change. dpkg
  keeps the file silently in that case. The table needs that row: *file
  edited, new default identical to the baseline → keep the file, refresh
  nothing, say nothing*.
- **Removal (W2).** Removing the base package runs `r.conffile`, which
  deletes every conffile still equal to its baseline: an unedited
  `/etc/inittab` or `/etc/default/login` would go, and the machine would not
  boot. `apkg` should refuse to remove or purge it (an "essential" mark), and
  the installer never offers it.
- **The stock defaults' bytes.** The D-N24 files are Commodore's. They are not
  in `amigaux/amix-system`, which holds `usr/`, the kernels and the floppies
  but no `etc/`; today they come only from the installer's extract of the
  stock `core` package. The package build needs them from a public, pinned
  source (amix-system gaining `etc/`, or the build reading them from the
  pinned stock media).
- **Installer (W7).** Lays both packages down, writes `/etc/rc.conf` and
  `/etc/inet/interfaces`, and transfers ownership from `core` with `removef`;
  the steps are in the next section.

## What the installer (W7) needs from this directory

Measured on the emulator with stock `pkgadd` (S2, 2026-10-31). The steps, in
order, on the target root:

1. **Install `core` first**, as today: amix-base takes files over from it.
2. **Seed the conffile baselines.** For each of amix-base's `CONFFILES`
   (`package.sh`) whose size and `sum` still match its `f` record in
   `/var/sadm/install/contents`, copy the file to
   `/var/sadm/conffiles/amxbase<path>` (make the directory only when it is
   missing: the 4.0 `mkdir -p` fails on one that exists). The class then
   takes the new default silently; a file that does not match is kept, with
   `<path>.new` and a line in `/var/sadm/conffiles/PENDING`. Without this
   step every stock file counts as edited, and the stock
   `/etc/inet/network-config`, which brings `aen0` up by itself, stays and
   fights `ifup` at every boot.
3. **`pkgadd` amxbase, then dhcpc** (`dhcp-client` carries no `depend` file;
   the order is the installer's). Stock 2.1c `pkgadd` asks two questions for
   amxbase whatever the admin file says: whether to install files another
   package owns, and whether to run scripts as root. Under `-n` it stops
   there (exit 5, nothing installed), so the installer answers `y` to both on
   standard input, or uses the engine's `pkgadd`. dhcpc asks nothing.
4. **Write `/etc/inet/interfaces`** (`interfaces(4)`). The public default is
   one line, `* dhcp`: every interface a driver finds asks a DHCP server.
   A machine name given at install goes on that line (`* dhcp name <host>`);
   with none, add the global line `hostname dhcp` to take the server's.
   A static choice is `* static <addr>/<bits> gw <router>` plus a
   `dns <addr> ...` line. `/usr/sbin/ifup -n` reports every mistake in the
   file.
5. **Leave `/etc/inittab` alone.** amix-base ships it with the `dlm` line
   (C3-5 §5), so the installer no longer adds it; `l11_inittab` compares the
   file with amix-base's default instead. A box whose `modtools` already
   added the line holds exactly that default, and the class takes it
   silently.
6. **`removef core`** the paths amix-base took over, with APKGENG's
   `/usr/apkg/bin/removef`: stock 2.1 has none. Until then the conffiles are
   listed by both packages; stock `pkgadd` records each as `f … core:none
   amxbase\` (the `\` is the per-package edit flag, so `pkgchk` skips
   amxbase's entry), and `pkgchk` reports an edited one through `core`'s.
   After the `removef` that goes quiet. No re-typing step: the stock
   `installf -f` crashes after `installf -c conffile … e` (pkgtools, E1).

The installer does not write `/etc/nodename`, the host's line in
`/etc/inet/hosts`, `/etc/resolv.conf` or any `ifconfig` line: `ifup` writes
them from `/etc/inet/interfaces` at the first boot. `/etc/rc.conf` is
optional (`ifup_dhcpwait`, default 20 s; `ifup_bound`, default 120 s). An
interface is seen only through its driver's `/etc/inet/link.d` entry: amix-base
ships `aen`, and every other network driver's package ships its own.
