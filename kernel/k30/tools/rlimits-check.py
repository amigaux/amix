#!/usr/bin/env python3
"""rlimits-check.py -- a k30 kernel's default process limits against the texts that describe them.

usage: rlimits-check.py UNIX [TEXT...]
       rlimits-check.py --selftest

UNIX is the linked kernel (ELF ET_REL, as build-cross-kernel.sh leaves it and the package
ships it beside the brel).  The tool reads its `rlimits` table, {soft, hard} for cpu, fsize,
data, stack, core, nofile and vmem, and prints it with the soft data and vmem limits' value:
"16 MiB" (0x1000000 both, the stock master.d/kernel.h) or "unlimited" (0x7fffffff both,
build-cross-kernel.sh --proc-limits).  Any other pair is an error.

Each TEXT must say which, in the words

    soft data and vmem limits 16 MiB          (or "... limits are 16 MiB", "16 MB")
    soft data and vmem limits unlimited       (or "... limits are unlimited")

(case, line breaks and leading `#` comment marks ignored), and must not say the other.  A
text that says neither is an error too: the point is that it tells the reader.

Exit 0 when the table is one of the two and every text agrees, 1 otherwise, 2 for usage.
MIT licence, see LICENSE in kernel/k30.
"""
import re
import struct
import sys

NAMES = ('cpu', 'fsize', 'data', 'stack', 'core', 'nofile', 'vmem')
STOCK, RAISED = 0x1000000, 0x7fffffff
SAYS = {
    '16 MiB': re.compile(r'soft data and vmem limits (?:are )?16 ?mi?b\b'),
    'unlimited': re.compile(r'soft data and vmem limits (?:are )?unlimited\b'),
}


def rlimits(b):
    """The 14 longwords of the one `rlimits` object in an ELF32 MSB file's symbol table."""
    if b[:6] != b'\x7fELF\x01\x02':
        raise ValueError('not an ELF32 MSB file')
    shoff, = struct.unpack_from('>I', b, 32)
    se, sn = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * se) for i in range(sn)]
    hit = []
    for st in (s for s in sh if s[1] == 2):
        so = sh[st[6]][4]
        for i in range(st[5] // 16):
            n, v, _sz, _info, _o, x = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
            if b[so + n:b.index(0, so + n)] == b'rlimits' and 0 < x < sn and sh[x][1] == 1:
                hit.append(struct.unpack_from('>14I', b, sh[x][4] + v))
    if len(hit) != 1:
        raise ValueError('%d rlimits objects with data, want 1' % len(hit))
    return hit[0]


def verdict(t):
    """'16 MiB' or 'unlimited' for the soft data and vmem limits; ValueError for anything else."""
    data, vmem = t[4], t[12]
    if data == vmem == STOCK:
        return '16 MiB'
    if data == vmem == RAISED:
        return 'unlimited'
    raise ValueError('soft data 0x%x and vmem 0x%x are neither both 0x%x nor both 0x%x'
                     % (data, vmem, STOCK, RAISED))


def says(text):
    """The set of values a text states for the soft data and vmem limits."""
    flat = ' '.join(re.sub(r'^\s*#+\s?', '', ln) for ln in text.splitlines())
    flat = re.sub(r'\s+', ' ', flat).lower()
    return {k for k, rx in SAYS.items() if rx.search(flat)}


def check(unix_bytes, texts):
    """[(ok, line)] for the table and each (name, text)."""
    t = rlimits(unix_bytes)
    v = verdict(t)
    out = [(True, 'rlimits ' + ' '.join('%s %x/%x' % (n, t[2 * i], t[2 * i + 1])
                                         for i, n in enumerate(NAMES))
            + ' -- soft data and vmem limits ' + v)]
    for name, text in texts:
        s = says(text)
        if s == {v}:
            out.append((True, '%s: says %s' % (name, v)))
        elif not s:
            out.append((False, '%s: does not say the soft data and vmem limits (want "%s")' % (name, v)))
        else:
            out.append((False, '%s: says %s, the kernel has %s' % (name, ' and '.join(sorted(s)), v)))
    return out


def _elf(words):
    """A minimal ELF32 MSB ET_REL: .data holding `words` at offset 8, a symtab naming it rlimits."""
    data = b'\0' * 8 + struct.pack('>14I', *words)
    strtab = b'\0rlimits\0'
    shstr = b'\0.data\0.symtab\0.strtab\0.shstrtab\0'
    sym = b'\0' * 16 + struct.pack('>IIIBBH', 1, 8, 56, 0x11, 0, 1)
    body = data + strtab + shstr + sym
    o_data, o_str, o_shs, o_sym = 52, 52 + len(data), 52 + len(data) + len(strtab), \
        52 + len(data) + len(strtab) + len(shstr)
    shoff = 52 + len(body)
    hdr = b'\x7fELF\x01\x02\x01' + b'\0' * 9 + struct.pack('>HHIIIIIHHHHHH', 1, 4, 1, 0, 0, shoff,
                                                             0, 52, 0, 0, 40, 5, 4)
    sh = [(0,) * 10,
          (1, 1, 3, 0, o_data, len(data), 0, 0, 4, 0),
          (7, 2, 0, 0, o_sym, len(sym), 3, 1, 4, 16),
          (15, 3, 0, 0, o_str, len(strtab), 0, 0, 1, 0),
          (23, 3, 0, 0, o_shs, len(shstr), 0, 0, 1, 0)]
    return hdr + body + b''.join(struct.pack('>10I', *s) for s in sh)


def selftest():
    raised = (RAISED, RAISED, 0x10000000, RAISED, RAISED, RAISED, STOCK, RAISED,
              0x100000, RAISED, 0x40, 0x400, RAISED, RAISED)
    stock = raised[:4] + (STOCK,) + raised[5:12] + (STOCK, RAISED)
    mixed = raised[:4] + (STOCK,) + raised[5:]
    n = 0

    def ok(cond, what):
        nonlocal n
        n += 1
        if not cond:
            sys.exit('selftest FAILED: ' + what)

    ok(rlimits(_elf(raised)) == raised, 'table read back')
    ok(verdict(raised) == 'unlimited' and verdict(stock) == '16 MiB', 'verdicts')
    try:
        verdict(mixed)
        ok(False, 'mixed table accepted')
    except ValueError:
        ok(True, '')
    ok(says('DESC=x, the soft data and vmem limits unlimited, y') == {'unlimited'}, 'raised phrase')
    ok(says('# the soft data and vmem\n# limits are 16 MiB (stock)') == {'16 MiB'}, 'wrapped comment')
    ok(says('Soft data and vmem limits 16 MB') == {'16 MiB'}, 'MB spelling')
    ok(says('a process may use 16 MiB of data') == set(), 'other wording is not a statement')
    r = check(_elf(stock), [('a', 'soft data and vmem limits 16 MiB'), ('b', 'nothing'),
                            ('c', 'soft data and vmem limits unlimited')])
    ok([x[0] for x in r] == [True, True, False, False], 'check verdicts %r' % (r,))
    r = check(_elf(raised), [('d', 'soft data and vmem limits unlimited; once soft data and vmem limits 16 MiB')])
    ok(not r[1][0], 'a text saying both fails')
    try:
        rlimits(b'\x7fELF\x01\x01' + b'\0' * 64)
        ok(False, 'LSB accepted')
    except ValueError:
        ok(True, '')
    print('rlimits-check selftest: %d checks passed' % n)


def main(argv):
    if argv[1:] == ['--selftest']:
        selftest()
        return 0
    if len(argv) < 2 or argv[1].startswith('-'):
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    texts = []
    for p in argv[2:]:
        with open(p, encoding='utf-8', errors='replace') as f:
            texts.append((p, f.read()))
    with open(argv[1], 'rb') as f:
        b = f.read()
    try:
        res = check(b, texts)
    except ValueError as e:
        print('rlimits-check: %s: %s' % (argv[1], e), file=sys.stderr)
        return 1
    for good, line in res:
        print(('  ' if good else 'FAIL ') + line)
    return 0 if all(g for g, _ in res) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
