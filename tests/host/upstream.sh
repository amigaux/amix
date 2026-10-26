#!/bin/sh
# upstream.sh -- core/upstream/ is kdedon's core as imported at b736c59
# (core/upstream.pin), unmodified: every file and nothing else, by the
# SHA-256 list core/upstream.sha256.  Our changes live in core/patches/.
set -e
(cd core/upstream && find . -type f | LC_ALL=C sort | xargs sha256sum) | cmp -s - core/upstream.sha256 ||
	{ echo "upstream: core/upstream/ differs from core/upstream.sha256: edit core/patches/, not the import" >&2; exit 1; }
echo "upstream: core/upstream/ is the import, file for file ($(wc -l < core/upstream.sha256) files)"
