#!/usr/bin/env python3
"""build-tzfile.py -- regenerate Amix's zone files (/usr/lib/locale/TZ) from current tzdata.

The 1991 zone files Amix ships carry 1991 rules: EET/MET/WET end summer time on the
last Sunday of SEPTEMBER (the EU moved it to October in 1996), the US zones keep the
pre-2007 rule, and so on. This tool compiles the vendored tzdata (src/tz/tzdata.zi,
public domain, IANA) with the host's zic and rewrites every compiled zone the image
ships, under its 1991 NAME and with its 1991 MEANING, in the 1991 tzfile layout the
Amix libc reads:

    char reserved[24]; long ttisstdcnt, leapcnt, timecnt, typecnt, charcnt;  (44 B)
    long ats[timecnt]; uchar types[timecnt]; {long gmtoff; uchar isdst, abbrind}[typecnt];
    char chars[charcnt]            -- no magic, 32-bit, no leap seconds, no footer

Only transitions in [1970, 2038) are kept (the reader's TZ_MAX_TIMES 370 / TZ_MAX_TYPES
10 / TZ_MAX_CHARS 50 are enforced). Before the first transition the 1991 localtime()
uses the first non-DST type, so the type list is ordered to make that the zone's type at
1970 (a zone in DST at 1970 gets a transition AT 0). Every output is checked against the
tzdata answer (offset, isdst, abbreviation) with the 1991 lookup algorithm at every
transition and every hour boundary around it.

Name meanings kept from 1991 (not today's tzdata aliases): EET/WET/MET/CET are the
rule zones they were (today's tzdata links them to Athens/Lisbon/Brussels, whose
history differs), and GMT+N is N hours EAST of GMT as in 1991's etcetera (today's
Etc/GMT+N is the opposite sign). Names tzdata dropped map to their successors.

Usage: tools/build-tzfile.py [--tzdata FILE] [--out DIR] [--compare STOCKDIR]
Output: DIR/<name> for every zone plus DIR/MANIFEST ("sha256  size  name" lines);
the set hash is sha256(MANIFEST), pinned by tools/build-install-iso.sh.
"""
import argparse, hashlib, os, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TZDATA = os.path.join(REPO, "src", "tz", "tzdata.zi")
TZDATA_SHA = "af5c1d3bebe136d372c131bb1a45725f955a8cc2a5ae2fc5a31d3b372e145f49"   # 2026c
OUT = os.path.join(REPO, "payload", "tz")

T_MAX_TIMES, T_MAX_TYPES, T_MAX_CHARS = 370, 10, 50
LO, HI = 0, 2 ** 31            # 1970-01-01 .. 2038-01-19 (32-bit time_t)
NOW = 1767225600               # 2026-01-01: --compare splits CHANGED (today on) from HISTORY

# The 1991 rule zones, in the compact tzdata.zi spelling (E = EU, c = C-Eur).
CLASSIC = ["Z AMIX/WET 0 E WE%sT", "Z AMIX/CET 1 c CE%sT",
           "Z AMIX/MET 1 c ME%sT", "Z AMIX/EET 2 E EE%sT"]
for _h in range(1, 14):
    CLASSIC.append("Z AMIX/GMT+%d %d - GMT+%02d00" % (_h, _h, _h))
    if _h <= 12:
        CLASSIC.append("Z AMIX/GMT-%d -%d - GMT-%02d00" % (_h, _h, _h))

# Every compiled zone the stock image ships (the zic SOURCE files beside them --
# asia, europe, ... -- and the localtime symlink are not zones and stay stock).
ZONES = """CET CST6CDT EET EST EST5EDT GB-Eire GMT Greenwich HST Hongkong Iceland Israel
Japan MET MST MST7MDT NZ Navajo PRC PST8PDT Poland ROC ROK Singapore Turkey UCT UTC
Universal W-SU WET Australia/Broken-Hill Australia/LHI Australia/NSW Australia/North
Australia/Queensland Australia/South Australia/Sturt Australia/Tasmania Australia/Victoria
Australia/West Australia/Yancowinna Brazil/Acre Brazil/DeNoronha Brazil/East Brazil/West
Canada/Atlantic Canada/Central Canada/East-Saskatche Canada/Eastern Canada/Mountain
Canada/Newfoundland Canada/Pacific Canada/Yukon Chile/Continental Chile/EasterIsland
Mexico/BajaNorte Mexico/BajaSur Mexico/General US/Arizona US/Central US/East-Indiana
US/Eastern US/Hawaii US/Mountain US/Pacific US/Pacific-New US/Yukon""".split()
ZONES += ["GMT+%d" % h for h in range(1, 14)] + ["GMT-%d" % h for h in range(1, 13)]

SOURCE = {n: n for n in ZONES}
SOURCE.update({n: "AMIX/" + n for n in ("WET", "CET", "MET", "EET")})
SOURCE.update({n: "AMIX/" + n for n in ZONES if n.startswith(("GMT+", "GMT-"))})
SOURCE.update({
    "Australia/Broken-Hill": "Australia/Broken_Hill",  # renamed
    "Australia/Sturt": "Australia/Broken_Hill",        # 1991: "9:00 NSW", as Broken-Hill
    "Canada/East-Saskatche": "America/Regina",         # 14-char s5 cut of East-Saskatchewan
    "US/Pacific-New": "America/Los_Angeles",           # dropped 2020; was US/Pacific + a bill
    "US/Yukon": "America/Anchorage",                   # 1991: -9:00 US Y%sT (Alaska)
})


def die(msg):
    sys.exit("build-tzfile: STOP: " + msg)


def read_tzif64(path):
    """(transitions, types[(gmtoff, isdst, abbr)], idx) from the 64-bit block."""
    d = open(path, "rb").read()
    if d[:4] != b"TZif" or d[4:5] < b"2":
        die("%s: not a v2+ TZif (compile with zic -b fat)" % path)
    isut, isstd, leap, tc, ty, ch = struct.unpack(">6l", d[20:44])
    o = 44 + tc * 5 + ty * 6 + ch + leap * 8 + isstd + isut
    isut, isstd, leap, tc, ty, ch = struct.unpack(">6l", d[o + 20:o + 44])
    o += 44
    ats = list(struct.unpack(">%dq" % tc, d[o:o + 8 * tc])); o += 8 * tc
    idx = list(d[o:o + tc]); o += tc
    raw = [struct.unpack(">lBB", d[o + 6 * i:o + 6 * i + 6]) for i in range(ty)]; o += 6 * ty
    chars = d[o:o + ch]
    types = [(g, s, chars[a:chars.index(b"\0", a)].decode()) for g, s, a in raw]
    return ats, types, idx


def lookup64(z, t):
    """The RFC 8536 answer: type 0 before the first transition."""
    ats, types, idx = z
    i = 0
    for a, k in zip(ats, idx):
        if a > t:
            break
        i = k
    return types[i]


def convert(z):
    """The 1991-layout bytes for one zone, clipped to [LO, HI)."""
    ats, types, idx = z
    init = lookup64(z, LO)
    trans = []
    cur = init
    for a, i in zip(ats, idx):
        if LO < a < HI and types[i] != cur:
            trans.append((a, types[i])); cur = types[i]
    order = []                       # types in order of first use
    if init[1]:                      # DST at 1970: a standard type must come first
        std = next((t for _, t in trans if not t[1]), None)
        if std is None:
            die("zone is in DST at 1970 and never leaves it")
        order.append(std)
        trans.insert(0, (LO, init))
    for t in [init] + [t for _, t in trans]:
        if t not in order:
            order.append(t)
    chars, abbrind = b"", {}
    for t in order:
        if t[2] not in abbrind:
            abbrind[t[2]] = len(chars); chars += t[2].encode() + b"\0"
    if len(trans) > T_MAX_TIMES or len(order) > T_MAX_TYPES or len(chars) > T_MAX_CHARS:
        die("limits: %d times / %d types / %d chars" % (len(trans), len(order), len(chars)))
    out = b"\0" * 24 + struct.pack(">5l", 0, 0, len(trans), len(order), len(chars))
    out += b"".join(struct.pack(">l", a) for a, _ in trans)
    out += bytes(order.index(t) for _, t in trans)
    out += b"".join(struct.pack(">lBB", g, s, abbrind[a]) for g, s, a in order)
    return out + chars


def read1991(d):
    tsc, lc, tc, ty, ch = struct.unpack(">5l", d[24:44])
    if lc or tsc and tsc != ty:
        die("unexpected ttisstd/leap counts")
    o = 44
    ats = list(struct.unpack(">%dl" % tc, d[o:o + 4 * tc])); o += 4 * tc
    idx = list(d[o:o + tc]); o += tc
    raw = [struct.unpack(">lBB", d[o + 6 * i:o + 6 * i + 6]) for i in range(ty)]; o += 6 * ty
    chars = d[o:o + ch]
    if o + ch + 8 * lc + tsc != len(d):
        die("1991 file length mismatch")
    types = [(g, s, chars[a:chars.index(b"\0", a)].decode()) for g, s, a in raw]
    return ats, types, idx


def lookup1991(z, t):
    """The 1989 tzcode localsub() choice."""
    ats, types, idx = z
    if not ats or t < ats[0]:
        i = 0
        while types[i][1]:
            i += 1
            if i >= len(types):
                i = 0; break
        return types[i]
    k = 1
    while k < len(ats) and t >= ats[k]:
        k += 1
    return types[idx[k - 1]]


def probes(*zs):
    pts = {LO, HI - 1}
    for z in zs:
        for a in z[0]:
            if LO <= a < HI:
                pts.update((a - 1, a, a + 1, a - 3600, a + 3600))
    return sorted(p for p in pts if LO <= p < HI)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tzdata", default=TZDATA)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--compare", help="a directory holding the stock zone files")
    a = ap.parse_args()
    if hashlib.sha256(open(a.tzdata, "rb").read()).hexdigest() != TZDATA_SHA:
        die("%s is not the pinned tzdata 2026c (sha256 %s)" % (a.tzdata, TZDATA_SHA))
    zic = shutil.which("zic") or die("no zic on PATH")
    tmp = tempfile.mkdtemp(prefix="build-tzfile.")
    try:
        extra = os.path.join(tmp, "amix.zi")
        open(extra, "w").write("\n".join(CLASSIC) + "\n")
        r = subprocess.run([zic, "-b", "fat", "-d", os.path.join(tmp, "z"), a.tzdata, extra],
                           capture_output=True, text=True)
        if r.returncode:
            die("zic failed:\n" + r.stderr)
        if os.path.isdir(a.out):
            shutil.rmtree(a.out)
        man = []
        for name in sorted(ZONES):
            src = os.path.join(tmp, "z", SOURCE[name])
            if not os.path.isfile(src):
                die("%s: tzdata has no %s" % (name, SOURCE[name]))
            z64 = read_tzif64(src)
            data = convert(z64)
            z91 = read1991(data)
            for t in probes(z64, z91):
                if lookup1991(z91, t) != lookup64(z64, t):
                    die("%s: the 1991 lookup disagrees with tzdata at %d" % (name, t))
            p = os.path.join(a.out, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(data)
            man.append("%s  %5d  %s" % (hashlib.sha256(data).hexdigest(), len(data), name))
    finally:
        shutil.rmtree(tmp)
    mtext = "\n".join(man) + "\n"
    open(os.path.join(a.out, "MANIFEST"), "w").write(mtext)
    print("build-tzfile: %d zones -> %s  set sha256 %s" % (
        len(man), a.out, hashlib.sha256(mtext.encode()).hexdigest()))
    if a.compare:
        compare(a.compare, a.out)


def compare(stock, new):
    import datetime
    cnt = {}
    for name in sorted(ZONES):
        s = open(os.path.join(stock, name), "rb").read()
        n = open(os.path.join(new, name), "rb").read()
        zs, zn = read1991(s), read1991(n)
        if s == n:
            kind, note = "IDENTICAL", ""
        else:
            diff = [t for t in probes(zs, zn) if lookup1991(zs, t)[:2] != lookup1991(zn, t)[:2]]
            if diff:
                now = [t for t in diff if t >= NOW]
                kind = "CHANGED" if now else "HISTORY"
                t = (now or diff)[0]
                note = "%s %s: stock %s, new %s" % (
                    "from" if now else "before 2026, first",
                    datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%d"),
                    lookup1991(zs, t), lookup1991(zn, t))
            else:
                ab = sorted({t[2] for t in zs[1]}), sorted({t[2] for t in zn[1]})
                kind = "ABBR-ONLY" if ab[0] != ab[1] else "EQUIVALENT"
                note = "%s -> %s" % ab if ab[0] != ab[1] else "same offsets and names"
        cnt[kind] = cnt.get(kind, 0) + 1
        print("%-10s %-22s %s" % (kind, name, note))
    print("build-tzfile: compare: " + ", ".join("%s %d" % kv for kv in sorted(cnt.items())))


if __name__ == "__main__":
    main()
