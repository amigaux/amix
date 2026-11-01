# Changelog

Changes to the shared kernel/drivers README and the fork pins. Each source driver keeps its own CHANGELOG in its
directory.

## 2026-11-01 — gayle and cdfs 1.1.0-6 on the 33ebadc kit (e53c106)

gayle-k30/-k46 1.1.0-6 (module 1.1.0-3) and cdfs-k30/-k46 1.1.0-6 (module 1.1.0-4) built with the gcc-2.7.2.3-33ebadc kit; only the cc= tag changes.

## 2026-10-31 — the four forks pinned from amigaux (99a6d8a)

The forks other developers started are pinned from our amigaux forks (P-38 S3.1, D-d): cdfs (main fd6cad8, new),
gayle-ide (main 24ed009), paula (dlm-module 1b2736d) and z3660rtg (dlm-module 7dd6d67), each in
kernel/drivers/<name>/<name>.pin with a README. kernel/drivers/README.md says the forks are ours: we fix them there,
the build takes them by pin, and pull requests go upstream when we choose to.
