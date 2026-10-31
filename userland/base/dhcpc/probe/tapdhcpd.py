#!/usr/bin/env python3
"""tapdhcpd -- a one-client DHCP responder on a Linux tap, for the dhcprobe runs.

    tapdhcpd.py --tap TAP --client-mac MAC --client-ip ADDR/BITS --router ADDR
                --server-ip ADDR [--server-mac MAC] [--lease SECS] --log FILE
                [--noise-flag FILE] [--control FILE] [--dns ADDR,...]
                [--hostname NAME] [--seconds N]

It attaches to an existing tap that the calling user owns (TUNSETIFF needs no
capability then), so it needs no root and no listener on the host. On the
segment behind the tap it answers exactly one client:

  - ARP requests for --server-ip, from anyone, so the client's unicast renew
    reaches this responder;
  - DHCPDISCOVER / DHCPREQUEST whose chaddr is --client-mac: OFFER / ACK with
    --client-ip, mask, router, the server identifier and a short lease
    (a REQUEST for any other address gets a NAK). Replies follow RFC 2131
    4.1: to ciaddr by unicast when it is set, else to the broadcast address
    when the client set the broadcast flag, else by unicast to chaddr and
    yiaddr.

Everything else is ignored. Every frame it sends, and every frame from the
client that is DHCP, ARP for the server or ICMP, is logged with a timestamp.
ICMP from the client is decoded (type, code, the quoted UDP port), which is
how "IP answered our unicast ACK with port-unreachable" shows up.

The file named by --control, read at every DHCP message, changes the
answers while the client runs (the dhcpc S1 tests): a word on its first line
of "silent" (answer nothing), "norenew" (ignore a unicast REQUEST from a
bound client, so it has to rebind), "nak" (refuse every REQUEST) or
"conflict" (answer the client's ARP probe for its address as another
station, 02:00:de:ad:be:ef, so it has to decline it); no file or any other
word, normal. The client's ARP probes and its DECLINE are logged. --dns and --hostname add options 6 and 12.

While the file named by --noise-flag exists, it also sends the client 20
unsolicited ICMP echo replies a second (IP drops them without answering), so
that a DLPI stream bound to 0x0800 always has frames queued: the stray
DL_UNITDATA_IND test.

MIT licence, see LICENSE at the top of the repository.
"""
import argparse
import fcntl
import os
import select
import struct
import sys
import time

TUNSETIFF = 0x400454CA
IFF_TAP = 0x0002
IFF_NO_PI = 0x1000
BCAST = b"\xff" * 6
COOKIE = 0x63825363
OTHER = bytes.fromhex("0200deadbeef")	# the station that "holds" the address
NAMES = {1: "DISCOVER", 2: "OFFER", 3: "REQUEST", 4: "DECLINE", 5: "ACK",
         6: "NAK", 7: "RELEASE", 8: "INFORM"}


def mac_b(s):
    return bytes(int(x, 16) for x in s.split(":"))


def mac_s(b):
    return ":".join("%02x" % x for x in b)


def ip_b(s):
    return bytes(int(x) for x in s.split("."))


def ip_s(b):
    return ".".join(str(x) for x in b)


def csum(data):
    if len(data) % 2:
        data += b"\0"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


class Responder:
    def __init__(self, a):
        self.a = a
        self.cmac = mac_b(a.client_mac)
        addr, bits = a.client_ip.split("/")
        self.cip = ip_b(addr)
        self.mask = struct.pack("!I", (0xFFFFFFFF << (32 - int(bits))) & 0xFFFFFFFF)
        self.router = ip_b(a.router)
        self.sip = ip_b(a.server_ip)
        self.smac = mac_b(a.server_mac)
        self.log = open(a.log, "a", buffering=1)
        self.fd = os.open("/dev/net/tun", os.O_RDWR)
        fcntl.ioctl(self.fd, TUNSETIFF,
                    struct.pack("16sH", a.tap.encode(), IFF_TAP | IFF_NO_PI))
        self.ipid = 1
        self.say("START tap=%s client=%s/%s server=%s/%s router=%s lease=%d" % (
            a.tap, a.client_mac, a.client_ip, a.server_ip, a.server_mac,
            a.router, a.lease))

    def say(self, msg):
        self.log.write("%.3f %s\n" % (time.time(), msg))

    def send(self, frame, what):
        if len(frame) < 60:
            frame += b"\0" * (60 - len(frame))
        os.write(self.fd, frame)
        self.say("TX %s len=%d %s" % (what, len(frame), frame[:96].hex()))

    def ipv4(self, dst, proto, payload):
        self.ipid = (self.ipid + 1) & 0xFFFF
        h = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(payload), self.ipid,
                        0, 64, proto, 0, self.sip, dst)
        return h[:10] + struct.pack("!H", csum(h)) + h[12:] + payload

    def udp(self, src_ip, dst_ip, sport, dport, data):
        u = struct.pack("!HHHH", sport, dport, 8 + len(data), 0) + data
        ph = src_ip + dst_ip + struct.pack("!BBH", 0, 17, len(u))
        c = csum(ph + u) or 0xFFFF
        return u[:6] + struct.pack("!H", c) + u[8:]

    def on_arp(self, f):
        op = struct.unpack("!H", f[20:22])[0]
        sha, spa, tpa = f[22:28], f[28:32], f[38:42]
        if op == 1 and tpa == self.cip and sha == self.cmac:
            # the client's probe for the address it was given (RFC 5227)
            self.say("RX ARP probe who-has %s tell %s (%s)" % (ip_s(tpa), ip_s(spa), mac_s(sha)))
            if self.mode() == "conflict":
                arp = struct.pack("!HHBBH6s4s6s4s", 1, 0x0800, 6, 4, 2,
                                  OTHER, self.cip, sha, spa)
                self.send(sha + OTHER + b"\x08\x06" + arp,
                          "CONTROL conflict: ARP %s is-at %s" % (ip_s(self.cip), mac_s(OTHER)))
            return
        if op != 1 or tpa != self.sip:
            return
        self.say("RX ARP who-has %s tell %s (%s)" % (ip_s(tpa), ip_s(spa), mac_s(sha)))
        arp = struct.pack("!HHBBH6s4s6s4s", 1, 0x0800, 6, 4, 2,
                          self.smac, self.sip, sha, spa)
        self.send(sha + self.smac + b"\x08\x06" + arp, "ARP is-at %s" % mac_s(self.smac))

    def on_dhcp(self, f, ip, udp, m):
        if len(m) < 240 or m[0] != 1 or m[28:34] != self.cmac:
            return
        if struct.unpack("!I", m[236:240])[0] != COOKIE:
            return
        xid = m[4:8]
        bflag = struct.unpack("!H", m[10:12])[0] & 0x8000
        ciaddr = m[12:16]
        opts, o = {}, 240
        while o < len(m) and m[o] != 255:
            if m[o] == 0:
                o += 1
                continue
            opts[m[o]] = m[o + 2:o + 2 + m[o + 1]]
            o += 2 + m[o + 1]
        t = opts.get(53, b"\0")[0]
        req = opts.get(50, b"")
        self.say("RX DHCP %s xid=%s bflag=%d ciaddr=%s req=%s sid=%s ip_src=%s "
                 "ip_dst=%s eth_dst=%s frame=%d ip_len=%d" % (
                     NAMES.get(t, t), xid.hex(), bool(bflag), ip_s(ciaddr),
                     ip_s(req) if req else "-",
                     ip_s(opts[54]) if 54 in opts else "-",
                     ip_s(ip[12:16]), ip_s(ip[16:20]), mac_s(f[0:6]), len(f),
                     struct.unpack("!H", ip[2:4])[0]))
        mode = self.mode()
        if mode == "silent":
            self.say("CONTROL silent: no answer")
            return
        if t == 1:
            reply = 2
        elif t == 3:
            if mode == "norenew" and ciaddr != b"\0\0\0\0" and ip[16:20] == self.sip:
                self.say("CONTROL norenew: unicast REQUEST ignored")
                return
            want = req or ciaddr
            reply = 6 if mode == "nak" else (5 if want == self.cip else 6)
        else:
            return
        lease = self.a.lease
        r = bytearray(300)
        r[0:4] = b"\x02\x01\x06\x00"
        r[4:8] = xid
        r[10:12] = m[10:12]
        r[12:16] = ciaddr
        if reply != 6:
            r[16:20] = self.cip
        r[28:34] = self.cmac
        r[236:240] = struct.pack("!I", COOKIE)
        o = bytearray([53, 1, reply, 54, 4]) + self.sip
        if reply != 6:
            o += bytes([51, 4]) + struct.pack("!I", lease)
            o += bytes([58, 4]) + struct.pack("!I", lease // 2)
            o += bytes([59, 4]) + struct.pack("!I", lease * 7 // 8)
            o += bytes([1, 4]) + self.mask + bytes([3, 4]) + self.router
            dns = self.a.dns.split(",") if self.a.dns else [ip_s(self.router)]
            o += bytes([6, 4 * len(dns)]) + b"".join(ip_b(d) for d in dns)
            if self.a.hostname:
                o += bytes([12, len(self.a.hostname)]) + self.a.hostname.encode()
        o += b"\xff"
        r[240:240 + len(o)] = o
        r = bytes(r)
        if ciaddr != b"\0\0\0\0":
            dmac, dip, how = f[6:12], ciaddr, "unicast-ciaddr"
        elif bflag or reply == 6:
            dmac, dip, how = BCAST, b"\xff" * 4, "broadcast"
        else:
            dmac, dip, how = self.cmac, self.cip, "unicast-chaddr"
        u = self.udp(self.sip, dip, 67, 68, r)
        self.send(dmac + self.smac + b"\x08\x00" + self.ipv4(dip, 17, u),
                  "DHCP %s xid=%s yiaddr=%s to=%s/%s (%s)" % (
                      NAMES[reply], xid.hex(), ip_s(self.cip) if reply != 6 else "-",
                      mac_s(dmac), ip_s(dip), how))

    def mode(self):
        try:
            with open(self.a.control) as c:
                return (c.readline().split() or [""])[0]
        except (OSError, TypeError):
            return ""

    def on_icmp(self, ip, ihl):
        icmp = ip[ihl:]
        t, c = icmp[0], icmp[1]
        extra = ""
        if t == 3 and len(icmp) >= 8 + 28:
            q = icmp[8:]
            qihl = (q[0] & 15) * 4
            if q[9] == 17 and len(q) >= qihl + 4:
                sp, dp = struct.unpack("!HH", q[qihl:qihl + 4])
                extra = " quoted udp %s:%d -> %s:%d" % (ip_s(q[12:16]), sp, ip_s(q[16:20]), dp)
        self.say("RX ICMP type=%d code=%d from=%s to=%s%s" % (
            t, c, ip_s(ip[12:16]), ip_s(ip[16:20]), extra))

    def frame(self, f):
        if len(f) < 14:
            return
        et = struct.unpack("!H", f[12:14])[0]
        if et == 0x0806 and len(f) >= 42:
            self.on_arp(f)
            return
        if et != 0x0800 or f[6:12] != self.cmac:
            return
        ip = f[14:]
        ihl = (ip[0] & 15) * 4
        if ip[9] == 1:
            self.on_icmp(ip, ihl)
        elif ip[9] == 17:
            udp = ip[ihl:]
            if struct.unpack("!H", udp[2:4])[0] == 67:
                ulen = struct.unpack("!H", udp[4:6])[0]
                self.on_dhcp(f, ip, udp, udp[8:ulen])

    def noise(self):
        payload = struct.pack("!BBHHH", 0, 0, 0, 0x4242, 1) + b"dhcprobe-noise"
        payload = payload[:2] + struct.pack("!H", csum(payload)) + payload[4:]
        f = self.cmac + self.smac + b"\x08\x00" + self.ipv4(self.cip, 1, payload)
        os.write(self.fd, f + b"\0" * max(0, 60 - len(f)))

    def run(self):
        end = time.time() + self.a.seconds
        nxt, noisy, sent = 0.0, False, 0
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                self.frame(os.read(self.fd, 2048))
            on = bool(self.a.noise_flag) and os.path.exists(self.a.noise_flag)
            if on != noisy:
                self.say("NOISE %s (%d echo replies sent so far)" % ("on" if on else "off", sent))
                noisy = on
            if on and time.time() >= nxt:
                self.noise()
                sent += 1
                nxt = time.time() + 0.05
        self.say("STOP noise_sent=%d" % sent)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--tap", required=True)
    p.add_argument("--client-mac", required=True)
    p.add_argument("--client-ip", required=True, help="ADDR/BITS")
    p.add_argument("--router", required=True)
    p.add_argument("--server-ip", required=True)
    p.add_argument("--server-mac", default="02:00:00:00:d4:c9")
    p.add_argument("--lease", type=int, default=120)
    p.add_argument("--log", required=True)
    p.add_argument("--noise-flag")
    p.add_argument("--control")
    p.add_argument("--dns", help="comma-separated; default the router")
    p.add_argument("--hostname")
    p.add_argument("--seconds", type=int, default=900)
    Responder(p.parse_args()).run()


if __name__ == "__main__":
    sys.exit(main())
