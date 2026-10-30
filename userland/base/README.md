# userland/base

The part of the Amiga UNIX (Amix) base system that this project writes itself:
the boot helper library and our boot scripts, the one network set-up shared by
every Ethernet interface, a DHCP client, and the base configuration files the
stock `core` package used to own. Later, the display launcher.

Amix is Commodore's 1992 port of AT&T System V Release 4.0 to the 68030 Amiga.
Its stock boot machinery (`/etc/inittab`, `/usr/sbin/rc0`–`rc6`, `/etc/init.d`
with `S`/`K` links) is standard SVR4 and stays as it is. What this directory
replaces is narrow: the stock network chain (`/etc/init.d/inetinit`,
`/etc/inet/network-config`, `/etc/inet/rc.inet`), which only knows the A2065
card, and the scattered scripts and settings the installer used to write
outside the package database.

## The rules it follows

- **One shared mechanism and one config shape for every general thing.** All
  network interfaces are configured by one file, `/etc/inet/interfaces`, and
  brought up by one script, `ifup`. A driver adds a one-line description of
  itself under `/etc/inet/link.d/` and nothing else. No driver gets a special
  case in `ifup` or in the DHCP client.
- **Defaults in the package, your changes in a file no package owns.**
  `/etc/rc.conf` (services on or off, and their settings) and
  `/etc/inet/interfaces` belong to the administrator; an update never touches
  them. The few files that must be edited in place are *conffiles*: an update
  keeps your version and puts the new default beside it as `<file>.new`.
- **Stock behaviour where it works.** Nothing here patches a stock binary.
- **Clean installs only.** Release 1.1 does not upgrade a 1.0 system, so there
  is no migration code here.

## What is here

| Path | What | State |
|---|---|---|
| [`docs/plan.md`](docs/plan.md) | the pieces, their files and the order they are built in | plan |
| [`docs/package-split.md`](docs/package-split.md) | the packages: base (boot and network) and `dhcp-client`, and the contract between them | design |
| [`docs/dhcp-probe.md`](docs/dhcp-probe.md) | what the 1991 DLPI path was measured to do, the facts the DHCP client is built on | measured |
| [`dhcpc/probe/`](dhcpc/probe/) | `dhcprobe`, the stage-0 probe, and `tapdhcpd.py`, the test DHCP responder it runs against | tool |
| [`man/`](man/) | `man`, one manual command for the add-on pages and the stock ones ([`docs/man.md`](docs/man.md)), its page and its host test | written, not yet packaged |

The rest (`rc/`, `net/`, the client in `dhcpc/`, `etc/`) arrives with the packages; see
`docs/plan.md`.

## Building

Programs that run on the boot path (`dhcpc`, `dlpi-mac`, the probe) are built
with the period cross compiler, gcc-cross-amix (`toolchain/gcc-cross-amix.pin`),
against the stock headers and libraries only, so they need nothing from
`/opt/amix`:

```sh
userland/base/dhcpc/probe/build.sh          # writes out/base/dhcprobe
sh userland/base/man/test-man.sh            # host tests of the man front-end
```

## Licence

MIT, see [LICENSE](LICENSE).
