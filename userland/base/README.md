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
| [`dhcpc/`](dhcpc/) | `dhcpc`, the DHCP client, and its page `dhcpc(1M)` | written, packaged (`pkg/dhcp-client`) |
| [`dhcpc/probe/`](dhcpc/probe/) | `dhcprobe`, the stage-0 probe, and `tapdhcpd.py`, the test DHCP responder the probe and the client's tests run against | tool |
| [`pkg/`](pkg/) | the two packages, `amix-base` (amxbase) and `dhcp-client` (dhcpc) | packaging |
| [`man/`](man/) | `man`, one manual command for the add-on pages and the stock ones ([`docs/man.md`](docs/man.md)), its page and its host test | written, not yet packaged |
| [`rc/`](rc/) | `rc.subr`, the boot scripts' helper library; the pages `rc.subr(1M)` and `rc.conf(4)`; its host test | written, not yet packaged |
| [`net/`](net/) | `ifup`/`ifdown`, `ifup.subr` (the `interfaces` parser and the shared apply step), `dhcpc-hook`, the new `inetinit`, `link.d/aen`, the two legacy hooks; the pages `ifup(1M)` and `interfaces(4)`; [`dlpi-mac`](net/dlpi-mac/), the generic MAC reader, and its page | written, not yet packaged |

What follows (`ifup`'s DHCP default in the installer, metal) is in `docs/plan.md`.

## Building

Programs that run on the boot path are built against the stock headers and
libraries only, so they need nothing from `/opt/amix`: `dhcpc` and `dlpi-mac`
with GCC 14, gcc14-cross-amix (`toolchain/gcc14-cross-amix.pin`, T-56 D6),
with the harness's flags (`-m68020-60 -mno-strict-align`); the probe with the
period cross compiler, gcc-cross-amix (`toolchain/gcc-cross-amix.pin`):

```sh
userland/base/dhcpc/probe/build.sh          # writes out/base/dhcprobe
userland/base/net/dlpi-mac/build.sh         # writes out/base/dlpi-mac
userland/base/dhcpc/build.sh                # writes out/base/dhcpc
sh build/pkg/pkgbuild.sh userland/base/pkg/amix-base     # and pkg/dhcp-client
sh userland/base/man/test-man.sh            # host tests of the man front-end
sh userland/base/rc/test-rc.sh              # host tests of rc.subr
sh userland/base/rc/test-devnodes.sh        # the device-node boot step
sh userland/base/net/test-ifparse.sh sh nawk    # the parser, under each awk
sh userland/base/net/test-ifup.sh sh nawk       # ifup, ifdown and the hook
sh userland/base/etc/test-profile.sh           # /etc/profile = stock + profile.add
sh userland/base/etc/test-inittab.sh           # /etc/inittab = stock + the dlm line
```

## Licence

MIT, see [LICENSE](LICENSE).
