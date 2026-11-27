#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
"""ugate-serve.py -- serve a candidate repository read-only, for the user-path gate.

  ugate-serve.py --bind ADDR --port PORT --name NAME --tree DIR [--log FILE]
  ugate-serve.py --selftest

Serves DIR (a release tree: catalog, catalog.md5, pkgs/) at http://ADDR:PORT/NAME/ and nothing else. GET and HEAD
only; a path that leaves DIR is 404. Nothing is written inside DIR: the access log goes to --log (default stderr),
one line per request with the client and the Host header. Prints "ugate-serve: ready <url>" when it listens.
"""
import argparse
import functools
import http.client
import http.server
import os
import sys
import tempfile
import threading
import urllib.parse


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, name=None, tree=None, logf=None, **k):
        self.ug_name, self.ug_tree, self.ug_log = name, tree, logf
        super().__init__(*a, directory=tree, **k)

    def send_head(self):
        self.ug_refuse = False
        path = self.translate_path(self.path)
        if self.ug_refuse or not os.path.isfile(path):
            self.send_error(404)
            return None
        return super().send_head()

    def translate_path(self, path):
        p = urllib.parse.unquote(urllib.parse.urlsplit(path).path)
        pre = "/" + self.ug_name + "/"
        if not p.startswith(pre):
            self.ug_refuse = True
            return self.ug_tree
        rel = os.path.normpath(p[len(pre):]).lstrip("/")
        full = os.path.realpath(os.path.join(self.ug_tree, rel))
        root = os.path.realpath(self.ug_tree)
        if full != root and not full.startswith(root + os.sep):
            self.ug_refuse = True
            return self.ug_tree
        return full

    def do_POST(self):
        self.send_error(405)

    do_PUT = do_DELETE = do_POST

    def log_message(self, fmt, *args):
        host = (self.headers.get("Host") if getattr(self, "headers", None) else None) or "-"
        line = "%s - [%s] %s host=\"%s\"\n" % (self.client_address[0], self.log_date_time_string(), fmt % args, host)
        self.ug_log.write(line)
        self.ug_log.flush()


def server(bind, port, name, tree, logf):
    h = functools.partial(Handler, name=name, tree=tree, logf=logf)
    return http.server.ThreadingHTTPServer((bind, port), h)


def selftest():
    with tempfile.TemporaryDirectory() as d:
        t = os.path.join(d, "1.1")
        os.makedirs(os.path.join(t, "pkgs"))
        with open(os.path.join(t, "catalog"), "w") as f:
            f.write("#apkg-catalog 1\n")
        with open(os.path.join(d, "secret"), "w") as f:
            f.write("x\n")
        log = open(os.path.join(d, "log"), "w")
        s = server("127.0.0.1", 0, "1.1", t, log)
        threading.Thread(target=s.serve_forever, daemon=True).start()
        port = s.server_address[1]

        def get(p, method="GET"):
            c = http.client.HTTPConnection("127.0.0.1", port)
            c.request(method, p)
            r = c.getresponse()
            return r.status, r.read()
        ok = get("/1.1/catalog") == (200, b"#apkg-catalog 1\n")
        ok = ok and get("/1.1/../secret")[0] == 404 and get("/1.1/%2e%2e/secret")[0] == 404
        ok = ok and get("/secret")[0] == 404 and get("/1.1/pkgs/")[0] == 404
        ok = ok and get("/1.1/catalog", "POST")[0] in (405, 501)
        s.shutdown()
        log.close()
        ok = ok and sorted(os.listdir(t)) == ["catalog", "pkgs"]
        print("ugate-serve: selftest", "PASS" if ok else "FAIL")
        return 0 if ok else 1


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--bind")
    p.add_argument("--port", type=int)
    p.add_argument("--name")
    p.add_argument("--tree")
    p.add_argument("--log")
    a = p.parse_args()
    if a.selftest:
        return selftest()
    if not (a.bind and a.port and a.name and a.tree):
        p.error("--bind, --port, --name and --tree are required")
    if not os.path.isfile(os.path.join(a.tree, "catalog")):
        p.error("%s has no catalog" % a.tree)
    logf = open(a.log, "a") if a.log else sys.stderr
    s = server(a.bind, a.port, a.name, os.path.abspath(a.tree), logf)
    print("ugate-serve: ready http://%s:%d/%s" % (a.bind, a.port, a.name), flush=True)
    s.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
