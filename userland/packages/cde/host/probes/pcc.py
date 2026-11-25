#!/usr/bin/env python3
# pcc.py -- the link half of pcc.  A feature probe (iffe's and conf.sh's test
# programs, every one named *.exe) is linked for the target as OUT.m68k, and OUT
# becomes a stub that runs it through prun.py under the probe's key; any other
# link (ksh, shcomp, ...) is the real one.  The generators the build runs on the
# build machine (PCC_HOSTPROGS: lcgen) are compiled for it with PCC_HOSTCC.
#
# The key is the probe's question, not its bytes: the sha256 of each C source
# preprocessed with the link's own flags (-E -P: no line markers, no paths; every
# -D, -U, -I and every header it includes, the generated FEATURE headers among
# them), then the libraries in order (-l words, and an archive or shared library
# given by its path, by its name), then each object given: the source beside
# it, preprocessed the same way, or else its bytes.  A
# changed header gives a new key, which has no answer until it is recorded.
# prun.py adds the run's arguments.
#
# Not a probe: package's check that CC is a cross compiler (pkgNNN.exe), which
# must see a program the build machine cannot run.
# MIT licence, see LICENSE in userland/packages.
import hashlib, os, re, shlex, subprocess, sys

real = shlex.split(os.environ['PCC_REAL'])
here = os.environ['PCC_DIR']
store = os.environ['PCC_STORE']
args = sys.argv[1:]

out = 'a.out'
i = 0
srcs, objs, libs, keep = [], [], [], []
while i < len(args):
    a = args[i]
    if a == '-o':
        out = args[i + 1]; i += 2; continue
    if a.startswith('-o') and len(a) > 2:
        out = a[2:]; i += 1; continue
    if a.startswith('-l'):
        libs.append(a)
    elif a.startswith(('-L', '-Wl,')) or a in ('-shared', '-static', '-s', '-rdynamic'):
        pass
    elif a.endswith(('.c', '.i')):
        srcs.append(a)
    elif a.endswith(('.o', '.a', '.so')) and not a.startswith('-'):
        objs.append(a)
    else:
        keep.append(a)
    i += 1

base = os.path.basename(out)
if base in os.environ.get('PCC_HOSTPROGS', 'lcgen').split():
    hcc = shlex.split(os.environ.get('PCC_HOSTCC', 'gcc'))
    os.execvp(hcc[0], hcc + args)
if not base.endswith('.exe') or re.fullmatch(r'pkg\d+\.exe', base) or not (srcs or objs):
    os.execvp(real[0], real + args)

# the probe itself, for the target
link = []
i = 0
while i < len(args):
    if args[i] == '-o':
        i += 2; continue
    if args[i].startswith('-o') and len(args[i]) > 2:
        i += 1; continue
    link.append(args[i]); i += 1
r = subprocess.run(real + link + ['-o', out + '.m68k'])
if r.returncode != 0:
    sys.exit(r.returncode)

h = hashlib.sha256()
pre = []


def pp(s, tag):
    p = subprocess.run(real + keep + ['-E', '-P', s], capture_output=True)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode('latin-1'))
        sys.exit('pcc: cannot preprocess %s for its key' % s)
    h.update(tag + b'\0' + p.stdout + b'\0')
    pre.append(p.stdout)


for s in srcs:
    pp(s, b'src')
for l in libs:
    h.update(b'lib\0' + l.encode() + b'\0')
for o in objs:
    if o.endswith('.o') and os.path.exists(o[:-2] + '.c'):
        # an object with its source beside it (INIT's compiler probe): the source
        pp(o[:-2] + '.c', b'objsrc')
    elif o.endswith('.o'):
        with open(o, 'rb') as f:
            h.update(b'obj\0' + f.read() + b'\0')
    else:
        # a library by its name, as -l words: an archive's bytes hold the
        # times its members were made
        h.update(b'lib\0' + os.path.basename(o).encode() + b'\0')
key = h.hexdigest()
# PCC_KEEP_I=DIR: the preprocessed text the key was made from, as DIR/KEY.i
if os.environ.get('PCC_KEEP_I'):
    with open('%s/%s.i' % (os.environ['PCC_KEEP_I'], key), 'wb') as f:
        f.write(b'\n'.join(pre))

# for the answers file: the probe as a person reads it (its first source as
# written) and where the build asked it
os.makedirs(store + '/src', exist_ok=True)
src = b''
first = srcs + [o[:-2] + '.c' for o in objs if o.endswith('.o') and os.path.exists(o[:-2] + '.c')]
if first:
    try:
        with open(first[0], 'rb') as f:
            src = f.read()
    except OSError:
        pass
cwd = os.getcwd()
where = cwd.rsplit('/src/', 1)[1] if '/src/' in cwd else os.path.basename(cwd)
# the tree's own path (iffe's "generated from" comments) as $PACKAGEROOT
if '/arch/' in cwd:
    src = src.replace(cwd.rsplit('/arch/', 1)[0].encode(), b'$PACKAGEROOT')
with open('%s/src/%s' % (store, key), 'wb') as f:
    f.write(src)
with open('%s/src/%s.name' % (store, key), 'w') as f:
    f.write('%s %s\n' % (where, re.sub(r'\d+', '', base)))

with open(out, 'w') as f:
    f.write('#!/bin/sh\nexec python3 -I %s/prun.py %s "$0.m68k" "$@"\n' % (here, key))
os.chmod(out, 0o755)
