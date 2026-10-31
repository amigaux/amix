# Changelog

Changes to the shared kernel/drivers README and the fork pins. Each source driver keeps its own CHANGELOG in its
directory.

## 2026-10-31 — the four forks pinned from amigaux (99a6d8a)

The forks other developers started are pinned from our amigaux forks (P-38 S3.1, D-d): cdfs (main fd6cad8, new),
gayle-ide (main 24ed009), paula (dlm-module 1b2736d) and z3660rtg (dlm-module 7dd6d67), each in
kernel/drivers/<name>/<name>.pin with a README. kernel/drivers/README.md says the forks are ours: we fix them there,
the build takes them by pin, and pull requests go upstream when we choose to.
