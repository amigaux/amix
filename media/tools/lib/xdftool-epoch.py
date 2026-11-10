#!/usr/bin/env python3
"""xdftool-epoch.py ARGS... -- amitools' xdftool with the clock pinned to SOURCE_DATE_EPOCH.

amitools stamps every FFS date (the volume's creation, disk and modification times, each file's and
directory's) from time.localtime(); with SOURCE_DATE_EPOCH set, time.time() and an argument-less
time.localtime()/gmtime() return that instant instead, so the same tree gives the same bytes. Without
SOURCE_DATE_EPOCH it is plain xdftool. Run it with the amitools environment's own python
(XDFTOOL_PY, default the interpreter on ~/.local/bin/xdftool's #! line).
"""
import os
import sys
import time

epoch = os.environ.get("SOURCE_DATE_EPOCH")
if epoch:
    e = int(epoch)
    _lt, _gt = time.localtime, time.gmtime
    time.time = lambda: float(e)
    time.localtime = lambda secs=None: _lt(e if secs is None else secs)
    time.gmtime = lambda secs=None: _gt(e if secs is None else secs)
from amitools.tools.xdftool import main  # noqa: E402
sys.argv[0] = "xdftool"
sys.exit(main())
