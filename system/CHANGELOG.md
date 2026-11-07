# Changelog

## 2026-11-07 — amix-system debb2e1: the stock usr/sbin/in.ftpd (833ae59)

amix-system is pinned at debb2e1, which adds the stock usr/sbin/in.ftpd from the 2.1 net package (69760 bytes, sha256 29048aef…3940d). MANIFEST.sha256 gains its line, so a package can ship it patched with STOCK_PATCHED.

## 2026-10-31 — amix-system pinned at 761a82e: usr/amiga, usr/ucblib, the 2.1p2a syslogd (857c7cb)

amix-system.pin moves to 761a82e, which adds usr/amiga, usr/ucblib and the 2.1p2a usr/sbin/syslogd (565 files and
one link, all byte-equal to the stock 2.1 packages plus the 2.1p2a patch). MANIFEST.sha256 4105 lines (+565),
SYMLINKS 152 (+1); the README table gains the three rows.

## 2026-10-31 — amix-system repinned to 7cba961, the stock /etc at 2.1p2a (284b8a8)

amix-system 7cba961 adds the stock /etc at 2.1p2a. MANIFEST.sha256 gains its 206 etc/ files (3540 in
all) and SYMLINKS its 86 etc/ links (151); no existing line changed. check-amix-system also requires etc/ and
compares its links, so fetch-amix-system and container-build.sh check etc/ too. amix-system's own etc.md is not in
the manifest, like its README.md.
