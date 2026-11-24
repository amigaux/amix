# probeans.py -- the answers file of ksh93's feature probes (README.md, dtksh): read,
# write and compare it.  A text file, for review:
#
#   # comment lines: what the file is, the toolchain it was recorded with
#   === probe KEY NAME
#   | the probe's source as written (each line after "| ")
#   --- run ["arg", ...]
#   status N
#   stdout
#   | each line of what the probe wrote, after "| "
#   stderr
#   | ...
#
# A probe is its key (pcc.py: the preprocessed source, the -l words, the objects);
# each run of it is its arguments and its answer.  In text after "| ", a backslash
# is written "\\" and a byte that is not printable ASCII or a tab "\xNN"; output
# that does not end in a newline ends with the line "\ no newline".
# MIT licence, see LICENSE in userland/packages.
import json, re

NONL = '\\ no newline'


def esc(b):
    o = []
    for c in b:
        if c == 0x5c:
            o.append('\\\\')
        elif c == 9 or 0x20 <= c < 0x7f:
            o.append(chr(c))
        else:
            o.append('\\x%02x' % c)
    return ''.join(o)


def unesc(s):
    return re.sub(rb'\\(\\|x[0-9a-f]{2})',
                  lambda m: b'\\' if m.group(1) == b'\\' else bytes([int(m.group(1)[1:], 16)]),
                  s.encode('latin-1'))


def lines(b):
    """bytes as '| ' lines"""
    if not b:
        return []
    parts = b.split(b'\n')
    tail = parts.pop()
    out = ['| ' + esc(p) for p in parts]
    if tail:
        out += ['| ' + esc(tail), NONL]
    return out


class Answers:
    def __init__(self):
        self.head = []          # comment lines
        self.probes = {}        # key -> {'name', 'src' (bytes), 'runs': {args tuple: (status, out, err)}}
        self.order = []         # keys, in the file's order

    def add(self, key, name, src, args, status, out, err):
        p = self.probes.get(key)
        if p is None:
            p = self.probes[key] = {'name': name, 'src': src, 'runs': {}}
            self.order.append(key)
        p['runs'][tuple(args)] = (status, out, err)

    def get(self, key, args):
        p = self.probes.get(key)
        return p and p['runs'].get(tuple(args))

    def dump(self):
        o = list(self.head)
        for k in self.order:
            p = self.probes[k]
            o += ['', '=== probe %s %s' % (k, p['name'])] + lines(p['src'])
            for a, (st, out, err) in p['runs'].items():
                o += ['--- run ' + json.dumps(list(a)), 'status %d' % st, 'stdout'] + lines(out) + ['stderr'] + lines(err)
        return '\n'.join(o) + '\n'


def load(path):
    a = Answers()
    try:
        f = open(path, encoding='latin-1')
    except FileNotFoundError:
        return a
    key = None
    buf = None          # the list '| ' lines go to
    cur = {}

    def flush():
        if key is not None and 'args' in cur:
            a.add(key, name, src, cur['args'], cur['status'], join(cur['stdout']), join(cur['stderr']))

    def join(ls):
        if not ls:
            return b''
        if ls[-1] is None:
            return b'\n'.join(ls[:-1])
        return b'\n'.join(ls) + b'\n'

    with f:
        for n, ln in enumerate(f, 1):
            ln = ln.rstrip('\n')
            if ln.startswith('| '):
                if buf is None:
                    raise ValueError('%s:%d: text outside a block' % (path, n))
                buf.append(unesc(ln[2:]))
            elif ln == NONL:
                buf.append(None)
            elif ln.startswith('=== probe '):
                flush()
                cur = {}
                _, _, key, name = ln.split(' ', 3)
                srcl = buf = []
                src = None
            elif ln.startswith('--- run '):
                if src is None:
                    src = join(srcl)
                flush()
                cur = {'args': json.loads(ln[8:])}
                buf = None
            elif ln.startswith('status '):
                cur['status'] = int(ln[7:])
            elif ln in ('stdout', 'stderr'):
                buf = cur[ln] = []
            elif ln.startswith('#') and key is None:
                a.head.append(ln)
            elif ln == '':
                continue
            else:
                raise ValueError('%s:%d: %r' % (path, n, ln))
        flush()
    return a


def diff(a, b):
    """the runs whose answers differ, or that only one file has"""
    o = []
    for k in a.order + [k for k in b.order if k not in a.probes]:
        pa, pb = a.probes.get(k), b.probes.get(k)
        runs = list((pa or {'runs': {}})['runs']) + [r for r in (pb or {'runs': {}})['runs'] if not pa or r not in pa['runs']]
        for r in runs:
            ra, rb = a.get(k, list(r)), b.get(k, list(r))
            if ra != rb:
                name = (pa or pb)['name']
                o.append('%s %s %s: %s' % (k[:16], name, json.dumps(list(r)),
                         'only in the second' if ra is None else 'only in the first' if rb is None else
                         'status %d/%d, stdout %d/%d bytes, stderr %d/%d bytes' % (ra[0], rb[0], len(ra[1]), len(rb[1]), len(ra[2]), len(rb[2]))))
    return o


if __name__ == '__main__':
    import sys
    if len(sys.argv) == 4 and sys.argv[1] == 'diff':
        d = diff(load(sys.argv[2]), load(sys.argv[3]))
        print('\n'.join(d) if d else 'probeans: the same answers')
        sys.exit(1 if d else 0)
    sys.exit('usage: probeans.py diff ANSWERS ANSWERS')
