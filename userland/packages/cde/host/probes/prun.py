#!/usr/bin/env python3
# prun.py KEY PROGRAM [ARG...] -- what a probe stub runs: the probe's answer, its
# standard output, standard error and exit status, given back as they were.
# PCC_MODE=replay (the build): from the answers file, PCC_ANSWERS; a run with no
#   answer stops the build (exit 125), named in $PCC_STORE/missing.  Each run
#   answered is noted in $PCC_STORE/used.
# PCC_MODE=record: a run with no answer goes to prund.py (PCC_SOCK), which runs
#   PROGRAM on an Amix box and adds the answer to the file.
# MIT licence, see LICENSE in userland/packages.
import json, os, socket, sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probeans

key, prog, args = sys.argv[1], sys.argv[2], sys.argv[3:]
mode = os.environ.get('PCC_MODE', 'replay')
store = os.environ['PCC_STORE']


def give(st, out, err):
    sys.stdout.buffer.write(out); sys.stdout.flush()
    sys.stderr.buffer.write(err); sys.stderr.flush()
    sys.exit(st)


e = probeans.load(os.environ['PCC_ANSWERS']).get(key, args)
if e is not None:
    with open(store + '/used', 'a') as f:
        f.write('%s %s\n' % (key, json.dumps(args)))
    give(*e)
if mode != 'record':
    sys.stderr.write('prun: no answer for probe %s %s (%s): record it on Amix (README.md, dtksh)\n'
                     % (key, json.dumps(args), os.path.basename(prog)))
    with open(store + '/missing', 'a') as f:
        f.write('%s %s\n' % (key, json.dumps(args)))
    sys.exit(125)

s = socket.socket(socket.AF_UNIX)
s.connect(os.environ['PCC_SOCK'])
s.sendall((json.dumps({'key': key, 'prog': os.path.abspath(prog), 'args': args}) + '\n').encode())
buf = b''
while not buf.endswith(b'\n'):
    d = s.recv(65536)
    if not d:
        break
    buf += d
r = json.loads(buf.decode('latin-1'))
if 'error' in r:
    sys.exit('prun: Amix did not answer probe %s: %s' % (key, r['error']))
with open(store + '/used', 'a') as f:
    f.write('%s %s\n' % (key, json.dumps(args)))
give(r['status'], r['out'].encode('latin-1'), r['err'].encode('latin-1'))
