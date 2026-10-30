#!/usr/bin/env python3
# slow-server.py - HTTP server for the apkg inactivity-timeout tests.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# Two behaviours plain http.server cannot produce, both needed to tell
# the two possible readings of "timeout" apart:
#
#   /trickle/<name>   serve <docroot>/<name> correctly but SLOWLY - the
#                     body goes out in TRICKLE_CHUNK-byte pieces with
#                     TRICKLE_GAP seconds between them, so the transfer
#                     takes far longer than the client's configured
#                     timeout while never going quiet for that long.
#                     A whole-transfer cap kills this; an inactivity
#                     timer must not.
#
#   /stall/<name>     send correct headers and a first short piece of
#                     the body, then go silent forever.  An inactivity
#                     timer must kill this - promptly, and reporting
#                     the bytes it did receive.
#
# Any other path is served like http.server, so the same instance can
# hand out the catalog.
#
# usage: slow-server.py <port> <docroot> <chunk> <gap-seconds> <stall-prefix>

import functools
import http.server
import os
import socketserver
import sys
import time

TRICKLE_CHUNK = 4096
TRICKLE_GAP = 0.5
STALL_PREFIX = 256


class Handler(http.server.SimpleHTTPRequestHandler):
    def _payload(self, tag):
        rel = self.path[len(tag):].lstrip('/')
        path = os.path.join(self.directory, rel)
        if not os.path.isfile(path):
            self.send_error(404)
            return None
        with open(path, 'rb') as fp:
            return fp.read()

    def _headers(self, nbytes):
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(nbytes))
        self.end_headers()

    def do_GET(self):
        try:
            if self.path.startswith('/trickle/'):
                data = self._payload('/trickle/')
                if data is None:
                    return
                self._headers(len(data))
                off = 0
                while off < len(data):
                    self.wfile.write(data[off:off + TRICKLE_CHUNK])
                    self.wfile.flush()
                    off += TRICKLE_CHUNK
                    if off < len(data):
                        time.sleep(TRICKLE_GAP)
                return
            if self.path.startswith('/stall/'):
                data = self._payload('/stall/')
                if data is None:
                    return
                self._headers(len(data))
                self.wfile.write(data[:STALL_PREFIX])
                self.wfile.flush()
                time.sleep(120)        # never finish; the client must give up
                return
            super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            pass                        # the client timed out and hung up

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True               # a stalled handler must not block
    allow_reuse_address = True


def main():
    global TRICKLE_CHUNK, TRICKLE_GAP, STALL_PREFIX
    port = int(sys.argv[1])
    docroot = sys.argv[2]
    if len(sys.argv) > 3:
        TRICKLE_CHUNK = int(sys.argv[3])
    if len(sys.argv) > 4:
        TRICKLE_GAP = float(sys.argv[4])
    if len(sys.argv) > 5:
        STALL_PREFIX = int(sys.argv[5])
    handler = functools.partial(Handler, directory=docroot)
    Server(('127.0.0.1', port), handler).serve_forever()


if __name__ == '__main__':
    main()
