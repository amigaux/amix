#!/usr/bin/env python3
# collect.py OUT_TAR SRC_DIR DEST: the record of a generation run on Amix (run.sh's
# out.tar) as replay.sh reads it.  SRC_DIR holds the directories as pushed (ab, tt);
# DEST gets <set>/<n>-<module>/{args, before.sha256, created, removed, after/, diffs/}.
# before.sha256: the run's .bip and .bil and the earlier contents of the files it rewrote;
# after/: the files it created; diffs/: unified diffs of the ones it rewrote with other
# contents (a file rewritten as it was needs none).  dtcodegen's own log, .dtcodegen.log
# (times of day; only dtcodegen reads it), is left out.
# MIT licence, see LICENSE in userland/packages.
import hashlib, os, subprocess, sys, tarfile, tempfile
tar, src, dest = sys.argv[1:4]
t = tarfile.open(tar)
mem = {m.name: m for m in t.getmembers() if m.isfile()}
def data(n):
    return t.extractfile(mem[n]).read()
def sha(b):
    return hashlib.sha256(b).hexdigest()
def rel(n, pre):
    n = n[len(pre):]
    while n.startswith('./'):
        n = n[2:]
    return n
for st in ('ab', 'tt'):
    runs = sorted({n.split('/')[2] for n in mem if n.startswith('out/%s/' % st) and n.count('/') >= 3},
                  key=lambda r: int(r.split('-')[0]))
    for r in runs:
        p = 'out/%s/%s/' % (st, r)
        rc = data(p + 'rc').decode().strip()
        if rc != '0':
            sys.exit('collect: %s %s: dtcodegen rc %s' % (st, r, rc))
        args = data(p + 'args').decode().strip()
        o = os.path.join(dest, st, r)
        os.makedirs(o)
        open(os.path.join(o, 'args'), 'w').write(args + '\n')
        LOG = '.dtcodegen.log'
        lines = []
        for w in args.split():
            if w.endswith(('.bip', '.bil')):
                lines.append('%s  ./%s' % (sha(open(os.path.join(src, st, w), 'rb').read()), w))
        before = {rel(n, p + 'before/'): data(n) for n in mem if n.startswith(p + 'before/')}
        after = {rel(n, p + 'after/'): data(n) for n in mem if n.startswith(p + 'after/')}
        for f in sorted(before):
            if f != LOG:
                lines.append('%s  ./%s' % (sha(before[f]), f))
        open(os.path.join(o, 'before.sha256'), 'w').write(''.join(l + '\n' for l in lines))
        for f in ('created', 'removed'):
            names = [l for l in data(p + f).decode().split('\n') if l and l != './' + LOG]
            open(os.path.join(o, f), 'w').write(''.join(l + '\n' for l in names))
        for f in sorted(after):
            if f == LOG or (f in before and before[f] == after[f]):
                continue
            if f in before:
                with tempfile.TemporaryDirectory() as td:
                    for side, b in (('a', before[f]), ('b', after[f])):
                        os.makedirs(os.path.join(td, side, os.path.dirname(f)), exist_ok=True)
                        open(os.path.join(td, side, f), 'wb').write(b)
                    d = subprocess.run(['diff', '-u', '--label', 'a/' + f, '--label', 'b/' + f,
                                        os.path.join(td, 'a', f), os.path.join(td, 'b', f)],
                                       capture_output=True).stdout
                q = os.path.join(o, 'diffs', f + '.diff')
                os.makedirs(os.path.dirname(q), exist_ok=True)
                open(q, 'wb').write(d)
            else:
                q = os.path.join(o, 'after', f)
                os.makedirs(os.path.dirname(q), exist_ok=True)
                open(q, 'wb').write(after[f])
        print('%s %s: %s' % (st, r, args))
