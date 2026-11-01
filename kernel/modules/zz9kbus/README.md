# zz9kbus — the ZZ9000-family board registry

`zz9kbus` is the meeting point between the drivers of ZZ9000-family boards (the Z3660's
`z3660rtg`; a ZZ9000 driver) and `zz9ksvc`, the service channel of the boards' second ARM core.
It is a misc module of a few hundred bytes, MIT, with no device of its own.

- A board driver that finds the SDK bootstrap block on its board fills a `struct
  zz9kbus_board` (`include/sys/zz9kbus.h`) and calls `zz9kbus_register()`, which gives the board a
  unit, 0 or 1. At its `_unload` it calls `zz9kbus_unregister()`, which answers `EBUSY` while
  `zz9ksvc` holds the board.
- `zz9ksvc` takes a unit's board with `zz9kbus_get()` and gives it back with `zz9kbus_put()`.
- Board drivers and `zz9ksvc` name `zz9kbus` in `depend=`; they never name each other, and two
  board drivers on one machine export no clashing names.

The board record gives `zz9ksvc` exactly this much of the board: a 16-bit read of the bootstrap
block, the doorbell write, the mailbox the board driver mapped, and where a range of the
firmware's host-visible heap lies in physical memory. No register pointer and no mapping of the
whole board. `include/sys/zz9kbus.h` describes both sides.

## Layout

| Path | Content |
|---|---|
| `src/zz9kbus.c` | the registry |
| `../include/sys/zz9kbus.h` | the interface, for board drivers and `zz9ksvc`; the ABI kit carries a copy |
| `module/keys`, `module/Master`, `module/Makefile`, `module/VERSION` | as for every module here |
| `test/hosttest.sh` | the host test |
| `pkg/` | the package recipe |

## The module

| `.moddata` key | Value |
|---|---|
| `name` | `zz9kbus` |
| `class` | `boot`, with `match` the boards it serves: resident on a box with one of them; elsewhere `depend=` loads it when a board driver or `zz9ksvc` needs it |
| `match` | `zorro:144b:01` (the Z3660), `mobo:z3660-window`, `zorro:6d6e:03` and `zorro:6d6e:04` (the ZZ9000, Zorro II and III) |
| `unload` | `never` |

Image 632 bytes, file 2,171 bytes on both lines; no kernel memory requests, no DDI imports
beyond `mod_miscops`.

## Building and testing

```sh
make -C zz9kbus/module             # both lines
make -C zz9kbus/module test        # the host test (any host cc)
```

The host test covers registration (units in order, every refusal, the same board twice, a
third board), `get` and `put` (holds counted, units out of range), unregistering while held
(`EBUSY` until the last put), reuse of a freed unit, and `_unload` refused while boards are
registered.

## Packages

`zz9kbus-k30` and `zz9kbus-k46` (pkginst `zz9kbus30`, `zz9kbus46`), its own package: the
object and its `modreg.d` file. Board driver packages and `zz9ksvc` need the one of their line.
