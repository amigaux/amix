# dhcpc/probe

Stage S0 of the DHCP client: before any client code, measure what the 1991
SVR4.0 DLPI path really does. Results: [`../../docs/dhcp-probe.md`](../../docs/dhcp-probe.md).

| File | What |
|---|---|
| `dhcprobe.c` | the probe, run on the Amix machine as root |
| `build.sh` | builds it with gcc-cross-amix into `out/base/dhcprobe` |
| `tapdhcpd.py` | a one-client DHCP responder for a Linux host, attached to a tap device the user owns (no root needed), that logs every frame it sends and every DHCP, ARP or ICMP frame from the client |

## Running

On the host, with the emulator's network on a bridge and a second, unused
tap on the same bridge:

```sh
python3 -I tapdhcpd.py --tap <spare tap> --client-mac <emulator's MAC> \
    --client-ip <addr>/<bits> --router <addr> --server-ip <unused addr> \
    --log tapdhcpd.log [--noise-flag FILE]
```

On the Amix machine:

```sh
dhcprobe -a -x /dev/aen0            # the link steps and the side tests only
dhcprobe -d 3 -x /dev/aen0          # count frames queued before and after the bind
dhcprobe -w 6 -i <addr> /dev/aen0   # the whole exchange: DLPI, then UDP port 68
```

The probe applies nothing: no `ifconfig`, no route, no file. It may run while
IP is linked on the same interface; that is one of the things it tests.

## Output

One line per step, a keyword first: `STEP`, `OPEN`, `INFO` (the fields of a
`DL_INFO_ACK`), `BIND`, `SIDE`, `QUEUED`, `SEND`, `RECV` (frame data length
beside the IP and UDP lengths, the addresses), `DHCP` (the decoded reply),
`UDP`, then `RULE<n> ok` or `FAIL <what>` per rule of P-36 §4.4, and `DONE`.
Exit 0 when every step that ran passed.
