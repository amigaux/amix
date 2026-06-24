#!/usr/bin/env python3
# amixrun.py -- run short shell commands on a networked Amix box over telnet.
#
# A self-contained telnet command runner with no external dependencies: `amix-build
# --run` uses it to drive any telnet-reachable Amix box.  Logs in as root, runs each
# argv as ONE short command, prints the captured output, exits.  Long-running work
# (the clean-gate) is NOT run synchronously here -- amix-build backgrounds it with
# nohup and polls a logfile with repeated short `tail` calls.
#
# Completion is detected with a marker emitted as  D''ONE_$?  so the echoed *input*
# line (which contains the quotes) never matches -- only the command's *output* does.
#
#   python3 amixrun.py 'uname -a' 'ls /usr/sys'
#
# Target + credentials via env (no defaults baked in -- you must set these):
#   AMIX_HOST=<box-ip>  AMIX_PORT=23  AMIX_USER=root  AMIX_PASS=<root-pw>
#   AMIX_CMD_TIMEOUT=60   (seconds to wait for one command's DONE_ marker)
import os, socket, sys, time

HOST = os.environ.get('AMIX_HOST')
PORT = int(os.environ.get('AMIX_PORT', '23'))
USER = (os.environ.get('AMIX_USER', 'root') + '\r\n').encode()
_PASS = os.environ.get('AMIX_PASS')
if not HOST or not _PASS:
    sys.exit('amixrun: set AMIX_HOST=<box ip> and AMIX_PASS=<root pw>')
PW   = (_PASS + '\r\n').encode()
CMD_TIMEOUT = int(os.environ.get('AMIX_CMD_TIMEOUT', '60'))


def strip_iac(sock, data):
    """Strip/answer telnet IAC negotiation; refuse all options (WONT/DONT)."""
    out = bytearray(); resp = bytearray(); i = 0; n = len(data)
    while i < n:
        b = data[i]
        if b == 0xff:
            if i + 1 >= n:
                break
            c = data[i + 1]
            if c in (0xfb, 0xfc, 0xfd, 0xfe) and i + 2 < n:
                opt = data[i + 2]
                if c == 0xfd:
                    resp += bytes([0xff, 0xfc, opt])    # DO   -> WONT
                elif c == 0xfb:
                    resp += bytes([0xff, 0xfe, opt])    # WILL -> DONT
                i += 3; continue
            elif c == 0xff:
                out.append(0xff); i += 2; continue
            else:
                i += 2; continue
        out.append(b); i += 1
    if resp:
        try:
            sock.sendall(bytes(resp))
        except OSError:
            pass
    return bytes(out)


def readuntil(sock, needles, timeout):
    sock.settimeout(1.0); buf = b''; end = time.time() + timeout
    while time.time() < end:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        buf += strip_iac(sock, chunk)
        if any(nd in buf for nd in needles):
            break
    return buf


def main(argv):
    s = socket.create_connection((HOST, PORT), timeout=20)
    readuntil(s, [b'ogin:'], 30); s.sendall(USER)
    readuntil(s, [b'assword:'], 15); s.sendall(PW)
    readuntil(s, [b'# ', b'$ '], 25)
    out = b''
    for c in argv:
        s.sendall(c.encode() + b"; echo D''ONE_$?\r\n")
        out += b'\n========== ' + c.encode() + b' ==========\n' + readuntil(s, [b'DONE_'], CMD_TIMEOUT)
    try:
        s.sendall(b'exit\r\n')
    except OSError:
        pass
    sys.stdout.buffer.write(out); sys.stdout.flush()


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.stderr.write("usage: amixrun.py '<cmd>' ['<cmd>' ...]   (env: AMIX_HOST/PORT/USER/PASS)\n")
        sys.exit(2)
    main(sys.argv[1:])
