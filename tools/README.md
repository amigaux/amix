# tools

Host-side developer tools: programs that run on the development machine, not
on the Amiga. For example, talking to a running box (run a command, sync
files), the privacy check every push passes, and `dmamask`.

Tools that run on the box itself are ordinary packages under `userland/`.

## privacy-check

`privacy-check` is the gate between a landing and the public repository: it
checks commits (`--range A..B`, `--all REF`, or `--pre-push` fed by git's
pre-push hook) or a single tree (`--tree REF`) and refuses five classes of
material: private network addresses, station files of the maintainers'
tooling, secrets such as private keys and access tokens, disk and ROM images,
oversized blobs and the system files listed in `system/MANIFEST.sha256`, and
AI attribution in our own commit messages. Contributors' commits are kept as
written, so the station-file and attribution classes apply only to our
commits. It prints one line per hit and exits 0 when clean, 1 on hits and 2 on
any error. A commit is judged on what it adds: the address and secret classes
read only the lines it adds relative to its first parent (all of them for a
root commit or a project moved in by a subtree merge), so a change to a file
does not inherit what earlier contributors wrote there, and a push skips
commits that any remote-tracking ref already has (`--exclude-remotes` does the
same for `--range` and `--all`). Public exemptions live in `privacy-allow.txt`, each with its
reason. A maintainer can add local extras that never enter this repository
through the `PRIVACY_PATTERNS` and `PRIVACY_BLOCKED` environment variables.
`test-privacy-check` builds a throwaway repository with one planted hit per
class beside clean controls, runs every mode, and passes only when every plant
is caught and every control passes. Both need only Python 3 and git.
