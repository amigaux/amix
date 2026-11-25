#!/usr/bin/env python3
# prund.py SOCKET ANSWERS -- records feature-probe answers on an Amix box
# (README.md, dtksh): the box is AMIX_HOST, root's password AMIX_PASS.  One
# telnet session and one FTP connection are held for the whole build (the box's
# inetd takes 40 logins a minute per service); FTP's data connections are
# active, as Amix's ftpd truncates passive ones.  Each probe is copied to
# /var/pr, run there with its arguments and standard input from /dev/null, and
# its standard output and error come back through od -b, so every byte survives
# the terminal, checked against the box's own byte counts.  Each answer is added
# to ANSWERS (probeans.py), with the probe's source and where the build asked it
# ($PCC_STORE/src); a new file starts with PCC_HEAD's lines.
# MIT licence, see LICENSE in userland/packages.
import ftplib, json, os, re, socket, sys, threading, time, traceback
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probeans

sock_path, answers = sys.argv[1], sys.argv[2]
store = os.environ['PCC_STORE']
BOX = '/var/pr'
HOST, PASS = os.environ['AMIX_HOST'], os.environ['AMIX_PASS']
ans = probeans.load(answers)
if not ans.order and not ans.head:
    ans.head = [l for l in os.environ.get('PCC_HEAD', '').split('\n') if l]
lock = threading.Lock()


class Box:
    """one telnet login as root, many commands, each ended by a marker with its
    exit status (the line the box echoes has the marker quoted, D''ONE)"""
    MAXLINE = 232       # the box's terminal line, less the marker

    def __init__(self):
        self.s = None

    def read(self, until, timeout):
        self.s.settimeout(1.0)
        buf, end = b'', time.time() + timeout
        while time.time() < end:
            try:
                d = self.s.recv(4096)
            except socket.timeout:
                continue
            if not d:
                break
            buf = (buf + self.iac(d)).replace(b'\r\x00', b'\r')
            m = until.search(buf)
            if m:
                return buf, m
        raise IOError('no answer from %s (%r)' % (HOST, buf[-200:]))

    def iac(self, d):
        """telnet negotiation answered with WONT and DONT, the rest kept"""
        out, rep, i = bytearray(), bytearray(), 0
        while i < len(d):
            if d[i] == 0xff and i + 1 < len(d):
                c = d[i + 1]
                if c in (0xfb, 0xfc, 0xfd, 0xfe) and i + 2 < len(d):
                    if c == 0xfd:
                        rep += bytes([0xff, 0xfc, d[i + 2]])
                    elif c == 0xfb:
                        rep += bytes([0xff, 0xfe, d[i + 2]])
                    i += 3
                    continue
                if c == 0xff:
                    out.append(0xff)
                i += 2
                continue
            out.append(d[i])
            i += 1
        if rep:
            self.s.sendall(bytes(rep))
        return bytes(out)

    def login(self):
        self.s = socket.create_connection((HOST, 23), timeout=20)
        self.read(re.compile(rb'ogin:'), 30)
        self.s.sendall(b'root\r\n')
        self.read(re.compile(rb'assword:'), 15)
        self.s.sendall(PASS.encode() + b'\r\n')
        self.read(re.compile(rb'[#$] '), 25)

    def run(self, cmd, timeout=180):
        if len(cmd) > self.MAXLINE:
            raise ValueError('command over %d bytes: %s' % (self.MAXLINE, cmd))
        for attempt in range(3):
            try:
                if self.s is None:
                    self.login()
                n = b'%04x' % int.from_bytes(os.urandom(2), 'big')
                self.s.sendall(cmd.encode() + b"; echo D''ONE_" + n + b'_$?\r\n')
                out, m = self.read(re.compile(rb"(?<!')DONE_" + n + rb'_(\d+)\s'), timeout)
                return out.decode('latin-1'), int(m.group(1))
            except (OSError, IOError):
                self.s = None
                time.sleep(2 * (attempt + 1))
        raise IOError('%s: no answer after 3 logins: %s' % (HOST, cmd))


box = Box()
ftp = None


def put(path):
    """the probe to BOX/p, over the held FTP connection (made again if it dropped)"""
    global ftp
    for attempt in range(2):
        try:
            if ftp is None:
                ftp = ftplib.FTP(HOST, timeout=60)
                ftp.login('root', PASS)
                ftp.set_pasv(False)
                try:
                    ftp.mkd(BOX)
                except ftplib.error_perm:
                    pass
            with open(path, 'rb') as fh:
                ftp.storbinary('STOR ' + BOX + '/p', fh)
            return
        except (OSError, EOFError, ftplib.Error):
            ftp = None
            if attempt:
                raise
odline = re.compile(r'^([0-7]{7})((?: [0-7]{3})*)\s*$')


def od_bytes(text):
    """od -b's output as the bytes it shows (a '*' line repeats the line before)"""
    rows, out, pending = [], bytearray(), False
    for ln in text.replace('\r', '').split('\n'):
        ln = ln.strip()
        if ln == '*':
            pending = True
            continue
        m = odline.match(ln)
        if not m:
            continue
        off = int(m.group(1), 8)
        if pending and rows:
            while len(out) < off:
                out += bytes(rows[-1])
            del out[off:]
            pending = False
        vals = [int(v, 8) for v in m.group(2).split()]
        if vals:
            rows.append(vals)
            out += bytes(vals)
        else:
            del out[off:]
    return bytes(out)


def q(a):
    return "'" + a.replace("'", "'\\''") + "'"


def run(req):
    put(req['prog'])
    box.run('cd %s && rm -f o e && chmod 755 p' % BOX)
    _, status = box.run('./p %s < /dev/null > o 2> e' % ' '.join(q(a) for a in req['args']))
    out = od_bytes(box.run('od -b o')[0])
    err = od_bytes(box.run('od -b e')[0])
    sizes = [int(n) for n in re.findall(r'^\s*(\d+)\s*$', box.run('wc -c < o; wc -c < e')[0].replace('\r', ''), re.M)]
    if sizes[-2:] != [len(out), len(err)]:
        raise IOError('od decode: %d/%d bytes, the box says %r' % (len(out), len(err), sizes))
    return status, out, err


def save():
    tmp = answers + '.new'
    with open(tmp, 'w', encoding='latin-1') as f:
        f.write(ans.dump())
    os.replace(tmp, answers)


def serve(c):
    buf = b''
    while not buf.endswith(b'\n'):
        d = c.recv(65536)
        if not d:
            return
        buf += d
    req = json.loads(buf.decode('latin-1'))
    with lock:
        try:
            r = ans.get(req['key'], req['args'])
            if r is None:
                r = run(req)
                sp = '%s/src/%s' % (store, req['key'])
                with open(sp, 'rb') as f:
                    src = f.read()
                with open(sp + '.name') as f:
                    name = f.read().strip()
                ans.add(req['key'], name, src, req['args'], *r)
                save()
                print('ok   %s %s status %d out %d err %d' % (req['key'][:12], name, r[0], len(r[1]), len(r[2])), flush=True)
            rep = {'status': r[0], 'out': r[1].decode('latin-1'), 'err': r[2].decode('latin-1')}
        except Exception as ex:
            traceback.print_exc()
            sys.stdout.flush()
            rep = {'error': repr(ex)}
    c.sendall((json.dumps(rep) + '\n').encode('latin-1'))
    c.close()


if os.path.exists(sock_path):
    os.unlink(sock_path)
srv = socket.socket(socket.AF_UNIX)
srv.bind(sock_path)
srv.listen(16)
print('prund: ready on %s, box %s' % (sock_path, HOST), flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
