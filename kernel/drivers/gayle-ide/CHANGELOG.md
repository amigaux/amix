# Changelog

## 2026-11-14 — two recipes, gayle and buddha; the fork pinned at release-1.1 (9ea1da9d, 0884fe5d)

gayle's recipe moves to pkg/gayle/ unchanged. pkg/buddha/ rolls buddha30/buddha46-1.1.0-4 (module 1.1.0-4: k30 8720ae0a, k46 da22bb8e; packages 6ceb7321, d212a715), root class, no depend, no kbootset= key; it needs kbootset 1.1.0.261113-44 or later and is tested in emulation only. The pin moves to the fork's release-1.1, 6003b68; the gayle objects and packages are unchanged.

## 2026-11-04 — packages 1.1.0-9 (408e557)

The copyright file's licence heading names the component; objects unchanged.

## 2026-11-02 — module 1.1.0-5, packages 1.1.0-8: the A1200 port too (0a2ca31)

The fork at amigaux/amix-gayle-ide 3b72994 drives the A1200's Gayle IDE port as well as the A4000's: the Kickstart ROM's card.resource resident picks the A1200, else the A4000; param board (0 auto, 1 A4000, 2 A1200, -1 never probe); no A600 row. The A1200 row has not run on hardware yet. Objects k30 3b7c03da, k46 33504a56. Packages gayle30 ae505479, gayle46 4cb26203.

## 2026-11-02 — module 1.1.0-4, packages 1.1.0-7: investigation symbols only with IDE_DIAG (b8bb38e)

The fork at amigaux/amix-gayle-ide d320430 builds its investigation-only symbols only with IDE_DIAG; no change in behaviour. Objects k30 afbf757f, k46 eb35c041. Packages gayle30 fff81c49, gayle46 6fbc5725.
