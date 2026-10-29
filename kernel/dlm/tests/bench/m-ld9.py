#!/usr/bin/env python3
# m-ld9.py -- M-LD9 bench half (docs/plan/stage-1.md S1-25): compare a row
# that booted a static kernel through our loader with the row that booted
# the same kernel and root through the stock loader.  Read only: it reads
# two rig evidence directories (amix-kerntools/docs/rig-slots.md).
#
# usage: m-ld9.py OURS STOCK
#   OURS   evidence dir of the loader row (03-batch.txt, 06-serial.log,
#          07-stages.tsv, result.tsv)
#   STOCK  evidence dir of the stock-loader row (03-batch.txt, result.tsv)
#
# Checks, one line each, then SAME or DIFFERENT:
#   result      both rows passed
#   stages      every loader stage passed (07-stages.tsv)
#   <command>   each batch command both rows ran gives the same output, with
#               the parts that change from boot to boot removed (mount
#               dates; df free counts; the uname build tag of the kernel is
#               kept: it names the kernel, so it must match)
#   rth1-root   the RTH1 unit the loader reported is the controller number
#               of the root device (cNdMsK) both rows mounted
# A command only one row ran is listed, not judged.
# Exit status 0 for SAME, 1 for DIFFERENT, 2 for missing evidence.
import os
import re
import sys


def read(d, name):
    p = os.path.join(d, name)
    if not os.path.exists(p):
        return None
    with open(p, 'rb') as f:
        return f.read().decode('latin-1').replace('\r', '')


def batch(d):
    """{command: [output lines]} from 03-batch.txt"""
    text = read(d, '03-batch.txt')
    if text is None:
        return None
    out, cmd = {}, None
    for line in text.split('\n'):
        m = re.match(r'^=+ (.*?) =+$', line)
        if m:
            cmd = m.group(1)
            out[cmd] = []
            continue
        if cmd is None:
            continue
        s = re.sub(r'^# ?', '', line).strip()
        if not s or s.startswith(cmd) or re.match(r'^DONE_\d+$', s) or s.startswith('amixrun:'):
            continue
        out[cmd].append(s)
    return out


def normal(cmd, lines):
    if cmd.startswith('mount'):
        return [re.sub(r' on \w{3} \w{3} +\d+ [\d:]+ \d{4}$', '', l) for l in lines]
    if cmd.startswith('df'):
        return [' '.join(l.split()[:2]) for l in lines]
    return lines


def result(d):
    text = read(d, 'result.tsv')
    if not text:
        return None
    f = text.split('\n')[0].split('\t')
    return f[2] if len(f) > 2 else None


def main():
    if len(sys.argv) != 3:
        print('usage: m-ld9.py OURS STOCK')
        return 2
    ours, stock = sys.argv[1], sys.argv[2]
    bo, bs = batch(ours), batch(stock)
    if bo is None or bs is None:
        print('m-ld9: 03-batch.txt missing in', ours if bo is None else stock)
        return 2
    rows, same = [], True

    def check(name, ok, detail):
        nonlocal same
        same &= ok
        rows.append('%-12s %-4s %s' % (name, 'ok' if ok else 'DIFF', detail))

    ro, rs = result(ours), result(stock)
    check('result', ro == 'PASS' and rs == 'PASS', 'ours %s, stock %s' % (ro, rs))
    stages = read(ours, '07-stages.tsv') or ''
    bad = [l.split('\t')[0] for l in stages.split('\n') if l and l.split('\t')[1:2] != ['pass']]
    check('stages', bool(stages) and not bad, 'all pass' if stages and not bad else
          'missing' if not stages else 'failed: ' + ' '.join(bad))
    for cmd in sorted(set(bo) | set(bs)):
        if cmd.startswith('stty') or 'RIGSER' in cmd:
            continue            # the rig's own serial check, not the system's
        if cmd not in bo or cmd not in bs:
            rows.append('%-12s %-4s only in %s' % (cmd.split()[0], '-', 'ours' if cmd in bo else 'stock'))
            continue
        a, b = normal(cmd, bo[cmd]), normal(cmd, bs[cmd])
        check(cmd.split()[0], a == b, (a[0] if a else '(no output)') if a == b else
              'ours %r, stock %r' % (a, b))
    serial = read(ours, '06-serial.log') or ''
    m = re.search(r'amix-boot: RTH1 flags (\w+) unit (\d+)', serial)
    root = [l for l in normal('mount', bo.get('mount', [])) if l.startswith('/ on ')]
    rm = re.search(r'/dev/dsk/c(\d+)d\d+s\d+', root[0]) if root else None
    if m and rm:
        check('rth1-root', m.group(2) == rm.group(1),
              'RTH1 unit %s, root c%sd…' % (m.group(2), rm.group(1)))
    else:
        check('rth1-root', False, 'no RTH1 line' if not m else 'no root device in mount')
    print('\n'.join(rows))
    print('m-ld9: %s' % ('SAME' if same else 'DIFFERENT'))
    return 0 if same else 1


sys.exit(main())
