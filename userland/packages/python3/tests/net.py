# net.py -- the socket and resource modules.  ON THE BOX, no outside network.
#
#     python3 tests/net.py
#
# A server thread and a client in the main thread on loopback: under Pth's
# cooperative threads this hangs if a blocking accept or recv stops the process,
# and SIGALRM's default action then ends it.  Also host names through /etc/hosts,
# HTTP through urllib, a timeout, accept with a timeout and after poll, a
# refused connection, and the resource limits.
# MIT, see LICENSE.amix in the package.

import http.server
import resource
import select
import signal
import socket
import threading
import urllib.request

signal.alarm(120)
fails = 0


def check(what, good, detail=""):
    global fails
    print("RES %s %s %s" % ("ok  " if good else "FAIL", what, detail), flush=True)
    if not good:
        fails += 1


# echo: a blocking accept and recv in a thread, the client in the main thread
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(5)
port = srv.getsockname()[1]


def echo():
    c, _ = srv.accept()
    while True:
        b = c.recv(4096)
        if not b:
            break
        c.sendall(b)
    c.close()


t = threading.Thread(target=echo)
t.start()
cli = socket.create_connection(("127.0.0.1", port), timeout=30)
msg = bytes(range(256)) * 64
cli.sendall(msg)
got = b""
while len(got) < len(msg):
    b = cli.recv(4096)
    if not b:           # the peer closed, or a stray empty read
        break
    got += b
cli.close()
t.join()
srv.close()
check("loopback echo through a thread", got == msg, "%d bytes" % len(got))

# names: localhost is in the stock /etc/hosts; the name the box calls itself too
check("gethostbyname localhost", socket.gethostbyname("localhost") == "127.0.0.1")
ai = socket.getaddrinfo("localhost", 80, socket.AF_INET, socket.SOCK_STREAM)
check("getaddrinfo localhost", ai[0][4] == ("127.0.0.1", 80), str(ai[0][4]))
check("inet_aton", socket.inet_aton("192.0.2.3") == b"\xc0\x00\x02\x03")
check("inet_ntoa", socket.inet_ntoa(b"\xc0\x00\x02\x03") == "192.0.2.3")
check("getservbyname", socket.getservbyname("telnet", "tcp") == 23)

# a timeout on a socket nobody writes to
a = socket.socket()
a.bind(("127.0.0.1", 0))
a.listen(1)
b = socket.create_connection(a.getsockname(), timeout=30)
b.settimeout(0.3)
try:
    b.recv(1)
    check("recv timeout", False, "no timeout")
except TimeoutError:
    check("recv timeout", True)
b.close()
a.close()


# accept on a listener with a timeout, and after select.poll on it (each gave
# EINVAL before Pth 2.0.7-3: Pth's poll peeked at the listener)
def accept_after(what, prepare):
    a = socket.socket()
    a.bind(("127.0.0.1", 0))
    a.listen(1)
    b = socket.create_connection(a.getsockname(), timeout=30)
    try:
        prepare(a)
        c, _ = a.accept()
        c.close()
        check("accept " + what, True)
    except OSError as e:
        check("accept " + what, False, repr(e))
    b.close()
    a.close()


def polled(a):
    p = select.poll()
    p.register(a, select.POLLIN)
    p.poll(5000)


accept_after("with a timeout", lambda a: a.settimeout(5))
accept_after("after poll", polled)

# a refused connection: the port of a socket bound but not listening
a = socket.socket()
a.bind(("127.0.0.1", 0))
try:
    socket.create_connection(a.getsockname(), timeout=30).close()
    check("refused connect", False, "connected")
except ConnectionRefusedError:
    check("refused connect", True)
except OSError as e:
    check("refused connect", False, repr(e))
a.close()


# a pair of connected sockets, AF_UNIX, the only family Amix's socketpair has
x, y = socket.socketpair()
x.sendall(b"pair")
check("socketpair", y.recv(16) == b"pair")
x.close()
y.close()


# HTTP: the standard library's server in a thread, urllib in the main thread
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"amix " * 1000
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


h = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
t = threading.Thread(target=h.serve_forever, kwargs={"poll_interval": 0.1})
t.start()
r = urllib.request.urlopen("http://localhost:%d/" % h.server_address[1], timeout=30).read()
h.shutdown()
t.join()
h.server_close()
check("http through urllib and http.server", len(r) == 5000, "%d bytes" % len(r))

# resource: what the shell's ulimit shows, and a change that holds
soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
check("getrlimit RLIMIT_NOFILE", soft > 0, "%d %d" % (soft, hard))
resource.setrlimit(resource.RLIMIT_NOFILE, (soft - 1, hard))
check("setrlimit holds", resource.getrlimit(resource.RLIMIT_NOFILE)[0] == soft - 1)
resource.setrlimit(resource.RLIMIT_NOFILE, (soft, hard))
check("getpagesize", resource.getpagesize() in (2048, 4096, 8192), str(resource.getpagesize()))

if fails:
    print("RES FAIL net: %d" % fails)
    raise SystemExit(1)
print("RES ok   net")
