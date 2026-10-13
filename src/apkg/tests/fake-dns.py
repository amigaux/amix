#!/usr/bin/env python3
# fake-dns.py - a scripted UDP nameserver for the apkg stub-resolver tests.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# One behaviour per instance, chosen on the command line, so a test says
# which kind of nameserver it is pointing apkg at instead of encoding the
# behaviour in the name being looked up:
#
#   ok        a correct answer: one A record, owner compressed to the
#             question name.
#   cname     a CNAME CHAIN to an A record, built with compression
#             pointers in BOTH places they legally occur: the RR owner
#             (a pointer to the question name) and INSIDE the rdata of
#             the CNAME (a label followed by a pointer into the middle
#             of the question name).  A resolver that does not implement
#             compression cannot answer this, and one that follows the
#             chain by record ORDER rather than by owner name is caught
#             too: the A record is emitted BEFORE the CNAME that leads
#             to it.
#   nx        a well-formed reply with rcode 3 (name error).  This is an
#             ANSWER, not a failure: the client must not retry the same
#             server for it.
#   garbage   a reply with our transaction id and a plausible header,
#             whose answer section is nonsense (a reserved label type,
#             lengths running past the datagram).
#   short     an 8-byte datagram: shorter than a DNS header.
#   wrongid   a correct answer carrying someone ELSE's transaction id -
#             i.e. the shape of an off-path spoof.  Must be discarded.
#   quiet     read the query and say nothing at all, ever.  The client's
#             per-attempt timeout is the only thing that can end this.
#
# usage: fake-dns.py <port> <mode> [answer-ip]
#
# Binds 127.0.0.1 only and never forwards anything anywhere.

import random
import socket
import sys

MODES = ("ok", "cname", "nx", "garbage", "short", "wrongid", "quiet")


def parse_qname(msg, off):
    """Decode the QNAME at msg[off]; return (dotted-name, offset-past).

    The queries under test are ours, so no compression pointer can occur
    here -- a pointer is treated as malformed input and refused.
    """
    labels = []
    while True:
        if off >= len(msg):
            raise ValueError("qname runs past the datagram")
        n = msg[off]
        if n & 0xC0:
            raise ValueError("compression pointer in a query")
        off += 1
        if n == 0:
            break
        labels.append(msg[off:off + n].decode("latin-1"))
        off += n
    return ".".join(labels), off


def header(qid, ancount, rcode=0):
    flags = 0x8180 | (rcode & 0x0F)          # QR | RD | RA
    return bytes([
        (qid >> 8) & 0xFF, qid & 0xFF,
        (flags >> 8) & 0xFF, flags & 0xFF,
        0, 1,                                 # qdcount
        (ancount >> 8) & 0xFF, ancount & 0xFF,
        0, 0,                                 # nscount
        0, 0,                                 # arcount
    ])


def rr(owner_bytes, rtype, rdata, ttl=60):
    return (owner_bytes
            + bytes([(rtype >> 8) & 0xFF, rtype & 0xFF, 0, 1])
            + ttl.to_bytes(4, "big")
            + bytes([(len(rdata) >> 8) & 0xFF, len(rdata) & 0xFF])
            + rdata)


def ptr(off):
    return bytes([0xC0 | ((off >> 8) & 0x3F), off & 0xFF])


def second_label_offset(msg):
    """Offset of the question name's SECOND label (i.e. the parent
    domain), which the CNAME rdata points into."""
    off = 12
    n = msg[off]
    return off + 1 + n


def answer_ok(msg, qid, qend, ip):
    body = msg[12:qend]                       # echo the question verbatim
    return header(qid, 1) + body + rr(ptr(12), 1, socket.inet_aton(ip))


def answer_cname(msg, qid, qend, ip):
    """qname CNAME alias.<parent> ; alias.<parent> A <ip>

    Emitted A-record-FIRST on purpose (see the module comment).

    Every pointer here points strictly BACKWARDS, into the question --
    which is what RFC 1035 means by "a prior occurrence" and what every
    real server emits.  A forward pointer would be a different test (of
    a rule apkg deliberately enforces: forward and self-pointers are how
    a reply builds an infinite name, so dns.c refuses them)."""
    question = msg[12:qend]
    parent = second_label_offset(msg)
    # one literal label + a pointer into the MIDDLE of the question name
    alias = bytes([len("alias")]) + b"alias" + ptr(parent)
    a_rr = rr(alias, 1, socket.inet_aton(ip))       # owner: literal+pointer
    cname_rr = rr(ptr(12), 5, alias)                # owner: pure pointer
    return header(qid, 2) + question + a_rr + cname_rr


def answer_nx(msg, qid, qend, ip):
    return header(qid, 0, rcode=3) + msg[12:qend]


def answer_garbage(msg, qid, qend, ip):
    # a plausible header, then an answer section that is not one: 0x40 is
    # a reserved label type, and the lengths run off the end
    return header(qid, 1) + msg[12:qend] + bytes([0x40, 0xFF, 0xFF, 0x01])


def answer_short(msg, qid, qend, ip):
    return header(qid, 1)[:8]


def answer_wrongid(msg, qid, qend, ip):
    return answer_ok(msg, (qid + 1) & 0xFFFF, qend, ip)


ANSWERS = {
    "ok": answer_ok,
    "cname": answer_cname,
    "nx": answer_nx,
    "garbage": answer_garbage,
    "short": answer_short,
    "wrongid": answer_wrongid,
}


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in MODES:
        sys.exit("usage: fake-dns.py <port> <%s> [answer-ip]"
                 % "|".join(MODES))
    port = int(sys.argv[1])
    mode = sys.argv[2]
    ip = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", port))
    while True:
        try:
            msg, peer = sock.recvfrom(4096)
        except OSError:
            continue
        if mode == "quiet" or len(msg) < 13:
            continue
        qid = (msg[0] << 8) | msg[1]
        try:
            _name, qend = parse_qname(msg, 12)
            qend += 4                          # qtype + qclass
            if qend > len(msg):
                continue
        except ValueError:
            continue
        reply = ANSWERS[mode](msg, qid, qend, ip)
        if mode == "garbage":
            # one byte of genuine noise on top, so a lucky parse is not a
            # standing possibility across runs
            reply += bytes([random.randrange(256)])
        sock.sendto(reply, peer)


if __name__ == "__main__":
    main()
