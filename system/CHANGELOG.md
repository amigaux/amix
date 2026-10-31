# Changelog

## 2026-10-31 — amix-system repinned to 7cba961, the stock /etc at 2.1p2a (284b8a8)

amix-system 7cba961 adds the stock /etc at 2.1p2a (P-36 D-N24). MANIFEST.sha256 gains its 206 etc/ files (3540 in
all) and SYMLINKS its 86 etc/ links (151); no existing line changed. check-amix-system also requires etc/ and
compares its links, so fetch-amix-system and container-build.sh check etc/ too. amix-system's own etc.md is not in
the manifest, like its README.md.
