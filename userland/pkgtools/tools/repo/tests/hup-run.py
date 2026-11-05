#!/usr/bin/env python3
"""hup-run.py ignore|default MARK CMD...: a login's end during CMD.

CMD runs as its own session and process group, SIGHUP ignored on entry (as
nohup leaves it) or at its default.  When the file MARK appears the whole group
gets one SIGHUP, as a hangup reaches a login's commands.  Exit: CMD's status,
128+signal if a signal ended it, 99 if MARK never came.
"""
import os
import signal
import sys
import time


def main():
    mode, mark, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
    pid = os.fork()
    if pid == 0:
        os.setsid()
        signal.signal(signal.SIGHUP,
                      signal.SIG_IGN if mode == "ignore" else signal.SIG_DFL)
        os.execvp(cmd[0], cmd)
    sent = False
    end = time.time() + 60
    while time.time() < end:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            if not sent:
                return 99
            break
        if not sent and os.path.exists(mark):
            os.killpg(pid, signal.SIGHUP)
            sent = True
        time.sleep(0.02)
    else:
        os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        return 99
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return os.WEXITSTATUS(status)


if __name__ == "__main__":
    sys.exit(main())
