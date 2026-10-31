# DHCP stage S0: what the 1991 DLPI path does

Measured 2026-10-30 with `dhcpc/probe/dhcprobe` on the Amiberry emulator: an
A3000 running stock Amix 2.1c with the A2065 Ethernet board (`/dev/aen0`,
major 18), IP already linked and addressed on `aen0` by the stock network
chain. The DHCP server was `dhcpc/probe/tapdhcpd.py` on a second tap of the
same host bridge, answering only this machine. Two boots, eight probe runs, all
exit 0; the Z3660 Ethernet (`zen0`) was not measured (no emulated board with
its driver exists yet).

The probe was built with gcc-cross-amix, the period compiler: it stands in for
a `/usr/sbin` boot-path tool, so it links only the stock `libc.so.1`,
`libnsl.so` and the `libsocket.a` archive, and needs nothing from `/opt/amix`.
The shipped `dhcpc` and `dlpi-mac` are built with GCC 14 (T-56 D6) against the
same stock libraries. No return-convention shims are needed for that: the
pinned gcc14-cross-amix (b51ff39) already returns pointers in `%a0` and `%d0`
and small structures in memory, as the stock libraries expect
(`amix-abi.h`), and its own runtime, `libamixc99`, is a static archive.

## The rules of P-36 §4.4, one by one

| Rule | What was measured | Verdict |
|---|---|---|
| 1. Open, then `DL_INFO_REQ` under an alarm | open returns at once; `DL_INFO_ACK`: Style 1, `DL_ETHER`, max SDU 1500, address length 6. On a fresh stream: state 0 (unbound) and no address (`addr_offset=0`) | holds |
| 2. `DL_ATTACH_REQ` only for Style 2 | sent to the A2065 anyway on a separate stream: **no reply at all**, the 4 s alarm fired; the stream still answered `DL_INFO_REQ` afterwards. An unknown primitive is also dropped without a reply | holds; the rule is what keeps a client from hanging on this driver |
| 3. `DL_BIND_REQ` 0x0800, MAC from the ack, discard `DL_UNITDATA_IND` meanwhile | `DL_BIND_ACK` carries the 6-byte address; `DL_INFO_ACK` carries it only once bound (state 3, idle). A second stream binds 0x0800 while IP's own stream is bound, and both get a copy of every IP frame: 58 frames queued in 3 s at 20 frames/s | holds |
| 3, the stale slot | a stream that reuses a slot an earlier process bound **opens already bound**: state 3, SAP 0x0800, address present, and 53–58 frames queued **before any request was sent**. A fresh slot queued none | the hazard is real; see below |
| 4. Broadcast DISCOVER through `DL_UNITDATA_REQ`, own IP/UDP headers | 6-byte destination at `dl_dest_addr_offset` = 20; the driver puts the bound SAP in the type field. The server got a 342-byte frame (14 + 328), IP source 0.0.0.0, destination 255.255.255.255 | holds |
| 4. Receive OFFER and ACK on the DLPI stream | a broadcast OFFER and a **unicast** ACK (to the client's MAC and address) both reached the probe's stream while IP also had them | holds |
| 4. Trust only the IP and UDP lengths | every received frame's data is **14 bytes longer** than its IP datagram (342 for 328): the driver counts the Ethernet header into the length it copies from after the header (`aen.c`, receive path) | holds, and is required |
| 4. Match `xid` and `chaddr` | done; see the emulator note on `chaddr` | holds |
| 6. Close the stream; renew over UDP bound to port 68 | `socket`, `bind *:68` as root, unicast REQUEST to the server: the unicast ACK came back on the socket | holds |
| 6. ICMP while nothing listens on 68 | the server's unicast ACK, arriving while only the DLPI stream had it, was answered by IP with **ICMP port unreachable** (type 3 code 3, quoting 67 → 68) when the server's ARP entry was already cached. With the socket bound, never | the socket is needed, as planned |
| 8. REBIND by broadcast from the socket | with `SO_BROADCAST`, `sendto 255.255.255.255:67` works, but the frame leaves with IP destination **the subnet's directed broadcast** (`x.y.z.255`) and Ethernet broadcast. The ACK came back on the socket | holds on one segment; a relay agent would not see it |

Rules 5, 7, 9, 10 and 11 apply the lease and keep state; the probe applies
nothing, so they are not measured here.

## What it means for the client

- **The acks overtake queued frames.** The A2065 sends `DL_INFO_ACK` and
  `DL_BIND_ACK` as `M_PCPROTO`, and the stream head hands high-priority
  messages out first, so even with 58 data frames queued the probe never had to
  skip one to reach an ack. The discard loop of rule 3 stays (another driver
  may answer with `M_PROTO`), but the real cost of the stale slot is the data:
  a client on a reused slot starts with a queue full of other IP traffic and
  must ignore everything that is not a DHCP reply to its own `xid`.
- **The A2065 needs no per-driver code.** Every difference from a textbook
  DLPI provider (no ATTACH reply, silent drop of unknown primitives, the 14
  extra bytes, the pre-bound reused slot) is covered by a general rule.
- **The ICMP finding confirms the D-N15 design.** Holding a bound address with
  no listener on port 68 makes IP refuse the server's unicast replies; the UDP
  socket on 68 must exist from BOUND on.
- **REBIND reaches only the local segment** on this IP. Acceptable for 1.0.

## The emulator translates the MAC

Amiberry's A2065 keeps two station addresses: the one the Amix driver reads
from the board and programs (`00:80:10:ff:ff:ff` here; its low three bytes
come from the board's serial number, so probably the same on every emulated
board, not checked) and the one configured for the host side. It swaps them in
the Ethernet header, in ARP, and in the DHCP `chaddr` field (fixing the UDP
checksum after), but not inside DHCP options. So on the emulator:

- the probe saw its own MAC as `00:80:10:ff:ff:ff` while the server saw the
  configured one, and the `chaddr` match still worked in both directions;
- a client identifier (option 61) built from the MAC would carry the guest
  address, likely the same for every emulated machine, and a server that keys
  leases by it would see one client. The client therefore sends no option 61
  in 1.0 (`package-split.md`);
- the UDP checksum the server sees on a client's DHCP frame is the emulator's,
  not the client's, so the client's checksum code is proven only on metal.

On real hardware there is no translation.

## Still open after S0

| Item (P-36) | Why not settled | Where it gets settled |
|---|---|---|
| A UDP socket sending before the interface has an address | the interface was addressed throughout (the test machine is driven over the network) | S1: the client does not rely on it (INIT goes over DLPI) |
| Re-addressing a live interface | the probe applies nothing | S1 |
| `zen0` (z3660eth) against the same rules | no emulated Z3660 Ethernet board with the driver loaded exists yet | an emulator configuration with the Z3660 network backend and a kernel carrying the z3660eth module, or metal |
| How fast `aenopen` fails with no A2065 fitted | the board was present | a boot without the board |
| Hydra (`hya0`) | no driver source | when the source is here |
