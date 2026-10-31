#!/usr/bin/env python3
"""scan060-g14.py -- the 68060 instruction scan for GCC 14 output, with the
switch tables sized from the code rather than guessed from the data.

    scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...

Exit 0 clean, 1 a 68060-unimplemented instruction, 2 unreadable input,
3 untrustworthy (a table could not be sized, or the decoder lost sync).

WHY THIS EXISTS.  GCC 14 compiles a switch into

    cmpib #32,%d6 ; bhiw default          (or moveq #N,%dY; cmpl %dX,%dY; bcs)
    movew %pc@(T,%d0:l),%d0               (or moveaw ...,%a5 / movew %a0@(0,%d0:l))
    jmp   %pc@(T,%d0:w)

with a table of N+1 signed word offsets at T -- and, unlike gcc 2.7, it puts
case code BEFORE the table as often as after it (negative offsets) and it
indexes through an address register too.  A linear objdump decodes the table
as code (movep, bset, `mulsl` noise).  amix-packagemanager's scan060.py sizes a
table from the smallest POSITIVE offset, the gcc 2.7 layout; on GCC 14 output
it reads past the table into code, takes an instruction word for an offset,
and reports the rest of the table as movep and 64-bit mulsl: 15 such hits on
the first gcc14 grep, none of them code.  This tool sizes each table from its
bound check instead (N+1 entries, exactly what the hardware can index),
verifies every entry lands on an even address inside the same function and
outside the table, and refuses to give a verdict on any table it cannot size
(exit 3) -- an unsized table is the case where a real instruction could hide.
One shape has no bound to read: a constant index (`moveq #K', a switch whose
value GCC knew), which can only take entry K.  That table is sized from its
own entries, up to the nearest case, and named in a NOTE as a known limit.

Then, like scan060.py, it re-disassembles only the code BETWEEN tables, so the
stream re-synchronises after each one, and scans that listing by ENCODING:
MUL.L/DIV.L with extension bit 10 (the 64-bit forms), and the movep, cmp2,
chk2 and cas2 the 68060 also lacks.  Every function label must fall on an
instruction start in the final listing, or the verdict is "untrustworthy".

--explain HITFILE: read scan060.py's output and say, for every hit address it
lists, whether it lies inside a table sized here (data, not code).  Exit 1 if
any hit is unexplained.  This is how the gcc14 gate keeps scan060.py as an
independent decoder instead of dropping it.

MIT, amix-packages.
"""
import os
import re
import struct
import subprocess
import sys

LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{4} )+)\s*(\S+)\s*(.*)$")
LABEL = re.compile(r"^([0-9a-f]+) <([^>]+)>:\s*$")
# The index register can be any data or address register -- including %a6,
# which objdump names %fp and GCC 14 -O2 uses as a general register (patch
# 2.5.9's quotearg, 2026-10-27: an %fp-indexed table read as a movep).
DISPATCH = re.compile(r"^%pc@\(([0-9a-f]+)\b[^,)]*,%([da][0-7]|fp|sp):w\)$")
PC_INDEXED = re.compile(r"^%pc@\([0-9a-f]+\b[^,)]*,%[a-z0-9]+:[wl]\)$")
BOUND_CMP = re.compile(r"^#(-?\d+),(\S+)$")                # cmp[i]{b,w,l} #N,<ea>
MOVEQ = re.compile(r"^#(-?\d+),%(d[0-7])$")
CMPL_REG = re.compile(r"^%(d[0-7]),%(d[0-7])$")            # cmpl %dX,%dY
MNEM_OTHER = re.compile(r"^(movep|cmp2|chk2|cas2)")
LOOKBACK = 16


def die(msg, code=2):
    sys.stderr.write("scan060-g14: %s\n" % msg)
    sys.exit(code)


def exec_sections(data):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 2:
        die("not an ELF32 big-endian file")
    shoff = struct.unpack(">I", data[32:36])[0]
    shentsize, shnum = struct.unpack(">HH", data[46:50])
    out = []
    for i in range(shnum):
        sh = data[shoff + i * shentsize: shoff + (i + 1) * shentsize]
        _n, typ, flags, addr, off, size = struct.unpack(">IIIIII", sh[:24])
        if typ == 1 and flags & 0x4 and size:
            out.append((addr, off, size))
    return out


def objdump(tool, path, lo=None, hi=None):
    cmd = [tool, "-d"]
    if lo is not None:
        cmd += ["--start-address=0x%x" % lo, "--stop-address=0x%x" % hi]
    r = subprocess.run(cmd + [path], capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        die("objdump failed on %s: %s" % (path, r.stderr.strip()[:200]))
    return r.stdout


def parse(listing):
    """-> (insns [(addr, words, mnem, ops)], labels {addr: name})"""
    insns, labels = [], {}
    for raw in listing.splitlines():
        m = LABEL.match(raw)
        if m:
            labels[int(m.group(1), 16)] = m.group(2)
            continue
        m = LINE.match(raw)
        if m:
            insns.append((int(m.group(1), 16), m.group(2).split(), m.group(3), m.group(4).strip()))
    return insns, labels


def function_bounds(labels, secs):
    """sorted label addresses + section ends, for 'which function is this in'."""
    pts = sorted(set(labels) | {sa + sz for sa, _o, sz in secs} | {sa for sa, _o, _s in secs})
    return pts


def enclosing(pts, a):
    lo, hi = None, None
    for p in pts:
        if p <= a:
            lo = p
        elif hi is None:
            hi = p
            break
    return lo, hi


def word_at(data, secs, a):
    for sa, so, sz in secs:
        if sa <= a and a + 2 <= sa + sz:
            return struct.unpack(">h", data[so + a - sa: so + a - sa + 2])[0]
    return None


def moveq_value(insns, j, reg):
    """The constant in %reg at insns[j], if the last write to it before j is a
    moveq #N,%reg within a few instructions; else None.  A compare or test
    names the register without writing it (perl 5.8.9's Perl_pv_uni_display:
    `moveq #6,%d7 ; cmpl %d0,%d7 ; ... ; cmpl %d1,%d7 ; bcs')."""
    for k in range(j - 1, max(0, j - 6) - 1, -1):
        mn, ops = insns[k][2], insns[k][3]
        if mn.startswith(("cmp", "tst", "btst")):
            continue
        if ops.endswith("," + reg) or ops == reg:
            m = MOVEQ.match(ops) if mn == "moveq" else None
            return int(m.group(1)) if m and m.group(2) == reg[1:] else None
    return None


def bound_for(insns, idx):
    """Entry count (N+1) from the unsigned bound check before the dispatch at
    insns[idx].  The forms met in GCC 14 output and in the stock archive
    members it links (libgen's regcmp/advance):
        cmp[i]{b,w,l} #N,<ea>      ; bhi default     (ea > N)
        moveq #N,%dY ; cmpl <ea>,%dY ; bcs default   (N < ea)
        moveq #N,%dY ; cmpl %dY,<ea> ; bhi default   (ea > N)
    <ea> may be a memory operand, which objdump prints with its symbol
    (`cmpl 8003db14 <subcommand_option>,%d6': tar 1.14, 2026-10-27).
    The compare may be cmpa against an address register: the stock AT&T
    compiler's `moveq #8,%d1 ; cmpal %d1,%a0 ; bhiw' in libc.so's static
    getutx.o (_getutxid), linked by coreutils who/users/pinky, 2026-10-29.
    And a biased one, on the index before the bias is added (vim 9.1,
    2026-10-31):
        movel %dS,%dI ; addql #K,%dI ; moveq #-K,%dY ; cmpl %dS,%dY ; bhi default
    lets through only dS in [-K, -1], so dI = dS + K indexes K entries;
    accepted only when the dispatch's index register is that dI.
    """
    lo = max(0, idx - LOOKBACK)
    block = None
    for j in range(idx - 1, lo - 1, -1):
        _a, _w, mn, ops = insns[j]
        if mn.startswith(("rts", "jmp", "bra")):
            block = j + 1                           # left the dispatch block
            break
        if not re.match(r"^cmp[ai]?[bwl]$", mn) or j + 1 >= idx:
            continue
        br = insns[j + 1][2]
        m = BOUND_CMP.match(ops)
        if m and br.startswith("bhi"):
            n = int(m.group(1))
            if mn.endswith("b"):
                n &= 0xff
            elif mn.endswith("w"):
                n &= 0xffff
            return n + 1
        m = re.match(r"^(.+),%(d[0-7])$", ops)
        if m and br.startswith("bcs"):
            n = moveq_value(insns, j, "%" + m.group(2))
            if n is not None:
                return n + 1
        m = re.match(r"^%(d[0-7]),(\S+)$", ops)
        if m and br.startswith("bhi"):
            n = moveq_value(insns, j, "%" + m.group(1))
            if n is not None and n >= 0:
                return n + 1
        m = re.match(r"^%(d[0-7]),%(d[0-7])$", ops)
        if m and br.startswith("bhi"):
            n = moveq_value(insns, j, "%" + m.group(2))
            if n is not None and n < 0 and biased_index(insns, j, idx, m.group(1), -n):
                return -n
    # no compare bounds it: a mask in the block, else the ways into the block
    for j in range(idx - 1, (block if block is not None else lo) - 1, -1):
        n = mask_bound(insns, j)
        if n is not None:
            return n
    if block is not None:
        return entry_bound(insns, block, idx)
    return None


def index_register(insns, idx):
    """The data register the dispatch at insns[idx] indexes its table with:
    the `movew %pc@(T,%dI:l),...' just before it."""
    if idx < 1 or insns[idx - 1][2] != "movew":
        return None
    m = re.match(r"^%pc@\([0-9a-f]+\b[^,)]*,%(d[0-7]):l\)", insns[idx - 1][3])
    return m.group(1) if m else None


def biased_index(insns, j, idx, src, k):
    """Whether the dispatch at insns[idx] indexes with %src + K: an
    `addql #K,%dI' (or `addl #K') into its index register %dI before the
    compare at insns[j], %dI copied from %src just before that unless it is
    %src, and nothing else writing %dI up to the dispatch but its doubling."""
    reg = index_register(insns, idx)
    if reg is None:
        return False
    add = "#%d,%%%s" % (k, reg)
    for p in range(idx - 2, max(0, j - LOOKBACK) - 1, -1):
        mn, ops = insns[p][2], insns[p][3]
        if p < j and mn in ("addql", "addl") and ops == add:
            if reg == src:
                return True
            for q in range(p - 1, max(0, p - 6) - 1, -1):
                if insns[q][2] == "movel" and insns[q][3] == "%%%s,%%%s" % (src, reg):
                    return True
                if insns[q][3].endswith(",%" + reg):
                    return False
            return False
        if ops.endswith(",%" + reg) and not mn.startswith(("cmp", "tst")) \
                and not (p == idx - 2 and mn == "addl" and ops == "%%%s,%%%s" % (reg, reg)):
            return False
    return False


def constant_index(insns, idx):
    """K when the dispatch at insns[idx] can only take entry K: `moveq #K,%dI ;
    addl %dI,%dI ; movew %pc@(T,%dI:l),... ; jmp' (a switch whose value GCC
    knew, vim 9.1, 2026-10-31), else None."""
    reg = index_register(insns, idx)
    if reg is None or idx < 2 or insns[idx - 2][2] != "addl" \
            or insns[idx - 2][3] != "%%%s,%%%s" % (reg, reg):
        return None
    return moveq_value(insns, idx - 2, "%" + reg)


def entries_bound(data, secs, t, fstart, fend):
    """Entry count of a table at t sized from its own words: the longest run
    of entries landing on an even address of the function past the table,
    ending where the nearest case begins.  A known limit: a code word just
    after the table that also reads as such an entry is taken for one."""
    n, lowest = 0, None
    while n < 4096:
        if lowest is not None and t + 2 * n >= lowest:
            break
        w = word_at(data, secs, t + 2 * n)
        if w is None:
            break
        tgt = t + w
        if tgt & 1 or not (fstart <= tgt < fend) or tgt <= t + 2 * n:
            break
        lowest = tgt if lowest is None else min(lowest, tgt)
        n += 1
    return n


def mask_bound(insns, j):
    """Entry count M+1 when insns[j] masks a data register with M = 2^k - 1:
    `andi{b,w,l} #M,%dX', or `andl %dA,%dB' after a moveq #M into either --
    switch (x & 7), e.g. Duff's device (perl 5.8.9's sdbm, Perl_ck_fun)."""
    mn, ops = insns[j][2], insns[j][3]
    if not re.match(r"^andi?[bwl]$", mn):
        return None
    m = re.match(r"^#(\d+),%d[0-7]$", ops)
    if m:
        n = int(m.group(1))
    else:
        m = re.match(r"^%(d[0-7]),%(d[0-7])$", ops)
        if not m:
            return None
        n = moveq_value(insns, j, "%" + m.group(1))
        if n is None:
            n = moveq_value(insns, j, "%" + m.group(2))
    if n is None or n < 0 or (n + 1) & n:
        return None
    return n + 1


def entry_bound(insns, start, idx):
    """Entry count for a dispatch block at insns[start] that is entered only by
    branches: each must be a bounded conditional one --
        cmp[i]{b,w,l} #N,<ea> ; bls block       (ea <= N)
        moveq #N,%dY ; cmpl <ea>,%dY ; bcc block (N >= ea)
        moveq #N,%dY ; cmpl %dY,<ea> ; bls block (ea <= N)
    (perl 5.8.9's Perl_ref: `cmpiw #15,%d1 ; blsw' far above the block)."""
    if start >= idx:
        return None
    target = "%x" % insns[start][0]
    found = set()
    for k, (_a, _w, mn, ops) in enumerate(insns):
        if not re.match(r"^b(ra|sr|hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)[bswl]?$", mn):
            continue
        if ops.split(" ")[0] != target:
            continue
        if k == 0 or not mn.startswith(("bls", "bcc")):
            return None                             # an unbounded way in
        pmn, pops = insns[k - 1][2], insns[k - 1][3]
        if not re.match(r"^cmp[ai]?[bwl]$", pmn):
            return None
        n = None
        m = BOUND_CMP.match(pops)
        if m and mn.startswith("bls"):
            n = int(m.group(1))
            if pmn.endswith("b"):
                n &= 0xff
            elif pmn.endswith("w"):
                n &= 0xffff
        m = re.match(r"^(.+),%(d[0-7])$", pops)
        if n is None and m and mn.startswith("bcc"):
            n = moveq_value(insns, k - 1, "%" + m.group(2))
        m = re.match(r"^%(d[0-7]),(\S+)$", pops)
        if n is None and m and mn.startswith("bls"):
            n = moveq_value(insns, k - 1, "%" + m.group(1))
        if n is None:
            return None
        found.add(n + 1)
    return found.pop() if len(found) == 1 else None


def find_tables(insns, labels, data, secs, pts):
    """-> ({(start, end)}, [problems], [notes])"""
    tables, problems, notes = set(), [], []
    for idx, (a, words, mn, ops) in enumerate(insns):
        if mn != "jmp" or not words or words[0] != "4efb":
            continue
        m = DISPATCH.match(ops)
        if not m:
            if PC_INDEXED.match(ops):                # a dispatch this tool cannot read
                problems.append("dispatch at 0x%08x: unrecognised indexed jmp '%s'" % (a, ops))
            continue                                 # PLT stubs: %pc@(...)@(0)
        t = int(m.group(1), 16)
        if not (a < t <= a + 64):
            problems.append("dispatch at 0x%08x: table 0x%08x not just after it" % (a, t))
            continue
        n = bound_for(insns, idx)
        k = constant_index(insns, idx) if n is None else None
        if k is not None and k >= 0:
            fstart, fend = enclosing(pts, a)
            n = entries_bound(data, secs, t, fstart, fend)
            if n <= k:
                problems.append("dispatch at 0x%08x: constant index #%d, but its table at 0x%08x "
                                "has only %d entr%s landing on code" % (a, k, t, n, "y" if n == 1 else "ies"))
                continue
            notes.append("dispatch at 0x%08x: constant index #%d; table at 0x%08x sized from its own "
                         "entries (%d), a known limit" % (a, k, t, n))
        if n is None or n <= 0 or n > 4096:
            problems.append("dispatch at 0x%08x: no bound check found, table at 0x%08x unsized" % (a, t))
            continue
        end = t + 2 * n
        fstart, fend = enclosing(pts, a)
        bad = []
        for k in range(n):
            w = word_at(data, secs, t + 2 * k)
            tgt = t + (w if w is not None else 0)
            if w is None or tgt & 1 or not (fstart <= tgt < fend) or t <= tgt < end:
                bad.append(k)
        if bad:
            problems.append("dispatch at 0x%08x: table 0x%08x x%d has %d entr%s not landing on code "
                            "in the function (first: #%d)" % (a, t, n, len(bad),
                                                               "y" if len(bad) == 1 else "ies", bad[0]))
            continue
        tables.add((a + 4, end))                      # dispatch tail + table
    return tables, problems, notes


def dispatch_of(problem):
    """The dispatch address a find_tables problem names, else None."""
    m = re.match(r"^dispatch at 0x([0-9a-f]+):", problem)
    return int(m.group(1), 16) if m else None


def resync_listing(tool, path, secs, skip):
    out = ""
    for sa, _so, sz in secs:
        lo, hi = sa, sa + sz
        for s, e in sorted(r for r in skip if sa <= r[0] < hi):
            if s > lo:
                out += objdump(tool, path, lo, s)
            lo = max(lo, e)
        if lo < hi:
            out += objdump(tool, path, lo, hi)
    return out


def scan(tool, path):
    data = open(path, "rb").read()
    secs = exec_sections(data)
    listing = objdump(tool, path)
    if "Disassembly of section" not in listing:
        die("%s: objdump produced no disassembly" % path)
    insns, labels = parse(listing)
    pts = function_bounds(labels, secs)
    skip, problems, notes = find_tables(insns, labels, data, secs, pts)
    for _round in range(6):
        if not skip:
            break
        listing = resync_listing(tool, path, secs, skip)
        insns, _l = parse(listing)
        new, more, more_notes = find_tables(insns, labels, data, secs, pts)
        problems = sorted(set(problems) | set(more))
        notes = sorted(set(notes) | set(more_notes))
        if not (new - skip):
            break
        skip |= new
    # A problem an earlier round met at a dispatch that a later, re-synced
    # round sized is stale: the first table's data had swallowed the next
    # dispatch's bound check (diffutils 2.8.1 groups_letter_value, two
    # back-to-back switches, 2026-10-29).
    sized = {s - 4 for s, _e in skip}
    problems = [p for p in problems if dispatch_of(p) not in sized]
    # sync: every label inside a code region (not a table) must start an insn
    starts = {i[0] for i in insns}
    desync = []
    for la, name in sorted(labels.items()):
        if not any(sa <= la < sa + sz for sa, _o, sz in secs):
            continue
        if any(s <= la < e for s, e in skip):
            continue
        if la not in starts:
            desync.append("%s at 0x%08x" % (name, la))
    hits, total_long = [], 0
    for a, words, mn, ops in insns:
        op = int(words[0], 16)
        if (op & 0xff80) == 0x4c00 and len(words) >= 2:
            total_long += 1
            if int(words[1], 16) & 0x0400:
                hits.append("0x%08x %s %s -- 64-bit %s" % (a, mn, ops, "divide" if op & 0x40 else "product"))
        elif MNEM_OTHER.match(mn):
            hits.append("0x%08x %s %s -- not implemented on the 68060" % (a, mn, ops))
    sized = {s for s, _e in skip}
    notes = [n for n in notes if int(re.match(r"^dispatch at 0x([0-9a-f]+)", n).group(1), 16) + 4 in sized]
    return dict(insns=len(insns), tables=sorted(skip), problems=problems,
                desync=desync, hits=hits, total_long=total_long, notes=notes)


def explain(tables, hitfile):
    """-> (all hit addresses, in-table, odd, unexplained).  A hit is data if
    it lies inside a sized table; it is a decode artifact if its address is
    odd (every 680x0 instruction starts on an even address, so a decode
    starting at an odd one is out of sync by construction)."""
    addrs = []
    for raw in open(hitfile, errors="replace"):
        m = re.match(r"^\s+([0-9a-f]{8})\s+<", raw)
        if m:
            addrs.append(int(m.group(1), 16))
    intab = [a for a in addrs if any(s <= a < e for s, e in tables)]
    odd = [a for a in addrs if a & 1 and a not in intab]
    unexplained = [a for a in addrs if a not in intab and a not in odd]
    return addrs, intab, odd, unexplained


def main(argv):
    tool = os.environ.get("OBJDUMP") or "m68k-elf-objdump"
    hitfile = None
    args = argv[1:]
    while args and args[0].startswith("--"):
        if args[0] == "--objdump" and len(args) > 1:
            tool, args = args[1], args[2:]
        elif args[0] == "--explain" and len(args) > 1:
            hitfile, args = args[1], args[2:]
        else:
            die("usage: scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...")
    if not args:
        die("usage: scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...")
    rc = 0
    for path in args:
        r = scan(tool, path)
        name = os.path.basename(path)
        if hitfile is not None:
            if r["problems"] or r["desync"]:
                print("  UNTRUSTWORTHY %s: cannot explain scan060.py hits -- %s"
                      % (name, "; ".join(r["problems"] + r["desync"])[:300]))
                rc = max(rc, 3)
                continue
            addrs, intab, odd, unexplained = explain(r["tables"], hitfile)
            if unexplained:
                print("  UNEXPLAINED %s: %d of %d scan060.py hit(s) at an even address outside every sized table: %s"
                      % (name, len(unexplained), len(addrs), " ".join("%08x" % a for a in unexplained)))
                rc = max(rc, 1)
            else:
                print("  explained %s: %d scan060.py hit(s) -- %d inside the %d sized switch tables (data), "
                      "%d at odd addresses (decode out of sync)" % (name, len(addrs), len(intab), len(r["tables"]), len(odd)))
            continue
        if r["problems"] or r["desync"]:
            print("  UNTRUSTWORTHY %s:" % name)
            for p in r["problems"] + ["decoder off-boundary at label " + d for d in r["desync"][:8]]:
                print("    " + p)
            rc = max(rc, 3)
            continue
        if r["hits"]:
            print("  HITS %d %s (%d insns, %d switch tables sized):" % (len(r["hits"]), name, r["insns"], len(r["tables"])))
            for h in r["hits"]:
                print("    " + h)
            rc = max(rc, 1)
            continue
        print("  CLEAN %s (%d insns, %d switch tables sized, %d long mul/div, none 64-bit; no movep/cmp2/chk2/cas2)"
              % (name, r["insns"], len(r["tables"]), r["total_long"]))
        for n in r["notes"]:
            print("    NOTE " + n)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
