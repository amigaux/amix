#!/usr/bin/env python3
# redirect-server.py - tiny HTTP server for the apkg 302-redirect test.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# Serves <docroot> like http.server, except that any path under /r/
# answers with a 302 pointing at the same file under /repo/ - which
# exercises apkg's follow-exactly-one-redirect path (plain
# python3 -m http.server cannot emit redirects).
#
# usage: redirect-server.py <port> <docroot>

import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/r/'):
            self.send_response(302)
            self.send_header('Location', '/repo/' + self.path[len('/r/'):])
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        super().do_GET()

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1])
    docroot = sys.argv[2]
    handler = functools.partial(Handler, directory=docroot)
    http.server.HTTPServer(('127.0.0.1', port), handler).serve_forever()


if __name__ == '__main__':
    main()
