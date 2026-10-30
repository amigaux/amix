#!/usr/bin/env python3
# ptyrun.py - run a command on a pseudo-terminal and answer its prompts.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# Usage: ptyrun.py <answers> <cmd> [args...]
#   <answers>  comma-separated replies, sent one per prompt ("" = Enter);
#              a prompt is apkg's conffile question, which ends in "[k] ".
# Everything the command prints is copied to stdout; the exit status is
# the command's.  Used by conffile-e2e.sh: apkg asks only when its stdin
# is a terminal.

import os
import pty
import sys
import time

PROMPT = b"[k] "


def main(argv):
    answers = argv[1].split(",") if argv[1] != "" else []
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[2], argv[2:])
    out = b""
    seen = 0
    deadline = time.time() + 120
    while time.time() < deadline:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
        sys.stdout.buffer.write(chunk)
        sys.stdout.flush()
        while out.count(PROMPT) > seen:
            reply = answers[seen] if seen < len(answers) else ""
            os.write(fd, reply.encode() + b"\n")
            seen += 1
    _, status = os.waitpid(pid, 0)
    return os.WEXITSTATUS(status) if os.WIFEXITED(status) else 255


if __name__ == "__main__":
    sys.exit(main(sys.argv))
